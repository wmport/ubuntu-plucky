#!/bin/bashset -xset -eE
# Настройки прав групп видео
sed -i 's/#EXTRA_GROUPS=.*/EXTRA_GROUPS="video"/g' /etc/adduser.conf
sed -i 's/#ADD_EXTRA_GROUPS=.*/ADD_EXTRA_GROUPS=1/g' /etc/adduser.conf
# Настройка аргументов ядра для ванильного RK3588 (консоль ttyFIQ0)
echo -n "rootwait rw console=ttyFIQ0,1500000 console=tty1 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" > /etc/kernel/cmdline
echo -n " quiet splash plymouth.ignore-serial-consoles" >> /etc/kernel/cmdline
# Автоматическое создание пользователя по умолчанию (логин: ubuntu / пароль: ubuntu)if ! id -u ubuntu >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,video ubuntu
    echo "ubuntu:ubuntu" | chpasswdfi
# Конфигурация меню u-boot
mkdir -p /usr/share/u-boot-menu/conf.d
cat << 'EOF' > /usr/share/u-boot-menu/conf.d/ubuntu.conf
U_BOOT_UPDATE="true"
U_BOOT_PROMPT="1"
U_BOOT_PARAMETERS="$(cat /etc/kernel/cmdline)"
U_BOOT_TIMEOUT="20" 
EOF

rm -f /var/lib/dbus/machine-id
true > /etc/machine-id
touch /var/log/syslog
chown root:adm /var/log/syslog
ssh-keygen -A
# Установка собранного ванильного ядраif [ "$(ls -A kernel/)" ]; then
    dpkg -i kernel/*.debfi
cd / && rm -rf kernel
# Удаление конфликтующих утилит
apt-get -y purge cloud-init flash-kernel fwupd ufw grub-efi-arm64 || true
apt-get -y autoremove
apt-get clean
sync
