---
name: finnhub
description: Fetch EPS/revenue estimates, analyst recommendations, insider sentiment (MSPR), social sentiment, lobbying data, and USA spending via the Finnhub Python SDK through the backend proxy. Use when users ask for earnings estimates, analyst consensus, insider MSPR, Reddit/Twitter sentiment, lobbying spend, or government contracts.
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

Only use these 6 functions in this skill:

| Function | SDK method | API path | Signal | Cadence |
| --- | --- | --- | --- | --- |
| EPS Estimates | `company_eps_estimates` | `/stock/eps-estimate` | Forward EPS consensus by quarter/year | Quarterly |
| Revenue Estimates | `company_revenue_estimates` | `/stock/revenue-estimate` | Forward revenue consensus by quarter/year | Quarterly |
| Analyst Recommendations | `recommendation_trends` | `/stock/recommendation` | Aggregate buy/hold/sell consensus history | Per analyst action |
| Insider Sentiment (MSPR) | `stock_insider_sentiment` | `/stock/insider-sentiment` | Monthly Share Purchase Ratio — aggregate insider signal | Monthly |
| Social Sentiment | `stock_social_sentiment` | `/stock/social-sentiment` | Reddit + Twitter mention counts and scores | Daily |
| Lobbying | `stock_lobbying` | `/stock/lobbying` | Senate lobbying spend and issues by company | Quarterly |
| USA Spending | `stock_usa_spending` | `/stock/usa-spending` | Federal contracts and government awards | Event-driven |

## Method Signatures

```python
client.company_eps_estimates(symbol, freq=None)          # freq: "quarterly" or "annual"
client.company_revenue_estimates(symbol, freq=None)       # freq: "quarterly" or "annual"
client.recommendation_trends(symbol)
client.stock_insider_sentiment(symbol, _from, to)         # dates: "YYYY-MM-DD"
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
