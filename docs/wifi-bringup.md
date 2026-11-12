# MediaTek Wi-Fi bring-up on the realme V11 (RMX3122 / MT6833)

Status: **working**. Built-in Wi-Fi powers on at boot, associates with the
configured hotspot and gets a DHCP lease with no manual steps. Verified on the
device across repeated cold boots.

This file records what actually blocked the bring-up and the evidence for each
fix, so the next person does not repeat the dead ends.

## The stack

Three vendor modules, all rebuilt from the vendor kernel tree:

| module | source dir |
|---|---|
| `wmt_drv.ko` | `kernel_modules/connectivity/common` |
| `wmt_chrdev_wifi.ko` | `kernel_modules/connectivity/wlan/adaptor` |
| `wlan_6833_axi.ko` | `kernel_modules/connectivity/wlan/core/gen4m` |

There is no conninfra on this SoC, so the chip is brought up the old way: the
driver asks userspace to do the loader's job over STP.

## Blocker 1: chip family selected at build time

`MTK_COMBO_CHIP` decides which chip family gen4m is compiled for. It is not
derived from the kernel config, so the cross build has to set it explicitly, and
each value is wrong in a different way:

| value | RX descriptor | firmware it requests | result |
|---|---|---|---|
| `CONNAC` | 16 bytes | `WIFI_RAM_CODE_soc1_0` | RX events dropped, ECO read times out |
| `SOC2_2X2` | 20 bytes | `WIFI_RAM_CODE_soc2_0` | ECO passes, firmware not found |
| `SOC2_1X1` | 20 bytes | `WIFI_RAM_CODE_soc2_2` | works |

`SOC2_1X1` is correct because it is the only family that names the firmware the
vendor actually ships (`WIFI_RAM_CODE_soc2_2_1_1.bin`) and its 20-byte RX
descriptor matches what the firmware really sends.

Symptom with the wrong family - the driver silently drops the reply to the
register read used for ECO detection, then fails:

```
kalDevPortRead: Skip Rx packet, SDL0[36] > SwRfb max len[32]
wlanSetChipEcoInfo failed!
wlanAdapterStart: Fail reason: 4
```

20 (descriptor) + 8 (init event) + 8 (access-reg payload) = 36. With a 16-byte
descriptor the driver expects 32 and rejects the packet.

## Blocker 2: ROM patch table and EMI offsets

`mtk_wcn_soc_rom_patch_dwn()` asks userspace for the patch list over STP. On
Android that request is answered by `/vendor/bin/wmt_launcher`, so on a plain
Ubuntu userland nothing answers and power-on unwinds with:

```
mtk_wcn_soc_rom_patch_dwn: failed to get patch (type: 0, ret: -1)
```

`tools/device/wmt_setpatch.c` answers it by pre-populating the same table with
`WMT_IOCTL_SET_ROM_PATCH_INFO`. The EMI offset is encoded in the patch file's
own header (bytes 24..31), and the kernel derives

```
offset = address[0] | address[1] << 8 | address[2] << 16
```

with the loader zeroing `address[0]`. Reading the soc2_2 headers directly gives:

| patch | type | header bytes 24..31 | EMI offset |
|---|---:|---|---:|
| `soc2_2_ram_mcu_1_1_hdr.bin` | 4 | `11 00 00 f0 00 00 00 04` | `0x000000` |
| `soc2_2_ram_wifi_1_1_hdr.bin` | 3 | `11 00 2a f0 00 00 00 03` | `0x2a0000` |
| `soc2_2_ram_bt_1_1_hdr.bin` | 0 | `11 00 17 f0 00 00 00 00` | `0x170000` |

Guessing these offsets (they are not round numbers) makes the MCU firmware
execute garbage and dump an exception over STP instead of booting.

Only the `soc2_2` family matches this silicon: the driver reports
`CONSYS SOC_CONSYS.E1 (0x8a00/0x8a00)`, and the `soc3_0` patches carry
`0x8a10`.

## Blocker 3: firmware and config files

`request_firmware()` needs the vendor files in `/lib/firmware`:
`WIFI_RAM_CODE_soc2_2_1_1.bin`, `WMT_SOC.cfg`, `BT_FW.cfg`,
`fm_cust.cfg`, `wifi_*.cfg` and `txpowerctrl_*.cfg` (from the vendor
image's `/firmware`). The ROM patch binaries must be reachable too; they live
in `/vendor/firmware` on the installed system.

## Boot sequence

`tools/device/mtkwifi-init.sh` (oneshot, before `network-pre.target`):

1. load the three modules
2. create `/dev/wmtdetect`, `/dev/wmtWifi`, `/dev/stpwmt` if devtmpfs did not
3. `wmt-init 0x6833`: `SET_CHIP_ID` + `DO_MODULE_INIT`
4. `wmt-setstp 0x23`: `SET_STP_MODE` for BTIF transport
5. `wmt-setpatch2 4|3|0 <file> <offset>` for the three patches above
6. write `1` to `/dev/wmtWifi`

Then `wifi-connect@wlan0.service` (started by a udev rule when `wlan0`
appears) runs `wpa_supplicant` and DHCP.

## Verified result

```
mtkwifi-init.sh: SET_ROM_PATCH_INFO(type=4, name=soc2_2_ram_mcu_1_1_hdr.bin, offset=0x0) -> 0 ok
mtkwifi-init.sh: SET_ROM_PATCH_INFO(type=3, name=soc2_2_ram_wifi_1_1_hdr.bin, offset=0x2a0000) -> 0 ok
mtkwifi-init.sh: SET_ROM_PATCH_INFO(type=0, name=soc2_2_ram_bt_1_1_hdr.bin, offset=0x170000) -> 0 ok
mtkwifi-init.sh: mtkwifi: wlan0 is up

wlan0  UP  192.168.137.122/24
default via 192.168.137.1 dev wlan0
ssid=Slider  wpa_state=COMPLETED
http 204
```

## Notes

* `wlan1` also appears (the driver creates it for multi-STA/p2p).
* The chip is referred to as 6632/6631 in places; the A-DIE reports chip id
  0x6833 and ECO E1.
* A failed power-on can leave the chip in a state where module unload hangs;
  `reboot -f` is the reliable way out.
* Type-C dock auto-switching is **not** part of this and is currently disabled.

## Boot timing

Measured on the test device (`journalctl -o short-precise`):

| event | time |
|---|---|
| kernel | 2 min 2 s |
| `mtkwifi-init` starts | +0 s |
| `wlan0` appears | +2 s |
| wpa_supplicant associated | +5 s |
| DHCPACK on wlan0 | +5 s |
| `eth0` static address applied | +8 s |

Two things were fixed here:

* `wifi-connect@.service` used to carry `After=network.target`. That unit is
  itself what brings the link up, so ordering it after `network.target` delayed
  the whole Wi-Fi connection by ~85 s. It now only orders after
  `network-pre.target` and starts from the udev trigger.
* The wait loops and the DHCP attempts are bounded: `WAIT=10` for the interface,
  `-lt 20` for association, and `timeout 15 dhclient -1` /
  `timeout 6 dhclient -1`. Note ISC dhclient has **no** `-timeout` flag - using
  it makes dhclient print its usage and exit, which silently leaves the link
  without an address.

The remaining boot cost is the kernel (2 min), not these scripts.
