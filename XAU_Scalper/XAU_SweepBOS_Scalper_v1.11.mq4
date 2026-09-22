//+------------------------------------------------------------------+
//|                        XAU_SweepBOS_Scalper.mq4                  |
//|   Rule-based M5 XAUUSD Liquidity-Sweep + BOS Scalping EA         |
//|   Faithful implementation of the supplied strategy.             |
//|   SIGNAL-ONLY by default. No entry rule invented or removed.    |
//|   v1.10 - strict 3-candle FVG, swing-after-sweep BOS, debug.    |
//+------------------------------------------------------------------+
#property copyright "Rule-exact implementation"
#property version   "1.11"
#property strict

//============================ INPUTS ==============================
input string  h_General          = "===== General =====";            // ---
input bool    SignalOnly         = true;      // true=signals only, false=live trades
input string  SymbolOverride     = "";        // empty => use chart symbol
input int     MagicNumber        = 20260920;  // EA magic number
input int     MaxSlippagePoints  = 30;        // max slippage (points)

input string  h_Trend            = "===== M15 Trend Filter =====";    // ---
input int     EMA_Period         = 50;        // M15 EMA period
input int     EMA_SlopeLookback  = 3;         // bars to measure EMA slope
input int     M15_StructLookback = 12;        // bars for M15 structure

input string  h_Sweep            = "===== Liquidity Sweep (M5) ====="; // ---
input int     SwingHalfWidth     = 5;         // fractal half-width for swing
input int     SweepSearchBars    = 40;        // how far back to seek swing
input int     SweepValidBars     = 6;         // sweep must resolve within N bars

input string  h_BOS              = "===== Structure Break (BOS) =====";// ---
input int     BOS_HalfWidth      = 3;         // minor swing half-width
input int     BOS_ValidBars      = 8;         // BOS must occur within N bars

input string  h_Pull             = "===== Pullback =====";            // ---
input int     Pullback_ValidBars = 8;         // pullback+confirm window
input bool    UseFVG             = true;       // enable 3-candle FVG detection
input bool    RequireFVG         = false;      // true=only FVG retest; false=FVG OR BOS retest
input double  MinFVG_ATR_Fraction= 0.05;       // min FVG size = this * ATR(14)

input string  h_Mom              = "===== Momentum Filters =====";     // ---
input int     ATR_Period         = 14;        // ATR period (M5)
input int     ATR_AvgPeriod      = 20;        // ATR average period
input double  ATR_Threshold      = 0.80;      // ATR >= threshold * avgATR
input int     RSI_Period         = 14;        // RSI period (M5)
input double  RSI_Level          = 50.0;      // RSI directional level

input string  h_VWAP             = "===== VWAP =====";                // ---
input bool    UseVWAPFilter      = true;       // session VWAP filter on/off

input string  h_Risk             = "===== Stop / Target =====";       // ---
input double  SL_ATR_Buffer      = 0.10;      // SL buffer = ATR * this
input double  SL_Min_ATR         = 0.60;      // min SL distance (xATR)
input double  SL_Max_ATR         = 1.50;      // max SL distance (xATR)
input double  TP_R_Multiple      = 1.5;       // TP = R * this (test 1.2/1.5/2.0)
input double  RiskPercent        = 0.5;       // % equity risk (live). <=0 => fixed lots
input double  FixedLots          = 0.01;      // fixed lot fallback

input string  h_Time             = "===== Time Exit =====";           // ---
input int     TimeExitBars       = 12;        // close after N completed M5 bars

input string  h_Spr              = "===== Spread =====";              // ---
input double  MaxAllowedSpread   = 40;        // max spread in points

input string  h_Sess             = "===== Sessions (server HH:MM) =====";// ---
input string  LondonStart        = "08:00";
input string  LondonEnd          = "12:00";
input string  NYStart            = "12:00";
input string  NYEnd              = "16:00";

input string  h_Lim              = "===== Trade Limits =====";        // ---
input int     MaxOpenTrades      = 1;
input int     MaxTradesPerDay    = 3;
input int     MaxConsecLosses    = 2;

input string  h_Disp             = "===== Display =====";             // ---
input bool    DebugMode          = true;       // show detailed diagnostics panel
input color   BuyColor           = clrLime;
input color   SellColor          = clrRed;
input color   TPColor            = clrDeepSkyBlue;
input color   SLColor            = clrOrangeRed;

//============================ GLOBALS =============================
string   Sym;
int      Dig;
double   Pnt;
string   Pfx = "SBS_";

