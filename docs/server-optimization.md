# 服务端存储与调优（realme V11 / RMX3122）

## super 分区（10 GiB）

`super` 是 Android 动态分区容器。本机不跑 Android，ROM 只写 boot/userdata，
分区表也不变，因此可以格式化后挂载使用。

| 项 | 配置 |
|---|---|
| 设备 | /dev/disk/by-partlabel/super（10 GiB） |
| 文件系统 | ext4，卷标 super |
| 挂载 | /mnt/super，fstab 用 LABEL=super + nofail |
| Docker 数据 | /mnt/super/docker（/etc/docker/daemon.json 的 data-root） |
| 虚拟机镜像 | /mnt/super/libvirt-images，绑定挂载到 /var/lib/libvirt/images |
| 启动依赖 | docker.service 与 libvirtd 均加 RequiresMountsFor |

一键配置：`tools/storage/setup-super.sh`（幂等，自动保留 .old 回滚目录）。

### 回滚

    systemctl stop docker libvirtd
    rm /etc/docker/daemon.json
    mv /mnt/super/docker /var/lib/docker
    umount /var/lib/libvirt/images
    uuid=$(blkid -s UUID -o value /dev/disk/by-partlabel/super)
    sed -i "/$uuid/d;/libvirt-images/d" /etc/fstab
    umount /mnt/super
    systemctl daemon-reload && systemctl start docker libvirtd

## 调优（tools/opt/apply-tuning.sh）

| 项 | 改动 | 效果（实测） |
|---|---|---|
| journald | SystemMaxUse=64M | 757 MB → 18 MB |
| zram | 2 GiB lz4 压缩 swap，优先级 100 | 内存不足时先压缩而非杀进程 |
| I/O 调度器 | sdc → deadline | 顺序写 204 → 235 MB/s |
| sysctl | cubic、16 MB 缓冲、连接队列、脏页、swappiness=100 | 网络/内存行为更接近服务器 |

启动时间：到 multi-user.target 19.5 s → 13.1 s（主要来自把 ufw-reload 从启动链移出）。
注意：ufw-reload 必须仍早于 ssh，否则 1Panel 防火墙链顺序会短暂阻断 TCP。

## 实测数据

- 顺序写 235 MB/s，顺序读约 870 MB/s
- 有线（USB CDC Ethernet）约 8.7 MB/s，受 USB 2.0 / 100 Mbps 网卡限制
- CPU governor 用 performance 无收益，保持 schedutil

## 已知限制

- 有线 SSH 在宿主机重启后可能要等约 60 s：设备侧 25 s 内就绪（IP 13 s、sshd 18 s、
  防火墙 25 s、ping 20 s），延迟发生在 Windows 客户端重新识别网络期间（ICMP 不受影响）。
- 内核未开 CONFIG_TCP_CONG_BBR，需要重编内核（见后续计划）。

## BBR 内核（2026-11-14）

内核 defconfig 已加入 `CONFIG_TCP_CONG_BBR=y`、`CONFIG_NET_SCH_FQ=y`、`CONFIG_DEFAULT_FQ=y`，并去掉 `CONFIG_DEBUG_INFO`（只影响构建体积）。

| 项 | 值 |
|---|---|
| 内核版本 | 4.14.186+ #1 SMP PREEMPT Sat Nov 14 08:45:05 UTC 2026 |
| 拥塞控制 | bbr（/etc/sysctl.d/99-server-tuning.conf） |
| 默认队列 | fq |
| 回滚镜像 | tools/boot-f9-backup.img（旧内核） |

实测：`ss -tin` 显示连接使用 bbr；WiFi 下载约 1.4 MB/s（受热点/链路限制）。
注意：内核本身没有 CONFIG_TCP_CONG_CUBIC？实际 available 里 cubic/bic/reno/bbr 都在，可随时切换。

## 内核第二轮（2026-11-14）

defconfig 追加：

- `CONFIG_TRANSPARENT_HUGEPAGE=y` + `CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y`
- 关闭 `CONFIG_SCHEDSTATS`、`CONFIG_UPROBES`（调试开销）
- 尝试关闭 `CONFIG_FTRACE`/`CONFIG_DEBUG_KERNEL` 失败：MTK DRM 与 net/core/rtnetlink 依赖 trace_printk/stack_trace，保持开启
- 尝试开启 `CONFIG_HUGETLBFS` 失败：4.14 的 mm/hugetlb.c 在 clang -Werror 下编译不过，放弃（THP 已覆盖匿名内存场景）

当前内核：4.14.186+ #1 SMP PREEMPT Sat Nov 14 09:39:18 UTC 2026。

验证：

| 项 | 结果 |
|---|---|
| THP | /sys/kernel/mm/transparent_hugepage/enabled = always [madvise] never |
| BBR/fq | 保持生效 |
| sysbench CPU | 930-938 events/s（基线 936，无差异） |
| sysbench 内存 | madvise 8734 MB/s、always 波动 8032-9165 MB/s，无稳定收益，保持 madvise |
| 模块 | 内核配置变化后 r8188eu 的 modversions CRC 不匹配，已用同构建的 tools/modules/r8188eu.ko 替换 |

注意：升级内核后如果用到 USB Wi-Fi 网卡（r8188eu），必须使用与内核同一次构建的模块，
否则 systemd-modules-load 会报 Exec format error（modversions 不匹配）。

## reboot 慢/像卡死的正确结论（2026-11-14 修正）

之前的判断（"内核复位不生效"）是**错的**，证据推翻了它：

1. 虚拟机停止时，原生 systemctl reboot 30 秒内正常重启。
2. 虚拟机运行时，reboot 会很久才回来（之前以为卡死要按电源键），实际是关机被拖了约 3 分钟。

真正原因：libvirt-guests 服务在关机前先要求客户机优雅关机，默认 SHUTDOWN_TIMEOUT=120 秒；
Alpine 客户机没有 acpid，不响应 ACPI 关机请求，宿主机就干等两分钟再强制结束。

修复：/etc/default/libvirt-guests 设置 ON_SHUTDOWN=shutdown、SHUTDOWN_TIMEOUT=25。
实测：虚拟机运行中执行 reboot，60 秒左右回到系统（关机约 25 秒 + 启动约 30 秒）。

因此**不需要改内核**。SysRq 强制复位单元保留为兜底但默认不启用（避免跳过正常关机）。
