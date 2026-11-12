/* Supply ROM patch metadata to the WMT driver (see docs/wifi-bringup.md).
 *
 * Usage: wmt-setpatch <type> <patch file> [emi offset in hex]
 *   type 0 = BT, 1 = FM, 2 = GPS, 3 = WIFI, 4 = WMT (MCU)
 *
 * On Android, /vendor/bin/wmt_launcher answers the driver's "srh_rom_patch"
 * request over STP and fills this table. Without an answer the driver unwinds
 * power-on with "failed to get patch (type: 0, ret: -1)", so a plain Ubuntu
 * userland has to supply the same entries up front.
 *
 * The EMI offset is the one encoded in the patch file header (bytes 24..31):
 *   MCU  soc2_2_ram_mcu_1_1_hdr.bin   0x000000
 *   WiFi soc2_2_ram_wifi_1_1_hdr.bin  0x2a0000
 *   BT   soc2_2_ram_bt_1_1_hdr.bin    0x170000
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

struct wmt_rom_patch_info {
    uint32_t type;
    uint8_t  addRess[4];
    uint8_t  patchName[256];
};

int main(int argc, char **argv)
{
    struct wmt_rom_patch_info info;
    unsigned long type = 4;
    unsigned long offset = 0;
    const char *name;

    if (argc < 3) {
        fprintf(stderr, "usage: %s <type> <patch-file> [emi-offset-hex]\n", argv[0]);
        return 2;
    }
    type = strtoul(argv[1], NULL, 0);
    name = argv[2];
    if (argc > 3)
        offset = strtoul(argv[3], NULL, 0);

    memset(&info, 0, sizeof(info));
    info.type = (uint32_t)type;
    info.addRess[0] = (uint8_t)(offset & 0xff);
    info.addRess[1] = (uint8_t)((offset >> 8) & 0xff);
    info.addRess[2] = (uint8_t)((offset >> 16) & 0xff);
    info.addRess[3] = 0;
    strncpy((char *)info.patchName, name, sizeof(info.patchName) - 1);

    int fd = open("/dev/stpwmt", O_RDWR);
    if (fd < 0) { perror("open /dev/stpwmt"); return 1; }

    int rc = ioctl(fd, WMT_IOCTL_SET_ROM_PATCH_INFO, &info);
    printf("SET_ROM_PATCH_INFO(type=%lu, name=%s, offset=0x%lx) -> %d %s\n",
           type, info.patchName, offset, rc, rc < 0 ? strerror(errno) : "ok");
    close(fd);
    return rc < 0 ? 1 : 0;
}
