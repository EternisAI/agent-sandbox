---
name: unusual-whales
description: Query unusual options flow, dark pool prints, market tide, stock greek exposure, congressional/insider trading, financial statements, and technical indicators via the Unusual Whales API proxy. Use when users ask for options flow alerts, whale trades, dark pool data, GEX/gamma exposure, or market sentiment.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Unusual Whales API (via proxy)

Use `httpx` to query the Unusual Whales API through the backend proxy. Do not use direct vendor endpoints.

## Authentication and Proxy Base

```python
import os
import httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]

headers = {
    "Authorization": f"Bearer {api_key}",
    "UW-CLIENT-API-ID": "100001",
}

def uw_get(path: str, params: dict | None = None) -> dict:
    url = f"{proxy_base.rstrip('/')}/{path.lstrip('/')}"
    resp = httpx.get(url, headers=headers, params=params, timeout=20)
    resp.raise_for_status()
    return resp.json()
```

All endpoints are `GET` only. Every path below is relative to the proxy base (e.g. `api/option-trades/flow-alerts`).

## Anti-Hallucination Rules

Only use endpoints listed in the reference below. These are commonly hallucinated and **do not exist**:

- `/api/options/flow` (use `/api/option-trades/flow-alerts`)
- `/api/flow` or `/api/flow/live`
- `/api/stock/{ticker}/flow` (use `/api/stock/{ticker}/flow-recent`)
- `/api/stock/{ticker}/options` (use `/api/stock/{ticker}/option-contracts`)
- `/api/unusual-activity`
- Any URL containing `/api/v1/` or `/api/v2/`
- Query params `apiKey=` or `api_key=` (use `Authorization` header only)

## Concept Mapping

| User intent | Endpoint |
| --- | --- |
| Live flow / whale trades / option flow | `/api/option-trades/flow-alerts` |
| Options screener / flow filter | `/api/screener/option-contracts` |
| Market sentiment / market tide | `/api/market/market-tide` |
| Dark pool | `/api/darkpool/recent` or `/api/darkpool/{ticker}` |
| Contract greeks | `/api/stock/{ticker}/greeks` |
| Spot gamma / GEX / gamma exposure | `/api/stock/{ticker}/spot-exposures/strike` |
| Financials / fundamentals | `/api/stock/{ticker}/financials` |
| Income statement | `/api/stock/{ticker}/income-statements` |
| Balance sheet | `/api/stock/{ticker}/balance-sheets` |
| Cash flow | `/api/stock/{ticker}/cash-flows` |
| Earnings history | `/api/stock/{ticker}/earnings` |
| Technical indicator (RSI, MACD, etc.) | `/api/stock/{ticker}/technical-indicator/{function}` |

## Valid Endpoint Reference

### Flow & Options Screening

- **Flow Alerts:** `api/option-trades/flow-alerts`
  - Params: `limit`, `is_call`, `is_put`, `is_otm`, `min_premium`, `ticker_symbol`, `size_greater_oi`
- **Options Screener:** `api/screener/option-contracts`
  - Params: `limit`, `min_premium`, `type`, `is_otm`, `issue_types[]`, `min_volume_oi_ratio`
- **Full Tape:** `api/option-trades/full-tape`
- **Single Flow Alert:** `api/option-trades/flow-alert/{id}`
- **Stock Screener:** `api/screener/stocks`
- **Analyst Ratings:** `api/screener/analyst-ratings`
- **Hottest Chains:** `api/screener/hottest-chains`

### Stock / Ticker Data

- **Stock Info:** `api/stock/{ticker}/info`
- **Stock State:** `api/stock/{ticker}/state`
- **OHLC:** `api/stock/{ticker}/ohlc`
- **Recent Flows:** `api/stock/{ticker}/flow-recent`
- **Flow Alerts (stock):** `api/stock/{ticker}/flow-alerts`
- **Flow per Expiry:** `api/stock/{ticker}/flow-per-expiry`
- **Flow per Strike:** `api/stock/{ticker}/flow-per-strike`
- **Flow per Strike Intraday:** `api/stock/{ticker}/flow-per-strike-intraday`
- **Net Premium Ticks:** `api/stock/{ticker}/net-prem-ticks`
- **Option Contracts:** `api/stock/{ticker}/option-contracts`
- **Option Chains:** `api/stock/{ticker}/option-chains`
- **Options Volume:** `api/stock/{ticker}/options-volume`
- **Option Price Levels:** `api/stock/{ticker}/option-price-levels`
- **Volume/OI per Expiry:** `api/stock/{ticker}/volume-oi-per-expiry`

