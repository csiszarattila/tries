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
    
    config_kernel_build () {
        make tinyconfig
        
        # Enable 64-bit support (if on x86_64)
        scripts/config --enable 64BIT

        # Essential base: threads/sync (systemd aborts without FUTEX:
        # "The futex facility returned an unexpected error code.")
        ./scripts/config --enable FUTEX
        ./scripts/config --enable FUTEX_PI
        ./scripts/config --enable EVENTFD
        ./scripts/config --enable PRINTK
        ./scripts/config --enable EARLY_PRINTK
        ./scripts/config --enable ACPI
        ./scripts/config --enable PCI

        # Serial Port and tty (console=ttyS0)
        ./scripts/config --enable SERIAL_8250
        ./scripts/config --enable SERIAL_8250_CONSOLE
        ./scripts/config --enable TTY
        
        # EFI support
        ./scripts/config --enable EFI
        ./scripts/config --enable EFI_STUB

        # Filesystems
        ./scripts/config --enable BLOCK
        ./scripts/config --enable BLK_DEV
        ./scripts/config --enable PROC_FS
        ./scripts/config --enable SYSFS
        ./scripts/config --enable TMPFS
        ./scripts/config --enable DEVTMPFS 
        ./scripts/config --enable DEVTMPFS_MOUNT 
        ./scripts/config --enable MULTIUSER
        ./scripts/config --enable SECURITY
        ./scripts/config --enable AUDIT
        ./scripts/config --enable TMPFS_POSIX_ACL
        ./scripts/config --enable FILE_LOCKING

        # Init script bin format
        ./scripts/config --enable BINFMT_SCRIPT
        ./scripts/config --enable BINFMT_ELF

        # VirtIO Bus
        ./scripts/config --enable VIRTIO
        ./scripts/config --enable VIRTIO_MENU
        ./scripts/config --enable VIRTIO_BLK
        ./scripts/config --enable VIRTIO_PCI
        ./scripts/config --enable VIRTIO_MMIO
        ./scripts/config --enable VIRTIO_NET

        # Initramfs
        ./scripts/config --enable BLK_DEV_INITRD
        ./scripts/config --enable RD_GZIP
        ./scripts/config --enable INITRAMFS_COMPRESSION_GZIP
        ./scripts/config --enable INITRAMFS_PRESERVE_MTIME

        # Networking
        ./scripts/config --enable NET
        ./scripts/config --enable INET
        ./scripts/config --enable PACKET
        ./scripts/config --enable NETDEVICES
        ./scripts/config --enable ETHERNET
        ./scripts/config --enable UNIX

        # Namespaces (symbol is CONFIG_NAMESPACES, plural)
        ./scripts/config --enable NAMESPACES
        ./scripts/config --enable UTS_NS
        ./scripts/config --enable IPC_NS
        ./scripts/config --enable PID_NS
        ./scripts/config --enable NET_NS
        ./scripts/config --enable USER_NS

        # cgroups
        ./scripts/config --enable CGROUPS

        # systemd needs these specific kernel features
        scripts/config --enable INOTIFY_USER
        scripts/config --enable SIGNALFD
        scripts/config --enable TIMERFD
        scripts/config --enable EPOLL
        scripts/config --enable FHANDLE
        scripts/config --enable FANOTIFY
        scripts/config --enable AUTOFS_FS
        scripts/config --enable PROC_SYSCTL
        scripts/config --enable RSEQ
        scripts/config --enable MEMBARRIER
        scripts/config --enable SECCOMP
        scripts/config --enable SECCOMP_FILTER

        # Wireless & Bluetooth support
        ./scripts/config --disable IPV6
        ./scripts/config --disable WIRELESS
        ./scripts/config --disable WLAN
        ./scripts/config --disable WIRELESS_EXT
        ./scripts/config --disable CFG80211
        ./scripts/config --disable MAC80211
        ./scripts/config --disable BT
        ./scripts/config --disable RFKILL
        ./scripts/config --disable SOUND

        make olddefconfig
    }

    config_kernel_build

    make -j$(nproc) bzImage
}

