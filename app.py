import os
import json
import time
import subprocess
import glob
from flask import Flask, render_template, request, jsonify, send_file, session

app = Flask(__name__)
app.secret_key = "royalviento_secret_key_vps_trading"

IS_WINDOWS = os.name == "nt"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

if IS_WINDOWS:
    CONFIG_FILE = os.path.join(BASE_DIR, "config.json")
    STATUS_FILE = os.path.join(BASE_DIR, "mql5", "Files", "web_status.json")
    COMMAND_FILE = os.path.join(BASE_DIR, "mql5", "Files", "web_command.json")
    SCREENSHOT_PATH = os.path.join(BASE_DIR, "preview.png")
    CLOUDFLARE_LOG = os.path.join(BASE_DIR, "cloudflared.log")
    PRESET_PATHS = [
        os.path.join(BASE_DIR, "mql5", "Presets", "RoyalViento_XAUUSD_M1_1JT_24H_CONTROLLED_MARTINGALE.set")
    ]
    START_INI_PATHS = []
else:
    CONFIG_FILE = "/root/dashboard/config.json"
    STATUS_FILE = "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/web_status.json"
    COMMAND_FILE = "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/web_command.json"
    SCREENSHOT_PATH = "/tmp/mt5_web_preview.png"
    CLOUDFLARE_LOG = "/root/dashboard/cloudflared.log"
    PRESET_PATHS = [
        "/root/dashboard/mql5/Presets/RoyalViento_XAUUSD_M1_1JT_24H_CONTROLLED_MARTINGALE.set",
        "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Presets/RoyalViento_XAUUSD_M1_1JT_24H_CONTROLLED_MARTINGALE.set"
    ]
    START_INI_PATHS = [
        "/root/.wine/drive_c/start.ini",
        "/root/.wine/drive_c/Program Files/MetaTrader 5/start.ini"
    ]

# Parameter definitions and metadata for GUI Configuration
PARAMETER_CATEGORIES = [
    {"id": "lot", "name": "Lot & Money Management", "icon": "fa-coins", "desc": "Ukuran lot awal, sistem perkalian martingale, dan kalkulasi lot dinamis."},
    {"id": "mtf", "name": "Multi-Timeframe & Sinyal", "icon": "fa-chart-line", "desc": "Filter trend M1, M5, H4, indikator EMA dan Stochastic oscillator."},
    {"id": "grid", "name": "Grid & Averaging", "icon": "fa-layer-group", "desc": "Jarak averaging, batasan jumlah order, dan recovery arah trend besar."},
    {"id": "tp", "name": "Take Profit & Trailing", "icon": "fa-trophy", "desc": "Target Take Profit dinamis ATR / poin tetap, basket trailing stop, dan profit lock."},
    {"id": "risk", "name": "Risk Management & Kill Switch", "icon": "fa-shield-halved", "desc": "Proteksi akun total drawdown, batasan rugi harian, dan basket cut loss."},
    {"id": "filter", "name": "Jam Trading & Filter Spread", "icon": "fa-clock", "desc": "Pengaturan jam aktif trading MT5, proteksi spread lebar, dan spike ATR."}
]

