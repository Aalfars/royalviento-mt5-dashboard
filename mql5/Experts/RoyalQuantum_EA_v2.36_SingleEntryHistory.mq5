//+------------------------------------------------------------------+
//| RoyalQuantum_EA_v2.04.mq5                                   |
//| Rekreasi strategi berdasarkan analisis visual dashboard EA        |
//| "EA Royal Quantum Final Mix 2.00" — BUKAN kode asli, hasil         |
//| rekonstruksi & redesign risk management independen.               |
//|                                                                    |
//| v2.35 — GRID TREND FOLLOW: averaging cek M5+H4; flip = close basket + follow trend baru
//| v2.10 — FIX FINAL: Adaptive DD self-rearm + no Peak DD lock + tester stale-lock reset
//| v2.36 — HISTORY: single-entry closes are shown as SINGLE; baskets keep format
//| v2.05 — CONTROLLED XAUUSD M1: safer averaging + profit-protect basket exit
//| v2.04 — ACCOUNT CURRENCY SAFE / REDESIGN RISK MANAGEMENT setelah v2.02 gagal di 3         |
//| backtest berturut-turut (Stop Out hari-1 dan Stop Out hari-26     |
//| dengan balance tersisa $1.19). Lihat Docs/CHANGELOG.md.           |
//|                                                                    |
//| Modul baru v2.03 (lihat masing-masing file utk detail & alasan):  |
//|  1. Daily Risk Kill Switch (% equity)      -> RiskManager.mqh     |
//|  2. Total Account Drawdown Kill Switch     -> RiskManager.mqh     |
//|     (PERSISTEN via GlobalVariable, reset manual wajib)            |
//|  3. Basket Cut Loss berbasis % equity      -> RiskManager.mqh     |
//|  4. Exposure Cap (total lot & jml order)   -> BasketManager.mqh   |
//|  5. ATR Dynamic Averaging Distance         -> ATRManager.mqh      |
//|  6. Hard Stop Loss Broker (ATR-based)      -> BasketManager.mqh   |
//|  7. Margin Safety sebelum entry/averaging  -> RiskManager.mqh     |
//|  8. Auto Lot by Equity (naik & turun)      -> MoneyManagement.mqh |
//|  9. Spread Filter                          -> RiskManager.mqh     |
//| 10. Basket Cooldown setelah cut-loss       -> RiskManager.mqh     |
//| 11. Trend Strength Filter (EMA Slope)      -> EntryManager.mqh    |
//| 12. News/ATR Spike Block                   -> ATRManager.mqh      |
//|                                                                    |
//| PERINGATAN RISIKO:                                                |
//| Lot averaging (martingale/grid-style) tetap berisiko tinggi walau |
//| sudah diberi banyak lapis proteksi. SELALU uji di akun demo/tester|
//| dgn data tick 100% sebelum live, dan pahami risikonya sepenuhnya. |
//| Modul kill-switch di sini MENGURANGI risiko Stop Out, TIDAK       |
//| menghilangkannya - gap harga ekstrem / broker disconnect tetap    |
//| bisa menyebabkan kerugian besar.                                  |
//+------------------------------------------------------------------+
#property copyright "Rekreasi & redesign independen - bukan afiliasi resmi"
#property version   "2.35"
#property strict

#define __ROYAL_QUANTUM__ 1

//======================================================================
// ROYAL QUANTUM BRANDING
// Resource BMP files are intentionally not required in this build.
// The dashboard uses native MT5 labels/buttons so the EA compiles
// without external BMP files.
//======================================================================

//======================================================================
// ---- BEGIN Globals.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| Globals.mqh                                                      |
//| RoyalQuantum_EA v2.03                                       |
//| State bersama antar modul. Di-include PALING ATAS di file utama, |
//| sebelum modul lain, karena semua modul lain mengasumsikan        |
//| variabel di sini sudah dideklarasikan (compile unit = textual    |
//| concatenation di MQL5).                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

string PFX = "RQ_"; // prefix objek dashboard

input group "=== General ==="
input int      InpMagic              = 20260707;   // Magic number
input ENUM_TIMEFRAMES InpTF          = PERIOD_M1;   // Timeframe analisis
input bool     InpShowPanel          = true;        // Tampilkan panel info di chart
input bool     InpShowBasketHistory = true;        // Tampilkan dashboard histori basket CLOSED
input int      InpBasketHistoryRows  = 5;             // Jumlah basket histori per halaman (maksimum tersimpan 20)
input int      InpMaxSlippage        = 20;          // Slippage maksimal (poin)
input string   InpOrderComment       = "ROYAL QUANTUM 2.20";// Komen order
input double   InpCloseBufferPoints  = 10.0;        // Buffer poin: EA close sedikit lebih awal dari ambang exit

input group "=== MULTI TIMEFRAME (M1 + M5 + H4) ==="
input bool     InpMTFEnabled          = true;        // Aktifkan filter Multi Timeframe
input ENUM_TIMEFRAMES InpMTFEntryTF   = PERIOD_M1;   // TF Entry / signal utama
input ENUM_TIMEFRAMES InpMTFConfirmTF = PERIOD_M5;   // TF Konfirmasi
input ENUM_TIMEFRAMES InpMTFTrendTF   = PERIOD_H4;   // TF Trend utama
input bool     InpMTFUseEMA200       = true;        // M5/H4 wajib searah EMA200
input bool     InpMTFUseSlope        = true;        // M5/H4 wajib memiliki slope EMA searah
input double   InpMTFSlopeMin        = 10.0;        // Minimum slope dalam point pada M5/H4
input bool     InpShowMTFDashboard   = true;        // Tampilkan dashboard MTF terpisah
bool           g_webMTFEnabled       = true;        // Runtime toggle via WebBridge (Safe MTF vs Scalper M1)

input group "=== LICENSE / SECURITY ==="
// Untuk lisensi produksi, isi RQ_LICENSE_IDS[] dengan account yang diizinkan.
// ID dibuat const agar user tidak dapat mengubahnya melalui input EA.
const long RQ_LICENSE_IDS[] =
  {
   10012687831, // MetaQuotes Demo
   463998681,   // Exness Demo Trial 17
   268028163,   // Exness Real 39
   374587438,
   235266628, 235245454, 374858304, 2028872, 0, 0, 0, 0, 0, 0
  };
const datetime RQ_LICENSE_EXPIRY = D'2026.12.31 23:59:59';

//================= ENUMS (dipakai lintas modul) =================
enum ENUM_LOT_AVERAGING_MODE
  {
   LOT_MODE_ADD_FLAT = 0,   // Lot ditambah flat tiap averaging
   LOT_MODE_MULTIPLIER = 1  // Lot dikali multiplier tiap averaging
  };

enum ENUM_ACCOUNT_STATUS
  {
   ACC_STATUS_SAFE = 0,
   ACC_STATUS_RISK = 1,
   ACC_STATUS_LOCKED = 2
  };

enum ENUM_ADAPTIVE_DD_MODE
  {
   DD_MODE_AGGRESSIVE = 0,
   DD_MODE_DEFENSIVE  = 1,
   DD_MODE_RECOVERY   = 2,
   DD_MODE_EMERGENCY  = 3,
   DD_MODE_HARD       = 4
  };

int      g_adaptiveDDMode      = DD_MODE_AGGRESSIVE;
bool     g_adaptiveDDHalted    = false;
datetime g_adaptiveDDLockTime   = 0;
int      g_adaptiveDDStableBars = 0;
datetime g_adaptiveDDLastBar    = 0;
double   g_adaptiveDDBaseline   = 0.0;

//---- Trailing peak state (per basket) ----
double   g_buyPeakPts  = -1e9;
double   g_sellPeakPts = -1e9;

//---- Cooldown candle-based (dipakai saat InpFollowEMACooldownRules) ----
int      g_buyCooldownLeft  = 0;
int      g_sellCooldownLeft = 0;
datetime g_lastBarTimeSeenBuyCD  = 0;
datetime g_lastBarTimeSeenSellCD = 0;

//---- Cooldown menit-based, khusus SETELAH basket kena cut-loss (Module 10) ----
datetime g_buyCooldownUntil  = 0;
datetime g_sellCooldownUntil = 0;

// v2.15 diagnostics: alasan terakhir entry/averaging tertahan.
string   g_entryBlockReason = "NONE";
string   g_buyBlockReason   = "";
string   g_sellBlockReason  = "";
string   g_otherBlockReason = "";
datetime g_lastHeartbeatTime = 0;

//---- State averaging (candle-wait & minimum time-gap) ----
datetime g_buyLastAvgBarTime  = 0;
datetime g_sellLastAvgBarTime = 0;
datetime g_buyLastAvgTime     = 0; // jam:menit:detik averaging terakhir (anti burst dalam 1 candle)
datetime g_sellLastAvgTime    = 0;

//---- Daily state (reset tiap hari server) ----
datetime g_dayStart;
double   g_dayStartEquity;
double   g_dailyProfit;
bool     g_dailyTargetHit = false;
bool     g_dailyLossHit   = false;

//---- Account-level state (kill-switch drawdown total, PERSISTEN lintas restart) ----
double   g_accountBaselineEquity = 0;
bool     g_accountLocked         = false;
string   g_accountLockReason     = "";
datetime g_accountLockTime       = 0;  // MODULE 2C: kapan akun terakhir dikunci, basis hitung cooldown auto-reset

//---- MODULE 2B: peak equity tertinggi yang pernah dicapai akun, PERSISTEN ----
//     (beda dari g_accountBaselineEquity yang tetap di modal AWAL - ini naik
//     terus mengikuti rekor tertinggi equity, dipakai utk drawdown dari peak,
//     bukan dari modal awal. Lihat RiskManager.mqh Module 2B.)
double   g_accountPeakEquity     = 0;

//---- MODULE 2C: state auto-reset bersyarat kondisi pasar (RiskManager.mqh) ----
int      g_autoResetStableBars   = 0;   // hitung candle berturut-turut kondisi pasar "sehat" sejak lock
datetime g_autoResetLastBarTime  = 0;   // guard supaya hitung sekali per candle baru, bukan per tick

//---- Indicator handles (dibuat di EntryManager/ATRManager, dipakai lintas modul) ----
int      hEMADir = INVALID_HANDLE;
int      hEMA200 = INVALID_HANDLE;
int      hStoch  = INVALID_HANDLE;
int      hATR    = INVALID_HANDLE;

//---- Multi Timeframe handles (M1 / M5 / H4) ----
int      hMTFDirM5   = INVALID_HANDLE;
int      hMTF200M5   = INVALID_HANDLE;
int      hMTFStochM5 = INVALID_HANDLE;
int      hMTFDirH4   = INVALID_HANDLE;
int      hMTF200H4   = INVALID_HANDLE;
int      hMTFStochH4 = INVALID_HANDLE;

struct RQMTFState
  {
   bool valid;
   int direction;
   double close;
   double emaDir;
   double ema200;
   double stoch;
   double slopePts;
   bool emaOK;
   bool slopeOK;
  };

RQMTFState g_mtfM1, g_mtfM5, g_mtfH4;
bool g_mtfDashboardVisible=true;
bool g_mtfDashboardLocked=false;
int g_mtfX=15, g_mtfY=470;
int g_mtfW=380, g_mtfH=245;

//+------------------------------------------------------------------+
//---- END Globals.mqh ----
//======================================================================
// ---- BEGIN MoneyManagement.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| MoneyManagement.mqh                                              |
//| RoyalQuantum_EA v2.04                                       |
//| FIX v2.04 (Module 8 - Account Currency Safe):                  |
//|  - Parameter referensi Auto Lot tetap dalam USD agar preset     |
//|    lama mudah dipahami.                                          |
//|  - Untuk simbol dengan profit currency USD (termasuk XAUUSD),   |
//|    nominal USD otomatis dikonversi ke currency akun (IDR/USD).  |
//|  - Perhitungan step equity memakai nilai currency akun, bukan   |
//|    angka mentah 100/500 yang sebelumnya salah pada akun IDR.    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
input group "=== Money Management / Auto Lot ==="
input double   InpBaseLot            = 0.01;     // Lot awal (dipakai jika Auto Lot OFF, atau sebagai lantai minimum)
input ENUM_LOT_AVERAGING_MODE InpLotMode = LOT_MODE_MULTIPLIER; // Mode lot averaging
input double   InpLotMultiplier      = 1.50;     // Multiplier averaging (mode = Multiplier)
input double   InpLotAddFlat         = 0.02;     // Penambahan lot flat (mode = Add Lot)
input bool     InpAutoLotByBalance   = true;     // Auto sesuaikan lot berdasarkan EQUITY (naik & turun)
input double   InpRiskPer100USD      = 0.01;     // Tambahan lot per kelipatan 100 USD equity (otomatis dikonversi ke currency akun)
input double   InpEquityBaseUnit     = 500.0;    // Equity acuan dalam USD (otomatis dikonversi ke currency akun)

//+------------------------------------------------------------------+
//| FIX v2.01 (dipertahankan): NormalizeDouble supaya volume tidak   |
//| menyisakan galat floating-point (mis. 0.010000000002) yang bisa  |
//| ditolak broker sebagai "invalid volume".                         |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   int stepDigits = 2;
   if(lotStep > 0)
      stepDigits = (int)MathRound(-MathLog10(lotStep));
   if(stepDigits < 0) stepDigits = 0;

   double normalized = MathRound(lot/lotStep)*lotStep;
   normalized = NormalizeDouble(normalized, stepDigits);
   normalized = MathMax(minLot, normalized);
   normalized = MathMin(normalized, maxLot);
   return normalized;
  }

//+------------------------------------------------------------------+
//| Base lot efektif, ikut naik/turun sesuai equity saat ini.        |
//| Equity turun -> steps turun -> lot ikut mengecil, bukan tetap    |
//| seperti versi lama yang berbasis balance & tidak pernah turun.   |
//+------------------------------------------------------------------+
// Konversi nominal USD ke mata uang deposit akun.
// Untuk XAUUSD/EURUSD/GBPUSD dst. profit currency = USD, sehingga
// profit 1 lot untuk perubahan harga +1.00 memberi kurs USD->account.
double USDToAccountCurrency(double usd)
  {
   if(usd <= 0.0) return 0.0;

   string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   if(accountCurrency == "USD") return usd;

   string profitCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(profitCurrency != "USD")
     {
      Print("[MoneyManagement] Profit currency simbol bukan USD (", profitCurrency,
            "). Konversi USD otomatis tidak dapat ditentukan; nominal USD dipakai apa adanya.");
      return usd;
     }

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(price <= 0.0 || contractSize <= 0.0) return usd;

   double profitAccount = 0.0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price + 1.0, profitAccount))
      return usd;

   double accountPerUSD = MathAbs(profitAccount) / contractSize;
   if(accountPerUSD <= 0.0) return usd;

   return usd * accountPerUSD;
  }

double GetEquityBaseUnitAccount()
  {
   return USDToAccountCurrency(InpEquityBaseUnit);
  }

double GetEquityStepAccount()
  {
   return USDToAccountCurrency(100.0);
  }

double GetEffectiveBaseLot()
  {
   if(!InpAutoLotByBalance) return InpBaseLot;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseUnit = GetEquityBaseUnitAccount();
   double stepAmount = GetEquityStepAccount();
   if(stepAmount <= 0.0) return InpBaseLot;

   double steps = MathFloor((eq - baseUnit) / stepAmount);
   if(steps < 0) steps = 0;

   double lot = InpBaseLot + steps * InpRiskPer100USD;
   if(lot < InpBaseLot) lot = InpBaseLot;
   return lot;
  }

double GetEffectiveAddFlat()
  {
   if(!InpAutoLotByBalance) return InpLotAddFlat;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseUnit = GetEquityBaseUnitAccount();
   double stepAmount = GetEquityStepAccount();
   if(stepAmount <= 0.0) return InpLotAddFlat;

   double steps = MathFloor((eq - baseUnit) / stepAmount);
   if(steps < 0) steps = 0;

   double addFlat = InpLotAddFlat + steps * (InpRiskPer100USD * 0.5);
   if(addFlat < InpLotAddFlat) addFlat = InpLotAddFlat;
   return addFlat;
  }

//+------------------------------------------------------------------+
//| Hitung lot untuk entry berikutnya dalam basket                   |
//+------------------------------------------------------------------+
double CalcNextLot(int count, double lastLot)
  {
   double baseLot = GetEffectiveBaseLot();
   if(count == 0) return NormalizeLot(baseLot);

   if(InpLotMode == LOT_MODE_ADD_FLAT)
     {
      double addFlat = GetEffectiveAddFlat();
      return NormalizeLot(baseLot + count*addFlat);
     }
   else // LOT_MODE_MULTIPLIER
     {
      double lot = (lastLot > 0) ? lastLot*InpLotMultiplier : baseLot*InpLotMultiplier;
      return NormalizeLot(lot);
     }
  }

//+------------------------------------------------------------------+
//---- END MoneyManagement.mqh ----
//======================================================================
// ---- BEGIN ATRManager.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| ATRManager.mqh                                                   |
//| RoyalQuantum_EA v2.03                                       |
//| MODULE 5 - FIXED POINT AVERAGING:                                 |
//|  Jarak averaging tidak lagi angka statis (v2.02: 500 poin utk    |
//|  semua kondisi pasar), tapi mengikuti ATR saat ini supaya grid   |
//|  melebar otomatis saat volatilitas naik dan menyempit saat sepi. |
//| MODULE 12 - News Volatility Block:                               |
//|  Jika ATR melonjak tajam dibanding rata-rata (indikasi news),    |
//|  EA pause entry/averaging beberapa candle.                       |
//+------------------------------------------------------------------+
input group "=== Filter & Averaging ATR ==="
input bool     InpUseATRFilter        = true;   // Entry #1 wajib berada pada regime ATR yang sehat
input int      InpATRPeriod           = 14;    // Periode ATR
input int      InpATRAvgBars          = 20;    // Jumlah candle utk hitung rata-rata ATR (baseline)
input double   InpATRRatioMin         = 0.40;   // ATR minimum untuk Entry #1
input double   InpATRRatioMax         = 2.50;   // ATR maksimum untuk Entry #1

input group "=== MODULE 5: FIXED POINT AVERAGING ==="
input double   InpFixedAveragingDistancePoints = 200.0; // Jarak tetap antar entry/grid #2+ (point)
// CATATAN: Grid TIDAK lagi menggunakan ATR. Nilai di atas selalu dipakai sebagai jarak grid.

input group "=== MODULE 12: News / ATR Spike Block ==="
input bool     InpAvoidHighATRSpike   = false;  // Aktifkan pause saat ATR melonjak (indikasi news)
input double   InpATRSpikeRatio       = 3.0;   // ATR skrg >= rata-rata x rasio ini dianggap spike
input int      InpATRSpikePauseBars   = 5;     // Jumlah candle pause setelah spike terdeteksi

//---- state internal modul ini ----
datetime g_atrSpikeLastBarTime = 0;
int      g_atrSpikePauseLeft   = 0;

//+------------------------------------------------------------------+
int ATR_Init()
  {
   ENUM_TIMEFRAMES tf = (InpTF > 0) ? InpTF : PERIOD_M1;
   for(int attempt = 0; attempt < 10; attempt++)
     {
      hATR = iATR(_Symbol, tf, InpATRPeriod);
      if(hATR != INVALID_HANDLE) return INIT_SUCCEEDED;
      Sleep(500);
     }
   return INIT_FAILED;
  }

//+------------------------------------------------------------------+
//| Ambil ATR sekarang + rata-rata baseline                          |
//+------------------------------------------------------------------+
bool GetATRValues(double &atrNow, double &atrAvg)
  {
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int n = CopyBuffer(hATR, 0, 0, InpATRAvgBars, atrBuf);
   if(n <= 0) return false;

   atrNow = atrBuf[0];
   double sum = 0;
   for(int i=0; i<n; i++) sum += atrBuf[i];
   atrAvg = sum / n;
   return true;
  }

//+------------------------------------------------------------------+
string GetATRRegime(double ratio, bool &ok)
  {
   ok = (ratio >= InpATRRatioMin && ratio <= InpATRRatioMax);
   if(ratio > InpATRRatioMax) return "tinggi";
   if(ratio < InpATRRatioMin) return "rendah";
   return "normal";
  }

//+------------------------------------------------------------------+
//| MODULE 5: jarak averaging FIXED POINT                           |
//| Tidak dipengaruhi ATR. Nilai input selalu dipakai.               |
//+------------------------------------------------------------------+
double CalcAveragingDistancePts()
  {
   return MathMax(0.0, InpFixedAveragingDistancePoints);
  }

//+------------------------------------------------------------------+
//| MODULE 12: update & cek status spike-pause. Panggil sekali per   |
//| candle baru di OnTick, sebelum entry/averaging diproses.         |
//+------------------------------------------------------------------+
void UpdateATRSpikePause(double atrNow, double atrAvg)
  {
   if(!InpAvoidHighATRSpike) return;

   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(curBar == g_atrSpikeLastBarTime) return; // sudah diupdate candle ini
   g_atrSpikeLastBarTime = curBar;

   if(g_atrSpikePauseLeft > 0)
     {
      g_atrSpikePauseLeft--;
      return;
     }

   double ratio = (atrAvg > 0) ? atrNow/atrAvg : 1.0;
   if(ratio >= InpATRSpikeRatio)
      g_atrSpikePauseLeft = InpATRSpikePauseBars;
  }

bool IsATRSpikePaused()
  {
   return (InpAvoidHighATRSpike && g_atrSpikePauseLeft > 0);
  }

//+------------------------------------------------------------------+
//---- END ATRManager.mqh ----
//======================================================================
// ---- BEGIN EntryManager.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| EntryManager.mqh                                                 |
//| RoyalQuantum_EA v2.03                                       |
//| FIX v2.03 (temuan #1 dari review v2.02):                         |
//|  Di v2.02, InpUseStochEMA200Filter hanya mengendalikan bagian     |
//|  Stochastic. Kondisi EMA200 (emaDir > ema200 / emaDir < ema200)   |
//|  SELALU wajib terpenuhi walau nama parameter menyiratkan filter   |
//|  EMA200 opsional juga. Sekarang dipecah jadi 2 toggle independen: |
//|  InpUseEMA200Filter dan InpUseStochFilter.                        |
//|                                                                    |
//| MODULE 11 - Trend Strength Filter (EMA Slope):                    |
//|  EMA datar (sideways) sering memicu entry palsu lalu basket       |
//|  langsung averaging di kedua arah bergantian. Ditambahkan filter  |
//|  slope EMA (perubahan EMA per candle, dalam poin) - kalau slope   |
//|  di bawah ambang, EA tidak entry pertama (averaging tetap boleh). |
//+------------------------------------------------------------------+
input group "=== Arah Entry (EMA) ==="
input int      InpEMADirPeriod       = 100;   // Periode EMA untuk menentukan arah open (Buy/Sell)
input int      InpEMA200Period       = 200;   // Periode EMA200 (filter tren)
input bool     InpUseEMA200Filter    = true;   // Entry #1 wajib searah tren EMA200
input bool     InpUseStochFilter     = true;   // Entry #1 wajib mendapat konfirmasi Stochastic

