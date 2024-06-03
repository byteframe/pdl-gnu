-------------------------------------------------------------------------------- ASSET_PACK BASHRC
S=/mnt/s/SteamLibrary/steamapps/common
D=/mnt/c/Program\ Files\ \(x86\)/Steam/steamapps/common
C=${D}/SteamVR/tools/steamvr_environments/content/steamtours_addons
G=${D}/SteamVR/tools/steamvr_environments/game/steamtours_addons
W=/mnt/c/Users/byteframe/Downloads
X=/mnt/d/Work/Game/steamtours/asset_packs
N=/mnt/c/Program\ Files/Notepad++/notepad++.exe
-------------------------------------------------------------------------------- WSL1 FIXES
pacman -S binutils
strip --remove-section=.note.ABI-tag /usr/lib/libQt5Core.so.5
sudo pacman -Udd /mnt/d/Work/pdl-gnu/misc/dbus-x11-1.12.16-1-x86_64.pkg.tar.xz
-------------------------------------------------------------------------------- OBSOLETE WSL2 FIXES
sudo pacman -Udd /mnt/d/Work/pdl-gnu/misc/systemd-altctl-1.4.4181-1-any.pkg.tar.xz
sudo sed -i 's/fakeroot/fakeroot systemd-sysvcompat/' /etc/pacman.conf
C:
cd \Windows\System32\lxss\lib
del libcuda.so libcuda.so.1
mklink libcuda.so libcuda.so.1.1
mklink libcuda.so.1 libcuda.so.1.1
-------------------------------------------------------------------------------- FIRST RUN
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
useradd -m -g users -G wheel -s /bin/bash byteframe
passwd && passwd byteframe
pacman-key --init && pacman-key --populate
pacman -Sy archlinux-keyring && pacman -Su
loginctl enable-linger byteframe
cp -v /mnt/d/Work/pdl-gnu/misc/euclid.xlaunch /mnt/c/Program\ Files/VcXsrv
cp -v /mnt/d/Work/pdl-gnu/misc/startxfce4.bat /mnt/c/Program\ Files/VcXsrv
cp -v /mnt/d/Work/pdl-gnu/misc/startxfce4.sh /home/byteframe
C:\Users\byteframe\Arch\Arch.exe config --default-user byteframe
(root) sh archlinux.sh
vcxsrv-64.1.20.14.0.installer.exe `Icon="C:\Program Files\VcXsrv\startxfce4.bat"`
pulseaudio-5.0-rev18.zip (C:\Program Files\pulseaudio) config.pa:
  load-module module-native-protocol-tcp auth-anonymous=1
  load-module module-esound-protocol-tcp auth-anonymous=1
  load-module module-waveout sink_name=output source_name=input record=0