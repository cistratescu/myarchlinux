# Arch install guide

## 1. Pre-installation

---

### 1.1 Download an installation image

Check the <https://archlinux.org/download/> page.

### 1.2 VERIFY SIGNATURE

```bash
sha256sum archlinux-x86_64.iso
```

### 1.3 Prepare an instalation medium

```bash
lsblk -pd
dd if=archlinux-x86-64.iso of=/dev/sdX bs=4M conv=fdatasync status=progress
```

### 1.4 Boot the live environment

Device dependent. Typically it is achieved by pressing a specific key during the POST phase.

### 1.5 Set the console keyboard layout and font

```bash
# localectl list-keymaps
# loadkeys de-latin1
# setfont ter-132b
```

### 1.6 Verify the boot mode

If using a virtual machine, make sure to set the firmware to UEFI.

```bash
cat /sys/firmware/efi/fw_platform_size
# 64 -> x64 UEFI (good)
# 32 -> IA32 UEFI (ok, with caveats)
# No such file or directory -> Legacy BIOS
```

### 1.7 Connect to the internet

```bash
ip addr show
iwctl device list
iwctl station NAME scan
iwctl station NAME get-networks
iwctl station NAME connect SSID
# iwctl station NAME connect-hidden SSID
ping archlinux.org
```

#### Setup ssh access

```bash
passwd
systemctl start sshd
ssh root@192.168.1.10 # From another PC
```

### 1.8 Update the system clock

```bash
timedatectl
```

### 1.9 Partion the disks

```bash
fdisk -l

MY_DISK=/dev/vda

wipefs -af $MY_DISK
sgdisk -Zo $MY_DISK

sgdisk -n 1:1M:+1G -c 1:ESP -t 1:ef00 $MY_DISK
sgdisk -n 2:0:0 -c 2:CRYPTROOT -t 2:8309 $MY_DISK
sgdisk -p $MY_DISK

ESP="/dev/disk/by-partlabel/ESP"
CRYPTROOT="/dev/disk/by-partlabel/CRYPTROOT"

partprobe "$MY_DISK"
```

#### Create a LUKS container for the root partition

```bash
MY_LUKSPASS=password

# The defaults for LUKS 2 are not suported by GRUB; we will pick "pbkdf2"
echo -n "$MY_LUKSPASS" | cryptsetup luksFormat --type luks2 --hash sha256 --pbkdf pbkdf2 "$CRYPTROOT" -d -
echo -n "$MY_LUKSPASS" | cryptsetup luksOpen "$CRYPTROOT" cryptroot -d -

BTRFS="/dev/mapper/cryptroot"
```

### 1.10 Format the partitions

```bash
mkfs.fat -F 32 $ESP
mkfs.btrfs $BTRFS
```

#### Create BTRFS subvolumes

This is an openSUSE inspired subvolume layout.

```bash
mount -v "$BTRFS" /mnt

btrfs filesystem label /mnt ARCH
btrfs filesystem show /mnt

# Non root subvolumes
SUBVOLUMES=(
    "var"
    "usr/local"
    "srv"
    "root"
    "opt"
    "home"
    "boot/grub"
)

for dir in "${SUBVOLUMES[@]}"; do
    btrfs subvolume create -p /mnt/$dir
done

btrfs subvolume create -p snapshots
btrfs subvolume create -p snapshots/1/snapshot

btrfs subvolume set-default /mnt/snapshots/1/snapshot
btrfs subvolume get-default /mnt/

chattr -VR +C /mnt/var

umount -Rv /mnt
```

### 1.11 Mount the file systems

```bash
mount -v $BTRFS /mnt
for dir in "${SUBVOLUMES[@]}"; do
    mount -vm -o subvol="$dir" "$BTRFS" /mnt/"$dir"
done
mount -vm $ESP /mnt/efi/

# Check the mounted rootfs
find /mnt
```

## 2. Installation

---

### 2.1 Select the mirrors

```bash
grep "Server =" /etc/pacman.d/mirrorlist | head -n 10
```

### 2.2 Install the required packages and some extras

```bash
kernel="linux" # Other options: linux-hardened, linux-lts, linux-rt, linux-rt-lts

cpu=$(grep vendor_id /proc/cpuinfo | head -n 1)
[[ "$cpu" == *"GenuineIntel"* ]] && microcode="intel-ucode"
[[ "$cpu" == *"AuthenticAMD"* ]] && microcode="amd-ucode"

essential="base $kernel linux-firmware $microcode"
required="base-devel efibootmgr grub btrfs-progs inotify-tools snapper snap-pac grub-btrfs networkmanager reflector plocate rsync zram-generator"
extra="bash-completion openssh git vim man-db man-pages"
pacstrap -K /mnt $(echo $essential) $(echo $required) $(echo $extra)
```

## 3. Configure the system

---

### 3.1 Fstab

