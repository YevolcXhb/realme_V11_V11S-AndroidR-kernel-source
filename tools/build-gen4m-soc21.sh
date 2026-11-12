#!/bin/sh
# Build wlan_6833_axi for the RMX3122 (MT6833) from the vendor source tree.
#
# MTK_COMBO_CHIP is the one setting that decides which chip family the gen4m
# driver is compiled for, and picking the wrong one fails in a confusing place
# much later (see docs/wifi-bringup.md):
#   CONNAC    -> 16-byte RX descriptor, requests WIFI_RAM_CODE_soc1_0  (wrong)
#   SOC2_2X2  -> 20-byte RX descriptor, requests WIFI_RAM_CODE_soc2_0  (wrong name)
#   SOC2_1X1  -> 20-byte RX descriptor, requests WIFI_RAM_CODE_soc2_2  (correct)
set -eu
cd /root/kbuild

export CROSS_COMPILE=aarch64-linux-gnu-
export MTK_COMBO_CHIP=SOC2_1X1
export MTK_PLATFORM_ID=6833 WLAN_CHIP_ID=6833 WIFI_IP_SET=1
export CONFIG_MTK_COMBO_WIFI_HIF=axi MTK_ANDROID_WMT=y MTK_ANDROID_EMI=y ADAPTOR_OPTS=CONNAC
export MTK_WIFI_AS_MODULE=1

CFLAGS="-DOPLUS_MT6833_POWERINFO_STANDBY -Wno-error -Wno-strict-prototypes -Wno-missing-prototypes"
FORCE="CONFIG_MTK_COMBO=m CONFIG_MTK_COMBO_WIFI=m CONFIG_WLAN_DRV_BUILD_IN=n CONFIG_MTK_WIFI_ONLY=n CONFIG_MTK_WIFI_CONNINFRA_SUPPORT=n"
MK="make -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out KBUILD_MODPOST_WARN=1 KCFLAGS=$CFLAGS MTK_PLATFORM=mt6833 $FORCE"

GEN=kernel_modules/connectivity/wlan/core/gen4m
# stale objects were compiled with a different -D set; ccflags changes do not
# invalidate them, so force a clean rebuild of the chip set
find $GEN -name '*.o' -delete
find $GEN -name '.*.cmd' -delete
rm -f $GEN/*.ko

$MK M=$PWD/$GEN modules
ls -l $GEN/*.ko
