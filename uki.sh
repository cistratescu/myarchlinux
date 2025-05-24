#!/bin/bash

set -ueo pipefail

###################################################################################################
### How to Unified Kernel Image (UKI)
###################################################################################################

### Generate initramfs (including CPU microcode)
# - mkinitcpio [*]
# - dracut
# - booster

### Assemble UKI
# - mkinitcpio
# - ukify [*]
# Contains:
# - EFI boot stub
# - Kernel
# - Initramfs + microcode
# - Splash image
# - Linux cmdline
# - OS release info

### Sign the UKI

### Install the UKI
# Location: /efi/EFI/Linux/
# - mkinitcpio [*]
# - ukify (with explicit path and options)
# - kernel-install

### mkinitcpio configuration
#
# /etc/mkinitcpio.d/linux.preset
#+-----------------------------------------------------------------------------
#|# mkinitcpio preset file for the 'linux' package
#|
#|#ALL_config="/etc/mkinitcpio.conf"
#|ALL_kver="/boot/vmlinuz-linux"
#|
#|PRESETS=('default' 'fallback')
#|
#|#default_config="/etc/mkinitcpio.conf"
#|default_image="/boot/initramfs-linux.img"
#|default_uki="esp/EFI/Linux/arch-linux.efi"
#|default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
#|
#|#fallback_config="/etc/mkinitcpio.conf"
#|#fallback_image="/boot/initramfs-linux-fallback.img"
#|fallback_uki="esp/EFI/Linux/arch-linux-fallback.efi"
#|fallback_options="-S autodetect --cmdline /etc/kernel/cmdline_fallback"
#+-----------------------------------------------------------------------------
#
# /etc/kernel/cmdline
#+-----------------------------------------------------------------------------
#|rd.luks.name=7af0fc85-a88f-4d8d-9cc0-afa4af298af9=cryptroot root=/dev/mapper/cryptroot rootfstype=btrfs loglevel=3 quiet zswap.enabled=1 zswap.compressor=lz4
#+-----------------------------------------------------------------------------
# /etc/kernel/cmdline_fallback
#+-----------------------------------------------------------------------------
#|rd.luks.name=7af0fc85-a88f-4d8d-9cc0-afa4af298af9=cryptroot root=/dev/mapper/cryptroot rootfstype=btrfs
#+-----------------------------------------------------------------------------
#
# Or add drop-ins in: /etc/cmdline.d/
###################################################################################################


pacman -S systemd-ukify

# Add cmdline
/etc/kernel/cmdline
/etc/kernel/cmdline_fallback

# Drop-ins are in
# /etc/cmdline.d/

# Edit the preset file
/etc/mkinitcpio.d/linux.preset

mkdir -p /efi/EFI/Linux
mkinitcpio -P 

rootflags=defaults,subvol="@./snapshots/95/snapshot"

### To use kernel-install
cat /etc/kernel/install.conf
layout=uki

### For systemd-ukify
cp /usr/lib/kernel/uki.conf /etc/kernel/

### Install systemd-boot
bootctl install

### Manually Add boot entry to UEFI
efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "ArchLinux" --loader "\EFI\Linux\arch-linux.efi" --unicode

# mkinitcpio and dracut generate combined initramfs files by default.
# Tip: You can optionally add boot/*-ucode.img to NoExtract in /etc/pacman.conf, since the microcode files will be picked up directly from /usr/lib/firmware/*-ucode/.

### For mkpkg amm local arch optimization
/etc/makepkg.conf
CFLAGS="-march=native -O2 -pipe ..."
OPTIONS=(...!debug ...)
MAKEFLAGS="--jobs=$(nproc)"

/etc/makepkg.conf.d/rust.conf
RUSTFLAGS="-C opt-level=2 -C target-cpu=native"


### Try to makepkg from arch install
runuser -u nobody makepkg -si
arch-chroot -u nobody /mnt makepkg -si


### Use limine???
