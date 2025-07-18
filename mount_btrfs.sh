#!/bin/bash

set -eo pipefail

readarray -t _BTRFS_TARGET_DIRS <<<"${BTRFS_TARGET_DIR:-$(
    dir=$(podman system info --format '{{.Store.GraphRoot}}' | sed 's|/storage$||')
    mkdir -p "$dir"
    echo "$dir"
)}"

# Expand target directories
readarray -t BTRFS_TARGET_DIRS < <(realpath -m "${_BTRFS_TARGET_DIRS[@]}")
unset -v _BTRFS_TARGET_DIRS

# Options used to mount
BTRFS_MOUNT_OPTS=${BTRFS_MOUNT_OPTS:-"compress-force=zstd:2"}
# Location where the loopback file will be placed.
_BTRFS_LOOPBACK_FILE=${_BTRFS_LOOPBACK_FILE:-/mnt/btrfs_loopbacks/shared_loopback}
# Percentage of the total space to use. Max: 1.0, Min: 0.0
BTRFS_LOOPBACK_FREE=${BTRFS_LOOPBACK_FREE:-"0.8"}

# Result of $(dirname "$_BTRFS_LOOPBACK_FILE")
btrfs_pdir="$(dirname "$_BTRFS_LOOPBACK_FILE")"

# Install btrfs-progs
sudo apt-get install -y btrfs-progs

# Create loopback file
sudo mkdir -p "$btrfs_pdir" && sudo chown "$(id -u)":"$(id -g)" "$btrfs_pdir"
_final_size=$(
    findmnt --target "$btrfs_pdir" --bytes --df --json |
        jq -r --arg freeperc "$BTRFS_LOOPBACK_FREE" \
            '.filesystems[0].avail * ($freeperc | tonumber) | round'
)
truncate -s "$_final_size" "$_BTRFS_LOOPBACK_FILE"
unset -v _final_size

# Format btrfs loopback
sudo mkfs.btrfs -f "$_BTRFS_LOOPBACK_FILE"

# Mount the loopback to a temporary directory
_BTRFS_TEMP_MOUNT=$(mktemp -d)
sudo systemd-mount "$_BTRFS_LOOPBACK_FILE" "$_BTRFS_TEMP_MOUNT" \
    ${BTRFS_MOUNT_OPTS:+ --options="${BTRFS_MOUNT_OPTS}"}

for BTRFS_TARGET_DIR in "${BTRFS_TARGET_DIRS[@]}"; do
    # Create a subvolume for each target directory
    sudo btrfs subvolume create "$_BTRFS_TEMP_MOUNT/${BTRFS_TARGET_DIR//\//-}"

    # Bind mount the subvolume to the target directory
    sudo mkdir -p "$BTRFS_TARGET_DIR"
    sudo mount --bind "$_BTRFS_TEMP_MOUNT/${BTRFS_TARGET_DIR//\//-}" "$BTRFS_TARGET_DIR"
done

# Unmount the temporary directory
sudo umount "$_BTRFS_TEMP_MOUNT"
sudo rmdir "$_BTRFS_TEMP_MOUNT"
