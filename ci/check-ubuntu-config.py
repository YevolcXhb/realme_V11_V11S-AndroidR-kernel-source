#!/usr/bin/env python3
"""Fail after olddefconfig if the native-Ubuntu requirements were dropped.

This is the counterpart to check-server-config.py: it asserts the symbols a
normal Linux userspace (systemd, udev, a text console) needs are actually
present in the resolved configuration, not merely requested in the fragment.
"""
import sys
from pathlib import Path

REQUIRED = [
    # /dev must exist before the first userspace process
    "CONFIG_DEVTMPFS", "CONFIG_DEVTMPFS_MOUNT",
    # a usable text console on the DRM framebuffer
    "CONFIG_VT", "CONFIG_VT_CONSOLE", "CONFIG_FRAMEBUFFER_CONSOLE",
    # systemd refuses to start without these
    "CONFIG_CGROUPS", "CONFIG_CGROUP_SCHED", "CONFIG_CGROUP_DEVICE",
    "CONFIG_CGROUP_PIDS", "CONFIG_CGROUP_FREEZER", "CONFIG_MEMCG",
    "CONFIG_AUTOFS4_FS", "CONFIG_FANOTIFY", "CONFIG_SECCOMP_FILTER",
    # the rootfs is ext4 because EROFS does not exist in 4.14
    "CONFIG_EXT4_FS",
]


def parse(path):
    out = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line.startswith("CONFIG_") and "=" in line:
            k, v = line.split("=", 1)
            out[k[7:]] = v
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            out[line[9:-11]] = "n"
    return out


def main():
    actual = parse(sys.argv[1])
    failures = []
    for sym in REQUIRED:
        name = sym[7:]
        got = actual.get(name)
        if got != "y":
            failures.append(f"{sym}: wanted y, got {got or 'missing'}")
    if failures:
        raise SystemExit("Ubuntu configuration validation failed:\n" + "\n".join(failures))
    print(f"Ubuntu configuration validated: {len(REQUIRED)} requirements.")


if __name__ == "__main__":
    main()
