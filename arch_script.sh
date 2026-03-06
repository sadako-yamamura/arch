#!/usr/bin/env bash

# ========================================= INTRO
set -e

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi
echo "========================================================="
echo "================== ARCH INSTALL SCRIPT =================="
echo "========================================================="
pacman -Syy --noconfirm
umount -R /mnt 2>/dev/null || true

# ========================================= DISK PARTITIONING
echo " ========== Available disks:"
lsblk -o NAME,SIZE,FSUSE%,TYPE,FSTYPE,MOUNTPOINTS,UUID
read -p " (i) Disk to install Arch to -! DATA WILL BE DELETED !- (ex: nvme0n1): " DISK
EFI=${DISK}p1
ROOT=${DISK}p2
if [[ $DISK == sd* ]]; then
  EFI=${DISK}1
  ROOT=${DISK}2
fi
echo " ========== Partitioning disk..."
wipefs -af /dev/$DISK
parted /dev/$DISK --script \
 mklabel gpt \
 mkpart ESP fat32 1MiB 1GiB \
 set 1 esp on \
 mkpart ROOT btrfs 1GiB 100%
echo "Formatting..."
mkfs.fat -F32 /dev/$EFI
mkfs.btrfs -f /dev/$ROOT

echo " ========== Creating BTRFS subvolumes..."
mount /dev/$ROOT /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt
echo " ========== Mounting subvolumes..."
mount -o compress=zstd:1,noatime,subvol=@ /dev/$ROOT /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o subvol=@home /dev/$ROOT /mnt/home
mount -o subvol=@log /dev/$ROOT /mnt/var/log
mount -o subvol=@pkg /dev/$ROOT /mnt/var/cache/pacman/pkg
mount -o subvol=@snapshots /dev/$ROOT /mnt/.snapshots
mount /dev/$EFI /mnt/boot

# ========================================= CORE PACKAGES
echo " ========== Optimizing mirrors..."
pacman -Sy --noconfirm reflector
reflector \
 --latest 20 \
 --sort rate \
 --save /etc/pacman.d/mirrorlist
echo " ========== Installing base system..."
pacstrap /mnt \
 base \
 base-devel \
 linux \
 linux-firmware \
 btrfs-progs \
 sudo \
 nano \
 git \
 networkmanager \
 htop \
 fastfetch \
 bluez \
 bluez-utils \
 grub \
 efibootmgr \
 mtools \
 dosfstools
#  snapper \
#  grub-btrfs

# ========================================= FSTAB
echo " ========== Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ========================================= LOCALES
echo " ========== Setting local timezone and en_US.UTF-8 locales"
arch-chroot /mnt /bin/bash -c "
 ln -sf /usr/share/zoneinfo/UTC /etc/localtime
 hwclock --systohc
 sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
 locale-gen
 echo 'LANG=en_US.UTF-8' > /etc/locale.conf
 echo 'KEYMAP=us' > /etc/vconsole.conf
"

# ========================================= HOSTNAMES
echo " ========== Setting hostname"
arch-chroot /mnt /bin/bash -c "
 echo archlinux > /etc/hostname
 cat >> /etc/hosts <<HOSTS
 127.0.0.1 localhost
 ::1 localhost
 127.0.1.1 archlinux.localdomain archlinux
 HOSTS
"

# ========================================= USERS
echo " ========== Insert root password"
passwd
echo " ========== Creating user"
read -p " (i) Username: " USERNAME
useradd -m -G wheel,audio,video,storage,power -s /bin/bash $USERNAME
passwd $USERNAME
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ========================================= HARDWARE AND DRIVERS
echo " ========== Installing CPU microcode"
if lscpu | grep -i intel; then
 pacstrap /mnt intel-ucode --noconfirm
elif lscpu | grep -i amd; then
 pacstrap /mnt amd-ucode --noconfirm
fi
echo " ========== Checking for NVIDIA GPU"
if lspci | grep -i nvidia; then
 pacstrap /mnt linux-headers nvidia-utils nvidia-settings nvidia-dkm --noconfirm
fi
arch-chroot /mnt /bin/bash -c "mkinitcpio -P"

# ========================================= BOOTLOADER
echo " ========== Installing GRUB bootloader"
arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"

lsblk -o NAME,SIZE,FSUSE%,TYPE,FSTYPE,MOUNTPOINTS,UUID
read -p " (i) Add second entry point to GRUB? (y/n): " ENABLE_DBOOT
if [[ "${ENABLE_DBOOT,,}" == "y" || "${ENABLE_DBOOT,,}" == "yes" ]]; then
 read -p " (i) Second EFI partition ((ex: nvme1n1p1)): " PART_DBOOT
 arch-chroot /mnt /bin/bash -c "
  mount --mkdir /dev/$PART_DBOOT /mnt/efi2
  pacman -S --noconfirm os-prober ntfs-3g
  sed -i 's/^#GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
  grep -q GRUB_DISABLE_OS_PROBER /etc/default/grub || echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
 "
fi
arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

# ========================================= ZRAM
arch-chroot /mnt bash -c '
 cat > /etc/systemd/zram-generator.conf <<EOF
 [zram0]
 zram-size = min(ram / 2, 8192)
 compression-algorithm = zstd
 swap-priority = 100
 EOF
 cat > /etc/sysctl.d/99-zram.conf <<EOF
 vm.swappiness=180
 vm.page-cluster=0
 EOF
'
arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service

# ========================================= SNAPPER
#echo "Setup snapper"
#snapper --no-dbus -c root create-config /
#systemctl enable snapper-timeline.timer
#systemctl enable snapper-cleanup.timer

# ========================================= DESKTOP
# TODO: xcfe as 2nd
read -p " (i) Install a Desktop Environment? (KDE Plasma will be used) (y/n)" ENABLE_KDE
if [[ "${ENABLE_KDE,,}" == "y" || "${ENABLE_KDE,,}" == "yes" ]]; then
 pacstrap /mnt plasma wayland sddm konsole dolphin kscreen kwrite breeze-gtk --noconfirm
 arch-chroot /mnt systemctl enable sddm
fi

# ========================================= SSH
read -p " (i) Enable SSH server? (y/n): " ENABLE_SSH
if [[ "${ENABLE_SSH,,}" == "y" || "${ENABLE_SSH,,}" == "yes" ]]; then
  pacstrap /mnt openssh --noconfirm
  arch-chroot /mnt systemctl enable sshd
fi

# ========================================= OPTIONAL SCRIPTS
read -p " (i) Download optional config script via curl? (y/n): " ENABLE_CURL
if [[ "${ENABLE_CURL,,}" == "y" || "${ENABLE_CURL,,}" == "yes" ]]; then
  curl -L https://raw.githubusercontent.com/sadako-yamamura/arch/refs/heads/main/install_optionals.sh \
  -o /mnt/home/\$(ls /mnt/home)/install_optionals.sh
  chmod +x /mnt/home/\$(ls /mnt/home)/install_optionals.sh
fi

# TODO ufw

# TODO lib32

# TODO yay

# ========================================= FINISING INSTALLATION
echo " ========== Enabling basic services"
arch-chroot /mnt /bin/bash -c "
 systemctl enable NetworkManager
 systemctl enable bluetooth
 systemctl enable fstrim.timer
"
echo " ========== Finished and rebooting in 5 seconds..."
umount -lR /mnt
sleep 5
reboot
