#!/bin/sh
# Fix: on this vendor kernel a clean systemd shutdown never reaches the hardware
# reset (the kernel log stops before "reboot: Restarting system"), so "reboot"
# from SSH or from 1Panel leaves the device powered with the network down until
# the power button is pressed. "reboot -f" always works, so the reset path is
# fine - the last ordered shutdown step is what wedges.
#
# This installs a unit that runs late in reboot.target only (not poweroff) and
# performs an emergency reboot through sysrq after syncing.
set -eu
d=$(cd "$(dirname "$0")" && pwd)
install -m 644 "$d/force-reboot-sysrq.service" /etc/systemd/system/force-reboot-sysrq.service
mkdir -p /etc/systemd/system/reboot.target.wants
ln -sf /etc/systemd/system/force-reboot-sysrq.service /etc/systemd/system/reboot.target.wants/force-reboot-sysrq.service
systemctl daemon-reload
echo "installed. 'reboot' / 'systemctl reboot' now resets the hardware."
echo "test: sync; systemctl reboot   (it should come back in about 30 s)"
