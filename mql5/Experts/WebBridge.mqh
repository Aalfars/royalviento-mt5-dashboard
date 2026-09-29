//+------------------------------------------------------------------+
//| WebBridge.mqh - RoyalViento EA Web Dashboard Integration Bridge  |
//+------------------------------------------------------------------+
#ifndef __RV_WEBBRIDGE_MQH__
#define __RV_WEBBRIDGE_MQH__

double g_webDailyTargetUSD = 0.0;
bool   g_webPaused         = false;

//+------------------------------------------------------------------+
//| Inisialisasi WebBridge                                           |
//+------------------------------------------------------------------+
void WebBridge_Init()
{
   if(GlobalVariableCheck("RV_DailyTargetUSD"))
      g_webDailyTargetUSD = GlobalVariableGet("RV_DailyTargetUSD");
   if(GlobalVariableCheck("RV_WebPaused"))
      g_webPaused = (GlobalVariableGet("RV_WebPaused") > 0.5);
   
   EventSetTimer(1); // update tiap detik
}

#ifdef __ROYAL_QUANTUM__
//+------------------------------------------------------------------+
//| Build MTF JSON (M1, M5, H4)                                      |
//+------------------------------------------------------------------+
string WebBridge_BuildMTFJson()
{
   string sigM1 = MTFDirectionText(g_mtfM1);
   string sigM5 = MTFDirectionText(g_mtfM5);
   string sigH4 = MTFDirectionText(g_mtfH4);

   string m1 = StringFormat("{\"tf\":\"M1\",\"signal\":\"%s\",\"direction\":%d,\"valid\":%s,\"close\":%.2f,\"ema_dir\":%.2f,\"ema_200\":%.2f,\"stoch\":%.1f,\"slope_pts\":%.1f,\"ema_ok\":%s,\"slope_ok\":%s}",
                            sigM1, g_mtfM1.direction, (g_mtfM1.valid ? "true" : "false"),
                            g_mtfM1.close, g_mtfM1.emaDir, g_mtfM1.ema200, g_mtfM1.stoch, g_mtfM1.slopePts,
                            (g_mtfM1.emaOK ? "true" : "false"), (g_mtfM1.slopeOK ? "true" : "false"));

   string m5 = StringFormat("{\"tf\":\"M5\",\"signal\":\"%s\",\"direction\":%d,\"valid\":%s,\"close\":%.2f,\"ema_dir\":%.2f,\"ema_200\":%.2f,\"stoch\":%.1f,\"slope_pts\":%.1f,\"ema_ok\":%s,\"slope_ok\":%s}",
                            sigM5, g_mtfM5.direction, (g_mtfM5.valid ? "true" : "false"),
                            g_mtfM5.close, g_mtfM5.emaDir, g_mtfM5.ema200, g_mtfM5.stoch, g_mtfM5.slopePts,
                            (g_mtfM5.emaOK ? "true" : "false"), (g_mtfM5.slopeOK ? "true" : "false"));

   string h4 = StringFormat("{\"tf\":\"H4\",\"signal\":\"%s\",\"direction\":%d,\"valid\":%s,\"close\":%.2f,\"ema_dir\":%.2f,\"ema_200\":%.2f,\"stoch\":%.1f,\"slope_pts\":%.1f,\"ema_ok\":%s,\"slope_ok\":%s}",
                            sigH4, g_mtfH4.direction, (g_mtfH4.valid ? "true" : "false"),
                            g_mtfH4.close, g_mtfH4.emaDir, g_mtfH4.ema200, g_mtfH4.stoch, g_mtfH4.slopePts,
                            (g_mtfH4.emaOK ? "true" : "false"), (g_mtfH4.slopeOK ? "true" : "false"));

   string summary = "WAIT";
   if(g_mtfM1.valid && g_mtfM5.valid && g_mtfH4.valid)
   {
      if(g_mtfM1.direction > 0 && g_mtfM5.direction > 0 && g_mtfH4.direction > 0)
         summary = "BUY_ALIGNED";
      else if(g_mtfM1.direction < 0 && g_mtfM5.direction < 0 && g_mtfH4.direction < 0)
         summary = "SELL_ALIGNED";
      else
         summary = "MIXED";
   }

   bool confirmed = MTFDirectionConfirmed(g_mtfM1.direction);

   return StringFormat("{\"enabled\":%s,\"mode\":\"%s\",\"summary\":\"%s\",\"confirmed\":%s,\"m1\":%s,\"m5\":%s,\"h4\":%s}",
                       (g_webMTFEnabled ? "true" : "false"),
                       (g_webMTFEnabled ? "safe" : "scalper"),
                       summary,
                       (confirmed ? "true" : "false"),
                       m1, m5, h4);
}

