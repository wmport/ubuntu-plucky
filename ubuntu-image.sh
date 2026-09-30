#!/bin/bashset -eE
export LANGUAGE=C LC_ALL=C LANG=C
rm -rf build && mkdir build

mem_size=$(free --giga | grep Mem | awk '{print $2}')if [ $mem_size -gt 15 ]; then mount -t tmpfs -o size=13G tmpfs build; fi

snap install --classic ubuntu-image
ubuntu-image --debug --workdir build classic image-definition.yaml

rm -rf build/root
chmod +x setup-script.sh
cp setup-script.sh build/chroot/

setup_mountpoint() {
    local mountpoint="$1"
    if [ ! -c /dev/mem ]; then mknod -m 660 /dev/mem c 1 1; chown root:kmem /dev/mem; fi
    mount dev-live -t devtmpfs "$mountpoint/dev"
    mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
    mount proc-live -t proc "$mountpoint/proc"
    mount sysfs-live -t sysfs "$mountpoint/sys"
    mount securityfs -t securityfs "$mountpoint/sys/kernel/security"
    mount -t cgroup2 none "$mountpoint/sys/fs/cgroup"
    mount -t tmpfs none "$mountpoint/tmp"
    mount -t tmpfs none "$mountpoint/var/lib/apt/lists"
    mount -t tmpfs none "$mountpoint/var/cache/apt"
}

teardown_mountpoint() {
    local mountpoint=$(realpath "$1")
    mountpoint_match=$(echo "$mountpoint" | sed -e's,/$,,; s,/,\\/,g;')'\/'
    awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
        mount --make-private "$submount"
        umount "$submount"
    done
}

setup_mountpoint build/chroot
mkdir -p build/chroot/kernel
cp *.deb build/chroot/kernel/ 2>/dev/null || true

chroot build/chroot /setup-script.sh

teardown_mountpoint build/chroot
rm -f build/chroot/setup-script.sh
rm -rf build/chroot/kernel

rootfs="./ubuntu.rootfs.tar"
echo "rootfs=$rootfs" > rootfs
if [ -d build/chroot/lib/modules ]; then
    kernel_version=$(ls -1 build/chroot/lib/modules | head -n 1)else
    kernel_version=$(ls -1 build/chroot/boot/Image-* 2>/dev/null | head -n 1 | sed 's#.*/Image-##')fi
echo "kernel_version=$kernel_version" > kernel_version

cd build/chroot && tar -cf ../../$rootfs --xattrs ./*
cd ../..if [ $mem_size -gt 15 ]; then umount build; fi  
exit 0
