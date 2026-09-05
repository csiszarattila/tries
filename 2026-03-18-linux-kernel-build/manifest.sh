#!/usr/bin/env bash

set -euo pipefail

ROOT="$(pwd)"
BUILD="$ROOT/build"

function build_linux()
{
    cd "$BUILD/linux"

    config_linux_build () {
        #make tinyconfig

        # Basic system and EFI setup
        ./scripts/config --enable 64BIT
        ./scripts/config --enable ACPI
        ./scripts/config --enable EFI
        ./scripts/config --enable EFI_STUB
        ./scripts/config --enable PROC_FS
        ./scripts/config --enable SYSFS
        ./scripts/config --enable BINFMT_SCRIPT
        ./scripts/config --enable BINFMT_ELF

        # Initramfs with only GZIP support
        ./scripts/config --enable BLK_DEV_INITRD
        ./scripts/config --enable RD_GZIP
        ./scripts/config --enable CONFIG_INITRAMFS_COMPRESSION_GZIP
        ./scripts/config --enable INITRAMFS_PRESERVE_MTIME

        # Disable other algorithms to save space
        ./scripts/config --disable RD_BZIP2
        ./scripts/config --disable RD_LZMA
        ./scripts/config --disable RD_XZ
        ./scripts/config --disable RD_LZO
        ./scripts/config --disable RD_LZ4
        ./scripts/config --disable RD_ZSTD

        # Disable other initramfs compressions
        ./scripts/config --disable INITRAMFS_COMPRESSION_NONE
        ./scripts/config --disable INITRAMFS_COMPRESSION_BZIP2
        ./scripts/config --disable INITRAMFS_COMPRESSION_LZMA
        ./scripts/config --disable INITRAMFS_COMPRESSION_XZ
        ./scripts/config --disable INITRAMFS_COMPRESSION_LZO
        ./scripts/config --disable INITRAMFS_COMPRESSION_LZ4
        ./scripts/config --disable INITRAMFS_COMPRESSION_ZSTD

        # Soros port és TTY konzol támogatása (console=ttyS0)
        ./scripts/config --enable CONFIG_SERIAL_8250
        ./scripts/config --enable CONFIG_SERIAL_8250_CONSOLE
        ./scripts/config --enable CONFIG_TTY

        # Korai kernel üzenetek soros porton (earlyprintk=serial,ttyS0,115200)
        ./scripts/config --enable CONFIG_EARLY_PRINTK

        # Beépített RAMFS / TMPFS támogatás (rootfstype=ramfs)
        ./scripts/config --enable CONFIG_RAMFS
        ./scripts/config --enable CONFIG_TMPFS

        # Kernel log szint és debug opciók (loglevel=7)
        ./scripts/config --enable CONFIG_PRINTK

        make olddefconfig
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

    cd $BUILD/busybox
    make allnoconfig

    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/# CONFIG_ASH is not set/CONFIG_ASH=y/' .config
    sed -i 's/# CONFIG_MOUNT is not set/CONFIG_MOUNT=y/' .config
    sed -i 's/# CONFIG_ECHO is not set/CONFIG_ECHO=y/' .config
    sed -i 's/# CONFIG_LS is not set/CONFIG_LS=y/' .config
    sed -i 's/# CONFIG_CAT is not set/CONFIG_CAT=y/' .config
    sed -i 's/# CONFIG_REBOOT is not set/CONFIG_REBOOT=y/' .config
    sed -i 's/# CONFIG_POWEROFF is not set/CONFIG_POWEROFF=y/' .config 
    # PS command
    sed -i 's/# CONFIG_PS is not set/CONFIG_PS=y/' .config
    sed -i 's/# CONFIG_FEATURE_PS_WIDE is not set/CONFIG_FEATURE_PS_WIDE=y/' .config
    sed -i 's/# CONFIG_FEATURE_PS_TIME is not set/CONFIG_FEATURE_PS_TIME=y/' .config
    #sed -i 's/# CONFIG_DESKTOP is not set/CONFIG_DESKTOP=y/' .config
    sed -i 's/# CONFIG_CTTYHACK is not set/CONFIG_CTTYHACK=y/' .config
    sed -i 's/# CONFIG_FEATURE_SHOW_THREADS is not set/CONFIG_FEATURE_SHOW_THREADS=y/' .config

    sed -i 's/# CONFIG_BLKID is not set/CONFIG_BLKID=y/' .config
    sed -i 's/# CONFIG_BLKID_TYPE is not set/CONFIG_BLKID_TYPE=y/' .config
    sed -i 's/# CONFIG_FDISK is not set/CONFIG_FDISK=y/' .config
    sed -i 's/# CONFIG_FDISK_SUPPORT_LARGE_DISKS is not set/CONFIG_FDISK_SUPPORT_LARGE_DISKS=y/' .config
    sed -i 's/# CONFIG_FEATURE_GPT_LABEL is not set/CONFIG_FEATURE_GPT_LABEL=y/' .config

    make oldconfig
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
            --linux="$BUILD/linux/arch/x86/boot/bzImage" \
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
        --build-linux)
            build_linux
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
