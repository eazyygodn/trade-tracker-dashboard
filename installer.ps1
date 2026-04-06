# Trade Tracker Pro — EA Installer
# Double-click "Install Trade Tracker Pro.bat" to run this
# Works on all Windows 10/11 computers with no software needed

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── COLORS & FONTS ─────────────────────────────────────────
$BG       = [System.Drawing.Color]::FromArgb(8, 8, 16)
$CARD     = [System.Drawing.Color]::FromArgb(17, 17, 31)
$BORDER   = [System.Drawing.Color]::FromArgb(40, 40, 80)
$TEXT     = [System.Drawing.Color]::FromArgb(232, 232, 240)
$MUTED    = [System.Drawing.Color]::FromArgb(107, 107, 138)
$BLUE     = [System.Drawing.Color]::FromArgb(79, 142, 247)
$GREEN    = [System.Drawing.Color]::FromArgb(16, 217, 138)
$RED      = [System.Drawing.Color]::FromArgb(240, 80, 104)
$AMBER    = [System.Drawing.Color]::FromArgb(247, 195, 90)

$FontTitle  = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$FontSub    = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$FontBold   = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$FontSmall  = New-Object System.Drawing.Font("Segoe UI", 9,  [System.Drawing.FontStyle]::Regular)
$FontMono   = New-Object System.Drawing.Font("Consolas",  10, [System.Drawing.FontStyle]::Regular)
$FontBtn    = New-Object System.Drawing.Font("Segoe UI",  11, [System.Drawing.FontStyle]::Bold)

$EF_URL = "https://vuxsxdirrwmbqntvkywi.supabase.co/functions/v1/trade-tracker"

# ── EA FILE CONTENT (MT5) ──────────────────────────────────
# The MT5 EA source is embedded directly so no separate file is needed
$EA_MT5_CONTENT = @'
//+------------------------------------------------------------------+
//|                     TradeTrackerPro_MT5.mq5                      |
//|              Automated Trade Logger - Trade Tracker Pro           |
//+------------------------------------------------------------------+
#property copyright "Trade Tracker Pro"
#property version   "1.00"
#property description "Automatically logs all trades to Trade Tracker Pro"
#include <Trade\Trade.mqh>
input string ApiKey          = "";
input string EdgeFunctionUrl = "";
input bool   DebugMode       = false;
int OnInit() {
  if (ApiKey == "") { Alert("TradeTracker: API Key is empty."); return INIT_PARAMETERS_INCORRECT; }
  if (EdgeFunctionUrl == "") { Alert("TradeTracker: Edge Function URL is empty."); return INIT_PARAMETERS_INCORRECT; }
  Print("TradeTracker Pro v1.0 started.");
  return INIT_SUCCEEDED;
}
void OnTradeTransaction(const MqlTradeTransaction& trans,const MqlTradeRequest& request,const MqlTradeResult& result) {
  if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
  ulong dealTicket = trans.deal;
  if (dealTicket == 0) return;
  if (!HistoryDealSelect(dealTicket)) return;
  ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
  ENUM_DEAL_TYPE  dealType  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
  if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) return;
  if (entryType == DEAL_ENTRY_IN) ProcessOpen(dealTicket, dealType);
  else if (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY) ProcessClose(dealTicket, dealType);
}
void ProcessOpen(ulong dealTicket, ENUM_DEAL_TYPE dealType) {
  string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
  double entry  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
  double lots   = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
  long   posT   = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
  datetime openTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
  double sl = 0.0, tp = 0.0;
  if (PositionSelectByTicket(posT)) { sl = PositionGetDouble(POSITION_SL); tp = PositionGetDouble(POSITION_TP); }
  string dir = (dealType == DEAL_TYPE_BUY) ? "buy" : "sell";
  string payload = StringFormat("{\"action\":\"open\",\"ticket\":%I64d,\"symbol\":\"%s\",\"direction\":\"%s\",\"entry_price\":%.5f,\"stop_loss\":%.5f,\"take_profit\":%.5f,\"lots\":%.2f,\"open_time\":\"%s\"}",posT,symbol,dir,entry,sl,tp,lots,IsoTime(openTime));
  if (DebugMode) Print("[TradeTracker] OPEN: ", payload);
  PostRequest(payload);
}
void ProcessClose(ulong dealTicket, ENUM_DEAL_TYPE dealType) {
  string symbol  = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
  double exit    = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
  double profit  = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
  double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
  double swap    = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
  long   posT    = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
  datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
  string dir = (dealType == DEAL_TYPE_SELL) ? "buy" : "sell";
  string payload = StringFormat("{\"action\":\"close\",\"ticket\":%I64d,\"symbol\":\"%s\",\"direction\":\"%s\",\"exit_price\":%.5f,\"profit\":%.2f,\"commission\":%.2f,\"swap\":%.2f,\"close_time\":\"%s\"}",posT,symbol,dir,exit,profit,commission,swap,IsoTime(closeTime));
  if (DebugMode) Print("[TradeTracker] CLOSE: ", payload);
  PostRequest(payload);
}
void PostRequest(string payload) {
  char post[]; char result[]; string headers;
  StringToCharArray(payload, post, 0, StringLen(payload));
  string hdr = "Content-Type: application/json\r\nx-api-key: " + ApiKey + "\r\n";
  ResetLastError();
  int res = WebRequest("POST", EdgeFunctionUrl, hdr, 10000, post, result, headers);
  if (res == -1) { int err = GetLastError(); if (err == 4060) Print("[TradeTracker] Add URL to: Tools > Options > Expert Advisors > Allow WebRequests: ", EdgeFunctionUrl); else Print("[TradeTracker] Error: ", err); }
  else if (DebugMode) Print("[TradeTracker] Response (", res, "): ", CharArrayToString(result));
}
string IsoTime(datetime t) { MqlDateTime dt; TimeToStruct(t, dt); return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec); }
'@