enum ESetup { ST_IDLE=0, ST_BOS_WAIT=1, ST_PULLBACK_WAIT=2, ST_CONFIRM_WAIT=3 };
int      g_state    = ST_IDLE;
int      g_dir      = 0;       // +1 buy, -1 sell
double   g_sweepLvl = 0.0;     // swept swing low/high
datetime g_sweepTime= 0;
double   g_bosLvl   = 0.0;     // minor swing broken
datetime g_bosTime  = 0;
int      g_stateBars= 0;
bool     g_fvgValid = false;   // valid 3-candle FVG present
double   g_fvgUpper = 0.0;     // FVG zone upper boundary
double   g_fvgLower = 0.0;     // FVG zone lower boundary
datetime g_fvgTime  = 0;       // FVG anchor (older candle) time
string   g_phase    = "IDLE";  // display phase
double   g_lastSLdist= 0.0;    // last signal SL distance
double   g_lastRR    = 0.0;    // last signal RR

datetime g_lastM5Bar= 0;
datetime g_curDay   = 0;
string   g_sigText  = "(none)";
string   g_blockReason = "(none)";

//============================ INIT ================================
int OnInit()
{
   Sym = (SymbolOverride=="" ? Symbol() : SymbolOverride);
   Dig = (int)MarketInfo(Sym, MODE_DIGITS);
   Pnt = MarketInfo(Sym, MODE_POINT);
   ResetSetup();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, Pfx);
   Comment("");
}

void ResetSetup()
{
   g_state=ST_IDLE; g_dir=0; g_sweepLvl=0; g_sweepTime=0;
   g_bosLvl=0; g_bosTime=0; g_stateBars=0;
   g_fvgValid=false; g_fvgUpper=0; g_fvgLower=0; g_fvgTime=0;
   g_phase="IDLE";
}
//===================== TIME / SESSION =========================
int HHMMtoMin(string s)
{
   int p=StringFind(s,":"); if(p<0) return(-1);
   int hh=(int)StringToInteger(StringSubstr(s,0,p));
   int mm=(int)StringToInteger(StringSubstr(s,p+1));
   return(hh*60+mm);
}
int NowMinutes(){ return(TimeHour(TimeCurrent())*60 + TimeMinute(TimeCurrent())); }
bool InRange(int now,int a,int b)
{
   if(a<=b) return(now>=a && now<b);
   return(now>=a || now<b);
}
string CurrentSession()
{
   int now=NowMinutes();
   if(InRange(now,HHMMtoMin(LondonStart),HHMMtoMin(LondonEnd))) return("London");
   if(InRange(now,HHMMtoMin(NYStart),HHMMtoMin(NYEnd)))         return("EarlyNY");
   return("");
}
bool InSession(){ return(CurrentSession()!=""); }

double CurrentSpreadPoints()
{
   double ask=MarketInfo(Sym,MODE_ASK), bid=MarketInfo(Sym,MODE_BID);
   if(Pnt<=0) return(0);
   return((ask-bid)/Pnt);
}

//===================== INDICATORS =============================
double EMAv(int tf,int period,int shift){ return(iMA(Sym,tf,period,0,MODE_EMA,PRICE_CLOSE,shift)); }
double ATRv(int tf,int period,int shift){ return(iATR(Sym,tf,period,shift)); }
double AvgATR(int tf,int period,int avgN)
{
   double s=0; for(int i=1;i<=avgN;i++) s+=iATR(Sym,tf,period,i);
   return(avgN>0? s/avgN : 0);
}
double RSIv(int shift){ return(iRSI(Sym,PERIOD_M5,RSI_Period,PRICE_CLOSE,shift)); }

//===================== SWING DETECTION ========================
bool IsSwingHigh(int tf,int shift,int w)
{
   double h=iHigh(Sym,tf,shift);
   for(int k=1;k<=w;k++)
   { if(iHigh(Sym,tf,shift+k)>h) return(false);
     if(iHigh(Sym,tf,shift-k)>h) return(false); }
   return(true);
}
bool IsSwingLow(int tf,int shift,int w)
{
   double l=iLow(Sym,tf,shift);
   for(int k=1;k<=w;k++)
   { if(iLow(Sym,tf,shift+k)<l) return(false);
     if(iLow(Sym,tf,shift-k)<l) return(false); }
   return(true);
}
int FindRecentSwingLow(int tf,int w,int maxback,double &lvl)
{
   for(int s=w+1;s<=maxback;s++)
      if(IsSwingLow(tf,s,w)){ lvl=iLow(Sym,tf,s); return(s); }
   lvl=0; return(-1);
}
int FindRecentSwingHigh(int tf,int w,int maxback,double &lvl)
{
   for(int s=w+1;s<=maxback;s++)
      if(IsSwingHigh(tf,s,w)){ lvl=iHigh(Sym,tf,s); return(s); }
   lvl=0; return(-1);
}

