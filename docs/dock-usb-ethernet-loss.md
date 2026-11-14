# Dock USB-Ethernet: size-dependent packet loss (open issue)

## Symptom

The dock's USB 10/100 LAN adapter (cdc_ether, QinHeng 1a86:5394) works for small
traffic but loses packets as frame size grows, so large transfers retransmit
heavily and sometimes time out:

| ICMP payload | USB packets per frame | loss |
|---|---|---|
| 56 B  | 1 | 0-10 % |
| 500 B | 1 | 10-25 % |
| 1400 B | 3 | 30-40 % |
| 1472 B | 3 | 30-40 % |

RTT stays at 0.5-0.9 ms even when packets are lost, so this is not queueing
backlog. The loss rate tracks the number of USB packets per frame, i.e. roughly
10-15 % of USB transactions are lost.

Throughput measured with a 40 MB HTTP transfer over the wired link:

* device -> PC: 2.0 MB/s (16 Mbit/s) on a 100 Mbit link
* PC -> device: ~24 KB/s, transfer stalls (300 s timeout, 7 MB moved)

The asymmetry (TX much better than RX) points at the host controller side.

## What was ruled out

* MTU, including a down/up cycle so cdc_ether re-derives rx_urb_size
* USB autosuspend and hub power management (forced power/control=on)
* Removing the sibling RTL8188EU Wi-Fi adapter from the same hub (unbind)
* MTK musb host tunables, all tested live and reverted:
  musb_host_dynamic_fifo, musb_host_db_enable,
  musb_host_db_workaround1/2, mtk_host_qmu_concurrent, mtk_qmu_max_gpd_num,
  mtk_host_qmu_pipe_msk (QMU for bulk made it 100 % loss)
* netfilter / firewall (ufw inactive while testing)
* MTK Wi-Fi traffic: with the dongle unbound loss drops to 3-10 % but does not
  disappear

## Conclusion

The loss scale with USB transaction count and the TX/RX asymmetry indicate a
physical-layer or hub/controller interaction problem, not a configuration
problem. Next steps are hardware: different USB-C cable, LAN adapter plugged
directly into the phone (bypassing the dock hub), or a different dock.

Until then: use wlan0 (on-board) or the USB Wi-Fi dongle for bulk traffic; the
wired link is fine for SSH, the panel and other light traffic.
