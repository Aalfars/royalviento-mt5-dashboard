//+------------------------------------------------------------------+
//|                                           RoyalCopier_Slave.mq5 |
//|                             RoyalViento Trade Follower / Copier  |
//|                                   https://trading.aranya.my.id   |
//+------------------------------------------------------------------+
#property copyright "RoyalViento Copier Engine"
#property link      "https://trading.aranya.my.id"
#property version   "1.00"
#property description "Follower Copier EA for Exness ($30 account with -$25 daily safety kill switch)"

#include <Trade\Trade.mqh>

input group "=== PENGATURAN SIMBOL & LOT ==="
input string InpMasterSymbol       = "XAUUSD";      // Master Symbol (MetaQuotes Demo)
input string InpSlaveSymbol        = "XAUUSDm";     // Slave Symbol (Exness Demo / Real)
input double InpFixedLot           = 0.01;          // Lot tetap (0.01 aman untuk modal $30)
input ulong  InpMagicNumber        = 778899;        // Magic Number posisi Slave
input int    InpMaxOpenPositions   = 3;             // Batas maksimum posisi terbuka simultan

input group "=== DAILY LOSS PROTECTION (SAFETY KILL SWITCH) ==="
input double InpDailyLossLimitUSD  = 25.0;          // Batas Max Loss Harian (Stop jika rugi mencapai -$25)
input bool   InpAutoCloseOnHalt    = true;          // Tutup sisa posisi terbuka saat batas rugi tersentuh

input group "=== PENGATURAN KONEKSI & INTERVAL ==="
input int    InpCheckIntervalMs    = 200;           // Interval sinkronisasi (milidetik)
input ulong  InpSlippagePoints     = 50;            // Toleransi slippage (points)

//--- Global Variables
CTrade   trade;
bool     g_dailyHalted         = false;
bool     g_copierPaused        = false;
double   g_todayClosedProfit   = 0.0;
datetime g_lastDayStart        = 0;
datetime g_lastMasterUpdate    = 0;
int      g_copiedCount         = 0;
int      g_closedCount         = 0;

struct MasterPosition
{
   ulong    ticket;
   string   symbol;
   string   type;
   double   lots;
   double   openPrice;
   double   sl;
   double   tp;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   g_lastDayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   CheckDailyLoss();

   EventSetMillisecondTimer(InpCheckIntervalMs);
   ExportSlaveStatus();

   PrintFormat("[RoyalCopier Slave] Inisialisasi berhasil. Target Simbol: %s -> %s, Lot: %.2f, Max Daily Loss: $%.2f",
      InpMasterSymbol, InpSlaveSymbol, InpFixedLot, InpDailyLossLimitUSD);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("[RoyalCopier Slave] EA dihentikan.");
}

//+------------------------------------------------------------------+
//| Timer event function (dipanggil tiap 200 ms)                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Cek perintah web dashboard
   ProcessSlaveCommands();

   // 2. Cek reset hari baru & hitung profit/loss tertutup hari ini
   CheckDailyLoss();

   // 3. Baca perintah/posisi dari Master via FILE_COMMON
   SyncWithMaster();

   // 4. Export telemetri status ke FILE_COMMON untuk web dashboard
   static datetime lastExport = 0;
   if(TimeCurrent() != lastExport)
   {
      lastExport = TimeCurrent();
      ExportSlaveStatus();
   }
}