// Find nearest confirmed swing high formed AFTER g_sweepTime (index >= 2 to be confirmed)
int FindSwingHighAfterSweep(int tf,int w,int maxback,double &lvl)
{
   for(int s=w+1;s<=maxback;s++)
   {
      datetime st=iTime(Sym,tf,s);
      if(st<=g_sweepTime) break;           // older than sweep -> stop
      if(IsSwingHigh(tf,s,w)){ lvl=iHigh(Sym,tf,s); return(s); }
   }
   lvl=0; return(-1);
}
// Find nearest confirmed swing low formed AFTER g_sweepTime
int FindSwingLowAfterSweep(int tf,int w,int maxback,double &lvl)
{
   for(int s=w+1;s<=maxback;s++)
   {
      datetime st=iTime(Sym,tf,s);
      if(st<=g_sweepTime) break;
      if(IsSwingLow(tf,s,w)){ lvl=iLow(Sym,tf,s); return(s); }
   }
   lvl=0; return(-1);
}

//===================== M15 TREND ==============================
int M15Trend()  // +1 bull, -1 bear, 0 unclear
{
   double emaNow =EMAv(PERIOD_M15,EMA_Period,1);
   double emaPast=EMAv(PERIOD_M15,EMA_Period,1+EMA_SlopeLookback);
   double close1 =iClose(Sym,PERIOD_M15,1);
   double slope  =emaNow-emaPast;
   bool bull=(close1>emaNow)&&(slope>0);
   bool bear=(close1<emaNow)&&(slope<0);
   int hw=MathMax(1,M15_StructLookback/2);
   double loFirst=iLow(Sym,PERIOD_M15, iLowest(Sym,PERIOD_M15,MODE_LOW,hw,1));
   double loPrev =iLow(Sym,PERIOD_M15, iLowest(Sym,PERIOD_M15,MODE_LOW,hw,1+hw));
   double hiFirst=iHigh(Sym,PERIOD_M15, iHighest(Sym,PERIOD_M15,MODE_HIGH,hw,1));
   double hiPrev =iHigh(Sym,PERIOD_M15, iHighest(Sym,PERIOD_M15,MODE_HIGH,hw,1+hw));
   bool higherStruct=(loFirst>=loPrev)&&(hiFirst>=hiPrev); // bullish: no bearish break
   bool lowerStruct =(hiFirst<=hiPrev)&&(loFirst<=loPrev); // bearish: no bullish break
   if(bull && higherStruct) return(+1);
   if(bear && lowerStruct)  return(-1);
   return(0);
}

//===================== SESSION VWAP ===========================
double SessionVWAP()
{
   datetime now=TimeCurrent();
   int startMin=HHMMtoMin(LondonStart);
   datetime sessStart=StrToTime(StringFormat("%04d.%02d.%02d %02d:%02d",
        TimeYear(now),TimeMonth(now),TimeDay(now), startMin/60, startMin%60));
   if(sessStart>now) sessStart-=86400;
   double pv=0, vv=0; int tot=Bars(Sym,PERIOD_M5);
   for(int i=0;i<tot;i++)
   {
      datetime bt=iTime(Sym,PERIOD_M5,i);
      if(bt<sessStart) break;
      double tp=(iHigh(Sym,PERIOD_M5,i)+iLow(Sym,PERIOD_M5,i)+iClose(Sym,PERIOD_M5,i))/3.0;
      double vol=(double)iVolume(Sym,PERIOD_M5,i);
      pv+=tp*vol; vv+=vol;
   }
   if(vv<=0) return(0);
   return(pv/vv);
}

//===================== 3-CANDLE FVG ==========================
// Bullish FVG: Low(C3) > High(C1) → zone = High(C1) → Low(C3)
// C1=older, C2=impulse, C3=newer  (all closed, shift ≥ 2)
bool DetectBullishFVG(int &c1Idx, double &fvgUpper, double &fvgLower)
{
   double atr=ATRv(PERIOD_M5,ATR_Period,1);
   double minGap=MinFVG_ATR_Fraction*atr;
   if(minGap<=0) minGap=Pnt;
   int win=BOS_ValidBars+2;                         // impulse neighbourhood only
   for(int i=1;i<=win && i+2<SweepSearchBars;i++)    // start at shift 1 (freshest FVG)
   {
      // C1 = i+2 (older), C2 = i+1 (impulse), C3 = i (newer)
      double h1=iHigh(Sym,PERIOD_M5,i+2);
      double l3=iLow(Sym,PERIOD_M5,i);
      if(l3>h1)
      {
         if(l3-h1>=minGap && iTime(Sym,PERIOD_M5,i+2)>=g_sweepTime)
         { c1Idx=i+2; fvgUpper=l3; fvgLower=h1; return(true); }
      }
   }
   return(false);
}
// Bearish FVG: High(C3) < Low(C1) → zone = High(C3) → Low(C1)
bool DetectBearishFVG(int &c1Idx, double &fvgUpper, double &fvgLower)
{
   double atr=ATRv(PERIOD_M5,ATR_Period,1);
   double minGap=MinFVG_ATR_Fraction*atr;
   if(minGap<=0) minGap=Pnt;
   int win=BOS_ValidBars+2;                         // impulse neighbourhood only
   for(int i=1;i<=win && i+2<SweepSearchBars;i++)    // start at shift 1 (freshest FVG)
   {
      double l1=iLow(Sym,PERIOD_M5,i+2);
      double h3=iHigh(Sym,PERIOD_M5,i);
      if(h3<l1)
      {
         if(l1-h3>=minGap && iTime(Sym,PERIOD_M5,i+2)>=g_sweepTime)
         { c1Idx=i+2; fvgUpper=l1; fvgLower=h3; return(true); }
      }
   }
   return(false);
}