//+------------------------------------------------------------------+
//| Build Active Parameters JSON                                     |
//+------------------------------------------------------------------+
string WebBridge_BuildParamsJson()
{
   string p1 = StringFormat("{\"InpBaseLot\":%.2f,\"InpLotMode\":%d,\"InpLotMultiplier\":%.2f,\"InpLotAddFlat\":%.2f,\"InpAutoLotByBalance\":%s,",
                            InpBaseLot, InpLotMode, InpLotMultiplier, InpLotAddFlat, (InpAutoLotByBalance ? "true" : "false"));
   string p2 = StringFormat("\"InpMTFEnabled\":%s,\"InpMTFUseEMA200\":%s,\"InpMTFUseSlope\":%s,\"InpMTFSlopeMin\":%.1f,",
                            (InpMTFEnabled ? "true" : "false"), (InpMTFUseEMA200 ? "true" : "false"), (InpMTFUseSlope ? "true" : "false"), InpMTFSlopeMin);
   string p3 = StringFormat("\"InpEMADirPeriod\":%d,\"InpEMA200Period\":%d,\"InpUseEMA200Filter\":%s,\"InpUseStochFilter\":%s,",
                            InpEMADirPeriod, InpEMA200Period, (InpUseEMA200Filter ? "true" : "false"), (InpUseStochFilter ? "true" : "false"));
   string p4 = StringFormat("\"InpStochK\":%d,\"InpStochD\":%d,\"InpStochSlowing\":%d,\"InpStochOversold\":%.1f,\"InpStochOverbought\":%.1f,",
                            InpStochK, InpStochD, InpStochSlowing, InpStochOversold, InpStochOverbought);
   string p5 = StringFormat("\"InpUseEMASlope\":%s,\"InpEMASlopeBars\":%d,\"InpEMASlopeMin\":%.1f,\"InpFollowEMACooldownRules\":%s,",
                            (InpUseEMASlope ? "true" : "false"), InpEMASlopeBars, InpEMASlopeMin, (InpFollowEMACooldownRules ? "true" : "false"));
   string p6 = StringFormat("\"InpTradingHourStart\":%d,\"InpTradingHourEnd\":%d,",
                            InpTradingHourStart, InpTradingHourEnd);
   string p7 = StringFormat("\"InpFixedAveragingDistancePoints\":%.1f,\"InpAvoidHighATRSpike\":%s,\"InpATRSpikeRatio\":%.1f,",
                            InpFixedAveragingDistancePoints, (InpAvoidHighATRSpike ? "true" : "false"), InpATRSpikeRatio);
   string p8 = StringFormat("\"InpMaxOpenOrdersBasket\":%d,\"InpMaxTotalLotBasket\":%.2f,\"InpMaxAveragingCycle\":%d,\"InpCooldownCandles\":%d,",
                            InpMaxOpenOrdersBasket, InpMaxTotalLotBasket, InpMaxAveragingCycle, InpCooldownCandles);
   string p9 = StringFormat("\"InpMinSecondsBetweenAvg\":%d,\"InpAllowBuySellTogether\":%s,\"InpAveragingWaitClose\":%s,",
                            InpMinSecondsBetweenAvg, (InpAllowBuySellTogether ? "true" : "false"), (InpAveragingWaitClose ? "true" : "false"));
   string p10 = StringFormat("\"InpUseBasketTrailing\":%s,\"InpTrailStartPoints\":%d,\"InpTrailStopDistance\":%d,\"InpDisableTrailTP\":%s,",
                             (InpUseBasketTrailing ? "true" : "false"), InpTrailStartPoints, InpTrailStopDistance, (InpDisableTrailTP ? "true" : "false"));
   string p11 = StringFormat("\"InpUseATRBasedTP\":%s,\"InpATRTPMultiplier\":%.1f,\"InpFixedTPPoints\":%.1f,",
                             (InpUseATRBasedTP ? "true" : "false"), InpATRTPMultiplier, InpFixedTPPoints);
   string p12 = StringFormat("\"InpUseDailyLossLimit\":%s,\"InpDailyLossPercent\":%.1f,\"InpUseDailyProfitTarget\":%s,\"InpDailyProfitTargetPercent\":%.1f,",
                             (InpUseDailyLossLimit ? "true" : "false"), InpDailyLossPercent, (InpUseDailyProfitTarget ? "true" : "false"), InpDailyProfitTargetPercent);
   string p13 = StringFormat("\"InpUseMaxAccountDD\":%s,\"InpMaxAccountDrawdown\":%.1f,\"InpUseBasketLossPercent\":%s,\"InpBasketLossPercent\":%.1f,",
                             (InpUseMaxAccountDD ? "true" : "false"), InpMaxAccountDrawdown, (InpUseBasketLossPercent ? "true" : "false"), InpBasketLossPercent);
   string p14 = StringFormat("\"InpCutLossPerBasketUSD\":%.2f,\"InpUseMarginSafety\":%s,\"InpMinMarginLevel\":%.1f,",
                             InpCutLossPerBasketUSD, (InpUseMarginSafety ? "true" : "false"), InpMinMarginLevel);
   string p15 = StringFormat("\"InpUseSpreadFilter\":%s,\"InpMaxSpreadPoints\":%d,\"InpBasketCooldownMinutes\":%d,",
                             (InpUseSpreadFilter ? "true" : "false"), InpMaxSpreadPoints, InpBasketCooldownMinutes);
   string p16 = StringFormat("\"InpGridFollowHigherTF\":%s,\"InpGridReverseOnTrendFlip\":%s,\"InpUseProfitLock\":%s,\"InpProfitLockStart\":%.1f,\"InpProfitLockPoints\":%.1f}",
                             (InpGridFollowHigherTF ? "true" : "false"), (InpGridReverseOnTrendFlip ? "true" : "false"), (InpUseProfitLock ? "true" : "false"), InpProfitLockStart, InpProfitLockPoints);

   return p1 + p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9 + p10 + p11 + p12 + p13 + p14 + p15 + p16;
}
#endif

