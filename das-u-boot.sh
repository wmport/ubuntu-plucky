#!/bin/bash

# Установка необходимых инструментов для сборки и кросс-компиляции
sudo apt-get update && sudo apt-get -y install build-essential gcc-aarch64-linux-gnu bison \
qemu-user-static qemu-system-arm qemu-efi-aarch64 binfmt-support \
debootstrap flex libssl-dev bc rsync kmod cpio xz-utils fakeroot parted \
udev dosfstools uuid-runtime git-lfs device-tree-compiler python3 \
python-is-python3 fdisk debhelper python3-pyelftools python3-setuptools \
python3-pkg-resources swig libfdt-dev libpython3-dev gawk \
ncurses-dev libelf-dev libgnutls28-dev libdw-dev

# Сохраняем абсолютный путь к стартовой директории запуска скрипта
START_DIR=$(pwd)

# Очистка и создание рабочего каталога
rm -rf arm64
mkdir arm64

# Оптимизация сборки в ОЗУ (если доступно более 2ГБ памяти)
mem_size=$(free --giga | grep Mem | awk '{print $2}')
if [ $mem_size -gt 2 ]; then
        sudo mount -t tmpfs -o size=1G tmpfs arm64
fi
cd arm64

# Фиксируем абсолютный путь к корню временной папки сборки arm64
BASE_DIR=$(pwd)

# Клонирование официальных бинарных компонентов инициализации Rockchip
git clone --depth 1 https://github.com/rockchip-linux/rkbin

# Находим файлы внутри rkbin и сразу формируем валидный абсолютный путь
DDR_FILE=$(ls rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v*.bin | head -n 1)
BL31_FILE=$(ls rkbin/bin/rk35/rk3588_bl31*.elf | head -n 1)

# Экспорт абсолютных путей для сборщика U-Boot (теперь они железно правильные)
export ROCKCHIP_TPL="${BASE_DIR}/${DDR_FILE}"
export BL31="${BASE_DIR}/${BL31_FILE}"

echo ""
echo "=== Проверенные переменные окружения Rockchip ==="
echo "ROCKCHIP_TPL: $ROCKCHIP_TPL"
echo "BL31:         $BL31"
echo "================================================="
echo ""

# Клонирование Mainline U-Boot конкретной версии v2024.01
git clone --depth 1 https://gitlab.com/u-boot/u-boot.git -b v2024.01
cd u-boot

# Определение конфигурационного файла (по умолчанию используется nanopc-t6-rk3588_defconfig)
CONFIG_NAME=${1:-nanopc-t6-rk3588_defconfig}

if [ ! -f configs/$CONFIG_NAME ]; then
	echo "Ошибка: Конфигурация $CONFIG_NAME не найдена в папке configs!"
	cd "$START_DIR"
	if [ $mem_size -gt 2 ]; then sudo umount arm64; fi
	exit 1
fi

# Экспорт архитектуры и кросс-компилятора для утилиты make
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

echo "Сборка конфигурации: $CONFIG_NAME"
make clean
make $CONFIG_NAME
make -j$(nproc)

# Копирование готового монолитного образа u-boot-rockchip.bin в стартовый корень
cp u-boot-rockchip.bin "$START_DIR"

cd "$START_DIR"

echo ""
echo "=== СБОРКА УСПЕШНО ЗАВЕРШЕНА ==="
echo "Файл u-boot-rockchip.bin скопирован в исходную директорию."
echo ""
echo "=== ИНСТРУКЦИЯ ДЛЯ ЗАПИСИ ==="
echo "Для записи загрузчика на microSD или eMMC выполните команду:"
echo "sudo dd if=u-boot-rockchip.bin of=/dev/sdX bs=512 seek=64 conv=notrunc,fsync"
echo "(Замените sdX на имя вашего целевого накопителя, например sdb или mmcblk0)"
echo "============================="
echo ""

# Освобождение оперативной памяти от tmpfs диска
if [ $mem_size -gt 2 ]; then
        sudo umount arm64
	sleep 2
fi 
exit 0