//===================== CONFIRMATION CANDLE ====================
bool BullConfirm(int shift)
{
   double o=iOpen(Sym,PERIOD_M5,shift), c=iClose(Sym,PERIOD_M5,shift);
   double h=iHigh(Sym,PERIOD_M5,shift), l=iLow(Sym,PERIOD_M5,shift);
   double po=iOpen(Sym,PERIOD_M5,shift+1), pc=iClose(Sym,PERIOD_M5,shift+1);
   double rng=h-l; if(rng<=0) return(false);
   bool bullish=c>o;
   bool closeUpper=(c-l)/rng>=0.5;
   bool engulf=bullish&&(pc<po)&&(c>=po)&&(o<=pc);
   double body=MathAbs(c-o), lowWick=MathMin(o,c)-l;
   bool pin=bullish&&(lowWick>=body*1.5)&&closeUpper;
   return(bullish && closeUpper && (engulf||pin));
}
bool BearConfirm(int shift)
{
   double o=iOpen(Sym,PERIOD_M5,shift), c=iClose(Sym,PERIOD_M5,shift);
   double h=iHigh(Sym,PERIOD_M5,shift), l=iLow(Sym,PERIOD_M5,shift);
   double po=iOpen(Sym,PERIOD_M5,shift+1), pc=iClose(Sym,PERIOD_M5,shift+1);
   double rng=h-l; if(rng<=0) return(false);
   bool bearish=c<o;
   bool closeLower=(h-c)/rng>=0.5;
   bool engulf=bearish&&(pc>po)&&(c<=po)&&(o>=pc);
   double body=MathAbs(c-o), upWick=h-MathMax(o,c);
   bool pin=bearish&&(upWick>=body*1.5)&&closeLower;
   return(bearish && closeLower && (engulf||pin));
}
//===================== COUNTERS / LIMITS ======================
void CheckNewDay()
{
   datetime today=StrToTime(TimeToStr(TimeCurrent(),TIME_DATE));
   if(today!=g_curDay) g_curDay=today;
}
int OpenTrades()
{
   int c=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
     if(OrderSymbol()==Sym && OrderMagicNumber()==MagicNumber && OrderType()<=OP_SELL) c++; }
   return(c);
}
int TradesToday()
{
   int cnt=0; datetime dayStart=StrToTime(TimeToStr(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
     if(OrderSymbol()!=Sym||OrderMagicNumber()!=MagicNumber) continue;
     if(OrderType()>OP_SELL) continue;
     if(OrderOpenTime()>=dayStart) cnt++; }
   return(cnt);
}
int ConsecLosses()
{
   int total=OrdersHistoryTotal(); datetime ct[]; double pl[]; int n=0;
   ArrayResize(ct,total); ArrayResize(pl,total);
   for(int i=0;i<total;i++)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
     if(OrderSymbol()!=Sym||OrderMagicNumber()!=MagicNumber) continue;
     if(OrderType()>OP_SELL) continue;
     ct[n]=OrderCloseTime(); pl[n]=OrderProfit()+OrderSwap()+OrderCommission(); n++; }
   for(int a=0;a<n-1;a++) for(int b=a+1;b<n;b++)
     if(ct[b]<ct[a]){datetime tt=ct[a];ct[a]=ct[b];ct[b]=tt;double pp=pl[a];pl[a]=pl[b];pl[b]=pp;}
   int losses=0;
   for(int i=n-1;i>=0;i--){ if(pl[i]<0.0) losses++; else break; }
   return(losses);
}

