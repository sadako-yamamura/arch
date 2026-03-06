
<h1 class="title-centered">Arch Script Installer</h1>

  
[Official Guide](https://wiki.archlinux.org/title/Installation_guide)

#### 1. Download live USB Arch installer
Download the ISO file and boot the image
[Downloads](https://archlinux.org/download/)

#### 2. Download the script
Inside the live USB installer, get the script and execute it
```
curl -L https://raw.githubusercontent.com/sadako-yamamura/arch/refs/heads/main/arch_script.sh -o arch_script.sh
chmod +x arch_script.sh
bash ./arch_script.sh
```

Last tested on: Release 2026.03.01 and Kernel 6.18.13
