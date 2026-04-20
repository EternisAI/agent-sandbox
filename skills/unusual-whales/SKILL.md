---
name: unusual-whales
description: Query unusual options flow, dark pool prints, market tide, stock greek exposure, congressional/insider trading, earnings, and sector ETF data via the Unusual Whales API proxy. Use when users ask for options flow alerts, whale trades, dark pool data, GEX/gamma exposure, or market sentiment.
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

## Concept Mapping

| User intent | Endpoint |
| --- | --- |
| Live flow / whale trades / option flow | `/api/option-trades/flow-alerts` |
| Options screener / flow filter | `/api/screener/option-contracts` |
| Market sentiment / market tide | `/api/market/market-tide` |
| Dark pool | `/api/darkpool/recent` or `/api/darkpool/{ticker}` |
| Contract greeks (SPY/QQQ/IWM only) | `/api/stock/{ticker}/greeks` |
| Spot gamma / GEX / gamma exposure | `/api/stock/{ticker}/spot-exposures/expiry-strike` |
| Earnings history | `/api/stock/{ticker}/earnings` |

## Valid Endpoint Reference

### Flow & Options Screening

- **Flow Alerts:** `api/option-trades/flow-alerts`
  - Params: `limit`, `is_call`, `is_put`, `is_otm`, `min_premium`, `ticker_symbol`, `size_greater_oi`
  - Boolean params filter-when-set — leave unset for "no filter". `side` is uppercase.
- **Options Screener:** `api/screener/option-contracts`
  - Params: `limit` (default is 1 — always set explicitly), `min_premium`, `type`, `is_otm`, `issue_types[]`, `min_volume_oi_ratio`, `min_ask_perc` / `max_ask_perc` (both 0–1 decimals)
- **Unusual Tickers:** `api/option-trades/unusual-tickers` — tickers with unusual options activity right now
- **Single Flow Alert:** `api/option-trades/flow-alerts/{id}`
- **Stock Screener:** `api/screener/stocks`

### Stock / Ticker Data

- **Recent Flows:** `api/stock/{ticker}/flow-recent` — response is a top-level JSON list (no `data` wrapper)
- **Flow Alerts (stock):** `api/stock/{ticker}/flow-alerts` — DEPRECATED; migrate to `/api/option-trades/flow-alerts?ticker_symbol={ticker}`
- **Flow per Expiry:** `api/stock/{ticker}/flow-per-expiry` — response is a top-level JSON list
- **Flow per Strike:** `api/stock/{ticker}/flow-per-strike` — response is a top-level JSON list
- **Flow per Strike Intraday:** `api/stock/{ticker}/flow-per-strike-intraday`
  - `filter` is case-sensitive: `"NetPremium"`, `"Volume"`, `"Trades"`
- **Net Premium Ticks:** `api/stock/{ticker}/net-prem-ticks`
- **Option Contracts:** `api/stock/{ticker}/option-contracts`
- **Options Volume:** `api/stock/{ticker}/options-volume` — daily call vol, put vol, premium totals (UW-specific, not in Polygon)
- **Volume/OI per Expiry:** `api/stock/{ticker}/option/volume-oi-expiry`
- **Expiry Breakdown:** `api/stock/{ticker}/expiry-breakdown` — field name is `expires` (not `expiry`)
- **Stock Volume/Price Levels:** `api/stock/{ticker}/stock-volume-price-levels`
- **Stock Price Levels (options):** `api/stock/{ticker}/option/stock-price-levels`
- **Companies in Sector:** `api/stock/{sector}/tickers` — returns list of ticker symbols for a sector (e.g. `"Technology"`, `"Financial Services"`, `"Health Care"`)

### Greeks, IV & GEX

- **Greeks:** `api/stock/{ticker}/greeks` — SPY/QQQ/IWM only; individual stocks silently return `[]`
- **Greek Exposure:** `api/stock/{ticker}/greek-exposure`
- **Greek Exposure by Expiry:** `api/stock/{ticker}/greek-exposure/expiry`
- **Greek Exposure by Strike:** `api/stock/{ticker}/greek-exposure/strike`
- **Greek Exposure by Strike+Expiry:** `api/stock/{ticker}/greek-exposure/strike-expiry` — SPY/QQQ/IWM only
- **Greek Flow:** `api/stock/{ticker}/greek-flow`
- **Greek Flow by Expiry:** `api/stock/{ticker}/greek-flow/{expiry}`
- **Spot Exposures:** `api/stock/{ticker}/spot-exposures`
- **Spot Exposures by Strike:** `api/stock/{ticker}/spot-exposures/strike` — DEPRECATED; migrate to `/spot-exposures/expiry-strike`
- **Spot Exposures by Expiry+Strike:** `api/stock/{ticker}/spot-exposures/expiry-strike`
- **Spot Exposures by Specific Expiry:** `api/stock/{ticker}/spot-exposures/{expiry}/strike`
- **Interpolated IV:** `api/stock/{ticker}/interpolated-iv`
- **IV Rank:** `api/stock/{ticker}/iv-rank`
- **IV Term Structure:** `api/stock/{ticker}/volatility/term-structure`
- **Historical Risk Reversal Skew:** `api/stock/{ticker}/historical-risk-reversal-skew` — SPY/QQQ/IWM only
- **Max Pain:** `api/stock/{ticker}/max-pain`
- **NOPE:** `api/stock/{ticker}/nope`
- **OI Change:** `api/stock/{ticker}/oi-change`
- **OI per Expiry:** `api/stock/{ticker}/oi-per-expiry`
- **OI per Strike:** `api/stock/{ticker}/oi-per-strike`
- **Realized Volatility:** `api/stock/{ticker}/volatility/realized`
- **Volatility Stats:** `api/stock/{ticker}/volatility/stats`

