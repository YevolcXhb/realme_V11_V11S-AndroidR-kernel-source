/* Bring up the vendor connectivity stack the way Android userspace does:
 * first tell wmt_detect the SoC chip id (which also sets the chip type to SOC),
 * then ask it to run the common driver init, which is what creates the wmt_lib
 * queues that power-on needs.
 *
 * Passing chip id 0 to DO_MODULE_INIT is wrong: wmt_detect_set_chip_type(0)
 * maps to WMT_CHIP_TYPE_COMBO, i.e. the external-combo platform, and that path
 * dereferences combo state that does not exist on this SoC.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>

#define WMT_DETECT_IOC_MAGIC 'w'
#define COMBO_IOCTL_GET_CHIP_ID      _IOR(WMT_DETECT_IOC_MAGIC, 0, int)
#define COMBO_IOCTL_SET_CHIP_ID      _IOW(WMT_DETECT_IOC_MAGIC, 1, int)
#define COMBO_IOCTL_GET_SOC_CHIP_ID  _IOR(WMT_DETECT_IOC_MAGIC, 3, int)
#define COMBO_IOCTL_DO_MODULE_INIT   _IOR(WMT_DETECT_IOC_MAGIC, 4, int)
#define COMBO_IOCTL_GET_ADIE_CHIP_ID _IOR(WMT_DETECT_IOC_MAGIC, 9, int)

int main(int argc, char **argv)
{
    unsigned int chip = 0x6833;
    if (argc > 1)
        chip = (unsigned int)strtoul(argv[1], NULL, 0);

    int fd = open("/dev/wmtdetect", O_RDWR);
    if (fd < 0) { perror("open /dev/wmtdetect"); return 1; }

    int rc = ioctl(fd, COMBO_IOCTL_SET_CHIP_ID, (unsigned long)chip);
    printf("SET_CHIP_ID(0x%x) -> %d %s\n", chip, rc, rc < 0 ? strerror(errno) : "ok");
    fflush(stdout);

    rc = ioctl(fd, COMBO_IOCTL_GET_CHIP_ID, 0);
    printf("GET_CHIP_ID  -> 0x%x\n", rc);
    fflush(stdout);

    rc = ioctl(fd, COMBO_IOCTL_DO_MODULE_INIT, (unsigned long)chip);
    printf("DO_MODULE_INIT(0x%x) -> %d %s\n", chip, rc, rc < 0 ? strerror(errno) : "ok");
    fflush(stdout);

    rc = ioctl(fd, COMBO_IOCTL_GET_SOC_CHIP_ID, 0);
    printf("GET_SOC_CHIP_ID -> 0x%x\n", rc);

    close(fd);
    return 0;
}