PARAMETER_DEFINITIONS = [
    # --- Category: LOT & MM ---
    {
        "key": "InpBaseLot",
        "category": "lot",
        "label": "Lot Awal (Base Lot)",
        "type": "float",
        "step": 0.01,
        "min": 0.01,
        "max": 10.0,
        "default": 0.01,
        "unit": "Lot",
        "desc": "Volume lot untuk order pertama basket. Gunakan 0.01 untuk ketahanan maksimal pada modal kecil."
    },
    {
        "key": "InpLotMode",
        "category": "lot",
        "label": "Mode Penambahan Lot",
        "type": "select",
        "options": [
            {"value": 0, "label": "0 - Lot Tambah Flat (Konstan)"},
            {"value": 1, "label": "1 - Multiplier Martingale (Perkalian)"}
        ],
        "default": 0,
        "desc": "Metode penghitungan volume order averaging berikutnya."
    },
    {
        "key": "InpLotMultiplier",
        "category": "lot",
        "label": "Pengali Lot Averaging (Multiplier)",
        "type": "float",
        "step": 0.05,
        "min": 1.0,
        "max": 3.0,
        "default": 1.50,
        "unit": "x",
        "desc": "Faktor pengali lot untuk setiap tingkat averaging (jika Mode Multiplier aktif)."
    },
    {
        "key": "InpLotAddFlat",
        "category": "lot",
        "label": "Tambahan Lot Flat",
        "type": "float",
        "step": 0.01,
        "min": 0.0,
        "max": 1.0,
        "default": 0.00,
        "unit": "Lot",
        "desc": "Nilai tambahan lot flat di setiap tingkat averaging (jika Mode Tambah Flat aktif)."
    },
    {
        "key": "InpAutoLotByBalance",
        "category": "lot",
        "label": "Auto Lot Berdasarkan Saldo",
        "type": "bool",
        "default": False,
        "desc": "Otomatis menaikkan lot awal saat modal bertambah sesuai rasio risiko."
    },
    {
        "key": "InpRiskPer100USD",
        "category": "lot",
        "label": "Kenaikan Lot per Unit Saldo",
        "type": "float",
        "step": 0.01,
        "min": 0.001,
        "max": 0.1,
        "default": 0.01,
        "unit": "Lot",
        "desc": "Besar penambahan lot per kelipatan modal unit."
    },

    # --- Category: MTF & SIGNALS ---
    {
        "key": "InpMTFEnabled",
        "category": "mtf",
        "label": "Filter Multi-Timeframe (M1 + M5 + H4)",
        "type": "bool",
        "default": True,
        "desc": "Wajibkan konfirmasi trend di timeframe yang lebih tinggi (M5 dan H4) sebelum membuka basket baru."
    },
    {
        "key": "InpMTFUseEMA200",
        "category": "mtf",
        "label": "MTF Wajib Searah EMA200",
        "type": "bool",
        "default": True,
        "desc": "Sinyal M5 dan H4 harus berada di sisi EMA200 yang sesuai dengan arah sinyal M1."
    },
    {
        "key": "InpMTFUseSlope",
        "category": "mtf",
        "label": "MTF Wajib Kemiringan Slope",
        "type": "bool",
        "default": True,
        "desc": "Sinyal M5 dan H4 harus memiliki momentum kemiringan EMA yang cukup kuat (tidak sideways)."
    },
    {
        "key": "InpMTFSlopeMin",
        "category": "mtf",
        "label": "Slope Minimum MTF",
        "type": "float",
        "step": 1.0,
        "min": 1.0,
        "max": 100.0,
        "default": 10.0,
        "unit": "Points",
        "desc": "Ambang minimum perubahan kemiringan EMA pada timeframe M5 dan H4."
    },
    {
        "key": "InpEMADirPeriod",
        "category": "mtf",
        "label": "Periode EMA Sinyal Arah",
        "type": "int",
        "step": 5,
        "min": 10,
        "max": 500,
        "default": 100,
        "unit": "Bar",
        "desc": "Periode EMA utama penentu arah Buy/Sell (harga Close di atas/bawah garis ini)."
    },
    {
        "key": "InpEMA200Period",
        "category": "mtf",
        "label": "Periode EMA Trend Besar",
        "type": "int",
        "step": 10,
        "min": 50,
        "max": 1000,
        "default": 200,
        "unit": "Bar",
        "desc": "Periode EMA sebagai filter bias tren jangka menengah/panjang."
    },
    {
        "key": "InpUseEMA200Filter",
        "category": "mtf",
        "label": "Aktifkan Filter EMA 200",
        "type": "bool",
        "default": True,
        "desc": "Hanya izinkan Buy jika EMA Direction > EMA 200, dan sebaliknya untuk Sell."
    },
    {
        "key": "InpUseStochFilter",
        "category": "mtf",
        "label": "Aktifkan Filter Stochastic",
        "type": "bool",
        "default": True,
        "desc": "Mencegah Buy di pucuk overbought (>80) dan Sell di lembah oversold (<20)."
    },
    {
        "key": "InpStochK",
        "category": "mtf",
        "label": "Stochastic %K Period",
        "type": "int",
        "step": 1,
        "min": 2,
        "max": 50,
        "default": 5,
        "unit": "Bar",
        "desc": "Periode %K pada osilator Stochastic."
    },
    {
        "key": "InpStochD",
        "category": "mtf",
        "label": "Stochastic %D Period",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 30,
        "default": 3,
        "unit": "Bar",
        "desc": "Periode %D smoothing garis sinyal Stochastic."
    },
    {
        "key": "InpStochSlowing",
        "category": "mtf",
        "label": "Stochastic Slowing",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 30,
        "default": 3,
        "unit": "Bar",
        "desc": "Nilai perlambatan (slowing) Stochastic."
    },
    {
        "key": "InpStochOversold",
        "category": "mtf",
        "label": "Ambang Oversold (Batas Bawah)",
        "type": "float",
        "step": 1.0,
        "min": 5.0,
        "max": 40.0,
        "default": 20.0,
        "unit": "%",
        "desc": "Di bawah level ini harga dianggap oversold; Sell dicegah."
    },
    {
        "key": "InpStochOverbought",
        "category": "mtf",
        "label": "Ambang Overbought (Batas Atas)",
        "type": "float",
        "step": 1.0,
        "min": 60.0,
        "max": 95.0,
        "default": 80.0,
        "unit": "%",
        "desc": "Di atas level ini harga dianggap overbought; Buy dicegah."
    },
    {
        "key": "InpUseEMASlope",
        "category": "mtf",
        "label": "Filter Kemiringan EMA M1 (Anti Sideways)",
        "type": "bool",
        "default": True,
        "desc": "Memblokir entry jika garis EMA bergerak mendatar/sideways tanpa tren."
    },
    {
        "key": "InpEMASlopeBars",
        "category": "mtf",
        "label": "Jarak Bar Perhitungan Slope",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 20,
        "default": 5,
        "unit": "Bar",
        "desc": "Jumlah candle ke belakang untuk menghitung perubahan elevasi EMA."
    },
    {
        "key": "InpEMASlopeMin",
        "category": "mtf",
        "label": "Kemiringan Minimum Slope M1",
        "type": "float",
        "step": 1.0,
        "min": 1.0,
        "max": 100.0,
        "default": 15.0,
        "unit": "Points",
        "desc": "Perubahan minimum poin EMA dalam rentang bar agar pasar dianggap bertren."
    },
    {
        "key": "InpFollowEMACooldownRules",
        "category": "mtf",
        "label": "Ikuti Aturan EMA & Cooldown Bar",
        "type": "bool",
        "default": True,
        "desc": "Jika FALSE, EA masuk ke mode instan Buy & Sell langsung tanpa filter indikator."
    },

    # --- Category: GRID & AVERAGING ---
    {
        "key": "InpFixedAveragingDistancePoints",
        "category": "grid",
        "label": "Jarak Averaging Grid (Points)",
        "type": "float",
        "step": 25.0,
        "min": 50.0,
        "max": 2000.0,
        "default": 200.0,
        "unit": "Points",
        "desc": "Jarak harga tetap dalam poin untuk mengeksekusi order averaging berikutnya."
    },
    {
        "key": "InpMaxOpenOrdersBasket",
        "category": "grid",
        "label": "Maksimal Order per Basket",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 20,
        "default": 3,
        "unit": "Posisi",
        "desc": "Jumlah posisi terbuka maksimum dalam satu keranjang (basket)."
    },
    {
        "key": "InpMaxTotalLotBasket",
        "category": "grid",
        "label": "Maksimal Akumulasi Lot Basket",
        "type": "float",
        "step": 0.01,
        "min": 0.01,
        "max": 5.0,
        "default": 0.03,
        "unit": "Lot",
        "desc": "Batas keras total akumulasi lot dalam satu keranjang agar margin tetap terlindungi."
    },
    {
        "key": "InpMaxAveragingCycle",
        "category": "grid",
        "label": "Maksimal Siklus Averaging",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 10,
        "default": 3,
        "unit": "Siklus",
        "desc": "Jumlah siklus averaging sebelum lot di-reset kembali ke base lot."
    },
    {
        "key": "InpMinSecondsBetweenAvg",
        "category": "grid",
        "label": "Jeda Minimum Antar Averaging",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 60,
        "default": 10,
        "unit": "Detik",
        "desc": "Mencegah pembukaan beberapa order sekaligus dalam satu detik saat terjadi lonjakan harga kilat."
    },
    {
        "key": "InpCooldownCandles",
        "category": "grid",
        "label": "Candle Tunggu Setelah Basket Tutup",
        "type": "int",
        "step": 1,
        "min": 0,
        "max": 20,
        "default": 5,
        "unit": "Candle",
        "desc": "Jeda candle menunggu setelah basket tertutup normal sebelum diizinkan entry baru."
    },
    {
        "key": "InpAveragingWaitClose",
        "category": "grid",
        "label": "Averaging Tunggu Candle Close",
        "type": "bool",
        "default": False,
        "desc": "Jika TRUE, averaging hanya dieksekusi saat pergantian bar (bukan setiap tick)."
    },
    {
        "key": "InpAllowBuySellTogether",
        "category": "grid",
        "label": "Izinkan Buy & Sell Bersamaan (Hedging)",
        "type": "bool",
        "default": False,
        "desc": "Bolehkan basket Buy dan basket Sell aktif bersamaan dalam satu waktu."
    },
    {
        "key": "InpGridFollowHigherTF",
        "category": "grid",
        "label": "Averaging Cek Konfirmasi M5 + H4",
        "type": "bool",
        "default": True,
        "desc": "Sebelum menambah averaging layer berikutnya, pastikan trend M5 & H4 tetap mendukung."
    },
    {
        "key": "InpGridReverseOnTrendFlip",
        "category": "grid",
        "label": "Tutup & Balik Arah Jika Trend Berbalik",
        "type": "bool",
        "default": True,
        "desc": "Jika tren besar H4/M5 berbalik drastis, tutup keranjang yang berlawanan dan ikuti arah baru."
    },

    # --- Category: TAKE PROFIT & TRAILING ---
    {
        "key": "InpUseBasketTrailing",
        "category": "tp",
        "label": "Aktifkan Trailing Basket Otomatis",
        "type": "bool",
        "default": True,
        "desc": "Mengunci floating profit basket secara dinamis mengikuti kenaikan harga."
    },
    {
        "key": "InpTrailStartPoints",
        "category": "tp",
        "label": "Jarak Mulai Trailing (Points)",
        "type": "int",
        "step": 10,
        "min": 20,
        "max": 1000,
        "default": 100,
        "unit": "Points",
        "desc": "Basket harus mencapai profit minimal sebesar poin ini sebelum trailing diaktifkan."
    },
    {
        "key": "InpTrailStopDistance",
        "category": "tp",
        "label": "Jarak Kunci Stop Trailing (Points)",
        "type": "int",
        "step": 10,
        "min": 10,
        "max": 500,
        "default": 50,
        "unit": "Points",
        "desc": "Jarak trailing stop di belakang puncak harga tertinggi (peak)."
    },
    {
        "key": "InpDisableTrailTP",
        "category": "tp",
        "label": "Matikan Total Trailing & TP (Manual Close)",
        "type": "bool",
        "default": False,
        "desc": "EA hanya open posisi & averaging; penutupan posisi dilakukan 100% manual."
    },
    {
        "key": "InpUseATRBasedTP",
        "category": "tp",
        "label": "Gunakan TP Dinamis ATR",
        "type": "bool",
        "default": True,
        "desc": "Take Profit menyesuaikan volatilitas harian (ATR) alih-alih angka poin statis."
    },
    {
        "key": "InpATRTPMultiplier",
        "category": "tp",
        "label": "Pengali TP ATR",
        "type": "float",
        "step": 0.5,
        "min": 0.5,
        "max": 10.0,
        "default": 2.5,
        "unit": "x ATR",
        "desc": "Jarak TP = ATR(14) x pengali ini."
    },
    {
        "key": "InpFixedTPPoints",
        "category": "tp",
        "label": "Take Profit Poin Tetap",
        "type": "float",
        "step": 100.0,
        "min": 200.0,
        "max": 10000.0,
        "default": 3000.0,
        "unit": "Points",
        "desc": "Dipakai jika TP Dinamis ATR dinonaktifkan."
    },
    {
        "key": "InpUseProfitLock",
        "category": "tp",
        "label": "Aktifkan Profit Lock",
        "type": "bool",
        "default": True,
        "desc": "Mengunci keuntungan minimal saat floating profit basket telah melampaui ambang tertentu."
    },
    {
        "key": "InpProfitLockStart",
        "category": "tp",
        "label": "Ambang Mulai Profit Lock",
        "type": "float",
        "step": 50.0,
        "min": 100.0,
        "max": 2000.0,
        "default": 500.0,
        "unit": "Points",
        "desc": "Floating profit yang harus dicapai agar proteksi profit lock aktif."
    },
    {
        "key": "InpProfitLockPoints",
        "category": "tp",
        "label": "Poin Profit yang Dijamin",
        "type": "float",
        "step": 25.0,
        "min": 50.0,
        "max": 1000.0,
        "default": 250.0,
        "unit": "Points",
        "desc": "Jumlah keuntungan minimum yang dijamin tidak akan hilang jika harga berbalik."
    },

    # --- Category: RISK & KILL SWITCHES ---
    {
        "key": "InpUseDailyLossLimit",
        "category": "risk",
        "label": "Batas Kerugian Harian (% Equity Kill Switch)",
        "type": "bool",
        "default": True,
        "desc": "Tutup semua order dan stop trading hari ini jika rugi harian melampaui persentase ini."
    },
    {
        "key": "InpDailyLossPercent",
        "category": "risk",
        "label": "Persentase Batas Rugi Harian",
        "type": "float",
        "step": 0.5,
        "min": 1.0,
        "max": 20.0,
        "default": 5.0,
        "unit": "%",
        "desc": "Maksimal penurunan equity harian sebelum kill-switch harian aktif."
    },
    {
        "key": "InpUseDailyProfitTarget",
        "category": "risk",
        "label": "Target Profit Harian Otomatis (% Equity)",
        "type": "bool",
        "default": False,
        "desc": "Tutup semua posisi & selesai trading hari ini jika profit harian mencapai target persen."
    },
    {
        "key": "InpDailyProfitTargetPercent",
        "category": "risk",
        "label": "Persentase Target Profit Harian",
        "type": "float",
        "step": 0.5,
        "min": 1.0,
        "max": 30.0,
        "default": 5.0,
        "unit": "%",
        "desc": "Target capaian profit harian dalam persen equity."
    },
    {
        "key": "InpUseMaxAccountDD",
        "category": "risk",
        "label": "Kill Switch Drawdown Total Akun",
        "type": "bool",
        "default": True,
        "desc": "Proteksi modal utama: kunci akun permanen jika drawdown mencapai batas krisis."
    },
    {
        "key": "InpMaxAccountDrawdown",
        "category": "risk",
        "label": "Batas Drawdown Total Akun",
        "type": "float",
        "step": 1.0,
        "min": 5.0,
        "max": 50.0,
        "default": 15.0,
        "unit": "%",
        "desc": "Batas maksimum drawdown dari modal awal sebelum EA menghentikan seluruh aktivitas."
    },
    {
        "key": "InpUseBasketLossPercent",
        "category": "risk",
        "label": "Cut Loss Basket (% Equity)",
        "type": "bool",
        "default": True,
        "desc": "Tutup paksa basket jika kerugian basket mencapai persentase equity saat ini."
    },
    {
        "key": "InpBasketLossPercent",
        "category": "risk",
        "label": "Persentase Cut Loss Basket",
        "type": "float",
        "step": 0.5,
        "min": 1.0,
        "max": 20.0,
        "default": 3.0,
        "unit": "%",
        "desc": "Batas cut-loss darurat untuk satu keranjang posisi."
    },
    {
        "key": "InpCutLossPerBasketUSD",
        "category": "risk",
        "label": "Cut Loss Basket Nominal USD",
        "type": "float",
        "step": 5.0,
        "min": 0.0,
        "max": 1000.0,
        "default": 0.0,
        "unit": "USD ($)",
        "desc": "Alternatif cut loss dalam nilai riil USD (0 = dinonaktifkan, pakai %)."
    },
    {
        "key": "InpUseMarginSafety",
        "category": "risk",
        "label": "Proteksi Ketahanan Margin Safety",
        "type": "bool",
        "default": True,
        "desc": "Cek margin level sebelum membuka entry atau averaging baru."
    },
    {
        "key": "InpMinMarginLevel",
        "category": "risk",
        "label": "Margin Level Minimum",
        "type": "float",
        "step": 10.0,
        "min": 50.0,
        "max": 500.0,
        "default": 150.0,
        "unit": "%",
        "desc": "EA menolak order jika margin level akun berada di bawah angka ini."
    },
    {
        "key": "InpBasketCooldownMinutes",
        "category": "risk",
        "label": "Jeda Menit Pasca Cut Loss Basket",
        "type": "int",
        "step": 5,
        "min": 1,
        "max": 240,
        "default": 60,
        "unit": "Menit",
        "desc": "Memberi waktu jeda bagi pasar untuk tenang sebelum mengizinkan order baru di arah yang sama."
    },

    # --- Category: FILTER & TIMING ---
    {
        "key": "InpTradingHourStart",
        "category": "filter",
        "label": "Jam Mulai Trading (Server MT5)",
        "type": "int",
        "step": 1,
        "min": 0,
        "max": 23,
        "default": 0,
        "unit": "Jam (0-23)",
        "desc": "Jam awal di mana EA diizinkan membuka posisi baru."
    },
    {
        "key": "InpTradingHourEnd",
        "category": "filter",
        "label": "Jam Akhir Trading (Server MT5)",
        "type": "int",
        "step": 1,
        "min": 1,
        "max": 24,
        "default": 24,
        "unit": "Jam (1-24)",
        "desc": "Jam batas akhir EA diizinkan entry baru (24 = nonstop 24 jam)."
    },
    {
        "key": "InpUseSpreadFilter",
        "category": "filter",
        "label": "Aktifkan Filter Spread",
        "type": "bool",
        "default": True,
        "desc": "Mencegah order saat spread broker melebar (misal saat rollover tengah malam)."
    },
    {
        "key": "InpMaxSpreadPoints",
        "category": "filter",
        "label": "Spread Maksimum Diizinkan",
        "type": "int",
        "step": 25,
        "min": 50,
        "max": 1000,
        "default": 300,
        "unit": "Points",
        "desc": "Batas atas spread yang diizinkan untuk open posisi baru maupun averaging."
    },
    {
        "key": "InpUseATRFilter",
        "category": "filter",
        "label": "Filter Volatilitas ATR Sehat",
        "type": "bool",
        "default": True,
        "desc": "Hanya entry saat volatilitas berada dalam rentang wajar (tidak terlalu sepi / tidak liar)."
    },
    {
        "key": "InpAvoidHighATRSpike",
        "category": "filter",
        "label": "Pause Saat Lonjakan Berita / Spike ATR",
        "type": "bool",
        "default": False,
        "desc": "Otomatis jeda order sementara saat terdeteksi candle impulsif berdampak berita tinggi."
    },
    {
        "key": "InpATRSpikeRatio",
        "category": "filter",
        "label": "Rasio Lonjakan Spike ATR",
        "type": "float",
        "step": 0.5,
        "min": 1.5,
        "max": 10.0,
        "default": 3.0,
        "unit": "x Rata-rata",
        "desc": "Jika ATR saat ini >= x kali rata-rata normal, kondisi dianggap spike."
    }
]