### Financial Statements & Fundamentals

For authoritative financials (10-K/10-Q line items, restatements, amendments), use the `sec-api` skill (xbrl-to-json) — it pulls directly from SEC EDGAR. UW's former `/financials`, `/income-statements`, `/balance-sheets`, `/cash-flows` endpoints are an Alpha Vantage-normalized subset of the same SEC filings with extra latency and are not documented here.

- **Earnings History:** `api/stock/{ticker}/earnings` — Params: `report_type`. Reported/estimated EPS, surprise, pre/post market timing.
- **Financial Earnings:** `api/stock/{ticker}/financials` — EPS vs estimates + surprise history. Response: `data.earnings[*]`. Fields: `report_date`, `report_type`, `fiscal_date_ending`, `report_time`, `reported_eps`, `estimated_eps`, `surprise`, `surprise_percentage`. Upcoming events have `reported_eps=None`.
- **Fundamental Breakdown:** `api/stock/{ticker}/fundamental-breakdown` — revenue-by-product / geography segments + RSU data (UW-specific pre-aggregation)
- **Insider Buy/Sells:** `api/stock/{ticker}/insider-buy-sells`
- **ATM Chains:** `api/stock/{ticker}/atm-chains` — `expirations[]` is effectively required; empty list returns HTTP 422

### Dark Pool

- **Recent (market-wide):** `api/darkpool/recent`
- **Ticker-specific:** `api/darkpool/{ticker}`
- `newer_than` / `older_than` params use UTC timestamp format (not `YYYY-MM-DD`).

### Market-Wide

- **Market Tide:** `api/market/market-tide`
- **Sector Tide:** `api/market/{sector}/sector-tide`
- **ETF Tide:** `api/market/{ticker}/etf-tide`
- **Correlations:** `api/market/correlations`
  - Required: `tickers=AAPL,MSFT,GOOGL,AMZN` (uppercase, no spaces) and `interval=1y`
  - Lowercase, spaces, or missing `interval` silently return `[]`. Only `interval=1y` reliably populated.
- **Sector ETFs:** `api/market/sector-etfs` — SPDR sector ETF stats (SPY, XLF, XLE, XLK, etc.)
- **FDA Calendar:** `api/market/fda-calendar`
- **Insider Buy/Sells (market):** `api/market/insider-buy-sells`
- **OI Change:** `api/market/oi-change`
- **Top Net Impact:** `api/market/top-net-impact`
- **Total Options Volume:** `api/market/total-options-volume`
- **Net Flow by Expiry:** `api/net-flow/expiry`

### Congress & Politicians

- **Congress Recent Trades:** `api/congress/recent-trades`
- **Congress Trader:** `api/congress/congress-trader`
- **Late Reports:** `api/congress/late-reports`
- **Politician Recent Trades:** `api/politician-portfolios/recent_trades` — working on our plan

### Insiders

For raw Form 4 filings (as-filed from SEC), use the `sec-api` skill. UW pre-aggregates same-person/same-day/same-code rows and adds market-wide filters, which is more convenient for flow-style queries.

- **Ticker Flow:** `api/insider/{ticker}/ticker-flow`
- **Sector Flow:** `api/insider/{sector}/sector-flow`

### Institutions

For raw 13F holdings (as-filed from SEC), use the `sec-api` skill.

- **Institutions List:** `api/institutions`
- **Activity:** `api/institution/{name}/activity/v2`
- **Sectors:** `api/institution/{name}/sectors`
- `{name}` is free-text; prefer the CIK (e.g. `0000102909` for Vanguard) from `/api/institutions`.

### ETFs

- **Exposure:** `api/etfs/{ticker}/exposure`
- **Holdings:** `api/etfs/{ticker}/holdings`
- **Info:** `api/etfs/{ticker}/info`
- **Weights:** `api/etfs/{ticker}/weights` — response is a flat dict without a `data` wrapper
- **In/Outflow:** `api/etfs/{ticker}/in-outflow`

### Short Selling

- **Screener:** `api/short_screener`
- **Short Data:** `api/shorts/{ticker}/data`
- **Failures to Deliver:** `api/shorts/{ticker}/ftds`
- **Interest/Float:** `api/shorts/{ticker}/interest-float/v2`
- **Volume & Ratio:** `api/shorts/{ticker}/volume-and-ratio` — response is a flat dict without a `data` wrapper
- **Volume by Exchange:** `api/shorts/{ticker}/volumes-by-exchange`