input group "=== Filter Stochastic ==="
input int      InpStochK             = 5;     // Stochastic %K period
input int      InpStochD             = 3;     // Stochastic %D period
input int      InpStochSlowing       = 3;     // Stochastic slowing
input double   InpStochOversold      = 20.0;  // Ambang oversold (Buy butuh Stoch di bawah ini)
input double   InpStochOverbought    = 80.0;  // Ambang overbought (Sell butuh Stoch di atas ini)

input group "=== MODULE 11: Trend Strength Filter (EMA Slope) ==="
input bool     InpUseEMASlope        = true;   // Entry #1 wajib memiliki momentum/slope EMA
input int      InpEMASlopeBars       = 5;     // Jumlah candle ke belakang utk hitung slope
input double   InpEMASlopeMin        = 10.0;  // Slope minimum (poin per InpEMASlopeBars candle)

input group "=== Mode Entry ==="
input bool     InpFollowEMACooldownRules = true;  // Entry #1 selektif; recovery tidak memakai filter ini

input group "=== Jam Trading ==="
input int      InpTradingHourStart   = 0;   // Jam mulai trading (0-23, waktu server MT5)
input int      InpTradingHourEnd     = 24;  // Jam akhir trading (0-23, waktu server MT5)

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES NormalizeTF(int tf, ENUM_TIMEFRAMES defaultTF)
  {
   if(tf == 1 || tf == (int)PERIOD_M1) return PERIOD_M1;
   if(tf == 5 || tf == (int)PERIOD_M5) return PERIOD_M5;
   if(tf == 15 || tf == (int)PERIOD_M15) return PERIOD_M15;
   if(tf == 30 || tf == (int)PERIOD_M30) return PERIOD_M30;
   if(tf == 60 || tf == 16385) return PERIOD_H1;
   if(tf == 240 || tf == 16388) return PERIOD_H4;
   if(tf == 1440 || tf == 16408) return PERIOD_D1;
   if(tf > 0) return (ENUM_TIMEFRAMES)tf;
   return defaultTF;
  }

