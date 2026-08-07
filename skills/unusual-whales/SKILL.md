---
name: unusual-whales
description: Query daily ETF fund flows (creations and redemptions), unusual options flow, dark pool prints, market tide, stock greek exposure, short interest, congressional/insider trading, earnings, and sector ETF data via the Unusual Whales API proxy. Use when users ask how much money went into or out of an ETF, for options flow alerts, whale trades, dark pool data, GEX/gamma exposure, short interest, or market sentiment.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Unusual Whales API (via proxy)

Use `httpx` to query the Unusual Whales API through the backend proxy. Do not use direct vendor endpoints.

## Authentication and Proxy Base

```python
import os
import httpx

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]

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
| **ETF fund flows / money into or out of an ETF / creations and redemptions** | `/api/etfs/{ticker}/in-outflow` |
| Live flow / whale trades / option flow | `/api/option-trades/flow-alerts` |
| Options screener / flow filter | `/api/screener/option-contracts` |
| Market sentiment / market tide | `/api/market/market-tide` |
| Intraday pressure from options flow on one ETF | `/api/market/{ticker}/etf-tide` |
| Dark pool | `/api/darkpool/recent` or `/api/darkpool/{ticker}` |
| Short interest / days to cover / failures to deliver | `/api/shorts/{ticker}/interest-float/v2`, `/api/shorts/{ticker}/ftds` |
| Contract greeks (SPY/QQQ/IWM only) | `/api/stock/{ticker}/greeks` |
| Spot gamma / GEX / gamma exposure | `/api/stock/{ticker}/spot-exposures/expiry-strike` |
| Earnings history | `/api/stock/{ticker}/earnings` |

## Valid Endpoint Reference

### Flow & Options Screening

- **Flow Alerts:** `api/option-trades/flow-alerts`
  - Params: `limit`, `is_call`, `is_put`, `is_otm`, `min_premium`, `ticker_symbol`, `size_greater_oi`
  - Boolean params filter-when-set — leave unset for "no filter". `side` is uppercase.
- **Options Screener:** `api/screener/option-contracts`
  - Params: `limit` (default is 1 — always set explicitly), `min_premium`, `type`, `is_otm`, `issue_types[]`, `min_volume_oi_ratio`, `min_ask_perc` / `max_ask_perc` (both 0–1 decimals), `min_iv_perc` / `max_iv_perc`, `min_delta` / `max_delta`, `min_marketcap` / `max_marketcap`, `min_dte` / `max_dte`, `vol_greater_oi`, `order`, `order_direction`, `page`
- **Unusual Tickers:** `api/option-trades/unusual-tickers` — tickers with unusual options activity right now
- **Single Flow Alert:** `api/option-trades/flow-alerts/{id}`
- **Stock Screener:** `api/screener/stocks` — screen the entire market without specifying a ticker; supports IV rank, volatility, market cap, and options flow filters
  - **Volatility/IV params:** `min_iv_rank` / `max_iv_rank` (0–100), `min_volatility` / `max_volatility` (decimal, e.g. `"0.30"` = 30% IV), `min_implied_move_perc` / `max_implied_move_perc`
  - **Size params:** `min_marketcap` / `max_marketcap` (dollars), `min_underlying_price` / `max_underlying_price`
  - **Options flow params:** `min_volume` / `max_volume`, `min_premium` / `max_premium`, `min_call_premium` / `max_call_premium`, `min_put_premium` / `max_put_premium`, `min_net_premium` / `max_net_premium`, `min_put_call_ratio` / `max_put_call_ratio`, `min_oi` / `max_oi`, `min_oi_vs_vol` / `max_oi_vs_vol`
  - **OI change params:** `min_total_oi_change_perc` / `max_total_oi_change_perc`, `min_call_oi_change_perc`, `min_put_oi_change_perc`
  - **Volume vs avg params:** `min_perc_3_day_total`, `min_perc_30_day_total`, `min_stock_volume_vs_avg30_volume`
  - **Universe filters:** `sectors[]`, `issue_types[]`, `is_s_p_500` (true only), `has_dividends`
  - **Sorting:** `order` (any response field), `order_direction` (`asc` / `desc`), `date` (historical date)
  - **Response fields include:** `ticker`, `name`, `sector`, `marketcap`, `iv_rank`, `iv30d`, `iv30d_1d`, `iv30d_1w`, `iv30d_1m`, `implied_move_perc`, `volatility`, `put_call_ratio`, `total_premium`, `oi`

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
- **Max Pain:** `api/stock/{ticker}/max-pain` — Response: `data[*]`. Fields: `expiry`, `max_pain`, `call_oi`, `put_oi`, `call_notional`, `put_notional`.
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
- **Insider Buy/Sells:** `api/stock/{ticker}/insider-buy-sells` — Response: `data[*]`. Aggregated by `filing_date` (not individual transactions). Fields: `filing_date`, `purchases`, `sells`, `notional`.
- **ATM Chains:** `api/stock/{ticker}/atm-chains` — `expirations[]` is effectively required; empty list returns HTTP 422

### Dark Pool

A dark pool print is a trade executed off-exchange (through an ATS or an internalizer) and reported to a FINRA trade reporting facility after the fact. It shows size and price but never a buyer or seller, and never a side.

- **Recent (market-wide):** `api/darkpool/recent` — use this to scan for large blocks without naming a ticker first.
- **Ticker-specific:** `api/darkpool/{ticker}`
- `newer_than` / `older_than` params use UTC timestamp format (not `YYYY-MM-DD`).
- `min_premium` filters by dollar notional. Always set it — unfiltered, the response is mostly odd-lot retail routing. `min_premium=1000000` is a reasonable floor for "block".
- Fields: `ticker`, `size`, `price`, `premium`, `volume` (the ticker's cumulative volume, not the print's), `executed_at`, `trf_executed_at`, `market_center`, `canceled`, `ext_hour_sold_codes`, `sale_cond_codes`, `trade_settlement`, `tracking_id`.
- **Side inference.** Every print carries the NBBO at execution: `nbbo_bid`, `nbbo_ask`, `nbbo_bid_quantity`, `nbbo_ask_quantity`. A print at or above the ask reads as buyer-initiated, at or below the bid as seller-initiated, and inside the spread as unclassifiable. Compute this in Python from the fields above. **It is an inference, not a reported side** — say so when you report it, and do not present a day's net inferred flow as an observed number.
- `executed_at` is when the trade happened; `trf_executed_at` is when it was reported. Late-reported prints can be minutes or hours old, so sort by `executed_at` when building a timeline.

### Market-Wide

- **Market Tide:** `api/market/market-tide` — full session, one row per interval (81 rows for a regular session).
- **Sector Tide:** `api/market/{sector}/sector-tide`
- **ETF Tide:** `api/market/{ticker}/etf-tide` — intraday pressure from options flow on one ETF. Fields per row: `timestamp`, `date`, `net_call_premium`, `net_put_premium`, `net_volume`, `underlying_price`, all strings. Direction read off tide is an inference about positioning, not a fund flow — for actual money in and out of an ETF use `api/etfs/{ticker}/in-outflow`.
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

### Insiders (only when specifically requested)

For raw Form 4 filings (as-filed from SEC), use the `sec-api` skill. UW pre-aggregates same-person/same-day/same-code rows and adds market-wide filters, which is more convenient for flow-style queries. Most insider filings are routine 10b5-1 plan sales or options exercises -- only fetch when the coordinator specifically asks about insider activity.

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
- **Fund flows (in/outflow):** `api/etfs/{ticker}/in-outflow` — **daily** creations and redemptions for one ETF. This is the answer to "how much money went into SPY last week" and every variant of it. Do not answer that question from web search: issuer pages and ETF.com publish weekly roundups, which are the wrong granularity and usually days stale.
  - One call returns the full history, newest row first — 680 daily rows back to 2023-08-07 for QQQ as of 2026-08-04. No date params needed; slice the list in Python.
  - Fields: `date`, `change_prem` (net dollar flow, a **string** — cast before arithmetic), `change` (net shares, integer), `close` (string), `volume`, `expiration_cycle`, `is_fomc`.
  - Negative `change_prem` is an outflow. Example: SPY on 2026-08-04 was `-6128000000`, a $6.13B outflow.
  - Sum `change_prem` over a date slice for a weekly or monthly figure rather than reporting a single day as a trend.

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

### ETF Fund Flows (Daily, Summed Over a Window)

```python
import os, httpx
from datetime import date, timedelta

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/etfs/SPY/in-outflow", headers=headers, timeout=20)
resp.raise_for_status()  # a 401 or 429 must not read as "no flows"
rows = resp.json().get("data", [])  # newest first

