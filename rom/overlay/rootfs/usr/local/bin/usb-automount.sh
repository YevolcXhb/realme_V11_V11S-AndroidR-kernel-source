#!/bin/sh
# Mount a removable USB block device (SD card in the USB-C dock) automatically.
#
# The kernel in this tree has no NTFS support (only vfat/exfat/msdos), so NTFS
# cards go through ntfs-3g (FUSE). Everything else mounts with the kernel
# driver. Mounts land in /media/<label> (or the UUID when there is no label).
set -u

DEV=${1:?device name required}
NODE="/dev/$DEV"
log() { echo "usb-automount[$DEV]: $*"; }

[ -b "$NODE" ] || { log "not a block device"; exit 0; }

# skip the disk itself when it has partitions
if [ -d "/sys/class/block/$DEV" ] && [ "$(ls "/sys/class/block/$DEV/" | grep -c "^$DEV[0-9]")" -gt 0 ]; then
    log "whole disk with partitions, skipping"
    exit 0
fi

if findmnt -S "$NODE" >/dev/null 2>&1; then
    log "already mounted"
    exit 0
fi

FSTYPE=$(blkid -s TYPE -o value "$NODE" 2>/dev/null)
[ -n "$FSTYPE" ] || { log "no filesystem detected"; exit 0; }

LABEL=$(blkid -s LABEL -o value "$NODE" 2>/dev/null)
UUID=$(blkid -s UUID -o value "$NODE" 2>/dev/null)
NAME=${LABEL:-$UUID}
[ -n "$NAME" ] || NAME=$DEV
# keep the path sane
NAME=$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9._-' '_')

MP="/media/$NAME"
mkdir -p "$MP"

OPTIONS="rw,nosuid,nodev,noatime"
case "$FSTYPE" in
    ntfs)
        log "mounting NTFS via ntfs-3g at $MP"
        ntfs-3g -o "$OPTIONS,uid=0,gid=0,umask=022,allow_other" "$NODE" "$MP" \
            && { log "mounted $MP ($FSTYPE)"; exit 0; }
        ;;
    vfat|exfat|ext4|ext3|ext2)
        log "mounting $FSTYPE at $MP"
        mount -t "$FSTYPE" -o "$OPTIONS" "$NODE" "$MP" \
            && { log "mounted $MP ($FSTYPE)"; exit 0; }
        ;;
    iso9660|udf)
        mount -t "$FSTYPE" -o ro,nosuid,nodev "$NODE" "$MP" \
            && { log "mounted $MP ($FSTYPE, read-only)"; exit 0; }
        ;;
    *)
        mount -o "$OPTIONS" "$NODE" "$MP" 2>/dev/null \
            && { log "mounted $MP ($FSTYPE)"; exit 0; }
        ;;
esac

log "mount failed"
exit 0
