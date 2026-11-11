/* Configure the WMT transport and power Wi-Fi on.
 *
 * The kernel side of the vendor stack needs two userspace steps that Android's
 * wmt_loader does:
 *   1. WMT_IOCTL_SET_STP_MODE on /dev/stpwmt - this is what registers the HIF
 *      info. Without it wmt_core_stp_init() bails out with "no hif info" and
 *      power-on fails. On an SoC part the transport is BTIF, not SDIO/UART.
 *   2. power on through /dev/wmtWifi.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>

#define WMT_IOC_MAGIC          0xa0
#define WMT_IOCTL_SET_STP_MODE _IOW(WMT_IOC_MAGIC, 5, int)

#define STP_UART_FULL  0x01
#define STP_SDIO       0x02
#define STP_BTIF_FULL  0x03

#define WMT_FM_COMM    2

int main(int argc, char **argv)
{
    unsigned long hifconf = STP_BTIF_FULL | (WMT_FM_COMM << 4);
    if (argc > 1)
        hifconf = strtoul(argv[1], NULL, 0);

    int fd = open("/dev/stpwmt", O_RDWR);
    if (fd < 0) { perror("open /dev/stpwmt"); return 1; }

    int rc = ioctl(fd, WMT_IOCTL_SET_STP_MODE, hifconf);
    printf("SET_STP_MODE(0x%lx) -> %d %s\n", hifconf, rc, rc < 0 ? strerror(errno) : "ok");
    close(fd);
    return rc < 0 ? 1 : 0;
}
