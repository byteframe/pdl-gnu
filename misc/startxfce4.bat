start /B "C:\Program Files\VcXsrv\vcxsrv.exe" "D:\Work\pdl-gnu\misc\euclid.xlaunch"
start "" /B "C:\Users\byteframe\Downloads\pulseaudio-1.1\bin\pulseaudio.exe"
Arch.exe run "if [ -z \"$(pidof xfce4-session)\" ]; then export DISPLAY=:0.0; export PULSE_SERVER=tcp:127.0.0.1; startxfce4; pkill '(gpg|ssh)-agent'; taskkill.exe /IM vcxsrv.exe; taskkill.exe /IM pulseaudio.exe /F; fi;"