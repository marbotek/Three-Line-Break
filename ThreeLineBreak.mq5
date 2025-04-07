//+------------------------------------------------------------------+
//|                                    Copyright 2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/Three-Line-Break/"
#property version   "1.00"
#property strict

#property description "The TLB chart always ends on the most recent bar of the base chart."
#property description "The TLB chart updates only when the new bar is formed and the new current bar appears."

#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   2

// Line Break Chart
#property indicator_label1  "Line Break Chart"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrGreen, clrRed

// Moving Average
#property indicator_label2  "Moving Average"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

enum ENUM_MA_METHOD_EXTENDED // Same as ENUM_MA_METHOD but with TEMA.
{
    MODE_SMA_,   // Simple
    MODE_EMA_,   // Exponential
    MODE_SMMA_,  // Smoothed
    MODE_LWMA_,  // Linear weighted
    MODE_TEMA    // TEMA (Triple exponential moving average)
};

input group "Three Line Break"
input int NumberOfBarsToLookBack = 1000;             // Number of bars to look back, 0 = all bars
input int LinesToBreak = 3;                          // Lines to break
input bool EnableRescaleChart = true;                // Rescale chart to fit TLB plot
input group "Moving average"
input bool EnableMA = true;                          // Enable MA
input ENUM_MA_METHOD_EXTENDED MA_Method = MODE_EMA_; // MA type
input int MA_Period = 14;                            // MA period
input group "Notifications"
input bool EnableNotify = false;                     // Enable notifications feature
input bool SendAlert = false;                        // Send alert notification
input bool SendSound = false;                        // Play sound for a notification
input string SoundFile = "alert.wav";                // Sound file
input bool SendApp = false;                          // Send notification to mobile
input bool SendEmail = false;                        // Send notification via email

double CandleBufferO[];
double CandleBufferH[];
double CandleBufferL[];
double CandleBufferC[];
double CColorsBuffer[];
double MABuffer[];
double TEMA_1[], TEMA_2[], TEMA_3[];

double Close_prev = DBL_MAX;
int prev_rates_total = 0;
int TLB_N = 0; // Number of candles in the ThreeLineBreak chart.
bool WasChartScaleFix = false; // To reset on deinitialization.
double Alpha; // For EMA.

