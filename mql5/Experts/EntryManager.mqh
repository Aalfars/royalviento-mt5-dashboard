//+------------------------------------------------------------------+
//| EntryManager.mqh                                                 |
//| RoyalViento_Clone_EA v2.03                                       |
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
#ifndef __RV_ENTRYMANAGER_MQH__
#define __RV_ENTRYMANAGER_MQH__

input group "=== Arah Entry (EMA) ==="
input int      InpEMADirPeriod       = 100;   // Periode EMA untuk menentukan arah open (Buy/Sell)
input int      InpEMA200Period       = 200;   // Periode EMA200 (filter tren)
input bool     InpUseEMA200Filter    = true;  // Aktifkan filter EMA200 (trend besar) sebelum open posisi baru
input bool     InpUseStochFilter     = true;  // Aktifkan filter Stochastic sebelum open posisi baru

input group "=== Filter Stochastic ==="
input int      InpStochK             = 5;     // Stochastic %K period
input int      InpStochD             = 3;     // Stochastic %D period
input int      InpStochSlowing       = 3;     // Stochastic slowing
input double   InpStochOversold      = 20.0;  // Ambang oversold (Buy butuh Stoch di bawah ini)
input double   InpStochOverbought    = 80.0;  // Ambang overbought (Sell butuh Stoch di atas ini)

input group "=== MODULE 11: Trend Strength Filter (EMA Slope) ==="
input bool     InpUseEMASlope        = true;  // Aktifkan filter kemiringan EMA (hindari sideways)
input int      InpEMASlopeBars       = 5;     // Jumlah candle ke belakang utk hitung slope
input double   InpEMASlopeMin        = 15.0;  // Slope minimum (poin per InpEMASlopeBars candle)

input group "=== Mode Entry ==="
input bool     InpFollowEMACooldownRules = true; // true = open ikut aturan EMA/cooldown | false = Buy & Sell langsung

input group "=== Jam Trading ==="
input int      InpTradingHourStart   = 0;   // Jam mulai trading (0-23, waktu server MT5)
input int      InpTradingHourEnd     = 24;  // Jam akhir trading (0-23, waktu server MT5)

//+------------------------------------------------------------------+
int EntryManager_Init()
  {
   hEMADir = iMA(_Symbol, InpTF, InpEMADirPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   hStoch  = iStochastic(_Symbol, InpTF, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);

   if(hEMADir==INVALID_HANDLE || hEMA200==INVALID_HANDLE || hStoch==INVALID_HANDLE)
      return INIT_FAILED;
   return INIT_SUCCEEDED;
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
   if(InpFollowEMACooldownRules)
     {
      if(!CheckTradingHours()) return false;

      bool trendUp   = (closeNow > emaDir) && (!InpUseEMA200Filter || (emaDir > ema200));
      bool trendDown = (closeNow < emaDir) && (!InpUseEMA200Filter || (emaDir < ema200));

      bool stochOKBuy  = (!InpUseStochFilter) || (stochMain < InpStochOverbought);
      bool stochOKSell = (!InpUseStochFilter) || (stochMain > InpStochOversold);

      if(InpUseEMASlope)
        {
         double slopePts;
         if(!GetEMASlopePoints(slopePts)) return false;
         if(slopePts < InpEMASlopeMin) return false;
        }

      if(direction==1)  return (trendUp   && stochOKBuy);
      if(direction==-1) return (trendDown && stochOKSell);
      return false;
     }
   else
     {
      // "Buy & Sell langsung": lewati cooldown & filter Stoch/ATR/EMA200/Slope,
      // tetap pakai arah dasar dari EMA vs Close supaya tidak asal arah.
      if(direction==1)  return (closeNow > emaDir);
      if(direction==-1) return (closeNow < emaDir);
      return false;
     }
  }

#endif // __RV_ENTRYMANAGER_MQH__
//+------------------------------------------------------------------+
