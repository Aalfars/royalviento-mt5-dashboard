# RoyalViento MT5 Web Dashboard 🚀
> *Serif analytics on warm paper — Institutional execution monitoring for MetaTrader 5*

Web Control & Real-time Telemetry Dashboard untuk **MetaTrader 5 (MT5)** dengan Expert Advisor **RoyalViento EA v2.04**, berjalan di Ubuntu VPS (Wine) dan dapat diakses publik melalui domain **[trading.aranya.my.id](https://trading.aranya.my.id)** dengan perlindungan Cloudflare.

---

## 🎨 Desain Steep Style
Dashboard ini mengadopsi estetika editorial **Steep**:
- **Palette Monokrom Hangat**: Dominan *Paper White* (`#ffffff`), *Mist Gray* (`#f2f2f3`), dan *Ink Black* (`#17191c`).
- **Punctuation Aksen Peach**: Satu panel editorial *Blush Peach* (`#fbe1d1`) dengan tipografi *Sienna Brown* (`#5d2a1a`) untuk sorotan Target Harian & Capaian Profit.
- **Tipografi Signifier & Söhne**: Judul serif *Source Serif 4* dengan weight 400 (regular) yang elegan dipadukan dengan sans *Inter* untuk UI & tabel data.
- **Geometri Minimalis**: Sudut kurva 24px pada kartu, 20px pada floating artifact produk, dan tombol kapsul *pill-shaped* (9999px) berpasangan (filled & ghost).

---

## 🌟 Fitur Utama

- **🎯 Target Profit Harian ($):** Atur target harian dalam USD (misal: $25, $50, $100). Saat target tercapai, robot otomatis menutup semua posisi dan menghentikan trading harian (*auto-stop*).
- **⏯️ Kontrol Trading Cepat:**
  - Pause / Resume EA Trading
  - Toggle tombol Algo Trading MT5 secara langsung via remote `xdotool`
  - Emergency Close All (Tutup semua posisi seketika)
  - Close Single Ticket (Tutup order individual dari tabel live)
  - Reset statistik profit harian ke nol
- **📺 Layar MT5 Chart & EA Live:** Menyematkan screenshot langsung dari grafik dan dashboard internal EA MT5 di browser tanpa perlu membuka aplikasi RDP.
- **📊 Metrik Akun Real-time:** Saldo (Balance), Equity, Free Margin, Floating P/L, dan tabel daftar posisi terbuka live (sinkronisasi setiap 2 detik via MQL5 WebBridge).
- **📜 Log Aktivitas Live:** Tab log terpisah untuk EA RoyalViento dan Terminal MT5.
- **🔒 Keamanan PIN:** Akses dashboard dilindungi oleh modal otentikasi PIN.
- **🌐 Custom Domain Cloudflare:** Terhubung ke domain custom `trading.aranya.my.id` melalui Cloudflare Proxy & Nginx reverse proxy dengan enkripsi SSL/HTTPS.

---

## 📁 Struktur Repositori

```text
├── app.py                      # Backend server Flask & REST API
├── requirements.txt            # Dependensi Python
├── config.example.json         # Contoh konfigurasi PIN & target harian
├── templates/
│   └── index.html              # Frontend Steep Style (Tailwind + Serif Analytics)
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
│   ├── mt5-dashboard.service   # Service systemd web dashboard (port 5000)
│   └── cloudflared-tunnel.service # Service systemd Cloudflare Tunnel
└── scripts/
    ├── start_mt5_trading.sh    # Script starter Xvfb, MT5, dan auto-click Algo
    └── update.sh               # Script auto-update dari GitHub & recompile
```

---

## 🔄 Cara Kontrol Update Dashboard dari GitHub

Setelah melakukan perubahan kode di GitHub repository `Aalfars/royalviento-mt5-dashboard`, Anda cukup menjalankan perintah berikut di terminal VPS:

```bash
/root/dashboard/scripts/update.sh
```

Script tersebut otomatis:
1. Menjalankan `git pull origin main` dari repository GitHub Anda
2. Menyinkronkan file MQL5 ke direktori MetaTrader 5 di Wine
3. Mengompilasi ulang EA dengan `metaeditor64.exe`
4. Merestart layanan `mt5-dashboard.service`

---

## 🌐 Konfigurasi Domain (Cloudflare)

Untuk menghubungkan domain `trading.aranya.my.id`:
1. Masuk ke dashboard **Cloudflare** pada domain `aranya.my.id`.
2. Masuk ke menu **DNS** > **Records**.
3. Tambahkan DNS Record:
   - **Type**: `A`
   - **Name**: `trading` (sehingga menjadi `trading.aranya.my.id`)
   - **IPv4 address**: `51.79.231.130`
   - **Proxy status**: **Proxied** (Awan Orange aktif)
4. Masuk ke menu **SSL/TLS** > pastikan mode SSL adalah **Full** atau **Flexible**.
5. Akses dashboard melalui browser di: `https://trading.aranya.my.id`

---

## 🛡️ Lisensi & Hak Cipta
Dikelola oleh **Aalfars** untuk monitoring & kontrol independen sistem trading MetaTrader 5 di VPS Linux.
