//+------------------------------------------------------------------+
//| Globals.mqh                                                      |
//| RoyalViento_Clone_EA v2.03                                       |
//| State bersama antar modul. Di-include PALING ATAS di file utama, |
//| sebelum modul lain, karena semua modul lain mengasumsikan        |
//| variabel di sini sudah dideklarasikan (compile unit = textual    |
//| concatenation di MQL5).                                          |
//+------------------------------------------------------------------+
#ifndef __RV_GLOBALS_MQH__
#define __RV_GLOBALS_MQH__

#include <Trade\Trade.mqh>
CTrade trade;

string PFX = "RV_"; // prefix objek dashboard

input group "=== General ==="
input int      InpMagic              = 20260707;   // Magic number
input ENUM_TIMEFRAMES InpTF          = PERIOD_M1;   // Timeframe analisis
input bool     InpShowPanel          = true;        // Tampilkan panel info di chart
input int      InpMaxSlippage        = 20;          // Slippage maksimal (poin)
input string   InpOrderComment       = "EA RV 2.03";// Komen order
input double   InpCloseBufferPoints  = 10.0;        // Buffer poin: EA close sedikit lebih awal dari ambang exit

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

#endif // __RV_GLOBALS_MQH__
//+------------------------------------------------------------------+
