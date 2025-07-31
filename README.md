# Container-storage BTRFS loopback

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

**Author:** [Zeglius](https://github.com/Zeglius)

**Description:** Mount container-storage in a btrfs loopback for space restrained environments

## Inputs

### `target-dir`
*   **Description:** Path to the container-storage directory. Defaults to the user container-storage (~/.local/share/containers)
*   **Required:** No
*   **Default:** `""`
*   **Note:** Set to `/var/lib/containers` in case of using rootful podman, `/var/lib/docker` if using docker.

### `mount-opts`
*   **Description:** Mount options for the BTRFS loopback, separated by commas
*   **Required:** No
*   **Default:** `""`

### `loopback-free`
*   **Description:** Percentage of the total space to use for the loopback. Max: 1.0, Min: 0.0
*   **Required:** No
*   **Default:** `"0.8"`

## How much space is usually available with this

`/mnt` is a volume with 66G available with default settings (80% utilization) that gets you around 52GiB.

## Caveats

Github Runners seem to compete for resources on `/mnt` (space is not guaranteed!) and it could be anywhere in the range of 0 to 60GiB.
This action will fail if there is not at least 60GB of free space available on `/mnt`.


## Usage

To use this action, add the following to your workflow file:

```yaml
- name: Mount BTRFS loopback
  uses: ublue-os/container-storage-action@v1 # Replace v1 with the desired tag or commit hash
  with:
    target-dir: /var/lib/containers
    mount-opts: compress-force=zstd:2
    loopback-free: 0.5
```

## How it works

This action executes the `mount_btrfs.sh` script, which performs the following steps:

1.  **Determines Target Directory:** It first determines the `target-dir` for the container storage. If not provided, it defaults to the `podman` system info's graph root.
2.  **Installs `btrfs-progs`:** Ensures that the `btrfs-progs` package is installed on the system.
3.  **Creates Loopback File:** A loopback file is created based on the available free space in the directory where the loopback file will reside. The size is determined by the `loopback-free` input.
4.  **Formats Loopback File:** The created loopback file is then formatted as a BTRFS filesystem.
5.  **Mounts Loopback:** Finally, the BTRFS loopback file is mounted to the `target-dir` using `systemd-mount`, applying any specified `mount-opts`.

## License

This project is licensed under the Apache License, Version 2.0 - see the [LICENSE](LICENSE) file for details.