//===================== STAGE 1: SWEEP =========================
// A sweep = trade beyond a confirmed swing, then CLOSE back on the origin
// side, with <=1 close beyond (NOT a continuation breakout).
void TryDetectBuySweep()
{
   double lvl; int sidx=FindRecentSwingLow(PERIOD_M5,SwingHalfWidth,SweepSearchBars,lvl);
   if(sidx<0) return;
   bool brokeBelow=false; int closesBelow=0, breakShift=-1;
   int span=MathMin(sidx-1,SweepValidBars);
   for(int s=1;s<=span;s++)
   { if(iLow(Sym,PERIOD_M5,s)<lvl){brokeBelow=true; if(breakShift<0)breakShift=s;}
     if(iClose(Sym,PERIOD_M5,s)<lvl) closesBelow++; }
   bool returnedAbove=iClose(Sym,PERIOD_M5,1)>lvl;   // closed back above swept low
   if(brokeBelow && returnedAbove && closesBelow<=1)
   { g_dir=+1; g_sweepLvl=lvl; g_sweepTime=iTime(Sym,PERIOD_M5,breakShift); g_state=ST_BOS_WAIT; g_stateBars=0; g_phase="SWEEP"; }
}
void TryDetectSellSweep()
{
   double lvl; int sidx=FindRecentSwingHigh(PERIOD_M5,SwingHalfWidth,SweepSearchBars,lvl);
   if(sidx<0) return;
   bool brokeAbove=false; int closesAbove=0, breakShift=-1;
   int span=MathMin(sidx-1,SweepValidBars);
   for(int s=1;s<=span;s++)
   { if(iHigh(Sym,PERIOD_M5,s)>lvl){brokeAbove=true; if(breakShift<0)breakShift=s;}
     if(iClose(Sym,PERIOD_M5,s)>lvl) closesAbove++; }
   bool returnedBelow=iClose(Sym,PERIOD_M5,1)<lvl;   // closed back below swept high
   if(brokeAbove && returnedBelow && closesAbove<=1)
   { g_dir=-1; g_sweepLvl=lvl; g_sweepTime=iTime(Sym,PERIOD_M5,breakShift); g_state=ST_BOS_WAIT; g_stateBars=0; g_phase="SWEEP"; }
}

//===================== STAGE 2: BOS ===========================
// Nearest confirmed swing formed AFTER the sweep; a COMPLETED candle must
// CLOSE beyond it. On BOS, capture the 3-candle FVG of the impulse.
void TryDetectBullBOS()
{
   double lvl; int hidx=FindSwingHighAfterSweep(PERIOD_M5,BOS_HalfWidth,SweepSearchBars,lvl);
   if(hidx<0) return;
   if(iClose(Sym,PERIOD_M5,1)>lvl)   // completed-candle close above; crossing may have occurred on an earlier bar within the BOS window
   {
      g_bosLvl=lvl; g_bosTime=iTime(Sym,PERIOD_M5,1);
      g_fvgValid=false; g_fvgUpper=0; g_fvgLower=0; g_fvgTime=0;
      if(UseFVG)
      { int c1; double fu,fl;
        if(DetectBullishFVG(c1,fu,fl)){ g_fvgValid=true; g_fvgUpper=fu; g_fvgLower=fl; g_fvgTime=iTime(Sym,PERIOD_M5,c1); } }
      g_state=ST_PULLBACK_WAIT; g_stateBars=0; g_phase="PULLBACK_WAIT";
   }
}
void TryDetectBearBOS()
{
   double lvl; int lidx=FindSwingLowAfterSweep(PERIOD_M5,BOS_HalfWidth,SweepSearchBars,lvl);
   if(lidx<0) return;
   if(iClose(Sym,PERIOD_M5,1)<lvl)   // completed-candle close below; crossing may have occurred on an earlier bar within the BOS window
   {
      g_bosLvl=lvl; g_bosTime=iTime(Sym,PERIOD_M5,1);
      g_fvgValid=false; g_fvgUpper=0; g_fvgLower=0; g_fvgTime=0;
      if(UseFVG)
      { int c1; double fu,fl;
        if(DetectBearishFVG(c1,fu,fl)){ g_fvgValid=true; g_fvgUpper=fu; g_fvgLower=fl; g_fvgTime=iTime(Sym,PERIOD_M5,c1); } }
      g_state=ST_PULLBACK_WAIT; g_stateBars=0; g_phase="PULLBACK_WAIT";
   }
}