void MTFEnsureHandles()
  {
   ENUM_TIMEFRAMES confirmTF = NormalizeTF(InpMTFConfirmTF, PERIOD_M5);
   ENUM_TIMEFRAMES trendTF   = NormalizeTF(InpMTFTrendTF, PERIOD_H4);

   if(hMTFDirM5 == INVALID_HANDLE)
      hMTFDirM5   = iMA(_Symbol, confirmTF, InpEMADirPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hMTF200M5 == INVALID_HANDLE)
      hMTF200M5   = iMA(_Symbol, confirmTF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(hMTFStochM5 == INVALID_HANDLE)
      hMTFStochM5 = iStochastic(_Symbol, confirmTF, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);

   if(hMTFDirH4 == INVALID_HANDLE)
      hMTFDirH4   = iMA(_Symbol, trendTF, InpEMADirPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hMTF200H4 == INVALID_HANDLE)
      hMTF200H4   = iMA(_Symbol, trendTF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(hMTFStochH4 == INVALID_HANDLE)
      hMTFStochH4 = iStochastic(_Symbol, trendTF, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
  }

int EntryManager_Init()
  {
   ENUM_TIMEFRAMES entryTF   = NormalizeTF(InpMTFEntryTF, NormalizeTF(InpTF, PERIOD_M1));
   ENUM_TIMEFRAMES confirmTF = NormalizeTF(InpMTFConfirmTF, PERIOD_M5);
   ENUM_TIMEFRAMES trendTF   = NormalizeTF(InpMTFTrendTF, PERIOD_H4);

   datetime dummyTimes[];
   CopyTime(_Symbol, entryTF, 0, 200, dummyTimes);
   CopyTime(_Symbol, confirmTF, 0, 200, dummyTimes);
   CopyTime(_Symbol, trendTF, 0, 200, dummyTimes);

   for(int attempt = 0; attempt < 10; attempt++)
     {
      if(hEMADir == INVALID_HANDLE)
         hEMADir = iMA(_Symbol, entryTF, InpEMADirPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hEMA200 == INVALID_HANDLE)
         hEMA200 = iMA(_Symbol, entryTF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
      if(hStoch == INVALID_HANDLE)
         hStoch  = iStochastic(_Symbol, entryTF, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);

      if(hEMADir != INVALID_HANDLE && hEMA200 != INVALID_HANDLE && hStoch != INVALID_HANDLE)
         break;
      Sleep(500);
     }

   if(hEMADir == INVALID_HANDLE || hEMA200 == INVALID_HANDLE || hStoch == INVALID_HANDLE)
     {
      PrintFormat("EntryManager_Init: Gagal membuat handle M1! err=%d", GetLastError());
      return INIT_FAILED;
     }

   MTFEnsureHandles();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void MTFResetState(RQMTFState &st)
  {
   st.valid=false; st.direction=0; st.close=0; st.emaDir=0; st.ema200=0;
   st.stoch=0; st.slopePts=0; st.emaOK=false; st.slopeOK=false;
  }

bool MTFReadState(ENUM_TIMEFRAMES tf,int hDir,int h200,int hStochHandle,RQMTFState &st)
  {
   MTFResetState(st);
   if(hDir==INVALID_HANDLE || h200==INVALID_HANDLE || hStochHandle==INVALID_HANDLE) return false;

   double d[1], e[1], k[1];
   if(CopyBuffer(hDir,0,0,1,d)<=0) return false;
   if(CopyBuffer(h200,0,0,1,e)<=0) return false;
   if(CopyBuffer(hStochHandle,0,0,1,k)<=0) return false;
   double c=iClose(_Symbol,tf,0);
   if(c<=0) return false;

   st.valid=true;
   st.close=c; st.emaDir=d[0]; st.ema200=e[0]; st.stoch=k[0];
   st.direction=(c>d[0])?1:((c<d[0])?-1:0);
   st.emaOK=(st.direction>0)?(d[0]>=e[0]):((st.direction<0)?(d[0]<=e[0]):false);

   int bars=MathMax(1,InpEMASlopeBars);
   double eb[]; ArraySetAsSeries(eb,true);
   int need=bars+1;
   int n=CopyBuffer(hDir,0,0,need,eb);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(n>=need && point>0)
     {
      double signedSlope=(eb[0]-eb[bars])/point;
      st.slopePts=MathAbs(signedSlope);
      if(st.direction>0) st.slopeOK=(!InpMTFUseSlope || signedSlope>=InpMTFSlopeMin);
      else if(st.direction<0) st.slopeOK=(!InpMTFUseSlope || signedSlope<=-InpMTFSlopeMin);
     }
   else
      st.slopeOK=!InpMTFUseSlope;

   if(!InpMTFUseEMA200) st.emaOK=true;
   return true;
  }

void MTFUpdateStates()
  {
   MTFEnsureHandles();
   MTFResetState(g_mtfM1); MTFResetState(g_mtfM5); MTFResetState(g_mtfH4);
   MTFReadState(NormalizeTF(InpMTFEntryTF, NormalizeTF(InpTF, PERIOD_M1)),hEMADir,hEMA200,hStoch,g_mtfM1);
   MTFReadState(NormalizeTF(InpMTFConfirmTF, PERIOD_M5),hMTFDirM5,hMTF200M5,hMTFStochM5,g_mtfM5);
   MTFReadState(NormalizeTF(InpMTFTrendTF, PERIOD_H4),hMTFDirH4,hMTF200H4,hMTFStochH4,g_mtfH4);
  }

bool MTFDirectionConfirmed(int direction)
  {
   if(!g_webMTFEnabled) return true;
   if(direction!=1 && direction!=-1) return false;
   if(!g_mtfM5.valid || !g_mtfH4.valid) return false;
   bool m5=(g_mtfM5.direction==direction && g_mtfM5.emaOK && g_mtfM5.slopeOK);
   bool h4=(g_mtfH4.direction==direction && g_mtfH4.emaOK && g_mtfH4.slopeOK);
   return m5 && h4;
  }

string MTFDirectionText(const RQMTFState &st)
  {
   if(!st.valid) return "WAIT";
   if(st.direction>0) return "BUY";
   if(st.direction<0) return "SELL";
   return "FLAT";
  }

color MTFDirectionColor(const RQMTFState &st)
  {
   if(!st.valid || st.direction==0) return PANEL_MUTED;
   return st.direction>0?PANEL_GREEN:PANEL_RED;
  }

//+------------------------------------------------------------------+
bool GetEntryIndicatorValues(double &emaDir, double &ema200, double &stochMain, double &closeNow)
  {
   double bufDir[1], buf200[1], bufStoch[1];
   if(CopyBuffer(hEMADir, 0, 0, 1, bufDir)   <= 0) return false;
   if(CopyBuffer(hEMA200, 0, 0, 1, buf200)   <= 0) return false;
   if(CopyBuffer(hStoch,  0, 0, 1, bufStoch) <= 0) return false;

   emaDir    = bufDir[0];
   ema200    = buf200[0];
   stochMain = bufStoch[0];
   closeNow  = iClose(_Symbol, InpTF, 0);
   return true;
  }

//+------------------------------------------------------------------+
bool CheckTradingHours()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(InpTradingHourStart <= InpTradingHourEnd)
      return (t.hour >= InpTradingHourStart && t.hour < InpTradingHourEnd);
   return (t.hour >= InpTradingHourStart || t.hour < InpTradingHourEnd);
  }

//+------------------------------------------------------------------+
//| MODULE 11: slope EMA dalam poin selama InpEMASlopeBars candle.   |
//| Nilai absolut - arah tren tetap ditentukan closeNow vs emaDir.   |
//+------------------------------------------------------------------+
bool GetEMASlopePoints(double &slopePts)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   int need = InpEMASlopeBars + 1;
   int n = CopyBuffer(hEMADir, 0, 0, need, buf);
   if(n < need) return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   slopePts = MathAbs(buf[0] - buf[InpEMASlopeBars]) / point;
   return true;
  }

//+------------------------------------------------------------------+
//| Evaluasi sinyal entry PERTAMA basket untuk suatu arah.           |
//| direction: 1 = Buy, -1 = Sell                                     |
//+------------------------------------------------------------------+
bool CheckEntrySignal(int direction, double emaDir, double ema200, double stochMain, double closeNow)
  {
   // v2.15: Entry #1 = SELECTIVE.
   // Semua filter kualitas diterapkan di sini.
   // Recovery/grid TIDAK memanggil fungsi ini, sehingga grid tetap punya jalur recovery sendiri.
   if(!CheckTradingHours()) return false;

   // Arah dasar harus sesuai EMA cepat/utama.
   bool trendUp   = (closeNow > emaDir);
   bool trendDown = (closeNow < emaDir);

   // Filter tren besar hanya untuk Entry #1.
   if(InpUseEMA200Filter)
     {
      trendUp   = trendUp   && (emaDir > ema200);
      trendDown = trendDown && (emaDir < ema200);
     }

   // Konfirmasi Stochastic yang benar-benar selektif:
   // BUY  = oversold/rebound zone
   // SELL = overbought/reversal zone
   bool stochOKBuy  = (!InpUseStochFilter) || (stochMain <= InpStochOversold);
   bool stochOKSell = (!InpUseStochFilter) || (stochMain >= InpStochOverbought);

   // EMA slope harus SEARAH dengan posisi, bukan sekadar besar.
   if(InpUseEMASlope)
     {
      double slopePts;
      if(!GetEMASlopePoints(slopePts)) return false;

      // GetEMASlopePoints() mengembalikan nilai absolut.
      // Ambil EMA historis untuk menentukan arah slope.
      double emaBuf[];
      ArraySetAsSeries(emaBuf,true);
      int need = InpEMASlopeBars + 1;
      int n = CopyBuffer(hEMADir,0,0,need,emaBuf);
      if(n < need) return false;

      double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      if(point <= 0) return false;

      double signedSlopePts = (emaBuf[0] - emaBuf[InpEMASlopeBars]) / point;

      if(direction == 1)
         trendUp = trendUp && (signedSlopePts >= InpEMASlopeMin);
      else
         trendDown = trendDown && (signedSlopePts <= -InpEMASlopeMin);
     }

   if(direction==1)
      {
       if(!(trendUp && stochOKBuy)) return false;
       return MTFDirectionConfirmed(1);
      }

   if(direction==-1)
      {
       if(!(trendDown && stochOKSell)) return false;
       return MTFDirectionConfirmed(-1);
      }

   return false;
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//---- END EntryManager.mqh ----
//======================================================================
// ---- BEGIN RiskManager.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| RoyalQuantum_EA v2.04                                       |
//| Semua fitur proteksi akun. Ini modul PRIORITAS 1.                |
//|                                                                    |
//| MODULE 1 - Daily Risk Kill Switch (persen equity harian)         |
//| MODULE 2 - Total Drawdown Kill Switch (persen dari baseline modal|
//|            AWAL, disimpan di GlobalVariable supaya tahan restart |
//|            EA/terminal - beda dgn g_dayStartEquity yg direset    |
//|            tiap hari). Butuh RESET MANUAL oleh user.             |
//| MODULE 3 - Basket Cut Loss berbasis PERSEN equity, atau nominal |
//|            tetap seperti v2.02 ($50 fix utk semua ukuran akun).  |
//| MODULE 7 - Margin Safety sebelum entry/averaging.                |
//| MODULE 9 - Spread Filter.                                        |
//| MODULE 10 - Basket Cooldown (menit) setelah kena cut loss.       |
//+------------------------------------------------------------------+
input group "=== MODULE 1: Daily Risk Kill Switch ==="
input bool     InpUseDailyLossLimit   = false;   // Aktifkan batas rugi harian (% equity awal hari)
input double   InpDailyLossPercent    = 20.0;   // Batas rugi harian (%)
input bool     InpUseDailyProfitTarget= false;   // Aktifkan target profit harian (% equity awal hari)
input double   InpDailyProfitTargetPercent = 8.0; // Target profit harian (%)

input group "=== MODULE 2: Total Account Drawdown Kill Switch ==="
input bool     InpUseMaxAccountDD     = true;   // Aktifkan kill switch drawdown total akun
input double   InpMaxAccountDrawdown  = 25.0;   // Batas drawdown total dari modal awal (%)
input bool     InpResetLockOnNewDeposit = false;// true = auto-reset baseline kalau balance naik signifikan (lihat catatan di kode)

input group "=== MODULE 2B: Trailing Peak Drawdown Kill Switch ==="
input bool     InpUseTrailingPeakDD     = false;  // Aktifkan kill switch drawdown dari PEAK equity tertinggi (bukan modal awal)
input double   InpTrailingPeakDDPercent = 15.0;   // Batas drawdown dari peak equity tertinggi (%)

input group "=== MODULE 2C: Auto-Reset Bersyarat Kondisi Pasar ==="
input bool     InpUseConditionalAutoReset   = false; // Aktifkan auto-reset otomatis (hanya berlaku kalau akun sedang locked). OPT-IN, default OFF.
input int      InpAutoResetMinDays          = 7;     // Minimum hari sejak lock sebelum auto-reset mulai dipertimbangkan
input int      InpAutoResetStableBarsNeeded = 30;

input group "=== MODULE 2D: Adaptive DD Controller ==="
input bool     InpUseAdaptiveDD          = true;
input double   InpDDDefensivePercent     = 2.0;
input double   InpDDRecoveryPercent      = 6.0;
input double   InpDDEmergencyPercent     = 12.0;
input double   InpDDHardPercent          = 20.0;
input double   InpDefensiveLotFactor     = 0.50;
input double   InpEmergencyLotFactor     = 0.35;  // Faktor lot saat Adaptive DD Emergency
input int      InpRecoveryCooldownMin    = 15;
input int      InpRecoveryStableBars     = 10;
input bool     InpAdaptiveAutoRearm      = true;
input bool     InpAdaptiveRebaseOnRearm  = true;   // Buat baseline risk-cycle baru saat re-arm; baseline kill-switch tetap utuh
input int      InpHardRearmCooldownMin = 10;   // Cooldown minimum setelah HARD DD sebelum re-arm
input int      InpHardRearmStableBars   = 3;    // Jumlah candle stabil sebelum re-arm

input group "=== MODULE 3: Basket Cut Loss (% Equity) ==="
input bool     InpUseBasketLossPercent= true;   // true = cut-loss basket berbasis % equity | false = pakai nominal $
input double   InpBasketLossPercent   = 7.0;    // Cut loss per basket (% equity saat ini)
input double   InpCutLossPerBasketUSD = 0.0;    // Cut loss per basket nominal USD (otomatis dikonversi ke currency akun, 0=off)

input group "=== MODULE 7: Margin Safety ==="
input bool     InpUseMarginSafety     = true;   // Aktifkan cek margin sebelum entry/averaging
input double   InpMinMarginLevel      = 200.0;  // Margin Level minimum (%) yang wajib tersisa SETELAH entry
input double   InpReserveFreeMarginUSD = 100.0;  // Reserve free margin dalam USD (otomatis dikonversi ke currency akun)

input group "=== MODULE 9: Spread Filter ==="
input bool     InpUseSpreadFilter     = true;   // Aktifkan filter spread
input int      InpMaxSpreadPoints     = 250;    // Spread maksimum (poin) - berlaku utk entry & averaging

input group "=== MODULE 10: Basket Cooldown Recovery ==="
input int      InpBasketCooldownMinutes = 2;   // Jeda (menit) setelah basket kena cut-loss sebelum boleh buka basket baru di arah sama

//---- nama GlobalVariable, unik per symbol+magic supaya tidak bentrok multi-chart ----
string RiskGV_Baseline()  { return StringFormat("RV_%s_%d_baseline_equity", _Symbol, InpMagic); }
string RiskGV_Locked()    { return StringFormat("RV_%s_%d_locked", _Symbol, InpMagic); }
string RiskGV_Peak()      { return StringFormat("RV_%s_%d_peak_equity", _Symbol, InpMagic); }
string RiskGV_LockTime()  { return StringFormat("RV_%s_%d_lock_time", _Symbol, InpMagic); } // MODULE 2C

// Forward declaration: implementasi asli ada di BasketManager.mqh (di-include
// SETELAH RiskManager.mqh). RiskManager perlu memanggil fungsi ini saat
// kill-switch harian/akun terpicu, tapi BasketManager juga perlu memanggil
// fungsi proteksi di RiskManager saat entry/averaging -> saling bergantung,
// jadi dipecah dengan forward declaration di sini (pola standar C/MQL5).
void CloseBasket(int direction);
void CloseAllPositions();
void ResetAccountLock(string source="manual reset");

//+------------------------------------------------------------------+
//| Panggil di OnInit. Baseline modal awal disimpan PERSISTEN via    |
//| GlobalVariable - TIDAK direset tiap hari seperti g_dayStartEquity,|
//| dan TIDAK hilang kalau EA di-restart / terminal reconnect.       |
//| Baseline hanya dibuat SEKALI (first run); setelah itu selalu     |
//| dibaca dari GlobalVariable supaya kill-switch Module 2 konsisten.|
//+------------------------------------------------------------------+
void RiskManager_Init()
  {
   string gvBase = RiskGV_Baseline();
   string gvLock = RiskGV_Locked();

   if(!GlobalVariableCheck(gvBase))
     {
      g_accountBaselineEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(gvBase, g_accountBaselineEquity);
     }
   else
     {
      g_accountBaselineEquity = GlobalVariableGet(gvBase);
     }

   if(GlobalVariableCheck(gvLock))
      g_accountLocked = (GlobalVariableGet(gvLock) > 0.5);
   else
      g_accountLocked = false;

   // v2.11: Strategy Tester memulai risk-cycle baru. GlobalVariable MT5 dapat
   // bertahan antar-run, sehingga baseline/peak/lock lama tidak boleh diwariskan.
   if(MQLInfoInteger(MQL_TESTER) && InpAutoResetLockInTester)
     {
      double testerEq = AccountInfoDouble(ACCOUNT_EQUITY);
      g_accountBaselineEquity = testerEq;
      GlobalVariableSet(gvBase, testerEq);
      g_accountLocked = false;
      g_accountLockReason = "";
      g_accountLockTime = 0;
      GlobalVariableSet(RiskGV_Locked(), 0.0);
      GlobalVariableSet(RiskGV_LockTime(), 0.0);
      g_accountPeakEquity = testerEq;
      GlobalVariableSet(RiskGV_Peak(), testerEq);
      Print("[v2.11 TESTER RESET] Risk baseline/peak/lock reset: ",DoubleToString(testerEq,2));
     }

   if(g_accountLocked)
     {
      g_accountLockReason = "Max Account Drawdown (locked sebelum restart)";
      string gvLockTime = RiskGV_LockTime();
      g_accountLockTime = GlobalVariableCheck(gvLockTime) ? (datetime)GlobalVariableGet(gvLockTime) : TimeCurrent();
     }

   // ---- MODULE 2B: peak equity, PERSISTEN via GlobalVariable, sama pola dgn baseline ----
   string gvPeak = RiskGV_Peak();
   if(!GlobalVariableCheck(gvPeak))
     {
      g_accountPeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(gvPeak, g_accountPeakEquity);
     }
   else
     {
      g_accountPeakEquity = GlobalVariableGet(gvPeak);
     }

   // Opsional: kalau user menambah dana (equity skrg jauh di atas baseline
   // lama) DAN akun belum locked, baseline dinaikkan supaya perhitungan DD
   // Module 2 memakai modal terbaru, bukan modal lama yang sudah kadaluarsa.
   // TIDAK berlaku kalau akun sedang locked - itu tetap butuh reset manual
   // eksplisit (ResetAccountLock) supaya kill-switch tidak bisa "dilewati"
   // hanya dgn menambah dana sedikit.
   if(InpResetLockOnNewDeposit && !g_accountLocked)
     {
      double eqNow = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eqNow > g_accountBaselineEquity * 1.20)
        {
         g_accountBaselineEquity = eqNow;
         GlobalVariableSet(gvBase, g_accountBaselineEquity);
         Print("Baseline drawdown akun dinaikkan mengikuti deposit baru: ", g_accountBaselineEquity);
        }
     }
  }

//+------------------------------------------------------------------+
//| Kunci akun secara PERMANEN (butuh reset manual - lihat           |
//| ResetAccountLock). Status disimpan di GlobalVariable supaya      |
//| bertahan walau EA di-remove/terminal restart/VPS reconnect.      |
//+------------------------------------------------------------------+
void LockAccount(string reason)
  {
   g_accountLocked = true;
   g_accountLockReason = reason;
   g_accountLockTime = TimeCurrent();                    // MODULE 2C: basis hitung cooldown auto-reset
   GlobalVariableSet(RiskGV_Locked(), 1.0);
   GlobalVariableSet(RiskGV_LockTime(), (double)g_accountLockTime);
   Print("=== ACCOUNT LOCKED === Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Reset manual oleh user (mis. dipanggil dari chart event tombol,  |
//| atau dengan menghapus EA lalu set input khusus - implementasi    |
//| sederhana di sini: hapus GlobalVariable via Script terpisah, ATAU|
//| set InpManualUnlock=true sekali lalu OnInit akan clear).         |
//+------------------------------------------------------------------+
void ResetAccountLock(string source="manual reset")
  {
   GlobalVariableDel(RiskGV_Locked());
   GlobalVariableDel(RiskGV_LockTime());
   GlobalVariableSet(RiskGV_Baseline(), AccountInfoDouble(ACCOUNT_EQUITY));
   g_accountLocked = false;
   g_accountLockReason = "";
   g_accountLockTime = 0;
   g_autoResetStableBars = 0;               // MODULE 2C: reset counter, mulai hitung dari nol lagi kalau locked lagi nanti
   g_accountBaselineEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // MODULE 2B: peak equity juga direset mengikuti baseline baru, supaya
   // kill-switch peak-DD tidak langsung terpicu ulang oleh peak lama sebelum
   // reset (yang sudah tidak relevan setelah user mereset akun/keputusan).
   GlobalVariableSet(RiskGV_Peak(), g_accountBaselineEquity);
   g_accountPeakEquity = g_accountBaselineEquity;

   Print("=== ACCOUNT UNLOCKED (", source, ") === Baseline baru: ", g_accountBaselineEquity);
  }

//+------------------------------------------------------------------+
//| Konversi USD -> mata uang akun. Untuk simbol dengan profit       |
//| currency USD (XAUUSD, EURUSD, GBPUSD, dll), kurs dihitung dari   |
//| profit aktual 1 lot untuk gerakan harga +1.00.                   |
//+------------------------------------------------------------------+
double USDToAccountCurrency_Risk(double usd)
  {
   if(usd <= 0.0) return 0.0;

   string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   if(accountCurrency == "USD") return usd;

   string profitCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(profitCurrency != "USD")
     {
      Print("[RiskManager] Profit currency simbol bukan USD (", profitCurrency,
            "). Reserve/nominal USD dipakai apa adanya.");
      return usd;
     }

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(price <= 0.0 || contractSize <= 0.0) return usd;

   double profitAccount = 0.0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price + 1.0, profitAccount))
      return usd;

   double accountPerUSD = MathAbs(profitAccount) / contractSize;
   if(accountPerUSD <= 0.0) return usd;

   return usd * accountPerUSD;
  }

//+------------------------------------------------------------------+
//| MODULE 1 + MODULE 2: dicek tiap tick di OnTick.                  |
//+------------------------------------------------------------------+
string AdaptiveDDModeText()
  {
   switch(g_adaptiveDDMode)
     {
      case DD_MODE_DEFENSIVE: return "DEFENSIVE";
      case DD_MODE_RECOVERY:  return "RECOVERY";
      case DD_MODE_EMERGENCY: return "EMERGENCY";
      case DD_MODE_HARD:      return "HARD";
      default:                return "AGGRESSIVE";
     }
  }

color AdaptiveDDModeColor()
  {
   switch(g_adaptiveDDMode)
     {
      case DD_MODE_DEFENSIVE: return clrGold;
      case DD_MODE_RECOVERY:  return clrDodgerBlue;
      case DD_MODE_EMERGENCY: return clrRed;
      case DD_MODE_HARD:      return clrRed;
      default:                return clrLime;
     }
  }

void AdaptiveDD_Init()
  {
   g_adaptiveDDBaseline=AccountInfoDouble(ACCOUNT_EQUITY);
   g_adaptiveDDMode=DD_MODE_AGGRESSIVE;
   g_adaptiveDDHalted=false;
   g_adaptiveDDLockTime=0;
   g_adaptiveDDStableBars=0;
   g_adaptiveDDLastBar=0;
  }

double AdaptiveDDPercent()
  {
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double base=(g_adaptiveDDBaseline>0.0)?g_adaptiveDDBaseline:g_accountBaselineEquity;
   if(base<=0.0) return 0.0;
   return MathMax(0.0,(base-eq)/base*100.0);
  }

void UpdateAdaptiveDD(double slopePts,bool atrOK)
  {
   if(!InpUseAdaptiveDD)
     {
      g_adaptiveDDMode=DD_MODE_AGGRESSIVE;
      g_adaptiveDDHalted=false;
      return;
     }

   double dd=AdaptiveDDPercent();

   // HARD adalah emergency-stop SEMENTARA, bukan penghentian strategi permanen.
   // v2.15: syarat re-arm sengaja dibuat sederhana: tunggu cooldown singkat +
   // beberapa candle tanpa ATR spike. Filter kualitas Entry #1 tetap berlaku
   // ketika trading kembali, sehingga DD controller tidak ikut mematikan EA
   // selama berhari-hari hanya karena slope pasar berubah.
   if(g_adaptiveDDHalted)
     {
      datetime curBar=iTime(_Symbol,InpTF,0);
      if(curBar!=g_adaptiveDDLastBar)
        {
         g_adaptiveDDLastBar=curBar;
         bool healthy = (!IsATRSpikePaused() && atrOK);
         if(healthy) g_adaptiveDDStableBars++;
         else        g_adaptiveDDStableBars=0;
        }
      int stableNeed=MathMax(1,InpHardRearmStableBars);
      int cooldownMin=MathMax(1,InpHardRearmCooldownMin);
      bool cooldownOK=(g_adaptiveDDLockTime>0 &&
                       TimeCurrent()-g_adaptiveDDLockTime>=cooldownMin*60);
      if(InpAdaptiveAutoRearm && cooldownOK && g_adaptiveDDStableBars>=stableNeed)
        {
         g_adaptiveDDHalted=false;
         g_adaptiveDDStableBars=0;
         if(InpAdaptiveRebaseOnRearm)
            g_adaptiveDDBaseline=AccountInfoDouble(ACCOUNT_EQUITY);
         g_adaptiveDDMode=DD_MODE_RECOVERY;
         Print(StringFormat("=== ADAPTIVE DD RE-ARM v2.15 === pause %d min + %d stable bars selesai; trading resumed. New cycle baseline %.2f",
                            cooldownMin,stableNeed,g_adaptiveDDBaseline));
        }
      else
        {
         g_adaptiveDDMode=DD_MODE_HARD;
         return;
        }
     }

   if(dd>=InpDDHardPercent)
     {
      CloseAllPositions();
      g_adaptiveDDHalted=true;
      g_adaptiveDDLockTime=TimeCurrent();
      g_adaptiveDDStableBars=0;
      g_adaptiveDDLastBar=iTime(_Symbol,InpTF,0);
      g_adaptiveDDMode=DD_MODE_HARD;
      Print(StringFormat("=== ADAPTIVE DD HARD v2.15 === DD %.2f%% >= %.2f%%. Temporary pause; auto re-arm active.",dd,InpDDHardPercent));
      return;
     }

   if(dd>=InpDDEmergencyPercent)      g_adaptiveDDMode=DD_MODE_EMERGENCY;
   else if(dd>=InpDDRecoveryPercent)  g_adaptiveDDMode=DD_MODE_RECOVERY;
   else if(dd>=InpDDDefensivePercent) g_adaptiveDDMode=DD_MODE_DEFENSIVE;
   else                               g_adaptiveDDMode=DD_MODE_AGGRESSIVE;
  }

bool AdaptiveDDBlocksNewBasket()
  {
   // v2.20 FIX: EMERGENCY tidak mengunci basket baru.
   // Emergency hanya mengecilkan lot melalui AdaptiveLotFactor().
   // Hanya HARD yang benar-benar menghentikan basket baru.
   return InpUseAdaptiveDD && (g_adaptiveDDMode==DD_MODE_HARD);
  }

bool AdaptiveDDBlocksAveraging()
  {
   // Recovery/emergency tetap boleh recovery dengan lot yang direduksi.
   return InpUseAdaptiveDD && (g_adaptiveDDMode==DD_MODE_HARD);
  }

double AdaptiveLotFactor()
  {
   if(!InpUseAdaptiveDD) return 1.0;
   if(g_adaptiveDDMode==DD_MODE_EMERGENCY)
      return MathMax(0.05,MathMin(1.0,InpEmergencyLotFactor));
   if(g_adaptiveDDMode==DD_MODE_DEFENSIVE || g_adaptiveDDMode==DD_MODE_RECOVERY)
      return MathMax(0.05,MathMin(1.0,InpDefensiveLotFactor));
   return 1.0;
  }

string GetHaltReason()
  {
   if(g_accountLocked)      return "ACCOUNT LOCK";
   if(g_dailyLossHit)       return "DAILY LOSS";
   if(g_dailyTargetHit)     return "DAILY TARGET";
   if(g_adaptiveDDHalted)   return "ADAPTIVE DD HARD";
   return "NONE";
  }

void CheckDailyLimits()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // ---- Module 1: Daily target / daily loss (persen dari equity AWAL HARI) ----
   if(!g_dailyTargetHit && InpUseDailyProfitTarget && g_dayStartEquity > 0)
     {
      double targetUSD = g_dayStartEquity * (InpDailyProfitTargetPercent/100.0);
      if(g_dailyProfit >= targetUSD)
        {
         CloseAllPositions();
         g_dailyTargetHit = true;
        }
     }

   if(!g_dailyLossHit && InpUseDailyLossLimit && g_dayStartEquity > 0)
     {
      double lossUSD = g_dayStartEquity * (InpDailyLossPercent/100.0);
      if(g_dailyProfit <= -MathAbs(lossUSD))
        {
         CloseAllPositions();
         g_dailyLossHit = true;
        }
     }

   // ---- Module 2: Total account drawdown kill switch (PERMANEN, manual reset) ----
   if(InpUseMaxAccountDD && !g_accountLocked && g_accountBaselineEquity > 0)
     {
      double ddPercent = (g_accountBaselineEquity - equity) / g_accountBaselineEquity * 100.0;
      if(ddPercent >= InpMaxAccountDrawdown)
        {
         CloseAllPositions();
         LockAccount(StringFormat("Max Drawdown %.1f%% (equity %.2f dari baseline %.2f)",
                                   InpMaxAccountDrawdown, equity, g_accountBaselineEquity));
        }
     }

   // ---- Module 2B: Trailing Peak Drawdown Kill Switch (PERMANEN, manual reset) ----
   // Independen dari Module 2: dihitung dari PEAK equity tertinggi yang pernah
   // dicapai akun (naik terus mengikuti rekor baru), bukan dari modal awal.
   // Siapa yang tersentuh duluan (Module 2 atau 2B) yang mengunci akun.
   if(InpUseTrailingPeakDD && !g_accountLocked)
     {
      if(equity > g_accountPeakEquity)
        {
         g_accountPeakEquity = equity;
         GlobalVariableSet(RiskGV_Peak(), g_accountPeakEquity);
        }

      if(g_accountPeakEquity > 0)
        {
         double peakDDPercent = (g_accountPeakEquity - equity) / g_accountPeakEquity * 100.0;
         if(peakDDPercent >= InpTrailingPeakDDPercent)
           {
            CloseAllPositions();
            LockAccount(StringFormat("Trailing Peak Drawdown %.1f%% (equity %.2f dari peak %.2f)",
                                      InpTrailingPeakDDPercent, equity, g_accountPeakEquity));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| MODULE 3: cut loss per basket, berbasis % equity ATAU nominal $. |
//| Mengembalikan true jika basket harus ditutup.                    |
//+------------------------------------------------------------------+
bool CheckBasketCutLoss(double floatingProfit, double totalLots)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double bufferMoney = 0;
   if(tickSize > 0)
      bufferMoney = (InpCloseBufferPoints*point/tickSize) * tickValue * totalLots;

   double cutLossAccount = 0;
   if(InpUseBasketLossPercent)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      cutLossAccount = equity * (InpBasketLossPercent/100.0);
     }
   else
     {
      if(InpCutLossPerBasketUSD <= 0) return false; // fitur off
      cutLossAccount = USDToAccountCurrency_Risk(InpCutLossPerBasketUSD);
     }

   if(cutLossAccount <= 0) return false;
   return (floatingProfit <= -(MathAbs(cutLossAccount) - bufferMoney));
  }

//+------------------------------------------------------------------+
//| MODULE 7: pastikan margin cukup SEBELUM order dikirim (entry     |
//| pertama maupun averaging). Menghitung margin proyeksi order baru |
//| + posisi berjalan, lalu cek terhadap ambang minimum.             |
//+------------------------------------------------------------------+
bool IsMarginSafeForOrder(ENUM_ORDER_TYPE orderType, double lot, double price)
  {
   if(!InpUseMarginSafety) return true;

   double marginRequired = 0;
   if(!OrderCalcMargin(orderType, _Symbol, lot, price, marginRequired))
     {
      Print("OrderCalcMargin gagal, order ditahan demi keamanan.");
      return false;
     }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double usedMargin  = AccountInfoDouble(ACCOUNT_MARGIN);

   // free margin sisa setelah order ini dikirim
   double projectedFreeMargin = freeMargin - marginRequired;
   if(projectedFreeMargin < USDToAccountCurrency_Risk(InpReserveFreeMarginUSD))
      return false;

   // margin level proyeksi setelah order = equity / (used margin + margin baru) * 100
   double projectedUsedMargin = usedMargin + marginRequired;
   if(projectedUsedMargin <= 0) return true; // tidak ada exposure, aman
   double projectedMarginLevel = equity / projectedUsedMargin * 100.0;
   if(projectedMarginLevel < InpMinMarginLevel)
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| MODULE 9: spread filter, berlaku utk entry pertama & averaging.  |
//+------------------------------------------------------------------+
bool IsSpreadOK()
  {
   if(!InpUseSpreadFilter) return true;
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPts <= InpMaxSpreadPoints);
  }

//+------------------------------------------------------------------+
//| MODULE 10: cek & set cooldown menit-based setelah basket ditutup |
//| karena cut-loss (dipanggil dari BasketManager.CloseBasket).      |
//+------------------------------------------------------------------+
void SetBasketCooldown(int direction)
  {
   datetime until = TimeCurrent() + InpBasketCooldownMinutes*60;
   if(direction==1)  g_buyCooldownUntil  = until;
   else              g_sellCooldownUntil = until;
  }

bool IsBasketCooldownActive(int direction)
  {
   datetime now = TimeCurrent();
   if(direction==1)  return (now < g_buyCooldownUntil);
   else              return (now < g_sellCooldownUntil);
  }

//+------------------------------------------------------------------+
//| MODULE 2C: Auto-Reset Bersyarat Kondisi Pasar.                   |
//| Dipanggil sekali per tick dari OnTick HANYA saat g_accountLocked |
//| && InpUseConditionalAutoReset. Hitung sekali per candle baru     |
//| (bukan per tick) supaya "jumlah candle stabil" akurat.           |
//|                                                                    |
//| Syarat reset otomatis (SEMUA harus terpenuhi):                   |
//|  (1) Sudah lewat InpAutoResetMinDays sejak lock terjadi.          |
//|  (2) Kondisi pasar "sehat" (ATR dlm rentang normal & EMA slope    |
//|      cukup kuat) bertahan InpAutoResetStableBarsNeeded candle    |
//|      BERTURUT-TURUT - putus sekali, hitung ulang dari nol.       |
//| atrOK & slopePts dihitung oleh caller (OnTick) memakai fungsi    |
//| yang sama dgn filter entry normal (GetATRRegime/GetEMASlopePoints)|
//| supaya definisi "sehat" konsisten dgn logic entry, bukan ambang   |
//| terpisah yang bisa saling bertentangan.                          |
//+------------------------------------------------------------------+
void CheckConditionalAutoReset(bool atrOK, double slopePts)
  {
   if(!g_accountLocked) { g_autoResetStableBars = 0; return; }

   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(curBar == g_autoResetLastBarTime) return; // sudah dihitung candle ini
   g_autoResetLastBarTime = curBar;

   // ---- syarat 1: minimum hari sejak lock ----
   if(g_accountLockTime == 0 || TimeCurrent() - g_accountLockTime < InpAutoResetMinDays*86400)
     {
      g_autoResetStableBars = 0; // belum masuk periode evaluasi, jangan numpuk progress palsu
      return;
     }

   // ---- syarat 2: kondisi pasar sehat, harus konsisten berturut-turut ----
   bool marketHealthy = atrOK && (slopePts >= InpEMASlopeMin);

   if(marketHealthy)
      g_autoResetStableBars++;
   else
      g_autoResetStableBars = 0; // putus sekali pun, hitung ulang dari nol - hindari reset saat kondisi masih labil

   if(g_autoResetStableBars >= InpAutoResetStableBarsNeeded)
     {
      double lockedDays = (double)(TimeCurrent() - g_accountLockTime) / 86400.0;
      Print("=== MODULE 2C: AUTO-RESET === Locked ", DoubleToString(lockedDays,1),
            " hari, kondisi pasar stabil ", g_autoResetStableBars, " candle berturut-turut. Reset otomatis dieksekusi.");
      ResetAccountLock("auto-reset Module 2C - kondisi pasar stabil");
     }
  }

//+------------------------------------------------------------------+
//---- END RiskManager.mqh ----
//======================================================================
// ---- BEGIN BasketManager.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| BasketManager.mqh                                                |
//| RoyalQuantum_EA v2.03                                       |
//| MODULE 4 - Exposure Cap: total lot & jumlah order per basket     |
//| dibatasi. Ini penyebab utama Stop Out di BT1/BT2 (basket bisa    |
//| tumbuh >6 lot tanpa batas). Dicek LANGSUNG di titik averaging,   |
//| bukan cuma sebagai parameter berdiri sendiri.                    |
//|                                                                    |
//| MODULE 6 - Hard Stop Loss Broker: setiap order (entry & average) |
//| sekarang WAJIB membawa SL riil di sisi broker (ATR x multiplier),|
//| di-clamp ke SYMBOL_TRADE_STOPS_LEVEL/freeze level supaya tidak    |
//| ditolak broker ("Invalid stops").                                 |
//|                                                                    |
//| Temuan review v2.02 lain yang diperbaiki di sini:                 |
//|  - Hasil trade.Buy()/trade.Sell() sekarang selalu dicek & di-log  |
//|    kalau gagal (requote/invalid volume/not enough money dsb),     |
//|    supaya kegagalan averaging saat kondisi kritis tidak diam saja.|
//|  - Averaging tambahan: minimum jeda waktu antar-averaging (detik) |
//|    supaya tidak numpuk banyak entry dalam candle M1 yang sama saat|
//|    harga XAUUSD spike tajam.                                      |
//+------------------------------------------------------------------+
input group "=== Basket / Averaging ==="
input bool     InpAveragingWaitClose  = false; // true = averaging tunggu candle close dulu | false = langsung
input int      InpMaxAveragingCycle   = 5;     // Max averaging per cycle (lot reset setelah basket ditutup)
input int      InpCooldownCandles     = 1;     // Jumlah candle tunggu setelah basket ditutup NORMAL sebelum boleh open lagi
input int      InpMinSecondsBetweenAvg= 2;     // Jeda minimum (detik) antar-averaging, anti burst saat spike
input bool     InpAllowBuySellTogether= false; // true = Buy & Sell boleh bareng | false = cuma 1 arah dalam satu waktu

input group "=== MODULE 4: Exposure Cap ==="
input double   InpMaxTotalLotBasket   = 0.50;  // Total lot maksimum per basket (5-level recovery grid)
input int      InpMaxOpenOrdersBasket = 5;     // Jumlah order maksimum per basket

input group "=== MODULE 6: Hard Stop Loss Broker ==="
input bool     InpUseBrokerSL         = false;  // Wajibkan SL riil di broker utk setiap order
input double   InpBrokerSL_ATR        = 2.5;   // SL = ATR(14) x multiplier
input double   InpInitialSLBeyondGridBufferPoints = 25.0; // Buffer agar SL Entry #1 berada sedikit di luar grid pertama

input group "=== MODULE 6B: Basket SL / Martingale Grid Mode ==="
input bool     InpGridRecoveryEnabled       = true;  // Entry #1 wajib diberi kesempatan mencapai grid #2
input bool     InpRecoveryBypassATRSpike       = true;  // Grid tidak diblokir oleh ATR spike/news pause
input bool     InpRecoveryBypassSpreadFilter   = false; // Tetap hormati spread saat averaging
input bool     InpRecoveryBypassAdaptiveDD     = true;  // Recovery tetap boleh sampai HARD DD
input bool     InpRemoveSLWhenAveraging      = true;  // Saat averaging pertama dipicu, SL posisi lama dihapus
input bool     InpAveragingOrdersNoSL         = true;  // Semua order averaging #2+ dibuka TANPA SL individual
input bool     InpActivateBrokerSLOnTrailing  = true;  // Setelah basket trailing aktif, pasang SL broker mengikuti basket
input bool     InpCloseWholeBasketOnTrailSL   = true;  // Jika satu SL trailing broker tersentuh, tutup sisa basket ini

input group "=== GRID TREND FOLLOW HIGHER TF ==="
input bool     InpGridFollowHigherTF       = true;   // Sebelum grid berikutnya, cek konfirmasi trend M5 + H4
input bool     InpGridReverseOnTrendFlip    = true;   // Jika trend besar berbalik, tutup basket lama lalu ikut arah baru
input bool     InpGridReverseUseBaseLot     = true;   // Basket hasil flip dimulai dari base lot, bukan melanjutkan lot martingale lama

//+------------------------------------------------------------------+
//| Info basket: jumlah posisi, avg price, total lot, floating, dll  |
//+------------------------------------------------------------------+
void GetBasketInfo(int direction, int &count, double &avgPrice, double &totalLots,
                    double &floatingProfit, double &lastOpenPrice, double &lastLot,
                    datetime &lastOpenTime)
  {
   count = 0; avgPrice = 0; totalLots = 0; floatingProfit = 0;
   lastOpenPrice = 0; lastLot = 0; lastOpenTime = 0;
   double sumPriceLot = 0;

   for(int i=0; i<PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(direction==1  && type!=POSITION_TYPE_BUY)  continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;

      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot  = (datetime)PositionGetInteger(POSITION_TIME);

      count++;
      totalLots      += vol;
      sumPriceLot    += price*vol;
      floatingProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(ot > lastOpenTime)
        {
         lastOpenTime  = ot;
         lastOpenPrice = price;
         lastLot       = vol;
        }
     }
   if(totalLots > 0) avgPrice = sumPriceLot/totalLots;
  }

//+------------------------------------------------------------------+
//| Tutup semua posisi 1 arah. Dipanggil oleh exit normal (trailing/ |
//| TP/cut-loss) MAUPUN oleh RiskManager (daily/account kill switch).|
//| reasonIsCutLoss=true akan memicu cooldown menit-based Module 10. |
//+------------------------------------------------------------------+
void CloseBasketEx(int direction, bool reasonIsCutLoss)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(direction==1  && type==POSITION_TYPE_BUY)
        {
         if(!trade.PositionClose(ticket))
            Print("Gagal close posisi BUY #", ticket, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
        }
      if(direction==-1 && type==POSITION_TYPE_SELL)
        {
         if(!trade.PositionClose(ticket))
            Print("Gagal close posisi SELL #", ticket, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
        }
     }

   if(direction==1)
     {
      g_buyCooldownLeft = InpCooldownCandles;
      g_buyPeakPts = -1e9;
     }
   else
     {
      g_sellCooldownLeft = InpCooldownCandles;
      g_sellPeakPts = -1e9;
     }

   if(reasonIsCutLoss)
      SetBasketCooldown(direction);
  }

void CloseBasket(int direction) { CloseBasketEx(direction, false); }

void CloseAllPositions()
  {
   CloseBasketEx(1, false);
   CloseBasketEx(-1, false);
  }

//+------------------------------------------------------------------+
//| Update cooldown candle-based sekali per candle baru               |
//+------------------------------------------------------------------+
void UpdateCooldownOnNewBar()
  {
   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(curBar != g_lastBarTimeSeenBuyCD)
     {
      if(g_buyCooldownLeft > 0) g_buyCooldownLeft--;
      g_lastBarTimeSeenBuyCD = curBar;
     }
   if(curBar != g_lastBarTimeSeenSellCD)
     {
      if(g_sellCooldownLeft > 0) g_sellCooldownLeft--;
      g_lastBarTimeSeenSellCD = curBar;
     }
  }

//+------------------------------------------------------------------+
//| MODULE 6: hitung SL harga (bukan poin) dari ATR x multiplier,    |
//| di-clamp ke stop level / freeze level minimum broker.            |
//+------------------------------------------------------------------+
double CalcBrokerSLPrice(int direction, double entryPrice, double atrNowPrice)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevelPts  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevelPts= SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long minPtsLong = MathMax(stopLevelPts, freezeLevelPts);
   double minPts = (double)minPtsLong;

   double slDistPts = (atrNowPrice/point) * InpBrokerSL_ATR;
   if(slDistPts < (double)minPts + 10.0) slDistPts = (double)minPts + 10.0; // +buffer kecil di atas minimum broker

   // ENTRY #1 harus punya kesempatan mencapai GRID sebelum broker SL menutupnya.
   // Setelah averaging #2 berhasil, SL Entry #1 akan dihapus dan seluruh basket
   // dikelola oleh basket cut-loss / basket trailing.
   double firstGridPts = CalcAveragingDistancePts();
   if(firstGridPts > 0.0)
      slDistPts = MathMax(slDistPts, firstGridPts + InpInitialSLBeyondGridBufferPoints);

   double slDist = slDistPts * point;
   if(direction==1)  return NormalizeDouble(entryPrice - slDist, _Digits);
   else              return NormalizeDouble(entryPrice + slDist, _Digits);
  }

//+------------------------------------------------------------------+
//| Kirim order Buy/Sell dengan SL opsional (Module 6), lalu cek     |
//| hasilnya (temuan #6 review v2.02: hasil order dulu tidak dicek). |
//+------------------------------------------------------------------+
bool SendBasketOrder(int direction, double lot, double atrNowPrice, bool useSL=true)
  {
   bool ok;
   double price, sl = 0;

   if(direction==1)
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(useSL && InpUseBrokerSL) sl = CalcBrokerSLPrice(1, price, atrNowPrice);
      ok = trade.Buy(lot, _Symbol, price, sl, 0, InpOrderComment);
     }
   else
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(useSL && InpUseBrokerSL) sl = CalcBrokerSLPrice(-1, price, atrNowPrice);
      ok = trade.Sell(lot, _Symbol, price, sl, 0, InpOrderComment);
     }

   if(!ok)
     {
      Print("[v2.15 ORDER FAIL] ", (direction==1?"BUY":"SELL"), " GAGAL. lot=", lot,
            " SL=",DoubleToString(sl,_Digits),
            " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
     }

   SetEntryBlockReason("NONE");
   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(direction==1) { g_buyLastAvgBarTime = curBar; g_buyLastAvgTime = TimeCurrent(); }
   else             { g_sellLastAvgBarTime = curBar; g_sellLastAvgTime = TimeCurrent(); }
   return true;
  }

void RemoveBasketIndividualSL(int direction)
  {
   if(!InpRemoveSLWhenAveraging) return;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      double oldSL=PositionGetDouble(POSITION_SL);
      double oldTP=PositionGetDouble(POSITION_TP);
      if(oldSL==0.0) continue;
      ResetLastError();
      if(!trade.PositionModify(ticket,0.0,oldTP))
         Print("Gagal hapus SL basket ",(direction==1?"BUY":"SELL")," #",ticket,
               " ret=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription()," err=",GetLastError());
     }
  }

void EnforceBasketNoSL(int direction)
  {
   if(!InpRemoveSLWhenAveraging) return;
   int count; double avgPrice,totalLots,floatingProfit,lastOpenPrice,lastLot; datetime lastOpenTime;
   GetBasketInfo(direction,count,avgPrice,totalLots,floatingProfit,lastOpenPrice,lastLot,lastOpenTime);
   if(count>=2) RemoveBasketIndividualSL(direction);
  }

double BrokerMinSLDistancePrice()
  {
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   long stopLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long minPts=MathMax(stopLevel,freezeLevel);
   return (double)(minPts+2)*point;
  }

void ApplyBasketTrailingSL(int direction,double avgPrice,double trailExitPts)
  {
   if(!InpActivateBrokerSLOnTrailing || trailExitPts<=0.0) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double minDist=BrokerMinSLDistancePrice();
   double basketSL;

   if(direction==1)
     {
      basketSL=NormalizeDouble(avgPrice+trailExitPts*point,_Digits);
      double maxAllowed=NormalizeDouble(bid-minDist,_Digits);
      if(basketSL>maxAllowed) basketSL=maxAllowed;
      if(basketSL<=0) return;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) continue;
         double oldSL=PositionGetDouble(POSITION_SL);
         if(oldSL!=0.0 && oldSL>=basketSL) continue;
         if(!trade.PositionModify(ticket,basketSL,0.0))
            Print("Gagal set basket trailing SL BUY #",ticket," SL=",DoubleToString(basketSL,_Digits),
                  " ret=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
        }
     }
   else
     {
      basketSL=NormalizeDouble(avgPrice-trailExitPts*point,_Digits);
      double minAllowed=NormalizeDouble(ask+minDist,_Digits);
      if(basketSL<minAllowed) basketSL=minAllowed;
      if(basketSL<=0) return;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) continue;
         double oldSL=PositionGetDouble(POSITION_SL);
         if(oldSL!=0.0 && oldSL<=basketSL) continue;
         if(!trade.PositionModify(ticket,basketSL,0.0))
            Print("Gagal set basket trailing SL SELL #",ticket," SL=",DoubleToString(basketSL,_Digits),
                  " ret=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
        }
     }
  }

