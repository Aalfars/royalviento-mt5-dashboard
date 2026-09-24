//+------------------------------------------------------------------+
//| MoneyManagement.mqh                                              |
//| RoyalViento_Clone_EA v2.04                                       |
//| FIX v2.04 (Module 8 - Account Currency Safe):                  |
//|  - Parameter referensi Auto Lot tetap dalam USD agar preset     |
//|    lama mudah dipahami.                                          |
//|  - Untuk simbol dengan profit currency USD (termasuk XAUUSD),   |
//|    nominal USD otomatis dikonversi ke currency akun (IDR/USD).  |
//|  - Perhitungan step equity memakai nilai currency akun, bukan   |
//|    angka mentah 100/500 yang sebelumnya salah pada akun IDR.    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
#ifndef __RV_MONEYMANAGEMENT_MQH__
#define __RV_MONEYMANAGEMENT_MQH__

input group "=== Money Management / Auto Lot ==="
input double   InpBaseLot            = 0.01;     // Lot awal (dipakai jika Auto Lot OFF, atau sebagai lantai minimum)
input ENUM_LOT_AVERAGING_MODE InpLotMode = LOT_MODE_ADD_FLAT; // Mode lot averaging
input double   InpLotMultiplier      = 2.25;     // Multiplier averaging (mode = Multiplier)
input double   InpLotAddFlat         = 0.02;     // Penambahan lot flat (mode = Add Lot)
input bool     InpAutoLotByBalance   = true;     // Auto sesuaikan lot berdasarkan EQUITY (naik & turun)
input double   InpRiskPer100USD      = 0.01;     // Tambahan lot per kelipatan 100 USD equity (otomatis dikonversi ke currency akun)
input double   InpEquityBaseUnit     = 500.0;    // Equity acuan dalam USD (otomatis dikonversi ke currency akun)

//+------------------------------------------------------------------+
//| FIX v2.01 (dipertahankan): NormalizeDouble supaya volume tidak   |
//| menyisakan galat floating-point (mis. 0.010000000002) yang bisa  |
//| ditolak broker sebagai "invalid volume".                         |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   int stepDigits = 2;
   if(lotStep > 0)
      stepDigits = (int)MathRound(-MathLog10(lotStep));
   if(stepDigits < 0) stepDigits = 0;

   double normalized = MathRound(lot/lotStep)*lotStep;
   normalized = NormalizeDouble(normalized, stepDigits);
   normalized = MathMax(minLot, normalized);
   normalized = MathMin(normalized, maxLot);
   return normalized;
  }

//+------------------------------------------------------------------+
//| Base lot efektif, ikut naik/turun sesuai equity saat ini.        |
//| Equity turun -> steps turun -> lot ikut mengecil, bukan tetap    |
//| seperti versi lama yang berbasis balance & tidak pernah turun.   |
//+------------------------------------------------------------------+
// Konversi nominal USD ke mata uang deposit akun.
// Untuk XAUUSD/EURUSD/GBPUSD dst. profit currency = USD, sehingga
// profit 1 lot untuk perubahan harga +1.00 memberi kurs USD->account.
double USDToAccountCurrency(double usd)
  {
   if(usd <= 0.0) return 0.0;

   string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   if(accountCurrency == "USD") return usd;

   string profitCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(profitCurrency != "USD")
     {
      Print("[MoneyManagement] Profit currency simbol bukan USD (", profitCurrency,
            "). Konversi USD otomatis tidak dapat ditentukan; nominal USD dipakai apa adanya.");
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

double GetEquityBaseUnitAccount()
  {
   return USDToAccountCurrency(InpEquityBaseUnit);
  }

double GetEquityStepAccount()
  {
   return USDToAccountCurrency(100.0);
  }

double GetEffectiveBaseLot()
  {
   if(!InpAutoLotByBalance) return InpBaseLot;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseUnit = GetEquityBaseUnitAccount();
   double stepAmount = GetEquityStepAccount();
   if(stepAmount <= 0.0) return InpBaseLot;

   double steps = MathFloor((eq - baseUnit) / stepAmount);
   if(steps < 0) steps = 0;

   double lot = InpBaseLot + steps * InpRiskPer100USD;
   if(lot < InpBaseLot) lot = InpBaseLot;
   return lot;
  }

double GetEffectiveAddFlat()
  {
   if(!InpAutoLotByBalance) return InpLotAddFlat;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseUnit = GetEquityBaseUnitAccount();
   double stepAmount = GetEquityStepAccount();
   if(stepAmount <= 0.0) return InpLotAddFlat;

   double steps = MathFloor((eq - baseUnit) / stepAmount);
   if(steps < 0) steps = 0;

   double addFlat = InpLotAddFlat + steps * (InpRiskPer100USD * 0.5);
   if(addFlat < InpLotAddFlat) addFlat = InpLotAddFlat;
   return addFlat;
  }

//+------------------------------------------------------------------+
//| Hitung lot untuk entry berikutnya dalam basket                   |
//+------------------------------------------------------------------+
double CalcNextLot(int count, double lastLot)
  {
   double baseLot = GetEffectiveBaseLot();
   if(count == 0) return NormalizeLot(baseLot);

   if(InpLotMode == LOT_MODE_ADD_FLAT)
     {
      double addFlat = GetEffectiveAddFlat();
      return NormalizeLot(baseLot + count*addFlat);
     }
   else // LOT_MODE_MULTIPLIER
     {
      double lot = (lastLot > 0) ? lastLot*InpLotMultiplier : baseLot*InpLotMultiplier;
      return NormalizeLot(lot);
     }
  }

#endif // __RV_MONEYMANAGEMENT_MQH__
//+------------------------------------------------------------------+
