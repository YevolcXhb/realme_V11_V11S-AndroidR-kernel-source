
## Firewall (ufw) on this kernel

`ufw enable` appeared to work but silently produced a firewall with **no allow
rules**: `ufw status` said active, `INPUT` flipped to DROP, and every remote
login was refused. The cause is netfilter, not ufw:

* this kernel has no `CONFIG_NETFILTER_XT_TARGET_LOG`, so any `-j LOG` rule is
  rejected with "Extension LOG revision 0 not supported";
* it also has no xt_rt, and ufw ships `-m rt --rt-type 0` rules for IPv6;
* `iptables-restore` aborts the **whole file** when one rule fails, so the
  chains that hold the allow rules never get created. What survives is the
  default DROP policy - i.e. a firewall that locks you out.

### Fix

1. `LOGLEVEL=off` in `/etc/ufw/ufw.conf` - with ufw logging off, no LOG rules
   are generated at all.
2. Comment out the three `-m rt` lines in `/etc/ufw/before6.rules` (a backup is
   kept as `before6.rules.orig`).
3. `/usr/lib/ufw/ufw-init force-reload` to load the rules cleanly.
4. `ufw-reload.service` repeats step 3 at every boot, because `ufw.service` runs
   before the reload is possible and can leave the chains empty.

`tools/device/ufw-reload.sh` + `tools/device/ufw-reload.service` implement
step 4; the script also enforces step 1 when it runs.

### Verify

```
iptables -S ufw-user-input | grep ACCEPT      # must list the allow rules
ufw status verbose
```

Rules shipped by default: 22/tcp (ssh), 23/tcp (telnet rescue console), and all
traffic from 192.168.42.0/24 (the USB gadget link).

### Never enable ufw without a way back

Before enabling on a headless box, arm a dead-man switch in the same breath:

```
systemd-run --on-active=300 --unit=ufw-safe --collect ufw disable
systemd-run --on-active=2   --unit=ufw-en   --collect ufw --force enable
```

If the box becomes unreachable the firewall disables itself after five minutes.
Cancel the timer (`systemctl stop ufw-safe.timer`) only after confirming SSH
still answers.
