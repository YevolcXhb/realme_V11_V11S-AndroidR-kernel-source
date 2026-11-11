#!/bin/sh
# Switch the Type-C port between device (UFP) and host (DFP) mode.
#
# The port is described by the kernel's dual_role_usb class (MTK tcpc):
#   /sys/class/dual_role_usb/dual-role-type_c_port0/{data_role,power_role,mode}
# data_role and power_role are writable; "mode" is not. Writing data_role=host
# is what makes the SoC act as an OTG host (like Android's OTG switch).
#
# Dock detection is deliberately conservative: we only switch to host when the
# port has negotiated a PD contract (a dock or PD charger is on the other end)
# AND there is no gadget enumeration, i.e. we are not talking to the PC over
# RNDIS. When the partner goes away we go back to device mode.
set -u

DR_DIR=/sys/class/dual_role_usb
DR=
for d in "$DR_DIR"/*/; do
    [ -e "${d}data_role" ] && DR="${d%/}" && break
done
[ -n "$DR" ] || { echo "usb-role-watch: no dual_role_usb device" >&2; exit 1; }

TCPC_DIR=$(dirname "$(dirname "$DR")")
LOG_TAG=usb-role-watch

log() { echo "$LOG_TAG: $*"; }

current() { cat "$DR/data_role" 2>/dev/null; }

pd_contract() {
    # remote_src_cap lines appear once a PD contract is negotiated
    if [ -r "$TCPC_DIR/caps_info" ]; then
        awk '/remote_src_cap/{flag=1;next}/remote_snk_cap/{flag=0}flag && NF>=4{c++}END{exit c?0:1}' \
            "$TCPC_DIR/caps_info"
    else
        return 1
    fi
}

gadget_up() {
    # RNDIS/gadget link to the PC present?
    [ -d /sys/class/net/rndis0 ] || [ -d /sys/class/net/usb0 ] && \
        { ip -o link show 2>/dev/null | grep -qE 'rndis0|usb0: .*(UP|LOWER_UP)'; return $?; }
    return 1
}

set_role() {
    want="$1"
    have=$(current)
    [ "$have" = "$want" ] && return 0
    log "switching data_role $have -> $want"
    echo "$want" > "$DR/data_role" 2>/dev/null || log "write data_role=$want failed"
    sleep 1
    log "data_role now $(current)"
}

log "watching $DR (tcpc $TCPC_DIR)"

while :; do
    if pd_contract && ! gadget_up; then
        set_role host
    else
        set_role device
    fi
    sleep 2
done
