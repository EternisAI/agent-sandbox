---
name: finnhub
description: Fetch EPS/revenue estimates, analyst recommendations, upgrades/downgrades, price targets, earnings/IPO calendars, fundamental metrics, insider sentiment (MSPR), social sentiment, lobbying data, and USA spending via the Finnhub Python SDK through the backend proxy.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Finnhub API (via proxy)

Use the `finnhub-python` package through the backend proxy. Do not use direct vendor API keys.

## Authentication and Proxy Base Override

```python
import os
import finnhub

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]

client = finnhub.Client(api_key=api_key)
client.API_URL = proxy_base.rstrip("/")
```

The SDK sends `token=` as a query param automatically. Override `client.API_URL` to route through the proxy.

## Supported Endpoints

Only use these 12 functions in this skill:

| Function | SDK method | API path | Signal | Cadence |
| --- | --- | --- | --- | --- |
| EPS Estimates | `company_eps_estimates` | `/stock/eps-estimate` | Forward EPS consensus by quarter/year | Quarterly |
| Revenue Estimates | `company_revenue_estimates` | `/stock/revenue-estimate` | Forward revenue consensus by quarter/year | Quarterly |
| Analyst Recommendations | `recommendation_trends` | `/stock/recommendation` | Aggregate buy/hold/sell consensus history | Per analyst action |
| Upgrades/Downgrades | `upgrade_downgrade` | `/stock/upgrade-downgrade` | Individual analyst rating changes with firm and grade | Event-driven |
| Price Targets | `price_target` | `/stock/price-target` | Street consensus high/low/mean/median targets | Per analyst action |
| Earnings Calendar | `earnings_calendar` | `/calendar/earnings` | Scheduled earnings dates with EPS/revenue estimates | Ongoing |
| IPO Calendar | `ipo_calendar` | `/calendar/ipo` | Upcoming IPOs with price range, exchange, status | Ongoing |
| Basic Financials | `company_basic_financials` | `/stock/metric` | P/E, beta, 52-week range, dividend yield, ratios | Daily |
| Insider Sentiment (MSPR) | `stock_insider_sentiment` | `/stock/insider-sentiment` | Monthly Share Purchase Ratio — aggregate insider signal | Monthly |
| Social Sentiment | `stock_social_sentiment` | `/stock/social-sentiment` | Reddit + Twitter mention counts and scores | Daily |
| Lobbying | `stock_lobbying` | `/stock/lobbying` | Senate lobbying spend and issues by company | Quarterly |
| USA Spending | `stock_usa_spending` | `/stock/usa-spending` | Federal contracts and government awards | Event-driven |

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

## Examples

### Pre-Earnings Preview (EPS + Revenue Estimates)

```python
import os
import finnhub

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
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

### Analyst Consensus + Insider MSPR

```python
import os
import finnhub

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

symbol = "AAPL"

recs = client.recommendation_trends(symbol)
if recs:
    r = recs[0]
    total = r['strongBuy'] + r['buy'] + r['hold'] + r['sell'] + r['strongSell']
    print(f"Analyst consensus ({r['period']}): strongBuy={r['strongBuy']} buy={r['buy']} hold={r['hold']} sell={r['sell']} strongSell={r['strongSell']} total={total}")

insider = client.stock_insider_sentiment(symbol, "2025-01-01", "2026-04-01")
for d in insider.get("data", [])[-6:]:
    print(f"  {d['year']}-{d['month']:02d}: MSPR={d['mspr']:.2f} change={d['change']}")
```

### Social Sentiment (Reddit + Twitter)

```python
import os
import finnhub

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

data = client.stock_social_sentiment("GME")
for d in data.get("data", [])[-7:]:
    print(f"{d['atTime']}: score={d['score']:.2f} mentions={d['mention']} (+{d['positiveMention']}/-{d['negativeMention']})")
```

### Analyst Actions + Price Target

```python
import os
import finnhub
from datetime import date, timedelta

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

symbol = "AAPL"
from_date = str(date.today() - timedelta(days=90))
to_date = str(date.today())

upgrades = client.upgrade_downgrade(symbol=symbol, _from=from_date, to=to_date)
for u in upgrades[:5]:
    pt = f" PT=${u['priceTarget']}" if u.get('priceTarget') else ""
    print(f"{u['company']}: {u['fromGrade']} → {u['toGrade']} ({u['action']}){pt}")

pt = client.price_target(symbol)
print(f"\nPrice target consensus ({pt['numberAnalysts']} analysts): "
      f"mean=${pt['targetMean']:.0f} low=${pt['targetLow']:.0f} high=${pt['targetHigh']:.0f}")
```

### Earnings + IPO Calendar

```python
import os
import finnhub
from datetime import date, timedelta

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
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

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
client.API_URL = proxy_base.rstrip("/")

result = client.company_basic_financials("AAPL", "all")
m = result.get("metric", {})
print(f"P/E (TTM): {m.get('peBasicExclExtraTTM')}")
print(f"Beta: {m.get('beta')}")
print(f"52-week: ${m.get('52WeekLow')} – ${m.get('52WeekHigh')}")
print(f"Dividend yield: {m.get('dividendYieldIndicatedAnnual'):.2f}%")
print(f"ROE (TTM): {m.get('roeTTM'):.2f}%")
```

### Lobbying + USA Spending

```python
import os
import finnhub

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/finnhub-proxy")
client = finnhub.Client(api_key=os.environ["OPENROUTER_API_KEY"])
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