//+------------------------------------------------------------------+
//| Export status akun & order ke JSON                               |
//+------------------------------------------------------------------+
void WebBridge_ExportStatus()
{
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin      = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   long   login       = AccountInfoInteger(ACCOUNT_LOGIN);
   string server      = AccountInfoString(ACCOUNT_SERVER);
   string currency    = AccountInfoString(ACCOUNT_CURRENCY);
   bool   algoAllowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

   int totalPos = PositionsTotal();
   double totalFloatingProfit = 0;
   double totalBuyLots = 0;
   double totalSellLots = 0;
   int buyCount = 0;
   int sellCount = 0;

   // 1. Open Positions JSON
   string posJson = "[";
   bool first = true;

   for(int i = 0; i < totalPos; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      long magic    = PositionGetInteger(POSITION_MAGIC);
      string symbol = PositionGetString(POSITION_SYMBOL);
      long posType  = PositionGetInteger(POSITION_TYPE);
      double lots   = PositionGetDouble(POSITION_VOLUME);
      double openPr = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPr  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT);
      datetime oTime= (datetime)PositionGetInteger(POSITION_TIME);

      totalFloatingProfit += profit;
      if(posType == POSITION_TYPE_BUY) { totalBuyLots += lots; buyCount++; }
      else if(posType == POSITION_TYPE_SELL) { totalSellLots += lots; sellCount++; }

      if(!first) posJson += ",";
      first = false;

      string p = StringFormat("{\"ticket\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\",\"lots\":%.2f,\"open_price\":%.2f,\"current_price\":%.2f,\"sl\":%.2f,\"tp\":%.2f,\"profit\":%.2f,\"time\":%I64d}",
                              ticket, symbol, (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                              lots, openPr, curPr, sl, tp, profit, (long)oTime);
      posJson += p;
   }
   posJson += "]";

   // 2. Order History (Deals / Closed Positions)
   datetime histFrom = TimeCurrent() - 7 * 86400; // 7 hari terakhir
   HistorySelect(histFrom, TimeCurrent() + 86400);
   int totalDeals = HistoryDealsTotal();
   
   string histJson = "[";
   bool firstHist = true;
   int exportedDeals = 0;
   double historyProfitSum = 0;

   for(int i = totalDeals - 1; i >= 0 && exportedDeals < 50; i--)
   {
      ulong dTicket = HistoryDealGetTicket(i);
      if(dTicket == 0) continue;

      long entry     = HistoryDealGetInteger(dTicket, DEAL_ENTRY);
      double dProfit = HistoryDealGetDouble(dTicket, DEAL_PROFIT);
      string dSymbol = HistoryDealGetString(dTicket, DEAL_SYMBOL);

      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && dProfit == 0.0)
         continue;
      if(StringLen(dSymbol) == 0 && dProfit == 0.0)
         continue;

      long dType    = HistoryDealGetInteger(dTicket, DEAL_TYPE);
      double dLots  = HistoryDealGetDouble(dTicket, DEAL_VOLUME);
      double dPrice = HistoryDealGetDouble(dTicket, DEAL_PRICE);
      datetime dTime= (datetime)HistoryDealGetInteger(dTicket, DEAL_TIME);
      ulong dOrder  = (ulong)HistoryDealGetInteger(dTicket, DEAL_ORDER);

      historyProfitSum += dProfit;

      string typeStr = (dType == DEAL_TYPE_BUY ? "BUY" : (dType == DEAL_TYPE_SELL ? "SELL" : "CLOSE"));

      if(!firstHist) histJson += ",";
      firstHist = false;
      exportedDeals++;

      string h = StringFormat("{\"ticket\":%I64u,\"order\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\",\"lots\":%.2f,\"price\":%.2f,\"profit\":%.2f,\"time\":%I64d}",
                              dTicket, dOrder, (StringLen(dSymbol) > 0 ? dSymbol : "BALANCE"),
                              typeStr, dLots, dPrice, dProfit, (long)dTime);
      histJson += h;
   }
   histJson += "]";