PRESET_TEMPLATES = {
    "1jt_controlled_martingale": {
        "name": "Modal 1 Juta (Controlled Martingale 24H)",
        "desc": "Preset bawaan optimal untuk modal Rp1.000.000 (~$65 USD): base lot 0.01, max 3 order, trailing cepat, dan cut-loss ketat.",
        "params": {
            "InpBaseLot": 0.01,
            "InpLotMode": 0,
            "InpLotMultiplier": 1.50,
            "InpLotAddFlat": 0.00,
            "InpAutoLotByBalance": False,
            "InpMTFEnabled": True,
            "InpMTFUseEMA200": True,
            "InpMTFUseSlope": True,
            "InpMTFSlopeMin": 10.0,
            "InpEMADirPeriod": 100,
            "InpEMA200Period": 200,
            "InpUseEMA200Filter": True,
            "InpUseStochFilter": True,
            "InpStochK": 5,
            "InpStochD": 3,
            "InpStochSlowing": 3,
            "InpStochOversold": 20.0,
            "InpStochOverbought": 80.0,
            "InpUseEMASlope": True,
            "InpEMASlopeBars": 5,
            "InpEMASlopeMin": 15.0,
            "InpFollowEMACooldownRules": True,
            "InpFixedAveragingDistancePoints": 200.0,
            "InpMaxOpenOrdersBasket": 3,
            "InpMaxTotalLotBasket": 0.03,
            "InpMaxAveragingCycle": 3,
            "InpCooldownCandles": 5,
            "InpMinSecondsBetweenAvg": 10,
            "InpAllowBuySellTogether": False,
            "InpAveragingWaitClose": False,
            "InpGridFollowHigherTF": True,
            "InpGridReverseOnTrendFlip": True,
            "InpUseBasketTrailing": True,
            "InpTrailStartPoints": 100,
            "InpTrailStopDistance": 50,
            "InpDisableTrailTP": False,
            "InpUseATRBasedTP": True,
            "InpATRTPMultiplier": 2.5,
            "InpFixedTPPoints": 3000.0,
            "InpUseProfitLock": True,
            "InpProfitLockStart": 500.0,
            "InpProfitLockPoints": 250.0,
            "InpUseDailyLossLimit": True,
            "InpDailyLossPercent": 5.0,
            "InpUseDailyProfitTarget": False,
            "InpDailyProfitTargetPercent": 5.0,
            "InpUseMaxAccountDD": True,
            "InpMaxAccountDrawdown": 15.0,
            "InpUseBasketLossPercent": True,
            "InpBasketLossPercent": 3.0,
            "InpCutLossPerBasketUSD": 0.0,
            "InpUseMarginSafety": True,
            "InpMinMarginLevel": 150.0,
            "InpUseSpreadFilter": True,
            "InpMaxSpreadPoints": 300,
            "InpBasketCooldownMinutes": 60,
            "InpTradingHourStart": 0,
            "InpTradingHourEnd": 24,
            "InpUseATRFilter": True,
            "InpAvoidHighATRSpike": False,
            "InpATRSpikeRatio": 3.0
        }
    },
    "safe_conservative": {
        "name": "Konservatif / Ultra-Safe Defense",
        "desc": "Fokus proteksi modal: averaging hanya 2 order, filter spread ketat (200pt), stop loss cepat, dan konfirmasi trend H4 wajib selaras.",
        "params": {
            "InpBaseLot": 0.01,
            "InpLotMode": 0,
            "InpLotMultiplier": 1.20,
            "InpLotAddFlat": 0.00,
            "InpAutoLotByBalance": False,
            "InpMTFEnabled": True,
            "InpMTFUseEMA200": True,
            "InpMTFUseSlope": True,
            "InpMTFSlopeMin": 15.0,
            "InpEMADirPeriod": 100,
            "InpEMA200Period": 200,
            "InpUseEMA200Filter": True,
            "InpUseStochFilter": True,
            "InpStochK": 5,
            "InpStochD": 3,
            "InpStochSlowing": 3,
            "InpStochOversold": 20.0,
            "InpStochOverbought": 80.0,
            "InpUseEMASlope": True,
            "InpEMASlopeBars": 5,
            "InpEMASlopeMin": 20.0,
            "InpFollowEMACooldownRules": True,
            "InpFixedAveragingDistancePoints": 300.0,
            "InpMaxOpenOrdersBasket": 2,
            "InpMaxTotalLotBasket": 0.02,
            "InpMaxAveragingCycle": 2,
            "InpCooldownCandles": 8,
            "InpMinSecondsBetweenAvg": 15,
            "InpAllowBuySellTogether": False,
            "InpAveragingWaitClose": True,
            "InpGridFollowHigherTF": True,
            "InpGridReverseOnTrendFlip": True,
            "InpUseBasketTrailing": True,
            "InpTrailStartPoints": 80,
            "InpTrailStopDistance": 40,
            "InpDisableTrailTP": False,
            "InpUseATRBasedTP": True,
            "InpATRTPMultiplier": 2.0,
            "InpFixedTPPoints": 2000.0,
            "InpUseProfitLock": True,
            "InpProfitLockStart": 300.0,
            "InpProfitLockPoints": 150.0,
            "InpUseDailyLossLimit": True,
            "InpDailyLossPercent": 3.0,
            "InpUseDailyProfitTarget": True,
            "InpDailyProfitTargetPercent": 3.0,
            "InpUseMaxAccountDD": True,
            "InpMaxAccountDrawdown": 10.0,
            "InpUseBasketLossPercent": True,
            "InpBasketLossPercent": 2.0,
            "InpCutLossPerBasketUSD": 0.0,
            "InpUseMarginSafety": True,
            "InpMinMarginLevel": 250.0,
            "InpUseSpreadFilter": True,
            "InpMaxSpreadPoints": 200,
            "InpBasketCooldownMinutes": 120,
            "InpTradingHourStart": 1,
            "InpTradingHourEnd": 23,
            "InpUseATRFilter": True,
            "InpAvoidHighATRSpike": True,
            "InpATRSpikeRatio": 2.5
        }
    },
    "scalper_aggressive": {
        "name": "Scalper Agresif M1 (High Frequency)",
        "desc": "Frekuensi trading tinggi: filter MTF dinonaktifkan (langsung eksekusi sinyal M1), trailing profit cepat, dan jarak grid lebih rapat.",
        "params": {
            "InpBaseLot": 0.01,
            "InpLotMode": 1,
            "InpLotMultiplier": 1.50,
            "InpLotAddFlat": 0.00,
            "InpAutoLotByBalance": False,
            "InpMTFEnabled": False,
            "InpMTFUseEMA200": False,
            "InpMTFUseSlope": False,
            "InpMTFSlopeMin": 5.0,
            "InpEMADirPeriod": 50,
            "InpEMA200Period": 200,
            "InpUseEMA200Filter": False,
            "InpUseStochFilter": True,
            "InpStochK": 5,
            "InpStochD": 3,
            "InpStochSlowing": 3,
            "InpStochOversold": 25.0,
            "InpStochOverbought": 75.0,
            "InpUseEMASlope": False,
            "InpEMASlopeBars": 3,
            "InpEMASlopeMin": 5.0,
            "InpFollowEMACooldownRules": True,
            "InpFixedAveragingDistancePoints": 150.0,
            "InpMaxOpenOrdersBasket": 4,
            "InpMaxTotalLotBasket": 0.06,
            "InpMaxAveragingCycle": 4,
            "InpCooldownCandles": 2,
            "InpMinSecondsBetweenAvg": 5,
            "InpAllowBuySellTogether": False,
            "InpAveragingWaitClose": False,
            "InpGridFollowHigherTF": False,
            "InpGridReverseOnTrendFlip": False,
            "InpUseBasketTrailing": True,
            "InpTrailStartPoints": 60,
            "InpTrailStopDistance": 30,
            "InpDisableTrailTP": False,
            "InpUseATRBasedTP": False,
            "InpATRTPMultiplier": 2.0,
            "InpFixedTPPoints": 1500.0,
            "InpUseProfitLock": True,
            "InpProfitLockStart": 300.0,
            "InpProfitLockPoints": 150.0,
            "InpUseDailyLossLimit": True,
            "InpDailyLossPercent": 7.0,
            "InpUseDailyProfitTarget": True,
            "InpDailyProfitTargetPercent": 8.0,
            "InpUseMaxAccountDD": True,
            "InpMaxAccountDrawdown": 20.0,
            "InpUseBasketLossPercent": True,
            "InpBasketLossPercent": 5.0,
            "InpCutLossPerBasketUSD": 0.0,
            "InpUseMarginSafety": True,
            "InpMinMarginLevel": 120.0,
            "InpUseSpreadFilter": True,
            "InpMaxSpreadPoints": 350,
            "InpBasketCooldownMinutes": 30,
            "InpTradingHourStart": 0,
            "InpTradingHourEnd": 24,
            "InpUseATRFilter": False,
            "InpAvoidHighATRSpike": False,
            "InpATRSpikeRatio": 3.5
        }
    }
}

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"pin": "1234", "daily_target_usd": 50.0, "accounts": [], "active_account_id": ""}