int OnInit()
{
    SetIndexBuffer(0, CandleBufferO, INDICATOR_DATA);
    SetIndexBuffer(1, CandleBufferH, INDICATOR_DATA);
    SetIndexBuffer(2, CandleBufferL, INDICATOR_DATA);
    SetIndexBuffer(3, CandleBufferC, INDICATOR_DATA);
    SetIndexBuffer(4, CColorsBuffer, INDICATOR_COLOR_INDEX);
    SetIndexBuffer(5, MABuffer, INDICATOR_DATA);
    SetIndexBuffer(6, TEMA_1, INDICATOR_CALCULATIONS);
    SetIndexBuffer(7, TEMA_2, INDICATOR_CALCULATIONS);
    SetIndexBuffer(8, TEMA_3, INDICATOR_CALCULATIONS);

    ArraySetAsSeries(CandleBufferO, true);
    ArraySetAsSeries(CandleBufferH, true);
    ArraySetAsSeries(CandleBufferL, true);
    ArraySetAsSeries(CandleBufferC, true);
    ArraySetAsSeries(CColorsBuffer, true);
    ArraySetAsSeries(MABuffer, true);
    ArraySetAsSeries(TEMA_1, true);
    ArraySetAsSeries(TEMA_2, true);
    ArraySetAsSeries(TEMA_3, true);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    if (EnableMA)
    {
        PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
        PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    }
    else PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);

    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

    string name = "Three-Line Break";
    if (EnableMA) name += " + MA(" + IntegerToString(MA_Period) + ")";
    IndicatorSetString(INDICATOR_SHORTNAME, name);

    if (LinesToBreak < 1)
    {
        Alert("Lines to break should be greater or equal to 1.");
    }
    
    if ((EnableMA) && (MA_Period < 1))
    {
        Alert("MA period should be greater or equal to 1.");
    }

    Alpha = 2.0 / (1.0 + MA_Period);

    if (EnableRescaleChart)
    {
        WasChartScaleFix = ChartGetInteger(0, CHART_SCALEFIX);
        ChartSetInteger(0, CHART_SCALEFIX, true);
    }

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    // Turn off the chart's fixed scale if it was off before attaching the indicator.
    if ((EnableRescaleChart) && (!WasChartScaleFix)) ChartSetInteger(0, CHART_SCALEFIX, false);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (rates_total < 2) return 0; // Not enough bars to even try putting the first TLB candle.

    if (prev_calculated == 0) // Starting from zero, clear previous garbage from memory.
    {
        Close_prev = DBL_MAX;
        TLB_N = 0;
        for (int i = 0; i < rates_total; i++)
        {
            CandleBufferO[i] = EMPTY_VALUE;
            CandleBufferH[i] = EMPTY_VALUE;
            CandleBufferL[i] = EMPTY_VALUE;
            CandleBufferC[i] = EMPTY_VALUE;
            MABuffer[i] = EMPTY_VALUE;
            TEMA_1[i] = EMPTY_VALUE;
            TEMA_2[i] = EMPTY_VALUE;
            TEMA_3[i] = EMPTY_VALUE;
        }
    }

    // Redraw only on new bar.
    if ((prev_calculated > 0) && (rates_total == prev_rates_total)) return rates_total;
    prev_rates_total = rates_total;

    // Starting position for calculations.
    int pos = prev_calculated - 1; // Start from the newest completed bar.

    if (pos < 0) pos = 0;

    if ((NumberOfBarsToLookBack > 0) && (rates_total - 1 - pos > NumberOfBarsToLookBack)) pos = rates_total - 1 - NumberOfBarsToLookBack; // Don't process more bars than required.

    // On the 2nd+ run:
    if (prev_calculated > 0)
    {
        // Shift the previous TLB chart to the right based on the number of new bars.
        MoveTLBRight(rates_total - prev_calculated);
    }

    for (int i = pos; i < rates_total - 1 && !IsStopped(); i++)
    {
        int shift = rates_total - 1 - i;
        double Close = iClose(_Symbol, _Period, shift); // Previous Close.
        
        // First close to surpass.
        if (((NumberOfBarsToLookBack == 0) && (i == 0)) || // Start from the oldest available bar.
            ((NumberOfBarsToLookBack > 0) && (i == rates_total - 1 - NumberOfBarsToLookBack))) // Start from the oldest bar among those that have to be processed.
        {
            Close_prev = Close;
        }
        else if (TLB_N == 0)  // Still no first candle.
        {
            if (Close > Close_prev)
            {
                DrawBullishCandle(Close);
            }
            else if (Close < Close_prev)
            {
                DrawBearishCandle(Close);
            }
        }
        else 
        {
            // Check for direction change:
            int bars_to_check = (int)MathMin(LinesToBreak, TLB_N); // Could be fewer than 3 (or LinesToBreak) bars in total right now.
            int max_index = ArrayMaximum(CandleBufferH, 0, bars_to_check);
            int min_index = ArrayMinimum(CandleBufferL, 0, bars_to_check);
            if ((CColorsBuffer[0] == 1) && (Close > CandleBufferH[max_index])) // Was red but broke above previous bars.
            {
                MoveTLBLeft(); // Move all TLB candles to the left so that the new one can be inserted at 0th position.
                DrawBullishCandle(Close);
                if ((EnableNotify) && (shift == 1) && (prev_calculated > 0)) // Changed direction on the latest finished bar and not upon initial attachment.
                {
                    NotifyHit("Bullish");
                }
            }
            else if ((CColorsBuffer[0] == 0) && (Close < CandleBufferL[min_index])) // Was green but broke below previous bars.
            {
                MoveTLBLeft();
                DrawBearishCandle(Close);
                if ((EnableNotify) && (shift == 1) && (prev_calculated > 0)) // Changed direction on the latest finished bar and not upon initial attachment.
                {
                    NotifyHit("Bearish");
                }
            }
            // Check if a new candle in the same direction is due:
            else if ((CColorsBuffer[0] == 0) && (Close > Close_prev)) // Up
            {
                MoveTLBLeft();
                DrawBullishCandle(Close);
            }
            else if ((CColorsBuffer[0] == 1) && (Close < Close_prev)) // Down
            {
                MoveTLBLeft();
                DrawBearishCandle(Close);
            }
        }
    }

    if (EnableRescaleChart) RescaleChart();

    return rates_total;
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if ((EnableRescaleChart) && (id == CHARTEVENT_CHART_CHANGE))
    {
        RescaleChart();
        ChartRedraw();
    }
}

