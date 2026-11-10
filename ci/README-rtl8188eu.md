# RTL8188EU (0bda:8179) on realme V11 / RMX3122

Kernel: 4.14.186+ built by GitHub Actions, boot.img reflashed 2026-11-11.

## Why a module, not built-in

drivers/staging/rtl8188eu/Kconfig declares "depends on m", so CONFIG_R8188EU
can only ever be a module. That is also what keeps the vendor ABI intact: a
module carries its own CRCs and adds none to vmlinux, so the nine vendor
modules under /vendor/lib/modules keep loading.

rtl8xxxu (drivers/net/wireless/realtek) cannot drive this adapter at all: its
dev_table[] has no 0x8179 entry and there is no rtl8188e_fops.

Re-resolving the whole Kconfig with the OEM defconfig moves exactly two
symbols (R8188EU n->m, 88EU_AP_MODE new y); the other 4603 are byte-identical.

## Files on device

    /data/adb/service.d/r8188eu.sh        autoload on boot (Magisk)
    /data/local/tmp/r8188eu/r8188eu.ko    driver module
    /data/local/tmp/r8188eu/wextscan      WEXT scan probe (repo tools/wext)
    /data/local/tmp/r8188eu/wifi-up.sh    bring up + scan in one shot
    /data/local/tmp/r8188eu/rtlwifi/rtl8188eufw.bin
                                          firmware, copied at boot to
                                          /data/misc/firmware/active/rtlwifi

## Use

    su -c sh /data/local/tmp/r8188eu/wifi-up.sh

Expected: wlan2 up with MAC 3c:33:00:b3:5f:b3, then a list of APs.

## Userspace caveat

r8188eu is a pure WEXT driver: it registers netdev->wireless_handlers and only
includes <net/cfg80211.h> from mon.c. The wpa_supplicant shipped on this ROM
lists only the nl80211 backend under -h, so -Dwext cannot work with it. To
associate, a wpa_supplicant built with CONFIG_DRIVER_WEXT (or iwconfig) is
required. Scanning already works today without it, via wextscan.

## Rolling back

The original boot image is at:

    /data/local/tmp/r8188eu_work/orig_boot.img.bak

Restore with:

    su -c dd if=/data/local/tmp/r8188eu_work/orig_boot.img.bak of=/dev/block/by-name/boot bs=4096