### Earnings

- **After Hours:** `api/earnings/afterhours`
- **Premarket:** `api/earnings/premarket`
- **Ticker Earnings:** `api/earnings/{ticker}`

### Seasonality

- **Market:** `api/seasonality/market`
- **Month Performers:** `api/seasonality/{month}/performers` — `month` is numeric `1`–`12`. String names (`"January"`) return HTTP 422.
- **Monthly Returns:** `api/seasonality/{ticker}/monthly`
- **Year/Month:** `api/seasonality/{ticker}/year-month`

### Crypto

- **Whale Transactions:** `api/crypto/whale-transactions`
- **Recent Whales:** `api/crypto/whales/recent`

### Other

- **Lit Flow Recent:** `api/lit-flow/recent`
- **Lit Flow Ticker:** `api/lit-flow/ticker`
- **Group Greek Flow:** `api/group-flow/{flow_group}/greek-flow`
- **Group Greek Flow by Expiry:** `api/group-flow/{flow_group}/greek-flow/{expiry}`
  - `flow_group` enum: `"mag7"`, `"semi"`, `"reit"`, `"refiners"`
- **Predictions Unusual:** `api/predictions/unusual` — response is nested `data.data[*]`
- **Predictions Whales:** `api/predictions/whales` — response is nested `data.data[*]`; each row has a numeric `asset_id`
- **Predictions Smart Money:** `api/predictions/smart-money` — response is nested `data.data[*]`
- **Predictions Insiders:** `api/predictions/insiders` — response is nested `data.data[*]`; each row has a numeric `asset_id`
- **Predictions Market:** `api/predictions/market/{asset_id}` — rich market-detail object; `asset_id` is a long numeric string discovered from the four predictions endpoints above
- **Market Liquidity:** `api/predictions/market/{asset_id}/liquidity` — full order book (bids/asks/best_bid/best_ask)
- **Option Contract Flow:** `api/option-contract/{id}/flow` — `side` is lowercase; stale/expired contract IDs return HTTP 500. Always use fresh IDs from `/api/stock/{ticker}/option-contracts`.
- **Option Contract Historic:** `api/option-contract/{id}/historic` — response is a flat dict without a `data` wrapper
- **Option Contract Intraday:** `api/option-contract/{id}/intraday`
- **Option Contract Volume Profile:** `api/option-contract/{id}/volume-profile`

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

### Gamma Exposure (GEX) by Strike+Expiry

```python
import os, httpx

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["OPENROUTER_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/stock/SPY/spot-exposures/expiry-strike", headers=headers, timeout=20)
data = resp.json().get("data", [])
for d in data[:10]:
    print(f"Strike={d.get('strike')} call_gex={d.get('call_gamma_oi')} put_gex={d.get('put_gamma_oi')}")
```

## Usage Rules

- All requests are `GET` only.
- Always include both `Authorization: Bearer` and `UW-CLIENT-API-ID: 100001` headers.
- Process responses in Python and print concise summaries — avoid dumping raw JSON.
- Use `limit` params to keep responses bounded.
- Most endpoints silently return `[]` (HTTP 200) on weekend/holiday dates and invalid tickers — cannot distinguish "no data" from "wrong param".
- Rate limits: 120 req/min, 20000 req/day (resets 8 PM Eastern). Track via response headers `x-uw-req-per-minute-remaining`, `x-uw-daily-req-count`, `x-uw-token-req-limit`.
- HTTP semantics: `401` = missing/invalid token; `429` = per-minute or daily quota exceeded (body contains `"Approaching daily quota"`); `422` = premium/enterprise-gated endpoints not on our plan (body: `"Missing access for ... enterprise only endpoint"`) OR missing/invalid required params.
- **Endpoints not available on our plan** (always return HTTP 422 — do not call): `stock/{ticker}/ownership`, `politician-portfolios/people`, `politician-portfolios/{politician_id}`, `politician-portfolios/disclosures`, `politician-portfolios/holders/{ticker}`, `predictions/market/{asset_id}/positions` (HashDive dependency error). Of the Congress & Politicians group, only `politician-portfolios/recent_trades` is accessible.
- Boolean filter params (`is_call`, `is_put`, `is_floor`, `is_sweep`, etc.) filter-when-set — leave unset for "no filter".
- Most endpoints wrap payload in `{data: [...]}`, but some return a top-level JSON list (`stock/flow-recent`, `stock/flow-per-expiry`, `stock/flow-per-strike`) or a flat dict without a `data` key (`etfs/{ticker}/weights`, `shorts/{ticker}/volume-and-ratio`, `option-contract/{id}/historic`). Inspect `type(resp.json())` before calling `.get('data')`. Prediction endpoints (`predictions/unusual`, `whales`, `smart-money`, `insiders`) wrap twice: `data.data[*]`.
