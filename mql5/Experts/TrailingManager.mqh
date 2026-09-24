//+------------------------------------------------------------------+
//| TrailingManager.mqh                                              |
//| RoyalViento_Clone_EA v2.03                                       |
//| Exit basket: cut-loss % equity (Module 3, dicek pertama = rem    |
//| darurat), lalu trailing basket ATAU Take Profit (fixed poin      |
//| ATAU ATR-based, mengikuti volatilitas seperti Module 5).         |
//| FIX v2.01 (dipertahankan): trailing peak pakai if/else langsung  |
//| ke g_buyPeakPts/g_sellPeakPts, BUKAN reference dari ternary yang |
//| tidak reliable di MQL5.                                          |
//+------------------------------------------------------------------+
#ifndef __RV_TRAILINGMANAGER_MQH__
#define __RV_TRAILINGMANAGER_MQH__

input group "=== Trailing & Take Profit Basket ==="
input bool     InpUseBasketTrailing  = true;   // Aktifkan trailing basket? (false = pakai Take Profit)
input int      InpTrailStartPoints   = 100;    // Trailing start (poin)
input int      InpTrailStopDistance  = 50;     // Trailing stop distance (poin)
input bool     InpDisableTrailTP     = false;  // Matikan total trailing & TP (EA cuma open+averaging, close manual)
input bool     InpUseATRBasedTP      = true;   // true = TP mengikuti ATR | false = TP poin tetap
input double   InpATRTPMultiplier    = 4.0;    // TP = ATR(14) x multiplier ini (jika InpUseATRBasedTP=true)
input double   InpFixedTPPoints      = 3000.0; // Take Profit tetap (poin), dipakai jika InpUseATRBasedTP=false

//+------------------------------------------------------------------+
void ManageBasketExit(int direction, double atrNow)
  {
   int count; double avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot;
   datetime lastOpenTime;
   GetBasketInfo(direction, count, avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot, lastOpenTime);
   if(count == 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // --- MODULE 3: cut loss basket berbasis % equity (rem darurat, dicek duluan) ---
   if(CheckBasketCutLoss(floatingProfit, totalLots))
     {
      CloseBasketEx(direction, true); // true = trigger cooldown menit-based Module 10
      return;
     }

   if(InpDisableTrailTP) return; // EA cuma open+averaging, close manual oleh user

   double curPrice = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPts = (direction==1) ? (curPrice - avgPrice)/point
                                      : (avgPrice - curPrice)/point;

   if(InpUseBasketTrailing)
     {
      if(profitPts >= InpTrailStartPoints)
        {
         double bufferPts = InpCloseBufferPoints;
         if(direction==1)
           {
            if(profitPts > g_buyPeakPts) g_buyPeakPts = profitPts;
            if(profitPts <= (g_buyPeakPts - InpTrailStopDistance + bufferPts))
              {
               CloseBasketEx(direction, false);
               return;
              }
           }
         else
           {
            if(profitPts > g_sellPeakPts) g_sellPeakPts = profitPts;
            if(profitPts <= (g_sellPeakPts - InpTrailStopDistance + bufferPts))
              {
               CloseBasketEx(direction, false);
               return;
              }
           }
        }
     }
   else
     {
      double tpPts;
      if(InpUseATRBasedTP)
        {
         tpPts = (atrNow/point) * InpATRTPMultiplier;
        }
      else
        {
         tpPts = InpFixedTPPoints;
        }

      if(profitPts >= (tpPts - InpCloseBufferPoints))
        {
         CloseBasketEx(direction, false);
         return;
        }
     }
  }

#endif // __RV_TRAILINGMANAGER_MQH__
//+------------------------------------------------------------------+