bool IsAveragingDDBlocked(double floatingProfit)
  {
   if(!InpReduceAveragingOnDD) return false;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0) return false;
   double ddPct=(-floatingProfit/equity)*100.0;
   return (floatingProfit<0.0 && ddPct>=InpAveragingDDLimitPct);
  }

//+------------------------------------------------------------------+
//| v2.15 diagnostics: simpan alasan filter terakhir agar tester/live|
//| tidak terlihat "mati" tanpa penjelasan.                         |
//+------------------------------------------------------------------+
void SetEntryBlockReason(string reason)
  {
   if(StringFind(reason, "BUY:") == 0)
     {
      if(reason != g_buyBlockReason)
        {
         g_buyBlockReason = reason;
         g_entryBlockReason = reason;
         Print("[v2.20 ENTRY BLOCK] ", reason);
        }
     }
   else if(StringFind(reason, "SELL:") == 0)
     {
      if(reason != g_sellBlockReason)
        {
         g_sellBlockReason = reason;
         g_entryBlockReason = reason;
         Print("[v2.20 ENTRY BLOCK] ", reason);
        }
     }
   else
     {
      if(reason != g_otherBlockReason)
        {
         g_otherBlockReason = reason;
         g_entryBlockReason = reason;
         Print("[v2.20 ENTRY BLOCK] ", reason);
        }
     }
  }

//+------------------------------------------------------------------+
//| GRID TREND FOLLOW: baca ulang MTF tepat saat averaging dibutuhkan. |
//| Menggunakan konfirmasi yang sama dengan dashboard: M5 + H4.      |
//| return = currentDirection jika trend masih searah                 |
//|       = -currentDirection jika trend besar sudah berbalik          |
//|       = 0 jika MTF belum jelas / belum terkonfirmasi               |
//+------------------------------------------------------------------+
int GetGridHigherTFDirection(int currentDirection)
  {
   if(!InpGridFollowHigherTF || !g_webMTFEnabled)
      return currentDirection;

   // Pastikan state MTF benar-benar fresh sebelum memutuskan grid.
   MTFUpdateStates();

   if(MTFDirectionConfirmed(currentDirection))
      return currentDirection;

   if(MTFDirectionConfirmed(-currentDirection))
      return -currentDirection;

   return 0;
  }

//+------------------------------------------------------------------+
//| Saat trend higher-TF berbalik, basket lama ditutup dan basket baru |
//| dibuka mengikuti arah trend baru. Ini mencegah grid terus          |
//| menambah posisi melawan M5/H4.                                     |
//+------------------------------------------------------------------+
bool ReverseBasketToHigherTF(int oldDirection, int newDirection,
                             int oldCount, double oldLastLot, double atrNow)
  {
   if(!InpGridReverseOnTrendFlip)
      return false;

   if(newDirection!=1 && newDirection!=-1)
      return false;

   // Jangan membalik kalau jam trading tidak aktif.
   if(!CheckTradingHours())
     {
      SetEntryBlockReason(newDirection==1?"GRID FLIP: OUT OF HOURS":"GRID FLIP: OUT OF HOURS");
      return false;
     }

   Print(StringFormat("[v2.35 GRID FLIP] Higher TF berubah: %s -> %s.\n"
                      "Basket lama ditutup, lalu EA mengikuti arah trend baru.",
                      oldDirection==1?"BUY":"SELL",
                      newDirection==1?"BUY":"SELL"));

   // Tutup basket lama lebih dulu agar tidak membuat hedge/dua arah
   // ketika InpAllowBuySellTogether=false.
   CloseBasketEx(oldDirection, false);

   int remainCount;
   double a,b,c,d,e;
   datetime f;
   GetBasketInfo(oldDirection, remainCount, a, b, c, d, e, f);
   if(remainCount > 0)
     {
      SetEntryBlockReason(newDirection==1?"GRID FLIP: CLOSE OLD BUY FAIL":"GRID FLIP: CLOSE OLD SELL FAIL");
      Print("[v2.35 GRID FLIP] Basket lama belum tertutup seluruhnya. Reverse dibatalkan.");
      return false;
     }

   // Setelah flip, mulai basket baru dari base lot secara default.
   // Opsi carry-grid tetap tersedia bila user memang menginginkannya.
   double lot = 0.0;
   if(InpGridReverseUseBaseLot)
      lot = NormalizeLot(CalcNextLot(0, 0) * AdaptiveLotFactor());
   else
      lot = NormalizeLot(CalcNextLot(oldCount, oldLastLot) * AdaptiveLotFactor());

   if(lot <= 0.0)
     {
      SetEntryBlockReason(newDirection==1?"GRID FLIP: INVALID LOT BUY":"GRID FLIP: INVALID LOT SELL");
      return false;
     }

   double price = (newDirection==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ENUM_ORDER_TYPE ot = (newDirection==1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!IsMarginSafeForOrder(ot, lot, price))
     {
      SetEntryBlockReason(newDirection==1?"GRID FLIP: BUY MARGIN":"GRID FLIP: SELL MARGIN");
      return false;
     }

   // Flip ini dianggap basket baru #1, sehingga broker SL dipasang bila
   // InpUseBrokerSL=true. Exit/trailing akan melihatnya sebagai count=1.
   bool ok = SendBasketOrder(newDirection, lot, atrNow, true);
   if(ok)
     {
      SetEntryBlockReason(newDirection==1?"GRID FLIP -> BUY":"GRID FLIP -> SELL");
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Buka posisi awal ATAU averaging pada basket tertentu.            |
//| direction: 1 = Buy, -1 = Sell                                     |
//+------------------------------------------------------------------+
void ProcessBasketEntry(int direction, double emaDir, double ema200, double stochMain,
                         bool atrOK, double closeNow, double atrNow)
  {
   int count; double avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot;
   datetime lastOpenTime;
   GetBasketInfo(direction, count, avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot, lastOpenTime);

   // v2.15: filter entry pertama secara terpisah dari recovery.
   // ATR spike/cooldown tidak boleh mematikan basket yang sedang recovery.
   if(count == 0)
     {
      if(IsATRSpikePaused()) { SetEntryBlockReason(direction==1?"BUY: ATR SPIKE PAUSE":"SELL: ATR SPIKE PAUSE"); return; }
      if(!IsSpreadOK()) { SetEntryBlockReason(direction==1?"BUY: SPREAD FILTER":"SELL: SPREAD FILTER"); return; }
      if(IsBasketCooldownActive(direction)) { SetEntryBlockReason(direction==1?"BUY: BASKET COOLDOWN":"SELL: BASKET COOLDOWN"); return; }
     }
   else
     {
      if(!InpRecoveryBypassSpreadFilter && !IsSpreadOK())
        { SetEntryBlockReason(direction==1?"BUY: RECOVERY SPREAD":"SELL: RECOVERY SPREAD"); return; }
      if(!InpRecoveryBypassATRSpike && IsATRSpikePaused())
        { SetEntryBlockReason(direction==1?"BUY: RECOVERY ATR SPIKE":"SELL: RECOVERY ATR SPIKE"); return; }
     }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // ---- ENTRY PERTAMA BASKET ----
   if(count == 0)
     {
      if(AdaptiveDDBlocksNewBasket()) { SetEntryBlockReason(direction==1?"BUY: ADAPTIVE DD NEW BASKET":"SELL: ADAPTIVE DD NEW BASKET"); return; }
      int otherCount; double a,b,c,d,e; datetime f;
      GetBasketInfo(-direction, otherCount, a, b, c, d, e, f);
      if(otherCount > 0 && !InpAllowBuySellTogether) { SetEntryBlockReason(direction==1?"BUY: OPPOSITE BASKET OPEN":"SELL: OPPOSITE BASKET OPEN"); return; }

      if(InpFollowEMACooldownRules)
        {
         if(direction==1  && g_buyCooldownLeft  > 0) { SetEntryBlockReason("BUY: EMA COOLDOWN"); return; }
         if(direction==-1 && g_sellCooldownLeft > 0) { SetEntryBlockReason("SELL: EMA COOLDOWN"); return; }
         if(InpUseATRFilter && !atrOK) { SetEntryBlockReason(direction==1?"BUY: ATR FILTER":"SELL: ATR FILTER"); return; }
        }

      if(!CheckEntrySignal(direction, emaDir, ema200, stochMain, closeNow)) { SetEntryBlockReason(direction==1?"BUY: SIGNAL FILTER":"SELL: SIGNAL FILTER"); return; }

      double lot = NormalizeLot(CalcNextLot(0, 0) * AdaptiveLotFactor());
      double price = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ENUM_ORDER_TYPE ot = (direction==1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!IsMarginSafeForOrder(ot, lot, price)) { SetEntryBlockReason(direction==1?"BUY: MARGIN SAFETY":"SELL: MARGIN SAFETY"); return; } // Module 7

      SendBasketOrder(direction, lot, atrNow, true);
      return;
     }

   // ---- AVERAGING ----
   // Adaptive DD tetap menjadi hard safety. Floating-DD blocker lama bersifat opsional
   // dan default OFF supaya basket benar-benar bisa melakukan recovery grid.
   if(!InpRecoveryBypassAdaptiveDD && AdaptiveDDBlocksAveraging())
     { SetEntryBlockReason(direction==1?"BUY: ADAPTIVE DD AVERAGING":"SELL: ADAPTIVE DD AVERAGING"); return; }
   if(IsAveragingDDBlocked(floatingProfit)) { SetEntryBlockReason(direction==1?"BUY: FLOATING DD BLOCK":"SELL: FLOATING DD BLOCK"); return; }
   if(count >= InpMaxAveragingCycle) { SetEntryBlockReason(direction==1?"BUY: MAX AVG CYCLE":"SELL: MAX AVG CYCLE"); return; }
   if(totalLots >= InpMaxTotalLotBasket) { SetEntryBlockReason(direction==1?"BUY: MAX BASKET LOT":"SELL: MAX BASKET LOT"); return; }      // Module 4 (lot cap)
   if(count >= InpMaxOpenOrdersBasket) { SetEntryBlockReason(direction==1?"BUY: MAX OPEN ORDERS":"SELL: MAX OPEN ORDERS"); return; }         // Module 4 (order count cap)

   if(InpAveragingWaitClose)
     {
      datetime curBar = iTime(_Symbol, InpTF, 0);
      datetime lastAvgBar = (direction==1) ? g_buyLastAvgBarTime : g_sellLastAvgBarTime;
      if(curBar == lastAvgBar) { SetEntryBlockReason(direction==1?"BUY: WAIT NEXT BAR":"SELL: WAIT NEXT BAR"); return; }
     }

   // anti-burst: jeda minimum antar averaging dalam detik
   datetime lastAvgTime = (direction==1) ? g_buyLastAvgTime : g_sellLastAvgTime;
   if(TimeCurrent() - lastAvgTime < InpMinSecondsBetweenAvg) { SetEntryBlockReason(direction==1?"BUY: AVG TIME GAP":"SELL: AVG TIME GAP"); return; }

   double distancePts = CalcAveragingDistancePts(); // Module 5: FIXED POINT, tidak menggunakan ATR

   bool needAverage = false;
   if(direction==1)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double distPts = (lastOpenPrice - bid)/point;
      needAverage = (distPts >= distancePts);
     }
   else
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double distPts = (ask - lastOpenPrice)/point;
      needAverage = (distPts >= distancePts);
     }
   if(!needAverage) return;

   // ================================================================
   // GRID TREND FOLLOW HIGHER TF
   // Hanya setelah jarak grid terpenuhi, cek ulang M5 + H4.
   // - searah  : lanjutkan grid normal
   // - berbalik : jangan tambah grid melawan trend; reverse basket
   // - tidak jelas : tahan grid sampai trend kembali terkonfirmasi
   // ================================================================
   int gridTrendDirection = GetGridHigherTFDirection(direction);

   if(gridTrendDirection == 0)
     {
      SetEntryBlockReason(direction==1?"BUY: GRID WAIT HIGHER TF":"SELL: GRID WAIT HIGHER TF");
      return;
     }

   if(gridTrendDirection != direction)
     {
      if(InpGridReverseOnTrendFlip)
        {
         ReverseBasketToHigherTF(direction, gridTrendDirection, count, lastLot, atrNow);
         return;
        }

      // Toggle flip OFF = pertahankan perilaku grid lama.
      SetEntryBlockReason(direction==1?"BUY: HTF FLIP IGNORED":"SELL: HTF FLIP IGNORED");
     }

   double nextLot = NormalizeLot(CalcNextLot(count, lastLot) * AdaptiveLotFactor());
   // jangan sampai averaging berikutnya menembus cap total lot basket
   if(totalLots + nextLot > InpMaxTotalLotBasket)
     {
      nextLot = NormalizeLot(InpMaxTotalLotBasket - totalLots);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(nextLot < minLot) { SetEntryBlockReason(direction==1?"BUY: LOT CAP REMAINDER":"SELL: LOT CAP REMAINDER"); return; } // sisa kapasitas terlalu kecil, skip
     }

   double price = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ENUM_ORDER_TYPE ot = (direction==1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!IsMarginSafeForOrder(ot, nextLot, price)) { SetEntryBlockReason(direction==1?"BUY: AVG MARGIN SAFETY":"SELL: AVG MARGIN SAFETY"); return; } // Module 7

   // Averaging #2+ dibuka tanpa SL individual. Setelah berhasil,
   // SL entry sebelumnya dihapus agar seluruh basket dikelola bersama.
   bool avgOK = SendBasketOrder(direction, nextLot, atrNow, !InpAveragingOrdersNoSL);
   if(avgOK && InpRemoveSLWhenAveraging)
      RemoveBasketIndividualSL(direction);
  }

//+------------------------------------------------------------------+
//---- END BasketManager.mqh ----
//======================================================================
// ---- BEGIN TrailingManager.mqh (inlined) ----
//======================================================================
//+------------------------------------------------------------------+
//| TrailingManager.mqh                                              |
//| RoyalQuantum_EA v2.03                                       |
//| Exit basket: cut-loss % equity (Module 3, dicek pertama = rem    |
//| darurat), lalu trailing basket ATAU Take Profit (fixed poin      |
//| ATAU ATR-based, mengikuti volatilitas seperti Module 5).         |
//| FIX v2.01 (dipertahankan): trailing peak pakai if/else langsung  |
//| ke g_buyPeakPts/g_sellPeakPts, BUKAN reference dari ternary yang |
//| tidak reliable di MQL5.                                          |
//+------------------------------------------------------------------+
input group "=== Trailing & Take Profit Basket ==="
input bool     InpUseBasketTrailing  = true;   // Aktifkan trailing basket? (false = pakai Take Profit)
input int      InpTrailStartPoints   = 180;    // Trailing start (poin)
input int      InpTrailStopDistance  = 90;     // Trailing stop distance (poin)
input bool     InpDisableTrailTP     = false;  // Matikan total trailing & TP (EA cuma open+averaging, close manual)
input bool     InpUseATRBasedTP      = true;   // true = TP mengikuti ATR | false = TP poin tetap
input double   InpATRTPMultiplier    = 2.5;    // TP = ATR(14) x multiplier ini (jika InpUseATRBasedTP=true)
input double   InpFixedTPPoints      = 3000.0; // Take Profit tetap (poin), dipakai jika InpUseATRBasedTP=false
input bool     InpUseProfitLock       = true;   // Kunci profit minimum setelah basket cukup jauh profit
input double   InpProfitLockStart     = 500.0;  // Profit peak minimal sebelum profit lock aktif
input double   InpProfitLockPoints    = 250.0;  // Profit minimum basket yang dilindungi
input bool     InpReduceAveragingOnDD = false;  // Jangan blok averaging hanya karena floating DD; hard safety tetap aktif
input double   InpAveragingDDLimitPct = 2.0;    // Dipakai hanya jika InpReduceAveragingOnDD=true


//+------------------------------------------------------------------+
void ManageBasketExit(int direction, double atrNow)
  {
   int count; double avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot;
   datetime lastOpenTime;
   GetBasketInfo(direction, count, avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot, lastOpenTime);
   if(count == 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double curPrice = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPts = (direction==1) ? (curPrice - avgPrice)/point
                                      : (avgPrice - curPrice)/point;

   // --- MODULE 3: basket cut-loss selalu menjadi rem darurat pertama ---
   bool singleEntryWaitingForGrid = (InpGridRecoveryEnabled && count == 1);
   if(CheckBasketCutLoss(floatingProfit, totalLots) && !singleEntryWaitingForGrid)
     {
      CloseBasketEx(direction, true);
      return;
     }

   if(InpDisableTrailTP) return;

   // ================================================================
   // STATE A: SINGLE ENTRY
   // Entry #1 tetap memakai broker SL individual.
   // Basket trailing BELUM boleh aktif pada count=1.
   // Untuk profit exit, gunakan TP ATR/fixed agar trade tidak dibiarkan
   // tanpa target profit hanya karena basket trailing sedang ON.
   // ================================================================
   if(count == 1)
     {
      double tpPts;
      if(InpUseATRBasedTP)
         tpPts = (atrNow/point) * InpATRTPMultiplier;
      else
         tpPts = InpFixedTPPoints;

      if(profitPts >= (tpPts - InpCloseBufferPoints))
        {
         CloseBasketEx(direction, false);
         return;
        }
      return;
     }

   // ================================================================
   // STATE B: BASKET RECOVERY (count >= 2)
   // Entry #1 SL sudah dihapus setelah averaging #2 berhasil.
   // Semua averaging #2+ tanpa SL individual.
   // Basket trailing baru boleh aktif setelah basket mencapai start.
   // ================================================================
   bool trailBrokerActive = false;
   if(direction==1)  trailBrokerActive = (g_buyPeakPts  > -1.0e8);
   else              trailBrokerActive = (g_sellPeakPts > -1.0e8);

   if(InpRemoveSLWhenAveraging && !trailBrokerActive)
      RemoveBasketIndividualSL(direction);

   if(!InpUseBasketTrailing)
     {
      double tpPts;
      if(InpUseATRBasedTP)
         tpPts = (atrNow/point) * InpATRTPMultiplier;
      else
         tpPts = InpFixedTPPoints;

      if(profitPts >= (tpPts - InpCloseBufferPoints))
        {
         CloseBasketEx(direction, false);
         return;
        }
      return;
     }

   if(profitPts < InpTrailStartPoints) return;

   double bufferPts = InpCloseBufferPoints;
   double trailExitPts;

   if(direction==1)
     {
      if(profitPts > g_buyPeakPts) g_buyPeakPts = profitPts;
      trailExitPts = g_buyPeakPts - InpTrailStopDistance + bufferPts;
      if(InpUseProfitLock && g_buyPeakPts >= InpProfitLockStart)
         trailExitPts = MathMax(trailExitPts, InpProfitLockPoints);

      // Setelah trailing aktif, broker SL boleh dipakai sebagai representasi
      // basket-level safety. Jika tersentuh, OnTradeTransaction menutup basket lain.
      ApplyBasketTrailingSL(1, avgPrice, trailExitPts);
      if(profitPts <= trailExitPts)
        {
         CloseBasketEx(direction, false);
         return;
        }
     }
   else
     {
      if(profitPts > g_sellPeakPts) g_sellPeakPts = profitPts;
      trailExitPts = g_sellPeakPts - InpTrailStopDistance + bufferPts;
      if(InpUseProfitLock && g_sellPeakPts >= InpProfitLockStart)
         trailExitPts = MathMax(trailExitPts, InpProfitLockPoints);

      ApplyBasketTrailingSL(-1, avgPrice, trailExitPts);
      if(profitPts <= trailExitPts)
        {
         CloseBasketEx(direction, false);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//---- END TrailingManager.mqh ----
//======================================================================
// ---- BEGIN PanelUI.mqh (inlined) ----

//+------------------------------------------------------------------+
//| PanelUI - Royal Quantum 2.04                                      |
//| Floating compact terminal style - clean dark UI                 |
//| v2.21 - separate CLOSED basket history dashboard               |
//+------------------------------------------------------------------+

bool   g_panelDetailsOpen = false;
bool   g_panelDragLocked  = false;
bool   g_panelVisible     = true;
#define RQ_BASKET_HISTORY_MAX 20
struct RQBasketHistoryItem
  {
   int direction; datetime openTime; datetime closeTime;
   double profit; double lots; double avgPrice; int orders; string reason;
  };
RQBasketHistoryItem g_basketHistory[RQ_BASKET_HISTORY_MAX];
int g_basketHistoryCount=0;
bool g_basketHistoryVisible=true;
bool g_basketHistoryDetails=false;
bool g_basketHistoryPendingRefresh=false;
datetime g_basketHistoryRefreshDue=0;
int g_basketHistoryRefreshRetries=0;
bool g_basketHistoryLocked=false;
int g_histX=465,g_histY=15,g_histW=370,g_histH=285;
int g_histPage=0;
int g_histPrevBuyCount=0,g_histPrevSellCount=0;

int    g_panelX = 15;
int    g_panelY = 15;
int    g_panelW = 430;
int    g_panelH = 440;
int    g_panelDetailH = 300;

//======================================================================
// ---- ROYAL QUANTUM LICENSE / SECURITY -----------------------------
//======================================================================
bool   g_licenseOK      = false;
bool   g_licenseExpired = false;
string g_licenseStatus  = "";
string RQ_LICENSE_BG    = "RQ_LICENSE_BG";
string RQ_LICENSE_TITLE = "RQ_LICENSE_TITLE";
string RQ_LICENSE_INFO  = "RQ_LICENSE_INFO";

bool RoyalQuantumLicenseCheck()
  {
   const long account_id=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   const datetime now=TimeCurrent();

   bool authorized=false;
   bool anyID=false;
   int totalIDs=ArraySize(RQ_LICENSE_IDS);
   for(int i=0;i<totalIDs;i++)
     {
      if(RQ_LICENSE_IDS[i]>0) anyID=true;
      if(RQ_LICENSE_IDS[i]>0 && account_id==RQ_LICENSE_IDS[i])
        { authorized=true; break; }
     }

   // Always authorize Demo accounts
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO)
     {
      authorized = true;
      anyID = true;
     }

   if(!anyID)
     {
      g_licenseOK=false;
      g_licenseExpired=false;
      g_licenseStatus="ACCOUNT ID NOT SET";
      return false;
     }

   if(!authorized)
     {
      g_licenseOK=false;
      g_licenseExpired=false;
      g_licenseStatus="ACCOUNT NOT AUTHORIZED";
      return false;
     }

   if(RQ_LICENSE_EXPIRY<=0 || now>RQ_LICENSE_EXPIRY)
     {
      g_licenseOK=false;
      g_licenseExpired=true;
      g_licenseStatus="LICENSE EXPIRED";
      return false;
     }

   g_licenseOK=true;
   g_licenseExpired=false;
   g_licenseStatus="LICENSE OK";
   return true;
  }

void RoyalQuantumDeleteLicenseOverlay()
  {
   if(ObjectFind(0,RQ_LICENSE_BG)>=0)    ObjectDelete(0,RQ_LICENSE_BG);
   if(ObjectFind(0,RQ_LICENSE_TITLE)>=0) ObjectDelete(0,RQ_LICENSE_TITLE);
   if(ObjectFind(0,RQ_LICENSE_INFO)>=0)  ObjectDelete(0,RQ_LICENSE_INFO);
  }

void RoyalQuantumPositionLicenseOverlay()
  {
   if(g_licenseOK) return;
   const int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   const int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   const int centerX=cw/2;
   const int centerY=ch/2;

   if(ObjectFind(0,RQ_LICENSE_BG)>=0)
     {
      ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_XDISTANCE,0);
      ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_YDISTANCE,0);
      ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_XSIZE,MathMax(1,cw));
      ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_YSIZE,MathMax(1,ch));
     }
   if(ObjectFind(0,RQ_LICENSE_TITLE)>=0)
     {
      ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_XDISTANCE,MathMax(0,centerX-170));
      ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_YDISTANCE,MathMax(0,centerY-55));
     }
   if(ObjectFind(0,RQ_LICENSE_INFO)>=0)
     {
      ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_XDISTANCE,MathMax(0,centerX-190));
      ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_YDISTANCE,MathMax(0,centerY+5));
     }
  }

