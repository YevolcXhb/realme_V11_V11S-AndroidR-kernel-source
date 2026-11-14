#!/bin/sh
# Bring up the vendor MediaTek connectivity stack and power the Wi-Fi chip on.
#
# Sequence mirrors what Android does with wmt_loader + WMT_SOC.cfg:
#   1. load the three rebuilt modules
#   2. SET_CHIP_ID + DO_MODULE_INIT on /dev/wmtdetect
#   3. SET_STP_MODE on /dev/stpwmt (BTIF transport on this SoC)
#   4. push the ROM patch table: MCU/WiFi/BT names + EMI offsets taken from the
#      patch headers in /lib/firmware (see docs/wifi-bringup.md)
#   5. power on by writing 1 to /dev/wmtWifi
#
# Chip selection matters: the gen4m driver must be built with MTK_COMBO_CHIP=SOC2_1X1
# for this SoC. SOC2_1X1 requests WIFI_RAM_CODE_soc2_2 and expects a 20-byte RX
# descriptor, which is what this firmware actually sends.
set -u

MODDIR=/lib/modules/4.14.186+/extra
WMTWIFI_DEV=/dev/wmtWifi
WMTRDETECT_DEV=/dev/wmtdetect
STPWMT_DEV=/dev/stpwmt
FW_DIR=/lib/firmware

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

ensure_node "$WMTRDETECT_DEV" 154 wmtdetect
ensure_node "$WMTWIFI_DEV" 487 wmtWifi
ensure_node "$STPWMT_DEV" 190 stpwmt

# already up (e.g. manual test earlier in the same boot)
if [ -e /sys/class/net/wlan0 ]; then
    echo "mtkwifi: wlan0 already exists, nothing to do"
    exit 0
fi

/usr/local/bin/wmt-init 0x6833 || echo "mtkwifi: wmt-init failed"
/usr/local/bin/wmt-setstp 0x23 || echo "mtkwifi: wmt-setstp failed"

# ROM patch metadata. Offsets are the EMI offsets encoded in each patch header:
#   MCU 0x000000, WiFi 0x2a0000, BT 0x170000
if [ -x /usr/local/bin/wmt-setpatch2 ]; then
    /usr/local/bin/wmt-setpatch2 4 soc2_2_ram_mcu_1_1_hdr.bin 0x0 || echo "mtkwifi: patch mcu failed"
    /usr/local/bin/wmt-setpatch2 3 soc2_2_ram_wifi_1_1_hdr.bin 0x2a0000 || echo "mtkwifi: patch wifi failed"
    /usr/local/bin/wmt-setpatch2 0 soc2_2_ram_bt_1_1_hdr.bin 0x170000 || echo "mtkwifi: patch bt failed"
fi

echo "mtkwifi: powering on"
printf '1' > "$WMTWIFI_DEV" 2>/dev/null || echo "mtkwifi: power on write failed"

i=0
while [ "$i" -lt 10 ]; do
    [ -e /sys/class/net/wlan0 ] && break
    i=$((i+1)); sleep 1
done

if [ -e /sys/class/net/wlan0 ]; then
    echo "mtkwifi: wlan0 is up"
    exit 0
fi
echo "mtkwifi: wlan0 did not appear"
exit 0
