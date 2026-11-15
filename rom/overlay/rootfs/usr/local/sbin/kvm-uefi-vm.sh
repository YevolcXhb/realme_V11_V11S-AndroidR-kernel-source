#!/bin/sh
# Create an arm64 UEFI (AAVMF) virtual machine on the realme V11 KVM host.
#
# The SoC's KVM has three hard requirements that the libvirt defaults get wrong:
#   * GICv3 only - KVM here has no GICv2 emulation ("KVM does not support GICv2
#     emulation" at startup),
#   * the guest CPU model must be host-passthrough ("KVM is not supported for
#     this guest CPU type" otherwise),
#   * the patched AAVMF image is a single 64 MiB pflash blob, so every guest
#     needs its own copy that the qemu user can write (pflash holds the UEFI
#     variable store).
#
# Usage: kvm-uefi-vm.sh <name> [vcpus] [memory_mb] [disk_gb]
set -eu

name="${1:-}"
vcpus="${2:-2}"
mem="${3:-1024}"
diskgb="${4:-6}"

[ -n "$name" ] || { echo "usage: $0 <name> [vcpus] [mem_mb] [disk_gb]" >&2; exit 2; }
case "$name" in *[!a-zA-Z0-9_-]*) echo "name must be alnum/-/_" >&2; exit 2;; esac

IMGDIR=/var/lib/libvirt/images
FW=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
DISK="$IMGDIR/$name.img"
VARS="$IMGDIR/$name.fd"

[ -f "$FW" ] || { echo "missing $FW" >&2; exit 1; }
virsh dominfo "$name" >/dev/null 2>&1 && { echo "domain $name already exists" >&2; exit 1; }
[ -e "$DISK" ] && { echo "$DISK already exists" >&2; exit 1; }

qemu-img create -f raw "$DISK" "${diskgb}G" >/dev/null
cp "$FW" "$VARS"
chown libvirt-qemu:kvm "$VARS" "$DISK" 2>/dev/null || true
chmod 660 "$VARS" "$DISK"

virsh define /dev/stdin <<EOF
<domain type='kvm'>
  <name>$name</name>
  <memory unit='MiB'>$mem</memory>
  <vcpu>$vcpus</vcpu>
  <os>
    <type arch='aarch64' machine='virt'>hvm</type>
    <loader readonly='no' type='pflash' format='raw'>$VARS</loader>
  </os>
  <cpu mode='host-passthrough'/>
  <features><acpi/><gic version='3'/></features>
  <devices>
    <emulator>/usr/bin/qemu-system-aarch64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='$DISK'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'/>
    <video><model type='virtio'/></video>
  </devices>
</domain>
EOF

virsh start "$name" >/dev/null
echo "created $name (vcpus=$vcpus mem=${mem}M disk=${diskgb}G)"
echo "firmware: $VARS (per-VM copy, writable)"
echo "console:  virsh console $name"
echo "vnc:      virsh vncdisplay $name"
