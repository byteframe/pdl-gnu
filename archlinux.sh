#!/bin/bash

if [ $(whoami) != root ]; then
  echo "fatal: not root user"
  exit 1
fi
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAIN_USER=$(grep ":x:1000:" /etc/passwd)
if [ ! -z ${MAIN_USER} ]; then
  MAIN_USER=${MAIN_USER:0:$(expr index ${MAIN_USER} ":")-1}
elif which patch > /dev/null 2>&1; then
  while [ -z ${MAIN_USER} ]; do
    echo "input main user:"
    read MAIN_USER
  done
fi
if [ -z ${MAIN_USER} ]; then
  MAIN_USER=byteframe
fi
if [ ! -e ${DIR}/archlinux.sh ]; then
  DIR=/mnt/Datavault/Work/pdl-gnu
fi
if [ -z ${DOMAIN} ]; then
  DOMAIN=primarydataloop
fi
APP=/usr/share/applications

function add_unique()
{
  # append line to file if it doesn't exist
  if [ -z "${1}" ] || [ -z "${2}" ]; then
    echo "add_unique: missing input ${1}|${2}"
  elif [ ! -e "${2}" ]; then
    echo "add_unique: ${2} not found"
  elif ! grep -qF "${1}" "${2}"; then
    echo -e "${1}" >> "${2}"
  fi
}

function archpackage()
{
  # install package with pacman if it is not installed
  for PACKAGE in $*; do
    if ! pacman -Q ${PACKAGE} > /dev/null 2>&1; then
      echo y | pacman -S ${PACKAGE}
    fi
  done
}

