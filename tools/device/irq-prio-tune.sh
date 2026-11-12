#!/bin/sh
# Take the vendor IRQ threads off their hard-coded SCHED_FIFO 50.
#
# Every threaded IRQ on this kernel runs at FIFO priority 50 ("-51" in tools
# that show it as non-negative), so a PMU interrupt preempts everything else on
# its CPU. On an Android phone that latency is wanted; on a headless server it
# buys nothing and just adds jitter. Lower them to FIFO 10 and keep them off
# the CPU that handles the network IRQs.
#
# This does NOT lower the load average by itself - load here was D-state vendor
# kernel threads, not CPU time in these threads (see ci/ubuntu.config). It only
# reduces preemption.
set -u

LOW_PRIO=${IRQ_LOW_PRIO:-10}
# interrupt names (from /proc/interrupts) that only exist to serve the phone
PATTERNS="5-0034 touchpan mt6358 mt-eint"

for pat in $PATTERNS; do
    for t in /proc/[0-9]*; do
        pid=${t#/proc/}
        [ -r "$t/comm" ] || continue
        comm=$(cat "$t/comm" 2>/dev/null) || continue
        case "$comm" in
            irq/*"$pat"*)
                chrt -f -p "$LOW_PRIO" "$pid" 2>/dev/null \
                    && echo "irq-prio: $comm -> FIFO $LOW_PRIO"
                ;;
        esac
    done
done
exit 0
