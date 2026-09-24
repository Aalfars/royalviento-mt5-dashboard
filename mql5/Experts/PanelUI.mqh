//+------------------------------------------------------------------+
//| PanelUI.mqh                                                      |
//| RoyalViento_Clone_EA v2.04                                       |
//| Dashboard panel sesuai mockup Bagian 8 dokumen proyek:            |
//| Balance/Equity/Today P/L, basket buy/sell, Daily DD, Account DD, |
//| status SAFE (hijau) / RISK (kuning) / LOCKED (merah).            |
//+------------------------------------------------------------------+
#ifndef __RV_PANELUI_MQH__
#define __RV_PANELUI_MQH__

void CreatePanel()
  {
   ObjectsDeleteAll(0, PFX);

   int x = 15, y = 15, w = 480, lineH = 18;
   int totalLines = 21;
   int h = 34 + totalLines*lineH;

   string bg = PFX+"bg";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x-6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y-6);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'8,10,30');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);

   string title = PFX+"title";
   ObjectCreate(0, title, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, title, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, title, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, title, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, title, OBJPROP_TEXT, "ROYAL VIENTO CLONE EA v2.04" + (InpAllowBuySellTogether ? " (Hedge)" : ""));
   ObjectSetString(0, title, OBJPROP_FONT, "Consolas Bold");
   ObjectSetInteger(0, title, OBJPROP_FONTSIZE, 11);
   ObjectSetInteger(0, title, OBJPROP_COLOR, clrGold);

   for(int i=0; i<totalLines; i++)
     {
      string ln = PFX+"line"+IntegerToString(i);
      ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, ln, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, ln, OBJPROP_YDISTANCE, y + 26 + i*lineH);
      ObjectSetInteger(0, ln, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, ln, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, ln, OBJPROP_COLOR, clrWhiteSmoke);
     }
  }

