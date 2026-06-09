---
name: finnhub
description: Fetch EPS/revenue estimates, earnings/IPO calendars, fundamental metrics, insider sentiment (MSPR), social sentiment, lobbying, USA spending, USPTO patents, and H1B visa applications via the Finnhub Python SDK through the backend proxy. Most endpoints require a stock ticker (public companies only); exceptions are ipo_calendar and earnings_calendar.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Finnhub API (via proxy)

Use the `finnhub-python` package through the backend proxy. Do not use direct vendor API keys.

## Authentication and Proxy Base Override

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
api_key = os.environ["PROXY_API_KEY"]

client = finnhub.Client(api_key=api_key)
client.API_URL = proxy_base.rstrip("/")
```

The SDK sends `token=` as a query param automatically. Override `client.API_URL` to route through the proxy.

## GCC / Dubai coverage

Finnhub covers the major Middle East exchanges. Pass the exchange suffix on the ticker (`EMAAR.DB`, `FAB.AD`, `2222.SR`). The exchange suffix is one of:

| Exchange | Country | Suffix | MIC |
|---|---|---|---|
| Dubai Financial Market (DFM) | UAE | `.DB` | XDFM |
| Abu Dhabi Securities Exchange (ADX) | UAE | `.AD` | XADS |
| Saudi Stock Exchange (Tadawul) | Saudi Arabia | `.SR` | XSAU |
| Qatar Exchange | Qatar | `.QA` | DSMD |
| Bahrain Bourse | Bahrain | `.BH` | XBAH |
| Kuwait Stock Exchange | Kuwait | `.KW` | XKUW |

To discover tickers on an exchange, call `client.stock_symbols(exchange="DB")` (or `AD`, `SR`, etc.) — returns all listed names with their `displaySymbol`, `description`, `mic`, `currency`, and `type`. The DFM catalog has ~69 names, ADX ~196, Tadawul ~649.

### What works for GCC tickers

Empirically confirmed against the current proxy contract (tested 2026-06-09 across DEWA.DB, EMAAR.DB, EMIRATESNBD.DB, DU.DB, SALIK.DB, TALABAT.DB, PARKIN.DB, EMPOWER.DB, FAB.AD, 2222.SR):

- ✅ `company_basic_financials` — full metric set, currency in AED/SAR. Use for market cap, P/E, ROE, 52W returns.
- ✅ `company_eps_estimates`, `company_revenue_estimates` — forward consensus with analyst count.
- ✅ `recommendation_trends` — aggregate buy/hold/sell history, often 15-22 analysts on the largest Dubai names.
- ✅ `earnings_calendar` (pass the GCC ticker as `symbol`) — quarterly EPS/revenue estimates with `epsActual`/`revenueActual` after report.
- ✅ Quarterly earnings history (via the same calendar call, looking at past quarters with `epsActual` populated).

### What is blocked or empty for GCC tickers

- ❌ `price_target`, `upgrade_downgrade` — return `{"error":"You don't have access to this resource."}` for GCC tickers. Skip them on Dubai questions.
- ❌ `stock_social_sentiment` — same access error. The sentiment agent's regional press search (Al Arabiya, The National, MEED, WAM via `exa_search`) is the right channel for GCC discourse, not this endpoint.
- ❌ Live prices, historical OHLCV candles, dividend history — not exposed in this skill at all; for those, fall back on Massive (which lacks GCC coverage anyway) or the `dfm-adx` build-out planned in `plans/potential-data-dubai.md`.
- ⚠️ `stock_insider_sentiment` (MSPR), `stock_uspto_patent`, `stock_visa_application`, `stock_lobbying`, `stock_usa_spending` — **US-only by data scope**. Calling them with GCC tickers returns an empty `data: []`, not an error. Do not infer absence of activity from absence of data — these endpoints simply do not cover GCC.

### Currency note

GCC tickers return values in their native currency, not USD:

- DFM and ADX tickers → AED (dirham). USD/AED is pegged at 3.6725, so multiply AED by ~0.2723 if a USD comparison is needed, but quote the native AED first in any artifact field that touches the user.
- Tadawul tickers → SAR (riyal). USD/SAR is pegged at 3.75 since 1986.
- Qatar → QAR (pegged 3.64), Bahrain → BHD (pegged 0.376), Kuwait → KWD (basket float, ~0.307), Oman → OMR (pegged 0.3845).

Always read the `currency` field on `stock/profile2` or the symbol catalog before doing arithmetic.

## Supported Endpoints

Only use these 14 functions in this skill:

| Function | SDK method | API path | Signal | Cadence |
| --- | --- | --- | --- | --- |
| EPS Estimates | `company_eps_estimates` | `/stock/eps-estimate` | Forward EPS consensus by quarter/year | Quarterly |
| Revenue Estimates | `company_revenue_estimates` | `/stock/revenue-estimate` | Forward revenue consensus by quarter/year | Quarterly |
| Upgrades/Downgrades | `upgrade_downgrade` | `/stock/upgrade-downgrade` | Individual analyst rating changes with firm and grade | Event-driven |
| Analyst Recommendations | `recommendation_trends` | `/stock/recommendation` | Aggregate buy/hold/sell consensus history (only when explicitly requested) | Per analyst action |
| Price Targets | `price_target` | `/stock/price-target` | Street consensus high/low/mean/median targets (only when explicitly requested) | Per analyst action |
| Earnings Calendar | `earnings_calendar` | `/calendar/earnings` | Scheduled earnings dates with EPS/revenue estimates | Ongoing |
| IPO Calendar | `ipo_calendar` | `/calendar/ipo` | Upcoming IPOs with price range, exchange, status | Ongoing |
| Basic Financials | `company_basic_financials` | `/stock/metric` | P/E, beta, 52-week range, dividend yield, ratios | Daily |
| Insider Sentiment (MSPR) | `stock_insider_sentiment` | `/stock/insider-sentiment` | Monthly Share Purchase Ratio — aggregate insider signal | Monthly |
| Social Sentiment | `stock_social_sentiment` | `/stock/social-sentiment` | Reddit + Twitter mention counts and scores | Daily |
| Lobbying | `stock_lobbying` | `/stock/lobbying` | Senate lobbying spend and issues by company | Quarterly |
| USA Spending | `stock_usa_spending` | `/stock/usa-spending` | Federal contracts and government awards | Event-driven |
| USPTO Patents | `stock_uspto_patent` | `/stock/uspto-patent` | Patent filings — R&D activity and innovation pipeline | Event-driven |
| H1B Visa Applications | `stock_visa_application` | `/stock/visa-application` | H1B + PERM LCA filings — hiring composition and wage data | Quarterly |

## Method Signatures

```python
client.company_eps_estimates(symbol, freq=None)           # freq: "quarterly" or "annual"
client.company_revenue_estimates(symbol, freq=None)        # freq: "quarterly" or "annual"
client.recommendation_trends(symbol)
client.upgrade_downgrade(symbol, _from=None, to=None)      # dates: "YYYY-MM-DD"
client.price_target(symbol)
client.earnings_calendar(_from, to, symbol, international=False)  # symbol="" for all tickers
client.ipo_calendar(_from, to)
client.company_basic_financials(symbol, metric)            # metric: "all" for everything
client.stock_insider_sentiment(symbol, _from, to)
client.stock_social_sentiment(symbol, _from=None, to=None)
client.stock_lobbying(symbol, _from, to)
client.stock_usa_spending(symbol, _from, to)
client.stock_uspto_patent(symbol, _from, to)       # hard cap: 250 records/call — use ≤3 month windows for prolific filers
client.stock_visa_application(symbol, _from, to)
```

## Response Fields

### EPS Estimates (`company_eps_estimates`)

```json
{
  "data": [
    {
      "epsAvg": 1.23, "epsHigh": 1.50, "epsLow": 1.00,
      "numberAnalysts": 30, "period": "2026-03-31", "year": 2026, "quarter": 1
    }
  ],
  "freq": "quarterly", "symbol": "AAPL"
}
```

### Revenue Estimates (`company_revenue_estimates`)

```json
{
  "data": [
    {
      "revenueAvg": 95000000000, "revenueHigh": 98000000000, "revenueLow": 92000000000,
      "numberAnalysts": 28, "period": "2026-03-31", "year": 2026, "quarter": 1
    }
  ],
  "freq": "quarterly", "symbol": "AAPL"
}
```

### Analyst Recommendations (`recommendation_trends`)

```json
[
  {
    "buy": 24, "hold": 7, "sell": 1, "strongBuy": 13, "strongSell": 0,
    "period": "2026-04-01", "symbol": "AAPL"
  }
]
```

### Upgrades/Downgrades (`upgrade_downgrade`)

```json
[
  {
    "symbol": "AAPL", "company": "Goldman Sachs", "action": "up",
    "fromGrade": "Neutral", "toGrade": "Buy",
    "priceTarget": 230.0, "gbGrade": "Buy", "gradeTime": 1744934400
  }
]
```

`action`: `"up"` (upgrade), `"down"` (downgrade), `"init"` (initiation), `"reit"` (reiterate), `"main"` (maintain). `priceTarget` may be `null`.

### Price Target (`price_target`)

```json
{
  "symbol": "AAPL", "lastUpdated": "2026-04-12 00:00:00",
  "numberAnalysts": 46,
  "targetHigh": 367.5, "targetLow": 217.15,
  "targetMean": 297.99, "targetMedian": 306.0
}
```

### Earnings Calendar (`earnings_calendar`)

```json
{
  "earningsCalendar": [
    {
      "symbol": "AAPL", "date": "2026-07-29", "hour": "amc",
      "quarter": 3, "year": 2026,
      "epsEstimate": 1.43, "epsActual": null,
      "revenueEstimate": 96500000000, "revenueActual": null
    }
  ]
}
```

`hour`: `"bmo"` (before market open), `"amc"` (after market close), `""` (unconfirmed). `epsActual`/`revenueActual` are `null` until reported.

### IPO Calendar (`ipo_calendar`)

```json
{
  "ipoCalendar": [
    {
      "symbol": "PS", "name": "Pershing Square Holdco", "date": "2026-04-29",
      "exchange": "NYSE", "price": "50.00",
      "numberOfShares": 0, "totalSharesValue": 0,
      "status": "expected"
    }
  ]
}
```

`status`: `"expected"`, `"priced"`, `"withdrawn"`.

### Basic Financials (`company_basic_financials`)

```json
{
  "symbol": "AAPL",
  "metric": {
    "peBasicExclExtraTTM": 33.68,
    "beta": 1.08,
    "52WeekHigh": 288.62, "52WeekLow": 189.81,
    "52WeekReturn": 0.12,
    "dividendYieldIndicatedAnnual": 0.38,
    "marketCapitalization": 3200000000000,
    "revenuePerShareTTM": 25.43,
    "roeTTM": 159.94, "roiTTM": 54.2,
    "currentRatioAnnual": 0.87, "debtToEquityAnnual": 1.87
  }
}
```

Pass `metric="all"` to get all 132 available fields.

### Insider Sentiment (`stock_insider_sentiment`)

```json
{
  "data": [
    {
      "symbol": "AAPL", "year": 2026, "month": 3,
      "change": 5000, "mspr": 0.85
    }
  ],
  "symbol": "AAPL"
}
```

`mspr` (Monthly Share Purchase Ratio) ranges from -100 to 100. Positive = net buying, negative = net selling.

### Social Sentiment (`stock_social_sentiment`)

```json
{
  "data": [
    {
      "atTime": "2026-04-01T00:00:00Z",
      "mention": 150, "positiveMention": 90, "negativeMention": 30,
      "positiveScore": 0.72, "negativeScore": 0.15, "score": 0.57
    }
  ],
  "symbol": "GME"
}
```

`score` ranges -1 (very negative) to 1 (very positive). Includes both Reddit and Twitter data.

### Lobbying (`stock_lobbying`)

```json
{
  "data": [
    {
      "symbol": "AAPL", "name": "Apple Inc", "year": 2025,
      "period": "H2", "type": "Lobbying", "expense": 5490000,
      "issues": [{"issue": "Taxation/Internal Revenue Code", "description": "..."}]
    }
  ],
  "symbol": "AAPL"
}
```

### USA Spending (`stock_usa_spending`)

```json
{
  "data": [
    {
      "symbol": "LMT", "recipientName": "Lockheed Martin Corp",
      "totalValue": 250000000, "actionDate": "2025-09-15",
      "awardDescription": "F-35 Production Contract", "naicsCode": "336411"
    }
  ],
  "symbol": "LMT"
}
```

### USPTO Patents (`stock_uspto_patent`)

> **⚠️ 250-record hard cap per call.** Prolific filers (AAPL, NVDA, MSFT, GOOG) exceed this within a single quarter. Use ≤3 month date windows and check `len(data) == 250` to detect truncation — paginate by shrinking the date range if so.

```json
{
  "data": [
    {
      "applicationNumber": "18162938", "patentNumber": "US20240259233A1",
      "description": "SLIM ETHERNET COMMUNICATION OVER INFINIBAND",
      "filingDate": "2023-02-01 00:00:00", "filingStatus": "Application",
      "patentType": "Utility", "companyFilingName": ["NVIDIA CORPORATION"], "url": ""
    }
  ],
  "symbol": "NVDA"
}
```

`filingStatus`: `"Application"`, `"Granted"`. `patentType`: `"Utility"`, `"Design"`, `"Plant"`. `url` may be empty.

### H1B Visa Applications (`stock_visa_application`)

```json
{
  "data": [
    {
      "symbol": "AAPL", "jobTitle": "Engineering Project Manager",
      "caseStatus": "Certified", "visaClass": "H-1B", "wageLevel": "III",
      "wageRangeFrom": 188000, "wageRangeTo": 282500, "wageUnitOfPay": "Year",
      "worksiteCity": "Sunnyvale", "worksiteState": "CA", "year": 2023, "quarter": 3
    }
  ],
  "symbol": "AAPL"
}
```

`caseStatus`: `"Certified"`, `"Denied"`, `"Withdrawn"`. `wageLevel`: `"I"`–`"IV"` (I = entry, IV = fully competent).

## Examples

### Pre-Earnings Preview (EPS + Revenue Estimates)

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

symbol = "AAPL"
eps = client.company_eps_estimates(symbol, freq="quarterly")
rev = client.company_revenue_estimates(symbol, freq="quarterly")

for e in eps.get("data", [])[:4]:
    print(f"Q{e['quarter']} {e['year']}: EPS avg={e['epsAvg']:.2f} (low={e['epsLow']:.2f} high={e['epsHigh']:.2f}) analysts={e['numberAnalysts']}")

for r in rev.get("data", [])[:4]:
    avg_b = r['revenueAvg'] / 1e9
    print(f"Q{r['quarter']} {r['year']}: Rev avg=${avg_b:.1f}B analysts={r['numberAnalysts']}")
```