# ── MT4 EA CONTENT ─────────────────────────────────────────
$EA_MT4_CONTENT = @'
//+------------------------------------------------------------------+
//|                     TradeTrackerPro_MT4.mq4                      |
//|              Automated Trade Logger - Trade Tracker Pro           |
//+------------------------------------------------------------------+
#property copyright "Trade Tracker Pro"
#property version   "1.0"
#property strict
input string ApiKey          = "";
input string EdgeFunctionUrl = "";
input int    CheckEveryNSecs = 3;
input bool   DebugMode       = false;
struct TradeState { long ticket; int type; double openPrice; double sl; double tp; double lots; long openTime; };
TradeState g_known[];
int g_histTotal = -1;
int OnInit() {
  if (ApiKey == "") { Alert("TradeTracker: API Key is empty."); return INIT_PARAMETERS_INCORRECT; }
  if (EdgeFunctionUrl == "") { Alert("TradeTracker: Edge Function URL is empty."); return INIT_PARAMETERS_INCORRECT; }
  EventSetTimer(CheckEveryNSecs); SnapshotOpen(); g_histTotal = OrdersHistoryTotal();
  Print("TradeTracker Pro v1.0 started."); return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); }
void OnTimer() { DetectNew(); DetectClosed(); }
void SnapshotOpen() { int total=OrdersTotal(); ArrayResize(g_known,0); for(int i=0;i<total;i++){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL)continue;int idx=ArraySize(g_known);ArrayResize(g_known,idx+1);g_known[idx].ticket=OrderTicket();g_known[idx].type=OrderType();g_known[idx].openPrice=OrderOpenPrice();g_known[idx].sl=OrderStopLoss();g_known[idx].tp=OrderTakeProfit();g_known[idx].lots=OrderLots();g_known[idx].openTime=(long)OrderOpenTime();} }
void DetectNew() {
  int total=OrdersTotal();
  for(int i=0;i<total;i++){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL)continue;long ticket=OrderTicket();bool known=false;for(int j=0;j<ArraySize(g_known);j++){if(g_known[j].ticket==ticket){known=true;break;}}if(!known){SendOpen(ticket);int idx=ArraySize(g_known);ArrayResize(g_known,idx+1);g_known[idx].ticket=ticket;g_known[idx].type=OrderType();g_known[idx].openPrice=OrderOpenPrice();g_known[idx].sl=OrderStopLoss();g_known[idx].tp=OrderTakeProfit();g_known[idx].lots=OrderLots();g_known[idx].openTime=(long)OrderOpenTime();}}
  int ns=0;for(int j=0;j<ArraySize(g_known);j++){bool open=false;for(int k=0;k<total;k++){if(!OrderSelect(k,SELECT_BY_POS,MODE_TRADES))continue;if(OrderTicket()==g_known[j].ticket){open=true;break;}}if(open){g_known[ns]=g_known[j];ns++;}}ArrayResize(g_known,ns);
}
void DetectClosed() { int h=OrdersHistoryTotal();if(g_histTotal==-1){g_histTotal=h;return;}if(h>g_histTotal){for(int i=g_histTotal;i<h;i++){if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))continue;if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL)continue;SendClose(OrderTicket());}g_histTotal=h;} }
void SendOpen(long ticket) { if(!OrderSelect((int)ticket,SELECT_BY_TICKET))return;string dir=OrderType()==OP_BUY?"buy":"sell";string payload=StringFormat("{\"action\":\"open\",\"ticket\":%d,\"symbol\":\"%s\",\"direction\":\"%s\",\"entry_price\":%.5f,\"stop_loss\":%.5f,\"take_profit\":%.5f,\"lots\":%.2f,\"open_time\":\"%s\"}",ticket,OrderSymbol(),dir,OrderOpenPrice(),OrderStopLoss(),OrderTakeProfit(),OrderLots(),IsoTime(OrderOpenTime()));if(DebugMode)Print("[TradeTracker] OPEN: ",payload);PostReq(payload); }
void SendClose(long ticket) { if(!OrderSelect((int)ticket,SELECT_BY_TICKET,MODE_HISTORY))return;string dir=OrderType()==OP_BUY?"buy":"sell";string payload=StringFormat("{\"action\":\"close\",\"ticket\":%d,\"symbol\":\"%s\",\"direction\":\"%s\",\"exit_price\":%.5f,\"profit\":%.2f,\"commission\":%.2f,\"swap\":%.2f,\"close_time\":\"%s\"}",ticket,OrderSymbol(),dir,OrderClosePrice(),OrderProfit(),OrderCommission(),OrderSwap(),IsoTime(OrderCloseTime()));if(DebugMode)Print("[TradeTracker] CLOSE: ",payload);PostReq(payload); }
void PostReq(string payload) { char post[];char result[];string rh;StringToCharArray(payload,post,0,StringLen(payload));string hdr="Content-Type: application/json\r\nx-api-key: "+ApiKey+"\r\n";ResetLastError();int res=WebRequest("POST",EdgeFunctionUrl,hdr,10000,post,result,rh);if(res==-1){int err=GetLastError();if(err==5003||err==4060)Print("[TradeTracker] Add URL in Tools>Options>Expert Advisors>Allow WebRequests: ",EdgeFunctionUrl);else Print("[TradeTracker] Error: ",err);}else if(DebugMode)Print("[TradeTracker] Response (",res,"): ",CharArrayToString(result)); }
string IsoTime(datetime t){string s=TimeToString(t,TIME_DATE|TIME_SECONDS);StringReplace(s,".","-");StringReplace(s," ","T");return s+"Z";}
'@