# Anchor to the newest session in the data, not the host clock. The sandbox runs
# UTC, which rolls over five hours before New York does and would drop a session.
latest = date.fromisoformat(rows[0]["date"])
cutoff = str(latest - timedelta(days=6))  # that session plus the six prior dates
window = [r for r in rows if r["date"] >= cutoff]
net = sum(float(r["change_prem"]) for r in window)

print(f"SPY net flow, last 7 days: ${net/1e9:+.2f}B over {len(window)} sessions")
for r in window:
    print(f"  {r['date']}  {float(r['change_prem'])/1e6:+10.1f}M  close={r['close']}")
```

### Flow Alerts (Unusual Activity)

```python
import os, httpx

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
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

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
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
    print(f"{d.get('ticker_symbol')} {d.get('option_symbol')} premium={d.get('premium')}")
```

### Market Tide (Sentiment)

```python
import os, httpx

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
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

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

resp = httpx.get(f"{proxy_base.rstrip('/')}/api/darkpool/NVDA", headers=headers, params={
    "min_premium": 1_000_000,
    "limit": 100,
}, timeout=20)
resp.raise_for_status()
data = resp.json().get("data", [])

def inferred_side(p):
    """Buyer- or seller-initiated, inferred from where the print sat in the NBBO.
    Not a reported side. Report it as an inference."""
    price, bid, ask = float(p["price"]), float(p["nbbo_bid"]), float(p["nbbo_ask"])
    if price >= ask:
        return "buy"
    if price <= bid:
        return "sell"
    return "unclassified"

