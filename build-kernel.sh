#!/bin/bash
# Останавливать выполнение при любых ошибкахset -eE
trap 'echo Error: in $0 on line $LINENO' ERR
if [ $# -ne 1 ]; then
	echo "Использование: $0 имя_папки_сборки"
	exit 1fi
# Установка необходимых инструментов для сборки и упаковки ядра
sudo apt-get update && sudo apt-get -y install  build-essential gcc-aarch64-linux-gnu bison \
qemu-user-binfmt qemu-system-arm qemu-efi-aarch64 binfmt-support \
debootstrap flex libssl-dev bc rsync kmod cpio xz-utils fakeroot parted \
udev dosfstools uuid-runtime git-lfs device-tree-compiler python3 \
python-is-python3 fdisk bc debhelper python3-pyelftools python3-setuptools \
python3-pkg-resources swig libfdt-dev libpython3-dev gawk \
git ncurses-dev wget libelf-dev libgnutls28-dev libdw-dev

START_DIR=$(pwd)
linux_dir=$1
# Очистка и создание рабочего каталога
rm -rf "$linux_dir" && mkdir "$linux_dir"
# Монтирование в ОЗУ для ускорения сборки
mem_size=$(free --giga | grep Mem | awk '{print $2}')if [ $mem_size -gt 8 ]; then
	sudo mount -t tmpfs -o size=8G tmpfs "$linux_dir"fi

cd "$linux_dir"
BASE_DIR=$(pwd)
# Клонируем ядро Linux 7.2 в строго определенную папку 'source'
git clone --depth 1 https://kernel.org -b linux-7.2.y source
# Скачивание медиа-патчей от проекта MiniMyth2
mkdir patches && cd patches
wget https://githubusercontent.com
wget https://githubusercontent.com
wget https://githubusercontent.com
wget https://githubusercontent.com
wget https://githubusercontent.com
wget https://githubusercontent.com
wget https://githubusercontent.com
# Переходим в исходный код ядра для наката патчей и конфигурации
cd "$BASE_DIR/source"

echo "=== Применение патчей MiniMyth2 ==="for patch_file in "$BASE_DIR"/patches/*.patchdo
        echo "Применяется: $patch_file"
        patch -p1 < "$patch_file"done
# Переменные сборщика для архитектуры ARM64 (Кросс-компиляция)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
# Шаг 1: Создаем стандартный базовый .config для ARM64
make defconfig
# Шаг 2: Накатываем ваш оптимизированный Kconfig-фрагмент (my-add.txt из корня репозитория)
./scripts/kconfig/merge_config.sh -m .config "$START_DIR/my-add.txt"
# Шаг 3: Отключаем тяжелые отладочные символы, чтобы вписаться в лимиты памяти GitHub
./scripts/config --set-val DEBUG_INFO_NONE y
./scripts/config --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
./scripts/config --disable DEBUG_INFO_DWARF4
./scripts/config --disable DEBUG_INFO_DWARF5
# Шаг 4: Валидируем зависимости получившейся конфигурации
make olddefconfig
# Убираем суффикс архитектуры Arch Linux
sed -i 's/CONFIG_LOCALVERSION="-ARCH"/CONFIG_LOCALVERSION=""/' .config
 # Флаги оптимизации сборщика под ARMv8-A
export KCFLAGS="-march=armv8-a+crypto+crc -mtune=generic"

echo "=== Запуск компиляции deb-пакетов ==="
fakeroot make -j$(nproc) LOCALVERSION="-rockchip" deb-pkg
# Сохраняем версию собранного ядра во внешний файл
tmp_var=$(make LOCALVERSION="-rockchip" -s kernelrelease)
echo "$tmp_var" > "$START_DIR/kernel_version"
# Возвращаемся в корень запуска
cd "$START_DIR"
# Копируем готовые пакеты ядра из виртуального диска в корень репозитория
cp "$BASE_DIR"/*.deb .

echo "=== СБОРКА ЯДРА УСПЕШНО ЗАВЕРШЕНА ==="
df -h "$linux_dir"
# Безопасное размонтирование tmpfsif [ $mem_size -gt 8 ]; then
	sudo umount "$linux_dir"
	sleep 2
fi

exit 0
