<h1 align="center">
==================================================
Manual Arch Core Installation
==================================================
</h1>

[Official Guide](https://wiki.archlinux.org/title/Installation_guide)
[Downloads](https://archlinux.org/download/)


#### To make the terminal clear do
```
setfont ter-132b or setfont -d
```

#### Arch needs internet to install stuff
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
Set 1G EFI, then RAM x 1.5 G swap (optional), the rest as filesystem which is the root partition
Replace $disk or export
```
cfdisk /dev/$disk
```
After creating the partitions, those must be formatted
Replace the variables or export
```
mkfs.fat -F32 /dev/$efi_partition
mkswap /dev/$swap_partition
mkfs.ext4 /dev/$root_partition
```
Mount the partitions
Replace the variables or export again
```
mount /dev/$root_partition /mnt
mount --mkdir /dev/$efi_partition /mnt/boot/efi
swapon /dev/$swap_partition
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

#### 6. GRUB bootloader installation
(disks must still be mounted)
```
pacman -S grub efibootmgr dosfstools mtools --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
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
sudo pacman -Syu xorg sddm plasma-meta plasma-workspace dolphin konsole kwrite cargo clang cmake make gcc noto-fonts noto-fonts-emoji ttf-dejavu ttf-font-awesome
```
Activation of the DE
```
sudo systemctl enable sddm
sudo systemctl start sddm
```

### TODO: optional upgrade to blackarch
### TODO: Blackarch installation in VMware
