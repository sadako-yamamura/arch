
<h1 class="title-centered">Manual Arch Core Installation</h1>

  
[Official Guide](https://wiki.archlinux.org/title/Installation_guide)
[Downloads](https://archlinux.org/download/)


#### 0. Optional 
To make the terminal clear do
```
setfont ter-132b or setfont -d
```

Arch needs internet to install stuff
If there is no cable use iwctl, otherwise skip
Can check internet with ping
If so, replace $wifi_ssid or export
Wifi password will be asked
```
iwctl
station wlan0 get-networks
station wlan0 connect $wifi_ssid
exit
```

SSH

On host
```
passwd
ip a
```
On client
```
ssh root@$ip
```

#### 1. Arch update
```
pacman -Sy
pacman -Sy archlinux-keyring --noconfirm
```

#### 2. Preparations of partitions
To list them do
```
lsblk
```
Manually create the partitions
Set 1G EFI, the rest as filesystem which is the root partition
Replace $disk or export
```
sudo wipefs --all /dev/$disk
sudo parted /dev/$disk --script mklabel gpt
sudo parted /dev/$disk --script mkpart ESP fat32 1MiB 1025MiB
sudo parted /dev/$disk --script set 1 esp on
sudo parted /dev/$disk --script mkpart primary btrfs 1025MiB 100%
```
After creating the partitions, those must be formatted
Replace the variables or export
```
mkfs.fat -F32 /dev/$efi_partition
mkfs.ext4 /dev/$root_partition
```
Mount the partitions
Replace the variables or export again
```
mount /dev/$root_partition /mnt
mount --mkdir /dev/$efi_partition /mnt/boot/efi
```

#### 3. Installation of core packages
```
pacstrap -i /mnt base base-devel linux linux-firmware git sudo fastfetch htop nano vim bluez bluez-utils networkmanager
```
for intel cpus
```
pacstrap -i /mnt intel-ucode
```
for amd cpus
```
pacstrap -i /mnt amd-ucode
```
then
```
genfstab -U /mnt >> /mnt/etc/fstab
```

#### 4. Create and prepare users
Password will be asked
```
arch-chroot /mnt
passwd
```
Replace $USER or export, password asked again
```
useradd -m -g users -G wheel,storage,power,video,audio -s /bin/bash $USER
passwd $USER
```
Uncomment wheel ALL=(ALL:ALL) ALL
```
EDITOR=nano visudo
```

#### 5. Get locales ready
uncomment desired languages like en_US.UTF-8 UTF-8
```
nano /etc/locale.gen
```
then run
```
locale-gen
```
add desired system languages like LANG=en_US.UTF-8
```
nano /etc/locale.conf
```
add desired system languages like KEYMAP=us
```
nano /etc/vconsole.conf
```

#### 6.A GRUB bootloader installation
```
pacman -S grub efibootmgr dosfstools mtools --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

#### 6.B Limine & Windows dual boot
Needs to be booted in UEFI mode, check with:
```
ls /sys/firmware/efi/efivars
```
```
pacman -S limine efibootmgr
mkdir -p /boot/efi/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/limine/
efibootmgr \
  --create \
  --disk /dev/$disk \
  --part $efi_partition_number \
  --label "Arch Linux Limine" \
  --loader '\EFI\limine\BOOTX64.EFI' \
  --unicode
```
Add this to /boot/limine.conf
```
timeout: 5

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    module_path: boot():/initramfs-linux.img
    options: root=$root_partition_UUID rw

/Windows
    protocol: efi
    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
    comment: Boot Microsoft Windows
```
```
lsblk -o NAME,UUID
nano /boot/limine.conf
```


#### 7. Enable basic services and exit installer to reboot
```
systemctl enable bluetooth
systemctl enable NetworkManager
exit
umount -lR /mnt
shutdown now
```
System will reboot, remove installation media

#### 8. Boot and log again
To make the terminal clear again, do
```
setfont ter-132b or setfont -d
```
Log with the previous user
Password will be asked
```
$USER
```
Access root for simplicity
```
su
```

#### Internet connection is needed again to install packages again
```
nmcli radio wifi on
```
Replace or export credentials
```
sudo nmcli dev wifi connect $wifi_ssid password "$wifi_passwd"
```

### 9. Install and enable KDE Plasma
Installation of the packages
```
sudo pacman -Syu
sudo pacman -Syu xorg sddm plasma-workspace dolphin cargo clang cmake make gcc noto-fonts noto-fonts-emoji ttf-dejavu
```
Activation of the DE
```
sudo systemctl enable sddm
sudo systemctl start sddm
```

