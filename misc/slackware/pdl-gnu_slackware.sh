#!/bin/sh

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/pdl-gnu_common.sh
if [ $(whoami) != root ]; then
  echo "fatal: not root user"
fi
exit 1

function heading()
{
  # print heading
  echo -e "\n==== ${1} ====\n"
}

function check_hdd()
{
  # print smart log, kernel output, and disk space
  cat /var/log/messages | grep SMART | tail
  sudo dmesg | grep ata
  /usr/sbin/smartctl -a /dev/sda | grep Temp
  df -h
}

function is_installed()
{
  # check if package is installed
  if [ -z ${1} ]; then
    echo "is_installed: missing input"
  elif get_installed ${1} > /dev/null; then
    return 0
  fi
  return 1
}

function get_installed()
{
  # print full package name
  if [ -z ${1} ]; then
    echo "get_installed: missing input"
  else
    OLD_PWD=${PWD}
    cd /var/log/packages
    for FILE in $(ls ${1}-*-*-* 2> /dev/null); do
      NAME=$(echo ${FILE} | rev | cut -d- -f4- | rev | head -1)
      if [ ${1} = ${NAME} ]; then
        cd ${OLD_PWD}
        echo ${FILE}
        return 0
      fi
    done
  fi
  cd ${OLD_PWD}
  echo "get_installed: ${1} not installed"
  return 1
}

