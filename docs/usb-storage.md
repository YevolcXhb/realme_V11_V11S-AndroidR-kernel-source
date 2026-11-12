
## SD card / USB storage on the dock

The dock's card reader enumerates as `1-1.4 349c:0418 USB2.0 Device` with no
product string, and the card itself shows up as `/dev/sdd1`. Nothing mounted it:
this kernel has **no NTFS support** (`/proc/filesystems` lists vfat, msdos and
exfat only), so `mount -t ntfs` and `ntfs3` both fail with "unknown filesystem
type".

Fix: `ntfs-3g` (userspace, over FUSE - `/dev/fuse` and `fuse` are present) plus
an auto-mounter:

* `tools/device/usb-automount.sh` picks the filesystem, uses ntfs-3g for NTFS
  and the kernel drivers otherwise, and mounts under `/media/<label>`
  (or `/media/<UUID>` when the card has no label).
* `99-usb-automount.rules` starts `usb-automount@<dev>.service` when a USB block
  partition appears, so plugging the card in (or booting with it inserted)
  mounts it without a manual step.

Verified after a reboot: `/dev/sdd1 on /media/84320F19320F0FBA type fuseblk
(rw,...)`, 30 GB with 65 MB used, and a write test succeeded.
