//+------------------------------------------------------------------+
//| RoyalViento_Clone_EA_v2.04.mq5                                   |
//| Rekreasi strategi berdasarkan analisis visual dashboard EA        |
//| "EA Royal Viento Final Mix 2.00" — BUKAN kode asli, hasil         |
//| rekonstruksi & redesign risk management independen.               |
//+------------------------------------------------------------------+
#property copyright "Rekreasi & redesign independen - bukan afiliasi resmi"
#property version   "2.04"
#property strict

#include "Globals.mqh"
#include "MoneyManagement.mqh"
#include "ATRManager.mqh"
#include "EntryManager.mqh"
#include "RiskManager.mqh"
#include "BasketManager.mqh"
#include "TrailingManager.mqh"
#include "PanelUI.mqh"
#include "WebBridge.mqh"

input group "=== Reset Manual (MODULE 2) ==="
input bool     InpManualUnlockAccount = false; // Set TRUE lalu apply input sekali utk buka kunci Max Drawdown, baseline baru dibuat

//+------------------------------------------------------------------+
int OnInit()
  {
   if(ATR_Init() != INIT_SUCCEEDED)
     {
      Print("Gagal membuat handle ATR");
      return INIT_FAILED;
     }
   if(EntryManager_Init() != INIT_SUCCEEDED)
     {
      Print("Gagal membuat handle EMA/Stochastic");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);

   RiskManager_Init(); // baca/inisialisasi baseline & status lock PERSISTEN

   if(InpManualUnlockAccount)
      ResetAccountLock(); // reset manual eksplisit dari user (Module 2)

   g_dayStart       = TimeCurrent();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyProfit     = 0;
   g_dailyTargetHit  = false;
   g_dailyLossHit    = false;

   if(InpShowPanel) CreatePanel();
   
   WebBridge_Init();
   WebBridge_ExportStatus();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   WebBridge_ProcessCommand();
   WebBridge_CheckTarget();
   WebBridge_ExportStatus();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   WebBridge_ProcessCommand();
   WebBridge_CheckTarget();

   double emaDir, ema200, stochMain, closeNow;
   if(!GetEntryIndicatorValues(emaDir, ema200, stochMain, closeNow))
     {
      WebBridge_ExportStatus();
      return;
     }

   double atrNow, atrAvg;
   if(!GetATRValues(atrNow, atrAvg))
     {
      WebBridge_ExportStatus();
      return;
     }

   double ratio = (atrAvg>0) ? atrNow/atrAvg : 1.0;
   bool atrOK;
   GetATRRegime(ratio, atrOK);

   double slopePts = 0.0;
   GetEMASlopePoints(slopePts);

   // ---- reset harian (equity awal hari, target/loss harian) ----
   MqlDateTime now, start;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(g_dayStart, start);
   if(now.day != start.day || now.mon != start.mon || now.year != start.year)
     {
      g_dayStart       = TimeCurrent();
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyTargetHit = false;
      g_dailyLossHit   = false;
     }
   g_dailyProfit = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity;

   UpdateCooldownOnNewBar();
   UpdateATRSpikePause(atrNow, atrAvg);
   CheckDailyLimits();

   if(g_accountLocked && InpUseConditionalAutoReset)
      CheckConditionalAutoReset(atrOK, slopePts);

   bool halted = (g_dailyTargetHit || g_dailyLossHit || g_accountLocked || g_webPaused);
   if(!halted)
     {
      ManageBasketExit(1, atrNow);
      ManageBasketExit(-1, atrNow);

      ProcessBasketEntry(1,  emaDir, ema200, stochMain, atrOK, closeNow, atrNow);
      ProcessBasketEntry(-1, emaDir, ema200, stochMain, atrOK, closeNow, atrNow);
     }
   else
     {
      ManageBasketExit(1, atrNow);
      ManageBasketExit(-1, atrNow);
     }

   if(InpShowPanel)
      UpdatePanel(emaDir, ema200, stochMain, atrNow, atrAvg, closeNow);

   WebBridge_ExportStatus();
  }
//+------------------------------------------------------------------+
