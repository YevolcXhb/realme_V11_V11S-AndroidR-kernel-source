#!/bin/sh
# Make "reboot" fast when a virtual machine is running.
#
# libvirt-guests (enabled by libvirt-daemon-system) asks every guest to shut
# down first, but its default SHUTDOWN_TIMEOUT is 120 s. The Alpine guest has no
# acpid, so it ignores the ACPI power request and the host waits the full two
# minutes before forcing the guest off - that is the "reboot hangs / needs the
# power button" symptom. Shorten the timeout so the guest is stopped quickly and
# the normal shutdown continues.
set -eu
cat > /etc/default/libvirt-guests <<'EOF'
# Shut guests down on host shutdown; do not wait long for a guest that ignores
# the ACPI request (the Alpine guest has no acpid installed).
ON_SHUTDOWN=shutdown
SHUTDOWN_TIMEOUT=25
PARALLEL_SHUTDOWN=5
EOF
systemctl daemon-reload
echo "done. shutdown will wait at most 25 s per guest before forcing it off."
echo "test: with a VM running, run 'sync; systemctl reboot' (returns in about 60 s)."