### Insider MSPR (only when specifically requested)

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

symbol = "AAPL"

insider = client.stock_insider_sentiment(symbol, "2025-01-01", "2026-04-01")
for d in insider.get("data", [])[-6:]:
    print(f"  {d['year']}-{d['month']:02d}: MSPR={d['mspr']:.2f} change={d['change']}")
```

### Social Sentiment (Reddit + Twitter)

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

data = client.stock_social_sentiment("GME")
for d in data.get("data", [])[-7:]:
    print(f"{d['atTime']}: score={d['score']:.2f} mentions={d['mention']} (+{d['positiveMention']}/-{d['negativeMention']})")
```

### Analyst Rating Actions (Upgrades/Downgrades)

```python
import os
import finnhub
from datetime import date, timedelta

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

symbol = "AAPL"
from_date = str(date.today() - timedelta(days=90))
to_date = str(date.today())

upgrades = client.upgrade_downgrade(symbol=symbol, _from=from_date, to=to_date)
for u in upgrades[:5]:
    print(f"{u['company']}: {u['fromGrade']} → {u['toGrade']} ({u['action']})")
```

### Price Target Consensus (only when explicitly requested)

```python
pt = client.price_target(symbol)
print(f"Price target consensus ({pt['numberAnalysts']} analysts): "
      f"mean=${pt['targetMean']:.0f} low=${pt['targetLow']:.0f} high=${pt['targetHigh']:.0f}")
```

