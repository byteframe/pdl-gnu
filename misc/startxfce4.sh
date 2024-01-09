if [ -z "$(pidof xfce4-session)" ]; then
  #export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):1
  export DISPLAY=192.168.50.100:1
  #export PULSE_SERVER=tcp:$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
  export PULSE_SERVER=tcp:192.168.50.100
  startxfce4
  sleep 3
  pkill '(gpg|ssh)-agent'; taskkill.exe /IM vcxsrv.exe; taskkill.exe /IM pulseaudio.exe /F
fi