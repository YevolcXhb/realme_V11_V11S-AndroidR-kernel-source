#!/bin/bash
# Build the flashable userdata.img for realme V11 (RMX3122 / MT6833).
set -euo pipefail

REPO="$GITHUB_REPOSITORY"
ASSETS="https://github.com/$REPO/releases/download/rom-assets"
ROOTFS="$PWD/rootfs"
IMG="$PWD/userdata.img"
SUITE=noble
MIRROR=http://ports.ubuntu.com/ubuntu-ports

PKGS="ubuntu-minimal ca-certificates curl wget openssh-server usbutils pciutils iproute2 net-tools iputils-ping less vim-tiny sudo rsync kmod procps psmisc tzdata locales man-db gnupg systemd-timesyncd isc-dhcp-client wpasupplicant wireless-tools rfkill python3 htop file unzip zip tar gzip xz-utils nano bash-completion lsof docker.io docker-compose-v2 qemu-system-arm qemu-utils libvirt-daemon-system libvirt-clients bridge-utils dnsmasq-base libxml2-utils autofs ntfs-3g"

echo "== host dependencies =="
sudo apt-get update -y
sudo apt-get install -y debootstrap qemu-user-static binfmt-support e2fsprogs rsync
sudo update-binfmts --enable qemu-aarch64 || true

echo "== debootstrap =="
sudo rm -rf "$ROOTFS"
sudo debootstrap --arch=arm64 --variant=minbase --components=main,universe --include=apt,ca-certificates "$SUITE" "$ROOTFS" "$MIRROR"

echo "== install packages =="
sudo mount --bind /proc "$ROOTFS/proc"
sudo mount --bind /sys "$ROOTFS/sys"
sudo mount --bind /dev "$ROOTFS/dev"
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
printf 'deb %s noble main universe\ndeb %s noble-updates main universe\ndeb %s noble-security main universe\n' "$MIRROR" "$MIRROR" "$MIRROR" > /tmp/sources.list
sudo cp /tmp/sources.list "$ROOTFS/etc/apt/sources.list"
sudo chroot "$ROOTFS" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -q --no-install-recommends $PKGS"

echo "== overlay =="
# --keep-dirlinks: /lib, /bin, /sbin are symlinks into /usr on Ubuntu.
# --no-owner/--no-group: the CI checkout is owned by uid 1001; without these
# flags /etc and /usr would end up owned by 1001 and tools such as ufw abort
# with "WARN: uid is 0 but '/etc' is owned by 1001".
sudo rsync -aK --no-owner --no-group rom/overlay/rootfs/ "$ROOTFS/"
if [ ! -e "$ROOTFS/lib/ld-linux-aarch64.so.1" ]; then
    echo "FATAL: dynamic loader missing after overlay" >&2
    exit 1
fi
sudo chown -R root:root "$ROOTFS/etc" "$ROOTFS/usr" "$ROOTFS/var" "$ROOTFS/opt" 2>/dev/null || true

echo "== kernel modules =="
sudo mkdir -p "$ROOTFS/usr/lib/modules/4.14.186+/extra"
for m in r8188eu.ko wmt_drv.ko wmt_chrdev_wifi.ko wlan_6833_axi.ko; do
    curl -fsSL "$ASSETS/$m" -o "/tmp/$m"
    sudo install -m 644 "/tmp/$m" "$ROOTFS/usr/lib/modules/4.14.186+/extra/$m"
done
sudo ln -sfn /usr/lib/modules "$ROOTFS/lib/modules" 2>/dev/null || true

echo "== patched QEMU + AAVMF =="
curl -fsSL "$ASSETS/qemu-system-aarch64-patched" -o /tmp/qemu-system-aarch64
sudo install -m 755 /tmp/qemu-system-aarch64 "$ROOTFS/usr/bin/qemu-system-aarch64"
curl -fsSL "$ASSETS/AAVMF_CODE_2MB.fd" -o /tmp/AAVMF_CODE_2MB.fd
sudo mkdir -p "$ROOTFS/usr/share/AAVMF"
sudo dd if=/dev/zero of="$ROOTFS/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd" bs=1M count=64 status=none
sudo dd if=/tmp/AAVMF_CODE_2MB.fd of="$ROOTFS/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd" conv=notrunc status=none
sudo chmod 644 "$ROOTFS/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd"
if [ -d /usr/lib/ipxe/qemu ]; then
    sudo mkdir -p "$ROOTFS/usr/share/qemu"
    sudo cp -n /usr/lib/ipxe/qemu/* "$ROOTFS/usr/share/qemu/" || true
fi

echo "== system configuration =="
sudo chroot "$ROOTFS" /bin/bash -c '
set -e
mkdir -p /media/usb
echo "root:root" | chpasswd
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/;s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
systemctl enable ssh docker libvirtd libvirt-guests systemd-networkd autofs 2>/dev/null || true
systemctl enable mtkwifi-init wifi-connect@wlan0 wired-connect@eth0 usbgadget-net 2>/dev/null || true
systemctl enable growroot 2>/dev/null || true
ln -sf /etc/systemd/system/kvm-net-fw.timer /etc/systemd/system/timers.target.wants/kvm-net-fw.timer 2>/dev/null || true
mkdir -p /etc/libvirt/qemu/networks/autostart /etc/libvirt/storage/autostart /var/lib/libvirt/images
ln -sf ../default.xml /etc/libvirt/qemu/networks/autostart/default.xml
ln -sf ../images.xml /etc/libvirt/storage/autostart/images.xml
chmod 755 /usr/local/sbin/*.sh /usr/local/bin/*.sh 2>/dev/null || true
depmod -a 4.14.186+ 2>/dev/null || true
'

echo "== image =="
sudo umount "$ROOTFS/dev" "$ROOTFS/sys" "$ROOTFS/proc" || true
rm -f "$IMG"
truncate -s 6G "$IMG"
mkfs.ext4 -q -F -L ubuntu-rootfs -m 1 "$IMG"
mkdir -p /tmp/rommnt
sudo mount -o loop "$IMG" /tmp/rommnt
sudo rsync -aHAX --numeric-ids "$ROOTFS/" /tmp/rommnt/
sudo mkdir -p /tmp/rommnt/proc /tmp/rommnt/sys /tmp/rommnt/dev /tmp/rommnt/run /tmp/rommnt/tmp /tmp/rommnt/mnt /tmp/rommnt/media /tmp/rommnt/media/usb
sudo chmod 1777 /tmp/rommnt/tmp
sudo sync
sudo umount /tmp/rommnt

echo "== compress =="
rm -f userdata.img.gz
gzip -1 -c "$IMG" > userdata.img.gz
ls -lh "$IMG" userdata.img.gz
sha256sum userdata.img.gz > userdata.img.gz.sha256
echo "== done =="