function build_systemd()
{
    cd "$BUILD"
    
    if [ ! -d systemd ]; then
        wget https://github.com/systemd/systemd-stable/archive/refs/tags/v255.22.tar.gz
        tar -xf v255.22.tar.gz
        mv systemd-stable-255.22 systemd
    fi

    cd "$BUILD/systemd"

    meson setup build \
        --prefix=/usr \
        --buildtype=release \
        -Dmode=release \
        -Dwerror=false \
        -Dman=disabled \
        -Dhtml=disabled \
        -Dtests=false \
        -Dinitrd=true \
        -Dfirst-boot-full-preset=false \
        -Dopenssl=disabled \
        -Dnss-systemd=false \
        -Dnss-myhostname=false \
        -Dnss-resolve=disabled \
        -Dnss-mymachines=disabled \
        -Dldconfig=false \

    meson compile -C build
    DESTDIR=$BUILD/systemd-build meson install -C build
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
    sed -i 's/# CONFIG_INSTALL is not set/CONFIG_INSTALL=y/' .config
    sed -i 's/# CONFIG_BUSYBOX is not set/CONFIG_BUSYBOX=y/' .config
    sed -i 's/# CONFIG_FEATURE_INSTALLER is not set/CONFIG_FEATURE_INSTALLER=y/' .config

    make oldconfig
    make -j$(nproc)
}

function create_initramfs()
{
    RAMFS="$BUILD/initramfs"
    rm -rf $RAMFS

    # Layout. We're building a HOST systemd, so all binaries already link
    # against /usr/lib (with RPATH $ORIGIN/../..) and /lib64/ld-linux-x86-64.so.2.
    # No patchelf, no stripping, no nix-store hacks: copy verbatim and supply the
    # loader at the path the interpreter requests.
    mkdir -p "$RAMFS"/{bin,dev,proc,sys,run,etc,lib64}
    mkdir -p "$RAMFS"/usr/{bin,lib}
    mkdir -p "$RAMFS"/usr/lib/{systemd,systemd/system}
    
    cp -a /lib64/ld-linux-x86-64.so.2 "$RAMFS/lib64/"

    # glibc + libgcc are needed explicitly because ldd resolves them
    # against the host and never considers them "missing".
    cp -a /usr/lib/libc.so.6   "$RAMFS/usr/lib/"
    cp -a /usr/lib/libgcc_s.so.1 "$RAMFS/usr/lib/"

    install_busybox() {
        cp "$BUILD/busybox/busybox" "$RAMFS/usr/bin/busybox"

        for applet in $("$BUILD/busybox/busybox" --list); do
            ln -s busybox "$RAMFS/usr/bin/$applet"
        done
    }

    install_systemd() {
        SYSD_SRC="$BUILD/systemd-build"
        # Copy all shared libraries the systemd binary needs.
        # Resolve the closure once via ldd on the BUILD-tree binary
        # (not the initramfs one, whose $ORIGIN-relative RPATH only
        # works under /usr/lib/systemd in the build dir), then copy
        # every absolute path ldd reports.
        ldd "$SYSD_SRC/usr/lib/systemd/systemd" 2>/dev/null \
            | awk '/=> \// {print $3; next} /^\// {print $1}' \
            | while read -r lib; do
                [ -f "$lib" ] || continue
                b=$(basename "$lib")
                [ -e "$RAMFS/usr/lib/$b" ] && continue
                cp -L "$lib" "$RAMFS/usr/lib/"
              done

        sysd_files=(
            "$SYSD_SRC"/usr/lib/systemd/libsystemd-core-255.so
            "$SYSD_SRC"/usr/lib/systemd/libsystemd-shared-255.so
            "$SYSD_SRC"/usr/lib/systemd/systemd-executor
        )

        for sysd in "${sysd_files[@]}"; do
            cp -L "$sysd" "$RAMFS/usr/lib/systemd/"

            ldd "$sysd" 2>/dev/null \
                | awk '/=> \// {print $3; next} /^\// {print $1}' \
                | while read -r lib; do
                    [ -f "$lib" ] || continue
                    b=$(basename "$lib")
                    [ -e "$RAMFS/usr/lib/$b" ] && continue
                    cp -L "$lib" "$RAMFS/usr/lib/"
                  done
        done

        ln -sf usr/lib/systemd/systemd "$RAMFS/init"

        # Full tree: helpers (journald, udevd, ...), generators, units, generators.
        # The tree contains relative symlinks (e.g. lib/systemd/systemd-udevd
        # -> ../../bin/udevadm) so /usr/bin from the build must come along.
        cp -a "$SYSD_SRC/usr/lib/systemd/systemd" "$RAMFS/usr/lib/systemd/"
        #cp -a "$SYSD_SRC/usr/bin/." "$RAMFS/usr/bin/"

        # Public libs shipped by the installed systemd tree. The ldd
        # closure above already brought in the external deps (glibc,
        # libaudit, libkmod, ...), but the internal ones (libsystemd,
        # libudev, libnss_*) live here in usr/lib.
        cp -a "$SYSD_SRC/usr/lib"/libsystemd.so* "$RAMFS/usr/lib/"
        #cp -a "$SYSD_SRC/usr/lib"/libudev.so* "$RAMFS/usr/lib/"
        #[ -d "$SYSD_SRC/usr/lib/udev" ]             && cp -a "$SYSD_SRC/usr/lib/udev"           "$RAMFS/usr/lib/"
        #[ -d "$SYSD_SRC/usr/lib/tmpfiles.d" ]       && cp -a "$SYSD_SRC/usr/lib/tmpfiles.d"     "$RAMFS/usr/lib/"
        #[ -d "$SYSD_SRC/usr/lib/sysusers.d" ]       && cp -a "$SYSD_SRC/usr/lib/sysusers.d"     "$RAMFS/usr/lib/"
        #[ -d "$SYSD_SRC/usr/lib/modules-load.d" ]   && cp -a "$SYSD_SRC/usr/lib/modules-load.d" "$RAMFS/usr/lib/"
        #[ -d "$SYSD_SRC/usr/lib/sysctl.d" ]         && cp -a "$SYSD_SRC/usr/lib/sysctl.d"       "$RAMFS/usr/lib/"
        #[ -d "$SYSD_SRC/usr/lib/binfmt.d" ]         && cp -a "$SYSD_SRC/usr/lib/binfmt.d"       "$RAMFS/usr/lib/"

        # Config so PID 1 detects initrd mode and loads the right units.
        # cp -a "$SYSD_SRC/etc/systemd" "$RAMFS/etc/"
        # cp -a "$SYSD_SRC/etc/udev"    "$RAMFS/etc/"
        
        cp -a "$SYSD_SRC/usr/lib/systemd/system/initrd.target" "$RAMFS/usr/lib/systemd/system/"
        cp -a "$SYSD_SRC/usr/lib/systemd/system/emergency.target" "$RAMFS/usr/lib/systemd/system/"
        cp -a "$SYSD_SRC/usr/lib/systemd/system/emergency.service" "$RAMFS/usr/lib/systemd/system/"
        cp -a "$SYSD_SRC/usr/lib/systemd/system/rescue.target" "$RAMFS/usr/lib/systemd/system/"
        cp -a "$SYSD_SRC/usr/lib/systemd/system/rescue.service" "$RAMFS/usr/lib/systemd/system/"
    
    cat <<EOF > "$RAMFS/usr/lib/systemd/system/default.service"
[Unit]
Description=Saját RAM-OS Shell Indító
DefaultDependencies=no
After=sysinit.target
Wants=sysinit.target

[Service]
Environment=HOME=/ TERM=linux
WorkingDirectory=/
ExecStart=-/usr/bin/sh
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/console
TTYReset=yes
TTYVHangup=yes
Type=idle

[Install]
WantedBy=default.target
EOF

    cat <<EOF > "$RAMFS/etc/os-release"
NAME="HyprOS"
VERSION="2026.9"
ID=hypros
VERSION_ID=2026.9
VERSION_CODENAME="aenea"
EOF
        touch "$RAMFS/etc/initrd-release"
    }

    install_busybox
    install_systemd

    cd $RAMFS
    find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$BUILD/initramfs.cpio.gz"
}

