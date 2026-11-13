## KVM on this SoC: it works

The tree already carries the full arm64 KVM implementation
(`arch/arm64/kvm/*.c`, `hyp-init.S`, `hyp.S`); the OEM defconfig simply never
enables it. Turning on

```
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=y
CONFIG_KVM_ARM_HOST=y
CONFIG_VHOST=y
```

in `ci/ubuntu.config` produces a kernel that boots the hypervisor:

```
[0.092524] CPU: All CPU(s) started at EL2
[0.536355] kvm [1]: 16-bit VMID
[0.538693] kvm [1]: GICv3: no GICV resource entry
[0.538701] kvm [1]: disabling GICv2 emulation
[0.538707] kvm [1]: GIC system register CPU interface enabled
[0.538907] kvm [1]: vgic interrupt IRQ1
[0.539110] kvm [1]: Hyp mode initialized successfully
```

`/dev/kvm` appears (misc 10,232) and opens; `KVM_GET_API_VERSION` returns 12.

So the stock preloader **does** enter the kernel at EL2. No alternative
preloader is needed.

### Why "PSCI method = smc" is not evidence against KVM

An easy mistake: reading `/proc/device-tree/psci/method` = `"smc"` and
concluding "the kernel runs at EL1". The PSCI conduit is chosen independently
of the exception level the kernel runs at - SMC is normal even for a kernel
running at EL2. The authoritative answer is the boot message
`CPU: All CPU(s) started at EL2`, not the PSCI method.

### Using it

```
apt-get install -y qemu-system-arm qemu-utils
```

Then point qemu/virsh/virt-manager at `/dev/kvm` as usual.