//===================== STAGE 3/4: PULLBACK + CONFIRM ==========
// Invalidation uses COMPLETED candles only (no intrabar noise).
bool SetupInvalidated(int dir)
{
   double c1=iClose(Sym,PERIOD_M5,1);
   if(dir>0)
   { if(g_fvgValid && c1<g_fvgLower) return(true);   // close below bullish FVG lower boundary
     if(c1<g_sweepLvl) return(true); }               // close below swept low
   else
   { if(g_fvgValid && c1>g_fvgUpper) return(true);   // close above bearish FVG upper boundary
     if(c1>g_sweepLvl) return(true); }
   return(false);
}
// Pullback: FVG-zone touch OR (if allowed) BOS retest area.
bool PullbackTouched(int dir)
{
   double atr=ATRv(PERIOD_M5,ATR_Period,1);
   double hi1=iHigh(Sym,PERIOD_M5,1), lo1=iLow(Sym,PERIOD_M5,1);
   bool fvgTouch=false;
   if(g_fvgValid) fvgTouch=(lo1<=g_fvgUpper && hi1>=g_fvgLower);   // intersection with FVG zone
   if(RequireFVG) return(g_fvgValid && fvgTouch);                  // FVG-only mode
   bool retest=(dir>0? (lo1<=g_bosLvl+atr*0.25) : (hi1>=g_bosLvl-atr*0.25));
   return(fvgTouch || retest);                                     // FVG OR BOS retest
}
void HandleConfirmWait(int dir)
{
   if(SetupInvalidated(dir)){ ResetSetup(); return; }
   if(dir>0){ if(!BullConfirm(1)) return; }
   else     { if(!BearConfirm(1)) return; }
   FireSignal(dir);
}
void HandlePullbackWait(int dir)
{
   if(SetupInvalidated(dir)){ ResetSetup(); return; }
   if(!PullbackTouched(dir)) return;
   g_state=ST_CONFIRM_WAIT; g_stateBars=0; g_phase="CONFIRMATION_WAIT";
   HandleConfirmWait(dir);   // allow same-bar confirmation (touch candle may confirm)
}

//===================== STATE MACHINE ==========================
void EvaluateSetup()
{
   int trend=M15Trend();
   if(g_state!=ST_IDLE && trend!=g_dir){ g_blockReason="M15_TREND_FLIP"; ResetSetup(); return; }
   if(g_state!=ST_IDLE) g_stateBars++;

   if(g_state==ST_IDLE && trend!=0)
   { g_phase="IDLE"; if(trend>0) TryDetectBuySweep(); else TryDetectSellSweep(); }
   else if(g_state==ST_BOS_WAIT)
   { g_phase="BOS_WAIT";
     if(g_stateBars>SweepValidBars+BOS_ValidBars){ g_blockReason="BOS_TIMEOUT"; ResetSetup(); return; }
     if(g_dir>0) TryDetectBullBOS(); else TryDetectBearBOS(); }
   else if(g_state==ST_PULLBACK_WAIT)
   { g_phase="PULLBACK_WAIT";
     if(g_stateBars>BOS_ValidBars+Pullback_ValidBars){ g_blockReason="PULLBACK_TIMEOUT"; ResetSetup(); return; }
     HandlePullbackWait(g_dir); }
   else if(g_state==ST_CONFIRM_WAIT)
   { g_phase="CONFIRMATION_WAIT";
     if(g_stateBars>BOS_ValidBars+2*Pullback_ValidBars){ g_blockReason="CONFIRMATION_TIMEOUT"; ResetSetup(); return; }
     HandleConfirmWait(g_dir); }
}

//===================== FIRE SIGNAL ============================
void FireSignal(int dir)
{
   double atr=ATRv(PERIOD_M5,ATR_Period,1);
   double aatr=AvgATR(PERIOD_M5,ATR_Period,ATR_AvgPeriod);
   if(aatr>0 && atr<ATR_Threshold*aatr){ g_blockReason="ATR"; ResetSetup(); return; }
   double rsi=RSIv(1);
   if(dir>0 && !(rsi>RSI_Level)){ g_blockReason="RSI_BUY"; ResetSetup(); return; }
   if(dir<0 && !(rsi<RSI_Level)){ g_blockReason="RSI_SELL"; ResetSetup(); return; }
   double vwap=(UseVWAPFilter? SessionVWAP():0);
   double px=(dir>0? MarketInfo(Sym,MODE_ASK):MarketInfo(Sym,MODE_BID));
   if(UseVWAPFilter && vwap>0)
   {
      if(dir>0 && !(px>vwap)){ g_blockReason="VWAP_BUY"; ResetSetup(); return; }
      if(dir<0 && !(px<vwap)){ g_blockReason="VWAP_SELL"; ResetSetup(); return; }
   }
   if(!InSession()){ g_blockReason="SESSION"; ResetSetup(); return; }
   if(CurrentSpreadPoints()>MaxAllowedSpread){ g_blockReason="SPREAD"; ResetSetup(); return; }
   if(OpenTrades()>=MaxOpenTrades){ g_blockReason="OPEN_TRADES_LIMIT"; ResetSetup(); return; }
   if(TradesToday()>=MaxTradesPerDay){ g_blockReason="DAILY_TRADE_LIMIT"; ResetSetup(); return; }
   if(ConsecLosses()>=MaxConsecLosses){ g_blockReason="CONSEC_LOSS_LIMIT"; ResetSetup(); return; }

   double entry=px, sl, tp, risk;
   if(dir>0){ sl=g_sweepLvl-atr*SL_ATR_Buffer; risk=entry-sl; }
   else     { sl=g_sweepLvl+atr*SL_ATR_Buffer; risk=sl-entry; }
   if(risk<SL_Min_ATR*atr){ g_blockReason="SL_TOO_TIGHT"; ResetSetup(); return; }
   if(risk>SL_Max_ATR*atr){ g_blockReason="SL_TOO_WIDE"; ResetSetup(); return; }
   tp=(dir>0? entry+risk*TP_R_Multiple : entry-risk*TP_R_Multiple);

   g_lastSLdist=risk; g_lastRR=TP_R_Multiple; g_phase="SIGNAL";
   g_blockReason="SIGNAL_READY";
   BuildSignalGraphics(dir,entry,sl,tp,TP_R_Multiple,atr,rsi,vwap);
   if(!SignalOnly) ExecuteTrade(dir,sl,tp,risk);
   ResetSetup();
}