function archbuild()
{
  # build package from AUR or existing folder
  if [ -z ${MAIN_USER} ] || [ -z ${2} ]; then
    echo "error, no user or package specified..."
    return 1
  fi
  rm -fr /home/${MAIN_USER}/${2}
  if [ -d "${DIR}"/${2}_arch ]; then
    cp -R "${DIR}"/${2}_arch /home/${MAIN_USER}/${2}
  else
    wget -q https://aur.archlinux.org/cgit/aur.git/snapshot/${2}.tar.gz
    tar -xzf ${2}.tar.gz -C /home/${MAIN_USER}
    rm ${2}.tar.gz
  fi
  if [ ! -e /home/${MAIN_USER}/${2}/PKGBUILD ]; then
    echo package download failed
    if [ ! -z ${SCRIPT_RUN} ]; then
      exit 1
    fi
  else
    echo "groups=('modified')" >> /home/${MAIN_USER}/${2}/PKGBUILD
    if [ ! -z ${3} ]; then
      sed -i -e "s/pkgver=.*/pkgver=${3}/" /home/${MAIN_USER}/${2}/PKGBUILD
    fi
    VER=$(grep -m1 ver= /home/${MAIN_USER}/${2}/PKGBUILD | sed s/.*=//)
    VER=${VER}-$(grep -m1 pkgrel= /home/${MAIN_USER}/${2}/PKGBUILD | sed s/.*=//)
    VER=${VER//\"}
    if [ ${VER} != "$(pacman -Q ${2} 2> /dev/null | awk '{print $2}' \
    | sed -e "s/.*://" -e s/\"//)" ]; then
      if [ ! -z ${4} ]; then
        sed -i -e ':a;N;$!ba;'"s/)\nsha[0-9]*sums=/\n        ${4})\nsha1sums=/" \
          /home/${MAIN_USER}/${2}/PKGBUILD
        sed -i -e ':a;N;$!ba;'"s/}\n\nbuild()/  patch -Np1 -i \"\${srcdir}\/${4}\"\n}\n\nbuild()/" \
          /home/${MAIN_USER}/${2}/PKGBUILD
      fi
      chown -R ${MAIN_USER}:users /home/${MAIN_USER}/${2}
      if [ ! -z ${5} ]; then
        DEPS=$*
        echo y | pacman -S ${DEPS/*${5}/${5}}
      fi
      ( cd /home/${MAIN_USER}/${2}
        sudo -u ${MAIN_USER} makepkg --skipinteg -s || exit 1
      )
      if find /home/${MAIN_USER}/${2} -name *.pkg.tar.xz > /dev/null;then
        echo y | pacman -U /home/${MAIN_USER}/${2}/${2}-*.pkg.tar.xz
      fi
      if [ ! -z ${5} ]; then
        echo y | pacman -R ${DEPS/*${5}/${5}}
      fi
    fi
    rm -fr /home/${MAIN_USER}/${2}
  fi
}

# installation with disk medium
if [ -d /sys/firmware/efi/efivars ]; then
  UEFI=1
fi
if [ -z "${SOURCING}" ];then
  SCRIPT_RUN=yes
  if [ ${HOSTNAME} = archiso ]; then
    DEVICE=sda
    if [ ! -z ${1} ]; then
      DEVICE=${1}
    fi
    ROOT=${DEVICE}3
    if mount | grep -q "sd.. on /mnt"; then
      cat /pdltee1.log /mnt/pdltee2.log > /mnt/pdl-gnu_archlinux.log
      rm -v /mnt/pdl*
      umount -R /mnt /pdl
      reboot
    elif ! which patch > /dev/null 2>&1; then
      nano /etc/pacman.d/mirrorlist
      {
        SWAP=2
        echo "formatting: ${ROOT} | swap: ${SWAP} | efi: ${UEFI}"
        read CONFIRM
        if [ -z ${FORMAT} ]; then
          mkfs.ext4 /dev/${ROOT}
        fi
        mkswap /dev/${DEVICE}${SWAP}
        swapon /dev/${DEVICE}${SWAP}
        mount /dev/${ROOT} /mnt
        if [ ! -z ${UEFI} ]; then
          mkdir /mnt/efi
          mount /dev/${DEVICE}${UEFI} /mnt/efi
        fi
        if [ ! -z ${FORMAT} ]; then
          find /mnt -maxdepth 1 -mindepth 1 -not -name home -exec rm -fr {} \;
        fi
        pacstrap -i /mnt base base-devel linux linux-firmware
        genfstab -U /mnt >> /mnt/etc/fstab
        sed -i -e "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /mnt/etc/locale.gen
        echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
        cp "${0}" /mnt
        sed -i -e "s/_DEVICE_/${DEVICE}/" /mnt/archlinux.sh
      } | tee /pdltee1.log
      arch-chroot /mnt /bin/bash
      exit 0
    else
      if [ -z ${1} ]; then
        echo "error, hostname not specified"
        exit 1
      fi
      {
        locale-gen
        ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
        echo ${1} > /etc/hostname
        echo -e "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t${1}.${DOMAIN}  ${1}" > /etc/hosts

        # timesyncd
        sed -i -e "s/#FallbackNTP/FallbackNTP/" /etc/systemd/timesyncd.conf
        timedatectl set-ntp true

        # linux-headers
        archpackage linux-headers

        # intel-ucode
        if cat /proc/cpuinfo | grep -q GenuineIntel; then
          archpackage intel-ucode
        fi

        # os-prober
        archpackage os-prober

        # grub
        archpackage grub
        if [ -z ${UEFI} ]; then
          grub-install --target=i386-pc /dev/_DEVICE_
        else
          archpackage efibootmgr
          grub-install --target=x86_64-efi --efi-directory=efi --bootloader-id=GRUB
        fi
        grub-mkconfig -o /boot/grub/grub.cfg

        # network-manager
        archpackage networkmanager
        systemctl enable NetworkManager.service

        # main user/sudo
        if ! grep -q "^${MAIN_USER}:" /etc/passwd; then
          mv /home/${MAIN_USER} /home/tmp 2> /dev/null
          useradd -c ${MAIN_USER} -g users -G wheel -m -s /bin/bash ${MAIN_USER}
          echo "[[ -z \${DISPLAY} && \${XDG_VTNR} -eq 1 ]] && startxfce4"  >> /home/${MAIN_USER}/.bash_profile
          mv /home/tmp/* /home/${MAIN_USER} 2> /dev/null
          mv /home/tmp/.* /home/${MAIN_USER} 2> /dev/null
          rmdir /home/tmp 2> /dev/null
          while ! passwd ${MAIN_USER}; do
            sleep 1
          done
        fi
        archpackage sudo
        add_unique "Defaults rootpw" /etc/sudoers
        add_unique "Defaults passwd_timeout=0" /etc/sudoers
        add_unique "%wheel ALL=PASSWD: ALL" /etc/sudoers

        # samba/fstab
        archpackage cifs-utils
        mkdir -p /mnt/Datavault /mnt/tmp
        if [ ${1} = "euclid" ]; then
          archpackage samba
          {
            echo "[global]"
            echo "  map to guest = Bad User"
            echo "  load printers = no"
            echo "  printing = bsd"
            echo "  printcap name = /dev/null"
            echo "  disable spoolss = yes"
            echo "  show add printer wizard = no"
            echo "  workgroup = primarydataloop"
            echo "  server string = Simba Server"
            echo "  server role = standalone server"
            echo "  hosts allow = 192.168.4. 127."
            echo "  logging = systemd"
            echo "  dns proxy = no"
            echo "[Video]"
            echo "  path = /mnt/Datavault/Video"
            echo "  guest ok = yes"
            echo "[Datavault]"
            echo "  path = /mnt/Datavault"
            echo "  hide files = /lost+found/"
            echo "  read only = no"
            echo "  valid users = byteframe"
            echo "  browseable = no"
            echo "  case sensitive = Yes"
          } > /etc/samba/smb.conf
          smbpasswd -a byteframe
          systemctl enable smb.service
          echo "UUID=c89cb473-3e20-4178-9a6c-9dbe90d34f59	/mnt/Datavault  ext4		defaults,nofail,relatime	0 0" >> /etc/fstab
        else
          echo "input samba username: "
          read SMBUSER
          echo "username=${SMBUSER}" > /root/.dvcred
          echo "input samba password: "
          read SMBPASSWD
          echo "password=${SMBPASSWD}" >> /root/.dvcred
          echo "//euclid/Datavault /mnt/Datavault cifs noauto,_netdev,credentials=/root/.dvcred 0   0" >> /etc/fstab
        fi

        # hdparm/fstrim
        archpackage hdparm
        if hdparm -I /dev/_DEVICE_ | grep -q TRIM\ supported; then
          systemctl enable fstrim.timer
        fi

        # root password
        while ! passwd; do
          sleep 1
        done
        echo MANUALLY_EXIT_CHROOT
      } | tee /pdltee2.log
      exit
    fi
  fi

  function extract_game()
  {
    # extract game wads/roms
    if [ ! -d /home/${MAIN_USER}/"${2}" ]; then
      sudo -u ${MAIN_USER} mkdir -p /home/${MAIN_USER}/"${2}"
      sudo -u ${MAIN_USER} unzip -d /home/${MAIN_USER}/"${2}" -o "${DIR}"/"${1}".zip
    fi
  }

  # detect WSL
  if uname -a | grep -q Microsoft; then
    WSL=true
  fi

  # enable multilib, ignore upgrades for modified, and clear cache/install logs
  if [ -z ${WSL} ] && grep -q "#\[multilib]" /etc/pacman.conf; then
    OPTS="Include = \/etc\/pacman.d\/mirrorlist"
    sed -i -e ':a;N;$!ba;'"s/#\[multilib\]\n#${OPTS}/\[multilib\]\n${OPTS}/" /etc/pacman.conf
  fi
  sed -i -e "s/#IgnoreGroup =/IgnoreGroup = modified/" /etc/pacman.conf
  rm -fr /var/cache/pacman/pkg /pdl-gnu_archlinux.log /home/pdl-gnu_archlinux.log

  # system upgrade/clutches
  pacman -Sy
  pacman -Rns $(pacman -Qtdq)
  while ! pacman -Su; do
    sleep 3
  done

  # post install/upgrade adjustments
  mv -v /etc/makepkg.conf.pacnew /etc/makepkg.conf 2> /dev/null
  sed -i -e 's/.*PACKAGER=".*"/PACKAGER="'"${MAIN_USER}@${DOMAIN}\"/" /etc/makepkg.conf
  mv -v /etc/pacman.d/mirrorlist.pacnew /etc/pacman.d/mirrorlist 2> /dev/null
  sed -i -e "s/#Server = http:\/\/mirrors.kernel/Server = http:\/\/mirrors.kernel/" /etc/pacman.d/mirrorlist

  # install packages
  archpackage screen \
    bc \
    cabextract \
    dosfstools \
    ethtool \
    gnu-netcat \
    inotify-tools \
    lsof \
    lame \
    p7zip \
    smartmontools \
    unrar \
    unzip \
    wget \
    zip \
    rsync \
    ntfs-3g \
    exfat-utils \
    ntp \
    nodejs-lts-dubnium \
    npm \
    git \
    xorg-server \
    nmap \
    nano
  if [ -z ${WSL} ]; then
    archpackage lib32-mesa
  fi
  add_unique "NoDisplay=true" ${APP}/zenmap.desktop
  add_unique "NoDisplay=true" ${APP}/zenmap-root.desktop
  if [ -e /proc/bus/pci ]; then
    archpackage xf86-video-fbdev \
      xf86-input-synaptics
    if lspci | grep VGA | grep -qi Intel\ Corp; then
      archpackage xf86-video-intel \
        libva-intel-driver \
        lib32-libva-intel-driver \
        libva1 lib32-libva1 \
        libva1-intel-driver \
        lib32-libva1-intel-driver \
        libvdpau-va-gl
    elif ! lspci | grep VGA | grep -qi VMware; then
      archpackage libva-vdpau-driver \
        lib32-libva-vdpau-driver
      if ! lspci | grep VGA | grep -qi NVIDIA\ Corp; then
        archpackage xf86-video-ati mesa-vdpau
        echo -e "export LIBVA_DRIVER_NAME=vdpau\nexport VDPAU_DRIVER=r600" > /etc/profile.d/vdpau.sh
      elif lspci | grep VGA | grep -qi GeForce\ FX || lspci | grep VGA | grep -qi GeForce\ [6-7]; then
        archpackage xf86-video-nouveau mesa-vdpau
      elif ! pacman -Q nvidia > /dev/null 2>&1; then
        pacman -S nvidia
        pacman -S lib32-nvidia-libgl
      fi
    fi
  fi
  archpackage vdpauinfo \
    libva-utils \
    libxv \
    libxvmc \
    xcb-util \
    ttf-dejavu \
    noto-fonts-emoji \
    ttf-liberation \
    wqy-zenhei
  ln -sf /etc/fonts/conf.avail/10-hinting-full.conf /etc/fonts/conf.d/
  ln -sf /etc/fonts/conf.avail/10-autohint.conf /etc/fonts/conf.d/
  rm -vf /etc/fonts/conf.d/10-hinting-slight.conf 2> /dev/null
  archpackage ffmpeg
  sed -i -e "s/Qt V4L2 test Utility/Qv4L2/" ${APP}/qv4l2.desktop
  add_unique "NoDisplay=true" ${APP}/qvidcap.desktop
  archpackage viewnior
  sed -i -e "s/GNOME.*Viewer;/AudioVideo;/" ${APP}/viewnior.desktop
  archpackage obs-studio
  archpackage youtube-dl \
    galculator \
    xarchiver \
    easytag
  archpackage gimp
  sed -i -e "s/Name=GNU Image Manipulation Program/Name=GIMP/" -e "s/Graphics.*GTK;/AudioVideo;/" ${APP}/gimp.desktop
  archpackage transmission-cli \
    transmission-gtk \
    chromium \
    gvfs
  add_unique "NoDisplay=true" ${APP}/avahi-discover.desktop
  add_unique "NoDisplay=true" ${APP}/bssh.desktop
  add_unique "NoDisplay=true" ${APP}/bvnc.desktop
  archpackage gvfs-smb \
    gvfs-mtp
  archpackage pulseaudio \
    pulseaudio-alsa \
    pasystray
  add_unique "NoDisplay=true" ${APP}/pasystray.desktop
  if [ -z ${WSL} ]; then
    archpackage lib32-alsa-plugins \
      lib32-libpulse
  fi
  archpackage mpv
  {
    echo "1 set window-scale 1.00"
    echo "2 set window-scale 2.00"
    echo "0 set window-scale 0.50"
    echo "- add volume -1"
    echo "= add volume 1"
  } > /etc/mpv/input.conf
  {
    echo "keep-open"
    echo "volume=100"
    echo "softvol=yes"
    echo "hwdec=auto"
    echo "save-position-on-quit"
    echo "load-unsafe-playlists"
    echo "no-stop-screensaver"
  } > /etc/mpv/mpv.conf
  sed -i -e "s/ Media Player//" ${APP}/mpv.desktop
  archpackage kodi
  sed -i -e "s/media center//" ${APP}/kodi.desktop
  archpackage gst-libav \
    gst-plugins-good \
    handbrake \
    notepadqq \
    synergy
  sed -i -e "s/Development;/;/" ${APP}/notepadqq.desktop
  sed -i -e "s/Icon=synergy/Icon=\/usr\/share\/icons\/synergy.ico/" ${APP}/synergy.desktop
  if [ -z ${WSL} ]; then
    archpackage network-manager-applet
    archpackage steam
    OPTS="LD_PRELOAD='\/usr\/\$LIB\/libstdc++.so.6 \/usr\/\$LIB\/libgcc_s.so.1 \/usr\/\$LIB\/libxcb.so.1 \/usr\/\$LIB\/libgpg-error.so'"
    sed -i -e "s/Network;FileTransfer;//" -e "s/steam-runtime %U/steam-runtime -console %U/" \
      -e "s/Exec=\/usr/Exec=env STEAM_FRAME_FORCE_CLOSE=1 /" \
      -e "s/env STEAM_/env ${OPTS} STEAM_/" -e "s/ (Runtime)//" ${APP}/steam.desktop
    rm -f ${APP}/steam-native.desktop
    OPTS=/home/${MAIN_USER}/.local/share/Steam/ubuntu12_32/steam-runtime/i386/usr
    if [ -d ${OPTS} ]; then
      if pacman -Q nvidia-utils > /dev/null 2>&1; then
        if [ ! -d ${OPTS}/lib/i386-linux-gnu/vdpau.bak ]; then
          mv ${OPTS}/lib/i386-linux-gnu/vdpau ${OPTS}/lib/i386-linux-gnu/vdpau.bak
        fi
        sudo -u ${MAIN_USER} ln -sfn /usr/lib32/vdpau ${OPTS}/lib/i386-linux-gnu/vdpau
      else
        sudo -u ${MAIN_USER} ln -sf /usr/lib32/libva1/libva.so.1.* ${OPTS}/lib/i386-linux-gnu/libva.so.1
        sudo -u ${MAIN_USER} ln -sf /usr/lib32/libva1/libva-glx.so.1.* ${OPTS}/lib/i386-linux-gnu/libva-glx.so.1
        sudo -u ${MAIN_USER} ln -sf /usr/lib32/libva1/libva-x11.so.1.* ${OPTS}/lib/i386-linux-gnu/libva-x11.so.1
      fi
    fi
  fi
  archpackage imagemagick
  archpackage rdesktop
  archpackage retroarch
  sed -i -e "s/Emulator;/;/" ${APP}/retroarch.desktop
  sed -i -e "s/menu_show_core_updater = false/menu_show_core_updater = true/" \
    -e "s/libretro_directory = \/usr\/lib\/libretro/libretro_directory = ~\/.config\/retroarch\/cores/" /etc/retroarch.cfg
  archpackage xfce4-session
  if ! grep -q SaveOnExit /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml; then
    sed -i -e 's/value="Failsafe"\/>/&\n    <property name="SaveOnExit" type="bool" value="false"\/>/' \
      /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
  fi
  archpackage xfwm4 \
    xfdesktop
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<channel name="xfce4-desktop" version="1.0">'
    echo '  <property name="desktop-icons" type="empty">'
    echo '    <property name="file-icons" type="empty">'
    echo '      <property name="show-home" type="bool" value="false"/>'
    echo '      <property name="show-removable" type="bool" value="false"/>'
    echo '      <property name="show-trash" type="bool" value="false"/>'
    echo '      <property name="show-filesystem" type="bool" value="false"/>'
    echo '    </property>'
    echo '    <property name="icon-size" type="uint" value="32"/>'
    echo '    <property name="style" type="uint" value="0"/>'
    echo '  </property>'
    echo '  <property name="desktop-menu" type="empty">'
    echo '    <property name="show" type="bool" value="false"/>'
    echo '  </property>'
    echo '  <property name="windowlist-menu" type="empty">'
    echo '    <property name="show" type="bool" value="false"/>'
    echo '  </property>'
    echo '</channel>'
  } > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
  archpackage xfce4-panel
  add_unique "NoDisplay=true" ${APP}/xfce4-about.desktop
  add_unique "NoDisplay=true" ${APP}/exo-file-manager.desktop
  add_unique "NoDisplay=true" ${APP}/exo-mail-reader.desktop
  add_unique "NoDisplay=true" ${APP}/exo-terminal-emulator.desktop
  add_unique "NoDisplay=true" ${APP}/exo-web-browser.desktop
  sed -i -e ':a;N;$!ba;s/<Separator\/>\n\s*<Menuname>/<Menuname>/' /etc/xdg/menus/xfce-applications.menu
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<channel name="xfce4-panel" version="1.0">'
    echo '  <property name="configver" type="int" value="2"/>'
    echo '  <property name="panels" type="array">'
    echo '    <value type="int" value="1"/>'
    echo '    <property name="panel-1" type="empty">'
    echo '      <property name="position" type="string" value="p=6;x=0;y=0"/>'
    echo '      <property name="length" type="uint" value="100"/>'
    echo '      <property name="position-locked" type="bool" value="true"/>'
    echo '      <property name="size" type="uint" value="24"/>'
    echo '      <property name="plugin-ids" type="array">'
    echo '        <value type="int" value="1"/>'
    echo '        <value type="int" value="3"/>'
    echo '        <value type="int" value="14"/>'
    echo '        <value type="int" value="2"/>'
    echo '        <value type="int" value="9"/>'
    echo '        <value type="int" value="7"/>'
    echo '        <value type="int" value="13"/>'
    echo '        <value type="int" value="4"/>'
    echo '        <value type="int" value="5"/>'
    echo '        <value type="int" value="11"/>'
    echo '        <value type="int" value="12"/>'
    echo '        <value type="int" value="6"/>'
    echo '      </property>'
    echo '    </property>'
    echo '  </property>'
    echo '  <property name="plugins" type="empty">'
    echo '    <property name="plugin-1" type="string" value="applicationsmenu">'
    echo '      <property name="show-button-title" type="bool" value="false"/>'
    echo '    </property>'
    echo '    <property name="plugin-2" type="string" value="weather"/>'
    echo '    <property name="plugin-3" type="string" value="tasklist">'
    echo '      <property name="sort-order" type="uint" value="4"/>'
    echo '      <property name="flat-buttons" type="bool" value="true"/>'
    echo '  </property>'
    echo '    <property name="plugin-4" type="string" value="systemload"/>'
    echo '    <property name="plugin-5" type="string" value="clock">'
    echo '      <property name="mode" type="uint" value="2"/>'
    echo '      <property name="digital-format" type="string" value=" %H:%M"/>'
    echo '      <property name="show-frame" type="bool" value="false"/>'
    echo '    </property>'
    echo '    <property name="plugin-6" type="string" value="systray">'
    echo '      <property name="show-frame" type="bool" value="false"/>'
    echo '    </property>'
    echo '    <property name="plugin-9" type="string" value="xfce4-sensors-plugin"/>'
    echo '    <property name="plugin-11" type="string" value="mixer"/>'
    echo '    <property name="plugin-12" type="string" value="xfce4-clipman-plugin"/>'
    echo '    <property name="plugin-13" type="string" value="cpugraph"/>'
    echo '    <property name="plugin-14" type="string" value="separator">'
    echo '      <property name="expand" type="bool" value="true"/>'
    echo '      <property name="style" type="uint" value="0"/>'
    echo '    </property>'
    echo '    <property name="plugin-7" type="string" value="separator">'
    echo '      <property name="style" type="uint" value="0"/>'
    echo '    </property>'
    echo '  </property>'
    echo '</channel>'
  } > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
  archpackage xfce4-appfinder
  add_unique "NoDisplay=true" ${APP}/xfce4-appfinder.desktop
  archpackage xfce4-settings
  sed -i -e 's/"ThemeName".*/"ThemeName" type="string" value="Adwaita-dark"\/>/' \
    -e "s/sorThemeName\" type=\"string\" value=\"\"/sorThemeName\" type=\"string\" value=\"Adwaita\"/" \
    -e "s/sorThemeSize\" type=\"int\" value=\"0\"/sorThemeSize\" type=\"int\" value=\"32\"/" \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
  sed -i -e 's/needs\.$/&-->/' -e 's/XSettingsRegistry$/XSettingsRegistry -->/' \
    -e '/^-->/d' \
    -e 's/"Antialias" type="int" value="-1"/"Antialias" type="int" value="1"/' \
    -e 's/"RGBA" type="string" value="none"/"RGBA" type="string" value="rgb"/' \
    -e 's/"Hinting" type="int" value="-1"/"Hinting" type="int" value="1"/' \
    -e 's/type="string" value="hintfull"/type="string" value="hintmedium"/' \
    -e "s/Sans 10/Sans 8/" /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
  if [ -z ${WSL} ]; then
    archpackage xfce4-power-manager
    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<channel name="xfce4-power-manager" version="1.0">'
      echo '  <property name="xfce4-power-manager" type="empty">'
      echo '    <property name="brightness-switch-restore-on-exit" type="int" value="-1"/>'
      echo '    <property name="brightness-switch" type="int" value="0"/>'
      echo '    <property name="power-button-action" type="uint" value="4"/>'
      echo '    <property name="sleep-button-action" type="uint" value="1"/>'
      echo '    <property name="hibernate-button-action" type="uint" value="1"/>'
      echo '    <property name="lid-action-on-battery" type="uint" value="1"/>'
      echo '    <property name="logind-handle-lid-switch" type="bool" value="true"/>'
      echo '    <property name="lid-action-on-ac" type="uint" value="1"/>'
      echo '    <property name="show-tray-icon" type="int" value="1"/>'
      echo '    <property name="inactivity-sleep-mode-on-battery" type="uint" value="1"/>'
      echo '    <property name="inactivity-on-ac" type="uint" value="30"/>'
      echo '    <property name="inactivity-on-battery" type="uint" value="15"/>'
      echo '    <property name="critical-power-level" type="uint" value="5"/>'
      echo '    <property name="critical-power-action" type="uint" value="1"/>'
      echo '    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>'
      echo '    <property name="dpms-on-battery-sleep" type="uint" value="2"/>'
      echo '    <property name="dpms-on-battery-off" type="uint" value="3"/>'
      echo '    <property name="blank-on-ac" type="int" value="10"/>'
      echo '    <property name="dpms-on-ac-sleep" type="uint" value="11"/>'
      echo '    <property name="dpms-on-ac-off" type="uint" value="12"/>'
      echo '    <property name="brightness-level-on-ac" type="uint" value="80"/>'
      echo '    <property name="brightness-on-battery" type="uint" value="9"/>'
      echo '    <property name="blank-on-battery" type="int" value="1"/>'
      echo '  </property>'
      echo '</channel>'
    } > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml
  fi
  archpackage xfce4-terminal
  mkdir -p /etc/xdg/xfce4/terminal
  {
    echo "[Configuration]"
    echo -e "CommandLoginShell=TRUE\nScrollingOnOutput=FALSE"
    echo -e "ScrollingLines=10000\nFontName=Monospace 8"
    echo -e "TabActivityTimeout=30\nColorForeground=#0000ffff0000"
    echo -e "ColorCursor=#ffffffffffff\nTitleMode=TERMINAL_TITLE_HIDE"
  } > /etc/xdg/xfce4/terminal/terminalrc
  add_unique "NoDisplay=true" ${APP}/xfce4-terminal-settings.desktop
  sed -i -e "s/GTK;System;/Utility;/" -e "s/Name=Xfce /Name=/" ${APP}/xfce4-terminal.desktop
  archpackage xfce4-notifyd \
    xfce4-screenshooter \
    xfce4-taskmanager
  sed -i -e "s/System;Utility/Utility/" -e "s/utilities-system-monitor/xfsm-suspend/" ${APP}/xfce4-taskmanager.desktop
  archpackage xfce4-cpugraph-plugin
  echo -e 'UpdateInterval=3\nSize=24\nBars=0\nBackground=#000000000000' > /etc/xdg/xfce4/panel/cpugraph-13.rc
  archpackage xfce4-systemload-plugin
  {
    echo -e '[Main]\nTimeout=10000\nTimeout_Seconds=10\nUse_Timeout_Seconds=true\n'
    echo -e '[SL_Cpu]\nEnabled=false\n[SL_Mem]\nUse_Label=false\n'
    echo -e '[SL_Swap]\nUse_Label=false\n[SL_Uptime]\nEnabled=false'
  } > /etc/xdg/xfce4/panel/systemload-4.rc
  archpackage xfce4-weather-plugin
  echo 'label0=3' > /etc/xdg/xfce4/panel/weather-2.rc
  if [ -z ${WSL} ]; then
    archpackage xfce4-sensors-plugin
    add_unique "NoDisplay=true" ${APP}/xfce4-sensors.desktop
    echo -e '[General]\nShow_Title=false\nShow_Labels=false\nShow_Units=false\nUpdate_Interval=60' > /etc/xdg/xfce4/panel/xfce4-sensors-plugin-9.rc
  fi
  archpackage xfce4-clipman-plugin
  add_unique "NoDisplay=true" ${APP}/xfce4-clipman.desktop
  archpackage thunar \
    thunar-volman \
    thunar-archive-plugin \
    thunar-media-tags-plugin \
    tumbler
  sed -i -e "s/=Thunar File Manager/=Thunar/" ${APP}/thunar.desktop
  sed -i -e "s/System;Utility/Utility/" ${APP}/thunar.desktop
  sed -i -e "s/System;Utility/Utility/" ${APP}/thunar-bulk-rename.desktop
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<channel name="thunar" version="1.0">'
    echo '  <property name="last-view" type="string" value="ThunarDetailsView"/>'
    echo '  <property name="misc-folders-first" type="bool" value="false"/>'
    echo '  <property name="misc-date-style" type="string" value="THUNAR_DATE_STYLE_ISO"/>'
    echo '  <property name="default-view" type="string" value="ThunarDetailsView"/>'
    echo '  <property name="shortcuts-icon-size" type="string" value="THUNAR_ICON_SIZE_SMALLEST"/>'
    echo '  <property name="last-details-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_SMALLEST"/>'
    echo '  <property name="last-separator-position" type="int" value="120"/>'
    echo '  <property name="last-location-bar" type="string" value="ThunarLocationButtons"/>'
    echo '  <property name="last-details-view-visible-columns" type="string" value="THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_NAME,THUNAR_COLUMN_SIZE"/>'
    echo '  <property name="last-details-view-column-order" type="string" value="THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_SIZE,THUNAR_COLUMN_NAME,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_DATE_ACCESSED,THUNAR_COLUMN_OWNER,THUNAR_COLUMN_PERMISSIONS,THUNAR_COLUMN_MIME_TYPE,THUNAR_COLUMN_GROUP"/>'
    echo '  <property name="last-details-view-fixed-columns" type="bool" value="true"/>'
    echo '  <property name="misc-show-delete-action" type="bool" value="true"/>'
    echo '</channel>'
  } > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/thunar.xml

  # finish
  pacman -Rns $(pacman -Qtdq)
  journalctl --vacuum-time=1d
  find /etc -name *.pacnew
  find /home/${MAIN_USER}/ -not -user ${MAIN_USER}
fi