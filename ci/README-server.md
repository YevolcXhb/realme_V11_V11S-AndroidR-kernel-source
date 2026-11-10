# MT6833 / RMX3122 server profile and USB-PD fixes

Date: 2026-11-02. This is a **source implementation**, not a newly built or flashed kernel.

## CPU governor profile (not a scheduler replacement)

Merge `ci/server.config` after `oppo6833_defconfig` or `oppo6833_debug_defconfig`, then run `olddefconfig` and `ci/check-server-config.py`.
`CONFIG_MTK_SERVER_SCHEDUTIL` is optional and defaults to `n` in Kconfig. With the fragment enabled, initial schedutil limits are:

- up: `max(driver transition delay, 2000 us)`;
- down: `max(effective up limit, 20000 us)`.

This retains WALT/HMP, PREEMPT, existing scheduler changes, thermal/frequency ceilings and runtime sysfs controls. Longer down delays may increase power consumption. No performance improvement is asserted without benchmarks.
A vendor power HAL or existing tuning service can change governor selection or limits after boot. The profile is used only when schedutil is active.

## USB-PD changes

`drivers/misc/mediatek/usb20/mt6833/usb20_host.c`:

- DR_SWAP follows the negotiated UFP/DFP intent even if the delayed MUSB controller has not reached the previous role yet.
- Detach clears host intent even if an attach job was queued but the HCD never became active.
- Queued Type-C host/VBUS workers read the latest requested state instead of blindly replaying a superseded operation. IDDIG/non-Type-C host workers keep their original queued semantics.
- Data-role notification does not request charger OTG boost. Existing Type-C `vbus_control=0` remains; source power follows SOURCE_VBUS notification.
- Null notifier payload/controller is ignored safely.

`drivers/misc/mediatek/typec/tcpc/tcpci_dual_role.c` returns the actual PD/Type-C swap request result to the caller, instead of returning false success. PD request completion still arrives asynchronously; a zero enqueue result is not proof that the partner accepted a swap.

These are targeted corrections to the existing vendor state machine, not a rewrite of PD policy or a guarantee against every in-flight hardware race.
A host data role and sink power role must remain independent. Simultaneous charging + Ethernet requires compatible phone hardware, charger, hub PD controller and negotiated roles; the patch cannot create missing hardware capabilities.

## Ethernet driver requirements

The fragment explicitly requires built-in USBNET, RTL8152 (including the RTL8153 driver family), AX8817X, AX88179/178A, CDC Ethernet and CDC NCM. These were already enabled in both locally resolved OEM configs; this change preserves rather than claims newly added drivers.
An adapter's exact USB ID/chip revision and physical link speed still require hardware testing. The phone's actual USB bus speed, not an adapter's advertised Ethernet port speed, limits throughput.

## Build and validation

The existing `.github/workflows/build-kernel.yml` now offers `server_profile: server|stock`, default server, for both OEM defconfigs. `stock` disables the additional DVFS defaults; it does **not** undo source-level USB fixes or pre-existing custom patches.
The workflow merges/checks the server fragment, runs portable C harnesses, builds `Image.gz-dtb`, and retains the exported-symbol CRC compatibility gate before publication. Release tags include commit, defconfig and profile so server/stock builds do not overwrite one another.

Example on an already prepared Linux builder (use the toolchains/environment in the workflow):

```bash
make O=out ARCH=arm64 oppo6833_defconfig
./scripts/kconfig/merge_config.sh -m -O out out/.config ci/server.config
make O=out ARCH=arm64 olddefconfig
python3 ci/check-server-config.py out/.config
python3 ci/test-server-policy.py
# Continue with the workflow's clang r383902/binutils, build and CRC gate.
```

Do not skip the CRC gate: vendor modules depend on the exported-symbol ABI. Config parsing or mocked C functions cannot verify it.
Do not repack the ROM with an unbuilt kernel. No GitHub push, workflow dispatch, phone connection, boot repack or flashing was performed in this continuation.

## Local evidence / remaining validation

Evidence is in the workspace sibling `_kernelwork_server_20261102/`:

- original files and SHA256 manifest; source patch and final SOURCE-SHA256.json;
- OEM/server Kconfig resolutions and deltas (both variants);
- seven actual-function host C test variants (stock/server/inverted limits, USB with/without UART, PD/Type-C request errors);
- standalone/common ADB deployment sandbox tests and report;
- Windows has no usable WSL distribution/ARM64 kernel build setup for a full local build.

Remaining: complete ARM64 compile + MODVERSIONS CRC comparison; boot/repack verification; manual boot/ADB test; hub attach/detach/DR_SWAP/PR_SWAP tests; charging direction/current and Ethernet DHCP/link/throughput tests; server latency/power/thermal measurements.

Primary references:
`https://www.kernel.org/doc/html/latest/driver-api/usb/typec.html`
`https://topjohnwu.github.io/Magisk/guides.html`
