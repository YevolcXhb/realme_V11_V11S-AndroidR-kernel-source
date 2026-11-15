#!/bin/sh
# clam-scan.sh <targets-file> - run a ClamAV scan over the configured paths,
# quarantine anything infected, and log the result.
#
# Quarantine: /var/lib/clamav/quarantine (mode 700), each file renamed with a
# timestamp, made unreadable, and recorded as
#   time | original path | quarantine path | signature
# in quarantine/manifest.log.
#
# Exit codes: 0 clean, 1 infected file(s) found, 2 setup problem.
set -u

CONF="$1"
QDIR=/var/lib/clamav/quarantine
LOG=/var/log/clamav/scan.log
TMP="$(mktemp)"

log() {
    printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG"
}

case "$CONF" in
    "") CONF=/etc/clamav/scan-daily.conf ;;
esac

mkdir -p "$QDIR" /var/log/clamav
chmod 700 "$QDIR" 2>/dev/null
touch "$LOG"

if ! systemctl is-active --quiet clamav-daemon; then
    log "clamd is not running, starting it"
    systemctl start clamav-daemon 2>/dev/null || { log "ERROR cannot start clamav-daemon"; rm -f "$TMP"; exit 2; }
fi
[ -r "$CONF" ] || { log "ERROR missing targets file: $CONF"; rm -f "$TMP"; exit 2; }

scanned=0
infected=0
: >"$TMP"

for target in $(awk 'NF && $1 !~ /^#/ {print $1}' "$CONF"); do
    if [ ! -e "$target" ]; then
        log "skip missing $target"
        continue
    fi
    scanned=$((scanned + 1))
    clamdscan --fdpass --infected --no-summary "$target" 2>>"$LOG" >"$TMP"
    rc=$?
    case "$rc" in
        0) log "clean $target" ;;
        1)
            log "INFECTED $target"
            while IFS= read -r line; do
                case "$line" in
                    *FOUND) ;;
                    *) continue ;;
                esac
                entry=${line% FOUND}
                sig=${entry##*: }
                path=${entry%: *}
                [ -f "$path" ] || continue
                base=$(basename "$path")
                dest="$QDIR/$(date +%Y%m%dT%H%M%S)-$base"
                n=1
                while [ -e "$dest" ]; do
                    dest="$QDIR/$(date +%Y%m%dT%H%M%S)-$n-$base"
                    n=$((n + 1))
                done
                if mv -f "$path" "$dest" 2>/dev/null; then
                    chmod 000 "$dest" 2>/dev/null
                    printf '%s | %s | %s | %s\n' "$(date -Is)" "$path" "$dest" "$sig" >>"$QDIR/manifest.log"
                    log "QUARANTINED $path -> $dest ($sig)"
                    infected=$((infected + 1))
                else
                    log "QUARANTINE FAILED $path ($sig)"
                    infected=$((infected + 1))
                fi
            done <"$TMP"
            ;;
        *)
            log "scan error rc=$rc $target"
            ;;
    esac
done

rm -f "$TMP"
log "finished targets=$scanned infected=$infected quarantine=$QDIR"
if [ "$infected" -gt 0 ]; then
    exit 1
fi
exit 0
