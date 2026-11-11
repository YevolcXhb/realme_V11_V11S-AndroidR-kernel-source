#!/bin/sh
# Bring up the vendor MediaTek connectivity stack to the point where it is ready
# for a power-on, without actually powering the chip (the current last mile -
# the BTIF/MCU handshake - is not working yet, and a failed power-on leaves an RX
# thread stuck long enough for hang_detect to reboot the device).
#
# Steps 1-3 are verified working on this device:
#   1. load the three rebuilt modules (CRCs match this kernel by construction)
#   2. tell wmt_detect the SoC chip id, which also sets the chip type to SOC and
#      runs the common driver init (this is what creates the wmt_lib queues)
#   3. configure the STP transport over BTIF so the HIF info is registered
set -u

MODDIR=/lib/modules/4.14.186+/extra
WMTWIFI_DEV=/dev/wmtWifi
WMTRDETECT_DEV=/dev/wmtdetect
STPWMT_DEV=/dev/stpwmt

ensure_node() {
    path="$1"; major="$2"; name="$3"
    if [ ! -c "$path" ]; then
        rm -f "$path" 2>/dev/null
        mknod "$path" c "$major" 0 2>/dev/null && chmod 600 "$path" \
            && echo "created $name node ($major,0)"
    fi
}

echo "mtkwifi: loading modules"
for m in wmt_drv wmt_chrdev_wifi wlan_6833_axi; do
    grep -q "^$m " /proc/modules && continue
    insmod "$MODDIR/$m.ko" || echo "mtkwifi: insmod $m failed"
done

# char device nodes: devtmpfs normally creates them, but /dev can be a tmpfs
# overlay and a plain file may already sit at these paths from earlier sessions
ensure_node "$WMTRDETECT_DEV" 154 wmtdetect
ensure_node "$WMTWIFI_DEV" 487 wmtWifi
ensure_node "$STPWMT_DEV" 190 stpwmt

# 2. chip id + common driver init (creates wmtd/wmtd_worker threads)
if [ -x /usr/local/bin/wmt-init ]; then
    /usr/local/bin/wmt-init 0x6833 || echo "mtkwifi: wmt-init failed"
fi

# 3. STP transport = BTIF on this SoC, FM = COMM
if [ -x /usr/local/bin/wmt-setstp ]; then
    /usr/local/bin/wmt-setstp 0x23 || echo "mtkwifi: wmt-setstp failed"
fi

echo "mtkwifi: stack ready (chip not powered)"
exit 0
