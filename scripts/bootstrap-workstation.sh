#!/bin/bash
set -euo pipefail

# ============================================================
# AWS AU294 / RH294 Workstation Bootstrap
# ============================================================
# Run as ec2-user on workstation.lab.com.
#
# Required:
#   - Repository cloned to ~/ansible-projects/aws-rh294
#   - EC2 SSH private key at ~/.ssh/ansiblelab.pem
#   - scripts/lab-hosts.txt transferred by provisioning script
#   - Authentication to registry.redhat.io
#
# No credentials or private keys are stored in Git.
# ============================================================

PROJECT_DIR="${PROJECT_DIR:-$HOME/ansible-projects/aws-rh294}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ansiblelab.pem}"

DEV_CONTAINER="ansible-dev"
CONTAINER_STORAGE="ansible-dev-tools-container-storage"

DEVTOOLS_IMAGE="registry.redhat.io/ansible-automation-platform-25/ansible-dev-tools-rhel8:latest"
SUPPORTED_EE="registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8:latest"
CUSTOM_EE="localhost/rh294-ee:1.0"

EE_DIR="$PROJECT_DIR/execution-environment"
LAB_HOSTS_FILE="$PROJECT_DIR/scripts/lab-hosts.txt"
STAGED_HOSTS_FILE="$HOME/.rh294/lab-hosts.txt"

if [[ ! -f "$LAB_HOSTS_FILE" && -f "$STAGED_HOSTS_FILE" ]]; then
    cp "$STAGED_HOSTS_FILE" "$LAB_HOSTS_FILE"
fi
INVENTORY_FILE="$PROJECT_DIR/inventory"

echo "AWS AU294 / RH294 workstation bootstrap"
echo "========================================"
echo "Project: $PROJECT_DIR"
echo "SSH key: $SSH_KEY"
echo

# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------

echo "Checking prerequisites..."

[[ -f /etc/redhat-release ]] || {
    echo "ERROR: RHEL workstation required."
    exit 1
}

command -v podman >/dev/null 2>&1 || {
    echo "ERROR: Podman is not installed."
    exit 1
}

[[ -d "$PROJECT_DIR" ]] || {
    echo "ERROR: Project not found: $PROJECT_DIR"
    exit 1
}

[[ -f "$SSH_KEY" ]] || {
    echo "ERROR: SSH private key not found: $SSH_KEY"
    exit 1
}

[[ -f "$LAB_HOSTS_FILE" ]] || {
    echo "ERROR: Dynamic host mapping file not found:"
    echo "       $LAB_HOSTS_FILE"
    echo
    echo "The AWS provisioning script must transfer this file."
    exit 1
}

[[ -f "$EE_DIR/Containerfile" ]] || {
    echo "ERROR: Execution-environment Containerfile missing."
    exit 1
}

[[ -f "$EE_DIR/requirements.yml" ]] || {
    echo "ERROR: execution-environment/requirements.yml missing."
    exit 1
}

chmod 600 "$SSH_KEY"

echo "OS:      $(cat /etc/redhat-release)"
echo "Podman:  $(podman --version)"
echo "Project: OK"
echo "SSH key: OK"

# ------------------------------------------------------------
# Persistent rootless Podman user services
# ------------------------------------------------------------

echo
echo "Checking persistent user services..."

CURRENT_USER=$(id -un)

if [[ "$(loginctl show-user "$CURRENT_USER" -p Linger --value)" != "yes" ]]; then
    sudo loginctl enable-linger "$CURRENT_USER"
fi

[[ "$(loginctl show-user "$CURRENT_USER" -p Linger --value)" == "yes" ]] || {
    echo "ERROR: Unable to enable lingering for $CURRENT_USER."
    exit 1
}

echo "User linger: OK"

# ------------------------------------------------------------
# Dynamic /etc/hosts
# ------------------------------------------------------------

echo
echo "Configuring lab host mappings..."

TEMP_HOSTS=$(mktemp)

grep -Ev \
    '[[:space:]](workstation|servera|serverb|serverc|serverd)(\.lab\.com)?([[:space:]]|$)' \
    /etc/hosts > "$TEMP_HOSTS" || true

echo >> "$TEMP_HOSTS"
cat "$LAB_HOSTS_FILE" >> "$TEMP_HOSTS"

sudo cp "$TEMP_HOSTS" /etc/hosts
rm -f "$TEMP_HOSTS"

for HOST in workstation servera serverb serverc serverd; do
    getent hosts "$HOST.lab.com" >/dev/null || {
        echo "ERROR: Cannot resolve $HOST.lab.com"
        exit 1
    }
done

echo "Host mappings: OK"

# ------------------------------------------------------------
# Red Hat container images
# ------------------------------------------------------------

echo
echo "Checking Red Hat container images..."

if ! podman image exists "$DEVTOOLS_IMAGE"; then
    echo "Pulling Ansible Development Tools..."
    podman pull "$DEVTOOLS_IMAGE"
