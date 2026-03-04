
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

Optional
```
export disk="nvme0n1"
export efi_partition="nvme0n1p1"
export root_partition="nvme0n1p2"
export USER="sadako"
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
mkfs.fat -F32 /dev/$efi_partition
mkfs.btrfs -f /dev/$root_partition
```

Mount the partitions
Replace the variables or export again
```
mount /dev/$root_partition /mnt
mount --mkdir /dev/$efi_partition /mnt/boot/efi
```

#### 3. Installation of core packages
```
touch /mnt/etc/vconsole.conf
pacstrap -i /mnt base base-devel linux linux-firmware git sudo fastfetch htop nano vim bluez bluez-utils networkmanager --noconfirm
```
for intel cpus
```
pacstrap -i /mnt intel-ucode --noconfirm
```
for amd cpus
```
pacstrap -i /mnt amd-ucode --noconfirm
```
then
```
genfstab -U /mnt >> /mnt/etc/fstab
```

#### 4. Create and prepare users
Password will be asked
```
arch-chroot /mnt
```
```
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

#### 7. Enable basic services and exit installer to reboot
```
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
sudo pacman -S xorg sddm plasma-workspace dolphin cargo clang cmake make gcc noto-fonts noto-fonts-emoji ttf-dejavu --noconfirm
```
Activation of the DE
```
sudo systemctl enable sddm
sudo systemctl start sddm
```