#ifdef __ROYAL_QUANTUM__
   string mtfPart = "\"mtf\": " + WebBridge_BuildMTFJson() + ",\n";
   string paramsPart = "\"parameters\": " + WebBridge_BuildParamsJson() + ",\n";
   string modeVal = (g_webMTFEnabled ? "safe" : "scalper");
   string blockReasonVal = g_entryBlockReason;
#else
   string mtfPart = "\"mtf\": null,\n";
   string paramsPart = "\"parameters\": null,\n";
   string modeVal = "scalper";
   string blockReasonVal = "NONE";
#endif

   string json = StringFormat(
      "{\n"
      "  \"account\": %I64d,\n"
      "  \"server\": \"%s\",\n"
      "  \"currency\": \"%s\",\n"
      "  \"balance\": %.2f,\n"
      "  \"equity\": %.2f,\n"
      "  \"margin\": %.2f,\n"
      "  \"free_margin\": %.2f,\n"
      "  \"margin_level\": %.2f,\n"
      "  \"day_start_equity\": %.2f,\n"
      "  \"daily_profit\": %.2f,\n"
      "  \"floating_profit\": %.2f,\n"
      "  \"daily_target_usd\": %.2f,\n"
      "  \"daily_target_hit\": %s,\n"
      "  \"daily_loss_hit\": %s,\n"
      "  \"account_locked\": %s,\n"
      "  \"web_paused\": %s,\n"
      "  \"trading_mode\": \"%s\",\n"
      "  \"entry_block_reason\": \"%s\",\n"
      "  \"algo_trading\": %s,\n"
      "  \"buy_count\": %d,\n"
      "  \"buy_lots\": %.2f,\n"
      "  \"sell_count\": %d,\n"
      "  \"sell_lots\": %.2f,\n"
      "  \"positions_total\": %d,\n"
      "  \"positions\": %s,\n"
      "  \"history_total\": %d,\n"
      "  \"history_profit_sum\": %.2f,\n"
      "  \"history\": %s,\n"
      "  %s"
      "  %s"
      "  \"updated_at\": %I64d\n"
      "}",
      login, server, currency,
      balance, equity, margin, freeMargin, marginLevel,
      g_dayStartEquity, g_dailyProfit, totalFloatingProfit,
      g_webDailyTargetUSD,
      (g_dailyTargetHit ? "true" : "false"),
      (g_dailyLossHit ? "true" : "false"),
      (g_accountLocked ? "true" : "false"),
      (g_webPaused ? "true" : "false"),
      modeVal,
      blockReasonVal,
      (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "true" : "false"),
      buyCount, totalBuyLots, sellCount, totalSellLots,
      totalPos, posJson,
      exportedDeals, historyProfitSum, histJson,
      mtfPart,
      paramsPart,
      (long)TimeCurrent()
   );

   int h = FileOpen("web_status.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, json);
      FileClose(h);
   }
}