void RoyalQuantumCreateLicenseOverlay()
  {
   RoyalQuantumDeleteLicenseOverlay();
   if(g_licenseOK) return;

   const int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   const int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   const string title=(g_licenseExpired ? "EXPIRED" : "LOCKED");
   string info;
   color titleColor;
   if(g_licenseExpired)
     {
      info="LICENSE EXPIRED: "+TimeToString(RQ_LICENSE_EXPIRY,TIME_DATE);
      titleColor=clrRed;
     }
   else
     {
      info="ACCOUNT NOT AUTHORIZED";
      titleColor=clrWhite;
     }

   ObjectCreate(0,RQ_LICENSE_BG,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_XDISTANCE,0);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_XSIZE,MathMax(1,cw));
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_YSIZE,MathMax(1,ch));
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_BORDER_COLOR,clrBlack);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_BACK,false);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,RQ_LICENSE_BG,OBJPROP_ZORDER,10000);

   ObjectCreate(0,RQ_LICENSE_TITLE,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetString(0,RQ_LICENSE_TITLE,OBJPROP_TEXT,title);
   ObjectSetString(0,RQ_LICENSE_TITLE,OBJPROP_FONT,"Arial Black");
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_FONTSIZE,42);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_COLOR,titleColor);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,RQ_LICENSE_TITLE,OBJPROP_ZORDER,10001);

   ObjectCreate(0,RQ_LICENSE_INFO,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetString(0,RQ_LICENSE_INFO,OBJPROP_TEXT,info);
   ObjectSetString(0,RQ_LICENSE_INFO,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_FONTSIZE,16);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,RQ_LICENSE_INFO,OBJPROP_ZORDER,10001);

   RoyalQuantumPositionLicenseOverlay();
   ChartRedraw();
  }

void RoyalQuantumRefreshLicense()
  {
   const bool previous=g_licenseOK;
   const bool current=RoyalQuantumLicenseCheck();
   if(current)
     {
      if(!previous)
        {
         RoyalQuantumDeleteLicenseOverlay();
         ChartRedraw();
        }
     }
   else
     {
      if(previous || ObjectFind(0,RQ_LICENSE_BG)<0)
         RoyalQuantumCreateLicenseOverlay();
      else
         RoyalQuantumPositionLicenseOverlay();
     }
  }

//======================================================================
// ---- ROYAL QUANTUM BRANDING / CENTER WALLPAPER --------------------
//======================================================================
string RQ_WALLPAPER = "RQ_BRAND_WALLPAPER";
string RQ_ICON      = "RQ_BRAND_ICON";

// External bitmap branding is disabled so no .bmp file is required.
// Keep these functions as no-ops because the rest of the EA calls them.
void RoyalQuantumDeleteBranding()
  {
   if(ObjectFind(0,RQ_WALLPAPER)>=0) ObjectDelete(0,RQ_WALLPAPER);
   if(ObjectFind(0,RQ_ICON)>=0)      ObjectDelete(0,RQ_ICON);
  }

void RoyalQuantumPositionBranding()
  {
   // No external resource required.
  }

void RoyalQuantumCreateBranding()
  {
   RoyalQuantumDeleteBranding();
  }

void RoyalQuantumPositionHeaderIcon()
  {
   // Header uses the native text label instead of a bitmap icon.
  }

color PANEL_BG      = C'11,16,24';
color PANEL_CARD    = C'16,22,31';
color PANEL_HEADER  = C'20,27,37';
color PANEL_BORDER  = C'48,61,76';
color PANEL_TEXT    = C'232,236,241';
color PANEL_MUTED   = C'150,160,173';
color PANEL_GREEN   = C'0,225,135';
color PANEL_RED     = C'255,70,82';
color PANEL_BLUE    = C'80,165,255';
color PANEL_GOLD    = C'238,190,70';

string BasketHistoryName(string suffix){return PFX+"basket_history_"+suffix;}
string BasketHistoryGVX(){return StringFormat("RV_BH_%s_%d_X",_Symbol,InpMagic);}
string BasketHistoryGVY(){return StringFormat("RV_BH_%s_%d_Y",_Symbol,InpMagic);}
string BasketHistoryReason(long r,double p)
  {
   if(r==DEAL_REASON_TP)return "TP";
   if(r==DEAL_REASON_SL)return "SL";
   if(r==DEAL_REASON_SO)return "STOP OUT";
   if(r==DEAL_REASON_CLIENT)return "MANUAL";
   if(r==DEAL_REASON_MOBILE)return "MOBILE";
   if(r==DEAL_REASON_WEB)return "WEB";
   if(r==DEAL_REASON_EXPERT)return p>=0?"EA PROFIT":"EA LOSS";
   return "CLOSED";
  }
void BasketHistoryAdd(int d,datetime ot,datetime ct,double p,double lots,double avg,int orders,string reason)
  {
   if(ct<=0||orders<=0)return;
   if(g_basketHistoryCount<RQ_BASKET_HISTORY_MAX)g_basketHistoryCount++;
   for(int k=g_basketHistoryCount-1;k>0;k--)g_basketHistory[k]=g_basketHistory[k-1];
   g_basketHistory[0].direction=d; g_basketHistory[0].openTime=ot; g_basketHistory[0].closeTime=ct;
   g_basketHistory[0].profit=p; g_basketHistory[0].lots=lots; g_basketHistory[0].avgPrice=avg;
   g_basketHistory[0].orders=orders; g_basketHistory[0].reason=reason;
  }
void BasketHistorySort()
  {
   // Newest CLOSED basket must always be row #1. Use close time as the
   // primary key and open time as a deterministic tie-breaker.
   for(int i=0;i<g_basketHistoryCount-1;i++)
      for(int j=i+1;j<g_basketHistoryCount;j++)
        {
         bool newer=false;
         if(g_basketHistory[j].closeTime>g_basketHistory[i].closeTime) newer=true;
         else if(g_basketHistory[j].closeTime==g_basketHistory[i].closeTime &&
                 g_basketHistory[j].openTime>g_basketHistory[i].openTime) newer=true;
         if(newer)
           {RQBasketHistoryItem t=g_basketHistory[i];g_basketHistory[i]=g_basketHistory[j];g_basketHistory[j]=t;}
        }
  }
bool BasketHistoryRebuild()
  {
   // Build into a temporary array first. Never erase the currently displayed
   // history just because MT5 history is momentarily unavailable while a
   // closing deal is being committed. This was the main cause of the
   // temporary empty/black history cards.
   RQBasketHistoryItem oldHistory[RQ_BASKET_HISTORY_MAX];
   int oldCount=g_basketHistoryCount;
   for(int z=0;z<oldCount;z++) oldHistory[z]=g_basketHistory[z];

   // BasketHistoryAdd writes directly to the global array, so save the old
   // state and let the normal builder operate, then commit only on success.
   g_basketHistoryCount=0;
   datetime from=TimeCurrent()-365*86400,to=TimeCurrent()+60;
   if(!HistorySelect(from,to))
     {
      g_basketHistoryCount=oldCount;
      for(int z=0;z<oldCount;z++) g_basketHistory[z]=oldHistory[z];
      return false;
     }
   double bv=0,sv=0,bp=0,sp=0,bl=0,sl=0,bpl=0,spl=0;
   datetime bo=0,so=0; int bn=0,sn=0; long br=DEAL_REASON_EXPERT,sr=DEAL_REASON_EXPERT;
   int total=(int)HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong tk=HistoryDealGetTicket(i); if(tk==0)continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=_Symbol)continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic)continue;
      long ty=HistoryDealGetInteger(tk,DEAL_TYPE),en=HistoryDealGetInteger(tk,DEAL_ENTRY);
      datetime tm=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      double v=HistoryDealGetDouble(tk,DEAL_VOLUME),pr=HistoryDealGetDouble(tk,DEAL_PRICE);
      double net=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      long rs=HistoryDealGetInteger(tk,DEAL_REASON);
      if(ty==DEAL_TYPE_BUY&&(en==DEAL_ENTRY_IN||en==DEAL_ENTRY_INOUT))
        {if(bv<=0.0000001){bo=tm;bp=0;bl=0;bpl=0;bn=0;}bv+=v;bl+=v;bpl+=pr*v;bn++;bp+=net;}
      else if(ty==DEAL_TYPE_SELL&&(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_OUT_BY))
        {if(bv>0.0000001){bv-=v;bp+=net;br=rs;if(bv<=0.0000001){double av=bl>0?bpl/bl:0;BasketHistoryAdd(1,bo,tm,bp,bl,av,bn,BasketHistoryReason(br,bp));bv=0;bo=0;bp=0;bl=0;bpl=0;bn=0;}}}
      if(ty==DEAL_TYPE_SELL&&(en==DEAL_ENTRY_IN||en==DEAL_ENTRY_INOUT))
        {if(sv<=0.0000001){so=tm;sp=0;sl=0;spl=0;sn=0;}sv+=v;sl+=v;spl+=pr*v;sn++;sp+=net;}
      else if(ty==DEAL_TYPE_BUY&&(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_OUT_BY))
        {if(sv>0.0000001){sv-=v;sp+=net;sr=rs;if(sv<=0.0000001){double av=sl>0?spl/sl:0;BasketHistoryAdd(-1,so,tm,sp,sl,av,sn,BasketHistoryReason(sr,sp));sv=0;so=0;sp=0;sl=0;spl=0;sn=0;}}}
     }
   BasketHistorySort();
   return true;
  }
void BasketHistoryLoadPosition(){g_histX=465;g_histY=15;if(GlobalVariableCheck(BasketHistoryGVX()))g_histX=(int)GlobalVariableGet(BasketHistoryGVX());if(GlobalVariableCheck(BasketHistoryGVY()))g_histY=(int)GlobalVariableGet(BasketHistoryGVY());}
void BasketHistorySavePosition(){GlobalVariableSet(BasketHistoryGVX(),(double)g_histX);GlobalVariableSet(BasketHistoryGVY(),(double)g_histY);}

string PanelName(string suffix)
  {
   return PFX+"float_"+suffix;
  }

string PanelGVX()
  {
   return StringFormat("RV_PANEL_%s_%d_X",_Symbol,InpMagic);
  }

string PanelGVY()
  {
   return StringFormat("RV_PANEL_%s_%d_Y",_Symbol,InpMagic);
  }

string PanelTF()
  {
   string tf=EnumToString(InpTF);
   StringReplace(tf,"PERIOD_","");
   return tf;
  }

void PanelSavePosition()
  {
   GlobalVariableSet(PanelGVX(),(double)g_panelX);
   GlobalVariableSet(PanelGVY(),(double)g_panelY);
  }

void PanelLoadPosition()
  {
   g_panelX=15;
   g_panelY=15;

   if(GlobalVariableCheck(PanelGVX()))
      g_panelX=(int)GlobalVariableGet(PanelGVX());
   if(GlobalVariableCheck(PanelGVY()))
      g_panelY=(int)GlobalVariableGet(PanelGVY());

   long cw=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   long ch=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);

   if(cw>0) g_panelX=MathMax(0,MathMin(g_panelX,(int)cw-g_panelW-5));
   if(ch>0) g_panelY=MathMax(0,MathMin(g_panelY,(int)ch-g_panelH-5));
  }

void PanelPos(string name,int x,int y)
  {
   if(ObjectFind(0,name)<0) return;
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
  }

void PanelText(string name,string text,color clr=clrWhite)
  {
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }

void PanelRect(string name,int x,int y,int w,int h,color bg,color border,
               bool selectable=false,long z=1)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);

   ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,selectable);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);
  }

void PanelLabel(string name,int x,int y,string text,int size,color clr,
                string font="Consolas",long z=20)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);

   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,font);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);
  }

void PanelButton(string name,int x,int y,int w,int h,string text)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);

   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,PANEL_TEXT);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'25,33,44');
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,PANEL_BORDER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,60);
  }