function slackbuild()
{
  # install or upgrade a set of slackbuilds
  if [ -z ${1} ] || [ -z ${2} ]; then
    echo "slackbuild: missing input!"
  elif [ $(whoami) != root ]; then
    echo "slackbuild: run as root"
    exit 1
  else
    unset SET REST
    for ARG in "$@"; do
      if [ -z ${SET} ]; then
        SET=${ARG}
      else
        if [ $(expr index ${ARG} /) != 0 ]; then
          IVER=${ARG#*/}
          ARG=${ARG%/*}
        fi
        rm -fr /tmp/${ARG}* /tmp/SBo
        if [ -e "${DIR}"/${ARG}.tar.gz ]; then
          tar -xzf "${DIR}"/${ARG}.tar.gz -C /tmp/
        elif [ -d "${DIR}"/${ARG} ]; then
          cp -R "${DIR}"/${ARG} /tmp
        else
          wget -q slackbuilds.org/slackbuilds/${SW_VER}/${SET}/${ARG}.tar.gz \
            -O /tmp/${ARG}.tar.gz || exit 1
          tar -xzf /tmp/${ARG}.tar.gz -C /tmp/
        fi
        source /tmp/${ARG}/${ARG}.info
        if [ ! -z ${IVER} ]; then
          sed -i -e  "s/${VERSION}/${IVER}/" /tmp/${ARG}/${ARG}.info \
            /tmp/${ARG}/${ARG}.SlackBuild
          sed -i -e "s/\/${VERSION%.*}\//\/${IVER%.*}\//" \
            /tmp/${ARG}/${ARG}.info
          source /tmp/${ARG}/${ARG}.info
        fi
        BUILD=$(cat /tmp/${ARG}/${ARG}.SlackBuild | grep ^BUILD=)
        BUILD=${BUILD##*-}
        BUILD=${BUILD%\}}
        if is_installed ${ARG}; then
          PVER=$(get_installed ${ARG} | rev | cut -d- -f3 | rev)
          PVER=${PVER%%_$(uname -r | sed -e "s/-/_/g")}
          PBLD=$(get_installed ${ARG} | rev | cut -d- -f1 | rev)
          PBLD=${PBLD%%_*}
          if [ ${PVER} != ${VERSION} ] || [ ${PBLD} != ${BUILD} ] ; then
            heading "change: ${ARG} (${PVER})_${PBLD} > (${VERSION})_${BUILD}"
            REMOVE=yes
          elif [ ! -z ${REST} ] || [ ! -z ${REBUILD} ]; then
            heading "rebuild: ${ARG} (${PVER})_${PBLD}"
            REMOVE=yes
          else
            heading "skip: ${ARG} (${PVER})_${PBLD}"
          fi
        else
          heading "package: ${ARG} (${VERSION})_${BUILD}"
        fi
        if [ ! -z ${REMOVE} ]; then
          sleep 5
          for RC in $(cat /var/log/packages/$(get_installed $ARG) \
          | grep "etc/rc.d/rc\."); do
            [ -x /${RC%.new} ] && sh /${RC%.new} stop
          done
          echo "  removing $(get_installed ${ARG})..."
          removepkg ${ARG} 1> /dev/null
        fi
        if ! is_installed ${ARG}; then
          REST=yes
          ( cd /tmp/${ARG}
            [ ! -z ${MD5SUM_x86_64} ] && [ ! -z ${ARCH64} ] && \
              DOWNLOAD=${DOWNLOAD_x86_64}
            SOURCE=${DOWNLOAD/ */}
            echo "  downloading ${SOURCE##*/}..."
            if [ -z ${DEBUG} ]; then
              OUTPUT=-q
            fi
            for FILE in ${DOWNLOAD}; do
              if [ ! -e ${FILE##*/} ]; then
                if [ -e "${DIR}"/${FILE##*/} ]; then
                  ln -sf "${DIR}"/${FILE##*/} ${FILE##*/}
                else
                  wget --no-check-certificate ${OUTPUT} ${FILE} || exit 1
                fi
              fi
            done
            chmod +x ./${ARG}.SlackBuild
            echo "  running ${ARG}.SlackBuild..."
            if [ -z ${DEBUG} ]; then
              ./${ARG}.SlackBuild > /dev/null 2>&1 || exit 1
            else
              ./${ARG}.SlackBuild || exit 1
            fi
            echo "  installing $(ls /tmp/${ARG}-*-*-*.t?z)..."
            upgradepkg --install-new /tmp/${ARG}-*-*-*.t?z > /dev/null
          )
        fi
        rm -fr /tmp/${ARG}* /tmp/package-${ARG} /tmp/SBo
        unset ARG IVER REMOVE SET
      fi
    done
  fi
}

function upgrade_package()
{
  # download and/or upgrade/install a package file
  heading "package: ${1##*/}"
  if [ -e "${DIR}"/${1##*/} ]; then
    ln -sf "${DIR}"/${1##*/} /tmp/${1##*/}
  else
    echo "  downloading ${1##*/}..."
    wget -q ${1} -O /tmp/${1##*/} || exit 1
  fi
  echo "  installing/upgrading /tmp/${1##*/}..."
  upgradepkg --install-new /tmp/${1##*/} > /dev/null
  if [ -e "${DIR}"/${1##*/} ]; then
    rm -f /tmp/${1##*/}
  fi
}

# check version
SW_VER=14.1
SW_DL=http://slackware.oregonstate.edu/slackware${ARCH64}-${SW_VER}
if ! grep -q "Slackware ${SW_VER}" /etc/slackware-version; then
  echo "fatal: only ${SW_VER} is supported"
  exit 1
fi

# main user
mkdir -p /root/sources
echo "set nobackup" > /root/.vimrc
sed -i -e "s/power) \/sbin/power) #\/sbin/" /etc/acpi/acpi_handler.sh
if ! grep -q "^${MAIN_USER}:" /etc/passwd; then
  MAIN_GROUPS="audio,cdrom,games,lp,plugdev,power,video"
  useradd -c ${MAIN_USER} -g users -G ${MAIN_GROUPS} -m -s /bin/bash \
    ${MAIN_USER}
  passwd ${MAIN_USER}
fi
add_unique "Defaults rootpw" /etc/sudoers
add_unique "Defaults passwd_timeout=0" /etc/sudoers
add_unique "${MAIN_USER} ALL=PASSWD: ALL" /etc/sudoers
add_unique "${MAIN_USER} ALL=NOPASSWD: /bin/dmesg" /etc/sudoers
add_unique "${MAIN_USER} ALL=NOPASSWD: /sbin/halt" /etc/sudoers
add_unique "${MAIN_USER} ALL=NOPASSWD: /sbin/reboot" /etc/sudoers
echo "set nobackup" > /home/${MAIN_USER}/.vimrc
chown ${MAIN_USER}:users /home/${MAIN_USER}/.vimrc

# chuck orage+volumed, keep blue+gimp+gchar,im,ff,nma,pgin,rd,Xsane,x11,chat,xss
for PACKAGE in audacious audacious-plugins blackbox ddd electricsheep fluxbox \
fvwm geeqie gftp gkrellm gnuchess gnuplot gv mozilla-thunderbird pan rxvt \
seamonkey seyon vim-gvim windowmaker x3270 xaos xfractint xgames xine-lib \
xine-ui xlockmore xmms xpaint xpdf xv orage xfce4-volumed; do
  if is_installed ${PACKAGE}; then
    removepkg ${PACKAGE}
  fi
done

# fstab
sed -i -e "s/#' | grep -w/#' | grep -v noauto | grep -w/" /etc/rc.d/rc.inet2
sed -i -e "s/defaults         1   1/defaults,relatime 1   1/" /etc/fstab
[ ! -e /dev/fd0 ] && sed -i -e "s/^\/dev\/fd0/#&/" /etc/fstab

# mixer
amixer -q set Center,0 100% unmute &> /dev/null
amixer -q set LFE,0 100% unmute &> /dev/null
amixer -q set Side,0 100% unmute &> /dev/null
amixer -q set Surround,0 100% unmute &> /dev/null
amixer -q set Master,0 50% unmute &> /dev/null
alsactl store

# mariadb
if [ ! -d /var/lib/mysql/mysql ]; then
  mysql_install_db --user=mysql
  sh /etc/rc.d/rc.mysqld start
  sleep 5
  mysql -u root -e "DROP DATABASE test"
  mysql -u root -e "DELETE FROM mysql.user WHERE user = ''"
  mysql -u root -e "DELETE FROM mysql.user WHERE host != 'localhost'"
  mysql -u root -e "FLUSH PRIVILEGES"
  echo "input mysql root passwd:"
  read -s MYSQL_PASSWD
  /usr/bin/mysqladmin -u root password ${MYSQL_PASSWD}
  unset MYSQL_PASSWD
  sh /etc/rc.d/rc.mysqld stop
fi

# rc.d
! grep -q PreloaderPageZeroProblem /etc/rc.d/rc.local && \
{
  echo "# http://wiki.winehq.org/PreloaderPageZeroProblem"
  echo -e "/sbin/sysctl -w vm.mmap_min_addr=0\n"
} >> /etc/rc.d/rc.local
[ ! -e /etc/rc.d/rc.local_shutdown ] && \
  echo -e '#!/bin/sh\n' > /etc/rc.d/rc.local_shutdown
chmod +x /etc/rc.d/rc.local_shutdown
chmod -x /etc/rc.d/rc.inetd

# samba
cp -n /etc/samba/smb.conf-sample /etc/samba/smb.conf
sed -i -e "s/string = Samba Server/string = $(hostname).$(dnsdomainname)/" \
  -e "s/workgroup = MYGROUP/workgroup = PRIMARYDATALOOP/" /etc/samba/smb.conf
mkdir -p /mnt/Datavault
if [ "$(e2label /dev/sdb1 2> /dev/null)" = "Datavault" ]; then
  add_unique "/dev/sdb1        /mnt/Datavault   ext4        defaults,noatime 1   1" \
    /etc/fstab
  if ! grep -q "^simba:" /etc/passwd; then
    useradd -c simba -d / -g users -s /bin/false simba
    echo "simba smbpasswd"
    smbpasswd -a simba
    echo "${MAIN_USER} smbpasswd"
    smbpasswd -a ${MAIN_USER}
  fi
  sed -i -e "s/load printers = yes/load printers = no/" \
    -e "s/;   printcap name = lpstat/   printcap name = \/dev\/null/" \
    -e "s/;   printing = cups/   printing = bsd\n   disable spoolss = yes/" \
    -e ':a;N;$!ba;s/^\[homes\]\n.*\n.*\n   writable = yes/#[homes]/' \
    /etc/samba/smb.conf
  ! grep -q "\[Datavault\]" /etc/samba/smb.conf && \
  {
    echo "[Datavault]"
    echo "   browseable = no"
    echo "   case sensitive = yes"
    echo "   create mask = 0644"
    echo "   path = /mnt/Datavault"
    echo "   valid users = ${MAIN_USER}"
    echo -e "   writable = yes\n"
  } >> /etc/samba/smb.conf
  ! grep -q "\[Video\]" /etc/samba/smb.conf && \
  {
    echo "[Video]"
    echo "   path = /mnt/Datavault/Video"
    echo -e "   writable = no\n"
  } >> /etc/samba/smb.conf
  chmod +x /etc/rc.d/rc.samba
elif [ ! -e /root/.dvcred ]; then
  echo "username=${MAIN_USER}" > /root/.dvcred
  echo "//euclid/Datavault /mnt/Datavault cifs noauto,credentials=/root/.dvcred 0   0" \
    >> /etc/fstab
fi

# startup
[ -z ${ARCH64} ] && [[ $(uname -r) == *-smp ]] && SMP=-smp
if [[ $(readlink /boot/vmlinuz) == *vmlinuz-huge* ]]; then
  VERSION=$(ls /boot/config-generic-*${SMP} | grep -m 1 -o \[0-9\.]*)
  CK=3.10-ck1
  if [ $(hostname) = euclid ]; then
    CK=3.12-ck2
    removepkg kernel-source
    tar xxf "${DIR}"/linux-3.12.40.tar.xz -C /usr/src
    ln -sfn /usr/src/linux-3.12.40 /usr/src/linux
    if [ ! -z ${ARCH64} ]; then
      cp "${DIR}"/config-generic-3.12.x64 /boot/config-generic-3.12.40
    else
      cp "${DIR}"/config-generic-3.12 /boot/config-generic-3.12.40
      cp "${DIR}"/config-generic-smp-3.12-smp \
        /boot/config-generic-smp-3.12.40-smp
    fi
    chmod -x /boot/config-generic-*3.12.40*
    cp /etc/rc.d/rc.modules-${VERSION}${SMP} /etc/rc.d/rc.modules-3.12.40${SMP}
    VERSION=3.12.40
  fi
  ln -sfn /etc/rc.d/rc.modules-${VERSION}${SMP} /etc/rc.d/rc.modules
  ( cd /usr/src/linux
    if [ -e patch-${CK}.bz2 ]; then
      make mrproper
    else
      cp "${DIR}"/patch-${CK}.bz2 .
    fi
    cat patch-${CK} | patch -Np1
    cp /boot/config-generic${SMP}-${VERSION}${SMP} .config
    if cat /proc/cpuinfo | grep -q "Intel(R) Core(TM)2" \
    || cat /proc/cpuinfo | grep -q "Pentium(R) Dual-Core"; then
      CPU=MCORE2
    elif cat /proc/cpuinfo | grep -q "Pentium(R) 4" \
    || cat /proc/cpuinfo | grep -q "Pentium(R) D"; then
      if [ -z ${ARCH64} ]; then
        CPU=MPENTIUM4
      else
        CPU=MPSC
      fi
    elif cat /proc/cpuinfo | grep -q "Pentium(R) M" \
    || cat /proc/cpuinfo | grep -q "Intel(R) Core(TM)"; then
      CPU=MPENTIUMM
    elif cat /proc/cpuinfo | grep -q "AMD"; then
      CPU=MK8
    else
      CPU=MPENTIUMIII
    fi
    sed -i -e "s/_LOCALVERSION=\"${SMP}\"/_LOCALVERSION=\"${SMP}-pdl\"/" \
      -e "s/CONFIG_PREEMPT_VOLUNTARY=y/CONFIG_PREEMPT=y/" \
      -e "s/CONFIG_EXT4_FS=m/CONFIG_EXT4_FS=y/" \
      -e "s/^CONFIG_M486=y/CONFIG_${CPU}=y/" \
      -e "s/^CONFIG_GENERIC_CPU=y/CONFIG_${CPU}=y/" \
      -e "s/^CONFIG_MPENTIUMIII=y/CONFIG_${CPU}=y/" \
      -e "s/^CONFIG_DEBUG_KERNEL=y/CONFIG_DEBUG_KERNEL=n/" .config
    yes "" | make oldconfig
    make -j$(($(nproc)*4))
    make modules_install
    if [ -z ${ARCH64} ]; then
      cp arch/i386/boot/bzImage \
        /boot/vmlinuz-generic${SMP}-${VERSION}-${CK}${SMP}-pdl
    else
      cp arch/x86/boot/bzImage \
        /boot/vmlinuz-generic${SMP}-${VERSION}-${CK}${SMP}-pdl
    fi
    cp System.map /boot/System.map-generic${SMP}-${VERSION}-${CK}${SMP}-pdl
    cp .config /boot/config-generic${SMP}-${VERSION}-${CK}${SMP}-pdl
  )
  ln -sf /boot/System.map-generic${SMP}-${VERSION}-${CK}${SMP}-pdl \
    /boot/System.map
  ln -sf /boot/config-generic${SMP}-${VERSION}-${CK}${SMP}-pdl /boot/config
  ln -sf /boot/vmlinuz-generic${SMP}-${VERSION}-${CK}${SMP}-pdl /boot/vmlinuz
  if ! blkid | grep -q ntfs; then
    sed -i -e "s/^other = /#&/" -e "s/^  label = Windows/#&/" \
      -e "s/^  table = /#&/" /etc/lilo.conf
  fi
  sed -i -e "s/timeout = 1200/timeout = 40/" \
    -e "s/#compact/default = linux\n&/" /etc/lilo.conf
  removepkg virtualbox-kernel
  lilo
  REBOOT=yes
fi
touch /etc/modprobe.d/blacklist.conf /etc/modprobe.d/sound.conf
add_unique "blacklist nouveau" /etc/modprobe.d/blacklist.conf
add_unique "blacklist mei_me" /etc/modprobe.d/blacklist.conf
sed -i -e "s/^CPUFREQ=battery/CPUFREQ=on/" $(readlink /etc/rc.d/rc.modules)
chmod -x /etc/rc.d/rc.networkmanager
if [ $(hostname) = euclid ]; then
  add_unique "/sbin/modprobe coretemp" $(readlink /etc/rc.d/rc.modules)
elif [ $(hostname) = lovelace ]; then
  add_unique "/sbin/modprobe f71882fg" $(readlink /etc/rc.d/rc.modules)
elif [ $(hostname) = kepler ]; then
  add_unique "/sbin/modprobe coretemp" $(readlink /etc/rc.d/rc.modules)
  add_unique "/sbin/modprobe w83627ehf" $(readlink /etc/rc.d/rc.modules)
elif [ $(hostname) = newton ]; then
  chmod +x /etc/rc.d/rc.networkmanager
elif [ $(hostname) = archimedes ]; then
  chmod +x /etc/rc.d/rc.networkmanager
fi
{
  echo 'KERNEL=="event[0-9]*", ENV{ID_BUS}=="?*", ENV{ID_INPUT_JOYSTICK}=="?*", GROUP="games", MODE="0660"'
  echo 'KERNEL=="js[0-9]*", ENV{ID_BUS}=="?*", ENV{ID_INPUT_JOYSTICK}=="?*", GROUP="games", MODE="0664"'
} > /etc/udev/rules.d/99-joystick.rules
if [ ! -z ${REBOOT} ]; then
  reboot
  exit 0
fi

# download updates
if [ -z ${1} ]; then
  MIRROR=http:\\/\\/carroll.aset.psu.edu\\/pub\\/linux\\/distributions\\/slackware\\/slackware${ARCH64}-${SW_VER}
  sed -i -e "s/^# ${MIRROR}/${MIRROR}/" /etc/slackpkg/mirrors
  add_unique "freetype" /etc/slackpkg/blacklist
  add_unique "ddd" /etc/slackpkg/blacklist
  add_unique "[0-9]+alien" /etc/slackpkg/blacklist
  if ! is_installed kdelibs; then
    add_unique "kde" /etc/slackpkg/blacklist
    add_unique "kdei" /etc/slackpkg/blacklist
  fi
  add_unique "MPlayer" /etc/slackpkg/blacklist
  add_unique "Thunar" /etc/slackpkg/blacklist
  sed -i -e "s/^#kernel/kernel/" /etc/slackpkg/blacklist
  if [[ $(slackpkg check-updates) != *"No news"* ]]; then
    slackpkg update
  fi
  slackpkg -dialog=off install-new
  slackpkg -dialog=off upgrade-all
  sleep 5
fi

# multilib
if [ ! -z ${ARCH64} ] && ! is_installed compat32-tools; then
  ML_DL=taper.alienbase.nl/mirrors/people/alien/multilib/${SW_VER}
  wget -r -np ${ML_DL}/ || exit 1
  upgradepkg --reinstall --install-new ${ML_DL}/*alien.t?z
  upgradepkg --install-new ${ML_DL}/slackware64-compat32/*-compat32/*.t?z
  rm -fr ${ML_DL/\/*} *alien.t?z
fi

# httpd
sed -i -e "s/^ServerAdmin you@example.com/ServerAdmin apache/" \
  -e "s/#ServerName www.example.com:80/ServerName 127.0.0.1:80/" \
  -e "s/AllowOverride none/AllowOverride all/" \
  -e "s/DirectoryIndex index.html/DirectoryIndex index.php index.html/" \
  -e "s/#Include \/etc\/httpd\/mod_php/Include \/etc\/httpd\/mod_php/" \
  /etc/httpd/httpd.conf
add_unique "Listen 8080" /etc/httpd/httpd.conf

# ntp
sed -i -e "s/^#server/server/" /etc/ntp.conf
chmod +x /etc/rc.d/rc.ntpd

# smartd
sed -i -e "s/^DEVICESCAN$/& -I 190 -I 194/" /etc/smartd.conf
! grep -q "smartd" /etc/rc.d/rc.local && \
{
  echo "# start smartd"
  echo -e "/usr/sbin/smartd\n"
} >> /etc/rc.d/rc.local

# xdg/xfce
add_unique "NoDisplay=true" ${APP}/CMake.desktop
sed -i -e "s/GTK;System;/Utility;/" ${APP}/xfce4-terminal.desktop
sed -i -e "s/Name=Xfce /Name=/" ${APP}/xfce4-terminal.desktop
add_unique "NoDisplay=true" ${APP}/assistant.desktop
add_unique "NoDisplay=true" ${APP}/blueman-manager.desktop
add_unique "NoDisplay=true" ${APP}/cups.desktop
add_unique "NoDisplay=true" ${APP}/dconf-editor.desktop
add_unique "NoDisplay=true" ${APP}/designer.desktop
add_unique "NoDisplay=true" ${APP}/distccmon-gnome.desktop
add_unique "NoDisplay=true" ${APP}/exo-file-manager.desktop
add_unique "NoDisplay=true" ${APP}/exo-mail-reader.desktop
add_unique "NoDisplay=true" ${APP}/exo-terminal-emulator.desktop
add_unique "NoDisplay=true" ${APP}/exo-web-browser.desktop
sed -i -e "s/Name=GNU Image Manipulation Program/Name=GIMP/" ${APP}/gimp.desktop
add_unique "NoDisplay=true" ${APP}/glade-3.desktop
add_unique "NoDisplay=true" ${APP}/gpa.desktop
add_unique "NoDisplay=true" ${APP}/hplip.desktop
add_unique "NoDisplay=true" ${APP}/htop.desktop
add_unique "NoDisplay=true" ${APP}/linguist.desktop
sed -i -e "s/Name=Pidgin Internet Messenger/Name=Pidgin/" ${APP}/pidgin.desktop
add_unique "NoDisplay=true" ${APP}/qtconfig.desktop
add_unique "NoDisplay=true" ${APP}/qv4l2.desktop
add_unique "NoDisplay=true" ${APP}/scim.desktop
add_unique "NoDisplay=true" ${APP}/scim-setup.desktop
sed -i -e "s/System;//" ${APP}/system-config-printer.desktop
add_unique "NoDisplay=true" ${APP}/uxterm.desktop
add_unique "NoDisplay=true" ${APP}/wpa_gui.desktop
sed -i -e "s/^Name=XChat IRC/Name=XChat/" ${APP}/xchat.desktop
add_unique "NoDisplay=true" ${APP}/xfce-wm-settings.desktop
add_unique "NoDisplay=true" ${APP}/xfce-wmtweaks-settings.desktop
add_unique "NoDisplay=true" ${APP}/xfce4-about.desktop
add_unique "NoDisplay=true" ${APP}/xfce4-appfinder.desktop
add_unique "NoDisplay=true" ${APP}/xfce4-clipman.desktop
add_unique "NoDisplay=true" ${APP}/xfce4-mixer.desktop
sed -i -e "s/System;Utility/System/" ${APP}/xfce4-taskmanager.desktop
sed -i -e "s/XSane - Scanning/XSane/" ${APP}/xsane.desktop
add_unique "NoDisplay=true" ${APP}/xscreensaver-properties.desktop
add_unique "NoDisplay=true" ${APP}/xterm.desktop
add_unique "NoDisplay=true" ${APP}/zenmap.desktop
add_unique "NoDisplay=true" ${APP}/zenmap-root.desktop
add_unique "Hidden=true" /etc/xdg/autostart/blueman.desktop
add_unique "Hidden=true" /etc/xdg/autostart/hplip-systray.desktop
add_unique "Hidden=true" /etc/xdg/autostart/xscreensaver.desktop
sed -i -e ':a;N;$!ba;s/<Separator\/>\n\s*<Menuname>/<Menuname>/' \
  /etc/xdg/menus/xfce-applications.menu
if ! grep -q SaveOnExit \
/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml; then
  sed -i -e 's/value="Failsafe"\/>/&\n<property name="SaveOnExit" type="bool" value="false"\/>/' \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
fi
{
  echo 'UpdateInterval=3'
  echo 'Size=24'
  echo 'Bars=0'
  echo 'Background=#000000000000'
} > /etc/xdg/xfce4/panel/cpugraph-13.rc
{
  echo '[Main]'
  echo 'Timeout=10000'
  echo 'Timeout_Seconds=10'
  echo -e 'Use_Timeout_Seconds=true\n'
  echo '[SL_Cpu]'
  echo -e 'Enabled=false\n'
  echo '[SL_Mem]'
  echo -e 'Use_Label=false\n'
  echo '[SL_Swap]'
  echo -e 'Use_Label=false\n'
  echo '[SL_Uptime]'
  echo 'Enabled=false'
} > /etc/xdg/xfce4/panel/systemload-4.rc
echo 'label0=3' > /etc/xdg/xfce4/panel/weather-2.rc
{
  echo "card=$(cat /proc/asound/cards | grep -m 1 irq | awk '{print $1$2}' | \
    sed -e s/[-=]//g)Alsamixer"
  echo 'track=Master'
  echo 'command=xfce4-mixer'
} > /etc/xdg/xfce4/panel/xfce4-mixer-plugin-11.rc
{
  echo '[General]'
  echo 'Show_Title=false'
  echo 'Show_Labels=false'
  echo 'Show_Units=false'
  echo 'Update_Interval=60'
} > /etc/xdg/xfce4/panel/xfce4-sensors-plugin-9.rc
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
  echo '        <value type="int" value="6"/>'
  echo '        <value type="int" value="10"/>'
  echo '        <value type="int" value="12"/>'
  echo '        <value type="int" value="2"/>'
  echo '        <value type="int" value="7"/>'
  echo '        <value type="int" value="9"/>'
  echo '        <value type="int" value="13"/>'
  echo '        <value type="int" value="4"/>'
  echo '        <value type="int" value="8"/>'
  echo '        <value type="int" value="5"/>'
  echo '        <value type="int" value="11"/>'
  echo '      </property>'
  echo '    </property>'
  echo '  </property>'
  echo '  <property name="plugins" type="empty">'
  echo '    <property name="plugin-1" type="string" value="applicationsmenu">'
  echo '      <property name="show-button-title" type="bool" value="false"/>'
  echo '    </property>'
  echo '    <property name="plugin-2" type="string" value="weather"/>'
  echo '    <property name="plugin-3" type="string" value="tasklist"/>'
  echo '    <property name="plugin-4" type="string" value="systemload"/>'
  echo '    <property name="plugin-5" type="string" value="clock">'
  echo '      <property name="show-frame" type="bool" value="false"/>'
  echo '    </property>'
  echo '    <property name="plugin-6" type="string" value="systray">'
  echo '      <property name="show-frame" type="bool" value="false"/>'
  echo '    </property>'
  echo '    <property name="plugin-7" type="string" value="separator">'
  echo '      <property name="style" type="uint" value="0"/>'
  echo '    </property>'
  echo '    <property name="plugin-8" type="string" value="separator">'
  echo '      <property name="style" type="uint" value="0"/>'
  echo '    </property>'
  echo '    <property name="plugin-9" type="string" value="xfce4-sensors-plugin"/>'
  echo '    <property name="plugin-10" type="string" value="xfce4-notes-plugin-47"/>'
  echo '    <property name="plugin-11" type="string" value="xfce4-mixer-plugin"/>'
  echo '    <property name="plugin-12" type="string" value="xfce4-clipman-plugin"/>'
  echo '    <property name="plugin-13" type="string" value="cpugraph"/>'
  echo '    <property name="plugin-14" type="string" value="separator">'
  echo '      <property name="expand" type="bool" value="true"/>'
  echo '      <property name="style" type="uint" value="0"/>'
  echo '    </property>'
  echo '    <property name="notes" type="empty">'
  echo '      <property name="global" type="empty">'
  echo '        <property name="font-description" type="string" value="Monospace 8"/>'
  echo '      </property>'
  echo '    </property>'
  echo '  </property>'
  echo '</channel>'
} > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<channel name="xfce4-desktop" version="1.0">'
  echo '  <property name="desktop-icons" type="empty">'
  echo '    <property name="file-icons" type="empty">'
  echo '      <property name="show-removable" type="bool" value="false"/>'
  echo '      <property name="show-trash" type="bool" value="false"/>'
  echo '      <property name="show-filesystem" type="bool" value="false"/>'
  echo '    </property>'
  echo '    <property name="icon-size" type="uint" value="32"/>'
  echo '  </property>'
  echo '  <property name="backdrop" type="empty">'
  echo '    <property name="screen0" type="empty">'
  echo '      <property name="monitor0" type="empty">'
  echo '        <property name="image-path" type="string" value="/usr/share/pixmaps/gdm-foot-logo.png"/>'
  echo '        <property name="last-image" type="string" value="/usr/share/pixmaps/gdm-foot-logo.png"/>'
  echo '        <property name="last-single-image" type="string" value="/usr/share/pixmaps/gdm-foot-logo.png"/>'
  echo '        <property name="image-style" type="int" value="1"/>'
  echo '        <property name="color1" type="array">'
  echo '          <value type="uint" value="0"/>'
  echo '          <value type="uint" value="0"/>'
  echo '          <value type="uint" value="0"/>'
  echo '          <value type="uint" value="65535"/>'
  echo '        </property>'
  echo '      </property>'
  echo '    </property>'
  echo '  </property>'
  echo '  <property name="desktop-menu" type="empty">'
  echo '    <property name="show" type="bool" value="false"/>'
  echo '  </property>'
  echo '  <property name="windowlist-menu" type="empty">'
  echo '    <property name="show" type="bool" value="false"/>'
  echo '  </property>'
  echo '</channel>'
} > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
sed -i -e 's/needs\.$/&-->/' -e 's/XSettingsRegistry$/XSettingsRegistry-->/' \
  -e '/^-->/d' -e 's/"DPI" type="empty"/"DPI" type="int" value="95"/' \
  -e 's/"Antialias" type="int" value="-1"/"Antialias" type="int" value="1"/' \
  -e 's/"RGBA" type="string" value="none"/"RGBA" type="string" value="rgb"/' \
  -e 's/"HintStyle" type="string" value="hintnone"/"HintStyle" type="string" value="hintfull"/' \
  -e "s/Sans 10/Sans 8/" /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<channel name="xfce4-notifyd" version="1.0">'
  echo '  <property name="theme" type="string" value="Smoke"/>'
  echo '</channel>'
} > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<channel name="xfce4-power-manager" version="1.0">'
  echo '  <property name="xfce4-power-manager" type="empty">'
  echo '    <property name="lid-action-on-ac" type="uint" value="0"/>'
  echo '    <property name="lid-action-on-battery" type="uint" value="1"/>'
  echo '    <property name="inactivity-on-battery" type="uint" value="15"/>'
  echo '    <property name="critical-power-action" type="uint" value="1"/>'
  echo '    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>'
  echo '    <property name="critical-power-level" type="uint" value="3"/>'
  echo '    <property name="brightness-on-battery" type="uint" value="10"/>'
  echo '    <property name="brightness-level-on-battery" type="uint" value="10"/>'
  echo '    <property name="dpms-on-ac-sleep" type="uint" value="4"/>'
  echo '    <property name="dpms-on-ac-off" type="uint" value="5"/>'
  echo '    <property name="dpms-on-battery-sleep" type="uint" value="1"/>'
  echo '    <property name="dpms-on-battery-off" type="uint" value="2"/>'
  echo '    <property name="brightness-level-on-ac" type="uint" value="100"/>'
  echo '    <property name="brightness-on-ac" type="uint" value="9"/>'
  echo '  </property>'
  echo '</channel>'
} > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml
mkdir -p /etc/xdg/xfce4/terminal
{
  echo "[Configuration]"
  echo "CommandLoginShell=TRUE"
  echo "ScrollingOnOutput=FALSE"
  echo "ScrollingLines=10000"
  echo "FontName=Monospace 8"
  echo "TabActivityTimeout=30"
  echo "ColorForeground=#0000ffff0000"
  echo "ColorCursor=#ffffffffffff"
  echo "TitleMode=TERMINAL_TITLE_HIDE"
} > /etc/xdg/xfce4/terminal/terminalrc

# cabextract
slackbuild system cabextract

# devede
slackbuild \
  multimedia dvdauthor \
  multimedia vcdimager \
  multimedia devede

# dia
slackbuild graphics dia
sed -i -e "s/^Name=Dia Diagram Editor/Name=Dia/" ${APP}/dia.desktop

# easytag
slackbuild \
  libraries id3lib \
  audio easytag

# office/evince (2.32.0)
slackbuild PRIMARYDATALOOP evince
sed -i -e "s/Name=Document Viewer/Name=Evince/" ${APP}/evince.desktop

# system/file-roller (2.32.2)
slackbuild PRIMARYDATALOOP file-roller

# flashplayer-plugin
slackbuild multimedia flashplayer-plugin
add_unique "NoDisplay=true" ${APP}/flash-player-properties.desktop
rm -fr /LGPL

# flite
slackbuild accessibility flite

# freetype
ln -sf /etc/fonts/conf.avail/10-autohint.conf /etc/fonts/conf.d/
if [[ $(get_installed freetype) != freetype*pdl ]]; then
  removepkg freetype > /dev/null
fi
slackbuild PRIMARYDATALOOP freetype

# academic/gcalctool (5.32.2)
slackbuild PRIMARYDATALOOP gcalctool

# gdm
slackbuild \
  libraries libgnomecanvas \
  system gdm
rm -f /usr/share/xsessions/afterstep.desktop
rm -f /usr/share/xsessions/enlightenment.desktop
rm -f /usr/share/xsessions/gnome.desktop
if ! is_installed kdelibs; then
  rm -f /usr/share/xsessions/kde.desktop
fi
rm -f /usr/share/xsessions/ssh.desktop
sed -i -e "s/Name=Xfce Session/Name=Xfce/" /usr/share/xsessions/xfce.desktop
sed -i -e "s/-x \"\$HOME\/.xsession\"/-e \"\$HOME\/.xinitrc\"/" \
  -e "s/command=\"\$HOME\/.xsession\"/command=\"sh \$HOME\/.xinitrc\"/" \
  -e "s/Cannot find ~\/.xsession/Cannot find ~\/.xinitrc/" /etc/gdm/Xsession
sed -i -e "s/User Dot xsession/User Dot xinitrc/" \
  -e "s/.xsession file/.xinitrc file/" /usr/share/xsessions/dotxsession.desktop
if ! grep -q Use24Clock /etc/gdm/custom.conf; then
  sed -i -e "s/\[daemon\]/&\nSessionDesktopDir=\/usr\/share\/xsessions\//" \
    /etc/gdm/custom.conf
  if /sbin/lsmod | grep -q -w battery || dmesg | grep -q "VBOX HARDDISK"; then
    sed -i -e "s/Dir=\/usr\/share\/xsessions\//&\nTimedLoginEnable=true/" \
      -e "s/TimedLoginEnable=true/&\nTimedLogin=${MAIN_USER}/" \
      -e "s/TimedLogin=${MAIN_USER}/&\nTimedLoginDelay=10/" \
      /etc/gdm/custom.conf
  fi
  sed -i -e "s/\[security\]/&\nAllowRoot=false/" \
    -e "s/\[gui\]/&\nGtkTheme=Clearlooks/" \
    -e "s/GtkTheme=Clearlooks/&\nAllowGtkThemeChange=false/" \
    -e "s/\[greeter\]/&\nDefaultWelcome=false/" \
    -e "s/DefaultWelcome=false/&\nWelcome=%n/" \
    -e "s/Welcome=%n/&\nTitleBar=false/" \
    -e "s/TitleBar=false/&\nQuiver=false/" \
    -e "s/Quiver=false/&\nConfigAvailable=false/" \
    -e "s/ConfigAvailable=false/&\nChooserButton=false/" \
    -e "s/ChooserButton=false/&\nBackgroundColor=#000000/" \
    -e "s/BackgroundColor=#000000/&\nShowGnomeFailsafeSession=false/" \
    -e "s/ShowGnomeFailsafeSession=false/&\nShowLastSession=false/" \
    -e "s/ShowLastSession=false/&\nUse24Clock=true/" \
    /etc/gdm/custom.conf
  add_unique "NoDisplay=true" /usr/share/gdm/applications/gdmsetup.desktop
fi
wget -q http://i.imgur.com/LxsTF.jpg -O /usr/share/pixmaps/gdm-foot-logo.png

# gedit
slackbuild \
  libraries gtksourceview \
  python pygtksourceview \
  development gedit \
  development gedit-plugins
gconf boo /apps/gedit-2/preferences/editor/line_numbers/display_line_numbers true
gconf boo /apps/gedit-2/preferences/editor/right_margin/display_right_margin true
gconf boo /apps/gedit-2/preferences/editor/current_line/highlight_current_line true
gconf boo /apps/gedit-2/preferences/editor/bracket_matching/bracket_matching true
gconf int /apps/gedit-2/preferences/editor/tabs/tabs_size 2
gconf boo /apps/gedit-2/preferences/editor/tabs/insert_spaces true
gconf str /apps/gedit-2/preferences/editor/wrap_mode/wrap_mode "GTK_WRAP_NONE"
gconf boo /apps/gedit-2/preferences/editor/font/use_default_font false
gconf str /apps/gedit-2/preferences/editor/font/editor_font "Monospace 8"

# gst-ffmpeg
slackbuild multimedia gst-ffmpeg

# gst-plugins-bad
slackbuild \
  audio faad2 \
  libraries libdvdcss \
  libraries libdvdnav \
  multimedia gst-plugins-bad

# gst-plugins-ugly
slackbuild \
  audio a52dec \
  multimedia gst-plugins-ugly

# gst-python
slackbuild python gst-python

# gtk-engines
slackbuild desktop gtk-engines
sed -i -e 's/"ThemeName" type="empty"/"ThemeName" type="string" value="Clearlooks"/' \
  /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml

# lame
slackbuild libraries lame

# libreoffice
ARCH=i486
[ ! -z ${ARCH64} ] && ARCH=x86_64
LO=libreoffice-4.4.1-${ARCH}-1alien
if [[ $(get_installed libreoffice) != ${LO} ]]; then
  upgrade_package http://taper.alienbase.nl/mirrors/people/alien/slackbuilds/libreoffice/pkg${ARCH64}/${SW_VER}/${LO}.txz
  rm -fr /root/libreoffice /tmp/lu*.tmp
fi
add_unique "NoDisplay=true" ${APP}/libreoffice-extension-manager.desktop
sed -i -e "s/;Graphics//" ${APP}/libreoffice-draw.desktop
sed -i -e "s/NoDisplay=true/NoDisplay=false/" -e "s/;Education//" \
  ${APP}/libreoffice-math.desktop
sed -i -e "s/NoDisplay=false/NoDisplay=true/" \
  ${APP}/libreoffice-startcenter.desktop

# metacity
slackbuild \
  desktop zenity \
  desktop metacity/2.30.3
if [ ! -d /usr/share/themes/Clearlooks/metacity-1 ]; then
  wget -q ftp.gnome.org/pub/GNOME/sources/gnome-themes/2.32/gnome-themes-2.32.1.tar.bz2 || exit 1
  tar -xjf gnome-themes-2.32.1.tar.bz2
  mv gnome-themes-2.32.1/metacity-themes/Clearlooks \
    /usr/share/themes/Clearlooks/metacity-1
  rm -fr gnome-themes-2.32.1 gnome-themes-2.32.1.tar.bz2
fi
sed -i -e "s/\"xfwm4\"/\"metacity\"/" \
  /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml

# x264
slackbuild multimedia x264

# mplayer (recompilation for lame)
MPLAYER=20130819
if [[ $(get_installed MPlayer) != *pdl ]]; then
  heading "install: MPlayer (${MPLAYER})"
  mkdir /root/MPlayer
  ( cd /root/MPlayer
    echo "  downloading MPlayer-${MPLAYER}.tar.xz..."
    wget -q ${SW_DL}/source/xap/MPlayer/Blue-1.8.tar.bz2 || exit 1
    wget -q ${SW_DL}/source/xap/MPlayer/MPlayer.SlackBuild
    wget -q ${SW_DL}/source/xap/MPlayer/MPlayer_nolibdvdcss-${MPLAYER}.tar.xz \
      -O MPlayer-${MPLAYER}.tar.xz || exit 1
    wget -q ${SW_DL}/source/xap/MPlayer/ffmpeg-20130505.tar.xz
    wget -q ${SW_DL}/source/xap/MPlayer/slack-desc
    echo "  running MPlayer.SlackBuild..."
    sed -i -e "s/\${BUILD:-2}/\${BUILD:-2pdl}/" MPlayer.SlackBuild
    USE_PATENTS=YES sh MPlayer.SlackBuild > /dev/null 2>&1 || exit 1
    echo "  installing /tmp/MPlayer-${MPLAYER}.txz..."
    installpkg /tmp/MPlayer-*-*.txz > /dev/null || exit 1
  )
  rm -fr /tmp/*MPlayer* /tmp/build /root/MPlayer
fi
add_unique "NoDisplay=true" ${APP}/mplayer.desktop

# node
slackbuild network node

# p7zip
slackbuild system p7zip

# prelink
slackbuild system prelink

# audio/rhythmbox (1.13.3)
USE_GSTPROP=no slackbuild \
  libraries totem-pl-parser \
  libraries gnome-media \
  PRIMARYDATALOOP rhythmbox
gconf boo /apps/rhythmbox/monitor_library true
gconf boo /apps/rhythmbox/plugins/status-icon/active true
gconf int /apps/rhythmbox/plugins/status-icon/notification-mode 0
gconf int /apps/rhythmbox/plugins/status-icon/status-icon-mode 3
gconf str /apps/rhythmbox/ui/rhythmdb_columns_setup \
  "RHYTHMDB_PROP_DURATION,RHYTHMDB_PROP_DATE,RHYTHMDB_PROP_TRACK_NUMBER,"

# steamclient
if [ "${ARCH64}" = 64 ] || uname -r | grep -q smp; then
  STEAMCLIENT=steamclient-1.0.0.50-i386-1alien
  if [[ $(get_installed steamclient) != ${STEAMCLIENT} ]]; then
    upgrade_package http://www.slackware.com/~alien/slackbuilds/steamclient/pkg/${SW_VER}/${STEAMCLIENT}.tgz
    rm /tmp/${STEAMCLIENT}.tgz
    sed -i -e "s/Network;FileTransfer;//" ${APP}/steam.desktop
    sed -i -e "s/steam %U/steam -console %U/" ${APP}/steam.desktop
  fi
fi

# stress
slackbuild system stress

# thunar
slackbuild PRIMARYDATALOOP Thunar
add_unique "NoDisplay=true" ${APP}/Thunar.desktop
sed -i -e "s/System;Utility/Utility/" ${APP}/Thunar-bulk-rename.desktop
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
  echo '</channel>'
} > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/thunar.xml

# thunar-archive-plugin
slackbuild desktop thunar-archive-plugin

# thunar-media-tags-plugin
slackbuild desktop thunar-media-tags-plugin

# thunar-thumbnailers
slackbuild desktop thunar-thumbnailers

# tigervnc
TIGERVNC=1.1.0
if ! is_installed tigervnc; then
  heading "install: tigervnc (${TIGERVNC})"
  ARCH=i486
  [ ! -z ${ARCH64} ] && ARCH=x86_64
  echo "  downloading tigervnc-${TIGERVNC}.txz..."
  wget -q ${SW_DL}/extra/tigervnc/tigervnc-${TIGERVNC}-${ARCH}-1.txz \
    -O /tmp/tigervnc-${TIGERVNC}-${ARCH}-1.txz || exit 1
  echo "  installing /tmp/tigervnc-${TIGERVNC}-${ARCH}-1.txz..."
  installpkg /tmp/tigervnc-${TIGERVNC}-${ARCH}-1.txz > /dev/null
  rm /tmp/tigervnc-${TIGERVNC}-${ARCH}-1.txz
fi

# timidity
slackbuild audio TiMidity++
slackbuild audio eawpats
add_unique "source /etc/timidity/eawpats.cfg" /etc/timidity/timidity.cfg

# totem
slackbuild \
  libraries libunique \
  multimedia totem
sed -i -e "s/Movie Player/Totem/" ${APP}/totem.desktop

# network/transmission (2.60 --with-gtk=2)
slackbuild PRIMARYDATALOOP transmission
if [ $(hostname) = euclid ] \
&& ! grep -q transmission-daemon /etc/rc.d/rc.local; then
  {
    echo "# start transmission-daemon as ${MAIN_USER}"
    echo -e "sudo -H -u ${MAIN_USER} /usr/bin/transmission-daemon\n"
  } >> /etc/rc.d/rc.local
fi

# unetbootin
slackbuild system unetbootin

# unrar
slackbuild system unrar

# viewnior
slackbuild graphics viewnior

# virtualbox
if [ "${ARCH64}" = 64 ] && cat /proc/cpuinfo | grep -qE " (svm|vmx) " \
&& [ $(hostname) = euclid ]; then
  groupadd -g 215 vboxusers 2> /dev/null
  slackbuild \
    development acpica \
    system virtualbox \
    system virtualbox-kernel
  ! grep -q vboxdrv /etc/rc.d/rc.local && \
  {
    echo "# start vboxdrv"
    echo "if [ -x /etc/rc.d/rc.vboxdrv ]; then"
    echo "  /etc/rc.d/rc.vboxdrv start"
    echo -e "fi\n"
  } >> /etc/rc.d/rc.local
  ! grep -q vboxdrv /etc/rc.d/rc.local_shutdown && \
  {
    echo "# stop vboxdrv" 
    echo "if [ -x /etc/rc.d/rc.vboxdrv ]; then"
    echo "  /etc/rc.d/rc.vboxdrv stop"
    echo -e "fi\n"
  } >> /etc/rc.d/rc.local_shutdown
  usermod -a -G vboxusers ${MAIN_USER}
  chmod +x /etc/rc.d/rc.vboxdrv
  if [[ $(lsmod) != *vboxdrv* ]]; then
    /etc/rc.d/rc.vboxdrv start
  fi
  sed -i -e "s/Name=Oracle VM /Name=/" ${APP}/virtualbox.desktop
elif dmesg | grep -q "VBOX HARDDISK"; then
  useradd -u 215 -d /var/run/vboxadd -g 1 -s /bin/sh vboxadd 2> /dev/null
  slackbuild \
    system virtualbox-addons \
    system virtualbox-kernel-addons
  ! grep -q vboxadd /etc/rc.d/rc.local && \
  {
    echo "# start vboxadd"
    echo "if [ -x /etc/rc.d/rc.vboxadd ]; then"
    echo "  /etc/rc.d/rc.vboxadd start"
    echo -e "fi\n"
  } >> /etc/rc.d/rc.local
  ! grep -q vboxadd-service /etc/rc.d/rc.local && \
  {
    echo "# start vboxadd-service"
    echo "if [ -x /etc/rc.d/rc.vboxadd-service ]; then"
    echo "  /etc/rc.d/rc.vboxadd-service start"
    echo -e "fi\n"
  } >> /etc/rc.d/rc.local
  ! grep -q vboxadd /etc/rc.d/rc.local_shutdown && \
  {
    echo "# stop vboxadd"
    echo "if [ -x /etc/rc.d/rc.vboxadd ]; then"
    echo "  /etc/rc.d/rc.vboxadd stop"
    echo -e "fi\n"
  } >> /etc/rc.d/rc.local_shutdown
  ! grep -q vboxadd-service /etc/rc.d/rc.local_shutdown && \
  {
    echo "# stop vboxadd-service"
    echo "if [ -x /etc/rc.d/rc.vboxadd-service ]; then"
    echo "  /etc/rc.d/rc.vboxadd-service stop"
    echo -e "fi\n"
  } >> /etc/rc.d/rc.local_shutdown
  ! grep -q setterm /etc/rc.d/rc.local && \
    echo -e "setterm -powerdown 0 -powersave off -blank 0\n" \
      >> /etc/rc.d/rc.local
  chmod +x /etc/rc.d/rc.vboxadd /etc/rc.d/rc.vboxadd-service
  if [[ $(lsmod) != *vboxguest* ]]; then
    /etc/rc.d/rc.vboxadd start
  fi
  /etc/rc.d/rc.vboxadd-service start
fi

# x11vnc
slackbuild network x11vnc
add_unique "NoDisplay=true" ${APP}/x11vnc.desktop

# xdotool
slackbuild accessibility xdotool

# xfburn
slackbuild \
  libraries libburn \
  libraries libisofs \
  system xfburn
sed -i -e "s/;Utility;/;/" /usr/share/applications/xfburn.desktop

# xfce4-cpugraph-plugin
slackbuild desktop xfce4-cpugraph-plugin

# xfce4-dict
slackbuild desktop xfce4-dict
sed -i -e "s/^Categories=Office;/Categories=Utility;/" ${APP}/xfce4-dict.desktop

# xfce4-notes-plugin
slackbuild desktop xfce4-notes-plugin
add_unique "NoDisplay=true" ${APP}/xfce4-notes.desktop

# xfce4-sensors-plugin
slackbuild desktop xfce4-sensors-plugin
add_unique "NoDisplay=true" ${APP}/xfce4-sensors.desktop

# xvkbd
slackbuild desktop xvkbd

# youtube-dl
slackbuild network youtube-dl

# x11
if ! pgrep -x X\|Xvfb 1> /dev/null; then
  if /sbin/lspci | grep -qi "VGA compatible controller: nVidia Corp"; then
    NVIDIA=349.16
    if [ $(hostname) = kepler ] || [ $(hostname) = lovelace ]; then
      NVIDIA=340.76
    elif [ $(hostname) = 6800gt ]; then
      NVIDIA=304.125
    fi
    ARCH=x86
    [ ! -z ${ARCH64} ] && ARCH=x86_64
    if [ ! -e /root/NVIDIA-Linux-${ARCH}-${NVIDIA}.run ]; then
      rm -f /root/NVIDIA-Linux-*.run
      wget us.download.nvidia.com/XFree86/Linux-${ARCH}/${NVIDIA}/NVIDIA-Linux-${ARCH}-${NVIDIA}.run \
        -O /root/NVIDIA-Linux-${ARCH}-${NVIDIA}.run || exit 1
      sh /root/NVIDIA-Linux-${ARCH}-${NVIDIA}.run -s
      if [[ ${NVIDIA} != 304.* ]]; then
        for FILE in lib/libEGL.la lib/libEGL.so.1.0.0 lib64/libEGL.la \
        lib64/libEGL.so.1.0.0; do
          if [ ! -e /usr/X11R6/${FILE} ]; then
            cp -v /var/lib/nvidia/$(cat /var/lib/nvidia/log | grep -m 1 ${FILE} \
              | awk '{print $1}' | sed -e "s/://") /usr/X11R6/${FILE}
          fi
        done
      fi
    fi
    {
      echo "Section \"Device\""
      echo "    Identifier \"Device0\""
      echo "    Driver     \"nvidia\""
      echo "    VendorName \"NVIDIA Corporation\""
      echo -e "EndSection\n"
      echo "Section \"Screen\""
      echo "    Identifier \"Screen0\""
      echo "    Device     \"Device0\""
      echo "    Option     \"NoLogo\" \"true\""
      echo -e "EndSection\n"
    } > /etc/X11/xorg.conf
  elif /sbin/lspci | grep -qi "VGA compatible controller: AMD/ATI" \
  && [ $(hostname) = lovelacefglrx ]; then
    add_unique "blacklist radeon" /etc/modprobe.d/blacklist.conf
    add_unique "blacklist radeonhd" /etc/modprobe.d/blacklist.conf
    if [ $(hostname) = lovelacefglrx ]; then
      AMD=linux-amd-catalyst-14.6-beta-v1.0-jul11.zip
      BETA=/beta
    elif [ $(hostname) = babbage ]; then
      AMD=amd-driver-installer-catalyst-13.1-legacy-linux-x86.x86_64.zip
      BETA=/legacy
    else
      AMD=amd-catalyst-omega-14.12-linux-run-installers.zip
      BETA=/linux
    fi
    if [ ! -e /root/${AMD} ]; then
      rm -fv /root/Linux_AMD_*.zip /root/amd-catalyst-*.zip \
        /root/amd-driver-*.run
      if [ -e /usr/share/ati/amd-uninstall.sh ]; then
        sh /usr/share/ati/amd-uninstall.sh --force
        slackpkg reinstall mesa
      fi
      wget --referer='http://support.amd.com/en-us/download/desktop?os=Linux+x86' \
        http://www2.ati.com/drivers${BETA}/${AMD} -O /root/${AMD} || exit 1
      unzip /root/${AMD}
      mv -v fglrx-*.*/amd-driver-installer-*.run /root
      chmod +x /root/amd-driver-installer-*.run
      /root/amd-driver-installer-*.run
      add_unique "NoDisplay=true" ${APP}/amdccclesu.desktop
      {
        echo "Section \"Device\""
        echo "    Identifier \"Device0\""
        echo "    Driver     \"fglrx\""
        echo -e "EndSection\n"
        echo "Section \"Screen\""
        echo "    Identifier \"Screen0\""
        echo "    Device     \"Device0\""
        echo -e "EndSection\n"
      } > /etc/X11/xorg.conf
      rm -frv fglrx-*.*.* amd-driver-installer-*.*.*-x86.x86_64.run \
        /etc/X11/xorg.conf.original-* /etc/X11/xorg.conf.fglrx-* \
        /etc/modprobe.d/blacklist-fglrx.conf
    fi
  fi
fi

# check for extra packages and new config files then remove junk files
( cd /var/log/packages
  for FILE in *_SBo; do
    if ! grep -q ${FILE%-*-*-*_SBo} "${0}"; then
      echo "${FILE%-*-*-*_SBo} is installed"
    fi
  done
)
for FILE in $(find / -name "*.new" -or -name "*.orig" 2> /dev/null | sort); do
  if [ -e ${FILE%.*} ]; then
    rm -fv ${FILE}
  else
    echo ${FILE}
  fi
done
remove_junk_files
