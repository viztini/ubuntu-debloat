#!/bin/bash
set -e

[ "$EUID" -ne 0 ] && echo "Run as root" && exit 1

read -p "Proceed with aggressive debloat? (y/N): " GO
[[ "$GO" =~ ^[Yy]$ ]] || exit 0

read -p "Replace Ubuntu Desktop with vanilla GNOME? (y/N): " GNOME
read -p "Apply laptop power + battery optimizations? (y/N): " POWER

### SNAP NUKING ###
systemctl disable --now snapd.service snapd.socket snapd.seeded.service
snap list | awk 'NR>1 {print $1}' | xargs -r snap remove --purge
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap
apt purge snapd -y
cat > /etc/apt/preferences.d/nosnap.pref <<EOF
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

### BASE CLEANUP ###
apt update -y
apt purge -y \
  ubuntu-report popularity-contest apport apport-symptoms \
  whoopsie kerneloops ubuntu-advantage-tools \
  thunderbird rhythmbox totem \
  cheese remmina \
  aisleriot gnome-mahjongg gnome-mines gnome-sudoku \
  simple-scan transmission-gtk \
  libreoffice* \
  cups cups-browsed avahi-daemon \
  modemmanager

### FIREFOX DEB ###
cat > /etc/apt/preferences.d/firefox-nosnap <<EOF
Package: firefox*
Pin: release o=Ubuntu*
Pin-Priority: -1
EOF

add-apt-repository ppa:mozillateam/ppa -y
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

### GNOME SWITCH ###
if [[ "$GNOME" =~ ^[Yy]$ ]]; then
  apt install -y vanilla-gnome-desktop
  apt purge -y ubuntu-desktop ubuntu-session
fi

### POWER / BATTERY ###
if [[ "$POWER" =~ ^[Yy]$ ]]; then
  apt install -y tlp tlp-rdw powertop linux-tools-common linux-tools-generic
  systemctl enable --now tlp
  powertop --auto-tune

  systemctl disable --now \
    bluetooth.service \
    cups.service \
    avahi-daemon.service \
    ModemManager.service

  echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf
  echo "options iwlwifi power_save=1" > /etc/modprobe.d/iwlwifi.conf

  gsettings set org.gnome.desktop.interface enable-animations false || true
fi

### FINAL CLEAN ###
apt autoremove --purge -y
apt clean

read -p "Reboot now? (Y/n): " RB
[[ ! "$RB" =~ ^[Nn]$ ]] && reboot

