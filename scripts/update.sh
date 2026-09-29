#!/bin/bash
set -e
echo "=== Updating MT5 Web Dashboard from GitHub ==="
cd /root/dashboard
git pull origin main

# Deploy updated MQL5 files if changed
cp mql5/Include/WebBridge.mqh "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Include/" 2>/dev/null || true
cp mql5/Experts/*.mqh "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/" 2>/dev/null || true
cp mql5/Experts/*.mq5 "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/" 2>/dev/null || true
mkdir -p "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Presets/"
cp mql5/Presets/*.set "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Presets/" 2>/dev/null || true

# Recompile EAs in Wine
export DISPLAY=:99
cd "/root/.wine/drive_c/Program Files/MetaTrader 5"
wine metaeditor64.exe /compile:"MQL5\Experts\RoyalQuantum_EA_v2.36_SingleEntryHistory.mq5" /log:"MQL5\Experts\compile_rq.log" || true
wine metaeditor64.exe /compile:"MQL5\Experts\RoyalViento_Clone_EA_v2_04.mq5" /log:"MQL5\Experts\compile.log" || true
cp "MQL5/Experts/RoyalViento_Clone_EA_v2_04.ex5" "MQL5/Experts/RoyalViento_v2_04_IDR_SAFE/RoyalViento_Clone_EA_v2_04.ex5" 2>/dev/null || true
cd /root/dashboard

# Restart Dashboard
systemctl restart mt5-dashboard
echo "=== Update Berhasil & Layanan Dashboard Direstart ==="