def save_config(cfg):
    try:
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        print(f"Error saving config: {e}")

def parse_set_file(filepath):
    params = {}
    if not os.path.exists(filepath):
        return params
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith(";"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip()
                    if v.lower() == "true":
                        val = True
                    elif v.lower() == "false":
                        val = False
                    else:
                        try:
                            if "." in v:
                                val = float(v)
                            else:
                                val = int(v)
                        except ValueError:
                            val = v
                    params[k] = val
    except Exception as e:
        print(f"Error parsing .set file {filepath}: {e}")
    return params

def save_set_file(filepath, updated_params):
    try:
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        lines = []
        if os.path.exists(filepath):
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
        else:
            lines = ["; RoyalViento Parameter Set File\n"]

        existing_keys = set()
        new_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped and not stripped.startswith(";") and "=" in stripped:
                k, _ = stripped.split("=", 1)
                k = k.strip()
                existing_keys.add(k)
                if k in updated_params:
                    val = updated_params[k]
                    if isinstance(val, bool):
                        val_str = "true" if val else "false"
                    elif isinstance(val, float):
                        val_str = f"{val:.2f}" if (val != int(val)) else f"{val:.1f}"
                    else:
                        val_str = str(val)
                    new_lines.append(f"{k}={val_str}\n")
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)

        # Append new parameters not yet in file
        for k, val in updated_params.items():
            if k not in existing_keys:
                if isinstance(val, bool):
                    val_str = "true" if val else "false"
                elif isinstance(val, float):
                    val_str = f"{val:.2f}"
                else:
                    val_str = str(val)
                new_lines.append(f"{k}={val_str}\n")

        with open(filepath, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
        return True
    except Exception as e:
        print(f"Error saving .set file {filepath}: {e}")
        return False

def get_current_parameters():
    # 1. Try reading live parameters from status file
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8", errors="ignore") as f:
                st = json.load(f)
                if st.get("parameters") and isinstance(st["parameters"], dict):
                    return st["parameters"]
        except Exception:
            pass

    # 2. Fall back to preset files
    for p in PRESET_PATHS:
        if os.path.exists(p):
            parsed = parse_set_file(p)
            if parsed:
                return parsed

    # 3. Fall back to defaults from definitions
    defaults = {}
    for d in PARAMETER_DEFINITIONS:
        defaults[d["key"]] = d["default"]
    return defaults

def update_start_ini(account_info):
    """Update start.ini files for MT5 launch"""
    login = account_info.get("login", "")
    password = account_info.get("password", "")
    server = account_info.get("server", "")
    symbol = account_info.get("symbol", "XAUUSDm")

    ini_content = f"""[Common]
Login={login}
Password={password}
Server={server}
ProxyEnable=0
CertInstall=0
NewsEnable=0

[Charts]
ProfileLast=Default
MaxBars=100000

[Experts]
AllowDllImport=1
Enabled=1
Account=0
Profile=0

[StartUp]
Expert=RoyalQuantum_EA_v2.36_SingleEntryHistory
ExpertParameters=RoyalViento_XAUUSD_M1_1JT_24H_CONTROLLED_MARTINGALE.set
Symbol={symbol}
Period=M1
"""
    for path in START_INI_PATHS:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(ini_content)
        except Exception as e:
            print(f"Error writing {path}: {e}")

def is_mt5_running():
    try:
        res = subprocess.run(["pgrep", "-f", "terminal64.exe"], capture_output=True, text=True)
        return res.returncode == 0
    except Exception:
        return False

def get_cloudflare_url():
    import re
    if os.path.exists(CLOUDFLARE_LOG):
        try:
            with open(CLOUDFLARE_LOG, "r") as f:
                text = f.read()
                matches = re.findall(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', text)
                if matches:
                    return matches[-1]
        except Exception:
            pass
    return None

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/auth", methods=["POST"])
def auth():
    data = request.json or {}
    pin = data.get("pin", "")
    cfg = load_config()
    if pin == cfg.get("pin", "1234"):
        session["authenticated"] = True
        return jsonify({"success": True})
    return jsonify({"success": False, "message": "PIN Salah!"}), 401

@app.route("/api/auth_check", methods=["GET"])
def auth_check():
    return jsonify({"authenticated": session.get("authenticated", False)})

@app.route("/api/status", methods=["GET"])
def get_status():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    cfg = load_config()
    running = is_mt5_running()

    status_data = {}
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8", errors="ignore") as f:
                status_data = json.load(f)
        except Exception as e:
            status_data = {"error": f"Error parsing status: {str(e)}"}
    else:
        status_data = {"warning": "Status file belum tersedia"}

    status_data["mt5_running"] = running
    status_data["configured_target_usd"] = cfg.get("daily_target_usd", 50.0)
    status_data["cf_url"] = get_cloudflare_url()

    # Active account meta
    active_id = str(cfg.get("active_account_id", ""))
    status_data["active_account_id"] = active_id
    active_acc = next((a for a in cfg.get("accounts", []) if str(a.get("id")) == active_id), None)
    if active_acc:
        status_data["account_name"] = active_acc.get("name")
        status_data["account_type"] = active_acc.get("type", "demo")

    # Fallback MTF signals if MT5 is starting up or status is pending
    if "mtf" not in status_data or not status_data["mtf"]:
        status_data["mtf"] = {
            "enabled": True,
            "mode": status_data.get("trading_mode", "safe"),
            "summary": "INITIALIZING",
            "confirmed": True,
            "m1": {
                "tf": "M1", "signal": "SCANNING", "direction": 0, "valid": False,
                "close": 0.0, "ema_dir": 0.0, "ema_200": 0.0, "stoch": 50.0, "slope_pts": 0.0,
                "ema_ok": False, "slope_ok": False
            },
            "m5": {
                "tf": "M5", "signal": "SCANNING", "direction": 0, "valid": False,
                "close": 0.0, "ema_dir": 0.0, "ema_200": 0.0, "stoch": 50.0, "slope_pts": 0.0,
                "ema_ok": False, "slope_ok": False
            },
            "h4": {
                "tf": "H4", "signal": "SCANNING", "direction": 0, "valid": False,
                "close": 0.0, "ema_dir": 0.0, "ema_200": 0.0, "stoch": 50.0, "slope_pts": 0.0,
                "ema_ok": False, "slope_ok": False
            }
        }

    # Parameters fallback
    if "parameters" not in status_data or not status_data["parameters"]:
        status_data["parameters"] = get_current_parameters()

    # System stats
    try:
        load1, load5, load15 = os.getloadavg()
        status_data["sys_load"] = f"{load1:.2f}, {load5:.2f}"
    except Exception:
        status_data["sys_load"] = "N/A"

    return jsonify(status_data)

@app.route("/api/parameters", methods=["GET"])
def get_parameters():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    current_params = get_current_parameters()

    # Format values according to schema
    formatted_params = {}
    for defn in PARAMETER_DEFINITIONS:
        k = defn["key"]
        val = current_params.get(k, defn["default"])
        if defn["type"] == "bool":
            if isinstance(val, str):
                val = (val.lower() == "true")
            else:
                val = bool(val)
        elif defn["type"] == "float":
            try:
                val = float(val)
            except Exception:
                val = float(defn["default"])
        elif defn["type"] in ("int", "select"):
            try:
                val = int(val)
            except Exception:
                val = int(defn["default"])
        formatted_params[k] = val

    return jsonify({
        "categories": PARAMETER_CATEGORIES,
        "definitions": PARAMETER_DEFINITIONS,
        "parameters": formatted_params,
        "presets": [
            {"id": pid, "name": pinfo["name"], "desc": pinfo["desc"]}
            for pid, pinfo in PRESET_TEMPLATES.items()
        ],
        "active_preset": "RoyalViento_XAUUSD_M1_1JT_24H_CONTROLLED_MARTINGALE.set"
    })

@app.route("/api/parameters/update", methods=["POST"])
def update_parameters():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    new_params = data.get("parameters", {})
    restart_mt5 = data.get("restart_mt5", True)

    if not new_params or not isinstance(new_params, dict):
        return jsonify({"success": False, "message": "Parameter tidak valid"}), 400

    # Type casting based on schema
    def_map = {d["key"]: d for d in PARAMETER_DEFINITIONS}
    sanitized = {}
    for k, v in new_params.items():
        if k in def_map:
            t = def_map[k]["type"]
            if t == "bool":
                sanitized[k] = bool(v) if not isinstance(v, str) else (v.lower() == "true")
            elif t == "float":
                try:
                    sanitized[k] = float(v)
                except Exception:
                    pass
            elif t in ("int", "select"):
                try:
                    sanitized[k] = int(v)
                except Exception:
                    pass
        else:
            sanitized[k] = v

    # 1. Save to preset files
    saved_paths = []
    for path in PRESET_PATHS:
        if save_set_file(path, sanitized):
            saved_paths.append(path)

    # 2. Write dynamic parameters command to MT5 if running
    try:
        os.makedirs(os.path.dirname(COMMAND_FILE), exist_ok=True)
        with open(COMMAND_FILE, "w") as f:
            json.dump({
                "action": "set_parameters",
                "parameters": sanitized
            }, f)
    except Exception as e:
        print(f"Error writing to COMMAND_FILE: {e}")

    # 3. Optional restart of MT5 to cleanly load .set parameters
    restarted = False
    if restart_mt5:
        try:
            subprocess.Popen(["systemctl", "restart", "mt5-trading"])
            restarted = True
        except Exception as e:
            print(f"Note: Could not restart mt5-trading service (expected in dev environment): {e}")

    msg = "Semua parameter berhasil disimpan ke preset MT5!"
    if restarted:
        msg += " MT5 sedang dimuat ulang dengan parameter baru..."
    else:
        msg += " Parameter akan aktif penuh saat MT5 dimulai ulang."

    return jsonify({
        "success": True,
        "message": msg,
        "restarted": restarted,
        "saved_files": len(saved_paths)
    })

@app.route("/api/parameters/preset", methods=["POST"])
def apply_preset():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    preset_id = data.get("preset_id", "")
    restart_mt5 = data.get("restart_mt5", True)

    if preset_id not in PRESET_TEMPLATES:
        return jsonify({"success": False, "message": f"Preset '{preset_id}' tidak ditemukan"}), 404

    target_preset = PRESET_TEMPLATES[preset_id]
    preset_params = target_preset["params"]

    # Save to all preset paths
    for path in PRESET_PATHS:
        save_set_file(path, preset_params)

    # Write command
    try:
        os.makedirs(os.path.dirname(COMMAND_FILE), exist_ok=True)
        with open(COMMAND_FILE, "w") as f:
            json.dump({
                "action": "set_parameters",
                "parameters": preset_params
            }, f)
    except Exception:
        pass

    restarted = False
    if restart_mt5:
        try:
            subprocess.Popen(["systemctl", "restart", "mt5-trading"])
            restarted = True
        except Exception:
            pass

    return jsonify({
        "success": True,
        "message": f"Preset '{target_preset['name']}' berhasil diterapkan!" + (" MT5 sedang direstart..." if restarted else ""),
        "parameters": preset_params,
        "restarted": restarted
    })

@app.route("/api/accounts", methods=["GET"])
def get_accounts():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    cfg = load_config()
    accounts = cfg.get("accounts", [])
    active_id = str(cfg.get("active_account_id", ""))

    safe_accounts = []
    for acc in accounts:
        safe_accounts.append({
            "id": str(acc.get("id")),
            "name": acc.get("name", ""),
            "login": acc.get("login", ""),
            "server": acc.get("server", ""),
            "type": acc.get("type", "demo"),
            "symbol": acc.get("symbol", "XAUUSDm")
        })

    return jsonify({
        "active_account_id": active_id,
        "accounts": safe_accounts
    })

@app.route("/api/account/switch", methods=["POST"])
def switch_account():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    target_id = str(data.get("account_id", "")).strip()

    cfg = load_config()
    accounts = cfg.get("accounts", [])
    target_acc = next((a for a in accounts if str(a.get("id")) == target_id), None)

    if not target_acc:
        return jsonify({"success": False, "message": "Akun tidak ditemukan"}), 404

    # 1. Update start.ini
    update_start_ini(target_acc)

    # 2. Update config.json
    cfg["active_account_id"] = target_id
    save_config(cfg)

    # 3. Remove old status file
    try:
        if os.path.exists(STATUS_FILE):
            os.remove(STATUS_FILE)
    except Exception:
        pass

    # 4. Restart mt5-trading service
    try:
        subprocess.Popen(["systemctl", "restart", "mt5-trading"])
    except Exception as e:
        return jsonify({"success": False, "message": f"Gagal me-restart MT5: {str(e)}"}), 500

    return jsonify({
        "success": True,
        "message": f"Beralih ke {target_acc.get('name')} ({target_acc.get('server')}). MT5 sedang dimuat ulang...",
        "account": {
            "id": target_id,
            "name": target_acc.get("name"),
            "server": target_acc.get("server"),
            "type": target_acc.get("type", "demo")
        }
    })

@app.route("/api/account/save", methods=["POST"])
def save_account():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    acc_id = str(data.get("id", "")).strip()
    name = str(data.get("name", "")).strip()
    login = data.get("login")
    password = str(data.get("password", "")).strip()
    server = str(data.get("server", "")).strip()
    acc_type = str(data.get("type", "demo")).lower().strip()
    symbol = str(data.get("symbol", "XAUUSDm")).strip()

    if not name or not login or not server:
        return jsonify({"success": False, "message": "Nama, login, dan server wajib diisi"}), 400

    try:
        login = int(login)
    except Exception:
        pass

    cfg = load_config()
    accounts = cfg.get("accounts", [])

    existing = next((a for a in accounts if str(a.get("id")) == acc_id), None)
    if existing:
        existing["name"] = name
        existing["login"] = login
        if password:
            existing["password"] = password
        existing["server"] = server
        existing["type"] = acc_type
        existing["symbol"] = symbol
    else:
        if not password:
            return jsonify({"success": False, "message": "Password wajib diisi untuk akun baru"}), 400
        new_id = acc_id if acc_id else str(login)
        accounts.append({
            "id": new_id,
            "name": name,
            "login": login,
            "password": password,
            "server": server,
            "type": acc_type,
            "symbol": symbol
        })

    cfg["accounts"] = accounts
    save_config(cfg)
    return jsonify({"success": True, "message": "Data akun berhasil disimpan"})

@app.route("/api/command", methods=["POST"])
def send_command():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    action = data.get("action", "")

    cfg = load_config()

    try:
        os.makedirs(os.path.dirname(COMMAND_FILE), exist_ok=True)
    except Exception:
        pass

    if action == "set_daily_target":
        target = float(data.get("value", 50.0))
        cfg["daily_target_usd"] = target
        save_config(cfg)
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "set_daily_target", "value": target}, f)
        return jsonify({"success": True, "message": f"Target harian berhasil diatur ke ${target:.2f}"})

    elif action == "pause":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "pause"}, f)
        return jsonify({"success": True, "message": "Trading di-Pause"})

    elif action == "resume":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "resume"}, f)
        return jsonify({"success": True, "message": "Trading di-Resume"})

    elif action == "close_all":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "close_all"}, f)
        return jsonify({"success": True, "message": "Perintah tutup semua posisi dikirim!"})

    elif action == "close_ticket":
        ticket = int(data.get("ticket", 0))
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "close_ticket", "ticket": ticket}, f)
        return jsonify({"success": True, "message": f"Perintah tutup tiket #{ticket} dikirim!"})

    elif action == "reset_daily":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "reset_daily"}, f)
        return jsonify({"success": True, "message": "Statistik profit harian di-reset ke 0"})

    elif action == "set_mode":
        mode = data.get("mode", "scalper")
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "set_mode", "mode": mode}, f)
        mode_label = "Mode Aman (MTF H4/M5)" if mode == "safe" else "Mode Scalper M1 (Aktif)"
        return jsonify({"success": True, "message": f"Mode trading diubah ke: {mode_label}"})

    elif action == "toggle_algo":
        try:
            subprocess.run("export DISPLAY=:99 && xdotool key ctrl+e", shell=True, timeout=5)
            return jsonify({"success": True, "message": "Tombol Algo Trading di-toggle!"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)}), 500

    return jsonify({"success": False, "message": "Action tidak dikenal"}), 400

