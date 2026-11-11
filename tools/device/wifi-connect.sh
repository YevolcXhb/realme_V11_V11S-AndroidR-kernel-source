#!/bin/sh
# Bring up wlan0 whenever a Wi-Fi interface exists.
#
# Works with any driver that creates wlan0 - the rebuilt MediaTek gen4m stack or
# an r8188eu USB dongle. It waits for the interface, associates with the
# configured network and asks for a DHCP lease.
set -u

IFACE=${1:-wlan0}
CONF="/etc/wpa_supplicant/wpa_supplicant-$IFACE.conf"
WAIT=30

log() { echo "wifi-connect[$IFACE]: $*"; }

[ -r "$CONF" ] || { log "missing $CONF"; exit 0; }

i=0
while [ ! -e "/sys/class/net/$IFACE" ]; do
    i=$((i+1))
    [ "$i" -gt "$WAIT" ] && { log "interface never appeared, giving up"; exit 0; }
    sleep 1
done
log "$IFACE present"

# r8188eu and friends need the regulatory domain set before scanning works well
if command -v iw >/dev/null 2>&1; then
    iw reg set CN 2>/dev/null || true
fi

ip link set "$IFACE" up || true

# stop any stale supplicant instance
pkill -f "wpa_supplicant .*-i $IFACE" 2>/dev/null || true
sleep 1

log "starting wpa_supplicant"
wpa_supplicant -B -i "$IFACE" -c "$CONF" -Dnl80211,wext || log "wpa_supplicant failed"

# wait for association (up to 45s)
i=0
while [ "$i" -lt 45 ]; do
    if wpa_cli -i "$IFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
        log "associated"
        break
    fi
    i=$((i+1))
    sleep 1
done

if command -v dhclient >/dev/null 2>&1; then
    log "requesting DHCP lease"
    dhclient -1 -v "$IFACE" 2>&1 | tail -3 || log "dhclient failed"
    ip -4 addr show "$IFACE" | grep -q "inet " && ip -4 addr show "$IFACE" | grep "inet "
fi

exit 0
