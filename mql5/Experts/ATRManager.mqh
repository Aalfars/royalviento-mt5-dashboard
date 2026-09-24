//+------------------------------------------------------------------+
//| ATRManager.mqh                                                   |
//| RoyalViento_Clone_EA v2.03                                       |
//| MODULE 5 - ATR Dynamic Averaging:                                |
//|  Jarak averaging tidak lagi angka statis (v2.02: 500 poin utk    |
//|  semua kondisi pasar), tapi mengikuti ATR saat ini supaya grid   |
//|  melebar otomatis saat volatilitas naik dan menyempit saat sepi. |
//| MODULE 12 - News Volatility Block:                               |
//|  Jika ATR melonjak tajam dibanding rata-rata (indikasi news),    |
//|  EA pause entry/averaging beberapa candle.                       |
//+------------------------------------------------------------------+
#ifndef __RV_ATRMANAGER_MQH__
#define __RV_ATRMANAGER_MQH__

input group "=== Filter & Averaging ATR ==="
input bool     InpUseATRFilter        = true;  // Aktifkan filter volatilitas ATR sebelum open posisi baru
input int      InpATRPeriod           = 14;    // Periode ATR
input int      InpATRAvgBars          = 20;    // Jumlah candle utk hitung rata-rata ATR (baseline)
input double   InpATRRatioMin         = 0.5;   // Batas bawah: ATR skrg harus >= (rata-rata x ratio ini)
input double   InpATRRatioMax         = 2.0;   // Batas atas: ATR skrg harus <= (rata-rata x ratio ini)

input group "=== MODULE 5: ATR Dynamic Averaging ==="
input double   InpATRDistanceMultiplier = 2.5;   // Jarak averaging = ATR(14) x multiplier ini
input double   InpMinAveragingDistance  = 700.0; // Batas bawah jarak averaging (poin)
input double   InpMaxAveragingDistance  = 2200.0;// Batas atas jarak averaging (poin)

input group "=== MODULE 12: News / ATR Spike Block ==="
input bool     InpAvoidHighATRSpike   = true;  // Aktifkan pause saat ATR melonjak (indikasi news)
input double   InpATRSpikeRatio       = 3.0;   // ATR skrg >= rata-rata x rasio ini dianggap spike
input int      InpATRSpikePauseBars   = 5;     // Jumlah candle pause setelah spike terdeteksi

//---- state internal modul ini ----
datetime g_atrSpikeLastBarTime = 0;
int      g_atrSpikePauseLeft   = 0;

//+------------------------------------------------------------------+
int ATR_Init()
  {
   hATR = iATR(_Symbol, InpTF, InpATRPeriod);
   return (hATR != INVALID_HANDLE) ? INIT_SUCCEEDED : INIT_FAILED;
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
//| MODULE 5: jarak averaging dinamis, di-clamp ke Min/Max distance  |
//+------------------------------------------------------------------+
double CalcAveragingDistancePts(double atrNowPrice)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atrPts = atrNowPrice / point;
   double dist = atrPts * InpATRDistanceMultiplier;
   if(dist < InpMinAveragingDistance) dist = InpMinAveragingDistance;
   if(dist > InpMaxAveragingDistance) dist = InpMaxAveragingDistance;
   return dist;
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

#endif // __RV_ATRMANAGER_MQH__
//+------------------------------------------------------------------+