void PanelCreateMain()
  {
   // Outer frame
   PanelRect(PanelName("bg"),g_panelX,g_panelY,g_panelW,g_panelH,
             PANEL_BG,PANEL_BORDER,false,1);

   // Header / drag zone
   PanelRect(PanelName("drag"),g_panelX,g_panelY,g_panelW,38,
             PANEL_HEADER,PANEL_BORDER,true,10);

   PanelLabel(PanelName("brand"),g_panelX+72,g_panelY+9,
              "ROYAL QUANTUM 2.11",9,PANEL_TEXT,"Consolas Bold",30);

   PanelLabel(PanelName("status"),g_panelX+220,g_panelY+11,
              "● SAFE",7,PANEL_GREEN,"Consolas Bold",30);

   // Header buttons are kept in a fixed right-side zone so the status
   // text can never overlap LOCK/HIDE.
   PanelButton(PanelName("lock"),g_panelX+300,g_panelY+7,48,23,"LOCK");
   PanelButton(PanelName("hide"),g_panelX+352,g_panelY+7,66,23,"HIDE");
   PanelButton(PanelName("close"),g_panelX+407,g_panelY+7,1,23,"");
   PanelButton(PanelName("main_tab"),g_panelX,g_panelY,86,25,"RQ  SHOW");

   // Symbol / signal row
   PanelLabel(PanelName("symbol"),g_panelX+14,g_panelY+51,
              "",9,PANEL_TEXT,"Consolas Bold");
   PanelLabel(PanelName("signal"),g_panelX+128,g_panelY+51,
              "",9,PANEL_GREEN,"Consolas Bold");
   PanelLabel(PanelName("trend"),g_panelX+315,g_panelY+51,
              "",9,PANEL_MUTED,"Consolas");

   // Separator
   PanelRect(PanelName("sep1"),g_panelX+12,g_panelY+70,
             g_panelW-24,1,PANEL_BORDER,PANEL_BORDER,false,2);

   // Account cards
   PanelLabel(PanelName("bal_cap"),g_panelX+18,g_panelY+84,
              "Balance",8,PANEL_MUTED);
   PanelLabel(PanelName("bal"),g_panelX+18,g_panelY+101,
              "",11,PANEL_TEXT,"Consolas Bold");

   PanelLabel(PanelName("eq_cap"),g_panelX+155,g_panelY+84,
              "Equity",8,PANEL_MUTED);
   PanelLabel(PanelName("eq"),g_panelX+155,g_panelY+101,
              "",11,PANEL_TEXT,"Consolas Bold");

   PanelLabel(PanelName("pl_cap"),g_panelX+292,g_panelY+84,
              "Today P/L",8,PANEL_MUTED);
   PanelLabel(PanelName("pl"),g_panelX+292,g_panelY+101,
              "",11,PANEL_GREEN,"Consolas Bold");

   // Basket cards
   PanelRect(PanelName("buy_card"),g_panelX+12,g_panelY+128,198,112,
             C'13,28,28',C'0,125,88',false,2);
   PanelRect(PanelName("sell_card"),g_panelX+220,g_panelY+128,198,112,
             C'29,18,24',C'145,55,67',false,2);

   PanelLabel(PanelName("buy_title"),g_panelX+23,g_panelY+139,
              "^  BUY BASKET",8,PANEL_GREEN,"Consolas Bold");
   PanelLabel(PanelName("sell_title"),g_panelX+231,g_panelY+139,
              "v  SELL BASKET",8,PANEL_RED,"Consolas Bold");

   PanelLabel(PanelName("buy0"),g_panelX+23,g_panelY+161,"",8,PANEL_TEXT);
   PanelLabel(PanelName("buy1"),g_panelX+23,g_panelY+179,"",8,PANEL_TEXT);
   PanelLabel(PanelName("buy2"),g_panelX+23,g_panelY+197,"",8,PANEL_MUTED);
   PanelLabel(PanelName("buy3"),g_panelX+23,g_panelY+215,"",8,PANEL_GREEN);

   PanelLabel(PanelName("sell0"),g_panelX+231,g_panelY+161,"",8,PANEL_TEXT);
   PanelLabel(PanelName("sell1"),g_panelX+231,g_panelY+179,"",8,PANEL_TEXT);
   PanelLabel(PanelName("sell2"),g_panelX+231,g_panelY+197,"",8,PANEL_MUTED);
   PanelLabel(PanelName("sell3"),g_panelX+231,g_panelY+215,"",8,PANEL_RED);

   // Statistics strip
   PanelRect(PanelName("stats"),g_panelX+12,g_panelY+250,
             g_panelW-24,66,PANEL_CARD,PANEL_BORDER,false,2);

   PanelLabel(PanelName("sp_cap"),g_panelX+25,g_panelY+260,"Spread",8,PANEL_MUTED);
   PanelLabel(PanelName("sp"),g_panelX+25,g_panelY+278,"",9,PANEL_TEXT,"Consolas Bold");

   PanelLabel(PanelName("atr_cap"),g_panelX+130,g_panelY+260,"ATR",8,PANEL_MUTED);
   PanelLabel(PanelName("atr"),g_panelX+130,g_panelY+278,"",9,PANEL_TEXT,"Consolas Bold");

   PanelLabel(PanelName("mar_cap"),g_panelX+235,g_panelY+260,"Margin",8,PANEL_MUTED);
   PanelLabel(PanelName("mar"),g_panelX+235,g_panelY+278,"",9,PANEL_GREEN,"Consolas Bold");

   PanelLabel(PanelName("dd_cap"),g_panelX+335,g_panelY+260,"DD",8,PANEL_MUTED);
   PanelLabel(PanelName("dd"),g_panelX+335,g_panelY+278,"",9,PANEL_TEXT,"Consolas Bold");
   PanelLabel(PanelName("dd_mode"),g_panelX+325,g_panelY+297,"",7,PANEL_TEXT,"Consolas Bold");

   // Trading state strip
   PanelRect(PanelName("trade"),g_panelX+12,g_panelY+325,
             g_panelW-24,66,PANEL_CARD,PANEL_BORDER,false,2);

   PanelLabel(PanelName("tr_cap"),g_panelX+25,g_panelY+335,"Trading",8,PANEL_MUTED);
   PanelLabel(PanelName("tr"),g_panelX+25,g_panelY+353,"",9,PANEL_GREEN,"Consolas Bold");

   PanelLabel(PanelName("ex_cap"),g_panelX+160,g_panelY+335,"Exit Mode",8,PANEL_MUTED);
   PanelLabel(PanelName("ex"),g_panelX+160,g_panelY+353,"",9,PANEL_TEXT,"Consolas Bold");

   PanelLabel(PanelName("sig_cap"),g_panelX+305,g_panelY+335,"Signal",8,PANEL_MUTED);
   PanelLabel(PanelName("sig"),g_panelX+305,g_panelY+353,"",9,PANEL_GREEN,"Consolas Bold");

   // Footer buttons
   PanelButton(PanelName("detail_btn"),g_panelX+12,g_panelY+400,196,28,"DETAILS  v");
   PanelButton(PanelName("history_btn"),g_panelX+222,g_panelY+400,196,28,"BASKET HISTORY");

   // Hidden detail panel
   int dy=g_panelY+g_panelH+6;
   PanelRect(PanelName("detail_bg"),g_panelX,dy,g_panelW,g_panelDetailH,
             PANEL_BG,PANEL_BORDER,false,1);
   PanelLabel(PanelName("detail_title"),g_panelX+14,dy+9,
              "TECHNICAL DETAILS",9,PANEL_TEXT,"Consolas Bold");

   for(int i=0;i<16;i++)
      PanelLabel(PanelName("detail"+IntegerToString(i)),
                 g_panelX+14,dy+34+i*17,"",8,PANEL_TEXT);

   PanelApplyVisibility();
  }

void PanelMoveAll(int x,int y)
  {
   g_panelX=MathMax(0,x);
   g_panelY=MathMax(0,y);

   // Main
   PanelPos(PanelName("bg"),g_panelX,g_panelY);
   PanelPos(PanelName("drag"),g_panelX,g_panelY);
   PanelPos(PanelName("brand"),g_panelX+72,g_panelY+9);
   PanelPos(PanelName("status"),g_panelX+220,g_panelY+11);
   PanelPos(PanelName("lock"),g_panelX+300,g_panelY+7);
   PanelPos(PanelName("hide"),g_panelX+352,g_panelY+7);
   PanelPos(PanelName("close"),g_panelX+407,g_panelY+7);
   PanelPos(PanelName("main_tab"),g_panelX,g_panelY);

   PanelPos(PanelName("symbol"),g_panelX+14,g_panelY+51);
   PanelPos(PanelName("signal"),g_panelX+128,g_panelY+51);
   PanelPos(PanelName("trend"),g_panelX+315,g_panelY+51);
   PanelPos(PanelName("sep1"),g_panelX+12,g_panelY+70);

   PanelPos(PanelName("bal_cap"),g_panelX+18,g_panelY+84);
   PanelPos(PanelName("bal"),g_panelX+18,g_panelY+101);
   PanelPos(PanelName("eq_cap"),g_panelX+155,g_panelY+84);
   PanelPos(PanelName("eq"),g_panelX+155,g_panelY+101);
   PanelPos(PanelName("pl_cap"),g_panelX+292,g_panelY+84);
   PanelPos(PanelName("pl"),g_panelX+292,g_panelY+101);

   PanelPos(PanelName("buy_card"),g_panelX+12,g_panelY+128);
   PanelPos(PanelName("sell_card"),g_panelX+220,g_panelY+128);
   PanelPos(PanelName("buy_title"),g_panelX+23,g_panelY+139);
   PanelPos(PanelName("sell_title"),g_panelX+231,g_panelY+139);

   PanelPos(PanelName("buy0"),g_panelX+23,g_panelY+161);
   PanelPos(PanelName("buy1"),g_panelX+23,g_panelY+179);
   PanelPos(PanelName("buy2"),g_panelX+23,g_panelY+197);
   PanelPos(PanelName("buy3"),g_panelX+23,g_panelY+215);
   PanelPos(PanelName("sell0"),g_panelX+231,g_panelY+161);
   PanelPos(PanelName("sell1"),g_panelX+231,g_panelY+179);
   PanelPos(PanelName("sell2"),g_panelX+231,g_panelY+197);
   PanelPos(PanelName("sell3"),g_panelX+231,g_panelY+215);

   PanelPos(PanelName("stats"),g_panelX+12,g_panelY+250);
   PanelPos(PanelName("sp_cap"),g_panelX+25,g_panelY+260);
   PanelPos(PanelName("sp"),g_panelX+25,g_panelY+278);
   PanelPos(PanelName("atr_cap"),g_panelX+130,g_panelY+260);
   PanelPos(PanelName("atr"),g_panelX+130,g_panelY+278);
   PanelPos(PanelName("mar_cap"),g_panelX+235,g_panelY+260);
   PanelPos(PanelName("mar"),g_panelX+235,g_panelY+278);
   PanelPos(PanelName("dd_cap"),g_panelX+335,g_panelY+260);
   PanelPos(PanelName("dd"),g_panelX+335,g_panelY+278);
   PanelPos(PanelName("dd_mode"),g_panelX+325,g_panelY+297);

   PanelPos(PanelName("trade"),g_panelX+12,g_panelY+325);
   PanelPos(PanelName("tr_cap"),g_panelX+25,g_panelY+335);
   PanelPos(PanelName("tr"),g_panelX+25,g_panelY+353);
   PanelPos(PanelName("ex_cap"),g_panelX+160,g_panelY+335);
   PanelPos(PanelName("ex"),g_panelX+160,g_panelY+353);
   PanelPos(PanelName("sig_cap"),g_panelX+305,g_panelY+335);
   PanelPos(PanelName("sig"),g_panelX+305,g_panelY+353);
   PanelPos(PanelName("detail_btn"),g_panelX+12,g_panelY+400);
   PanelPos(PanelName("history_btn"),g_panelX+222,g_panelY+400);

   // Details
   int dy=g_panelY+g_panelH+6;
   PanelPos(PanelName("detail_bg"),g_panelX,dy);
   PanelPos(PanelName("detail_title"),g_panelX+14,dy+9);
   for(int i=0;i<16;i++)
      PanelPos(PanelName("detail"+IntegerToString(i)),
               g_panelX+14,dy+34+i*17);

   ChartRedraw();
  }

void PanelApplyVisibility()
  {
   // The technical panel background/title AND its text must use the same
   // visibility state. Previously the background stayed visible while the
   // labels remained hidden until DETAILS was clicked.
   long detailMode=(g_panelVisible && g_panelDetailsOpen)?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;

   ObjectSetInteger(0,PanelName("detail_bg"),OBJPROP_TIMEFRAMES,detailMode);
   ObjectSetInteger(0,PanelName("detail_title"),OBJPROP_TIMEFRAMES,detailMode);

   for(int i=0;i<16;i++)
      ObjectSetInteger(0,PanelName("detail"+IntegerToString(i)),
                       OBJPROP_TIMEFRAMES,detailMode);

   PanelText(PanelName("detail_btn"),
             g_panelDetailsOpen?"DETAILS  ^":"DETAILS  v",PANEL_TEXT);
   ChartRedraw();
  }

void PanelSetMainVisibility(bool visible)
  {
   g_panelVisible=visible;

   string n[]={"bg","drag","brand","status","lock","hide","close",
               "symbol","signal","trend","sep1","bal_cap","bal","eq_cap","eq",
               "pl_cap","pl","buy_card","sell_card","buy_title","sell_title",
               "buy0","buy1","buy2","buy3","sell0","sell1","sell2","sell3",
               "stats","sp_cap","sp","atr_cap","atr","mar_cap","mar","dd_cap",
               "dd","dd_mode","trade","tr_cap","tr","ex_cap","ex","sig_cap",
               "sig","detail_btn","history_btn"};

   long mode=visible?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
   for(int i=0;i<ArraySize(n);i++)
      ObjectSetInteger(0,PanelName(n[i]),OBJPROP_TIMEFRAMES,mode);

   // Do NOT expose the technical background independently of its contents.
   PanelApplyVisibility();

   // SHOW tab exists only while the main dashboard is hidden.
   ObjectSetInteger(0,PanelName("main_tab"),OBJPROP_TIMEFRAMES,
                    visible?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);

   ChartRedraw();
  }

void PanelToggleMainVisibility()
  {
   PanelSetMainVisibility(!g_panelVisible);
  }

