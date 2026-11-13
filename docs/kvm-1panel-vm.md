# 在 realme V11 上用 1Panel 管理 KVM 虚拟机

设备：realme V11（RMX3122 / MT6833），原生 Ubuntu 24.04 aarch64，内核 4.14.186+。

## 结论

* KVM 可用：`/dev/kvm` 存在，`KVM_GET_API_VERSION = 12`，QEMU 8.2.2 以 `-accel kvm` 运行 ARM64 客户机。
* libvirt 10.0.0 已装，default NAT 网络（192.168.122.0/24）正常。
* 1Panel 的「虚拟机」页面可接管并管理已有的 libvirt 域：启动、强制停止、打开控制台。
* 虚拟机使用**内核直启**（kernel + initramfs + 磁盘根分区），不依赖固件。

## 组件与脚本

| 路径 | 作用 |
|---|---|
| `/usr/local/sbin/vm-create.sh` | 从 Alpine 模板克隆并定义、启动虚拟机 |
| `/usr/local/sbin/kvm-net-fw.sh` + `kvm-net-fw.timer` | 1Panel 重建防火墙链后自动补回 virbr0 放行规则 |
| `/var/lib/libvirt/images/alpine-root.img` | 6 GiB ext4 Alpine 3.20 模板（含 sshd/acpid） |
| `/var/lib/libvirt/images/alpine-vmlinuz` / `alpine-initramfs` | 客户机内核与 initramfs |
| `/usr/share/doc/kvm-1panel/NOTES.md` | 限制、回滚步骤 |

## 使用

```sh
vm-create.sh web1 2 1024 8
virsh vncdisplay web1
virsh console web1          # Ctrl-] 退出
ssh root@<ip>               # 默认密码 alpine
```

1Panel → 虚拟机 会自动同步新域，之后启停都在面板里完成。

## 为什么面板内建机暂时不可用

ARM64 上 libvirt 只有在启用 UEFI 时才允许 ACPI，因此面板建机会强制使用
AAVMF pflash 固件。该固件在本 SoC 的 KVM 上无法引导：固件会写入只读的
firmware memslot，产生的 stage-2 异常无法被这颗厂商 KVM 解码
（`kvm run failed Function not implemented`）。

已尝试并确认的事实：

* QEMU 的 `-kernel` 直启客户机完全正常（本文的虚拟机就是这么跑的）。
* 厂商 KVM 能识别 `CPU: All CPU(s) started at EL2`，Hyp 模式已初始化。
* 给固件加补丁跳过写 ROM 的指令后，固件能继续执行一段，但仍会在
  「异常综合征与 PC 不自洽」处失败，说明问题在固件与这颗 KVM 的交互层。

## 排错

* 客户机拿不到 IP：`systemctl status kvm-net-fw.timer`，确认
  `iptables -S 1PANEL_BASIC_BEFORE | grep virbr0` 有放行规则。
* 面板显示「未检测到 libvirt/storage」：刷新页面或点「重新检测」；
  依赖判定是 `/dev/kvm` + `/var/lib/libvirt/images` + `qemu:///system` 可连。
* 面板关机按钮无效：这些域没有 ACPI，请用强制停止或客户机内 `poweroff`。
## 追加验证（2026-11-14）

为判断 UEFI 问题是否只出在「写只读区指令无法解码」，内核追加了一次实验
（commit 746a6245）：无法解码的写只读区故障改为无条件跳过 4 字节。

结果：标准 AAVMF 固件不再报 `Function not implemented`，但陷入 0x36d0 与
0x36f8 之间的循环。日志显示被跳过的指令是 `ldurb`/`ldrb` 类**加载**指令，
而异常报告的是**写**：这颗厂商 KVM 的异常综合征（ESR）与 PC 在该路径上不自洽。
跳过加载会破坏固件的数据流，因此该内核被回退，设备回到 commit f65d7852 的
稳定内核。

结论：UEFI 引导失败是固件与该厂商 KVM 的交互层问题，与 KVM 基本能力、
libvirt、QEMU 都没有关系；内核直启的虚拟机不受影响。
