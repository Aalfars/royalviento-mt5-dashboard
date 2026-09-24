//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| RoyalViento_Clone_EA v2.04                                       |
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
#ifndef __RV_RISKMANAGER_MQH__
#define __RV_RISKMANAGER_MQH__

input group "=== MODULE 1: Daily Risk Kill Switch ==="
input bool     InpUseDailyLossLimit   = true;   // Aktifkan batas rugi harian (% equity awal hari)
input double   InpDailyLossPercent    = 15.0;   // Batas rugi harian (%)
input bool     InpUseDailyProfitTarget= true;   // Aktifkan target profit harian (% equity awal hari)
input double   InpDailyProfitTargetPercent = 8.0; // Target profit harian (%)

input group "=== MODULE 2: Total Account Drawdown Kill Switch ==="
input bool     InpUseMaxAccountDD     = true;   // Aktifkan kill switch drawdown total akun
input double   InpMaxAccountDrawdown  = 30.0;   // Batas drawdown total dari modal awal (%)
input bool     InpResetLockOnNewDeposit = false;// true = auto-reset baseline kalau balance naik signifikan (lihat catatan di kode)

input group "=== MODULE 2B: Trailing Peak Drawdown Kill Switch ==="
input bool     InpUseTrailingPeakDD     = false;  // Aktifkan kill switch drawdown dari PEAK equity tertinggi (bukan modal awal)
input double   InpTrailingPeakDDPercent = 20.0;   // Batas drawdown dari peak equity tertinggi (%)

input group "=== MODULE 2C: Auto-Reset Bersyarat Kondisi Pasar ==="
input bool     InpUseConditionalAutoReset   = false; // Aktifkan auto-reset otomatis (hanya berlaku kalau akun sedang locked). OPT-IN, default OFF.
input int      InpAutoResetMinDays          = 7;     // Minimum hari sejak lock sebelum auto-reset mulai dipertimbangkan
input int      InpAutoResetStableBarsNeeded = 30;    // Jumlah candle berturut-turut ATR normal & EMA slope kuat sebelum reset otomatis dieksekusi

input group "=== MODULE 3: Basket Cut Loss (% Equity) ==="
input bool     InpUseBasketLossPercent= true;   // true = cut-loss basket berbasis % equity | false = pakai nominal $
input double   InpBasketLossPercent   = 5.0;    // Cut loss per basket (% equity saat ini)
input double   InpCutLossPerBasketUSD = 0.0;    // Cut loss per basket nominal USD (otomatis dikonversi ke currency akun, 0=off)

input group "=== MODULE 7: Margin Safety ==="
input bool     InpUseMarginSafety     = true;   // Aktifkan cek margin sebelum entry/averaging
input double   InpMinMarginLevel      = 300.0;  // Margin Level minimum (%) yang wajib tersisa SETELAH entry
input double   InpReserveFreeMarginUSD = 200.0;  // Reserve free margin dalam USD (otomatis dikonversi ke currency akun)

input group "=== MODULE 9: Spread Filter ==="
input bool     InpUseSpreadFilter     = true;   // Aktifkan filter spread
input int      InpMaxSpreadPoints     = 300;    // Spread maksimum (poin) - berlaku utk entry & averaging

input group "=== MODULE 10: Basket Cooldown Recovery ==="
input int      InpBasketCooldownMinutes = 60;   // Jeda (menit) setelah basket kena cut-loss sebelum boleh buka basket baru di arah sama

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

#endif // __RV_RISKMANAGER_MQH__
//+------------------------------------------------------------------+