void MoveTLBLeft()
{
    for (int i = 0; i < TLB_N; i++)
    {
        CandleBufferO[TLB_N - i] = CandleBufferO[TLB_N - i - 1];
        CandleBufferH[TLB_N - i] = CandleBufferH[TLB_N - i - 1];
        CandleBufferL[TLB_N - i] = CandleBufferL[TLB_N - i - 1];
        CandleBufferC[TLB_N - i] = CandleBufferC[TLB_N - i - 1];
        CColorsBuffer[TLB_N - i] = CColorsBuffer[TLB_N - i - 1];
        MABuffer[TLB_N - i] = MABuffer[TLB_N - i - 1];
        TEMA_1[TLB_N - i] = TEMA_1[TLB_N - i - 1];
        TEMA_2[TLB_N - i] = TEMA_2[TLB_N - i - 1];
        TEMA_3[TLB_N - i] = TEMA_3[TLB_N - i - 1];
    }
}

void MoveTLBRight(int new_base_bars)
{
    for (int i = 0; i < TLB_N; i++)
    {
        CandleBufferO[i] = CandleBufferO[i + new_base_bars];
        CandleBufferH[i] = CandleBufferH[i + new_base_bars];
        CandleBufferL[i] = CandleBufferL[i + new_base_bars];
        CandleBufferC[i] = CandleBufferC[i + new_base_bars];
        CColorsBuffer[i] = CColorsBuffer[i + new_base_bars];
        MABuffer[i] = MABuffer[i + new_base_bars];
        TEMA_1[i] = TEMA_1[i + new_base_bars];
        TEMA_2[i] = TEMA_2[i + new_base_bars];
        TEMA_3[i] = TEMA_3[i + new_base_bars];
    }
    // Clean up old stuff.
    for (int i = TLB_N; i < TLB_N + new_base_bars; i++)
    {
        CandleBufferO[i] = EMPTY_VALUE;
        CandleBufferH[i] = EMPTY_VALUE;
        CandleBufferL[i] = EMPTY_VALUE;
        CandleBufferC[i] = EMPTY_VALUE;
        CColorsBuffer[i] = EMPTY_VALUE;
        MABuffer[i] = EMPTY_VALUE;
        TEMA_1[i] = EMPTY_VALUE;
        TEMA_2[i] = EMPTY_VALUE;
        TEMA_3[i] = EMPTY_VALUE;
    }
}

void DrawBullishCandle(const double Close)
{
    TLB_N++;
    CandleBufferO[0] = Close_prev;
    CandleBufferH[0] = Close;
    CandleBufferL[0] = Close_prev;
    CandleBufferC[0] = Close;
    CColorsBuffer[0] = 0; // Green
    if (EnableMA) CalculateMA();
    Close_prev = Close;
}

void DrawBearishCandle(const double Close)
{
    TLB_N++;
    CandleBufferO[0] = Close_prev;
    CandleBufferH[0] = Close_prev;
    CandleBufferL[0] = Close;
    CandleBufferC[0] = Close;
    CColorsBuffer[0] = 1; // Red
    if (EnableMA) CalculateMA();
    Close_prev = Close;
}