//===================== EXECUTION (ECN) ========================
double NormalizeLots(double l)
{
   double mn=MarketInfo(Sym,MODE_MINLOT), mx=MarketInfo(Sym,MODE_MAXLOT), st=MarketInfo(Sym,MODE_LOTSTEP);
   if(st<=0) st=0.01;
   l=MathFloor(l/st)*st;
   if(l<mn) l=mn; if(l>mx) l=mx;
   return(l);
}
double CalcLots(double riskDist)
{
   if(RiskPercent<=0) return(NormalizeLots(FixedLots));
   double tickVal=MarketInfo(Sym,MODE_TICKVALUE), tickSz=MarketInfo(Sym,MODE_TICKSIZE);
   if(tickSz<=0||riskDist<=0) return(NormalizeLots(FixedLots));
   double riskMoney=AccountEquity()*RiskPercent/100.0;
   double lossPerLot=(riskDist/tickSz)*tickVal;
   if(lossPerLot<=0) return(NormalizeLots(FixedLots));
   return(NormalizeLots(riskMoney/lossPerLot));
}
void ExecuteTrade(int dir,double sl,double tp,double risk)
{
   double lots=CalcLots(risk);
   int type=(dir>0? OP_BUY:OP_SELL);
   double stopLevel=MarketInfo(Sym,MODE_STOPLEVEL)*Pnt;
   for(int attempt=0;attempt<3;attempt++)
   {
      RefreshRates();
      double price=(dir>0? MarketInfo(Sym,MODE_ASK):MarketInfo(Sym,MODE_BID));
      // ECN-safe: open market order first WITHOUT SL/TP, then OrderModify
      int ticket=OrderSend(Sym,type,lots,NormalizeDouble(price,Dig),MaxSlippagePoints,
                           0,0,"SweepBOS",MagicNumber,0,(dir>0?BuyColor:SellColor));
      if(ticket<0){ Print("OrderSend err ",GetLastError()); Sleep(300); continue; }
      if(OrderSelect(ticket,SELECT_BY_TICKET))
      {
         double op=OrderOpenPrice();
         double sl2=(dir>0? op-risk : op+risk);
         double tp2=(dir>0? op+risk*TP_R_Multiple : op-risk*TP_R_Multiple);
         if(dir>0){ if(op-sl2<stopLevel) sl2=op-stopLevel; if(tp2-op<stopLevel) tp2=op+stopLevel; }
         else     { if(sl2-op<stopLevel) sl2=op+stopLevel; if(op-tp2<stopLevel) tp2=op-stopLevel; }
         if(!OrderModify(ticket,op,NormalizeDouble(sl2,Dig),NormalizeDouble(tp2,Dig),0,clrNONE))
            Print("OrderModify err ",GetLastError());
      }
      break;
   }
}
void ManageOpenTrades()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
     if(OrderSymbol()!=Sym||OrderMagicNumber()!=MagicNumber) continue;
     if(OrderType()>OP_SELL) continue;
     int barsOpen=(int)((TimeCurrent()-OrderOpenTime())/PeriodSeconds(PERIOD_M5));
     if(barsOpen>=TimeExitBars)
     { RefreshRates();
       double cp=(OrderType()==OP_BUY? MarketInfo(Sym,MODE_BID):MarketInfo(Sym,MODE_ASK));
       if(!OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(cp,Dig),MaxSlippagePoints,clrYellow))
          Print("Time-exit close err ",GetLastError()); } }
}