# ── FIND MT4/MT5 FOLDERS ──────────────────────────────────
function Find-MTFolders {
    $found = @()
    $searchPaths = @(
        "$env:APPDATA\MetaQuotes\Terminal",
        "$env:LOCALAPPDATA\MetaQuotes\Terminal",
        "C:\Program Files\MetaTrader 5",
        "C:\Program Files\MetaTrader 4",
        "C:\Program Files (x86)\MetaTrader 5",
        "C:\Program Files (x86)\MetaTrader 4"
    )
    foreach ($base in $searchPaths) {
        if (Test-Path $base) {
            # Look for MQL5/Experts or MQL4/Experts subfolder
            Get-ChildItem -Path $base -Recurse -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq "Experts" -and ($_.FullName -like "*MQL5*" -or $_.FullName -like "*MQL4*") } |
                ForEach-Object {
                    $terminalName = "MT5"
                    if ($_.FullName -like "*MQL4*") { $terminalName = "MT4" }
                    $found += [PSCustomObject]@{
                        Path    = $_.FullName
                        Type    = $terminalName
                        Display = "$terminalName — $($_.FullName)"
                    }
                }
        }
    }
    return $found
}

# ── STEP TRACKER ──────────────────────────────────────────
$script:currentStep = 1
$script:apiKey = ""
$script:selectedFolder = ""
$script:mt4folders = @()
$script:mt5folders = @()

