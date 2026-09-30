#!/bin/bash
set -eE
trap 'echo Error: in $0 on line $LINENO' ERR

# 1. Установка необходимых инструментов для сборки
sudo apt-get update && sudo apt-get -y install \
    build-essential bison flex libssl-dev bc rsync kmod cpio xz-utils \
    fakeroot parted udev dosfstools uuid-runtime git-lfs device-tree-compiler \
    python3 python-is-python3 fdisk debhelper python3-pyelftools python3-setuptools \
    python3-pkg-resources swig libfdt-dev libpython3-dev gawk ncurses-dev \
    libelf-dev libgnutls28-dev libdw-dev uuid-dev ccache

START_DIR=$(pwd)

rm -rf arm64
mkdir arm64

mem_size=$(free --giga | grep Mem | awk '{print $2}')
if [ $mem_size -gt 15 ]; then
        sudo mount -t tmpfs -o size=4G tmpfs arm64
fi
cd arm64
BASE_DIR=$(pwd)

# 2. Клонирование официального репозитория U-Boot от FriendlyARM (ветка rk3588)
echo "Клонирование U-Boot от FriendlyARM..."
git clone --depth 1 https://github.com/friendlyarm/uboot-rockchip -b nanopi6-v2017.09 u-boot
cd u-boot

# 3. Клонирование сопутствующих бинарников rkbin от FriendlyARM (критично для их скриптов)
echo "Клонирование rkbin от FriendlyARM..."
git clone --depth 1 https://github.com/friendlyarm/rkbin -b nanopi6 rkbin

# Настройка переменных окружения, которые требует скрипт сборки FriendlyARM
export ARCH=arm64

# Если мы собираем на ARM64 хосте, кросс-компилятор не нужен, используем нативный gcc
if [ "$(uname -m)" != "aarch64" ]; then
    export CROSS_COMPILE=aarch64-linux-gnu-
fi

# Имя конфигурации по умолчанию для NanoPC-T6 у FriendlyARM
CONFIG_NAME=${1:-nanopc-t6-rk3588_defconfig}

if [ ! -f configs/$CONFIG_NAME ]; then
	echo "Ошибка: Конфигурация $CONFIG_NAME не найдена в папке configs!"
	cd "$START_DIR"
	if mountpoint -q arm64; then sudo umount arm64; fi
	exit 1
fi

echo "Сборка конфигурации FriendlyARM: $CONFIG_NAME"

# У FriendlyARM сборка выполняется через их фирменный скрипт-обертку make.sh
# Флаг --spl компилирует загрузчик и автоматически упаковывает его в монолитный u-boot-rockchip.bin
./make.sh $CONFIG_NAME
./make.sh --spl

# Проверяем, создался ли файл загрузчика
if [ ! -f u-boot-rockchip.bin ]; then
    echo "Критическая ошибка: u-boot-rockchip.bin не был собран скриптом FriendlyARM!"
    exit 1
fi

# 4. Копирование готового загрузчика в рабочий корень
cp u-boot-rockchip.bin "$START_DIR"
cd "$START_DIR"

echo ""
echo "=== СБОРКА FRIENDLYARM U-BOOT УСПЕШНО ЗАВЕРШЕНА ==="
echo "Файл u-boot-rockchip.bin успешно скопирован."
echo ""

# 5. Очистка RAM-диска
if mountpoint -q arm64; then
    sudo umount arm64
    sleep 2
fi 
exit 0