//===================== DISPLAY ================================
void DrawHLine(string name,double price,color c,int style)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}
void BuildSignalGraphics(int dir,double entry,double sl,double tp,double rr,double atr,double rsi,double vwap)
{
   datetime t=iTime(Sym,PERIOD_M5,0);
   string tag=(dir>0?"BUY":"SELL");
   color col=(dir>0?BuyColor:SellColor);
   // entry arrow
   string an=Pfx+"arr_"+(string)t;
   if(ObjectFind(0,an)>=0) ObjectDelete(0,an);
   double ap=(dir>0? iLow(Sym,PERIOD_M5,1)-atr*0.2 : iHigh(Sym,PERIOD_M5,1)+atr*0.2);
   ObjectCreate(0,an,OBJ_ARROW,0,t,ap);
   ObjectSetInteger(0,an,OBJPROP_ARROWCODE,(dir>0?233:234));
   ObjectSetInteger(0,an,OBJPROP_COLOR,col);
   ObjectSetInteger(0,an,OBJPROP_WIDTH,2);
   // entry / SL / TP lines
   DrawHLine(Pfx+"entry",entry,col,STYLE_SOLID);
   DrawHLine(Pfx+"sl",sl,SLColor,STYLE_DASH);
   DrawHLine(Pfx+"tp",tp,TPColor,STYLE_DASH);
   // sweep & BOS reference lines
   DrawHLine(Pfx+"sweep",g_sweepLvl,clrSilver,STYLE_DOT);
   DrawHLine(Pfx+"bos",g_bosLvl,clrAqua,STYLE_DOT);
   // FVG rectangle (only if a real FVG exists)
   string rn=Pfx+"fvg";
   if(ObjectFind(0,rn)>=0) ObjectDelete(0,rn);
   if(g_fvgValid)
   {
      ObjectCreate(0,rn,OBJ_RECTANGLE,0,g_fvgTime,g_fvgUpper,t,g_fvgLower);
      ObjectSetInteger(0,rn,OBJPROP_COLOR,col);
      ObjectSetInteger(0,rn,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,rn,OBJPROP_BACK,true);
   }
   string sess=CurrentSession(); if(sess=="") sess="OUT";
   int tr=M15Trend(); string trS=(tr>0?"BULLISH":tr<0?"BEARISH":"UNCLEAR");
   g_sigText=StringFormat("%s Entry:%s SL:%s TP:%s RR:%.2f | %s | ATR:%.2f RSI:%.1f FVG:%s M15:%s",
        tag,DoubleToStr(entry,Dig),DoubleToStr(sl,Dig),DoubleToStr(tp,Dig),rr,
        sess,atr,rsi,(g_fvgValid?"yes":"no"),trS);
   Print("SIGNAL >> ",g_sigText);
}
void UpdateStatus()
{
   if(!DebugMode)
   {
      Comment(StringFormat("XAU Sweep+BOS Scalper [%s]  Mode:%s  State:%s\nLast Signal: %s\nLast Block: %s",
              Sym,(SignalOnly?"SIGNAL-ONLY":"LIVE"),g_phase,g_sigText,g_blockReason));
      return;
   }
   int tr=M15Trend(); string trS=(tr>0?"BULLISH":tr<0?"BEARISH":"UNCLEAR");
   double atr=ATRv(PERIOD_M5,ATR_Period,1), aatr=AvgATR(PERIOD_M5,ATR_Period,ATR_AvgPeriod);
   double rsi=RSIv(1); double vw=(UseVWAPFilter?SessionVWAP():0);
   string sess=CurrentSession(); if(sess=="") sess="OUT";
   string fvgS=(g_fvgValid?StringFormat("VALID [%s-%s]",DoubleToStr(g_fvgLower,Dig),DoubleToStr(g_fvgUpper,Dig)):"none");
   double fvgSize=(g_fvgValid? g_fvgUpper-g_fvgLower : 0);
   Comment(StringFormat(
     "XAU Sweep+BOS Scalper  [%s]  Mode:%s\nState: %s   M15 Trend: %s\nSweep: %s   BOS: %s\nFVG: %s  size:%.2f (min %.2f)\nSession: %s   Spread: %.0f/%.0f pts\nATR: %.2f (avg %.2f, min %.2f)   RSI: %.1f\nVWAP: %.2f (%s)\nLast SL dist: %.2f   RR: %.2f\nTradesToday: %d/%d  ConsecLoss: %d/%d\nLast Signal: %s",
     Sym,(SignalOnly?"SIGNAL-ONLY":"LIVE"),g_phase,trS,
     (g_sweepLvl>0?DoubleToStr(g_sweepLvl,Dig):"-"),(g_bosLvl>0?DoubleToStr(g_bosLvl,Dig):"-"),
     fvgS,fvgSize,MinFVG_ATR_Fraction*atr,
     sess,CurrentSpreadPoints(),MaxAllowedSpread,
     atr,aatr,ATR_Threshold*aatr,rsi,vw,(UseVWAPFilter?"on":"off"),
     g_lastSLdist,g_lastRR,TradesToday(),MaxTradesPerDay,ConsecLosses(),MaxConsecLosses,g_sigText,g_blockReason));
}

//===================== MAIN TICK ==============================
void OnTick()
{
   CheckNewDay();
   if(!SignalOnly) ManageOpenTrades();
   UpdateStatus();
   datetime b=iTime(Sym,PERIOD_M5,0);
   if(b!=g_lastM5Bar)
   { g_lastM5Bar=b; EvaluateSetup(); }
}
//+------------------------------------------------------------------+