### Earnings + IPO Calendar

```python
import os
import finnhub
from datetime import date, timedelta

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

today = str(date.today())
two_weeks = str(date.today() + timedelta(days=14))

# Earnings for a specific ticker
ec = client.earnings_calendar(_from=today, to=two_weeks, symbol="AAPL", international=False)
for e in ec.get("earningsCalendar", []):
    print(f"Earnings: {e['symbol']} on {e['date']} ({e['hour']}) Q{e['quarter']} {e['year']} "
          f"EPS est={e['epsEstimate']}")

# Upcoming IPOs
ipos = client.ipo_calendar(_from=today, to=two_weeks)
for ipo in ipos.get("ipoCalendar", [])[:5]:
    print(f"IPO: {ipo['name']} ({ipo['symbol']}) on {ipo['date']} @ {ipo['price']} — {ipo['exchange']}")
```

### Basic Financials (Ratios + Metrics)

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

result = client.company_basic_financials("AAPL", "all")
m = result.get("metric", {})
print(f"P/E (TTM): {m.get('peBasicExclExtraTTM')}")
print(f"Beta: {m.get('beta')}")
print(f"52-week: ${m.get('52WeekLow')} – ${m.get('52WeekHigh')}")
print(f"Dividend yield: {m.get('dividendYieldIndicatedAnnual'):.2f}%")
print(f"ROE (TTM): {m.get('roeTTM'):.2f}%")
```

### Dubai listed company — fundamentals + consensus + earnings history

Works the same way as a US name, but the ticker carries the exchange suffix and values come back in AED. The example below covers a Dubai-strategy lookup that an Axion agent would do when the question touches a DFM-listed name (DEWA, Emaar, Salik, Empower, Talabat, Parkin, Emirates NBD, du). Do NOT call `price_target`, `upgrade_downgrade`, or `stock_social_sentiment` for these tickers — they return an access error.

```python
import os
import finnhub
from datetime import date

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

