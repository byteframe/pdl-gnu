-------------------------------------------------------------------------------- INSTALL
echo "delete dir in appdata/packages for reinstalling appx"
passwd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
useradd -m -g users -G wheel -s /bin/bash byteframe
passwd byteframe
-------------------------------------------------------------------------------- SET DEFAULT USER FOR WSL
Arch.exe config --default-user byteframe
-------------------------------------------------------------------------------- PACMAN INIT AND PRE-SCRIPT PACKAGES
sudo pacman -Sy
sudo pacman -Su
sudo pacman -Udd /mnt/d/Work/pdl-gnu/misc/systemd-altctl-1.4.4181-1-any.pkg.tar.xz
sudo sed -i 's/fakeroot/fakeroot systemd-sysvcompat/' /etc/pacman.conf
-------------------------------------------------------------------------------- WSL2-POST-SCRIPT FIXES (if needed)
C:
cd \Windows\System32\lxss\lib
del libcuda.so
del libcuda.so.1
mklink libcuda.so libcuda.so.1.1
mklink libcuda.so.1 libcuda.so.1.1
-------------------------------------------------------------------------------- WSL1-POST-SCRIPT FIXES
pacman -S binutils
strip --remove-section=.note.ABI-tag /usr/lib/libQt5Core.so.5
sudo pacman -Udd /mnt/d/Work/pdl-gnu/misc/dbus-x11-1.12.16-1-x86_64.pkg.tar.xz
-------------------------------------------------------------------------------- RUNNING
cp -v /mnt/d/Work/pdl-gnu/misc/startxfce4.sh /home/byteframe
echo "export LIBGL_ALWAYS_INDIRECT=1" >> /home/byteframe/.bashrc
--------------------------------------------------------------------------------