#!/bin/bash

# Ensure you run the script as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# 1. Arch update
echo "Updating Arch and Keyring..."
pacman -Sy --noconfirm
pacman -Sy archlinux-keyring --noconfirm

# 2. Prepare disk partitions
echo "Listing available disks..."
lsblk

# You need to specify the disk and EFI partition manually or set it as a variable
read -p "Format disk (DATA WILL BE DELETED) (Partitions still needed)? (y/n): " is_format_disk
if [[ "${is_format_disk,,}" == "y" || "${is_format_disk,,}" == "yes" ]]; then
  read -p "Enter the disk to format (DATA WILL BE DELETED) (e.g., sda or nvme0n1): " disk
  # Wipe existing disk, partition it, and format
  echo "Wiping and partitioning $disk..."
  wipefs --all /dev/$disk
  parted /dev/$disk --script mklabel gpt
  parted /dev/$disk --script mkpart ESP fat32 1MiB 1025MiB
  parted /dev/$disk --script set 1 esp on
  parted /dev/$disk --script mkpart primary btrfs 1025MiB 100%
fi
# Get partition names (use lsblk to help identify the correct names)
read -p "Enter the EFI partition (e.g., nvme0n1p1): " efi_partition
read -p "Enter the root partition (e.g., nvme0n1p2): " root_partition

# Format partitions
echo "Formatting EFI and Root partitions..."
mkfs.fat -F32 /dev/$efi_partition
mkfs.btrfs -f /dev/$root_partition

# Mount the partitions
echo "Mounting the partitions..."
mount /dev/$root_partition /mnt
mount --mkdir /dev/$efi_partition /mnt/boot/efi

# 3. Install core packages
echo "Installing core packages..."
touch /mnt/etc/vconsole.conf
pacstrap -i /mnt base base-devel linux linux-firmware git sudo fastfetch htop nano bluez bluez-utils networkmanager --noconfirm

# Check CPU architecture for microcode (Intel vs AMD)
read -p "Enter CPU type (intel/amd): " cpu_type
if [[ "${cpu_type,,}" == "intel" ]]; then
  pacstrap -i /mnt intel-ucode --noconfirm
elif [[ "${cpu_type,,}" == "amd" ]]; then
  pacstrap -i /mnt amd-ucode --noconfirm
else
  echo "Unknown CPU type. Proceeding without microcode."
fi

# NVIDIA GPU drivers
echo "Looking for NVIDIA cards..." 
lspci | grep -E "NVIDIA|GeForce"
read -p "Install NVIDIA drivers? (y/n): " is_nvidia
if [[ "${is_nvidia,,}" == "y" || "${is_nvidia,,}" == "yes" ]]; then
  pacstrap -i /mnt linux-headers nvidia-utils nvidia-settings nvidia-dkms --noconfirm
fi

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# 4. Create and prepare users
echo "Creating user..."
arch-chroot /mnt /bin/bash -c "
  echo 'Set root password:'
  passwd

  read -p 'Enter your username: ' USER
  useradd -m -g users -G wheel,storage,power,video,audio -s /bin/bash \$USER
  echo 'Set user password for \$USER:'
  passwd \$USER

  sudo sed -i '/^#.*%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers
"

# 5. Configure locales
echo "Configuring en_US.UTF-8 locales..."
arch-chroot /mnt /bin/bash -c "
  sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
  locale-gen
  
  echo 'LANG=en_US.UTF-8' > /etc/locale.conf
  echo 'KEYMAP=us' > /etc/vconsole.conf
"

# 6. Install GRUB
echo "Installing GRUB..."
pacstrap -i /mnt grub efibootmgr dosfstools mtools --noconfirm
arch-chroot /mnt /bin/bash -c "
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg
"

# 7. Install KDE Plasma with Wayland
echo "Installing KDE Plasma with Wayland..."
pacstrap -i /mnt plasma wayland sddm dolphin kscreen breeze-gtk --noconfirm
# old xorg: pacstrap -i /mnt xorg sddm plasma-workspace dolphin cargo clang cmake make gcc noto-fonts noto-fonts-emoji ttf-dejavu --noconfirm

# Enable SDDM (KDE's Display Manager)
echo "Enabling basic services"
arch-chroot /mnt /bin/bash -c "
  systemctl enable NetworkManager
  systemctl enable bluetooth.service
  systemctl enable sddm
"

umount -lR /mnt

# 9. Reboot the system
echo "Finished and rebooting in 5 seconds..."
sleep 5
sudo shutdown -r
