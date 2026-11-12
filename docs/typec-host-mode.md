# USB-C host mode / dock support

## Symptom

Plugging a passive USB-C dock into the phone did nothing at all:

* no VBUS (`ac`/`usb` power supplies stayed `online=0`)
* no attach event in the TCPC logs
* `data_role` stayed `none`, `mode` stayed `none`
* the battery just kept draining

## Why

`/proc/device-tree/type_c_port0/mt-tcpc,role_def` is **0**, i.e.
`SNK Only`. A sink-only port never sources VBUS, and a passive dock is also
sink-side, so the two ends never agree on a contract: nothing powers up and no
attach is reported. `supported_modes` already advertised `ufp dfp`, so the
hardware supports both - only the controller configuration was sink-locked.

Writing to the dual-role knob does not help: `data_role` goes through
`tcpc_dual_role_set_prop_dr()` -> `tcpm_dpm_pd_data_swap()`, which is a PD
data-role swap and therefore needs an attached PD partner. With nothing
attached it just returns `-4`:

```
tcpc_dual_role_set_prop_dr data role swap (2->0): -4
```

The role is also read once at probe time (`of_property_read_u32(np,
"mt-tcpc,role_def", ...)` in `tcpc_mt6360.c`), and `role_def` is exported
read-only (`0444`), so there is no runtime switch.

## Fix

Set `role_def = 2` (DRP) in the DTB inside the boot image:

```
./tools/patch-dtb-typec-drp.py boot.img boot-drp.img     # 0 -> 2
dd if=boot-drp.img of=/dev/sdc44 bs=1M conv=fsync
```

The image length is unchanged; only the 4-byte property value is rewritten, so
the boot header, kernel and ramdisk are untouched. `dtbo` overlays were checked
and none of them set this property, so the base DTB is the right place.

Keep a copy of the original boot partition - reverting is flashing it back
(`tools/device/boot_current.img` was the pre-change image on the test device).

## Result

With the dock attached:

```
data_role        host
power_role       source
mode             dfp
role = DRP

1-1      1a86:809d  USB2.0 HUB
1-1.5    1a86:5394  USB 10/100 LAN (wch.cn)   -> eth0 UP
```

So the switch is automatic at the hardware/PD level: plug the dock and the port
negotiates DFP and powers it; unplug it and the port returns to toggling, so
plugging a PC cable still gives the normal UFP/RNDIS path.

## Notes

* The dock's Ethernet needs a cable in its RJ45 before `dhclient` gets a lease;
  the adapter itself enumerates fine without one.
* Battery is not charged while sourcing the dock, which is expected.
* `mt-tcpc,vconn_supply` is still `0`; if a dock with an e-marked cable fails
  to power up, try setting it to `1` as well.

## Wired networking through the dock

The dock's `1a86:5394` Ethernet adapter comes up as `eth0` as soon as the port
is in host mode. When the dock is cabled straight into a PC NIC there is no DHCP
server anywhere on that link, so `eth0` otherwise sits at a link-local address
and neither side can reach the other.

`tools/device/wired-connect.sh` (started by a udev rule whenever `eth0`
appears) tries DHCP with a short timeout and falls back to a static address:

```
eth0  UP  192.168.123.50/24      (WIRED_STATIC_ADDR overrides)
```

The PC side just needs to be on the same subnet. Verified after an unattended
reboot: `eth0` came up at `192.168.123.50/24` with no manual step, the dock's
hub and LAN adapter enumerated, and `data_role` was `host` again.

Windows reports that adapter as an unidentified/no-internet network, which is
expected on a router-less point-to-point link and does not stop SSH or file
transfer.