@app.route("/api/server", methods=["POST"])
def server_control():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    op = data.get("operation", "")

    if op == "restart_mt5":
        try:
            subprocess.Popen(["systemctl", "restart", "mt5-trading"])
            return jsonify({"success": True, "message": "Layanan MT5 sedang direstart..."})
        except Exception as e:
            return jsonify({"success": False, "message": f"Error restarting MT5: {str(e)}"}), 500
    elif op == "stop_mt5":
        try:
            subprocess.Popen(["systemctl", "stop", "mt5-trading"])
            return jsonify({"success": True, "message": "Layanan MT5 dihentikan."})
        except Exception as e:
            return jsonify({"success": False, "message": f"Error stopping MT5: {str(e)}"}), 500
    elif op == "start_mt5":
        try:
            subprocess.Popen(["systemctl", "start", "mt5-trading"])
            return jsonify({"success": True, "message": "Layanan MT5 dijalankan."})
        except Exception as e:
            return jsonify({"success": False, "message": f"Error starting MT5: {str(e)}"}), 500
    elif op == "change_pin":
        new_pin = str(data.get("pin", "")).strip()
        if len(new_pin) >= 4:
            cfg = load_config()
            cfg["pin"] = new_pin
            save_config(cfg)
            return jsonify({"success": True, "message": "PIN keamanan berhasil diubah!"})
        return jsonify({"success": False, "message": "PIN minimal 4 karakter"}), 400

    return jsonify({"success": False, "message": "Operasi tidak valid"}), 400

