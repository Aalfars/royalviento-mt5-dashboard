//+------------------------------------------------------------------+
//| BasketManager.mqh                                                |
//| RoyalViento_Clone_EA v2.03                                       |
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
#ifndef __RV_BASKETMANAGER_MQH__
#define __RV_BASKETMANAGER_MQH__

input group "=== Basket / Averaging ==="
input bool     InpAveragingWaitClose  = false; // true = averaging tunggu candle close dulu | false = langsung
input int      InpMaxAveragingCycle   = 8;     // Max averaging per cycle (lot reset setelah basket ditutup)
input int      InpCooldownCandles     = 5;     // Jumlah candle tunggu setelah basket ditutup NORMAL sebelum boleh open lagi
input int      InpMinSecondsBetweenAvg= 3;     // Jeda minimum (detik) antar-averaging, anti burst saat spike
input bool     InpAllowBuySellTogether= false; // true = Buy & Sell boleh bareng | false = cuma 1 arah dalam satu waktu

input group "=== MODULE 4: Exposure Cap ==="
input double   InpMaxTotalLotBasket   = 0.50;  // Total lot maksimum per basket
input int      InpMaxOpenOrdersBasket = 8;     // Jumlah order maksimum per basket

input group "=== MODULE 6: Hard Stop Loss Broker ==="
input bool     InpUseBrokerSL         = true;  // Wajibkan SL riil di broker utk setiap order
input double   InpBrokerSL_ATR        = 3.0;   // SL = ATR(14) x multiplier ini

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
   long minPts = MathMax(stopLevelPts, freezeLevelPts);

   double slDistPts = (atrNowPrice/point) * InpBrokerSL_ATR;
   if(slDistPts < minPts + 10) slDistPts = minPts + 10; // +buffer kecil di atas minimum broker

   double slDist = slDistPts * point;
   if(direction==1)  return NormalizeDouble(entryPrice - slDist, _Digits);
   else              return NormalizeDouble(entryPrice + slDist, _Digits);
  }

//+------------------------------------------------------------------+
//| Kirim order Buy/Sell dengan SL opsional (Module 6), lalu cek     |
//| hasilnya (temuan #6 review v2.02: hasil order dulu tidak dicek). |
//+------------------------------------------------------------------+
bool SendBasketOrder(int direction, double lot, double atrNowPrice)
  {
   bool ok;
   double price, sl = 0;

   if(direction==1)
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(InpUseBrokerSL) sl = CalcBrokerSLPrice(1, price, atrNowPrice);
      ok = trade.Buy(lot, _Symbol, price, sl, 0, InpOrderComment);
     }
   else
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(InpUseBrokerSL) sl = CalcBrokerSLPrice(-1, price, atrNowPrice);
      ok = trade.Sell(lot, _Symbol, price, sl, 0, InpOrderComment);
     }

   if(!ok)
     {
      Print("Order ", (direction==1?"BUY":"SELL"), " GAGAL. lot=", lot,
            " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
     }

   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(direction==1) { g_buyLastAvgBarTime = curBar; g_buyLastAvgTime = TimeCurrent(); }
   else             { g_sellLastAvgBarTime = curBar; g_sellLastAvgTime = TimeCurrent(); }
   return true;
  }

//+------------------------------------------------------------------+
//| Buka posisi awal ATAU averaging pada basket tertentu.            |
//| direction: 1 = Buy, -1 = Sell                                     |
//+------------------------------------------------------------------+
void ProcessBasketEntry(int direction, double emaDir, double ema200, double stochMain,
                         bool atrOK, double closeNow, double atrNow)
  {
   if(IsATRSpikePaused()) return;        // Module 12
   if(!IsSpreadOK()) return;             // Module 9
   if(IsBasketCooldownActive(direction)) return; // Module 10

   int count; double avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot;
   datetime lastOpenTime;
   GetBasketInfo(direction, count, avgPrice, totalLots, floatingProfit, lastOpenPrice, lastLot, lastOpenTime);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // ---- ENTRY PERTAMA BASKET ----
   if(count == 0)
     {
      int otherCount; double a,b,c,d,e; datetime f;
      GetBasketInfo(-direction, otherCount, a, b, c, d, e, f);
      if(otherCount > 0 && !InpAllowBuySellTogether) return;

      if(InpFollowEMACooldownRules)
        {
         if(direction==1  && g_buyCooldownLeft  > 0) return;
         if(direction==-1 && g_sellCooldownLeft > 0) return;
         if(InpUseATRFilter && !atrOK) return;
        }

      if(!CheckEntrySignal(direction, emaDir, ema200, stochMain, closeNow)) return;

      double lot = CalcNextLot(0, 0);
      double price = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ENUM_ORDER_TYPE ot = (direction==1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!IsMarginSafeForOrder(ot, lot, price)) return; // Module 7

      SendBasketOrder(direction, lot, atrNow);
      return;
     }

   // ---- AVERAGING ----
   if(count >= InpMaxAveragingCycle) return;
   if(totalLots >= InpMaxTotalLotBasket) return;      // Module 4 (lot cap)
   if(count >= InpMaxOpenOrdersBasket) return;         // Module 4 (order count cap)

   if(InpAveragingWaitClose)
     {
      datetime curBar = iTime(_Symbol, InpTF, 0);
      datetime lastAvgBar = (direction==1) ? g_buyLastAvgBarTime : g_sellLastAvgBarTime;
      if(curBar == lastAvgBar) return;
     }

   // anti-burst: jeda minimum antar averaging dalam detik
   datetime lastAvgTime = (direction==1) ? g_buyLastAvgTime : g_sellLastAvgTime;
   if(TimeCurrent() - lastAvgTime < InpMinSecondsBetweenAvg) return;

   double distancePts = CalcAveragingDistancePts(atrNow); // Module 5: dinamis, bukan statis 500pt

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

   double nextLot = CalcNextLot(count, lastLot);
   // jangan sampai averaging berikutnya menembus cap total lot basket
   if(totalLots + nextLot > InpMaxTotalLotBasket)
     {
      nextLot = NormalizeLot(InpMaxTotalLotBasket - totalLots);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(nextLot < minLot) return; // sisa kapasitas terlalu kecil, skip
     }

   double price = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ENUM_ORDER_TYPE ot = (direction==1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!IsMarginSafeForOrder(ot, nextLot, price)) return; // Module 7

   SendBasketOrder(direction, nextLot, atrNow);
  }

#endif // __RV_BASKETMANAGER_MQH__
//+------------------------------------------------------------------+
