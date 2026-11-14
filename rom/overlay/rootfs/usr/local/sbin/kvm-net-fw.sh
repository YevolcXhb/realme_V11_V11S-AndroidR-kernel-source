#!/bin/sh
# Keep the libvirt NAT network usable alongside the 1Panel firewall.
#
# 1Panel rebuilds its own chains (1PANEL_BASIC*) from its database on every
# reload and its INPUT policy drops TCP/UDP before ufw runs, which kills
# DHCP/DNS for guests on virbr0. Re-add the allow rule whenever it is gone.
# Idempotent; safe to run often.
set -u

want_iface=virbr0
chain=1PANEL_BASIC_BEFORE

# nothing to do when the 1Panel firewall is not in use
iptables -L "$chain" -n >/dev/null 2>&1 || exit 0

if ! iptables -C "$chain" -i "$want_iface" -j ACCEPT 2>/dev/null; then
    iptables -I "$chain" 1 -i "$want_iface" -j ACCEPT
    logger -t kvm-net-fw "allow rule for $want_iface re-added"
fi

# guests need NAT/forwarding towards the outside world
if ! iptables -C FORWARD -i "$want_iface" -j ACCEPT 2>/dev/null; then
    iptables -I FORWARD 1 -i "$want_iface" -j ACCEPT
    logger -t kvm-net-fw "forward allow for $want_iface re-added"
fi
exit 0