```bash
# Automatic way
# genfstab -U /mnt >> /mnt/etc/fstab

# I will do it "manually" since I need to alter the genfstab output anyway
BTRFS_UUID=$(blkid -s UUID -o value $BTRFS)
ESP_UUID=$(blkid -s UUID -o value $ESP)

maxlen="$(printf '/%s\n' ".snapshots" "${SUBVOLUMES[@]}" | wc -L)" # Accounts for .snapshot mount point
maxlen2="$(printf '/%s\n' "snapshots" "${SUBVOLUMES[@]}" | wc -L)"
maxlen2="$(($maxlen2+6))" # Accounts for "subvol="

# printf "\n" >> /mnt/etc/fstab
printf "%-41s  %-${maxlen}s  btrfs  %-${maxlen2}s  0  0\n" "UUID=${BTRFS_UUID}" "/" "defaults" >> /mnt/etc/fstab
for dir in "${SUBVOLUMES[@]}"; do
    printf "%-41s  %-${maxlen}s  btrfs  %-${maxlen2}s  0  0\n" "UUID=${BTRFS_UUID}" "/${dir}" "subvol=${dir}" >> /mnt/etc/fstab
done
printf "%-41s  %-${maxlen}s  vfat   %-${maxlen2}s  0  2\n" "UUID=${ESP_UUID}" "/efi" "utf8" >> /mnt/etc/fstab
printf "%-41s  %-${maxlen}s  btrfs  %-${maxlen2}s  0  0\n" "UUID=${BTRFS_UUID}" "/.snapshots" "subvol=snapshots" >> /mnt/etc/fstab
```

### 3.2 Chroot

I will call arch-chroot when needed. Makes it easier to turn this doc into an automated script.

### 3.3 Time

```bash
arch-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/$(curl -s "http://ip-api.com/line?fields=timezone") /etc/localtime
hwclock --systohc
EOF
```

### 3.4 Localization

```bash
locale="en_US.UTF-8"
layout="us"

sed -i "/^#$locale/s/^#//" /mnt/etc/locale.gen
echo "LANG=$locale" > /mnt/etc/locale.conf
echo "KEYMAP=$layout" > /mnt/etc/vconsole.conf

arch-chroot /mnt locale-gen
```

### 3.5 Network configuration

```bash
MY_HOSTNAME=arch
echo "$MY_HOSTNAME" > /mnt/etc/hostname
echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $MY_HOSTNAME" >> /mnt/etc/hosts

systemctl enable NetworkManager --root=/mnt
```

### 3.6 Initramfs

#### Create LUKS keyfile (avoid having to input password 2 times)

```bash
KEYFILE="etc/cryptsetup-keys.d/cryptroot.key"
dd bs=512 count=4 if=/dev/random iflag=fullblock | install -m 0600 /dev/stdin /mnt/$KEYFILE
cryptsetup luksAddKey $CRYPTROOT /mnt/$KEYFILE
```

```bash
# Busybox based (use if you want grub-btrfs-overlayfs)
# hooks="base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck grub-btrfs-overlayfs"

# Systemd based
hooks="base systemd keyboard autodetect microcode modconf kms sd-vconsole block sd-encrypt filesystems fsck"

sed -i "s,^HOOKS=.*,HOOKS=($hooks)," /mnt/etc/mkinitcpio.conf
sed -i "s,^FILES=.*,FILES=(/$KEYFILE)," /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

# Check btrfs module or add MODULES=(btrfs)
lsinitcpio -a /mnt/boot/initramfs-linux.img
```

### 3.7 Root password

```bash
MY_ROOTPASS=root
echo "root:$MY_ROOTPASS" | arch-chroot /mnt chpasswd
```

### 3.8 Bootloader

```bash
UUID=$(blkid -s UUID -o value $CRYPTROOT)

# Enable support for booting from encrypted disk
sed -i "s/^#GRUB_ENABLE_CRYPTODISK/GRUB_ENABLE_CRYPTODISK/" /mnt/etc/default/grub

# For the encrypt hook
# sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&cryptdevice=UUID=$UUID\:cryptroot cryptkey=rootfs\:/$KEYFILE root=$BTRFS rootfstype=btrfs," /mnt/etc/default/grub

# For systemd-cryptsetup-generator (only if using systemd based initramfs)
sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$BTRFS rootfstype=btrfs," /mnt/etc/default/grub

arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
```

#### Add convenience script to update grub.cfg

The GRUB version on Arch does not handle paths relative to the default btrfs root subvolume.
After `snapper rollback` we need to update the linux and initrd lines with the correct path.

```bash
cat > /usr/local/bin/grub-btrfs-subvol-update <<EOF
#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please rerun with 'sudo' or as root."
    exit 1
fi

GRUBCFG="/boot/grub/grub.cfg"

default_path=$(btrfs subvolume get-default / | awk -F'path ' '/path/ {print "/" $2}')
current_path=$(grep -oP '/snapshots/\d+/snapshot' $GRUBCFG | head -n1)

if [[ -z "$current_path" ]]; then
    echo "Could not find current root subvolume path in $GRUBCFG. Aborting."
    exit 1
fi

echo "Default root subvolume: $default_path"
echo "Current root subvolume: $current_path"

if [[ "$default_path" == "$current_path" ]]; then
    echo "The default root subvolume is already set in $GRUBCFG. No changes needed."
    exit 0
fi

read -rp "Update $GRUBCFG to use the default root subvolume? [Y/n] " confirm
confirm=${confirm:-Y}

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    cp $GRUBCFG $GRUBCFG.bak.$(date +%Y%m%d%H%M%S)

    escaped_old=$(echo "$current_path" | sed 's/[\/&]/\\&/g')
    escaped_new=$(echo "$default_path" | sed 's/[\/&]/\\&/g')
    sed -i "s/${escaped_old}/${escaped_new}/g" $GRUBCFG

    echo "Updated $GRUBCFG to use the default root subvolume."
else
    echo "Aborted. No changes made."
fi
EOF
chmod 755 /usr/local/bin/grub-btrfs-subvol-update
```

