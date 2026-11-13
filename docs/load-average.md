## Load average: what it was, and what it is now

The box idles at 96% CPU yet used to report a load average of 3.8-4.1. The
load was never CPU work - it was tasks sitting in `D` (uninterruptible sleep)
that never finish:

| Source | Before | Fix |
|---|---|---|
| `amms_task` | SCHED_FIFO 98, active | thread creation removed |
| vendor threaded IRQs | SCHED_FIFO 50 | lowered to FIFO 10 at boot |
| `rpmb_open` | permanent D, waiting on a TEE session | thread not started at boot |
| `udhcpd-usb` / `telnetd-fallback` | respawn storm (74+ restarts) | gated on `usb0` existing |

### rpmb_open

The RPMB driver opens a session through the TEE at boot. Nothing in a plain
Ubuntu userspace ever asks for RPMB, so `session_mc_open_session()` waits
forever and the task is charged to the load average permanently.
`rpmb-mtk.c` now leaves `open_th = NULL` instead of calling `kthread_run`;
`/dev/rpmb` is still created and `open()` retries lazily, so no functionality
is lost.

### Flapping units

`udhcpd-usb` and `telnetd-fallback` were written for the data-cable case where
the gadget interface is `usb0`. With a dock attached the interface is `rndis0`,
the initramfs udhcpd/telnetd survive `switch_root` and serve it, and the
systemd units could only fail - restarting every 3 seconds forever. Both now
carry `ConditionPathIsDirectory=/sys/class/net/usb0` and `Restart=on-failure`
with a `StartLimitBurst=3`, so they simply skip when there is no cable.

### Result

```
load average: 0.64, 0.57, 0.30   (was 3.8-4.1)
D-state tasks: 0
CPU idle: 96%
```
