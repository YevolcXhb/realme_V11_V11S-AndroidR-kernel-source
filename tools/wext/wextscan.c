/* r8188eu WEXT probe: trigger a scan and dump raw scan results.
 * Built for aarch64 (bionic) so it runs on the device as root.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/ioctl.h>

#define SIOCSIWSCAN     0x8B18
#define SIOCGIWSCAN     0x8B19
#define SIOCGIWNAME     0x8B01
#define SIOCGIWAP       0x8B15
#define SIOCGIWESSID    0x8B1B

struct iw_point_u { void *pointer; unsigned short length; unsigned short flags; };
struct iwreq_u { char ifrn_name[16]; union { struct iw_point_u data; char pad[32]; } u; };

#define IW_EV_LCP_LEN 4

static const char *evname(int id) {
    switch (id) {
    case 0x8B15: return "SIOCGIWAP";
    case 0x8B1B: return "SIOCGIWESSID";
    case 0x8B1F: return "SIOCGIWFREQ";
    case 0x8B21: return "SIOCGIWMODE";
    case 0x8B29: return "SIOCGIWENCODE";
    case 0x8B2B: return "SIOCGIWRATE";
    case 0x8C00: return "IWEVCUSTOM";
    case 0x8C01: return "IWEVASSOCREQIE";
    case 0x8C02: return "IWEVASSOCRESPIE";
    case 0x8C04: return "IWEVGENIE";
    default:     return "event";
    }
}

int main(int argc, char **argv) {
    const char *ifname = argc > 1 ? argv[1] : "wlan2";
    struct iwreq_u wrq;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) { perror("socket"); return 1; }

    memset(&wrq, 0, sizeof wrq);
    strncpy(wrq.ifrn_name, ifname, 15);
    if (ioctl(s, SIOCGIWNAME, &wrq) == 0)
        printf("SIOCGIWNAME : %s\n", (char*)&wrq.u.data);
    else
        printf("SIOCGIWNAME : FAILED %s\n", strerror(errno));

    memset(&wrq, 0, sizeof wrq);
    strncpy(wrq.ifrn_name, ifname, 15);
    if (ioctl(s, SIOCSIWSCAN, &wrq) < 0) {
        printf("SIOCSIWSCAN : FAILED %s (errno=%d)\n", strerror(errno), errno);
        close(s); return 2;
    }
    printf("SIOCSIWSCAN : accepted\n");

    char *buf = malloc(256*1024);
    int got = -1;
    for (int i = 0; i < 40; i++) {
        memset(&wrq, 0, sizeof wrq);
        strncpy(wrq.ifrn_name, ifname, 15);
        wrq.u.data.pointer = buf;
        wrq.u.data.length = 256*1024;
        if (ioctl(s, SIOCGIWSCAN, &wrq) < 0) {
            if (errno == EAGAIN || errno == E2BIG) { usleep(300000); continue; }
            printf("SIOCGIWSCAN : FAILED %s (errno=%d)\n", strerror(errno), errno);
            close(s); free(buf); return 4;
        }
        got = wrq.u.data.length;
        break;
    }
    if (got < 0) { printf("SIOCGIWSCAN : timeout\n"); close(s); free(buf); return 5; }

    printf("SIOCGIWSCAN : %d bytes\n", got);
    int off = 0, n = 0;
    while (off + IW_EV_LCP_LEN <= got) {
        unsigned short id, len;
        memcpy(&id,  buf+off, 2);
        memcpy(&len, buf+off+2, 2);
        if (!len || off+len > got) break;
        if (id == SIOCGIWAP) { n++; printf("\n--- BSS #%d ---\n", n); }
        printf("  %-16s len=%-4u", evname(id), len);
        if (id == SIOCGIWAP) {
            unsigned char *p = (unsigned char*)(buf+off);
            printf(" MAC");
            for (int k = 0; k < 6; k++) printf(":%02x", p[IW_EV_LCP_LEN+2+k]);
        } else if (id == SIOCGIWESSID) {
            unsigned char *p = (unsigned char*)(buf+off);
            printf(" ");
            for (int k = IW_EV_LCP_LEN; k < len; k++)
                if (p[k] >= 0x20 && p[k] < 0x7f) putchar(p[k]);
        }
        printf("\n");
        off += len;
    }
    printf("\ntotal BSS: %d\n", n);
    close(s); free(buf);
    return n > 0 ? 0 : 6;
}