for d in data[:10]:
    print(f"{d['ticker']} ${float(d['premium'])/1e6:.1f}M size={d['size']} "
          f"price={d['price']} side~{inferred_side(d)} at={d['executed_at']}")
```

### Stock IV Screener (High IV Rank by Market Cap)

```python
import os, httpx

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
headers = {"Authorization": f"Bearer {api_key}", "UW-CLIENT-API-ID": "100001"}

# Large-cap stocks (>$10B) with IV rank 70–99, sorted by IV rank desc
# Use max_iv_rank="99.9" to exclude 100 (all-time high IV — usually earnings imminent)
resp = httpx.get(f"{proxy_base.rstrip('/')}/api/screener/stocks", headers=headers, params={
    "min_marketcap": "10000000000",
    "min_iv_rank": "70",
    "max_iv_rank": "99.9",
    "order": "iv_rank",
    "order_direction": "desc",
}, timeout=20)
data = resp.json().get("data", [])

print(f"{'Ticker':<8} {'IV Rank':>8} {'IV30d':>7} {'Mkt Cap':>10} {'Imp Move%':>10} {'Sector'}")
print("-" * 75)
for s in data[:20]:
    print(
        f"{s['ticker']:<8} "
        f"{float(s.get('iv_rank') or 0):>8.1f} "
        f"{float(s.get('iv30d') or 0)*100:>6.1f}% "
        f"${float(s.get('marketcap') or 0)/1e9:>7.1f}B "
        f"{float(s.get('implied_move_perc') or 0)*100:>9.1f}%  "
        f"{s.get('sector') or ''}"
    )
```

> **IV rank 100** = current IV is the highest in the past 52 weeks — almost always earnings within days. After earnings the IV collapses (IV crush), so premium sellers target this window.

### Gamma Exposure (GEX) by Strike+Expiry

```python
import os, httpx

proxy_base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/unusual-whale-proxy")
api_key = os.environ["PROXY_API_KEY"]
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
