#!/bin/bashset -eE
START_DIR=$(pwd)

rm -rf arm64 && mkdir arm64
mem_size=$(free --giga | grep Mem | awk '{print $2}')if [ $mem_size -gt 2 ]; then sudo mount -t tmpfs -o size=1G tmpfs arm64; fi
cd arm64
BASE_DIR=$(pwd)

git clone --depth 1 https://github.com/rockchip-linux/rkbin
DDR_FILE=$(ls rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v*.bin | head -n 1)
BL31_FILE=$(ls rkbin/bin/rk35/rk3588_bl31*.elf | head -n 1)

export ROCKCHIP_TPL="${BASE_DIR}/${DDR_FILE}"
export BL31="${BASE_DIR}/${BL31_FILE}"

git clone --depth 1 https://gitlab.com/u-boot/u-boot.git -b v2024.01
cd u-boot

CONFIG_NAME=${1:-nanopc-t6-rk3588_defconfig}
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

make clean
make $CONFIG_NAME
make -j$(nproc)

cp u-boot-rockchip.bin "$START_DIR"
cd "$START_DIR"
if [ $mem_size -gt 2 ]; then sudo umount arm64; fi
exit 0
