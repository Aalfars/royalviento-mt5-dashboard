#!/bin/bash
export DISPLAY=:99
export WINEPREFIX=/root/.wine
export WINEDEBUG=-all

cleanup() {
    echo "[SHUTDOWN] Signal received, stopping MT5..."
    killall -9 terminal64.exe wineserver 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

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

STATUS_FILE='/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/web_status.json'

# Touch status file or clear previous timestamp to start fresh tracking
rm -f "$STATUS_FILE" 2>/dev/null || true

# Launch MT5 with /portable and /config:C:\start.ini
/opt/wine-stable/bin/wine '/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe' /portable '/config:C:\start.ini' &
MT5_PID=$!
echo "[STARTUP] MT5 launched with PID $MT5_PID at $(date)"

# Wait for MT5 window and startup (up to 30s)
BOOT_WAIT=0
while [ $BOOT_WAIT -lt 30 ]; do
    sleep 2
    BOOT_WAIT=$((BOOT_WAIT + 2))
    if [ -f "$STATUS_FILE" ]; then
        break
    fi
done

# Initial Algo Trading check & enable
if [ -f "$STATUS_FILE" ] && grep -q '"algo_trading": false' "$STATUS_FILE"; then
    echo "[STARTUP] Enabling Algo Trading via Ctrl+E..."
    WID=$(DISPLAY=:99 xdotool search --name 'MetaTrader' 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:99 xdotool key --window "$WID" ctrl+e 2>/dev/null || true
    else
        DISPLAY=:99 xdotool key ctrl+e 2>/dev/null || true
    fi
fi

# ===================================================================
# 24/7 AUTO-HEALING WATCHDOG
# Monitors:
# 1. Stale web_status.json (>45s wake-up, >90s force restart)
# 2. Modal update/alert popups that freeze MT5 tick processing
# 3. Accidental disabling of Algo Trading
# ===================================================================
echo "[WATCHDOG] 24/7 Self-Healing Watchdog active..."

while pgrep -f "terminal64.exe" > /dev/null; do
    sleep 5

    # 1. Dismiss any modal popups (LiveUpdate, Update, Restart, Attention, etc.)
    for wid in $(DISPLAY=:99 xdotool search --onlyvisible '' 2>/dev/null); do
        wname=$(DISPLAY=:99 xdotool getwindowname "$wid" 2>/dev/null)
        if echo "$wname" | grep -qiE "liveupdate|update|restart|attention|notice|warning|error"; then
            echo "[WATCHDOG $(date)] Detected popup window '$wname' (WID $wid). Auto-dismissing..."
            DISPLAY=:99 xdotool key --window "$wid" Return 2>/dev/null || true
            DISPLAY=:99 xdotool key --window "$wid" Escape 2>/dev/null || true
        fi
    done

    # 2. Check Algo Trading status
    if [ -f "$STATUS_FILE" ] && grep -q '"algo_trading": false' "$STATUS_FILE"; then
        echo "[WATCHDOG $(date)] Algo Trading detected OFF. Re-enabling via Ctrl+E..."
        WID=$(DISPLAY=:99 xdotool search --name 'MetaTrader' 2>/dev/null | head -1)
        if [ -n "$WID" ]; then
            DISPLAY=:99 xdotool key --window "$WID" ctrl+e 2>/dev/null || true
        else
            DISPLAY=:99 xdotool key ctrl+e 2>/dev/null || true
        fi
    fi

    # 3. Check web_status.json freshness (health check)
    if [ -f "$STATUS_FILE" ]; then
        NOW=$(date +%s)
        MTIME=$(stat -c %Y "$STATUS_FILE" 2>/dev/null || echo "$NOW")
        STALE_SECS=$((NOW - MTIME))

        # If status has not updated for > 45 seconds, try dismissing modal dialogs
        if [ "$STALE_SECS" -ge 45 ] && [ "$STALE_SECS" -lt 90 ]; then
            echo "[WATCHDOG $(date)] Stale status detected (${STALE_SECS}s). Attempting to unfreeze..."
            for wid in $(DISPLAY=:99 xdotool search --onlyvisible '' 2>/dev/null); do
                DISPLAY=:99 xdotool key --window "$wid" Return 2>/dev/null || true
                DISPLAY=:99 xdotool key --window "$wid" Escape 2>/dev/null || true
            done
        fi

        # If frozen for > 90 seconds, restart terminal64.exe
        if [ "$STALE_SECS" -ge 90 ]; then
            echo "[WATCHDOG $(date)] CRITICAL: MT5 frozen for ${STALE_SECS}s! Force killing terminal64.exe to auto-recover..."
            killall -9 terminal64.exe 2>/dev/null || true
            break
        fi
    fi
done

echo "[SHUTDOWN] terminal64.exe exited at $(date). Service will auto-restart."
