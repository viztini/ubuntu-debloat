#!/bin/bash
set -e

### ROOT CHECK ###
if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

echo "=== ULTIMATE UBUNTU DEBLOAT + BATTERY SCRIPT ==="

read -p "Proceed with aggressive debloat? (y/N): " GO
[[ "$GO" =~ ^[Yy]$ ]] || exit 0

read -p "Replace Ubuntu Desktop with vanilla GNOME? (y/N): " GNOME
read -p "Apply laptop battery + performance optimizations? (y/N): " POWER
read -p "Enable verbose boot (disable quiet splash)? (y/N): " BOOTTEXT

### SNAP NUKING (HARD) ###
systemctl disable --now snapd.service snapd.socket snapd.seeded.service || true
snap list | awk 'NR>1 {print $1}' | xargs -r snap remove --purge || true

rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap

apt purge -y snapd || true

cat > /etc/apt/preferences.d/nosnap.pref <<EOF
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

### BASE DEBLOAT ###
apt update -y

apt purge -y \
  ubuntu-report popularity-contest \
  apport apport-symptoms whoopsie kerneloops \
  ubuntu-advantage-tools \
  thunderbird rhythmbox totem \
  cheese remmina \
  aisleriot gnome-mahjongg gnome-mines gnome-sudoku \
  simple-scan transmission-gtk \
  libreoffice* \
  cups cups-browsed \
  avahi-daemon \
  modemmanager || true

### FIREFOX DEB (NO SNAP) ###
cat > /etc/apt/preferences.d/firefox-nosnap <<EOF
Package: firefox*
Pin: release o=Ubuntu*
Pin-Priority: -1
EOF

add-apt-repository -y ppa:mozillateam/ppa
apt update -y
apt install -y firefox

cat > /etc/apt/preferences.d/firefox-mozilla <<EOF
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 501
EOF

### FLATPAK ###
apt install -y flatpak gnome-software-plugin-flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

### VANILLA GNOME ###
if [[ "$GNOME" =~ ^[Yy]$ ]]; then
  apt install -y vanilla-gnome-desktop
  apt purge -y ubuntu-desktop ubuntu-session
fi

### BOOT TEXT (GRUB) ###
if [[ "$BOOTTEXT" =~ ^[Yy]$ ]]; then
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
  sed -i 's/#GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
  sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
  update-grub
fi

### POWER + BATTERY ###
if [[ "$POWER" =~ ^[Yy]$ ]]; then

  apt install -y \
    tlp tlp-rdw \
    powertop \
    thermald \
    linux-tools-common linux-tools-generic

  systemctl enable --now tlp
  systemctl enable --now thermald

  powertop --auto-tune || true

  ### DISABLE UNUSED SERVICES ###
  systemctl disable --now \
    bluetooth.service \
    cups.service \
    avahi-daemon.service \
    ModemManager.service || true

  ### KERNEL TUNING ###
  cat > /etc/sysctl.d/99-laptop.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  ### WIFI POWER SAVE ###
  echo "options iwlwifi power_save=1 power_level=3" > /etc/modprobe.d/iwlwifi.conf

  ### SSD POWER SAVE ###
  for d in /sys/block/sd*/queue/scheduler; do
    echo mq-deadline > "$d" || true
  done

  ### ZSWAP (LOW RAM BATTERY WIN) ###
  sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 /' /etc/default/grub
  update-grub

  ### GNOME POWER SAVINGS ###
  gsettings set org.gnome.desktop.interface enable-animations false || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'suspend' || true
fi

### FINAL CLEAN ###
apt autoremove --purge -y
apt clean

echo "=== DONE ==="
read -p "Reboot now? (Y/n): " RB
[[ ! "$RB" =~ ^[Nn]$ ]] && reboot