//+------------------------------------------------------------------+
//| Parsing & eksekusi command dari Web Dashboard                    |
//+------------------------------------------------------------------+
void WebBridge_ProcessCommand()
{
   if(!FileIsExist("web_command.json")) return;

   int h = FileOpen("web_command.json", FILE_READ|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;

   string content = "";
   while(!FileIsEnding(h))
      content += FileReadString(h);
   FileClose(h);
   FileDelete("web_command.json");

   if(StringLen(content) < 5) return;

   // 1. Set Daily Target USD
   int idxTarget = StringFind(content, "\"set_daily_target\"");
   if(idxTarget >= 0)
   {
      int valIdx = StringFind(content, "\"value\":", idxTarget);
      if(valIdx >= 0)
      {
         string numStr = StringSubstr(content, valIdx + 8);
         double val = StringToDouble(numStr);
         g_webDailyTargetUSD = val;
         GlobalVariableSet("RV_DailyTargetUSD", val);
         PrintFormat("[WebBridge] Target Harian Diupdate ke $%.2f", val);
      }
   }

   // 2. Pause Trading
   if(StringFind(content, "\"pause\"") >= 0)
   {
      g_webPaused = true;
      GlobalVariableSet("RV_WebPaused", 1.0);
      Print("[WebBridge] Trading di-PAUSE oleh Web Dashboard");
   }

   // 3. Resume Trading
   if(StringFind(content, "\"resume\"") >= 0)
   {
      g_webPaused = false;
      g_dailyTargetHit = false;
      g_dailyLossHit = false;
      GlobalVariableSet("RV_WebPaused", 0.0);
      Print("[WebBridge] Trading di-RESUME oleh Web Dashboard (Target Hit cleared)");
   }

   // 4. Close All Positions
   if(StringFind(content, "\"close_all\"") >= 0)
   {
      Print("[WebBridge] Menutup SEMUA posisi atas perintah Web Dashboard...");
      CloseAllPositions();
   }

   // 5. Close specific ticket
   int idxCloseTicket = StringFind(content, "\"close_ticket\"");
   if(idxCloseTicket >= 0)
   {
      int tIdx = StringFind(content, "\"ticket\":", idxCloseTicket);
      if(tIdx >= 0)
      {
         ulong ticket = (ulong)StringToInteger(StringSubstr(content, tIdx + 9));
         if(ticket > 0)
         {
            trade.PositionClose(ticket);
            PrintFormat("[WebBridge] Posisi #%I64u ditutup atas perintah Web Dashboard", ticket);
         }
      }
   }

   // 6. Reset Daily Stats
   if(StringFind(content, "\"reset_daily\"") >= 0)
   {
      g_dayStart       = TimeCurrent();
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyProfit    = 0;
      g_dailyTargetHit = false;
      g_dailyLossHit   = false;
      Print("[WebBridge] Statistik harian di-RESET");
   }

   // 7. Set Mode (Safe MTF vs Scalper M1)
   int idxMode = StringFind(content, "\"set_mode\"");
   if(idxMode >= 0)
   {
#ifdef __ROYAL_QUANTUM__
      if(StringFind(content, "\"safe\"") >= 0)
      {
         g_webMTFEnabled = true;
         Print("[WebBridge] Mode diubah ke AMAN (MTF H4/M5)");
      }
      else if(StringFind(content, "\"scalper\"") >= 0)
      {
         g_webMTFEnabled = false;
         Print("[WebBridge] Mode diubah ke SCALPER M1 (Aktif)");
      }
#endif
   }
}

//+------------------------------------------------------------------+
//| Cek target harian USD dari WebBridge                             |
//+------------------------------------------------------------------+
void WebBridge_CheckTarget()
{
   if(!g_dailyTargetHit && g_webDailyTargetUSD > 0.0)
   {
      if(g_dailyProfit >= g_webDailyTargetUSD)
      {
         PrintFormat("🎯 [WebBridge] TARGET HARIAN $%.2f TERCAPAI! Profit saat ini: $%.2f. Menutup order & berhenti trading hari ini.",
                     g_webDailyTargetUSD, g_dailyProfit);
         CloseAllPositions();
         g_dailyTargetHit = true;
      }
   }
}

#endif // __RV_WEBBRIDGE_MQH__
