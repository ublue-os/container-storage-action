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
_BTRFS_LOOPBACK_FILE=${_BTRFS_LOOPBACK_FILE:-/mnt/btrfs_loopbacks/$(systemd-escape -p "$BTRFS_TARGET_DIR")}
# Percentage of the total space to use. Max: 1.0, Min: 0.0
BTRFS_LOOPBACK_FREE=${_BTRFS_LOOPBACK_FREE:-"0.8"}

# Result of $(dirname "$_BTRFS_LOOPBACK_FILE")
btrfs_pdir="$(dirname "$_BTRFS_LOOPBACK_FILE")"

# Install btrfs-progs
sudo apt-get install -y btrfs-progs

# use 60 GB to determine if Github mounted /mnt already
# It should have 66GB avail out of 74GB
MIN_SPACE=$((60 * 1000 * 1000 * 1000))
MAX_RETRIES=3

for ATTEMPT in $(seq 1 "$MAX_RETRIES"); do
  AVAILABLE=$(findmnt /mnt --bytes --df --json | jq -r '.filesystems[0].avail')
  AVAILABLE_HUMAN=$(findmnt /mnt --df --json | jq -r '.filesystems[0].avail')

  if [[ "$AVAILABLE" -ge "$MIN_SPACE" ]]; then
    echo "Enough space available: $AVAILABLE_HUMAN"
    break  # Exit the loop if enough space is available
  else
    echo "Not enough space, it seems like the runner has not mounted /mnt yet "
    echo "Available size: $AVAILABLE_HUMAN. Waiting 5 seconds..."
    sleep 5

    if (( ATTEMPT == MAX_RETRIES )); then
      echo "Max retries reached. Exiting."
      exit 1
    fi
  fi
done

# Create loopback file
sudo mkdir -p "$btrfs_pdir" && sudo chown "$(id -u)":"$(id -g)" "$btrfs_pdir"
_final_size=$(
    findmnt --target "$btrfs_pdir" --bytes --df --json |
        jq -r --arg freeperc "$BTRFS_LOOPBACK_FREE" \
            '.filesystems[0].avail * ($freeperc | tonumber) | round'
)
truncate -s "$_final_size" "$_BTRFS_LOOPBACK_FILE"
unset -v _final_size

# # Stop docker services
# sudo systemctl stop docker

# Format btrfs loopback
sudo mkfs.btrfs -f -r "$BTRFS_TARGET_DIR" "$_BTRFS_LOOPBACK_FILE"

# Mount
sudo systemd-mount "$_BTRFS_LOOPBACK_FILE" "$BTRFS_TARGET_DIR" \
    ${BTRFS_MOUNT_OPTS:+ --options="${BTRFS_MOUNT_OPTS}"}

# # Restart docker services
# sudo systemctl start docker