### Create user

```bash
MY_USERNAME=admin
MY_USERPASS=admin

echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$MY_USERNAME"
echo "$MY_USERNAME:$MY_USERPASS" | arch-chroot /mnt chpasswd

# Optional: install xdg-user-dirs to populate the common user directories on login
# pacstrap /mnt xdg-user-dirs
```

### ZRAM configuration

```bash
cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF
```

### Pacman colors

```bash
sed -i "s/^#Color/Color/" /mnt/etc/pacman.conf
```

### Install virtualization guest utils

```bash
hypervisor=$(systemd-detect-virt)
case $hypervisor in
    kvm) pacstrap /mnt qemu-guest-agent
         systemctl enable qemu-guest-agent --root=/mnt
         ;;
    vmware) pacstrap /mnt open-vm-tools >/dev/null
            systemctl enable vmtoolsd --root=/mnt
            systemctl enable vmware-vmblock-fuse --root=/mnt
            ;;
    oracle) pacstrap /mnt virtualbox-guest-utils
            systemctl enable vboxservice --root=/mnt
            ;;
    microsoft) pacstrap /mnt hyperv
               systemctl enable hv_fcopy_daemon --root=/mnt
               systemctl enable hv_kvp_daemon --root=/mnt
               systemctl enable hv_vss_daemon --root=/mnt
               ;;
esac
```

### Enable useful services

```bash
services=(reflector.timer grub-btrfsd.service systemd-oomd)
for service in "${services[@]}"; do
    systemctl enable "$service" --root=/mnt
done
```

### Move Pacman DB out of /var

By default, the Pacman files are stored at "/var/lib/pacman/".
Relocating them is required to keep the Pacman DB in sync on rollback, since we are excluding "/var" from snapshots.

(does not play well with pacstrap so doing this close to the end of the setup)

```bash
grep "DBPath" /mnt/etc/pacman.conf
sed -i "s,^#DBPath.*,DBPath       = /usr/lib/sysimage/pacman/," /mnt/etc/pacman.conf

mkdir -vp /mnt/usr/lib/sysimage/pacman
rsync -aAXHv --numeric-ids /mnt/var/lib/pacman/ /mnt/usr/lib/sysimage/pacman/

# After making sure the copy is fine delete the original
rm -rf /mnt/var/lib/pacman/
```

### Set-up Snapper

```bash
arch-chroot /mnt /bin/bash -e <<EOF
# umount -v /.snapshots
# rm -r /.snapshots
snapper --no-dbus -c root create-config /
snapper --no-dbus -c root set-config TIMELINE_CREATE=no
btrfs subvolume delete /.snapshots
mkdir /.snapshots

# Should mount the snapshots subvolume from fstab
mount -av

chmod 750 /.snapshots
EOF

systemctl disable snapper-timeline.timer snapper-cleanup.timer --root=/mnt

# Make plocate ignore the .snapshots directory
sed -i '/^PRUNENAMES *=/ s/"$/ .snapshots"/' /mnt/etc/updatedb.conf

# Register the root filesystem subvolume with snapper
cat <<EOF > /mnt/.snapshots/1/info.xml
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>$(date -u +"%F %T")</date>
  <description>first root filesystem</description>
</snapshot>
EOF
```

### Take an "after installation" snapshot

```bash
mkdir /mnt/.snapshots/2
cat <<EOF > /mnt/.snapshots/2/info.xml
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>2</num>
  <date>$(date -u +"%F %T")</date>
  <description>after installation</description>
</snapshot>
EOF
btrfs subvolume snapshot -r /mnt /mnt/.snapshots/2/snapshot

# Confirm that snapper registered the snapshot
arch-chroot /mnt snapper --no-dbus ls
```

## 4. Reboot

```bash
umount -Rv /mnt
reboot
```

## 5. Post-installation

If you got here, enjoy!

### Install an AUR helper

```bash
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

### Install the audio framework

Same as archinstall.

```bash
sudo pacman -S pipewire pipewire-alsa pipewire-jack pipewire-pulse gst-plugin-pipewire libpulse wireplumber
```

### Install desktop manager

For KDE Plasma. Same as archinstall.

```bash
sudo pacman -S plasma-meta konsole dolphin ark plasma-workspace
sudo pacman -S sddm
sudo systemctl enable sddm.service
```

### Install web browser

```bash
sudo pacman -S firefox
```