@app.route("/api/screenshot")
def screenshot():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401
    try:
        subprocess.run("export DISPLAY=:99 && scrot -o " + SCREENSHOT_PATH, shell=True, timeout=5)
        if os.path.exists(SCREENSHOT_PATH):
            return send_file(SCREENSHOT_PATH, mimetype="image/png", max_age=0)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({"error": "Failed to capture screenshot"}), 500

@app.route("/api/logs")
def get_logs():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    # Latest MQL5 log
    mql5_logs = sorted(glob.glob("/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/logs/*.log"), key=os.path.getmtime)
    ea_log_lines = []
    if mql5_logs:
        try:
            with open(mql5_logs[-1], "rb") as f:
                content = f.read().decode("utf-16le", errors="ignore")
                ea_log_lines = content.splitlines()[-40:]
        except Exception:
            pass

    # Latest Terminal log
    term_logs = sorted(glob.glob("/root/.wine/drive_c/Program Files/MetaTrader 5/logs/*.log"), key=os.path.getmtime)
    term_log_lines = []
    if term_logs:
        try:
            with open(term_logs[-1], "rb") as f:
                content = f.read().decode("utf-16le", errors="ignore")
                term_log_lines = content.splitlines()[-40:]
        except Exception:
            pass

    return jsonify({
        "ea_logs": ea_log_lines,
        "terminal_logs": term_log_lines
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
