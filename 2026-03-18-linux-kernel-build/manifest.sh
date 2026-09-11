#!/usr/bin/env bash

set -euo pipefail

ROOT="$(pwd)"
BUILD="$ROOT/build"
SRC="$ROOT/src"

function build_kernel()
{
    cd "$BUILD"
    
    if [ ! -d kernel ]; then
        wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.4.tar.xz
        tar -xf linux-7.2.4.tar.xz
        mv linux-7.2.4 kernel
        rm -rf linux-7.2.4
    fi

    cd "$BUILD/kernel"
    
    config_linux_build () {
        if [ ! -f "$BUILD/kernel/defconfig" ]; then
            ln -s "$SRC/kernel/defconfig" "$BUILD/kernel/defconfig"
            make olddefconfig
        fi
    }

    config_linux_build

    make -j$(nproc) bzImage
}

function build_busybox()
{
    cd $BUILD
    if [ ! -d busybox ]; then
        wget https://busybox.net/downloads/busybox-1.38.0.tar.bz2
        tar xjf busybox-1.38.0.tar.bz2
        mv busybox-1.38.0 busybox
    fi

    cd "$BUILD/busybox"

    if [ ! -f "$BUILD/busybox/.config" ]; then
        cp "$SRC/busybox/config" "$BUILD/busybox/.config"
    fi

    make -j$(nproc)
}

function create_initramfs()
{
    RAMFS="$BUILD/initramfs"
    rm -rf $RAMFS

    cd $BUILD/busybox
    make CONFIG_PREFIX="$RAMFS" install
    
    cd $RAMFS
    mkdir -p bin dev proc sys

    hostname bbox

    cat << 'EOF' > init
#!/bin/sh

mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys

exec /bin/sh
EOF

    chmod +x init

    find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$BUILD/initramfs.cpio.gz"
}

function create_disk()
{
    build_uki_efi() {
        mkdir -p "$BUILD/esp/EFI/Linux/"

        ukify build \
            --linux="$BUILD/kernel/arch/x86/boot/bzImage" \
            --initrd="$BUILD/initramfs.cpio.gz" \
            --cmdline="console=ttyS0 earlyprintk=serial,ttyS0,115200 loglevel=7 rootfstype=ramfs" \
            --output="$BUILD/esp/EFI/Linux/vmlinux-uki.efi"
    }

    create_disk_img() {
        dd if=/dev/zero of=$disk_img bs=1M count=2048 status=progress
        parted --script $disk_img \
            mklabel gpt \
            mkpart ESP fat32 1MiB 512MiB \
            set 1 esp on \
            mkpart root ext4 512MiB 100%
    }

    make_esp_partition() {
        mkdir -p "$BUILD/esp/EFI/BOOT/"
        cp "$(nix-build '<nixpkgs>' -A systemd)/lib/systemd/boot/efi/systemd-bootx64.efi" "$BUILD/esp/EFI/BOOT/BOOTX64.EFI"

        mkdir -p "$BUILD/esp/loader/"
        cat <<EOF > "$BUILD/esp/loader/loader.conf"
timeout 15
console-mode max
EOF

        dd if=/dev/zero of=$esp_img bs=1M count=511
        mkfs.vfat -F32 "$esp_img"
        mcopy -i "$esp_img" -s "$BUILD/esp"/* ::/
    }

    make_root_partition() {
        dd if=/dev/zero of=$root_img bs=1M count=$((2048-511-1))
        
        mkfs.ext4 "$root_img"
    }

    write_partitions_to_disk() {
        dd if="$esp_img" of="$disk_img" bs=1M seek=1 conv=notrunc
        dd if="$root_img" of="$disk_img" bs=1M seek=512 conv=notrunc
    }
    
    local disk_img="$BUILD/disk/disk.img"
    local esp_img="$BUILD/disk/esp.img"
    local root_img="$BUILD/disk/root.img"

    rm -rf "$BUILD/esp"
    rm -rf "$BUILD/disk"
    mkdir -p "$BUILD/disk"
    mkdir -p "$BUILD/esp"

    build_uki_efi
    create_disk_img
    make_esp_partition
    make_root_partition
    write_partitions_to_disk
}

function run() {
    OVMF_PATH=$(nix-build '<nixpkgs>' -A OVMF.fd --no-out-link)

    qemu-system-x86_64 -m 2048M \
        -machine q35,firmware=$OVMF_PATH/FV/OVMF.fd \
        -drive file="$BUILD/disk/disk.img",if=virtio,format=raw \
        -netdev tap,id=net0,ifname=qemu-machineA,script=no,downscript=no \
        -device virtio-net-pci,netdev=net0 \
        -nographic
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-busybox)
            # NOTE: 
            #   not working with nix-shell, due to compile error with gcc
            #   call without nix-shell
            build_busybox
            shift 1
            ;;
        --build-kernel)
            build_kernel
            shift 1
            ;;
        --create-disk)
            create_disk
            shift 1
            ;;
        -i|--create-initramfs)
            create_initramfs
            shift 1
            ;;
        -r|--run)
            run
            shift 1
            ;;
        *)
            exit 1
            ;;
        esac
done