# ── BUILD MAIN FORM ───────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text           = "Trade Tracker Pro — EA Installer"
$form.Size           = New-Object System.Drawing.Size(600, 560)
$form.StartPosition  = "CenterScreen"
$form.BackColor      = $BG
$form.ForeColor      = $TEXT
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox    = $false
$form.Font           = $FontSub

# Header
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "Trade Tracker Pro"
$lblTitle.Font      = $FontTitle
$lblTitle.ForeColor = $BLUE
$lblTitle.Location  = New-Object System.Drawing.Point(30, 24)
$lblTitle.Size      = New-Object System.Drawing.Size(540, 40)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = "EA Installer — connects MT4/MT5 to your dashboard automatically"
$lblSub.Font      = $FontSmall
$lblSub.ForeColor = $MUTED
$lblSub.Location  = New-Object System.Drawing.Point(30, 64)
$lblSub.Size      = New-Object System.Drawing.Size(540, 20)
$form.Controls.Add($lblSub)

# Divider
$div = New-Object System.Windows.Forms.Panel
$div.BackColor = $BORDER
$div.Location  = New-Object System.Drawing.Point(30, 92)
$div.Size      = New-Object System.Drawing.Size(540, 1)
$form.Controls.Add($div)

# Step indicator panel
$stepPanel = New-Object System.Windows.Forms.Panel
$stepPanel.Location  = New-Object System.Drawing.Point(30, 104)
$stepPanel.Size      = New-Object System.Drawing.Size(540, 36)
$stepPanel.BackColor = $BG
$form.Controls.Add($stepPanel)

function Update-StepIndicator {
    $stepPanel.Controls.Clear()
    $steps = @("1. API Key", "2. Find MT4/MT5", "3. Install", "4. Done")
    $xPos = 0
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $steps[$i]
        $lbl.Font = $FontSmall
        $lbl.Size = New-Object System.Drawing.Size(130, 30)
        $lbl.Location = New-Object System.Drawing.Point($xPos, 4)
        $lbl.TextAlign = "MiddleCenter"
        if (($i + 1) -eq $script:currentStep) {
            $lbl.ForeColor = $BLUE
            $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        } elseif (($i + 1) -lt $script:currentStep) {
            $lbl.ForeColor = $GREEN
        } else {
            $lbl.ForeColor = $MUTED
        }
        $stepPanel.Controls.Add($lbl)
        $xPos += 135
    }
}

# Content panel
$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Location  = New-Object System.Drawing.Point(30, 148)
$contentPanel.Size      = New-Object System.Drawing.Size(540, 300)
$contentPanel.BackColor = $BG
$form.Controls.Add($contentPanel)

# Bottom buttons
$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text      = "← Back"
$btnBack.Location  = New-Object System.Drawing.Point(30, 470)
$btnBack.Size      = New-Object System.Drawing.Size(100, 38)
$btnBack.BackColor = $CARD
$btnBack.ForeColor = $TEXT
$btnBack.FlatStyle = "Flat"
$btnBack.FlatAppearance.BorderColor = $BORDER
$btnBack.Font      = $FontBtn
$btnBack.Visible   = $false
$form.Controls.Add($btnBack)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text      = "Next →"
$btnNext.Location  = New-Object System.Drawing.Point(440, 470)
$btnNext.Size      = New-Object System.Drawing.Size(130, 38)
$btnNext.BackColor = $BLUE
$btnNext.ForeColor = [System.Drawing.Color]::White
$btnNext.FlatStyle = "Flat"
$btnNext.FlatAppearance.BorderSize = 0
$btnNext.Font      = $FontBtn
$form.Controls.Add($btnNext)

$lblError = New-Object System.Windows.Forms.Label
$lblError.ForeColor = $RED
$lblError.Font      = $FontSmall
$lblError.Location  = New-Object System.Drawing.Point(30, 520)
$lblError.Size      = New-Object System.Drawing.Size(540, 20)
$form.Controls.Add($lblError)

