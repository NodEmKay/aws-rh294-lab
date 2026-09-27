#!/bin/bash
set -euo pipefail

# AWS RH294 workstation bootstrap
#
# Run on workstation.lab.com as ec2-user.
# This script prepares the Ansible development environment.
#
# Secrets are NOT stored here:
# - EC2 private SSH key
# - Red Hat registry credentials
# - AWS credentials

PROJECT_DIR="$HOME/ansible-projects/aws-rh294"
DEV_CONTAINER="ansible-dev"

DEVTOOLS_IMAGE="registry.redhat.io/ansible-automation-platform-25/ansible-dev-tools-rhel8:latest"
SUPPORTED_EE="registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8:latest"
CUSTOM_EE="localhost/rh294-ee:1.0"

SSH_KEY="$HOME/.ssh/ansiblelab1.pem"
CONTAINER_STORAGE="ansible-dev-tools-container-storage"

echo "AWS RH294 workstation bootstrap"
echo "================================"
echo "Project:       $PROJECT_DIR"
echo "Dev container: $DEV_CONTAINER"
echo "Custom EE:     $CUSTOM_EE"

echo
echo "Checking prerequisites..."

# Confirm RHEL
if [[ ! -f /etc/redhat-release ]]; then
    echo "ERROR: This bootstrap expects a RHEL workstation."
    exit 1
fi

echo "OS: $(cat /etc/redhat-release)"

# Check Podman
if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: Podman is not installed."
    exit 1
fi

echo "Podman: $(podman --version)"

# Check EC2 SSH private key
if [[ ! -f "$SSH_KEY" ]]; then
    echo "ERROR: SSH key not found: $SSH_KEY"
    echo "Copy ansiblelab1.pem securely to ~/.ssh before continuing."
    exit 1
fi

# Enforce private-key permissions
chmod 600 "$SSH_KEY"

echo "SSH key: present"

# Check project directory
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "ERROR: Project directory not found: $PROJECT_DIR"
    echo "Clone the GitHub repository first."
    exit 1
fi

echo "Project directory: present"

echo
echo "Prerequisite checks passed."

echo
echo "Checking container images..."

# Dev Tools image
if podman image exists "$DEVTOOLS_IMAGE"; then
    echo "Dev Tools image: present"
else
    echo "Dev Tools image: missing"
    echo "Authenticate first with:"
    echo "  podman login registry.redhat.io"
    echo "Then rerun this bootstrap."
    exit 1
fi

# Supported EE base image
if podman image exists "$SUPPORTED_EE"; then
    echo "Supported EE: present"
else
    echo "Supported EE: missing"
    echo "Authenticate first with:"
    echo "  podman login registry.redhat.io"
    echo "Then pull:"
    echo "  podman pull $SUPPORTED_EE"
    echo "Then rerun this bootstrap."
    exit 1
fi

# Custom RH294 execution environment
if podman image exists "$CUSTOM_EE"; then
    echo "Custom RH294 EE: present"
else
    echo "Custom RH294 EE: missing"
    echo "Restore the saved rh294-ee-1.0.tar or rebuild it before continuing."
    exit 1
fi

echo
echo "Container image checks passed."

echo
echo "Checking Ansible development container..."

# Create persistent nested Podman storage if needed
if ! podman volume exists "$CONTAINER_STORAGE"; then
    echo "Creating persistent container storage..."
    podman volume create "$CONTAINER_STORAGE" >/dev/null
fi

# Check whether ansible-dev already exists
if podman container exists "$DEV_CONTAINER"; then

    echo "Development container already exists."

    CONTAINER_STATE=$(podman inspect \
        --format '{{.State.Status}}' \
        "$DEV_CONTAINER")

    if [[ "$CONTAINER_STATE" != "running" ]]; then
        echo "Starting development container..."
        podman start "$DEV_CONTAINER" >/dev/null
    fi

else
    echo "Creating development container..."

    podman run -dit \
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
        /bin/bash
fi

echo
echo "Development container status:"
podman ps \
    --filter "name=$DEV_CONTAINER" \
    --format '  {{.Names}}  {{.Status}}'

echo
echo "Development container ready."

echo
echo "Checking custom EE inside development container..."

if podman exec "$DEV_CONTAINER" \
    podman image exists "$CUSTOM_EE"; then

    echo "Nested custom RH294 EE: present"

else
    echo "ERROR: Custom RH294 EE is missing from nested Podman."
    echo
    echo "Restore the saved image to the host first:"
    echo "  podman load -i ~/rh294-ee-1.0.tar"
    echo
    echo "Then load it into the development container:"
    echo "  podman exec -i $DEV_CONTAINER podman load < ~/rh294-ee-1.0.tar"
    exit 1
fi

echo
echo "Nested execution environment ready."

# ------------------------------------------------------------
# Configure dynamic lab host mappings
# ------------------------------------------------------------

LAB_HOSTS_FILE="$PROJECT_DIR/scripts/lab-hosts.txt"

echo
echo "Checking dynamic lab host mappings..."

if [[ -f "$LAB_HOSTS_FILE" ]]; then

    echo "Lab host mapping file found."

    TEMP_HOSTS=$(mktemp)

    # Preserve all non-RH294 entries.
    grep -Ev '[[:space:]](workstation|servera|serverb|serverc|serverd)(\.lab\.com)?([[:space:]]|$)' \
        /etc/hosts > "$TEMP_HOSTS"

    # Append the current AWS lab mappings.
    echo >> "$TEMP_HOSTS"
    cat "$LAB_HOSTS_FILE" >> "$TEMP_HOSTS"

    sudo cp "$TEMP_HOSTS" /etc/hosts
    rm -f "$TEMP_HOSTS"

    echo "Lab host mappings updated."

else
    echo "No generated lab-hosts.txt found."
    echo "Keeping existing /etc/hosts mappings."
fi
