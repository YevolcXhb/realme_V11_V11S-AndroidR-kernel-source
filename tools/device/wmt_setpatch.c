/* Supply ROM patch metadata to the WMT driver.
 *
 * wmt_ctrl_get_rom_patch_info() does this when asked for a patch entry:
 *
 *   if (!pDev->pWmtRomPatchInfo[WMTDRV_TYPE_WMT]) {
 *           snprintf(cmdStr, "srh_rom_patch");
 *           ret = wmt_ctrl_ul_cmd(pDev, cmdStr);   // asks the MCU over STP
 *           if (ret) return -1;                    // <- where power-on dies here
 *   }
 *
 * Android's wmt_loader pre-populates that table with WMT_IOCTL_SET_ROM_PATCH_INFO
 * so the MCU query never happens. Without it the driver asks the (not yet
 * responding) MCU for the patch list and the whole power-on sequence unwinds.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <stdint.h>

#define WMT_IOC_MAGIC                 0xa0
#define WMT_IOCTL_SET_ROM_PATCH_INFO  _IOW(WMT_IOC_MAGIC, 31, char*)

#define WMTDRV_TYPE_WMT  4

struct wmt_rom_patch_info {
    uint32_t type;
    uint8_t  addRess[4];
    uint8_t  patchName[256];
};

int main(int argc, char **argv)
{
    struct wmt_rom_patch_info info;
    const char *name = argc > 1 ? argv[1] : "soc3_0_ram_mcu_1_1_hdr.bin";
    unsigned long a0 = argc > 2 ? strtoul(argv[2], NULL, 0) : 0;
    unsigned long a1 = argc > 3 ? strtoul(argv[3], NULL, 0) : 0;
    unsigned long a2 = argc > 4 ? strtoul(argv[4], NULL, 0) : 0;
    unsigned long a3 = argc > 5 ? strtoul(argv[5], NULL, 0) : 0;

    memset(&info, 0, sizeof(info));
    info.type = WMTDRV_TYPE_WMT;
    info.addRess[0] = (uint8_t)a0;
    info.addRess[1] = (uint8_t)a1;
    info.addRess[2] = (uint8_t)a2;
    info.addRess[3] = (uint8_t)a3;
    strncpy((char *)info.patchName, name, sizeof(info.patchName) - 1);

    int fd = open("/dev/stpwmt", O_RDWR);
    if (fd < 0) { perror("open /dev/stpwmt"); return 1; }

    int rc = ioctl(fd, WMT_IOCTL_SET_ROM_PATCH_INFO, &info);
    printf("SET_ROM_PATCH_INFO(type=%u, name=%s, addr=%02x %02x %02x %02x) -> %d %s\n",
           info.type, info.patchName, info.addRess[0], info.addRess[1],
           info.addRess[2], info.addRess[3], rc, rc < 0 ? strerror(errno) : "ok");
    close(fd);
    return rc < 0 ? 1 : 0;
}
