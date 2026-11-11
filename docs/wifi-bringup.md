# MediaTek CONSYS 6833 Wi-Fi bring-up notes

Field notes from getting the built-in Wi-Fi of the realme V11 (RMX3122, MT6833,
CONSYS_6833) working on a native Ubuntu 24.04 kernel. Written down because
almost none of it is documented anywhere.

## Where the stack lives

The kernel tree only builds `connadp` (a thin adapter). The real driver stack is
the vendor tree under `kernel_modules/connectivity` and it is built as three
modules against this kernel:

| module | source | role |
|---|---|---|
| `wmt_drv.ko` | `common/` | WMT core, STP transport, CONSYS power/clock |
| `wmt_chrdev_wifi.ko` | `wlan/adaptor/` | `/dev/wmtWifi` power switch + fw log |
| `wlan_6833_axi.ko` | `wlan/core/gen4m/` | the actual Wi-Fi driver (AXI HIF) |

The OEM's own module set is exactly these three; there is no `conninfra.ko` on
this SoC, and the OEM kernel config (`CONFIG_MTK_COMBO_CHIP="CONSYS_6833"`,
`CONFIG_MTK_COMBO_WIFI=y`, `CONFIG_MTK_BTIF=y`) matches what we build.

## Build gotchas

1. **obj-m vs obj-y.** The vendor Makefiles emit `obj-y` whenever
   `CONFIG_MTK_COMBO_WIFI=y`, so an out-of-tree `make M=...` produces nothing
   ("MODPOST 0 modules") and no error. `MTK_WIFI_AS_MODULE` (see the Makefiles)
   pins the branch to `obj-m` for a module-only build.

2. **Empty guard variables.** `common/` and `adaptor/` wrap their whole body in
   `ifneq ($(CONFIG_MTK_COMBO),)`, and `gen4m` picks `obj-$(CONFIG_MTK_WIFI_ONLY)`
   when that variable is empty (`obj-` is not a variable kbuild reads). Both are
   silent failures.

3. **Platform code selection.** `common/Makefile` compiles
   `platform/$(MTK_PLATFORM).o`. The kernel Makefile exports `MTK_PLATFORM` from
   `CONFIG_MTK_PLATFORM`, which is **mt6853** in this tree, so the build silently
   pulls in `platform/mt6853.c` instead of `platform/mt6833.c` and the SoC
   regulator/clock hooks are wrong. Pass `MTK_PLATFORM=mt6833` on the make
   command line (an environment variable is not enough).

4. **`-Werror` in the vendor Makefiles** does not survive modern gcc. The
   Makefiles here downgrade it to `-Wno-error`.

5. **A real source bug:** `common_main/platform/mtk_wcn_consys_hw.c` puts the
   closing brace of a `for` loop inside `#ifdef OPLUS_MT6833_POWERINFO_STANDBY`,
   so the file only compiles when that symbol is defined
   (`KCFLAGS=-DOPLUS_MT6833_POWERINFO_STANDBY`).

## Userspace has to drive the init

`wmt_drv` only registers `wmt_detect` at module load. Everything else is
triggered by userspace, which is what Android's `wmt_loader` does:

1. `SET_CHIP_ID` on `/dev/wmtdetect` with the SoC id (`0x6833`). Passing 0 maps to
   `WMT_CHIP_TYPE_COMBO` and crashes the kernel on this board.
2. `DO_MODULE_INIT` - runs `mtk_wcn_common_drv_init()`, which creates the
   `wmtd`/`wmtd_worker` threads and the `wmt_lib` queues.
3. `SET_STP_MODE` on `/dev/stpwmt` with `0x23` = `STP_BTIF_FULL | WMT_FM_COMM<<4`.
   Without it power-on bails out with "no hif info".
4. **ROM patch metadata** - see below.

`SET_ROM_PATCH_INFO` (ioctl 31, `struct wmt_rom_patch_info`) matters because
`wmt_ctrl_get_rom_patch_info()` asks the MCU for the patch list when the table is
empty, and the MCU is not answering yet at that point:

```c
if (!pDev->pWmtRomPatchInfo[WMTDRV_TYPE_WMT]) {
        snprintf(cmdStr, "srh_rom_patch");
        ret = wmt_ctrl_ul_cmd(pDev, cmdStr);   /* -2, no MCU yet */
        if (ret) return -1;                    /* power-on unwinds here */
}
```

Supplying the entry up front skips the query and lets the driver copy the patch
into EMI over AXI, which is how `mtk_wcn_soc_rom_patch_dwn()` works.

### Choosing the patch file

The patch header's version must match the silicon. This board reports
`consys HW version id(0x8a00)`, and:

| file | header version |
|---|---|
| `soc3_0_ram_mcu_1_1_hdr.bin` | 0x8a10 |
| `soc2_2_ram_mcu_1_1_hdr.bin` | **0x8a00** |

So the `soc2_2` family is the right one for this device.

## Current status

```
[WMT-IC] [Rom Patch]Name=soc2_2_ram_mcu_1_1_hdr.bin,EmiOffset=0x0,Size=0x... 
[WMT-IC] physAddr=0xbe000000 ...      <- patch written into EMI
```

The remaining gap is the MCU/BTIF handshake: `mtk btif irq` never fires, so the
MCU never acknowledges. Everything below that (power rails, clocks, A-DIE
detect, EMI windows) is verified working.

## Files in this directory

| file | purpose |
|---|---|
| `wmt_init.c` | chip id + common driver init via `/dev/wmtdetect` |
| `wmt_setstp.c` | STP transport selection via `/dev/stpwmt` |
| `wmt_setpatch.c` | ROM patch metadata injection |
| `mtkwifi-init.sh` | runs the three steps above at boot |
| `mtkwifi-init.service` | systemd unit for the above |
| `usb-role-watch.sh` + `.service` | Type-C dock detection, switch to OTG host |
| `wifi-connect.sh` + `wifi-connect@.service` + `99-wifi-connect.rules` | bring any `wlan0` up and connect |

## Fallback

`r8188eu` is built by the same workflow. With an RTL8188EU dongle plugged in the
udev rule starts `wifi-connect@wlan0.service` and the device associates using
`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`.