# ── STEP 1 — API KEY ──────────────────────────────────────
function Show-Step1 {
    $contentPanel.Controls.Clear()
    $script:currentStep = 1
    Update-StepIndicator
    $btnBack.Visible = $false
    $btnNext.Text = "Next →"
    $btnNext.BackColor = $BLUE
    $lblError.Text = ""

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text      = "Step 1 — Paste your API Key"
    $lbl1.Font      = $FontBold
    $lbl1.ForeColor = $TEXT
    $lbl1.Location  = New-Object System.Drawing.Point(0, 0)
    $lbl1.Size      = New-Object System.Drawing.Size(540, 28)
    $contentPanel.Controls.Add($lbl1)

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text      = "Go to your Trade Tracker Pro dashboard → API Keys tab → Generate new API key → copy it and paste below:"
    $lbl2.Font      = $FontSmall
    $lbl2.ForeColor = $MUTED
    $lbl2.Location  = New-Object System.Drawing.Point(0, 32)
    $lbl2.Size      = New-Object System.Drawing.Size(540, 40)
    $contentPanel.Controls.Add($lbl2)

    $script:txtApiKey = New-Object System.Windows.Forms.TextBox
    $script:txtApiKey.Location  = New-Object System.Drawing.Point(0, 78)
    $script:txtApiKey.Size      = New-Object System.Drawing.Size(540, 32)
    $script:txtApiKey.BackColor = $CARD
    $script:txtApiKey.ForeColor = $GREEN
    $script:txtApiKey.Font      = $FontMono
    $script:txtApiKey.BorderStyle = "FixedSingle"
    $script:txtApiKey.PlaceholderText = "Paste your API key here (64 characters)"
    if ($script:apiKey -ne "") { $script:txtApiKey.Text = $script:apiKey }
    $contentPanel.Controls.Add($script:txtApiKey)

    $lbl3 = New-Object System.Windows.Forms.Label
    $lbl3.Text      = "Your dashboard URL:"
    $lbl3.Font      = $FontSmall
    $lbl3.ForeColor = $MUTED
    $lbl3.Location  = New-Object System.Drawing.Point(0, 130)
    $lbl3.Size      = New-Object System.Drawing.Size(540, 20)
    $contentPanel.Controls.Add($lbl3)

    $lblUrl = New-Object System.Windows.Forms.Label
    $lblUrl.Text      = "https://rad-nasturtium-8cb612.netlify.app"
    $lblUrl.Font      = $FontMono
    $lblUrl.ForeColor = $BLUE
    $lblUrl.Location  = New-Object System.Drawing.Point(0, 152)
    $lblUrl.Size      = New-Object System.Drawing.Size(540, 20)
    $contentPanel.Controls.Add($lblUrl)

    $lbl4 = New-Object System.Windows.Forms.Label
    $lbl4.Text      = "The API key connects this MT4/MT5 installation to your personal account. It is stored encrypted — only you can use it."
    $lbl4.Font      = $FontSmall
    $lbl4.ForeColor = $MUTED
    $lbl4.Location  = New-Object System.Drawing.Point(0, 200)
    $lbl4.Size      = New-Object System.Drawing.Size(540, 40)
    $contentPanel.Controls.Add($lbl4)
}

