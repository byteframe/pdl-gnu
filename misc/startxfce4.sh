if [ -z "$(pidof xfce4-session)" ]; then
  export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):0
  export PULSE_SERVER=tcp:$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}');
  startxfce4
  pkill '(gpg|ssh)-agent'; taskkill.exe /IM vcxsrv.exe; taskkill.exe /IM pulseaudio.exe /F
fi