function create_disk()
{
    build_uki_efi() {
        mkdir -p "$BUILD/esp/EFI/Linux/"

        ukify build \
            --linux="$BUILD/kernel/arch/x86/boot/bzImage" \
            --initrd="$BUILD/initramfs.cpio.gz" \
            --cmdline="systemd.log_level=debug systemd.log_target=console console=ttyS0 earlyprintk=serial,ttyS0,115200 loglevel=7 rootfstype=tmpfs" \
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
        cp "$(nix-build '<nixpkgs>' -A systemd.boot)/lib/systemd/boot/efi/systemd-bootx64.efi" "$BUILD/esp/EFI/BOOT/BOOTX64.EFI"

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
        local root_bytes
        root_bytes=$(parted -m "$disk_img" unit B print | awk -F: '$1==2 {print $4}' | tr -d 'B')
        dd if=/dev/zero of="$root_img" bs=1 count=0 seek="$root_bytes"   # sparse-allocate exact size
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

function runB() {
    OVMF_PATH=$(nix-build '<nixpkgs>' -A OVMF.fd --no-out-link)

    cp "$BUILD/disk/disk.img" "$BUILD/disk/diskB.img"

    qemu-system-x86_64 -m 2048M \
        -kernel "$BUILD/kernel/arch/x86/boot/bzImage" \
        -initrd "$BUILD/initramfs.cpio.gz" \
        -append "systemd.log_level=debug systemd.log_target=console console=ttyS0 earlyprintk=serial,ttyS0,115200 loglevel=7 rootfstype=tmpfs rd.systemd.unit=default.service" \
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
        --build-systemd)
            build_systemd
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
        --runB)
            runB
            shift 1
            ;;
        *)
            exit 1
            ;;
        esac
done