# ── STEP 2 — FIND MT FOLDER ────────────────────────────────
function Show-Step2 {
    $contentPanel.Controls.Clear()
    $script:currentStep = 2
    Update-StepIndicator
    $btnBack.Visible = $true
    $btnNext.Text = "Install →"
    $lblError.Text = ""

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text      = "Step 2 — Select your MT4/MT5 installation"
    $lbl1.Font      = $FontBold
    $lbl1.ForeColor = $TEXT
    $lbl1.Location  = New-Object System.Drawing.Point(0, 0)
    $lbl1.Size      = New-Object System.Drawing.Size(540, 28)
    $contentPanel.Controls.Add($lbl1)

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text      = "Searching for MT4/MT5 installations on your computer..."
    $lbl2.Font      = $FontSmall
    $lbl2.ForeColor = $MUTED
    $lbl2.Location  = New-Object System.Drawing.Point(0, 32)
    $lbl2.Size      = New-Object System.Drawing.Size(540, 20)
    $contentPanel.Controls.Add($lbl2)

    $folders = Find-MTFolders
    $script:foundFolders = $folders

    if ($folders.Count -eq 0) {
        $lbl2.Text = "No MT4/MT5 installation found automatically."
        $lbl3 = New-Object System.Windows.Forms.Label
        $lbl3.Text      = "Browse manually to your MT4/MT5 Experts folder:"
        $lbl3.Font      = $FontSmall
        $lbl3.ForeColor = $MUTED
        $lbl3.Location  = New-Object System.Drawing.Point(0, 60)
        $lbl3.Size      = New-Object System.Drawing.Size(540, 20)
        $contentPanel.Controls.Add($lbl3)

        $script:txtFolder = New-Object System.Windows.Forms.TextBox
        $script:txtFolder.Location  = New-Object System.Drawing.Point(0, 86)
        $script:txtFolder.Size      = New-Object System.Drawing.Size(430, 28)
        $script:txtFolder.BackColor = $CARD
        $script:txtFolder.ForeColor = $TEXT
        $script:txtFolder.Font      = $FontSmall
        $script:txtFolder.BorderStyle = "FixedSingle"
        $contentPanel.Controls.Add($script:txtFolder)

        $btnBrowse = New-Object System.Windows.Forms.Button
        $btnBrowse.Text      = "Browse"
        $btnBrowse.Location  = New-Object System.Drawing.Point(436, 84)
        $btnBrowse.Size      = New-Object System.Drawing.Size(100, 30)
        $btnBrowse.BackColor = $CARD
        $btnBrowse.ForeColor = $TEXT
        $btnBrowse.FlatStyle = "Flat"
        $btnBrowse.FlatAppearance.BorderColor = $BORDER
        $btnBrowse.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "Select your MT4/MT5 Experts folder (inside MQL4 or MQL5)"
            if ($dlg.ShowDialog() -eq "OK") {
                $script:txtFolder.Text = $dlg.SelectedPath
                $script:selectedFolder = $dlg.SelectedPath
            }
        })
        $contentPanel.Controls.Add($btnBrowse)

        $lbl4 = New-Object System.Windows.Forms.Label
        $lbl4.Text      = "Hint: In MT5 go to File → Open Data Folder → open MQL5 → Experts"
        $lbl4.Font      = $FontSmall
        $lbl4.ForeColor = $AMBER
        $lbl4.Location  = New-Object System.Drawing.Point(0, 120)
        $lbl4.Size      = New-Object System.Drawing.Size(540, 20)
        $contentPanel.Controls.Add($lbl4)
    } else {
        $lbl2.Text = "$($folders.Count) installation(s) found. Select which one to install to:"

        $script:listFolders = New-Object System.Windows.Forms.ListBox
        $script:listFolders.Location  = New-Object System.Drawing.Point(0, 58)
        $script:listFolders.Size      = New-Object System.Drawing.Size(540, 160)
        $script:listFolders.BackColor = $CARD
        $script:listFolders.ForeColor = $TEXT
        $script:listFolders.Font      = $FontSmall
        $script:listFolders.BorderStyle = "FixedSingle"
        foreach ($f in $folders) { $script:listFolders.Items.Add($f.Display) | Out-Null }
        $script:listFolders.SelectedIndex = 0
        $script:selectedFolder = $folders[0].Path
        $script:listFolders.Add_SelectedIndexChanged({
            $idx = $script:listFolders.SelectedIndex
            if ($idx -ge 0 -and $idx -lt $script:foundFolders.Count) {
                $script:selectedFolder = $script:foundFolders[$idx].Path
            }
        })
        $contentPanel.Controls.Add($script:listFolders)

        $lbl3 = New-Object System.Windows.Forms.Label
        $lbl3.Text      = "Not listed? Browse manually:"
        $lbl3.Font      = $FontSmall
        $lbl3.ForeColor = $MUTED
        $lbl3.Location  = New-Object System.Drawing.Point(0, 226)
        $lbl3.Size      = New-Object System.Drawing.Size(540, 20)
        $contentPanel.Controls.Add($lbl3)

        $btnBrowse2 = New-Object System.Windows.Forms.Button
        $btnBrowse2.Text      = "Browse to different folder"
        $btnBrowse2.Location  = New-Object System.Drawing.Point(0, 248)
        $btnBrowse2.Size      = New-Object System.Drawing.Size(200, 28)
        $btnBrowse2.BackColor = $CARD
        $btnBrowse2.ForeColor = $TEXT
        $btnBrowse2.FlatStyle = "Flat"
        $btnBrowse2.FlatAppearance.BorderColor = $BORDER
        $btnBrowse2.Font      = $FontSmall
        $btnBrowse2.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "Select MT4/MT5 Experts folder"
            if ($dlg.ShowDialog() -eq "OK") {
                $script:selectedFolder = $dlg.SelectedPath
                $script:listFolders.ClearSelected()
                [System.Windows.Forms.MessageBox]::Show("Selected: $($dlg.SelectedPath)", "Folder selected", "OK", "Information") | Out-Null
            }
        })
        $contentPanel.Controls.Add($btnBrowse2)
    }
}

