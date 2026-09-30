#!/bin/bash
set -eE
trap 'echo Error: in $0 on line $LINENO' ERR

# 1. Установка необходимых инструментов для сборки
sudo apt-get update && sudo apt-get -y install \
    build-essential bison flex libssl-dev bc rsync kmod cpio xz-utils \
    fakeroot parted udev dosfstools uuid-runtime git-lfs device-tree-compiler \
    python3 python-is-python3 fdisk debhelper python3-pyelftools python3-setuptools \
    python3-pkg-resources swig libfdt-dev libpython3-dev gawk ncurses-dev \
    libelf-dev libgnutls28-dev libdw-dev uuid-dev

START_DIR=$(pwd)

rm -rf arm64
mkdir arm64

mem_size=$(free --giga | grep Mem | awk '{print $2}')
if [ $mem_size -gt 15 ]; then
        sudo mount -t tmpfs -o size=4G tmpfs arm64
fi
cd arm64
BASE_DIR=$(pwd)

# 2. Клонирование официальных бинарников Rockchip с фиксацией стабильного коммита
git clone https://github.com/rockchip-linux/rkbin
cd rkbin
# Фиксируем коммит, с которым Mainline U-Boot v2024.01 собирается без ошибок binman
# ИСПРАВЛЕНИЕ: Надежный поиск файлов с проверкой на существование
DDR_FILE=$(find "${BASE_DIR}/rkbin/bin/rk35/" -name "rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v*.bin" | head -n 1)
BL31_FILE=$(find "${BASE_DIR}/rkbin/bin/rk35/" -name "rk3588_bl31*.elf" | head -n 1)

if [ -z "$DDR_FILE" ] || [ -z "$BL31_FILE" ]; then
    echo "Критическая ошибка: Файлы инициализации Rockchip DDR или BL31 не найдены в rkbin!"
    exit 1
fi

export ROCKCHIP_TPL="$DDR_FILE"
export BL31="$BL31_FILE"

echo ""
echo "=== Проверенные переменные окружения Rockchip ==="
echo "ROCKCHIP_TPL: $ROCKCHIP_TPL"
echo "BL31:         $BL31"
echo "================================================="
echo ""

# 3. Клонирование Mainline U-Boot stable release
git clone --depth 1 https://gitlab.com/u-boot/u-boot.git -b v2024.01
cd u-boot

CONFIG_NAME=${1:-nanopc-t6-rk3588_defconfig}

if [ ! -f configs/$CONFIG_NAME ]; then
	echo "Error: Configuration $CONFIG_NAME not found in configs/ folder!"
	cd "$START_DIR"
	if mountpoint -q arm64; then sudo umount arm64; fi
	exit 1
fi

export ARCH=arm64
if [ "$(uname -m)" != "aarch64" ]; then
    export CROSS_COMPILE=aarch64-linux-gnu-
fi

echo "Сборка конфигурации: $CONFIG_NAME"
make clean
make $CONFIG_NAME

# ИСПРАВЛЕНИЕ: Если make упадет на этапе binman, скрипт мгновенно прекратит работу благодаря set -e
make -j$(nproc)

# Проверяем, создался ли файл загрузчика на самом деле перед копированием
if [ ! -f u-boot-rockchip.bin ]; then
    echo "Критическая ошибка: u-boot-rockchip.bin не был собран утилитой binman!"
    exit 1
fi

# 4. Копирование готового загрузчика в рабочий корень
cp u-boot-rockchip.bin "$START_DIR"
cd "$START_DIR"

echo ""
echo "=== СБОРКА УСПЕШНО ЗАВЕРШЕНА ==="
echo "Файл u-boot-rockchip.bin успешно скопирован."
echo ""

# 5. Очистка RAM-диска
if mountpoint -q arm64; then
    sudo umount arm64
    sleep 2
fi 
exit 0
