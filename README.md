# myarchlinux

## My Arch Linux installer

Included:

* Full disk encryption with LUKS2
* BTRFS filesystem with a snapshot compatible subvolume layout
* Filesystem snapshot support using the `snapper` tool
* GRUB bootloader with snapshot booting submenu
* Automatic snapshot creation upon a pacman transaction
* Swap configuration with swap file and zswap enabled
* Network configuration using `networkmanager`
* Minimal set of preinstalled tools and utilities such as:
    `openssh`, `git`, `vim`, `plocate`, `rsync`, `man-pages`

Not included:

* Desktop environment

Usage:

```bash
curl -Lo myarchlinux https://github.com/cistratescu/myarchlinux/archive/refs/heads/main.tar.gz \
&& tar -xzf myarchlinux \
&& rm myarchlinux \
&& chmod +x myarchlinux-main/install \
&& ./myarchlinux-main/install
```
