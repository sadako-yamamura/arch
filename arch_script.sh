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
read -p "Enter the disk (e.g., /dev/sda): " disk

# Wipe existing disk, partition it, and format
echo "Wiping and partitioning $disk..."
wipefs --all $disk
parted $disk --script mklabel gpt
parted $disk --script mkpart ESP fat32 1MiB 1025MiB
parted $disk --script set 1 esp on
parted $disk --script mkpart primary btrfs 1025MiB 100%

# Get partition names (use lsblk to help identify the correct names)
efi_partition="${disk}1"
root_partition="${disk}2"

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
pacstrap -i /mnt base base-devel linux linux-firmware git sudo fastfetch htop nano vim bluez bluez-utils networkmanager --noconfirm

# Check CPU architecture for microcode (Intel vs AMD)
read -p "Enter CPU type (intel/amd): " cpu_type
if [[ "$cpu_type" == "intel" ]]; then
  pacstrap -i /mnt intel-ucode --noconfirm
elif [[ "$cpu_type" == "amd" ]]; then
  pacstrap -i /mnt amd-ucode --noconfirm
else
  echo "Unknown CPU type. Proceeding without microcode."
fi

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# 4. Create and prepare users
echo "Creating user..."
arch-chroot /mnt /bin/bash -c "
  # Set root password
  echo 'Set root password:'
  passwd

  # Set up a regular user
  read -p 'Enter your username: ' USER
  useradd -m -g users -G wheel,storage,power,video,audio -s /bin/bash \$USER
  echo 'Set user password for \$USER:'
  passwd \$USER

  # Uncomment wheel group in sudoers file
  EDITOR=nano visudo
"

# 5. Configure locales
echo "Configuring locales..."
arch-chroot /mnt /bin/bash -c "
  # Uncomment desired locale
  sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
  locale-gen

  # Set system language and keymap
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
pacstrap -i /mnt plasma-wayland-session kde-applications sddm --noconfirm

# Install additional utilities for Wayland and Plasma
pacstrap -i /mnt konsole dolphin kscreen kwrite kdenetworkmanager --noconfirm

# Enable SDDM (KDE's Display Manager)
arch-chroot /mnt /bin/bash -c "
  systemctl enable sddm
"

# 8. Enable essential services
echo "Enabling NetworkManager and other services..."
arch-chroot /mnt /bin/bash -c "
  systemctl enable NetworkManager
"

# 9. Reboot the system
echo "Finishing up and rebooting..."
umount -lR /mnt
shutdown now