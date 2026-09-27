#!/bin/bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/ansiblelab1.pem"

declare -A EXPECTED_DISKS=(
    [servera]=1
    [serverb]=1
    [serverc]=1
    [serverd]=2
)

echo "AWS RH294 practice disk verification"
echo "===================================="

for HOST in servera serverb serverc serverd; do

    echo
    echo "===== $HOST ====="

    DISK_COUNT=$(ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        "ec2-user@$HOST" \
        "lsblk -dn -o TYPE | grep -c '^disk$'")

    EXPECTED_TOTAL=${EXPECTED_DISKS[$HOST]}

    # Every server has one root disk.
    EXPECTED_TOTAL=$((EXPECTED_TOTAL + 1))

    if [[ "$DISK_COUNT" -ne "$EXPECTED_TOTAL" ]]; then
        echo "ERROR: $HOST has $DISK_COUNT disks; expected $EXPECTED_TOTAL."
        exit 1
    fi

    echo "Disk count: $DISK_COUNT"
    echo "Expected:   $EXPECTED_TOTAL"
    echo "Status:     OK"

    ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        "ec2-user@$HOST" \
        'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS'
done

echo
echo "Practice disk verification passed."
