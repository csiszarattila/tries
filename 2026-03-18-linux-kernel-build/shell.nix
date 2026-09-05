{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    coreutils
    cpio
    glibc.static
    dosfstools
    mtools
    e2fsprogs
    parted
    qemu
    systemd
    systemdUkify
    OVMF
  ];
  
  OVMF_PATH = "${pkgs.OVMF.fd}";
}

