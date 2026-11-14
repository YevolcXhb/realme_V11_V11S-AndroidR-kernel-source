# 1Panel 虚拟机在 realme V11 上原生可用（UEFI 修复）

设备：realme V11（RMX3122 / MT6833），原生 Ubuntu 24.04 aarch64，内核 4.14.186+。

## 结论

1Panel → 虚拟机 → 创建虚拟机 现在**原生可用**：面板建域 → UEFI 引导 ISO → 客户机正常安装。
不需要适配器守护进程。

## 根因

ARM64 上 libvirt 只在启用 UEFI 时才允许 ACPI，所以 1Panel 建机一律使用 AAVMF pflash 固件。
这颗 MT6833 的厂商 KVM 对固件区访问产生的 stage-2 异常没有可用的 ESR syndrome，
QEMU 无法据此模拟固件访问，客户机直接报：

    error: kvm run failed Function not implemented

## 修复（两处，均为源码补丁）

1. **QEMU** `hw/block/pflash_cfi01.c`：KVM 模式下把 pflash 建成普通可写 RAM
   （`memory_region_init_ram`），客户机访问固件区不再产生异常。
2. **EDK2** `OvmfPkg/VirtNorFlashDxe/VirtNorFlash.c`：flash 驱动改为内存语义
   （读状态=就绪、擦除=memset 0xFF、写=memcpy），因为 RAM 后备没有 CFI 状态机。

补丁与预编译产物在 ROM 包 `tools/kvm/native/`：

| 文件 | 说明 |
|---|---|
| qemu-system-aarch64-patched | 打过补丁的 QEMU 8.2.2（Ubuntu 源码编译） |
| AAVMF_CODE_2MB.fd | 打过补丁的 AAVMF 固件（edk2-stable202402） |
| qemu-pflash-ram.patch | QEMU 补丁源码 |
| edk2-norflash-ram.patch | EDK2 补丁源码 |
| install-native-uefi.sh | 一键安装（自动备份原始文件为 .orig） |

## 验证

* 面板创建的 `ubuntu-vm` 通过 VNC 控制台显示 Alpine 3.20 安装器登录界面
  （`Welcome to Alpine Linux 3.20 / Kernel 6.6.134-0-virt on an aarch64`）。
* 设备重启后虚拟机自动启动，面板显示 running，补丁二进制仍然生效。

## 限制

* 1Panel 社区版最多创建 1 台虚拟机。
* 安装 ISO 后请在面板控制台里完成安装；安装完成前不要关闭控制台。

## 回滚

    cp -a /usr/bin/qemu-system-aarch64.orig /usr/bin/qemu-system-aarch64
    cp -a /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd.orig /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
    systemctl restart libvirtd
