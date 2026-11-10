/* r8188eu WEXT scan probe.
 *
 * Two things this got wrong before, both worth keeping in mind:
 *  - struct iw_point.length is __u16, so a 256 KiB request truncates to 0 and
 *    the driver answers -E2BIG. Keep the buffer inside 16 bits.
 *  - The scan event stream is framed as  <len:u16 LE><event-id:u16 LE><payload>
 *    -- length FIRST, then the id. Parsing id-first silently walks off into
 *    the payload and decodes zero BSS entries even though data came back.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/ioctl.h>

#define SIOCSIWSCAN  0x8B18
#define SIOCGIWSCAN  0x8B19
#define SIOCGIWNAME  0x8B01
#define SIOCGIWAP    0x8B15
#define SIOCGIWESSID 0x8B1B
#define SIOCGIWFREQ  0x8B1F

#define SCAN_BUFSZ 32768

struct iw_point_u { void *pointer; unsigned short length; unsigned short flags; };
struct iwreq_u { char ifrn_name[16]; union { struct iw_point_u data; char pad[32]; } u; };

#define HDR 4

static int enc_print(const unsigned char *p, int len) {
    int n = 0;
    for (int k = HDR; k < len; k++) {
        unsigned char ch = p[k];
        if (ch >= 0x20 && ch < 0x7f) { putchar(ch); n++; }
        else if (ch >= 0x80) { putchar('?'); n++; }
    }
    return n;
}

int main(int argc, char **argv) {
    const char *ifn = argc > 1 ? argv[1] : "wlan2";
    struct iwreq_u w;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) { perror("socket"); return 1; }

    memset(&w, 0, sizeof w);
    strncpy(w.ifrn_name, ifn, 15);
    if (ioctl(s, SIOCGIWNAME, &w) != 0) {
        printf("interface %s not reachable via WEXT\n", ifn);
        close(s); return 1;
    }
    printf("interface %s reachable via WEXT\n", ifn);

    memset(&w, 0, sizeof w);
    strncpy(w.ifrn_name, ifn, 15);
    if (ioctl(s, SIOCSIWSCAN, &w) < 0) {
        printf("SIOCSIWSCAN failed: %s\n", strerror(errno));
        close(s); return 2;
    }

    static char buf[SCAN_BUFSZ];
    int got = -1;
    for (int i = 0; i < 10; i++) {
        memset(&w, 0, sizeof w);
        strncpy(w.ifrn_name, ifn, 15);
        w.u.data.pointer = buf;
        w.u.data.length  = SCAN_BUFSZ;
        w.u.data.flags   = 0;
        memset(buf, 0, 64);
        errno = 0;
        if (ioctl(s, SIOCGIWSCAN, &w) == 0) { got = (int)w.u.data.length; break; }
        if (errno == EAGAIN) { usleep(300000); continue; }
        printf("SIOCGIWSCAN failed: %s\n", strerror(errno));
        close(s); return 3;
    }
    if (got < 0)  { printf("no scan results\n"); close(s); return 4; }
    if (got == 0) { printf("driver returned an empty scan list\n"); close(s); return 6; }

    printf("scan payload: %d bytes\n\n", got);

    int off = 0, bss = 0, flushed = 0;
    while (off + HDR <= got) {
        unsigned short len, id;
        memcpy(&len, buf + off,     2);
        memcpy(&id,  buf + off + 2, 2);
        if (len < HDR || off + len > got) break;
        const unsigned char *p = (const unsigned char *)(buf + off);

        if (id == SIOCGIWAP) {
            if (flushed) printf("\n");
            bss++; flushed = 0;
            printf("[%2d] bssid ", bss);
            for (int k = 0; k < 6; k++) printf("%02x%s", p[HDR + 2 + k], k < 5 ? ":" : "");
            printf("  ");
        } else if (id == SIOCGIWESSID) {
            printf("ssid=\"");
            enc_print(p, len);
            printf("\"  ");
        } else if (id == SIOCGIWFREQ) {
            int m = 0, e = 0;
            memcpy(&m, p + HDR, 4);
            memcpy(&e, p + HDR + 4, 2);
            if (e == 0) printf("chan=%d  ", m);
            else        printf("freq=%d.%03dGHz  ", m / 100000, (m % 100000) / 100);
            flushed = 1;
        }
        off += len;
    }
    printf("\n\ntotal BSS: %d\n", bss);
    close(s);
    return bss > 0 ? 0 : 6;
}
