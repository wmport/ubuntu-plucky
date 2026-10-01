#!/bin/bash
set -eE

cleanup_loopdev() {
    local loop="$1"
    sync --file-system && sync && sleep 1
    if [ -b "${loop}" ]; then
        local mountpoint_match
        mountpoint_match=$(echo "/tmp/mnt/writable" | sed -e's,/$,,; s,/,\\/,g;')'\/'
        awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
            mount --make-private "$submount" || true
            umount -l "$submount" || true
        done
        losetup -d "${loop}" || true
    fi
}

wait_loopdev() {
    local loop="$1" seconds="$2"
    until test $((seconds--)) -eq 0 -o -b "${loop}"; do sleep 1; done
    ((++seconds))
    ls -l "${loop}" &> /dev/null
}

if [ "$(id -u)" -ne 0 ]; then echo "Please run as root"; exit 1; fi
export LC_ALL=C LC_CTYPE=C LANGUAGE=C LANG=C

if [ ! -f ./rootfs ]; then exit 1; fi
. ./rootfs
. ./kernel_version

mkdir -p images
now=$(date +%F)
img="./images/Ubuntu-${kernel_version}-$2-$now.img"
size="$(( $(wc -c < "${rootfs}" ) / 1024 / 1024 ))"
truncate -s "$(( size + 512 ))M" "${img}"

loop="$(losetup -f)"
losetup -P "${loop}" "${img}"
disk="${loop}"
trap 'cleanup_loopdev ${loop}' EXIT

mount_point=/tmp/mnt
umount "${disk}"* 2> /dev/null || true
umount ${mount_point}/* 2> /dev/null || true
mkdir -p ${mount_point}/writable

# ============================================================
# ШАГ 1: Сначала создаём таблицу разделов и раздел
# ============================================================
echo "=== Создание таблицы разделов GPT ==="
dd if=/dev/zero of="${disk}" count=4096 bs=512 conv=notrunc

parted --script "${disk}" mklabel gpt
parted --script "${disk}" mkpart primary ext4 16MiB 100%

# Устанавливаем тип раздела Linux rootfs (GUID B921B045-1DF0-41C3-AF44-4C6F280D3FAE)
{ echo "t"; echo "1"; echo "B921B045-1DF0-41C3-AF44-4C6F280D3FAE"; echo "w"; } | fdisk "${disk}" &> /dev/null || true

partprobe "${disk}"
partition_char="$(if [[ ${disk: -1} == [0-9] ]]; then echo p; fi)"
sleep 1
wait_loopdev "${disk}${partition_char}1" 60

# ============================================================
# ШАГ 2: ТОЛЬКО ТЕПЕРЬ записываем U-Boot в сектор 64
# Это должно быть ПОСЛЕ создания разметки, иначе parted
# может затереть загрузчик при создании GPT.
# ============================================================
echo "=== Запись U-Boot в сектор 64 ==="
if [ -f "u-boot-rockchip.bin" ]; then
    dd if="u-boot-rockchip.bin" of="${disk}" bs=512 seek=64 conv=notrunc,fsync
    sync
    echo "U-Boot записан в сектор 64"
else
    echo "ОШИБКА: u-boot-rockchip.bin не найден!"
    exit 1
fi

# Проверка: убеждаемся, что в секторе 64 есть данные (не нули)
echo "=== Проверка записи U-Boot ==="
uboot_check=$(dd if="${disk}" bs=512 skip=64 count=1 2>/dev/null | hexdump -C | head -1)
echo "Сектор 64: $uboot_check"
if echo "$uboot_check" | grep -q "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"; then
    echo "ПРЕДУПРЕЖДЕНИЕ: Сектор 64 выглядит пустым! U-Boot мог не записаться."
fi

# ============================================================
# ШАГ 3: Форматирование корневого раздела
# ============================================================
echo "=== Форматирование корневого раздела ==="
root_uuid=$(uuidgen)
dd if=/dev/zero of="${disk}${partition_char}1" bs=1KB count=10 > /dev/null
mkfs.ext4 -U "${root_uuid}" -L desktop-rootfs "${disk}${partition_char}1"

mount "${disk}${partition_char}1" ${mount_point}/writable
tar -xpf "${rootfs}" -C ${mount_point}/writable

# ============================================================
# ШАГ 4: Настройка fstab и u-boot
# ============================================================
fdt_name="rockchip/$3.dtb"
dtbs_install_path="/usr/lib/linux-image-"
if [ ! -f ${mount_point}/writable${dtbs_install_path}${kernel_version}/${fdt_name} ]; then
    if [ -f ${mount_point}/writable/boot/dtbs/${kernel_version}/${fdt_name} ]; then
        dtbs_install_path="/boot/dtbs/"
    else
        echo "Error: $3.dtb not found in rootfs!"
        exit 1
    fi
fi

echo "# <file system>     <mount point>  <type>  <options>   <dump>  <fsck>" > ${mount_point}/writable/etc/fstab
echo "UUID=${root_uuid,,} /              ext4    defaults,x-systemd.growfs    0       1" >> ${mount_point}/writable/etc/fstab

mkdir -p ${mount_point}/writable/etc/default
echo U_BOOT_FDT='"'"$fdt_name"'"' >> ${mount_point}/writable/etc/default/u-boot
echo U_BOOT_FDT_DIR='"'"$dtbs_install_path"'"' >> ${mount_point}/writable/etc/default/u-boot

# ============================================================
# ШАГ 5: Chroot для обновления конфигурации U-Boot
# ============================================================
mountpoint="${mount_point}/writable"
mount dev-live -t devtmpfs "$mountpoint/dev"
mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
mount proc-live -t proc "$mountpoint/proc"
mount sysfs-live -t sysfs "$mountpoint/sys"
mount securityfs -t securityfs "$mountpoint/sys/kernel/security"

chroot ${mount_point}/writable/ /bin/bash -c "u-boot-update && sync"
sync --file-system && sync

# ============================================================
# ШАГ 6: Финальная очистка
# ============================================================
trap '' EXIT
sgdisk -e "${disk}"
cleanup_loopdev "${loop}"

echo -e "\nCompressing $(basename "${img}.xz")\n"
xz -v -9 -T0 "${img}"
exit 0
