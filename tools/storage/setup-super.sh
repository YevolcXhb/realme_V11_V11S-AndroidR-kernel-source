#!/bin/sh
# Put Docker data and libvirt images on the spare "super" partition (10 GiB).
#
# super is the Android dynamic-partition container. This device does not run
# Android, the ROM only flashes boot + userdata, so the partition is free.
#
# Layout after this script:
#   /mnt/super                 ext4 (LABEL=super, mounted from fstab, nofail)
#   /mnt/super/docker          docker data-root (daemon.json)
#   /mnt/super/libvirt-images  bind-mounted over /var/lib/libvirt/images
set -eu
P=/dev/disk/by-partlabel/super

[ -b "$P" ] || { echo "no super partition"; exit 1; }
[ -f /etc/docker/daemon.json ] && cp -a /etc/docker/daemon.json /root/daemon.json.bak || true

if ! blkid "$P" | grep -q 'TYPE="ext4"'; then
    echo "== formatting super (existing Android data on it is discarded) =="
    mkfs.ext4 -q -F -L super "$P"
fi

mkdir -p /mnt/super
grep -q '/mnt/super' /etc/fstab || echo 'LABEL=super /mnt/super ext4 defaults,nofail,x-systemd.device-timeout=5 0 2' >> /etc/fstab
systemctl daemon-reload
mount /mnt/super 2>/dev/null || true

echo "== docker data-root =="
systemctl stop docker docker.socket 2>/dev/null || true
mkdir -p /mnt/super/docker
if [ -d /var/lib/docker ] && [ ! -L /var/lib/docker ]; then
    rsync -aHAX --numeric-ids /var/lib/docker/ /mnt/super/docker/ || true
    mv /var/lib/docker /var/lib/docker.old 2>/dev/null || true
fi
cat > /etc/docker/daemon.json <<'JSON'
{
  "data-root": "/mnt/super/docker",
  "registry-mirrors": [
    "https://docker.1ms.run"
  ]
}
JSON
mkdir -p /etc/systemd/system/docker.service.d
printf '[Unit]\nRequiresMountsFor=/mnt/super\n' > /etc/systemd/system/docker.service.d/mount-super.conf
systemctl daemon-reload
systemctl start docker

echo "== libvirt images =="
systemctl stop libvirtd 2>/dev/null || true
mkdir -p /mnt/super/libvirt-images
if [ -d /var/lib/libvirt/images ] && ! mountpoint -q /var/lib/libvirt/images; then
    rsync -aHAX --sparse --numeric-ids /var/lib/libvirt/images/ /mnt/super/libvirt-images/ || true
    mv /var/lib/libvirt/images /var/lib/libvirt/images.old 2>/dev/null || true
    mkdir -p /var/lib/libvirt/images
fi
grep -q 'libvirt-images' /etc/fstab || echo '/mnt/super/libvirt-images /var/lib/libvirt/images none bind,nofail,x-systemd.requires=/mnt/super 0 0' >> /etc/fstab
systemctl daemon-reload
mount /var/lib/libvirt/images 2>/dev/null || true
mkdir -p /etc/systemd/system/libvirtd.service.d
printf '[Unit]\nRequiresMountsFor=/var/lib/libvirt/images\n' > /etc/systemd/system/libvirtd.service.d/requires-images.conf
systemctl daemon-reload
systemctl start libvirtd 2>/dev/null || true

echo "== done =="
df -h /mnt/super /var/lib/libvirt/images 2>/dev/null || true
