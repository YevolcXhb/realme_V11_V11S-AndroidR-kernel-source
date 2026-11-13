#!/bin/sh
# Bring up the USB Wi-Fi dongle (Realtek RTL8188EU) and join the hotspot.
#
# The r8188eu driver is a wireless-extensions driver: with the default
# nl80211 backend wpa_supplicant associates but never completes the WPA2
# four-way handshake ("Security mode:open", every frame dropped). -D wext is
# what makes it work.
#
# Address: the Windows hotspot's ICS DHCP does not answer this client, so the
# script tries DHCP with a short budget and falls back to a static lease.
set -u

IFACE="${1:-wlx3c3300b35fb3}"
CONF="/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf"
STATIC_IP="192.168.137.60"
GATEWAY="192.168.137.1"

[ -d "/sys/class/net/${IFACE}" ] || exit 0

ip link set "${IFACE}" up
pkill -f "wpa_supplicant.*${IFACE}" 2>/dev/null
sleep 1
wpa_supplicant -B -i "${IFACE}" -D wext -c "${CONF}" >/var/log/wpa-${IFACE}.log 2>&1

i=0
while [ $i -lt 30 ]; do
    state=$(wpa_cli -i "${IFACE}" status 2>/dev/null | sed -n 's/^wpa_state=//p')
    [ "${state}" = "COMPLETED" ] && break
    sleep 1
    i=$((i + 1))
done

if [ "$(wpa_cli -i "${IFACE}" status 2>/dev/null | sed -n 's/^wpa_state=//p')" != "COMPLETED" ]; then
    echo "wifi-dongle: association failed"
    exit 1
fi

# DHCP with a short budget, then fall back to a fixed address.
timeout 15 dhclient -1 "${IFACE}" >/dev/null 2>&1 || true
if ! ip -4 addr show "${IFACE}" | grep -q "inet "; then
    ip addr replace "${STATIC_IP}/24" dev "${IFACE}"
fi
ip route replace default via "${GATEWAY}" dev "${IFACE}"
echo "wifi-dongle: ${IFACE} up, $(ip -4 -br addr show "${IFACE}" | awk '{print $3}')"