//+------------------------------------------------------------------+
//| Hitung profit/loss tertutup hari ini & periksa safety limit      |
//+------------------------------------------------------------------+
void CheckDailyLoss()
{
   datetime currentDayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(currentDayStart != g_lastDayStart)
   {
      g_lastDayStart = currentDayStart;
      g_dailyHalted  = false;
      g_todayClosedProfit = 0.0;
      PrintFormat("[RoyalCopier Slave] Hari baru (%s). Limit rugi harian di-reset.", TimeToString(currentDayStart));
   }

   HistorySelect(g_lastDayStart, TimeCurrent() + 86400);
   double profitSum = 0.0;
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dTicket = HistoryDealGetTicket(i);
      if(dTicket == 0) continue;

      long entry = HistoryDealGetInteger(dTicket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      {
         profitSum += HistoryDealGetDouble(dTicket, DEAL_PROFIT);
         profitSum += HistoryDealGetDouble(dTicket, DEAL_SWAP);
         profitSum += HistoryDealGetDouble(dTicket, DEAL_COMMISSION);
      }
   }
   g_todayClosedProfit = profitSum;

   // Cek apakah menyentuh batas minus harian (-$25)
   if(g_todayClosedProfit <= -InpDailyLossLimitUSD)
   {
      if(!g_dailyHalted)
      {
         g_dailyHalted = true;
         PrintFormat("==================================================================");
         PrintFormat("[SAFETY KILL SWITCH AKTIF] Realized Loss hari ini $%.2f <= -$%.2f!",
            g_todayClosedProfit, InpDailyLossLimitUSD);
         PrintFormat("[SAFETY KILL SWITCH AKTIF] Trading di Exness dihentikan untuk melindungi modal.");
         PrintFormat("==================================================================");

         if(InpAutoCloseOnHalt)
         {
            CloseAllSlavePositions("KILL_SWITCH_HIT");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tutup semua posisi terbuka milik Slave EA                         |
//+------------------------------------------------------------------+
void CloseAllSlavePositions(string reason="MANUAL")
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         trade.PositionClose(ticket);
         PrintFormat("[RoyalCopier Slave] Posisi #%I64u ditutup paksa. Alasan: %s", ticket, reason);
      }
   }
}

//+------------------------------------------------------------------+
//| Periksa dan eksekusi perintah dari Web Dashboard                 |
//+------------------------------------------------------------------+
void ProcessSlaveCommands()
{
   if(!FileIsExist("copier_slave_command.json", FILE_COMMON)) return;

   int h = FileOpen("copier_slave_command.json", FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;

   string content = "";
   while(!FileIsEnding(h))
      content += FileReadString(h);
   FileClose(h);
   FileDelete("copier_slave_command.json", FILE_COMMON);

   if(StringLen(content) < 5) return;

   PrintFormat("[RoyalCopier Slave] Menerima Perintah Web: %s", content);

   if(StringFind(content, "\"pause\"") >= 0)
   {
      g_copierPaused = true;
      Print("[RoyalCopier Slave] Copier di-PAUSE via Web Dashboard.");
   }
   else if(StringFind(content, "\"resume\"") >= 0)
   {
      g_copierPaused = false;
      Print("[RoyalCopier Slave] Copier di-RESUME via Web Dashboard.");
   }
   else if(StringFind(content, "\"reset_halt\"") >= 0)
   {
      g_dailyHalted = false;
      Print("[RoyalCopier Slave] Daily Loss Halt di-RESET via Web Dashboard.");
   }
   else if(StringFind(content, "\"close_all\"") >= 0)
   {
      CloseAllSlavePositions("WEB_DASHBOARD_PANIC_CLOSE");
   }

   ExportSlaveStatus();
}

//+------------------------------------------------------------------+
//| Parse JSON Master dan Sinkronisasi Entry / Close                 |
//+------------------------------------------------------------------+
void SyncWithMaster()
{
   int h = FileOpen("copier_master.json", FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;

   string content = "";
   while(!FileIsEnding(h))
      content += FileReadString(h);
   FileClose(h);

   if(StringLen(content) < 15) return;

   // Cek timestamp update
   int timeIdx = StringFind(content, "\"updated_at\":");
   if(timeIdx >= 0)
   {
      string sub = StringSubstr(content, timeIdx + 13);
      long uTime = (long)StringToInteger(sub);
      g_lastMasterUpdate = (datetime)uTime;
   }

   // 1. Ekstrak daftar posisi Master
   MasterPosition masterPositions[];
   int masterCount = ParseMasterPositions(content, masterPositions);

   // 2. Ekstrak daftar posisi Slave yang sedang terbuka
   ulong slaveTickets[];
   ulong mappedMasterTickets[];
   int slaveTotal = GetSlaveOpenPositions(slaveTickets, mappedMasterTickets);

   // 3. JIKA SEDANG HALT (RUGI -$25): JANGAN BUKA POSISI BARU!
   if(g_dailyHalted)
   {
      // Pastikan tidak ada posisi yang tertinggal
      if(slaveTotal > 0 && InpAutoCloseOnHalt)
         CloseAllSlavePositions("HALTED");
      return;
   }

   // 4. OPEN SYNC: Cari posisi Master yang belum ada di Slave (Hanya jika TIDAK di-PAUSE)
   if(!g_copierPaused)
   {
      string tradeSymbol = (StringLen(InpSlaveSymbol) > 0 ? InpSlaveSymbol : _Symbol);

      for(int m = 0; m < masterCount; m++)
      {
         ulong mTicket = masterPositions[m].ticket;
         if(mTicket == 0) continue;

         bool exists = false;
         for(int s = 0; s < slaveTotal; s++)
         {
            if(mappedMasterTickets[s] == mTicket)
            {
               exists = true;
               break;
            }
         }

         if(!exists)
         {
            // Cek batas maksimum posisi
            if(PositionsTotal() >= InpMaxOpenPositions)
            {
               PrintFormat("[RoyalCopier Slave] Maksimum posisi terbuka tercapai (%d). Lewati #%I64u",
                  InpMaxOpenPositions, mTicket);
               continue;
            }

            string comment = StringFormat("RV-M:%I64u", mTicket);

            if(masterPositions[m].type == "BUY")
            {
               double ask = SymbolInfoDouble(tradeSymbol, SYMBOL_ASK);
               if(trade.Buy(InpFixedLot, tradeSymbol, ask, 0, 0, comment))
               {
                  g_copiedCount++;
                  PrintFormat("[RoyalCopier Slave] COPIED BUY #%I64u -> Slave #%I64u (Lot %.2f @ %.2f)",
                     mTicket, trade.ResultOrder(), InpFixedLot, ask);
               }
               else
               {
                  PrintFormat("[RoyalCopier Slave] Gagal Copy BUY Master #%I64u. Err: %d", mTicket, GetLastError());
               }
            }
            else if(masterPositions[m].type == "SELL")
            {
               double bid = SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
               if(trade.Sell(InpFixedLot, tradeSymbol, bid, 0, 0, comment))
               {
                  g_copiedCount++;
                  PrintFormat("[RoyalCopier Slave] COPIED SELL #%I64u -> Slave #%I64u (Lot %.2f @ %.2f)",
                     mTicket, trade.ResultOrder(), InpFixedLot, bid);
               }
               else
               {
                  PrintFormat("[RoyalCopier Slave] Gagal Copy SELL Master #%I64u. Err: %d", mTicket, GetLastError());
               }
            }
         }
      }
   }

   // 5. CLOSE SYNC: Cari posisi Slave yang Master-nya sudah ditutup
   for(int s = 0; s < slaveTotal; s++)
   {
      ulong sTicket = slaveTickets[s];
      ulong mTicket = mappedMasterTickets[s];

      if(mTicket > 0)
      {
         bool masterStillActive = false;
         for(int m = 0; m < masterCount; m++)
         {
            if(masterPositions[m].ticket == mTicket)
            {
               masterStillActive = true;
               break;
            }
         }

         if(!masterStillActive)
         {
            // Master sudah menutup posisi ini! Tutup Slave segera!
            if(trade.PositionClose(sTicket))
            {
               g_closedCount++;
               PrintFormat("[RoyalCopier Slave] Master #%I64u sudah ditutup. Menutup Slave #%I64u...",
                  mTicket, sTicket);
               CheckDailyLoss();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Parser sederhana posisi Master dari JSON string                  |
//+------------------------------------------------------------------+
int ParseMasterPositions(const string &json, MasterPosition &positions[])
{
   int startPos = StringFind(json, "\"positions\": [");
   if(startPos < 0) startPos = StringFind(json, "\"positions\":[");
   if(startPos < 0) return 0;

   int endPos = StringFind(json, "]", startPos);
   if(endPos < 0) return 0;

   string arrayContent = StringSubstr(json, startPos, endPos - startPos + 1);

   int count = 0;
   int searchPos = 0;

   while(true)
   {
      int ticketIdx = StringFind(arrayContent, "\"ticket\":", searchPos);
      if(ticketIdx < 0) break;

      int ticketEnd = StringFind(arrayContent, ",", ticketIdx);
      if(ticketEnd < 0) ticketEnd = StringFind(arrayContent, "}", ticketIdx);
      if(ticketEnd < 0) break;

      string ticketStr = StringSubstr(arrayContent, ticketIdx + 9, ticketEnd - (ticketIdx + 9));
      StringTrimLeft(ticketStr); StringTrimRight(ticketStr);
      ulong tVal = (ulong)StringToInteger(ticketStr);

      int typeIdx = StringFind(arrayContent, "\"type\":\"", ticketIdx);
      string typeVal = "BUY";
      if(typeIdx >= 0 && typeIdx < ticketIdx + 150)
      {
         int typeEnd = StringFind(arrayContent, "\"", typeIdx + 8);
         if(typeEnd > typeIdx)
            typeVal = StringSubstr(arrayContent, typeIdx + 8, typeEnd - (typeIdx + 8));
      }

      int lotsIdx = StringFind(arrayContent, "\"lots\":", ticketIdx);
      double lotsVal = 0.01;
      if(lotsIdx >= 0 && lotsIdx < ticketIdx + 200)
      {
         int lotsEnd = StringFind(arrayContent, ",", lotsIdx);
         if(lotsEnd < 0) lotsEnd = StringFind(arrayContent, "}", lotsIdx);
         if(lotsEnd > lotsIdx)
            lotsVal = StringToDouble(StringSubstr(arrayContent, lotsIdx + 7, lotsEnd - (lotsIdx + 7)));
      }

      ArrayResize(positions, count + 1);
      positions[count].ticket    = tVal;
      positions[count].type      = typeVal;
      positions[count].lots      = lotsVal;
      positions[count].symbol    = InpMasterSymbol;
      count++;

      searchPos = ticketEnd;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Ambil daftar tiket Slave yang sedang terbuka & peta Master ticket|
//+------------------------------------------------------------------+
int GetSlaveOpenPositions(ulong &slaveTickets[], ulong &mappedMasterTickets[])
{
   int count = 0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         string comment = PositionGetString(POSITION_COMMENT);
         ulong mTicket = 0;

         int prefixIdx = StringFind(comment, "RV-M:");
         if(prefixIdx >= 0)
         {
            mTicket = (ulong)StringToInteger(StringSubstr(comment, prefixIdx + 5));
         }

         ArrayResize(slaveTickets, count + 1);
         ArrayResize(mappedMasterTickets, count + 1);
         slaveTickets[count] = ticket;
         mappedMasterTickets[count] = mTicket;
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Export status Slave ke FILE_COMMON untuk Web Dashboard           |
//+------------------------------------------------------------------+
void ExportSlaveStatus()
{
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin      = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   long   login       = AccountInfoInteger(ACCOUNT_LOGIN);
   string server      = AccountInfoString(ACCOUNT_SERVER);
   string currency    = AccountInfoString(ACCOUNT_CURRENCY);

   int totalPos = 0;
   double floatingProfit = 0.0;
   string posJson = "[";
   bool first = true;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         totalPos++;
         double profit = PositionGetDouble(POSITION_PROFIT);
         floatingProfit += profit;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long posType  = PositionGetInteger(POSITION_TYPE);
         double lots   = PositionGetDouble(POSITION_VOLUME);
         double openPr = PositionGetDouble(POSITION_PRICE_OPEN);
         string comm   = PositionGetString(POSITION_COMMENT);

         if(!first) posJson += ",";
         first = false;

         string p = StringFormat(
            "{\"ticket\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\",\"lots\":%.2f,\"open_price\":%.2f,\"profit\":%.2f,\"comment\":\"%s\"}",
            ticket, symbol, (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
            lots, openPr, profit, comm
         );
         posJson += p;
      }
   }
   posJson += "]";

   string statusStr = "ACTIVE_SYNCED";
   if(g_dailyHalted) statusStr = "HALTED_DAILY_LOSS";
   else if(g_copierPaused) statusStr = "PAUSED";

   string json = "{\n";
   json += StringFormat("  \"slave_account\": %I64d,\n", login);
   json += StringFormat("  \"slave_server\": \"%s\",\n", server);
   json += StringFormat("  \"slave_symbol\": \"%s\",\n", InpSlaveSymbol);
   json += StringFormat("  \"balance\": %.2f,\n", balance);
   json += StringFormat("  \"equity\": %.2f,\n", equity);
   json += StringFormat("  \"margin\": %.2f,\n", margin);
   json += StringFormat("  \"free_margin\": %.2f,\n", freeMargin);
   json += StringFormat("  \"today_closed_profit\": %.2f,\n", g_todayClosedProfit);
   json += StringFormat("  \"floating_profit\": %.2f,\n", floatingProfit);
   json += StringFormat("  \"daily_loss_limit_usd\": %.2f,\n", InpDailyLossLimitUSD);
   json += StringFormat("  \"is_halted\": %s,\n", (g_dailyHalted ? "true" : "false"));
   json += StringFormat("  \"is_paused\": %s,\n", (g_copierPaused ? "true" : "false"));
   json += StringFormat("  \"status\": \"%s\",\n", statusStr);
   json += StringFormat("  \"fixed_lot\": %.2f,\n", InpFixedLot);
   json += StringFormat("  \"copied_total\": %d,\n", g_copiedCount);
   json += StringFormat("  \"closed_total\": %d,\n", g_closedCount);
   json += StringFormat("  \"last_master_update\": %I64d,\n", (long)g_lastMasterUpdate);
   json += StringFormat("  \"positions_count\": %d,\n", totalPos);
   json += "  \"positions\": " + posJson + ",\n";
   bool tradeAllowed  = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   json += StringFormat("  \"algo_trading\": %s,\n", (tradeAllowed ? "true" : "false"));
   json += StringFormat("  \"updated_at\": %I64d\n", (long)TimeCurrent());
   json += "}";

   int h = FileOpen("copier_slave_status.json", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, json);
      FileClose(h);
   }
}