# DEWA on DFM. Substitute EMAAR.DB, EMIRATESNBD.DB, SALIK.DB, etc.
symbol = "DEWA.DB"

# 1. Fundamentals — note the currency is AED, not USD.
fin = client.company_basic_financials(symbol, "all")
m = fin.get("metric", {})
mcap_aed_b = m.get("marketCapitalization", 0) / 1000  # value is in millions of AED
print(f"{symbol} market cap: AED {mcap_aed_b:.1f}B  P/E: {m.get('peNormalizedAnnual') or m.get('peBasicExclExtraTTM')}")
print(f"  52W return: {m.get('52WeekPriceReturnDaily'):.1f}%   ROE TTM: {m.get('roeTTM')}")
print(f"  13W return: {m.get('13WeekPriceReturnDaily'):.1f}%   26W: {m.get('26WeekPriceReturnDaily'):.1f}%")

# 2. Forward consensus.
eps = client.company_eps_estimates(symbol, freq="quarterly")
for e in eps.get("data", [])[:4]:
    print(f"  Q{e['quarter']} {e['year']}: EPS avg={e['epsAvg']:.3f} AED (analysts={e['numberAnalysts']})")

rev = client.company_revenue_estimates(symbol, freq="quarterly")
for r in rev.get("data", [])[:4]:
    avg_b = r["revenueAvg"] / 1e9
    print(f"  Q{r['quarter']} {r['year']}: Rev avg=AED {avg_b:.2f}B (analysts={r['numberAnalysts']})")