void CalculateMA()
{
    if (TLB_N < MA_Period) MABuffer[0] = EMPTY_VALUE; // Not enough bars for any calculations.
    else if (MA_Method == MODE_SMA_) // Simple
    {
        MABuffer[0] = 0;
        for (int i = 0; i < MA_Period; i++)
        {
            MABuffer[0] += CandleBufferC[i];
        }
        MABuffer[0] /= MA_Period;
    }
    else if (MA_Method == MODE_EMA_) // Exponential
    {
        if (TLB_N == MA_Period) // First EMA is just an SMA.
        {
            MABuffer[0] = 0;
            for (int i = 0; i < MA_Period; i++)
            {
                MABuffer[0] += CandleBufferC[i];
            }
            MABuffer[0] /= MA_Period;
        }
        else MABuffer[0] = Alpha * CandleBufferC[0] + (1 - Alpha) * MABuffer[1];
    }
    else if (MA_Method == MODE_SMMA_) // Smoothed
    {
        if (TLB_N == MA_Period) // First EMA is just an SMA.
        {
            MABuffer[0] = 0;
            for (int i = 0; i < MA_Period; i++)
            {
                MABuffer[0] += CandleBufferC[i];
            }
            MABuffer[0] /= MA_Period;
        }
        else MABuffer[0] = (CandleBufferC[0] + (MA_Period - 1) * MABuffer[1]) / MA_Period;
    }
    else if (MA_Method == MODE_LWMA_) // Linear-weighted
    {
        
        MABuffer[0] = 0;
        int sum_i = 0;
        for (int i = 0; i < MA_Period; i++)
        {
            MABuffer[0] += CandleBufferC[i] * (i + 1);
            sum_i += i + 1;
        }
        MABuffer[0] /= sum_i;
    }
    else if (MA_Method == MODE_TEMA) // Triple-exponential
    {
        if (TLB_N == MA_Period) // First value of the first EMA is just an SMA.
        {
            TEMA_1[0] = 0; // First EMA.
            for (int i = 0; i < MA_Period; i++)
            {
                TEMA_1[0] += CandleBufferC[i];
            }
            TEMA_1[0] /= MA_Period;
        }
        else TEMA_1[0] = Alpha * CandleBufferC[0] + (1 - Alpha) * TEMA_1[1];
        if (TLB_N == MA_Period * 2 - 1) // First value of the second EMA is an SMA of the first EMA.
        {
            TEMA_2[0] = 0; // Second EMA.
            for (int i = 0; i < MA_Period; i++)
            {
                TEMA_2[0] += TEMA_1[i];
                
            }
            TEMA_2[0] /= MA_Period;
        }
        else if (TLB_N > MA_Period * 2 - 1) TEMA_2[0] = Alpha * TEMA_1[0] + (1 - Alpha) * TEMA_2[1];
        if (TLB_N == MA_Period * 3 - 2) // First value of the third EMA is an SMA of the second EMA.
        {
            TEMA_3[0] = 0; // Third EMA.
            for (int i = 0; i < MA_Period; i++)
            {
                TEMA_3[0] += TEMA_2[i];
            }
            TEMA_3[0] /= MA_Period;
            MABuffer[0] = 3 * TEMA_1[0] - 3 * TEMA_2[0] + TEMA_3[0];
        }
        else if (TLB_N > MA_Period * 3 - 2)
        {
            TEMA_3[0] = Alpha * TEMA_2[0] + (1 - Alpha) * TEMA_3[1];
            MABuffer[0] = 3 * TEMA_1[0] - 3 * TEMA_2[0] + TEMA_3[0];        
        }
    }
}

// Rescale the chart so that both the highest and the lowest visible TLB candles are within the chart limits.
void RescaleChart()
{
    int visible_bars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
    int first_bar = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR); // Left-most bar.
    int last_bar = first_bar - visible_bars + 1; // Right-most bar.
    if (last_bar < 0) return; // Sometimes, visible bars gets updated before the first bar, and last bar becomes -1.

    int range = MathMin(visible_bars, TLB_N - last_bar);
    if (range <= 0) return; // No need to rescale. Scrolled back to where there is no TLB plot.

    int min_bar = ArrayMinimum(CandleBufferL, last_bar, range);
    int max_bar = ArrayMaximum(CandleBufferH, last_bar, range);

if ((min_bar == -1) || (max_bar == -1))
{
    Print("last_bar = ", last_bar, " range = ", range);
}

    double TLB_min = CandleBufferL[min_bar];
    double TLB_max = CandleBufferH[max_bar];

    ChartSetDouble(0, CHART_FIXED_MAX, TLB_max + (TLB_max - TLB_min) * 0.02);
    ChartSetDouble(0, CHART_FIXED_MIN, TLB_min - (TLB_max - TLB_min) * 0.02);
}

void NotifyHit(string signal)
{
    if ((!SendAlert) && (!SendSound) && (!SendApp) && (!SendEmail)) return;

    string EmailSubject = "Three Line Break: " + Symbol() + " Notification";
    string EmailBody = AccountInfoString(ACCOUNT_COMPANY) + " - " + AccountInfoString(ACCOUNT_NAME) + " - " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\r\n\r\n" + "Three Line Break Notification for " + Symbol() + " @ " + EnumToString(Period()) + "\r\n\r\n";
    string AlertText = "";
    string AppText = AccountInfoString(ACCOUNT_COMPANY) + " - " + AccountInfoString(ACCOUNT_NAME) + " - " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " - Three Line Break - " + Symbol() + " @ " + EnumToString(Period()) + " - ";
    string Text = "";

    Text += "TLB New Direction - " + signal;

    EmailBody += Text;
    AlertText += Text;
    AppText += Text;
    if (SendAlert) Alert(AlertText);
    if (SendSound) PlaySound(SoundFile);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
}
//+------------------------------------------------------------------+