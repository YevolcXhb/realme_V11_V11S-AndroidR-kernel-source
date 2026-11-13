#!/bin/sh
# ufw-init fails on this kernel because netfilter has no xt_LOG target:
# any "-j LOG" line makes iptables-restore abort the whole file, so the
# firewall ends up "active" with an empty ufw-user-input chain (default DROP,
# no allow rules) - which is exactly how SSH got locked out before.
#
# Turning logging off removes every LOG rule from the generated files, and a
# force-reload then loads the user rules cleanly.
set -u
grep -q '^LOGLEVEL=off' /etc/ufw/ufw.conf 2>/dev/null || sed -i 's/^LOGLEVEL=.*/LOGLEVEL=off/' /etc/ufw/ufw.conf
/usr/lib/ufw/ufw-init force-reload >/dev/null 2>&1
n=$(iptables -S ufw-user-input 2>/dev/null | grep -c ACCEPT)
echo "ufw-reload: $n accept rules loaded"
