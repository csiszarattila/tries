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
    systemdUkify
    OVMF
  ];
  
#! nix-shell -p coreutils cpio glibc.static dosfstools e2fsprogs mtools parted qemu systemdUkify OVMF nix musl

  OVMF_PATH = "${pkgs.OVMF.fd}";
}

