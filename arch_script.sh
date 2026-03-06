#!/usr/bin/env bash

set -e
if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi
echo "==== ARCH INSTALL SCRIPT ===="
umount -R /mnt 2>/dev/null || true

echo "Available disks:"
lsblk -o NAME,SIZE,TYPE,FSTYPE
read -p "Disk to install to (ex: nvme0n1): " DISK
EFI=${DISK}p1
ROOT=${DISK}p2
if [[ $DISK == sd* ]]; then
  EFI=${DISK}1
  ROOT=${DISK}2
fi
echo "Partitioning disk..."
wipefs -af /dev/$DISK
parted /dev/$DISK --script \
 mklabel gpt \
 mkpart ESP fat32 1MiB 1GiB \
 set 1 esp on \
 mkpart ROOT btrfs 1GiB 100%
echo "Formatting..."
mkfs.fat -F32 /dev/$EFI
mkfs.btrfs -f /dev/$ROOT

echo "Creating BTRFS subvolumes..."
mount /dev/$ROOT /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt
echo "Mounting subvolumes..."
mount -o compress=zstd,subvol=@ /dev/$ROOT /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o compress=zstd,subvol=@home /dev/$ROOT /mnt/home
mount -o compress=zstd,subvol=@log /dev/$ROOT /mnt/var/log
mount -o compress=zstd,subvol=@pkg /dev/$ROOT /mnt/var/cache/pacman/pkg
mount -o compress=zstd,subvol=@snapshots /dev/$ROOT /mnt/.snapshots
mount /dev/$EFI /mnt/boot

echo "Optimizing mirrors..."
pacman -Sy --noconfirm reflector
reflector \
 --latest 20 \
 --sort rate \
 --save /etc/pacman.d/mirrorlist
echo "Installing base system..."
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
 snapper \
 htop \
 fastfetch \
 bluez \
 bluez-utils \
 grub \
 efibootmgr \
 mtools \
 dosfstools

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Entering chroot..."
arch-chroot /mnt /bin/bash <<EOF

echo "Setting timezone"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "Locales"
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Hostname"
echo archlinux > /etc/hostname
echo "Hosts"
cat >> /etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 archlinux.localdomain archlinux
HOSTS

echo "Root password"
passwd
echo "Creating user"
read -p "Username: " USERNAME
useradd -m -G wheel,audio,video,storage,power -s /bin/bash \$USERNAME
passwd \$USERNAME
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "Enabling basic services"
systemctl enable NetworkManager
systemctl enable bluetooth

echo "Installing CPU microcode"
if grep -q "Intel" /proc/cpuinfo; then
 pacman -S --noconfirm intel-ucode
elif grep -q "AMD" /proc/cpuinfo; then
 pacman -S --noconfirm amd-ucode
fi

echo "Checking for NVIDIA GPU"
if lspci | grep -i nvidia; then
 pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
fi

echo "Installing GRUB bootloader"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

#echo "Setup snapper"
#snapper --no-dbus -c root create-config /
#systemctl enable snapper-timeline.timer
#systemctl enable snapper-cleanup.timer

read -p "Install a Desktop Environment? (KDE Plasma will be used) (y/n)" ENABLE_KDE
if [[ "${ENABLE_KDE,,}" == "y" || "${ENABLE_KDE,,}" == "yes" ]]; then
 pacstrap /mnt plasma sddm konsole dolphin --noconfirm
 arch-chroot /mnt systemctl enable sddm
fi

read -p "Enable SSH server? (y/n): " ENABLE_SSH
if [[ "${ENABLE_SSH,,}" == "y" || "${ENABLE_SSH,,}" == "yes" ]]; then
  pacstrap /mnt openssh --noconfirm
  arch-chroot /mnt systemctl enable sshd
fi

read -p "Download optional config script via curl? (y/n): " ENABLE_CURL
if [[ "${ENABLE_CURL,,}" == "y" || "${ENABLE_CURL,,}" == "yes" ]]; then
  curl -L https://raw.githubusercontent.com/sadako-yamamura/arch/refs/heads/main/install_optionals.sh \
  -o /mnt/home/\$(ls /mnt/home)/install_optionals.sh
  chmod +x /mnt/home/\$(ls /mnt/home)/install_optionals.sh
fi

echo "Finished and rebooting in 5 seconds..."
umount -lR /mnt
sleep 5
reboot