fi

if ! podman image exists "$SUPPORTED_EE"; then
    echo "Pulling supported execution environment..."
    podman pull "$SUPPORTED_EE"
fi

echo "Red Hat images: OK"

# ------------------------------------------------------------
# Build custom EE reproducibly
# ------------------------------------------------------------

echo
echo "Checking custom RH294 execution environment..."

if ! podman image exists "$CUSTOM_EE"; then

    echo "Building $CUSTOM_EE from Git source..."

    podman build \
        -t "$CUSTOM_EE" \
        -f "$EE_DIR/Containerfile" \
        "$EE_DIR"
fi

podman image exists "$CUSTOM_EE" || {
    echo "ERROR: Custom EE build failed."
    exit 1
}

echo "Custom EE: OK"

# ------------------------------------------------------------
# Persistent nested Podman storage
# ------------------------------------------------------------

if ! podman volume exists "$CONTAINER_STORAGE"; then
    podman volume create "$CONTAINER_STORAGE" >/dev/null
fi

# ------------------------------------------------------------
# Development container
# ------------------------------------------------------------

echo
echo "Checking Ansible development container..."

create_dev_container() {
    podman run -d \
        --name "$DEV_CONTAINER" \
        --hostname ansible-dev-container \
        --user root \
        --cap-add=SYS_ADMIN \
        --cap-add=SYS_RESOURCE \
        --device /dev/fuse \
        --security-opt seccomp=unconfined \
        --security-opt label=disable \
        --userns=host \
        --volume "$CONTAINER_STORAGE:/var/lib/containers" \
        --volume "$PROJECT_DIR:/workspaces/aws-rh294" \
        --volume "$HOME/.ssh:/root/.ssh:ro" \
        --volume /etc/hosts:/etc/hosts:ro \
        --volume /usr/share/zoneinfo:/usr/share/zoneinfo:ro \
        --workdir /workspaces/aws-rh294 \
        "$DEVTOOLS_IMAGE" \
        sleep infinity >/dev/null
}

if podman container exists "$DEV_CONTAINER"; then

    DEV_ARGS=$(podman inspect \
        --format '{{json .Args}}' \
        "$DEV_CONTAINER")

    if [[ "$DEV_ARGS" == *'"/bin/bash"'* ]]; then
        echo "Migrating legacy development container..."
        podman rm -f "$DEV_CONTAINER" >/dev/null
        create_dev_container
    else
        STATE=$(podman inspect \
            --format '{{.State.Status}}' \
            "$DEV_CONTAINER")

        if [[ "$STATE" != "running" ]]; then
            podman start "$DEV_CONTAINER" >/dev/null
        fi
    fi

else

    create_dev_container

fi

STATE=$(podman inspect \
    --format '{{.State.Status}}' \
    "$DEV_CONTAINER")

if [[ "$STATE" != "running" ]]; then
    echo "ERROR: Development container is not running."
    exit 1
fi

podman exec "$DEV_CONTAINER" \
    sh -c 'echo development-container-ready' >/dev/null

echo "Development container: OK"

# ------------------------------------------------------------
# Import custom EE into nested Podman
# ------------------------------------------------------------

echo
echo "Checking nested execution environment..."

if ! podman exec "$DEV_CONTAINER" \
    podman image exists "$CUSTOM_EE"; then

    echo "Transferring custom EE into development container..."

    podman save "$CUSTOM_EE" | \
        podman exec -i "$DEV_CONTAINER" podman load
fi

podman exec "$DEV_CONTAINER" \
    podman image exists "$CUSTOM_EE" || {
        echo "ERROR: Custom EE unavailable inside development container."
        exit 1
    }

echo "Nested custom EE: OK"

# ------------------------------------------------------------
# Inventory
# ------------------------------------------------------------

echo
echo "Validating Ansible inventory..."

[[ -f "$INVENTORY_FILE" ]] || {
    echo "ERROR: Inventory missing: $INVENTORY_FILE"
    exit 1
}

for HOST in \
    servera.lab.com \
    serverb.lab.com \
    serverc.lab.com \
    serverd.lab.com
do
    grep -Fxq "$HOST" "$INVENTORY_FILE" || {
        echo "ERROR: $HOST missing from inventory."
        exit 1
    }
done

echo "Inventory: OK"

# ------------------------------------------------------------
# SSH connectivity
# ------------------------------------------------------------

echo
echo "Testing SSH connectivity..."

for HOST in servera serverb serverc serverd; do

    ssh \
        -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        "ec2-user@$HOST" \
        true || {
            echo "ERROR: SSH failed: $HOST"
            exit 1
        }

    echo "  $HOST: OK"
done

# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

echo
echo "========================================"
echo "WORKSTATION BOOTSTRAP COMPLETE"
echo "========================================"
echo
echo "Enter the development container with:"
echo
echo "  podman exec -it ansible-dev bash"
echo
