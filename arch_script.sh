#!/bin/bash

# Ensure script as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Arch update
echo "Updating Arch and Keyring..."
pacman -Sy --noconfirm
pacman -Sy archlinux-keyring --noconfirm

# Prepare disk partitions
echo "Listing available disks..."
lsblk -f
read -p "Format a disk? (DATA OF THE SELECTED DISK WILL BE DELETED)? (y/n): " is_format_disk
if [[ "${is_format_disk,,}" == "y" || "${is_format_disk,,}" == "yes" ]]; then
  read -p "Enter the disk to format (DATA WILL BE DELETED) (e.g., sda or nvme0n1): " disk
  # Wipe existing disk, partition it, and format
  echo "Wiping and partitioning $disk..."
  wipefs --all /dev/$disk
  parted /dev/$disk --script mklabel gpt
  parted /dev/$disk --script mkpart ESP fat32 1MiB 1025MiB
  parted /dev/$disk --script set 1 esp on
  parted /dev/$disk --script mkpart primary btrfs 1025MiB 100%
  lsblk
fi

# Get partition names
read -p "Enter the EFI partition (e.g., nvme0n1p1): " efi_partition
read -p "Enter the root partition (e.g., nvme0n1p2): " root_partition
# Format partitions
echo "Formatting EFI and Root partitions..."
mkfs.fat -F32 /dev/${efi_partition}
mkfs.btrfs -f /dev/${root_partition}

# Mount the partitions
echo "Mounting the partitions..."
mount /dev/${root_partition} /mnt
mount --mkdir /dev/${efi_partition} /mnt/boot/efi
# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt > /mnt/etc/fstab

# Check if fsck is in the mkinitcpio.conf hooks array
if grep -q 'fsck' "/etc/mkinitcpio.conf"; then
  echo "Removing fsck hook..."
  sed -i 's/\bfsck\b//g' "/etc/mkinitcpio.conf"
  arch-chroot /mnt mkinitcpio -P
fi

# Optional file 
touch /mnt/etc/vconsole.conf

# Install core packages
echo "Installing core packages..."
pacstrap /mnt base base-devel linux linux-firmware git sudo fastfetch htop nano bluez bluez-utils networkmanager --noconfirm

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

# Create and prepare users
arch-chroot /mnt /bin/bash -c "
  echo 'Set root password:'
  passwd
"
read -p "Enter your username: " INSTALL_USER
if [[ -z "$INSTALL_USER" ]]; then
    echo "Username cannot be empty"
    exit 1
fi
arch-chroot /mnt /bin/bash -c "
  useradd -m -G wheel,storage,power,video,audio -s /bin/bash \"$INSTALL_USER\"
  echo 'Set password for  \"$INSTALL_USER\":'
  passwd \"$INSTALL_USER\"
  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
"

# Configure locales
echo "Configuring en_US.UTF-8 locales..."
arch-chroot /mnt /bin/bash -c "
  sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
  locale-gen
  
  echo 'LANG=en_US.UTF-8' > /etc/locale.conf
  echo 'KEYMAP=us' > /etc/vconsole.conf
"

# Install GRUB as the bootloader
echo "Installing GRUB..."
pacstrap -i /mnt grub efibootmgr dosfstools mtools --noconfirm
arch-chroot /mnt /bin/bash -c "
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg
"

# Install KDE Plasma with Wayland
echo "Installing KDE Plasma with Wayland..."
pacstrap -i /mnt plasma wayland sddm dolphin kscreen konsole breeze-gtk --noconfirm

# Optionally curl a file to sync other packages and .config files
read -p "Curl optional package installer? (y/n): " is_opt_pkgs
if [[ "${is_opt_pkgs,,}" == "y" || "${is_opt_pkgs,,}" == "yes" ]]; then
  tmp="/mnt/tmp/install_optionals.sh.$$"
  if curl -fL --show-error "https://raw.githubusercontent.com/sadako-yamamura/arch/refs/heads/main/install_optionals.sh" -o "$tmp"; then
    chmod +x "$tmp"
    mkdir -p "/mnt/home/$INSTALL_USER/Desktop"
    mv "$tmp" "/mnt/home/$INSTALL_USER/Desktop/install_optionals.sh"
    chown "$INSTALL_USER:$INSTALL_USER" "/mnt/home/$INSTALL_USER/Desktop/install_optionals.sh"
  else
    echo "Download failed"
    rm -f "$tmp"
  fi
fi

# Enable needed basic services
echo "Enabling basic services"
arch-chroot /mnt /bin/bash -c "
  systemctl enable NetworkManager
  systemctl enable bluetooth.service
  systemctl enable sddm.service
"

# Reboot and exit installation
umount -lR /mnt
echo "Finished and rebooting in 5 seconds..."
sleep 5
sudo shutdown -r now
