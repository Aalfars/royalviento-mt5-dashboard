#!/bin/bash
set -e
echo "=== Updating MT5 Web Dashboard from GitHub ==="
cd /root/dashboard
git pull origin main

# Deploy updated MQL5 files if changed
cp mql5/Include/WebBridge.mqh "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Include/"
cp mql5/Experts/*.mqh "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/"
cp mql5/Experts/RoyalViento_Clone_EA_v2_04.mq5 "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/"

# Recompile EA in Wine
export DISPLAY=:99
wine "/root/.wine/drive_c/Program Files/MetaTrader 5/metaeditor64.exe" /compile:"C:\Program Files\MetaTrader 5\MQL5\Experts\RoyalViento_Clone_EA_v2_04.mq5" /log:"C:\Program Files\MetaTrader 5\MQL5\Experts\compile.log" || true
cp "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/RoyalViento_Clone_EA_v2_04.ex5" "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/RoyalViento_v2_04_IDR_SAFE/RoyalViento_Clone_EA_v2_04.ex5" 2>/dev/null || true

# Restart Dashboard
systemctl restart mt5-dashboard
echo "=== Update Berhasil & Layanan Dashboard Direstart ==="
