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

   string posJson = "[";
   bool first = true;

   for(int i = 0; i < totalPos; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      long magic = PositionGetInteger(POSITION_MAGIC);
      // include all or EA magic
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
      "  \"algo_trading\": %s,\n"
      "  \"buy_count\": %d,\n"
      "  \"buy_lots\": %.2f,\n"
      "  \"sell_count\": %d,\n"
      "  \"sell_lots\": %.2f,\n"
      "  \"positions_total\": %d,\n"
      "  \"positions\": %s,\n"
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
      (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "true" : "false"),
      buyCount, totalBuyLots, sellCount, totalSellLots,
      totalPos, posJson, (long)TimeCurrent()
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
