#!/bin/sh

source "$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/pdl-gnu_common.sh
if [ $(whoami) = root ]; then
  echo "fatal: can't be run as root!"
  exit 1
fi

# clone/fetch
[ ! -x ${HOME}/.gitwine ] && \
  git clone git://source.winehq.org/git/wine.git ${HOME}/.gitwine
cd ${HOME}/.gitwine
git fetch

# tags/time
OLD_VERSION=none
[ -e /usr/bin/wine ] && OLD_VERSION=$(wine --version)
TAG=origin
[ ! -z ${1} ] && TAG=wine-${1}
OLD_TIME=$(git log -n1 --format=%ct)
TAG_TIME=$(git log -n1 --format=%ct ${TAG})

# don't rebuild same version
if [ ${OLD_TIME} = ${TAG_TIME} ] && [ ${OLD_VERSION} != "none" ]; then
  echo "$(wine --version) is the same as $(git log -n1 --format=%h) (${TAG})"
else

  # uninstall
  if [ ${OLD_VERSION} != none ]; then
    heading "uninstalling"
    wineserver -k
    sudo mv /usr/share/wine/gecko/* /usr/share/wine/mono/* /tmp
    sudo rmdir /usr/share/wine/gecko /usr/share/wine/mono
    sudo make uninstall || exit 1
  fi

  # clean
  if [ -e Makefile ]; then 
    heading "cleaning"
    make clean || exit 1
  fi

  # reset
  git reset --hard ${TAG} || exit 1

  # patch
  if [ ${OLD_TIME} -le ${TAG_TIME} ] && ls *.diff &> /dev/null; then
    heading "patching"
    for FILE in *.diff; do
      cat ${FILE} | patch --no-backup-if-mismatch -p1 || exit 1
    done
  fi

  # configure
  heading "configuring"
  CFLAGS="-O2 -march=native" ./configure --prefix=/usr \
    | tee configure-$(date +%s).log

  # make
  heading "making"
  if pgrep -x gnome-power-manager 1> /dev/null; then
    killall -w gnome-power-manager
    echo "stopped gnome-power-manager"
  elif pgrep -x xfce4-power-manager 1> /dev/null; then
    xfce4-power-manager -q
    echo "stopped xfce4-power-manager"
  fi
  make -j$(grep -c ^processor /proc/cpuinfo) || exit 1

  # install
  heading "installing"
  sudo make install || exit 1
  sudo mkdir /usr/share/wine/gecko /usr/share/wine/mono

  if [ ${TAG_TIME} -ge 1424872524 ]; then
    GECKO=2.36-x86.msi
  elif [ ${TAG_TIME} -ge 1415015572 ]; then
    GECKO=2.34-x86.msi
  elif [ ${TAG_TIME} -ge 1380130298 ]; then
    GECKO=2.24-x86.msi
  elif [ ${TAG_TIME} -ge 1368801708 ]; then
    GECKO=2.21-x86.msi
  elif [ ${TAG_TIME} -ge 1357749949 ]; then
    GECKO=1.9-x86.msi
  elif [ ${TAG_TIME} -ge 1349800344 ]; then
    GECKO=1.8-x86.msi
  elif [ ${TAG_TIME} -ge 1342624491 ]; then
    GECKO=1.7-x86.msi
  elif [ ${TAG_TIME} -ge 1339441426 ]; then
    GECKO=1.6-x86.msi
  elif [ ${TAG_TIME} -ge 1331742903 ]; then
    GECKO=1.5-x86.msi
  elif [ ${TAG_TIME} -ge 1320863473 ]; then
    GECKO=1.4-x86.msi
  elif [ ${TAG_TIME} -ge 1314116204 ]; then
    GECKO=1.3-x86.msi
  elif [ ${TAG_TIME} -ge 1300205648 ]; then
    GECKO=1.2.0-x86.msi
  elif [ $TAG_TIME -ge 1282750634 ]; then
    GECKO=1.1.0-x86.cab
  elif [ $TAG_TIME -ge 1249392781 ]; then
    GECKO=1.0.0-x86.cab
  elif [ $TAG_TIME -ge 1233928226 ]; then
    GECKO=0.9.1-x86.cab
  elif [ $TAG_TIME -ge 1230637414 ]; then
    GECKO=0.9.0-x86.cab
  else
    GECKO=0.1.0-x86.cab
  fi
  if [ -e /tmp/wine_gecko-${GECKO} ]; then
    sudo mv -v /tmp/wine_gecko-${GECKO} /usr/share/wine/gecko/
  else
    sudo wget http://downloads.sourceforge.net/wine/wine_gecko-${GECKO} \
     -O /usr/share/wine/gecko/wine_gecko-${GECKO}
  fi
  if [ ${TAG_TIME} -ge 1425394233 ]; then
    MONO=4.5.6
  elif [ ${TAG_TIME} -ge 1416287453 ]; then
    MONO=4.5.4
  elif [ ${TAG_TIME} -ge 1386255543 ]; then
    MONO=4.5.2
  elif [ ${TAG_TIME} -ge 1350381242 ]; then
    MONO=0.0.8
  else
    MONO=0.0.4
  fi
  if [ -e /tmp/wine-mono-${MONO}.msi ]; then
    sudo mv -v /tmp/wine-mono-${MONO}.msi /usr/share/wine/mono/
  else
    sudo wget http://downloads.sourceforge.net/wine/wine-mono-${MONO}.msi \
      -O /usr/share/wine/mono/wine-mono-${MONO}.msi
  fi
  sudo rm -vf /tmp/wine_gecko-* /tmp/wine-mono-*.msi

  # update prefixes
  export DISPLAY=:0.0
  for DIR in ${HOME}/.wine*; do
    if [ -d ${DIR} ]; then
      if ! pgrep -x X 1> /dev/null; then
        NO_X=yes
        echo "starting X..."
        screen -dmS pdl-gnu_wine xinit -geometry =80x24+0+0 -j
        while ! pgrep -x X 1> /dev/null; do
          sleep 1
        done
      fi
      WINEDLLOVERRIDES="winemenubuilder.exe=d" WINEDEBUG="-all" \
        WINEPREFIX=${DIR} wineboot
    fi
  done
  if [ ! -z ${NO_X} ]; then
    while pgrep -n wineserver 1> /dev/null; do
      sleep 1
    done
    killall -qw X
    echo "stopped x"
  fi

  # report
  echo -e "\n${OLD_VERSION} changed to $(wine --version)/${TAG} \n"
  git status
  git clean -n
  if pgrep -x gnome-session 1> /dev/null \
  && ! pgrep -x gnome-power-manager 1> /dev/null; then
    gnome-power-manager > /dev/null 2>&1
    echo "started gnome-power-manager"
  elif pgrep -x xfce4-session 1> /dev/null \
  && ! pgrep -x xfce4-power-manager 1> /dev/null; then
    xfce4-power-manager > /dev/null 2>&1
    echo "started xfce4-power-manager"
  fi
fi
