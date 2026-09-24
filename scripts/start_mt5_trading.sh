#!/bin/bash
export DISPLAY=:99
export WINEPREFIX=/root/.wine
export WINEDEBUG=-all

# Ensure Xvfb is running
if ! pgrep -f "Xvfb :99" > /dev/null; then
    Xvfb :99 -screen 0 1440x900x24 -ac -noreset >/dev/null 2>&1 &
    sleep 2
fi

# Ensure x11vnc is running
if ! pgrep -f "x11vnc.*5900" > /dev/null; then
    /usr/bin/x11vnc -display :99 -forever -shared -rfbport 5900 -nopw >/dev/null 2>&1 &
    sleep 1
fi

# Kill any existing stuck terminal64
killall -9 terminal64.exe 2>/dev/null || true
sleep 1

# Launch MT5
/opt/wine-stable/bin/wine '/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe' '/config:C:\start.ini' &

# Wait for MT5 window to initialize, then click Algo Trading
(
    sleep 20
    xdotool mousemove 350 70 click 1 >/dev/null 2>&1 || true
) &

# Keep script running as long as terminal64.exe is alive
sleep 8
while pgrep -f "terminal64.exe" > /dev/null; do
    sleep 5
done
