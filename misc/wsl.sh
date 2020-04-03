-------------------------------------------------------------------------------- INSTALL
passwd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
useradd -m -g users -G wheel -s /bin/bash byteframe
passwd byteframe
-------------------------------------------------------------------------------- SET DEFAULT USER FOR WSL
Arch.exe config --default-user byteframe
-------------------------------------------------------------------------------- PACMAN INIT AND BASE DEVEL
sudo pacman-key --init
sudo pacman-key --populate
sudo pacman -Syu
sudo pacman -S base-devel
sudo pacman -R vim
-------------------------------------------------------------------------------- FIXES
pacman -S binutils
strip --remove-section=.note.ABI-tag /usr/lib/libQt5Core.so.5
sudo pacman -Udd /mnt/c/systemd-altctl-1.4.3027-1-x86_64.pkg.tar.xz
sed -i 's/fakeroot$/fakeroot systemd-sysvcompat/' /etc/pacman.conf
-------------------------------------------------------------------------------- RUNNING
export DISPLAY=:0.0
export LIBGL_ALWAYS_INDIRECT=1
--------------------------------------------------------------------------------