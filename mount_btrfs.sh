#!/bin/bash

set -eo pipefail

BTRFS_TARGET_DIR="${BTRFS_TARGET_DIR:-$(
    dir=$(podman system info --format '{{.Store.GraphRoot}}' | sed 's|/storage$||')
    mkdir -p "$dir"
    echo "$dir"
)}"
# Options used to mount
BTRFS_MOUNT_OPTS=${BTRFS_MOUNT_OPTS:-"compress-force=zstd:2"}
# Location where the loopback file will be placed.
BTRFS_LOOPBACK_FILE=${BTRFS_LOOPBACK_FILE:-/mnt/btrfs_loopbacks/$(systemd-escape -p "$BTRFS_TARGET_DIR")}
# Percentage of the total space to use. Max: 1.0, Min: 0.0
BTRFS_LOOPBACK_FREE=${BTRFS_LOOPBACK_FREE:-"0.8"}

# Result of $(dirname "$_BTRFS_LOOPBACK_FILE")
btrfs_pdir="$(dirname "$BTRFS_LOOPBACK_FILE")"

# Install btrfs-progs
sudo apt-get install -y btrfs-progs

# use 60 GB to determine if Github allocated space for /mnt
# It should have 66GB avail out of 74GB
MIN_SPACE=$((60 * 1000 * 1000 * 1000))

AVAILABLE=$(findmnt /mnt --bytes --df --json | jq -r '.filesystems[0].avail')
AVAILABLE_HUMAN=$(findmnt /mnt --df --json | jq -r '.filesystems[0].avail')

if [[ "$AVAILABLE" -ge "$MIN_SPACE" ]]; then
  echo "Enough space available: $AVAILABLE_HUMAN"
else
  echo "/mnt doesn't have the desired capacity."
  echo "Available size: $AVAILABLE_HUMAN"
  echo "This usually happens when many runners are competing for resources"
fi

# Create loopback file
sudo mkdir -p "$btrfs_pdir" && sudo chown "$(id -u)":"$(id -g)" "$btrfs_pdir"
_final_size=$(
    findmnt --target "$btrfs_pdir" --bytes --df --json |
        jq -r --arg freeperc "$BTRFS_LOOPBACK_FREE" \
            '.filesystems[0].avail * ($freeperc | tonumber) | round'
)
truncate -s "$_final_size" "$BTRFS_LOOPBACK_FILE"
unset -v _final_size

# # Stop docker services
# sudo systemctl stop docker

# Format btrfs loopback
sudo mkfs.btrfs -f -r "$BTRFS_TARGET_DIR" "$BTRFS_LOOPBACK_FILE"

# Mount
sudo systemd-mount "$BTRFS_LOOPBACK_FILE" "$BTRFS_TARGET_DIR" \
    ${BTRFS_MOUNT_OPTS:+ --options="${BTRFS_MOUNT_OPTS}"}

# # Restart docker services
# sudo systemctl start docker
