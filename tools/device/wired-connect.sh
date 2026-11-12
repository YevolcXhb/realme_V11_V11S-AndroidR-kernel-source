#!/bin/sh
# Bring up a wired interface on the USB-C dock.
#
# There is no router on this link (dock Ethernet straight into a PC NIC), so
# nothing answers DHCP. Try DHCP first so the same dock still works on a real
# LAN, then fall back to a static address on the direct-link subnet.
set -u

IFACE=${1:-eth0}
STATIC_ADDR=${WIRED_STATIC_ADDR:-192.168.123.50/24}
WAIT=20

log() { echo "wired-connect[$IFACE]: $*"; }

i=0
while [ ! -e "/sys/class/net/$IFACE" ]; do
    i=$((i+1))
    [ "$i" -gt "$WAIT" ] && { log "interface never appeared"; exit 0; }
    sleep 1
done

ip link set "$IFACE" up || true

# wait for carrier (dock has to power up and train the PHY)
i=0
while [ "$i" -lt 15 ]; do
    [ "$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)" = "1" ] && break
    i=$((i+1)); sleep 1
done
log "carrier=$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)"

if dhclient -1 -timeout 8 "$IFACE" >/dev/null 2>&1; then
    log "dhcp lease: $(ip -4 addr show "$IFACE" | awk '/inet /{print $2}')"
    exit 0
fi

log "no dhcp server, using static $STATIC_ADDR"
ip addr replace "$STATIC_ADDR" dev "$IFACE"
log "address: $(ip -4 addr show "$IFACE" | awk '/inet /{print $2}')"
