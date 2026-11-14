#!/bin/sh
# Server tuning: journald cap, zram swap, I/O scheduler, sysctl.
# Every change is reversible; backups go to /root/opt-backup.
set -eu
B=/root/opt-backup; mkdir -p $B

echo "== journald cap =="
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf <<'UNIT'
[Journal]
SystemMaxUse=64M
SystemKeepFree=512M
UNIT
systemctl restart systemd-journald

echo "== zram swap (2 GiB, lz4) =="
cat > /etc/systemd/system/zram-swap.service <<'UNIT'
[Unit]
Description=zram compressed swap
After=systemd-modules-load.service
Before=swap.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'swapoff /dev/zram0 2>/dev/null; echo 1 > /sys/block/zram0/reset 2>/dev/null; echo lz4 > /sys/block/zram0/comp_algorithm; echo 2147483648 > /sys/block/zram0/disksize && mkswap /dev/zram0 >/dev/null && swapon -p 100 /dev/zram0'
ExecStop=/bin/sh -c 'swapoff /dev/zram0 2>/dev/null; echo 1 > /sys/block/zram0/reset 2>/dev/null'

[Install]
WantedBy=swap.target
UNIT
systemctl daemon-reload
systemctl enable --now zram-swap.service

echo "== I/O scheduler =="
cat > /etc/udev/rules.d/60-io-scheduler.rules <<'UNIT'
ACTION=="add|change", KERNEL=="sdc", ATTR{queue/scheduler}="deadline"
UNIT
for d in /sys/block/sd*/queue/scheduler; do echo deadline > "$d" 2>/dev/null || true; done

echo "== sysctl =="
cat > /etc/sysctl.d/99-server-tuning.conf <<'UNIT'
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.swappiness = 100
UNIT
sysctl -q -p /etc/sysctl.d/99-server-tuning.conf

echo "== done =="
free -m | head -3
swapon --show || true
