# RoyalViento MT5 Web Dashboard 🚀

Web Control & Real-time Monitoring Dashboard untuk **MetaTrader 5 (MT5)** dengan Expert Advisor **RoyalViento EA v2.04**, berjalan di Ubuntu VPS (Wine) dan dapat diakses dari mana saja melalui **Cloudflare Tunnel (HTTPS)**.

---

## 🌟 Fitur Utama

- **🎯 Target Profit Harian ($):** Atur target harian dalam USD (misal: $25, $50, $100). Saat target tercapai, robot otomatis menutup semua posisi dan menghentikan trading harian (*auto-stop*).
- **⏯️ Kontrol Trading Cepat:**
  - Pause / Resume EA Trading
  - Toggle tombol Algo Trading MT5 secara langsung via remote `xdotool`
  - Emergency Close All (Tutup semua posisi seketika)
  - Close Single Ticket (Tutup order individual)
  - Reset statistik harian
- **📺 Layar MT5 Chart & EA Live:** Menyematkan screenshot langsung dari grafik dan dashboard internal EA MT5 di browser tanpa perlu aplikasi RDP.
- **📊 Metrik Akun Real-time:** Saldo (Balance), Equity, Free Margin, Floating P/L, dan tabel daftar posisi terbuka live.
- **📜 Log Aktivitas Live:** Tab log terpisah untuk EA RoyalViento dan Terminal MT5.
- **🔒 Keamanan PIN:** Akses dashboard dilindungi oleh PIN otentikasi.
- **☁️ Cloudflare Tunnel:** Akses publik menggunakan HTTPS aman tanpa perlu membuka port NAT atau port forwarding 3389/80.

---

## 📁 Struktur Repositori

```text
├── app.py                      # Backend server Flask & REST API
├── requirements.txt            # Dependensi Python
├── config.example.json         # Contoh konfigurasi PIN & target harian
├── templates/
│   └── index.html              # Frontend web UI responsif (Tailwind CSS)
├── mql5/
│   ├── Include/
│   │   └── WebBridge.mqh       # Bridge komunikasi status & perintah JSON
│   ├── Experts/
│   │   ├── RoyalViento_Clone_EA_v2_04.mq5 # Kode sumber EA + integrasi WebBridge
│   │   ├── Globals.mqh         # Modul deklarasi global EA
│   │   ├── RiskManager.mqh     # Modul proteksi resiko & drawdown
│   │   ├── BasketManager.mqh   # Modul eksekusi averaging & basket exit
│   │   ├── MoneyManagement.mqh # Modul kalkulasi lot dinamis
│   │   ├── ATRManager.mqh      # Modul ATR & volatilitas
│   │   ├── EntryManager.mqh    # Modul sinyal EMA & Stochastic
│   │   ├── TrailingManager.mqh # Modul trailing profit
│   │   └── PanelUI.mqh         # Modul visual panel di chart MT5
│   └── Presets/
│       └── *.set               # Preset konfigurasi EA
├── systemd/
│   ├── mt5-trading.service     # Service systemd runner MT5 di Wine
│   ├── mt5-dashboard.service   # Service systemd web dashboard
│   └── cloudflared-tunnel.service # Service systemd Cloudflare Tunnel
└── scripts/
    ├── start_mt5_trading.sh    # Script starter Xvfb, MT5, dan auto-click Algo
    └── update.sh               # Script auto-update dari GitHub & recompile
```

---

## 🚀 Cara Update Dashboard di VPS

Setelah melakukan perubahan kode di GitHub, Anda cukup menjalankan perintah berikut di terminal VPS:

```bash
/root/dashboard/scripts/update.sh
```

Script tersebut otomatis:
1. Menjalankan `git pull origin main`
2. Menyinkronkan file MQL5 ke direktori MetaTrader 5
3. Mengompilasi ulang EA dengan `metaeditor64.exe`
4. Merestart layanan `mt5-dashboard.service`

---

## 🛡️ Lisensi & Hak Cipta
Dibuat untuk monitoring & kontrol independen sistem trading MetaTrader 5 di VPS Linux.