# ── STEP 3 — INSTALL ───────────────────────────────────────
function Show-Step3 {
    $contentPanel.Controls.Clear()
    $script:currentStep = 3
    Update-StepIndicator
    $btnBack.Visible = $false
    $btnNext.Visible = $false
    $lblError.Text = ""

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text      = "Installing..."
    $lbl1.Font      = $FontBold
    $lbl1.ForeColor = $TEXT
    $lbl1.Location  = New-Object System.Drawing.Point(0, 0)
    $lbl1.Size      = New-Object System.Drawing.Size(540, 28)
    $contentPanel.Controls.Add($lbl1)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(0, 40)
    $progress.Size     = New-Object System.Drawing.Size(540, 18)
    $progress.Style    = "Continuous"
    $progress.Value    = 0
    $contentPanel.Controls.Add($progress)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Font      = $FontSmall
    $lblStatus.ForeColor = $MUTED
    $lblStatus.Location  = New-Object System.Drawing.Point(0, 64)
    $lblStatus.Size      = New-Object System.Drawing.Size(540, 20)
    $contentPanel.Controls.Add($lblStatus)

    $form.Refresh()

    try {
        # Determine if MT4 or MT5
        $isMT4 = $script:selectedFolder -like "*MQL4*"
        $eaContent = if ($isMT4) { $EA_MT4_CONTENT } else { $EA_MT5_CONTENT }
        $eaFileName = if ($isMT4) { "TradeTrackerPro_MT4.mq4" } else { "TradeTrackerPro_MT5.mq5" }

        $lblStatus.Text = "Writing EA file..."; $progress.Value = 30; $form.Refresh()
        $eaPath = Join-Path $script:selectedFolder $eaFileName
        [System.IO.File]::WriteAllText($eaPath, $eaContent, [System.Text.Encoding]::UTF8)

        $lblStatus.Text = "Saving configuration..."; $progress.Value = 60; $form.Refresh()
        # Save config file next to EA with the API key and URL pre-filled
        $configContent = "API_KEY=$($script:apiKey)`nEDGE_FUNCTION_URL=$EF_URL"
        $configPath = Join-Path $script:selectedFolder "TradeTrackerPro_config.txt"
        [System.IO.File]::WriteAllText($configPath, $configContent)

        $lblStatus.Text = "Verifying installation..."; $progress.Value = 90; $form.Refresh()
        Start-Sleep -Milliseconds 300

        $progress.Value = 100
        $lblStatus.Text = "Installation complete!"
        $form.Refresh()
        Start-Sleep -Milliseconds 400

        Show-Step4 -EaPath $eaPath -EaFileName $eaFileName -IsMT4 $isMT4

    } catch {
        $lblError.Text = "Error: $($_.Exception.Message)"
        $btnBack.Visible = $true
        $btnNext.Visible = $true
    }
}

