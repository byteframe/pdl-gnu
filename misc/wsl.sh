-------------------------------------------------------------------------------- INSTALL
passwd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
useradd -m -g users -G wheel -s /bin/bash byteframe
passwd byteframe
-------------------------------------------------------------------------------- SET DEFAULT USER FOR WSL
Arch.exe config --default-user byteframe
-------------------------------------------------------------------------------- PACMAN INIT AND BASE DEVEL
sed -i -e "s/fakeroot/fakeroot glibc/" /etc/pacman.conf
sudo pacman-key --init
sudo pacman-key --populate
sudo pacman -U /mnt/c/glibc-2.33-3-x86_64.pkg.tar.zst
sudo pacman -Syu
sudo pacman -S base-devel
sudo pacman -R vim
-------------------------------------------------------------------------------- FIXES
strip --remove-section=.note.ABI-tag /usr/lib/libQt5Core.so.5
sudo pacman -Udd /mnt/c/systemd-altctl-1.4.4181-1-any.pkg.tar.xz
sudo pacman -Udd /mnt/c/dbus-x11-1.12.16-1-x86_64.pkg.tar.xz
sed -i 's/fakeroot/fakeroot systemd-sysvcompat dbus/' /etc/pacman.conf
-------------------------------------------------------------------------------- RUNNING
export DISPLAY=:0.0
export LIBGL_ALWAYS_INDIRECT=1
load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1
load-module module-waveout sink_name=output source_name=input record=0
--------------------------------------------------------------------------------