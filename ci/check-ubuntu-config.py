#!/usr/bin/env python3
"""Fail after olddefconfig if the native-Ubuntu requirements were dropped.

This is the counterpart to check-server-config.py: it asserts the symbols a
headless Linux userspace can actually boot with are present in the *resolved*
configuration, not merely requested in the fragment.

Note what is deliberately NOT required: VT / VT_CONSOLE / FRAMEBUFFER_CONSOLE.
The first attempt at this profile enabled them, and the resulting kernel
reboot-looped before init ever ran - fbcon binds onto mediatek-drm's fbdev and
this handset has had its DSI panel physically removed. A headless server is
reached over the network, so a text console is not needed.
"""
import sys
from pathlib import Path

REQUIRED = [
    # /dev must exist before the first userspace process
    "CONFIG_DEVTMPFS", "CONFIG_DEVTMPFS_MOUNT",
    # cgroup controllers systemd refuses to start without
    "CONFIG_CGROUPS", "CONFIG_CGROUP_SCHED", "CONFIG_CGROUP_DEVICE",
    "CONFIG_CGROUP_PIDS", "CONFIG_CGROUP_FREEZER", "CONFIG_MEMCG",
    # systemd units / mounts expect these
    "CONFIG_AUTOFS4_FS", "CONFIG_FANOTIFY", "CONFIG_SECCOMP_FILTER",
    # the rootfs is ext4 because EROFS does not exist in 4.14
    "CONFIG_EXT4_FS",
    # wired networking: the dock's USB Ethernet is how the box is reached
    "CONFIG_USB_USBNET", "CONFIG_USB_NET_CDCETHER",
]

# Symbols that must NOT be enabled: they are the ones that broke boot.
FORBIDDEN = [
    "CONFIG_VT",
    "CONFIG_VT_CONSOLE",
    "CONFIG_FRAMEBUFFER_CONSOLE",
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
        got = actual.get(sym[7:])
        if got != "y":
            failures.append(f"{sym}: wanted y, got {got or 'missing'}")
    for sym in FORBIDDEN:
        if actual.get(sym[7:]) == "y":
            failures.append(f"{sym}: must stay off (breaks boot on this panel-less device)")
    if failures:
        raise SystemExit("Ubuntu configuration validation failed:\n" + "\n".join(failures))
    print(f"Ubuntu configuration validated: {len(REQUIRED)} required, {len(FORBIDDEN)} must-off.")


if __name__ == "__main__":
    main()