### Greeks, IV & GEX

- **Greeks:** `api/stock/{ticker}/greeks`
- **Greek Exposure (overall):** `api/stock/{ticker}/greek-exposure`
- **Greek Exposure by Expiry:** `api/stock/{ticker}/greek-exposure/expiry`
- **Greek Exposure by Strike:** `api/stock/{ticker}/greek-exposure/strike`
- **Greek Exposure by Strike+Expiry:** `api/stock/{ticker}/greek-exposure/strike-expiry`
- **Greek Flow:** `api/stock/{ticker}/greek-flow`
- **Greek Flow by Expiry:** `api/stock/{ticker}/greek-flow-expiry`
- **Spot GEX (1min):** `api/stock/{ticker}/spot-gex-1min`
- **Spot GEX by Strike:** `api/stock/{ticker}/spot-exposures/strike`
- **Spot GEX by Strike+Expiry:** `api/stock/{ticker}/spot-gex-strike-expiry`
- **Interpolated IV:** `api/stock/{ticker}/interpolated-iv`
- **IV Rank:** `api/stock/{ticker}/iv-rank`
- **IV Term Structure:** `api/stock/{ticker}/iv-term-structure`
- **Risk Reversal Skew:** `api/stock/{ticker}/risk-reversal-skew`
- **Max Pain:** `api/stock/{ticker}/max-pain`
- **NOPE:** `api/stock/{ticker}/nope`
- **OI Change:** `api/stock/{ticker}/oi-change`
- **OI per Expiry:** `api/stock/{ticker}/oi-per-expiry`
- **OI per Strike:** `api/stock/{ticker}/oi-per-strike`
- **Realized Volatility:** `api/stock/{ticker}/realized-volatility`
- **Volatility Stats:** `api/stock/{ticker}/volatility-stats`

### Financial Statements & Fundamentals

- **Full Financials:** `api/stock/{ticker}/financials`
- **Income Statements:** `api/stock/{ticker}/income-statements` — Params: `report_type`
- **Balance Sheets:** `api/stock/{ticker}/balance-sheets` — Params: `report_type`
- **Cash Flows:** `api/stock/{ticker}/cash-flows` — Params: `report_type`
- **Earnings History:** `api/stock/{ticker}/earnings` — Params: `report_type`
- **Fundamentals:** `api/stock/{ticker}/fundamentals`
- **Ownership:** `api/stock/{ticker}/ownership`
- **Insider Buy/Sell:** `api/stock/{ticker}/insider-buy-sell`
- **ATM Chains:** `api/stock/{ticker}/atm-chains`
- **Companies in Sector:** `api/stock/{ticker}/companies-in-sector`
- **Technical Indicators:** `api/stock/{ticker}/technical-indicator/{function}` — Params: `interval`, `time_period`, `series_type`
- **Price Levels:** `api/stock/{ticker}/price-levels`

### Dark Pool

- **Recent (market-wide):** `api/darkpool/recent`
- **Ticker-specific:** `api/darkpool/{ticker}`

### Market-Wide

- **Market Tide:** `api/market/market-tide`
- **Sector Tide:** `api/market/sector-tide`
- **ETF Tide:** `api/market/etf-tide`
- **Correlations:** `api/market/correlations`
- **Economic Calendar:** `api/market/economic-calendar`
- **FDA Calendar:** `api/market/fda-calendar`
- **Insider Buy/Sells:** `api/market/insider-buy-sells`
- **OI Change:** `api/market/oi-change`
- **Sector ETFs:** `api/market/sector-etfs`
- **Top Net Impact:** `api/market/top-net-impact`
- **Total Options Volume:** `api/market/total-options-volume`
- **Net Flow by Expiry:** `api/market/net-flow-expiry`

### Congress & Politicians

- **Congress Trades:** `api/congress/trades`
- **Congress Trader:** `api/congress/trader`
- **Late Reports:** `api/congress/late-reports`
- **Politician List:** `api/politicians/list`
- **Politician Trades:** `api/politicians/trades`
- **Politician Portfolios:** `api/politicians/portfolios`
- **Politician Disclosures:** `api/politicians/disclosures`
- **Holds Ticker:** `api/politicians/holds-ticker`

### Insiders

- **Insider Transactions:** `api/insiders/transactions`
- **Insider List:** `api/insiders/list`
- **Sector Flow:** `api/insiders/sector-flow`
- **Ticker Flow:** `api/insiders/ticker-flow`

### Institutions