# 3. Analyst consensus history (works for GCC; price_target / upgrade_downgrade do NOT).
recs = client.recommendation_trends(symbol)
if recs:
    r = recs[0]
    print(f"  {r['period']} consensus: strongBuy={r['strongBuy']} buy={r['buy']} hold={r['hold']} sell={r['sell']} strongSell={r['strongSell']}")

# 4. Quarterly earnings history with surprise — fetched via earnings_calendar over the past year.
today = str(date.today())
year_ago = str(date.today().replace(year=date.today().year - 1))
ec = client.earnings_calendar(_from=year_ago, to=today, symbol=symbol, international=True)
for q in ec.get("earningsCalendar", []):
    actual = q.get("epsActual")
    if actual is None:
        continue
    est = q.get("epsEstimate") or 0
    surprise = ((actual - est) / est * 100) if est else 0
    print(f"  {q['date']} Q{q['quarter']} {q['year']}: EPS actual={actual} est={est} surprise={surprise:+.1f}%")
```

Notes specific to this call shape on GCC tickers:

- `marketCapitalization` in `company_basic_financials` is reported in millions of the native currency (AED for `.DB`/`.AD`, SAR for `.SR`, etc.) — divide by 1000 to get billions of native currency, never by 1e9.
- Pass `international=True` to `earnings_calendar` when querying GCC names. Without it the call may return an empty list for non-US tickers depending on the SDK version.
- Coverage depth on the largest Dubai names is real: at the time of writing, DEWA had 20 analysts, Emaar 21, Emirates NBD 22, du 13, Salik 19, Empower 19, Talabat 18, Parkin 12. Consensus dispersion is meaningful, not a single-analyst stub.

### USPTO Patents + H1B Visa Applications

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

symbol = "NVDA"

# USPTO patents — use tight date window to avoid 250-record cap
patents = client.stock_uspto_patent(symbol, _from="2023-01-01", to="2023-03-31")
data = patents.get("data", [])
truncated = len(data) == 250
print(f"{len(data)} patents{'  (truncated — narrow date range)' if truncated else ''}")
for p in data[:5]:
    print(f"  [{p['filingDate'][:10]}] {p['description'][:70]} ({p['filingStatus']})")

# H1B filings
visas = client.stock_visa_application(symbol, _from="2023-01-01", to="2023-12-31")
filings = visas.get("data", [])
print(f"\n{len(filings)} H1B filings")
for v in filings[:5]:
    print(f"  {v['jobTitle']} — {v['caseStatus']} ${v['wageRangeFrom']:,.0f}–${v['wageRangeTo']:,.0f} L{v['wageLevel']} ({v['worksiteCity']}, {v['worksiteState']})")
```

