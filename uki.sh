#!/bin/bash

set -ueo pipefail

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


### To use kernel install
cat /etc/kernel/install.conf
layout=uki

cp /usr/lib/kernel/uki.conf /etc/kernel/

### Install systemd-boot
bootctl install

### Add boot entry to UEFI
udo efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "ArchLinux" --loader "\EFI\Linux\arch-linux.efi" --unicode