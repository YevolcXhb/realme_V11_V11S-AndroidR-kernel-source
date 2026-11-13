## USB Wi-Fi dongle on the dock (RTL8188EU)

The dock's second radio is `0bda:8179` (Realtek RTL8188EUS), driven by the
in-tree `r8188eu` module at `/lib/modules/4.14.186+/extra/r8188eu.ko`.

### The module must match the kernel

`r8188eu.ko` is produced by the same CI build as the kernel image. After
switching kernels, an older .ko fails with:

```
modprobe: ERROR: could not insert 'r8188eu': Exec format error
```

Copy the `r8188eu.ko` asset from the matching release, then `depmod -a`.

### WPA2 needs the wext backend

With the default nl80211 backend, wpa_supplicant associates but the four-way
handshake never completes - `iwconfig` reports `Security mode:open` and every
frame is dropped, so DHCP and even ping to the gateway fail. Use:

```
wpa_supplicant -B -i wlx3c3300b35fb3 -D wext \
    -c /etc/wpa_supplicant/wpa_supplicant-wlx3c3300b35fb3.conf
```

`tools/device/wifi-dongle.sh` wraps this: it brings the link up, starts
wpa_supplicant with `-D wext`, waits for `wpa_state=COMPLETED`, then tries
DHCP and falls back to a static lease if the AP's DHCP does not answer.

Note: the built-in MediaTek radio (`wlan0`) remains the primary interface;
the dongle is a spare path.
