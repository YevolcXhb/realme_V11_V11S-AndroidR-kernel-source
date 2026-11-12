
## Load average on an idle box

`loadavg` read 3.8-4.1 while `top` showed 94-97% idle. The number was entirely
tasks parked in **D state**, so it said nothing about CPU work:

```
amms_task       SCHED_FIFO 98   drivers/misc/mediatek/memory-amms
hang_detect1    SCHED_FIFO      drivers/misc/mediatek/aee/aed (AEE hang monitor)
rpmb_open       stale OP-TEE session wait
```

`amms_task` was the worst of them: FIFO **98**, i.e. above every threaded IRQ on
the kernel (those sit at 50), and it never did any useful work here because the
modem is gone.

`CONFIG_MTK_AMMS=n` does not work: `CONFIG_ANDROID_DEFAULT_SETTING` selects it,
and that symbol drags in binder/ashmem and dozens of others. Instead the thread
is simply not created (drivers/misc/mediatek/memory-amms/memory-amms.c) - the
platform driver still registers and the one other user of `amms_task` already
NULL-checks it. `CONFIG_MTK_AEE_HANG_DETECT` can be turned off normally, and
that also removes the thing that reboots a phone it thinks is hung.

Every vendor threaded IRQ also ran at FIFO 50. On a server that buys no latency,
only jitter, so `tools/device/irq-prio-tune.sh` drops the phone-specific ones
(PMU 5-0034, touchpanel, mt6358) to FIFO 10 at boot.

Measured after a reboot:

| | before | after |
|---|---|---|
| loadavg (1 min) | 3.8 - 4.1 | 2.0 - 2.7, falling |
| loadavg (15 min) | 0.43 | 0.39 |
| D-state tasks | 3 - 6 | 1 (`rpmb_open`) |

`rpmb_open` remains: it waits for an OP-TEE session that never comes up, and
`CONFIG_RPMB` was left enabled because disabling it risks the TEE build.

## Battery without a battery

The unit is fed from a DC module that holds the pack terminals at 4.2-4.4 V, so
the fuel gauge (which counts coulombs through a pack that never discharges)
reported nonsense - it was seen jumping between 1% and 50% at a steady 4.25 V.
The driver now derives the level from the terminal voltage it already reads:
100% at 4.2 V, 0% at 3.4 V, linear between. Verified: `capacity=100` at
`voltage_now=4249000`.