### Lobbying + USA Spending

```python
import os
import finnhub

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["PROXY_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

lobby = client.stock_lobbying("AAPL", "2023-01-01", "2026-01-01")
for d in lobby.get("data", [])[:5]:
    issues = ", ".join(i["issue"] for i in d.get("issues", [])[:3])
    print(f"{d['year']} {d['period']}: ${d.get('expense', 0):,.0f} — {issues}")

spend = client.stock_usa_spending("LMT", "2024-01-01", "2026-01-01")
for d in spend.get("data", [])[:5]:
    print(f"{d.get('actionDate')}: ${d.get('totalValue', 0):,.0f} — {d.get('awardDescription', '')[:80]}")
```

## Usage Rules

- All requests are `GET` only.
- Always override `client.API_URL` to the proxy base.
- Date params use `"YYYY-MM-DD"` format.
- Process responses in Python and print concise summaries.
- Rate limit: 30 calls/sec max. Add `time.sleep(0.1)` between rapid calls.
- The `freq` param for estimates accepts `"quarterly"` or `"annual"`.
- `earnings_calendar` with `symbol=""` returns all tickers (1500+) — always pass a specific `symbol` unless you need the full market calendar.
- `stock_uspto_patent` hard cap is 250 records/call — use ≤3 month windows for large-cap tech companies and check `len(data) == 250` to detect truncation.
- `price_target` and `recommendation_trends` return sell-side consensus that herds toward price and adds noise. Only call them when the task explicitly asks for analyst coverage or price targets. Use `upgrade_downgrade` for individual rating actions — those are useful as event-driven sentiment signals.
- **GCC ticker rules:** for tickers ending `.DB`, `.AD`, `.SR`, `.QA`, `.BH`, or `.KW`, **do NOT call `price_target`, `upgrade_downgrade`, or `stock_social_sentiment`** — they return access errors at the current tier. Do not retry; treat them as unavailable for these tickers and proceed without that signal. `stock_insider_sentiment`, `stock_uspto_patent`, `stock_visa_application`, `stock_lobbying`, and `stock_usa_spending` return empty data for GCC tickers because the underlying datasets are US-only — do NOT report this as "no insider activity" or "no lobbying", report it as "data not available for this jurisdiction." All other endpoints (`company_basic_financials`, `company_eps_estimates`, `company_revenue_estimates`, `recommendation_trends`, `earnings_calendar`, `ipo_calendar`) work normally — read the `currency` field and quote values in the native currency before any USD conversion.