- **Activity:** `api/institutions/activity-v2`
- **Holdings:** `api/institutions/holdings`
- **Sectors:** `api/institutions/sectors`
- **Ownership:** `api/institutions/ownership`
- **List:** `api/institutions/list`
- **Filings:** `api/institutions/filings`

### ETFs

- **Exposure:** `api/etfs/exposure`
- **Holdings:** `api/etfs/holdings`
- **Inflow/Outflow:** `api/etfs/inflow-outflow`
- **Info:** `api/etfs/info`
- **Weights:** `api/etfs/weights`

### Short Selling

- **Screener:** `api/short/screener`
- **Short Data:** `api/short/data`
- **Failures to Deliver:** `api/short/failures-to-deliver`
- **Interest/Float:** `api/short/interest-float-v2`
- **Volume Ratio:** `api/short/volume-ratio`
- **Volume by Exchange:** `api/short/volume-by-exchange`

### Earnings

- **After Hours:** `api/earnings/afterhours`
- **Premarket:** `api/earnings/premarket`
- **Ticker Earnings:** `api/earnings/ticker`

### Seasonality

- **Market:** `api/seasonality/market`
- **Month Performers:** `api/seasonality/month-performers`
- **Monthly Returns:** `api/seasonality/monthly-returns`
- **Year/Month:** `api/seasonality/year-month`

### Crypto

- **Whale Transactions:** `api/crypto/whale-transactions`
- **Recent Whales:** `api/crypto/whales-recent`
- **OHLC:** `api/crypto/ohlc`
- **State:** `api/crypto/state`

### Other

- **News Headlines:** `api/news/headlines`
- **Alerts:** `api/alerts`
- **Alert Configurations:** `api/alert-configurations`
- **Lit Flow Recent:** `api/lit-flow/recent`
- **Lit Flow Ticker:** `api/lit-flow/ticker`
- **Group Greek Flow:** `api/group-flow/greek-flow`
- **Group Greek Flow Expiry:** `api/group-flow/greek-flow-expiry`
- **Predictions Market:** `api/predictions/market`
- **Predictions Unusual:** `api/predictions/unusual`
- **Predictions Whales:** `api/predictions/whales`
- **Stock Directory:** `api/stock-directory/ticker-exchanges`
- **Option Contract History:** `api/option-contracts/history`
- **Option Contract Flow:** `api/option-contracts/flow`

## Examples

### Flow Alerts (Unusual Activity)

```python
import os, httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/option-trades/flow-alerts", headers=headers, params={
    "ticker_symbol": "TSLA",
    "min_premium": 50_000,
    "size_greater_oi": True,
    "is_otm": True,
    "limit": 10,
}, timeout=20)
data = resp.json().get("data", [])
for d in data[:5]:
    print(f"{d.get('ticker')} {d.get('type')} premium={d.get('total_premium')} size={d.get('total_size')}")
```

### Options Screener (Bullish Flow)

```python
import os, httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/screener/option-contracts", headers=headers, params={
    "limit": 50,
    "is_otm": True,
    "type": "Calls",
    "min_premium": 250_000,
    "min_volume": 500,
    "vol_greater_oi": True,
}, timeout=20)
data = resp.json().get("data", [])
for d in data[:10]:
    print(f"{d.get('ticker_symbol')} {d.get('option_symbol')} premium={d.get('total_premium')}")
```

### Market Tide (Sentiment)

```python
import os, httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/market/market-tide", headers=headers, timeout=20)
data = resp.json().get("data", [])
if data:
    latest = data[-1]
    print(f"Net Call Premium: {latest.get('net_call_premium')}  Net Put Premium: {latest.get('net_put_premium')}")
```

### Dark Pool Prints

```python
import os, httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/darkpool/NVDA", headers=headers, timeout=20)
data = resp.json().get("data", [])
for d in data[:5]:
    print(f"{d.get('ticker')} price={d.get('price')} size={d.get('size')} at={d.get('executed_at')}")
```

### Gamma Exposure (GEX) by Strike

```python
import os, httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/stock/SPY/spot-exposures/strike", headers=headers, timeout=20)
data = resp.json().get("data", [])
for d in data[:10]:
    print(f"Strike={d.get('strike')} call_gex={d.get('call_gamma_oi')} put_gex={d.get('put_gamma_oi')}")
```

## Usage Rules

- All requests are `GET` only.
- Always include both `Authorization: Bearer` and `UW-CLIENT-API-ID: 100001` headers.
- Process responses in Python and print concise summaries — avoid dumping raw JSON.
- Use `limit` params to keep responses bounded.
- Response data is typically nested under a `"data"` key.