void PanelHideMainByInput()
  {
   if(InpShowPanel) { PanelSetMainVisibility(true); return; }
   PanelSetMainVisibility(false);
   ObjectSetInteger(0,PanelName("bg"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("drag"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("brand"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("status"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("lock"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("close"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("history_btn"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("detail_btn"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("symbol"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("signal"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("trend"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,PanelName("sep1"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   string n[]={"bal_cap","bal","eq_cap","eq","pl_cap","pl","buy_card","sell_card","buy_title","sell_title","buy0","buy1","buy2","buy3","sell0","sell1","sell2","sell3","stats","sp_cap","sp","atr_cap","atr","mar_cap","mar","dd_cap","dd","dd_mode","trade","tr_cap","tr","ex_cap","ex","sig_cap","sig"};
   for(int i=0;i<ArraySize(n);i++) ObjectSetInteger(0,PanelName(n[i]),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,RQ_ICON,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
  }

string MTFName(string suffix){return PFX+"mtf_"+suffix;}
string MTFGVX(){return StringFormat("RV_MTF_%s_%d_X",_Symbol,InpMagic);}
string MTFGVY(){return StringFormat("RV_MTF_%s_%d_Y",_Symbol,InpMagic);}
void MTFLoadPosition()
  {
   g_mtfX=15; g_mtfY=470;
   if(GlobalVariableCheck(MTFGVX())) g_mtfX=(int)GlobalVariableGet(MTFGVX());
   if(GlobalVariableCheck(MTFGVY())) g_mtfY=(int)GlobalVariableGet(MTFGVY());
  }
void MTFSavePosition(){GlobalVariableSet(MTFGVX(),(double)g_mtfX);GlobalVariableSet(MTFGVY(),(double)g_mtfY);}
void MTFPos(string n,int x,int y){PanelPos(n,x,y);}
void MTFApplyVisibility()
  {
   long mode=g_mtfDashboardVisible?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
   string n[]={"bg","drag","title","status","hide","close","summary","m1","m1d","m5","m5d","h4","h4d","sep","detail0","detail1","detail2","detail3","detail4","detail5","lock"};
   for(int i=0;i<ArraySize(n);i++) ObjectSetInteger(0,MTFName(n[i]),OBJPROP_TIMEFRAMES,mode);
   ObjectSetInteger(0,MTFName("tab"),OBJPROP_TIMEFRAMES,g_mtfDashboardVisible?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
  }
void MTFCreateDashboard()
  {
   MTFLoadPosition();
   PanelRect(MTFName("bg"),g_mtfX,g_mtfY,g_mtfW,g_mtfH,PANEL_BG,PANEL_BORDER,false,1);
   PanelRect(MTFName("drag"),g_mtfX,g_mtfY,g_mtfW,38,PANEL_HEADER,PANEL_BORDER,true,10);
   PanelLabel(MTFName("title"),g_mtfX+14,g_mtfY+10,"MTF DIRECTION",10,PANEL_TEXT,"Consolas Bold",30);
   PanelLabel(MTFName("status"),g_mtfX+170,g_mtfY+11,"● WAIT",7,PANEL_MUTED,"Consolas Bold",30);
   PanelButton(MTFName("lock"),g_mtfX+g_mtfW-125,g_mtfY+7,58,23,"LOCK");
   PanelButton(MTFName("hide"),g_mtfX+g_mtfW-65,g_mtfY+7,58,23,"HIDE");
   PanelButton(MTFName("close"),g_mtfX+g_mtfW+2,g_mtfY+7,40,23,"X");
   PanelButton(MTFName("tab"),g_mtfX,g_mtfY,105,25,"MTF");
   PanelLabel(MTFName("summary"),g_mtfX+14,g_mtfY+49,"M1 + M5 + H4 | ALL MUST AGREE",8,PANEL_MUTED,"Consolas Bold");
   PanelRect(MTFName("sep"),g_mtfX+12,g_mtfY+69,g_mtfW-24,1,PANEL_BORDER,PANEL_BORDER,false,2);
   PanelRect(MTFName("m1"),g_mtfX+12,g_mtfY+81,g_mtfW-24,42,PANEL_CARD,PANEL_BORDER,false,2);
   PanelRect(MTFName("m5"),g_mtfX+12,g_mtfY+129,g_mtfW-24,42,PANEL_CARD,PANEL_BORDER,false,2);
   PanelRect(MTFName("h4"),g_mtfX+12,g_mtfY+177,g_mtfW-24,42,PANEL_CARD,PANEL_BORDER,false,2);
   PanelLabel(MTFName("m1d"),g_mtfX+24,g_mtfY+90,"M1   WAIT",10,PANEL_MUTED,"Consolas Bold",30);
   PanelLabel(MTFName("m5d"),g_mtfX+24,g_mtfY+138,"M5   WAIT",10,PANEL_MUTED,"Consolas Bold",30);
   PanelLabel(MTFName("h4d"),g_mtfX+24,g_mtfY+186,"H4   WAIT",10,PANEL_MUTED,"Consolas Bold",30);
   PanelLabel(MTFName("detail0"),g_mtfX+145,g_mtfY+90,"",7,PANEL_MUTED,"Consolas");
   PanelLabel(MTFName("detail1"),g_mtfX+145,g_mtfY+106,"",7,PANEL_MUTED,"Consolas");
   PanelLabel(MTFName("detail2"),g_mtfX+145,g_mtfY+138,"",7,PANEL_MUTED,"Consolas");
   PanelLabel(MTFName("detail3"),g_mtfX+145,g_mtfY+154,"",7,PANEL_MUTED,"Consolas");
   PanelLabel(MTFName("detail4"),g_mtfX+145,g_mtfY+186,"",7,PANEL_MUTED,"Consolas");
   PanelLabel(MTFName("detail5"),g_mtfX+145,g_mtfY+202,"",7,PANEL_MUTED,"Consolas");
   MTFApplyVisibility();
  }
void MTFMoveAll(int x,int y)
  {
   g_mtfX=x;g_mtfY=y;
   PanelPos(MTFName("bg"),x,y); PanelPos(MTFName("drag"),x,y); PanelPos(MTFName("title"),x+14,y+10);
   PanelPos(MTFName("status"),x+170,y+11); PanelPos(MTFName("lock"),x+g_mtfW-125,y+7);
   PanelPos(MTFName("hide"),x+g_mtfW-65,y+7); PanelPos(MTFName("close"),x+g_mtfW+2,y+7); PanelPos(MTFName("tab"),x,y);
   PanelPos(MTFName("summary"),x+14,y+49); PanelPos(MTFName("sep"),x+12,y+69);
   PanelPos(MTFName("m1"),x+12,y+81); PanelPos(MTFName("m5"),x+12,y+129); PanelPos(MTFName("h4"),x+12,y+177);
   PanelPos(MTFName("m1d"),x+24,y+90); PanelPos(MTFName("m5d"),x+24,y+138); PanelPos(MTFName("h4d"),x+24,y+186);
   PanelPos(MTFName("detail0"),x+145,y+90);
   PanelPos(MTFName("detail1"),x+145,y+106);
   PanelPos(MTFName("detail2"),x+145,y+138);
   PanelPos(MTFName("detail3"),x+145,y+154);
   PanelPos(MTFName("detail4"),x+145,y+186);
   PanelPos(MTFName("detail5"),x+145,y+202);
  }
void MTFHandleDrag()
  {
   if(g_mtfDashboardLocked)return;
   int x=(int)ObjectGetInteger(0,MTFName("drag"),OBJPROP_XDISTANCE);
   int y=(int)ObjectGetInteger(0,MTFName("drag"),OBJPROP_YDISTANCE);
   long cw=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),ch=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(cw>0)x=MathMax(0,MathMin(x,(int)cw-g_mtfW-4));
   if(ch>0)y=MathMax(0,MathMin(y,(int)ch-g_mtfH-4));
   MTFMoveAll(x,y); MTFSavePosition(); ObjectSetInteger(0,MTFName("drag"),OBJPROP_SELECTED,false); ChartRedraw();
  }
void MTFSetVisibility(bool visible)
  {
   g_mtfDashboardVisible=visible; MTFApplyVisibility(); ChartRedraw();
  }
void MTFUpdateDashboard()
  {
   if(ObjectFind(0,MTFName("bg"))<0)return;
   MTFUpdateStates();
   string m1=MTFDirectionText(g_mtfM1),m5=MTFDirectionText(g_mtfM5),h4=MTFDirectionText(g_mtfH4);
   string overall;
   color oc;
   if(!g_webMTFEnabled)
     {
      overall="SCALPER M1";
      oc=PANEL_GREEN;
     }
   else
     {
      bool buy=MTFDirectionConfirmed(1), sell=MTFDirectionConfirmed(-1);
      overall=buy?"BUY CONFIRMED":(sell?"SELL CONFIRMED":"WAIT");
      oc=buy?PANEL_GREEN:(sell?PANEL_RED:PANEL_GOLD);
     }
   PanelText(MTFName("status"),"● "+overall,oc);
   PanelText(MTFName("m1d"),"M1   "+m1,MTFDirectionColor(g_mtfM1));
   PanelText(MTFName("m5d"),"M5   "+m5,MTFDirectionColor(g_mtfM5));
   PanelText(MTFName("h4d"),"H4   "+h4,MTFDirectionColor(g_mtfH4));
   PanelText(MTFName("detail0"),StringFormat("EMA %.2f | EMA200 %.2f",g_mtfM1.emaDir,g_mtfM1.ema200),PANEL_MUTED);
   PanelText(MTFName("detail1"),StringFormat("Stoch %.1f | Slope %.1f",g_mtfM1.stoch,g_mtfM1.slopePts),PANEL_MUTED);
   PanelText(MTFName("detail2"),StringFormat("EMA %.2f | EMA200 %.2f",g_mtfM5.emaDir,g_mtfM5.ema200),PANEL_MUTED);
   PanelText(MTFName("detail3"),StringFormat("Stoch %.1f | Slope %.1f",g_mtfM5.stoch,g_mtfM5.slopePts),PANEL_MUTED);
   PanelText(MTFName("detail4"),StringFormat("EMA %.2f | EMA200 %.2f",g_mtfH4.emaDir,g_mtfH4.ema200),PANEL_MUTED);
   PanelText(MTFName("detail5"),StringFormat("Stoch %.1f | Slope %.1f",g_mtfH4.stoch,g_mtfH4.slopePts),PANEL_MUTED);
   MTFApplyVisibility();
  }

//======================================================================
// ---- DASHBOARD LAYOUT / NO-OVERLAP GUARD ---------------------------
// Keeps the three floating dashboards from covering each other.
// User positions are preserved whenever possible; if a saved position
// overlaps another dashboard, the affected dashboard is moved to the
// nearest free side and its new position is saved.
//======================================================================
bool RQRectOverlap(int x1,int y1,int w1,int h1,
                   int x2,int y2,int w2,int h2)
  {
   return !(x1+w1<=x2 || x2+w2<=x1 || y1+h1<=y2 || y2+h2<=y1);
  }

void RQClampPanelPositions()
  {
   long cw=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   long ch=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(cw<=0 || ch<=0) return;

   g_panelX=MathMax(0,MathMin(g_panelX,(int)cw-g_panelW-5));
   g_panelY=MathMax(0,MathMin(g_panelY,(int)ch-g_panelH-5));
   g_histX=MathMax(0,MathMin(g_histX,(int)cw-g_histW-5));
   g_histY=MathMax(0,MathMin(g_histY,(int)ch-g_histH-5));
   g_mtfX=MathMax(0,MathMin(g_mtfX,(int)cw-g_mtfW-5));
   g_mtfY=MathMax(0,MathMin(g_mtfY,(int)ch-g_mtfH-5));
  }

void RQResolveDashboardOverlap()
  {
   long cw=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   long ch=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(cw<=0 || ch<=0) return;

   const int gap=12;
   RQClampPanelPositions();

   // 1) Main vs Basket History.
   // Prefer history to the RIGHT of the main dashboard. If there is not
   // enough room, put it to the LEFT; if neither side fits, put it BELOW.
   if(RQRectOverlap(g_panelX,g_panelY,g_panelW,g_panelH,
                    g_histX,g_histY,g_histW,g_histH))
     {
      int rightX=g_panelX+g_panelW+gap;
      int leftX=g_panelX-g_histW-gap;
      int belowY=g_panelY+g_panelH+gap;

      if(rightX+g_histW <= cw-5)
        { g_histX=rightX; g_histY=g_panelY; }
      else if(leftX>=5)
        { g_histX=leftX; g_histY=g_panelY; }
      else if(belowY+g_histH <= ch-5)
        { g_histX=g_panelX; g_histY=belowY; }
      else
        { g_histX=MathMax(5,(int)cw-g_histW-5); g_histY=5; }

      BasketHistoryMoveAll(g_histX,g_histY);
      BasketHistorySavePosition();
     }

   // 2) Main/History vs MTF. Prefer MTF below the main dashboard. If that
   // collides with history, move it below the lowest occupied dashboard.
   bool mtfOverlap=RQRectOverlap(g_panelX,g_panelY,g_panelW,g_panelH,
                                 g_mtfX,g_mtfY,g_mtfW,g_mtfH) ||
                   RQRectOverlap(g_histX,g_histY,g_histW,g_histH,
                                 g_mtfX,g_mtfY,g_mtfW,g_mtfH);
   if(mtfOverlap)
     {
      int y1=g_panelY+g_panelH+gap;
      int y2=g_histY+g_histH+gap;
      int candidateY=MathMax(y1,y2);

      if(candidateY+g_mtfH<=ch-5)
        { g_mtfX=g_panelX; g_mtfY=candidateY; }
      else
        {
         // Try the left/right free columns before falling back to the
         // bottom-most available position.
         int rightX=g_panelX+g_panelW+gap;
         int leftX=g_panelX-g_mtfW-gap;
         if(rightX+g_mtfW<=cw-5 &&
            !RQRectOverlap(rightX,g_panelY,g_mtfW,g_mtfH,
                           g_histX,g_histY,g_histW,g_histH))
           { g_mtfX=rightX; g_mtfY=g_panelY; }
         else if(leftX>=5 &&
                 !RQRectOverlap(leftX,g_panelY,g_mtfW,g_mtfH,
                                g_histX,g_histY,g_histW,g_histH))
           { g_mtfX=leftX; g_mtfY=g_panelY; }
         else
           { g_mtfX=MathMax(5,(int)cw-g_mtfW-5);
             g_mtfY=MathMax(5,(int)ch-g_mtfH-5); }
        }

      MTFMoveAll(g_mtfX,g_mtfY);
      MTFSavePosition();
     }

   RQClampPanelPositions();
  }

void CreatePanel()
  {
   ObjectsDeleteAll(0,PFX);
   PanelLoadPosition();
   PanelCreateMain();
   PanelHideMainByInput();
   BasketHistoryLoadPosition();
   BasketHistoryRebuild();
   g_basketHistoryVisible=InpShowBasketHistory;
   BasketHistoryCreate();
   BasketHistoryHandleDrag();
   g_mtfDashboardVisible=InpShowMTFDashboard;
   if(InpShowMTFDashboard) MTFCreateDashboard();
   else
     {
      MTFCreateDashboard();
      MTFSetVisibility(false);
     }
   // Final layout pass: never allow the floating dashboards to overlap.
   RQResolveDashboardOverlap();
   int ibc; double ia,ib,ic,id,ie; datetime ift; GetBasketInfo(1,ibc,ia,ib,ic,id,ie,ift);
   int isc; double isa,isb,iscf,isd,ise; datetime isft; GetBasketInfo(-1,isc,isa,isb,iscf,isd,ise,isft);
   g_histPrevBuyCount=ibc; g_histPrevSellCount=isc;
   ChartRedraw();
  }

void BasketHistoryCreate()
  {
   PanelRect(BasketHistoryName("bg"),g_histX,g_histY,g_histW,g_histH,PANEL_BG,PANEL_BORDER,false,1);
   PanelRect(BasketHistoryName("drag"),g_histX,g_histY,g_histW,38,PANEL_HEADER,PANEL_BORDER,true,10);
   PanelLabel(BasketHistoryName("title"),g_histX+14,g_histY+10,"BASKET HISTORY",10,PANEL_TEXT,"Consolas Bold",30);
   PanelButton(BasketHistoryName("hide"),g_histX+g_histW-70,g_histY+7,62,23,"HIDE");
   // Small tab remains available when Basket History is hidden.
   PanelButton(BasketHistoryName("tab"),g_histX,g_histY,118,25,"BASKET HISTORY");
   PanelLabel(BasketHistoryName("summary"),g_histX+14,g_histY+50,"",8,PANEL_MUTED,"Consolas");
   PanelRect(BasketHistoryName("sep"),g_histX+12,g_histY+72,g_histW-24,1,PANEL_BORDER,PANEL_BORDER,false,2);
   int rows=MathMax(1,MathMin(InpBasketHistoryRows,5));
   for(int i=0;i<5;i++)
     {
      int yy=g_histY+82+i*34;
      PanelRect(BasketHistoryName("rowbg"+IntegerToString(i)),g_histX+10,yy,g_histW-20,32,PANEL_CARD,PANEL_BORDER,false,2);
      PanelLabel(BasketHistoryName("row"+IntegerToString(i)),g_histX+18,yy+5,"",8,PANEL_TEXT,"Consolas Bold");
      PanelLabel(BasketHistoryName("sub"+IntegerToString(i)),g_histX+18,yy+19,"",7,PANEL_MUTED,"Consolas");
     }
   PanelButton(BasketHistoryName("prev"),g_histX+12,g_histY+g_histH-31,34,23,"<");
   PanelLabel(BasketHistoryName("page"),g_histX+55,g_histY+g_histH-25,"1 / 1",8,PANEL_TEXT,"Consolas Bold");
   PanelButton(BasketHistoryName("next"),g_histX+95,g_histY+g_histH-31,34,23,">");
   PanelButton(BasketHistoryName("details"),g_histX+g_histW-105,g_histY+g_histH-31,93,23,"DETAILS");
   BasketHistoryApplyVisibility();
   BasketHistoryUpdate();
  }
void BasketHistoryMoveAll(int x,int y)
  {
   g_histX=x;g_histY=y;
   PanelPos(BasketHistoryName("bg"),x,y);
   PanelPos(BasketHistoryName("drag"),x,y);
   PanelPos(BasketHistoryName("title"),x+14,y+10);
   PanelPos(BasketHistoryName("hide"),x+g_histW-70,y+7);
   PanelPos(BasketHistoryName("tab"),x,y);
   PanelPos(BasketHistoryName("summary"),x+14,y+50);
   PanelPos(BasketHistoryName("sep"),x+12,y+72);
   int rows=MathMax(1,MathMin(InpBasketHistoryRows,5));
   for(int i=0;i<5;i++)
     {
      int yy=y+82+i*34;
      PanelPos(BasketHistoryName("rowbg"+IntegerToString(i)),x+10,yy);
      PanelPos(BasketHistoryName("row"+IntegerToString(i)),x+18,yy+5);
      PanelPos(BasketHistoryName("sub"+IntegerToString(i)),x+18,yy+19);
     }
   PanelPos(BasketHistoryName("prev"),x+12,y+g_histH-31);
   PanelPos(BasketHistoryName("page"),x+55,y+g_histH-25);
   PanelPos(BasketHistoryName("next"),x+95,y+g_histH-31);
   PanelPos(BasketHistoryName("details"),x+g_histW-105,y+g_histH-31);
  }
void BasketHistoryApplyVisibility()
  {
   long mode=g_basketHistoryVisible?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
   string n[]={"bg","drag","title","hide","summary","sep","prev","page","next","details"};
   for(int i=0;i<ArraySize(n);i++)
      ObjectSetInteger(0,BasketHistoryName(n[i]),OBJPROP_TIMEFRAMES,mode);

   // When hidden, leave only a compact SHOW tab on the chart.
   ObjectSetInteger(0,BasketHistoryName("tab"),OBJPROP_TIMEFRAMES,
                    g_basketHistoryVisible?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
   for(int i=0;i<5;i++)
     {
      ObjectSetInteger(0,BasketHistoryName("rowbg"+IntegerToString(i)),OBJPROP_TIMEFRAMES,mode);
      ObjectSetInteger(0,BasketHistoryName("row"+IntegerToString(i)),OBJPROP_TIMEFRAMES,mode);
      ObjectSetInteger(0,BasketHistoryName("sub"+IntegerToString(i)),OBJPROP_TIMEFRAMES,mode);
     }
  }
void BasketHistoryUpdate()
  {
   if(ObjectFind(0,BasketHistoryName("bg"))<0)return;
   int rows=MathMax(1,MathMin(InpBasketHistoryRows,5));
   int pageCount=(g_basketHistoryCount+rows-1)/rows;
   if(pageCount<1) pageCount=1;
   if(g_histPage<0) g_histPage=0;
   if(g_histPage>=pageCount) g_histPage=pageCount-1;
   double total=0; int wins=0;
   for(int i=0;i<g_basketHistoryCount;i++)
     {
      total+=g_basketHistory[i].profit;
      if(g_basketHistory[i].profit>0)wins++;
     }
   double wr=g_basketHistoryCount>0?100.0*wins/g_basketHistoryCount:0;
   string cur=AccountInfoString(ACCOUNT_CURRENCY);
   PanelText(BasketHistoryName("summary"),StringFormat("CLOSED %d/20 | WIN %.0f%% | P/L %+.2f %s",g_basketHistoryCount,wr,total,cur),total>=0?PANEL_GREEN:PANEL_RED);
   PanelText(BasketHistoryName("page"),StringFormat("%d / %d",g_histPage+1,pageCount),PANEL_TEXT);
   int first=g_histPage*rows;
   for(int i=0;i<5;i++)
     {
      int idx=first+i;
      if(i<rows && idx<g_basketHistoryCount)
        {
         RQBasketHistoryItem h=g_basketHistory[idx];
         string dir=h.direction==1?"BUY":"SELL";
         // Background first, text explicitly restored on top. MT5 Strategy
         // Tester can redraw rectangle labels after a transaction event.
         // IMPORTANT: repainting history must never force hidden rows back onto
         // the chart. v2.30 unconditionally used OBJ_ALL_PERIODS here, which
         // could make the newest basket reappear after a refresh while the
         // History dashboard was hidden. Respect the persistent visibility
         // state on every repaint.
         long histMode=g_basketHistoryVisible?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
         ObjectSetInteger(0,BasketHistoryName("rowbg"+IntegerToString(i)),OBJPROP_TIMEFRAMES,histMode);
         ObjectSetInteger(0,BasketHistoryName("rowbg"+IntegerToString(i)),OBJPROP_ZORDER,1);
         PanelText(BasketHistoryName("row"+IntegerToString(i)),StringFormat("#%03d  %-4s  %+.2f %s",idx+1,dir,h.profit,cur),h.profit>=0?PANEL_GREEN:PANEL_RED);
         string t=TimeToString(h.closeTime,TIME_DATE|TIME_MINUTES);
         // Single-entry trades are recorded as their own history item.
         // Multi-entry baskets keep the existing history format unchanged.
         if(h.orders<=1)
            PanelText(BasketHistoryName("sub"+IntegerToString(i)),StringFormat("%s | SINGLE | %.2fL | %s",t,h.lots,h.reason),PANEL_MUTED);
         else
            PanelText(BasketHistoryName("sub"+IntegerToString(i)),StringFormat("%s | %d ord | %.2fL | %s",t,h.orders,h.lots,h.reason),PANEL_MUTED);
         ObjectSetInteger(0,BasketHistoryName("row"+IntegerToString(i)),OBJPROP_ZORDER,100);
         ObjectSetInteger(0,BasketHistoryName("sub"+IntegerToString(i)),OBJPROP_ZORDER,101);
         ObjectSetInteger(0,BasketHistoryName("row"+IntegerToString(i)),OBJPROP_TIMEFRAMES,histMode);
         ObjectSetInteger(0,BasketHistoryName("sub"+IntegerToString(i)),OBJPROP_TIMEFRAMES,histMode);
        }
      else
        {
         PanelText(BasketHistoryName("row"+IntegerToString(i)),"",PANEL_TEXT);
         PanelText(BasketHistoryName("sub"+IntegerToString(i)),"",PANEL_MUTED);
         ObjectSetInteger(0,BasketHistoryName("rowbg"+IntegerToString(i)),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
        }
     }
   ObjectSetInteger(0,BasketHistoryName("prev"),OBJPROP_STATE,g_histPage>0);
   ObjectSetInteger(0,BasketHistoryName("next"),OBJPROP_STATE,g_histPage<pageCount-1);

   // Final guard: data can be rebuilt/repainted from OnTick/OnTimer even while
   // the dashboard is hidden. Re-apply visibility after the repaint.
   BasketHistoryApplyVisibility();
  }
void BasketHistoryToggle()
  {
   g_basketHistoryVisible=!g_basketHistoryVisible;
   BasketHistoryApplyVisibility();
   if(g_basketHistoryVisible)BasketHistoryUpdate();
   ChartRedraw();
  }

void BasketHistoryNextPage()
  {
   int rows=MathMax(1,MathMin(InpBasketHistoryRows,5));
   int pc=(g_basketHistoryCount+rows-1)/rows;
   if(pc<1)pc=1;
   if(g_histPage<pc-1)g_histPage++;
   BasketHistoryUpdate();
   ChartRedraw();
  }

void BasketHistoryPrevPage()
  {
   if(g_histPage>0)g_histPage--;
   BasketHistoryUpdate();
   ChartRedraw();
  }

void BasketHistoryDetectClosed()
  {
   int bc;double a,b,c,d,e;datetime f;
   GetBasketInfo(1,bc,a,b,c,d,e,f);
   int sc;double sa,sb,scf,sd,se;datetime sf;
   GetBasketInfo(-1,sc,sa,sb,scf,sd,se,sf);

   bool closed=(g_histPrevBuyCount>0&&bc==0)||
               (g_histPrevSellCount>0&&sc==0);

   if(closed)
     {
      BasketHistoryRebuild();
      g_histPage=0;
      BasketHistoryUpdate();
     }

   g_histPrevBuyCount=bc;
   g_histPrevSellCount=sc;
  }

void BasketHistoryHandleDrag()
  {
   if(g_basketHistoryLocked) return;

   int x=(int)ObjectGetInteger(0,BasketHistoryName("drag"),OBJPROP_XDISTANCE);
   int y=(int)ObjectGetInteger(0,BasketHistoryName("drag"),OBJPROP_YDISTANCE);

   long cw=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   long ch=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(cw>0) x=MathMax(0,MathMin(x,(int)cw-g_histW-4));
   if(ch>0) y=MathMax(0,MathMin(y,(int)ch-g_histH-4));

   g_histX=x;
   g_histY=y;
   BasketHistoryMoveAll(x,y);
   BasketHistorySavePosition();

   ObjectSetInteger(0,BasketHistoryName("drag"),OBJPROP_SELECTED,false);
   ChartRedraw();
  }

void UpdatePanel(double emaDir,double ema200,double stochMain,
                 double atrNow,double atrAvg,double closeNow)
  {
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   long spreadPts=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   int bc; double ba,bl,bf,bp,bll; datetime bt;
   GetBasketInfo(1,bc,ba,bl,bf,bp,bll,bt);

   int sc; double sa,sl,sf,sp,sll; datetime st;
   GetBasketInfo(-1,sc,sa,sl,sf,sp,sll,st);

   string signal=(closeNow>emaDir)?"BUY":"SELL";
   string trend=(closeNow>emaDir)?"UP":"DOWN";
   double ratio=(atrAvg>0)?atrNow/atrAvg:1.0;
   bool atrOK; string regime=GetATRRegime(ratio,atrOK);

   bool tradingOpen=CheckTradingHours();

   double dailyDD=(g_dayStartEquity>0)?
                  MathMax(0.0,-g_dailyProfit/g_dayStartEquity*100.0):0.0;
   double accDD=(g_accountBaselineEquity>0)?
                MathMax(0.0,(g_accountBaselineEquity-eq)/
                g_accountBaselineEquity*100.0):0.0;
   double peakDD=(g_accountPeakEquity>0)?
                 MathMax(0.0,(g_accountPeakEquity-eq)/
                 g_accountPeakEquity*100.0):0.0;

   ENUM_ACCOUNT_STATUS status=ACC_STATUS_SAFE;
   if(g_accountLocked || g_dailyLossHit)
      status=ACC_STATUS_LOCKED;
   else if(g_adaptiveDDMode!=DD_MODE_AGGRESSIVE ||
           dailyDD>=InpDailyLossPercent*0.6 ||
           accDD>=InpMaxAccountDrawdown*0.6 ||
           (InpUseTrailingPeakDD &&
            peakDD>=InpTrailingPeakDDPercent*0.6) ||
           IsATRSpikePaused())
      status=ACC_STATUS_RISK;

   color statusClr=(status==ACC_STATUS_LOCKED)?PANEL_RED:
                   (InpUseAdaptiveDD?AdaptiveDDModeColor():
                    (status==ACC_STATUS_RISK?PANEL_GOLD:PANEL_GREEN));
   string statusTxt=(status==ACC_STATUS_LOCKED)?"LOCKED":
                    (InpUseAdaptiveDD?AdaptiveDDModeText():
                     (status==ACC_STATUS_RISK?"RISK":"SAFE"));

   PanelText(PanelName("status"),"● "+statusTxt,statusClr);

   PanelText(PanelName("symbol"),_Symbol+"   "+PanelTF(),PANEL_TEXT);
   PanelText(PanelName("signal"),
             (signal=="BUY"?"^  BUY":"v  SELL"),
             signal=="BUY"?PANEL_GREEN:PANEL_RED);
   PanelText(PanelName("trend"),"Trend  "+trend,
             signal=="BUY"?PANEL_GREEN:PANEL_RED);

   string cur=AccountInfoString(ACCOUNT_CURRENCY);

   PanelText(PanelName("bal"),StringFormat("%s %.2f",cur,bal),PANEL_TEXT);
   PanelText(PanelName("eq"),StringFormat("%s %.2f",cur,eq),PANEL_TEXT);
   PanelText(PanelName("pl"),StringFormat("%+.2f",g_dailyProfit),
             g_dailyProfit>=0?PANEL_GREEN:PANEL_RED);

   PanelText(PanelName("buy0"),
             StringFormat("%d / %d   Orders",bc,InpMaxOpenOrdersBasket));
   PanelText(PanelName("buy1"),
             StringFormat("%.2f / %.2f   Lot",bl,InpMaxTotalLotBasket));
   PanelText(PanelName("buy2"),
             ba>0?StringFormat("Avg Price  %.2f",ba):"Avg Price  -");
   PanelText(PanelName("buy3"),
             StringFormat("P/L        %+.2f",bf),
             bf>=0?PANEL_GREEN:PANEL_RED);

   PanelText(PanelName("sell0"),
             StringFormat("%d / %d   Orders",sc,InpMaxOpenOrdersBasket));
   PanelText(PanelName("sell1"),
             StringFormat("%.2f / %.2f   Lot",sl,InpMaxTotalLotBasket));
   PanelText(PanelName("sell2"),
             sa>0?StringFormat("Avg Price  %.2f",sa):"Avg Price  -");
   PanelText(PanelName("sell3"),
             StringFormat("P/L        %+.2f",sf),
             sf>=0?PANEL_GREEN:PANEL_RED);

   PanelText(PanelName("sp"),
             StringFormat("%d pt%s",(int)spreadPts,
                          IsSpreadOK()?"":"  FILTER"),
             IsSpreadOK()?PANEL_TEXT:PANEL_RED);

   PanelText(PanelName("atr"),
             StringFormat("%.2f",atrNow),PANEL_TEXT);

   PanelText(PanelName("mar"),
             StringFormat("%.0f%%",marginLevel),
             marginLevel<InpMinMarginLevel*1.5?PANEL_GOLD:PANEL_GREEN);

   // DD is split into two compact lines so the mode text never overflows.
   PanelText(PanelName("dd"),
             StringFormat("%.1f%%",AdaptiveDDPercent()),
             AdaptiveDDModeColor());
   PanelText(PanelName("dd_mode"),
             AdaptiveDDModeText(),
             AdaptiveDDModeColor());

   PanelText(PanelName("tr"),
             tradingOpen?"●  OPEN":"●  CLOSED",
             tradingOpen?PANEL_GREEN:PANEL_RED);

   string exitMode=InpDisableTrailTP?"MANUAL":
                   (InpUseBasketTrailing?"TRAILING":
                   (InpUseATRBasedTP?"ATR TP":"FIXED TP"));
   PanelText(PanelName("ex"),exitMode,PANEL_TEXT);
   PanelText(PanelName("sig"),signal,
             signal=="BUY"?PANEL_GREEN:PANEL_RED);

   // Detail data - intentionally short to avoid text leaving the panel.
   PanelText(PanelName("detail0"),
             StringFormat("BUY  avg %.2f | next %.2f | CD %d",
                          ba,CalcNextLot(bc,bll),g_buyCooldownLeft),PANEL_MUTED);
   PanelText(PanelName("detail1"),
             StringFormat("SELL avg %.2f | next %.2f | CD %d",
                          sa,CalcNextLot(sc,sll),g_sellCooldownLeft),PANEL_MUTED);
   PanelText(PanelName("detail2"),
             StringFormat("Margin %.0f%% | Free %.2f",
                          marginLevel,AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
   PanelText(PanelName("detail3"),
             StringFormat("DD MODE %-10s | %.2f%%",AdaptiveDDModeText(),AdaptiveDDPercent()),AdaptiveDDModeColor());
   PanelText(PanelName("detail4"),
             StringFormat("Hours %02d-%02d | AutoLot %s",
                          InpTradingHourStart,InpTradingHourEnd,
                          InpAutoLotByBalance?"ON":"OFF"));
   PanelText(PanelName("detail5"),
             StringFormat("Cut Loss %s",
                          InpUseBasketLossPercent?
                          StringFormat("%.1f%% equity",InpBasketLossPercent):
                          (InpCutLossPerBasketUSD>0?
                           StringFormat("USD %.2f",InpCutLossPerBasketUSD):
                           "OFF")));
   PanelText(PanelName("detail6"),
             StringFormat("Exit %s | TP %s",exitMode,
                          InpUseBasketTrailing?"-":
                          (InpUseATRBasedTP?
                           StringFormat("%.0fp",atrNow/
                           SymbolInfoDouble(_Symbol,SYMBOL_POINT)*
                           InpATRTPMultiplier):
                           StringFormat("%.0fp",InpFixedTPPoints))));
   PanelText(PanelName("detail7"),
             StringFormat("Avg distance FIXED %.0fp | wait %s",
                          CalcAveragingDistancePts(),
                          InpAveragingWaitClose?"YES":"NO"));
   PanelText(PanelName("detail8"),
             StringFormat("Entry %s | Hedge %s",
                          InpFollowEMACooldownRules?"EMA":"DIRECT",
                          InpAllowBuySellTogether?"ON":"OFF"));
   PanelText(PanelName("detail9"),
             StringFormat("EMA%d %.2f | EMA200 %.2f",
                          InpEMADirPeriod,emaDir,ema200));
   PanelText(PanelName("detail10"),
             StringFormat("Stoch %.1f | EMA200 %s | Stoch %s",
                          stochMain,InpUseEMA200Filter?"ON":"OFF",
                          InpUseStochFilter?"ON":"OFF"));
   PanelText(PanelName("detail11"),
             StringFormat("ATR %.2f / %.2f | %s | Spike %s",
                          atrNow,atrAvg,regime,
                          IsATRSpikePaused()?"PAUSE":"OK"),
             IsATRSpikePaused()?PANEL_GOLD:PANEL_GREEN);
   string slModeText = "OFF";
   if(InpUseBrokerSL)
     {
      if(InpAveragingOrdersNoSL)
         slModeText = "ENTRY + BASKET TRAIL";
      else
         slModeText = StringFormat("ATR x%.1f",InpBrokerSL_ATR);
     }

   PanelText(PanelName("detail12"),
             StringFormat("Magic %d | Slip %dp | SL %s",
                          InpMagic,InpMaxSlippage,slModeText),
             PANEL_MUTED);
   PanelText(PanelName("detail13"),
             StringFormat("Target %s | Loss %s | Peak %.1f%%",
                          InpUseDailyProfitTarget?
                          StringFormat("%.1f%%",InpDailyProfitTargetPercent):"OFF",
                          InpUseDailyLossLimit?
                          StringFormat("%.1f%%",InpDailyLossPercent):"OFF",
                          peakDD),PANEL_MUTED);

   string resetTxt;
   if(!InpUseConditionalAutoReset) resetTxt="OFF";
   else if(!g_accountLocked) resetTxt="STANDBY";
   else resetTxt="LOCKED / EVAL";
   PanelText(PanelName("detail14"),
              StringFormat("AutoReset %s | Stable %d/%d | HALT %s",resetTxt,g_adaptiveDDStableBars,InpRecoveryStableBars,GetHaltReason()),
              g_accountLocked?PANEL_GOLD:PANEL_MUTED);
   PanelText(PanelName("detail15"),
              StringFormat("EntryGate: %.42s",g_entryBlockReason),
              g_entryBlockReason=="NONE"?PANEL_GREEN:PANEL_MUTED);

   // History is display-only and cheap to repaint. Keep its labels alive on
   // every tick so a tester redraw cannot leave only the card backgrounds.
   if(g_basketHistoryVisible) BasketHistoryUpdate();

   ChartRedraw();
  }

void PanelRefreshNow()
  {
   double emaDir,ema200,stochMain,closeNow,atrNow,atrAvg;
   if(!GetEntryIndicatorValues(emaDir,ema200,stochMain,closeNow)) return;
   if(!GetATRValues(atrNow,atrAvg)) return;
   UpdatePanel(emaDir,ema200,stochMain,atrNow,atrAvg,closeNow);
  }

void PanelToggleDetails()
  {
   g_panelDetailsOpen=!g_panelDetailsOpen;
   PanelApplyVisibility();
  }

void PanelToggleLock()
  {
   g_panelDragLocked=!g_panelDragLocked;
   PanelText(PanelName("lock"),g_panelDragLocked?"LOCKED":"LOCK");
  }

void PanelHandleDrag()
  {
   if(g_panelDragLocked) return;

   int x=(int)ObjectGetInteger(0,PanelName("drag"),OBJPROP_XDISTANCE);
   int y=(int)ObjectGetInteger(0,PanelName("drag"),OBJPROP_YDISTANCE);

   long cw=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   long ch=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);

   if(cw>0) x=MathMax(0,MathMin(x,(int)cw-g_panelW-4));
   if(ch>0) y=MathMax(0,MathMin(y,(int)ch-g_panelH-4));

   g_panelX=x;
   g_panelY=y;

   PanelMoveAll(x,y);
   RoyalQuantumPositionHeaderIcon();
   PanelSavePosition();

   ObjectSetInteger(0,PanelName("drag"),OBJPROP_SELECTED,false);
   ChartRedraw();
  }

//---- END PanelUI.mqh ----


//---- urutan include PENTING: Globals dulu (deklarasi bersama & enum),
//     lalu modul yang TIDAK saling bergantung fungsi (MoneyManagement,
//     ATRManager, EntryManager, RiskManager - RiskManager forward-declare
//     CloseBasket/CloseAllPositions), baru BasketManager (implementasi
//     asli fungsi close), lalu TrailingManager, lalu PanelUI paling akhir
//     karena dia memakai fungsi dari SEMUA modul lain.
#include "WebBridge.mqh"

input group "=== Reset Manual (MODULE 2) ==="
input bool     InpManualUnlockAccount = false; // TRUE sekali untuk reset lock akun + baseline
input bool     InpAutoResetLockInTester = true; // Tester: bersihkan persistent lock lama agar BT baru tidak langsung HALT


//+------------------------------------------------------------------+
int OnInit()
  {
   RoyalQuantumLicenseCheck();
   EventSetTimer(1);
   if(!g_licenseOK)
     {
      RoyalQuantumCreateLicenseOverlay();
      return INIT_SUCCEEDED;
     }

   if(ATR_Init() != INIT_SUCCEEDED)
     {
      Print("Gagal membuat handle ATR");
      return INIT_FAILED;
     }
   if(EntryManager_Init() != INIT_SUCCEEDED)
     {
      Print("Gagal membuat handle EMA/Stochastic");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);

   RiskManager_Init(); // baca/inisialisasi baseline & status lock PERSISTEN
    AdaptiveDD_Init();

   if(InpManualUnlockAccount)
      ResetAccountLock(); // reset manual eksplisit dari user (Module 2)

   g_dayStart       = TimeCurrent();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyProfit     = 0;
   g_dailyTargetHit  = false;
   g_dailyLossHit    = false;

   if(InpShowPanel || InpShowBasketHistory || InpShowMTFDashboard) CreatePanel();
   RoyalQuantumCreateBranding();
   RoyalQuantumPositionHeaderIcon();
   WebBridge_Init();
   WebBridge_ExportStatus();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   RoyalQuantumRefreshLicense();
   // Deferred basket-history refresh: process after MT5 has completed the
   // position/deal transaction, preventing the temporary empty-panel state.
   BasketHistoryProcessPendingRefresh();
   if(g_mtfDashboardVisible || InpShowMTFDashboard) MTFUpdateDashboard();
   WebBridge_ProcessCommand();
   WebBridge_CheckTarget();
   WebBridge_ExportStatus();
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   RoyalQuantumDeleteLicenseOverlay();
   RoyalQuantumDeleteBranding();
   BasketHistorySavePosition();
   MTFSavePosition();
   if(hEMADir!=INVALID_HANDLE) IndicatorRelease(hEMADir);
   if(hEMA200!=INVALID_HANDLE) IndicatorRelease(hEMA200);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hMTFDirM5!=INVALID_HANDLE) IndicatorRelease(hMTFDirM5);
   if(hMTF200M5!=INVALID_HANDLE) IndicatorRelease(hMTF200M5);
   if(hMTFStochM5!=INVALID_HANDLE) IndicatorRelease(hMTFStochM5);
   if(hMTFDirH4!=INVALID_HANDLE) IndicatorRelease(hMTFDirH4);
   if(hMTF200H4!=INVALID_HANDLE) IndicatorRelease(hMTF200H4);
   if(hMTFStochH4!=INVALID_HANDLE) IndicatorRelease(hMTFStochH4);
   ObjectsDeleteAll(0, PFX);
  }


//+------------------------------------------------------------------+
//| Floating panel mouse interaction                                 |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Floating panel mouse interaction                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_licenseOK)
     {
      if(id==CHARTEVENT_CHART_CHANGE) RoyalQuantumPositionLicenseOverlay();
      return;
     }

   if(id==CHARTEVENT_CHART_CHANGE)
     {
      RoyalQuantumPositionBranding();
      RoyalQuantumPositionHeaderIcon();

      // Re-clamp both floating dashboards after a chart resize.
      PanelHandleDrag();
      BasketHistoryHandleDrag();
      MTFHandleDrag();
      RQResolveDashboardOverlap();
      ChartRedraw();
      return;
     }

   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam==MTFName("hide")) { MTFSetVisibility(false); return; }
      if(sparam==MTFName("tab")) { MTFSetVisibility(true); MTFUpdateDashboard(); return; }
      if(sparam==MTFName("lock"))
        {
         g_mtfDashboardLocked=!g_mtfDashboardLocked;
         PanelText(MTFName("lock"),g_mtfDashboardLocked?"LOCKED":"LOCK");
         return;
        }
      if(sparam==MTFName("close"))
        {
         MTFSetVisibility(false);
         return;
        }
      if(sparam==PanelName("hide"))
        {
         PanelSetMainVisibility(false);
         return;
        }

      if(sparam==PanelName("main_tab"))
        {
         PanelSetMainVisibility(true);
         // Force both visibility state and text values to be refreshed.
         PanelApplyVisibility();
         PanelRefreshNow();
         return;
        }

      if(sparam==PanelName("detail_btn"))
        {
         PanelToggleDetails();
         return;
        }

      if(sparam==PanelName("history_btn")) { BasketHistoryToggle(); return; }
      if(sparam==BasketHistoryName("hide") || sparam==BasketHistoryName("tab")) { BasketHistoryToggle(); return; }
      if(sparam==BasketHistoryName("prev")) { BasketHistoryPrevPage(); return; }
      if(sparam==BasketHistoryName("next")) { BasketHistoryNextPage(); return; }

      if(sparam==PanelName("lock"))
        {
         PanelToggleLock();
         return;
        }

      if(sparam==PanelName("close"))
        {
         ObjectSetInteger(0,PanelName("bg"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         ObjectSetInteger(0,PanelName("drag"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         ObjectSetInteger(0,PanelName("brand"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         ObjectSetInteger(0,PanelName("status"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         ObjectSetInteger(0,PanelName("lock"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         ObjectSetInteger(0,PanelName("close"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         for(int i=0;i<16;i++)
            ObjectSetInteger(0,PanelName("detail"+IntegerToString(i)),
                             OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         return;
        }
     }

   if(id==CHARTEVENT_OBJECT_DRAG)
     {
      if(sparam==PanelName("drag"))
        {
         PanelHandleDrag();
         RQResolveDashboardOverlap();
         return;
        }
      if(sparam==BasketHistoryName("drag")) { BasketHistoryHandleDrag(); RQResolveDashboardOverlap(); return; }
      if(sparam==MTFName("drag")) { MTFHandleDrag(); RQResolveDashboardOverlap(); return; }
     }
  }

//+------------------------------------------------------------------+
//| v2.29 - restore classic basket history UI, keep realtime fix    |
//+------------------------------------------------------------------+
//| Broker trailing SL is a basket-level safety trigger. If one      |
//| position is stopped, close remaining positions in that basket.   |
//+------------------------------------------------------------------+
// Refresh CLOSED basket history only when a trade transaction actually
// completes the last position of a basket. This is event-driven, not
// dependent on a new candle or a polling tick.
void BasketHistoryRefreshAfterTrade(const MqlTradeTransaction &trans)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;

   // A closing deal means the basket history may have changed. Do not try to
   // rebuild inside OnTradeTransaction: MT5 can still be committing the deal
   // to the account history at this exact moment.
   g_basketHistoryPendingRefresh=true;
   g_basketHistoryRefreshDue=TimeCurrent()+2;
   g_basketHistoryRefreshRetries=0;
  }

void BasketHistoryProcessPendingRefresh()
  {
   if(!g_basketHistoryPendingRefresh)return;
   if(TimeCurrent()<g_basketHistoryRefreshDue)return;

   g_basketHistoryRefreshRetries++;

   // Rebuild only after MT5 has settled the transaction into history.
   // If HistorySelect is temporarily unavailable, DO NOT clear the visible
   // cards. Keep the old data and retry.
   bool rebuilt=BasketHistoryRebuild();
   if(rebuilt)
     {
      g_histPage=0;
      BasketHistoryApplyVisibility();
      BasketHistoryUpdate();
      ChartRedraw();

      // Even when HistorySelect succeeds, the newest closing deal can become
      // visible one event later. Keep a few short verification passes.
      if(g_basketHistoryRefreshRetries<6)
        {
         g_basketHistoryRefreshDue=TimeCurrent()+1;
         return;
        }
      g_basketHistoryPendingRefresh=false;
      g_basketHistoryRefreshRetries=0;
      return;
     }

   // History API was not ready. Retry without touching the current UI.
   if(g_basketHistoryRefreshRetries<6)
     {
      g_basketHistoryRefreshDue=TimeCurrent()+1;
      return;
     }
   g_basketHistoryPendingRefresh=false;
   g_basketHistoryRefreshRetries=0;
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Basket History is refreshed independently of the broker-SL basket handler.
   // This must run even when InpCloseWholeBasketOnTrailSL=false.
   BasketHistoryRefreshAfterTrade(trans);

   if(!InpCloseWholeBasketOnTrailSL) return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   long reason=HistoryDealGetInteger(trans.deal,DEAL_REASON);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   if(reason!=DEAL_REASON_SL) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;

   long dealType=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
   if(dealType==DEAL_TYPE_SELL)
     {
      int count; double a,b,c,d,e; datetime f;
      GetBasketInfo(1,count,a,b,c,d,e,f);
      if(count>0) CloseBasketEx(1,false);
     }
   else if(dealType==DEAL_TYPE_BUY)
     {
      int count; double a,b,c,d,e; datetime f;
      GetBasketInfo(-1,count,a,b,c,d,e,f);
      if(count>0) CloseBasketEx(-1,false);
     }
  }

void OnTick()
  {
   if(!g_licenseOK) return;

   WebBridge_ProcessCommand();
   WebBridge_CheckTarget();

   // Process basket-history updates before any indicator/data early-return.
   // This guarantees the history dashboard is independent from entry logic.
   BasketHistoryProcessPendingRefresh();
   MTFUpdateStates();
   double emaDir, ema200, stochMain, closeNow;
   if(!GetEntryIndicatorValues(emaDir, ema200, stochMain, closeNow))
     {
      WebBridge_ExportStatus();
      return;
     }

   double atrNow, atrAvg;
   if(!GetATRValues(atrNow, atrAvg))
     {
      WebBridge_ExportStatus();
      return;
     }

   // ---- dihitung sekali di awal tick, dipakai utk filter entry MAUPUN Module 2C ----
   double ratio = (atrAvg>0) ? atrNow/atrAvg : 1.0;
   bool atrOK;
   GetATRRegime(ratio, atrOK);

   double slopePts = 0.0;
   GetEMASlopePoints(slopePts); // kalau gagal (data kurang), slopePts tetap 0 -> otomatis dianggap "belum sehat"

   // ---- reset harian (equity awal hari, target/loss harian) ----
   MqlDateTime now, start;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(g_dayStart, start);
   if(now.day != start.day || now.mon != start.mon || now.year != start.year)
     {
      g_dayStart       = TimeCurrent();
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyTargetHit = false;
      g_dailyLossHit   = false;
     }
   g_dailyProfit = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity;

   UpdateCooldownOnNewBar();
   UpdateATRSpikePause(atrNow, atrAvg);       // Module 12
   UpdateAdaptiveDD(slopePts, atrOK);        // Module 2D
   CheckDailyLimits();                        // Module 1 + Module 2 + Module 2B (bisa LockAccount permanen)

   if(g_accountLocked && InpUseConditionalAutoReset)
      CheckConditionalAutoReset(atrOK, slopePts); // Module 2C: bisa langsung ResetAccountLock() di tick ini juga

   bool halted = (g_dailyTargetHit || g_dailyLossHit || g_accountLocked || g_adaptiveDDHalted || g_webPaused);
   static string lastHaltReason = "";
   string haltReason = GetHaltReason();
   if(haltReason != lastHaltReason)
     {
      if(haltReason != "NONE") Print("[v2.20 HALT] ",haltReason," | ",g_accountLockReason);
      else Print("[v2.20 RESUME] EA kembali mengizinkan entry.");
      lastHaltReason = haltReason;
     }
   if(!halted)
     {
      // exit dicek dulu (termasuk cut-loss % equity - Module 3) sebelum entry baru
      ManageBasketExit(1, atrNow);
      ManageBasketExit(-1, atrNow);

      ProcessBasketEntry(1,  emaDir, ema200, stochMain, atrOK, closeNow, atrNow);
      ProcessBasketEntry(-1, emaDir, ema200, stochMain, atrOK, closeNow, atrNow);
     }
   else
     {
      // tetap kelola exit basket yang mungkin masih terbuka (mis. baru saja
      // status berubah jadi halted di tick ini) supaya tidak "nyangkut" tanpa
      // proteksi trailing/cut-loss, tapi TIDAK ada entry/averaging baru.
      ManageBasketExit(1, atrNow);
      ManageBasketExit(-1, atrNow);
     }

   if(TimeCurrent()-g_lastHeartbeatTime>=300)
     {
      g_lastHeartbeatTime=TimeCurrent();
      Print(StringFormat("[v2.20 HEARTBEAT] ACTIVE | Equity %.2f | DD %.2f%% | Mode %s | Gate %s | Halt %s",
                         AccountInfoDouble(ACCOUNT_EQUITY),AdaptiveDDPercent(),
                         AdaptiveDDModeText(),g_entryBlockReason,GetHaltReason()));
     }

   if(InpShowPanel)
      UpdatePanel(emaDir, ema200, stochMain, atrNow, atrAvg, closeNow);
   if(g_mtfDashboardVisible || InpShowMTFDashboard)
      MTFUpdateDashboard();

   WebBridge_ExportStatus();
  }
//+------------------------------------------------------------------+