void SetLine(int idx, string text, color clr)
  {
   string ln = PFX+"line"+IntegerToString(idx);
   ObjectSetString(0, ln, OBJPROP_TEXT, text);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
void UpdatePanel(double emaDir, double ema200, double stochMain,
                  double atrNow, double atrAvg, double closeNow)
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   long   spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   int bCount; double bAvg, bLots, bFloat, bLastPrice, bLastLot; datetime bLastTime;
   GetBasketInfo(1, bCount, bAvg, bLots, bFloat, bLastPrice, bLastLot, bLastTime);
   int sCount; double sAvg, sLots, sFloat, sLastPrice, sLastLot; datetime sLastTime;
   GetBasketInfo(-1, sCount, sAvg, sLots, sFloat, sLastPrice, sLastLot, sLastTime);

   string signal = (closeNow>emaDir) ? "BUY" : "SELL";
   double ratio = (atrAvg>0) ? atrNow/atrAvg : 1.0;
   bool atrOK; string regime = GetATRRegime(ratio, atrOK);
   bool tradingOpen = CheckTradingHours();
   double nextBuyLot  = CalcNextLot(bCount, bLastLot);
   double nextSellLot = CalcNextLot(sCount, sLastLot);

   double dailyDDPercent = (g_dayStartEquity>0) ? MathMax(0.0, -g_dailyProfit/g_dayStartEquity*100.0) : 0.0;
   double accDDPercent   = (g_accountBaselineEquity>0) ? MathMax(0.0, (g_accountBaselineEquity-eq)/g_accountBaselineEquity*100.0) : 0.0;
   double peakDDPercent  = (g_accountPeakEquity>0) ? MathMax(0.0, (g_accountPeakEquity-eq)/g_accountPeakEquity*100.0) : 0.0;

   // status keseluruhan
   ENUM_ACCOUNT_STATUS status = ACC_STATUS_SAFE;
   if(g_accountLocked || g_dailyLossHit) status = ACC_STATUS_LOCKED;
   else if(dailyDDPercent >= InpDailyLossPercent*0.6 || accDDPercent >= InpMaxAccountDrawdown*0.6
           || (InpUseTrailingPeakDD && peakDDPercent >= InpTrailingPeakDDPercent*0.6)
           || IsATRSpikePaused())
      status = ACC_STATUS_RISK;

   color statusColor = (status==ACC_STATUS_SAFE) ? clrLime : (status==ACC_STATUS_RISK ? clrOrange : clrTomato);
   string statusText  = (status==ACC_STATUS_SAFE) ? "SAFE" : (status==ACC_STATUS_RISK ? "RISK" : "TRADING LOCKED");

   SetLine(0, StringFormat("Balance %s %.2f | Equity %s %.2f | Today P/L %s %.2f", AccountInfoString(ACCOUNT_CURRENCY), bal, AccountInfoString(ACCOUNT_CURRENCY), eq, AccountInfoString(ACCOUNT_CURRENCY), g_dailyProfit),
           g_dailyProfit>=0?clrLime:clrTomato);
   SetLine(1, StringFormat("Trend: %s | Spread: %d pt %s", signal, (int)spreadPts, IsSpreadOK()?"":"(FILTER)"),
           IsSpreadOK()?clrLime:clrTomato);
   SetLine(2, "", clrWhiteSmoke);

   SetLine(3, StringFormat("BUY basket : %d/%d order | lot %.2f/%.2f | float %s %.2f", bCount, InpMaxOpenOrdersBasket,
             bLots, InpMaxTotalLotBasket, AccountInfoString(ACCOUNT_CURRENCY), bFloat), bCount>0?clrLime:clrWhiteSmoke);
   SetLine(4, StringFormat("   avg %.2f | next lot %.2f | cooldown %d bar / %s", bAvg, nextBuyLot, g_buyCooldownLeft,
             IsBasketCooldownActive(1)?"LOCKED":"ready"), clrSilver);
   SetLine(5, StringFormat("SELL basket: %d/%d order | lot %.2f/%.2f | float %s %.2f", sCount, InpMaxOpenOrdersBasket,
             sLots, InpMaxTotalLotBasket, AccountInfoString(ACCOUNT_CURRENCY), sFloat), sCount>0?clrTomato:clrWhiteSmoke);
   SetLine(6, StringFormat("   avg %.2f | next lot %.2f | cooldown %d bar / %s", sAvg, nextSellLot, g_sellCooldownLeft,
             IsBasketCooldownActive(-1)?"LOCKED":"ready"), clrSilver);

   SetLine(7, StringFormat("Risk: Daily DD %.1f%% / %.1f%%  |  Account DD %.1f%% / %.1f%%",
             dailyDDPercent, InpDailyLossPercent, accDDPercent, InpMaxAccountDrawdown),
             accDDPercent>=InpMaxAccountDrawdown*0.6?clrOrange:clrWhiteSmoke);
   SetLine(8, StringFormat("Margin Level: %.0f%% (min %.0f%%) | Free Margin: %s %.2f", marginLevel, InpMinMarginLevel, AccountInfoString(ACCOUNT_CURRENCY),
             AccountInfoDouble(ACCOUNT_MARGIN_FREE)), marginLevel<InpMinMarginLevel*1.5?clrOrange:clrWhiteSmoke);

   SetLine(9, StringFormat("STATUS: %s%s", statusText, g_accountLocked?(" - "+g_accountLockReason):""), statusColor);
   SetLine(10, StringFormat("Jam Trading %d-%dh : %s | Auto Lot: %s", InpTradingHourStart, InpTradingHourEnd,
             tradingOpen?"BUKA":"TUTUP", InpAutoLotByBalance?"ON":"OFF"), clrWhiteSmoke);
   SetLine(11, StringFormat("Basket Cut Loss: %s", InpUseBasketLossPercent?
             StringFormat("%.1f%% equity",InpBasketLossPercent):
             (InpCutLossPerBasketUSD>0?StringFormat("USD %.2f",InpCutLossPerBasketUSD):"nonaktif")), clrWhiteSmoke);
   SetLine(12, StringFormat("Exit Mode: %s | TP: %s", InpDisableTrailTP?"Manual (OFF)":
             (InpUseBasketTrailing?"Trailing Basket":(InpUseATRBasedTP?"ATR Dynamic":"Fixed Point")),
             InpUseBasketTrailing?"-":(InpUseATRBasedTP?StringFormat("%.0fp (ATR x%.1f)",(atrNow/SymbolInfoDouble(_Symbol,SYMBOL_POINT))*InpATRTPMultiplier,InpATRTPMultiplier):StringFormat("%.0fp",InpFixedTPPoints))),
             clrWhiteSmoke);
   SetLine(13, StringFormat("Averaging: ATR dist %.0fp (min %.0f/max %.0f) | tunggu close:%s",
             CalcAveragingDistancePts(atrNow), InpMinAveragingDistance, InpMaxAveragingDistance,
             InpAveragingWaitClose?"YA":"TIDAK"), clrWhiteSmoke);
   SetLine(14, StringFormat("Entry Mode: %s | Buy&Sell bareng: %s", InpFollowEMACooldownRules?"Ikut EMA/cooldown":"Buy&Sell langsung",
             InpAllowBuySellTogether?"ON":"OFF"), clrWhiteSmoke);
   SetLine(15, StringFormat("EMA%d %.2f | EMA200 %.2f (filter:%s) | Stoch %.1f (filter:%s)", InpEMADirPeriod, emaDir, ema200,
             InpUseEMA200Filter?"ON":"OFF", stochMain, InpUseStochFilter?"ON":"OFF"), clrWhiteSmoke);
   SetLine(16, StringFormat("ATR %.2f (avg %.2f, x%.2f) -> %s [%s]%s", atrNow, atrAvg, ratio, regime,
             InpUseATRFilter?"filter ON":"filter OFF", IsATRSpikePaused()?" | SPIKE PAUSE":""),
             IsATRSpikePaused()?clrOrange:clrLime);
   SetLine(17, StringFormat("Magic %d | Slippage %dp | Hard SL: %s", InpMagic, InpMaxSlippage,
             InpUseBrokerSL?StringFormat("ATR x%.1f",InpBrokerSL_ATR):"OFF"), clrGray);
   SetLine(18, StringFormat("Daily Target: %s | Daily Loss Limit: %s",
             InpUseDailyProfitTarget?StringFormat("%.1f%%",InpDailyProfitTargetPercent):"off",
             InpUseDailyLossLimit?StringFormat("%.1f%%",InpDailyLossPercent):"off"), clrGray);
   SetLine(19, StringFormat("Peak DD (Module 2B): %s", InpUseTrailingPeakDD?
             StringFormat("%.1f%% / %.1f%% (peak %s %.2f)", peakDDPercent, InpTrailingPeakDDPercent, AccountInfoString(ACCOUNT_CURRENCY), g_accountPeakEquity):
             "nonaktif"), peakDDPercent>=InpTrailingPeakDDPercent*0.6?clrOrange:clrWhiteSmoke);

   string autoResetText;
   if(!InpUseConditionalAutoReset)
      autoResetText = "nonaktif";
   else if(!g_accountLocked)
      autoResetText = "standby (akun tidak locked)";
   else
     {
      double lockedDays = (double)(TimeCurrent()-g_accountLockTime)/86400.0;
      if(lockedDays < InpAutoResetMinDays)
         autoResetText = StringFormat("cooldown %.1f/%d hari", lockedDays, InpAutoResetMinDays);
      else
         autoResetText = StringFormat("evaluasi pasar: stabil %d/%d candle", g_autoResetStableBars, InpAutoResetStableBarsNeeded);
     }
   SetLine(20, StringFormat("Auto-Reset (Module 2C): %s", autoResetText),
             (g_accountLocked && InpUseConditionalAutoReset)?clrOrange:clrWhiteSmoke);
  }

#endif // __RV_PANELUI_MQH__
//+------------------------------------------------------------------+