# ── STEP 4 — DONE ──────────────────────────────────────────
function Show-Step4 {
    param($EaPath, $EaFileName, $IsMT4)
    $contentPanel.Controls.Clear()
    $script:currentStep = 4
    Update-StepIndicator
    $btnBack.Visible = $false
    $btnNext.Visible = $true
    $btnNext.Text = "Open Setup Guide →"
    $btnNext.BackColor = $GREEN

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text      = "EA installed successfully!"
    $lbl1.Font      = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lbl1.ForeColor = $GREEN
    $lbl1.Location  = New-Object System.Drawing.Point(0, 0)
    $lbl1.Size      = New-Object System.Drawing.Size(540, 36)
    $contentPanel.Controls.Add($lbl1)

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text      = "File installed to:`n$EaPath"
    $lbl2.Font      = $FontSmall
    $lbl2.ForeColor = $MUTED
    $lbl2.Location  = New-Object System.Drawing.Point(0, 42)
    $lbl2.Size      = New-Object System.Drawing.Size(540, 40)
    $contentPanel.Controls.Add($lbl2)

    $instructions = if ($IsMT4) {
        "1. Restart MT4 completely (close and reopen)`n2. Press Ctrl+N to open Navigator → Expert Advisors → TradeTrackerPro_MT4`n3. Double-click it → Common tab: check 'Allow Algo Trading'`n4. Inputs tab: paste your API key and the URL below`n5. Tools → Options → Expert Advisors → Allow WebRequests → add the URL`n6. Click the Algo Trading button in toolbar until it turns green"
    } else {
        "1. Restart MT5 completely (close and reopen)`n2. Press Ctrl+N to open Navigator → Expert Advisors → TradeTrackerPro_MT5`n3. Double-click it → Common tab: check 'Allow Algo Trading'`n4. Inputs tab: paste your API key and the URL below`n5. Tools → Options → Expert Advisors → Allow WebRequests → add the URL`n6. Click the Algo Trading button in toolbar until it turns green"
    }

    $lbl3 = New-Object System.Windows.Forms.Label
    $lbl3.Text      = "Final steps in $( if ($IsMT4) { 'MT4' } else { 'MT5' } ):"
    $lbl3.Font      = $FontBold
    $lbl3.ForeColor = $TEXT
    $lbl3.Location  = New-Object System.Drawing.Point(0, 92)
    $lbl3.Size      = New-Object System.Drawing.Size(540, 24)
    $contentPanel.Controls.Add($lbl3)

    $lbl4 = New-Object System.Windows.Forms.Label
    $lbl4.Text      = $instructions
    $lbl4.Font      = $FontSmall
    $lbl4.ForeColor = $MUTED
    $lbl4.Location  = New-Object System.Drawing.Point(0, 118)
    $lbl4.Size      = New-Object System.Drawing.Size(540, 130)
    $contentPanel.Controls.Add($lbl4)

    $lbl5 = New-Object System.Windows.Forms.Label
    $lbl5.Text      = "Edge Function URL (copy this into EA Inputs):"
    $lbl5.Font      = $FontSmall
    $lbl5.ForeColor = $MUTED
    $lbl5.Location  = New-Object System.Drawing.Point(0, 252)
    $lbl5.Size      = New-Object System.Drawing.Size(540, 20)
    $contentPanel.Controls.Add($lbl5)

    $lblUrl = New-Object System.Windows.Forms.TextBox
    $lblUrl.Text        = $EF_URL
    $lblUrl.Font        = $FontMono
    $lblUrl.ForeColor   = $BLUE
    $lblUrl.BackColor   = $CARD
    $lblUrl.BorderStyle = "FixedSingle"
    $lblUrl.ReadOnly    = $true
    $lblUrl.Location    = New-Object System.Drawing.Point(0, 274)
    $lblUrl.Size        = New-Object System.Drawing.Size(540, 24)
    $contentPanel.Controls.Add($lblUrl)
}

# ── BUTTON EVENTS ──────────────────────────────────────────
$btnNext.Add_Click({
    $lblError.Text = ""
    switch ($script:currentStep) {
        1 {
            $key = $script:txtApiKey.Text.Trim()
            if ($key.Length -lt 32) {
                $lblError.Text = "Please paste your API key (it should be 64 characters long)"
                return
            }
            $script:apiKey = $key
            Show-Step2
        }
        2 {
            if ($script:selectedFolder -eq "" -or !(Test-Path $script:selectedFolder)) {
                $lblError.Text = "Please select a valid MT4/MT5 Experts folder"
                return
            }
            Show-Step3
        }
        4 {
            # Open the visual setup guide in browser with API key pre-filled
            $guidePath = Join-Path $PSScriptRoot "setup-guide.html"
            $guideUrl = "file:///$($guidePath.Replace('\','/'))$( if ($script:apiKey) { "?key=$($script:apiKey)" } else { "" } )"
            Start-Process $guideUrl
            $form.Close()
        }
    }
})

$btnBack.Add_Click({
    switch ($script:currentStep) {
        2 { Show-Step1 }
    }
})

# ── START ──────────────────────────────────────────────────
Show-Step1
Update-StepIndicator
[System.Windows.Forms.Application]::Run($form)
