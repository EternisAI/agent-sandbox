---
name: massive-sdk
description: Fetch financial market data (stocks, options, crypto, forex, economy, fundamentals) using the Massive Python SDK. Use when agents need stock prices, aggregates, snapshots, financials, indicators, or any market data. Supports all Massive.com/Polygon.io endpoints.
allowed-tools: Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py *), Bash(python3 -c *)
---

# Massive Python SDK (Financial Market Data)

The `massive` Python package provides typed access to the full Massive.com (formerly Polygon.io) REST API. The API key is proxied through the backend -- never use a raw API key.

## Authentication

The SDK connects through the backend proxy. Pass the existing `OPENROUTER_API_KEY` (proxy JWT token) as the api_key -- the backend validates it and injects the real Massive API key.

```python
import os
from massive import RESTClient

# The proxy base URL is derived from OPENROUTER_BASE_URL
# e.g., https://backend.example.com/api/llm-proxy -> https://backend.example.com/api/massive-proxy
proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
token = os.environ["OPENROUTER_API_KEY"]

client = RESTClient(api_key=token, base=proxy_base)
```

## Quick Start

```python
import os
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)

# Daily OHLCV bars
aggs = client.get_aggs("AAPL", 1, "day", "2026-01-01", "2026-03-31")
for a in aggs:
    print(a.open, a.high, a.low, a.close, a.volume, a.timestamp)

# Ticker details
details = client.get_ticker_details("AAPL")
print(details.name, details.market_cap, details.description)

# Technical indicators (returns SingleIndicatorResults -- access .values)
sma = client.get_sma("AAPL", timespan="day", window=20, limit=10)
for v in sma.values:
    print(v.timestamp, v.value)

# MACD (returns MACDIndicatorResults -- access .values)
macd = client.get_macd("AAPL", timespan="day", limit=5)
for v in macd.values:
    print(v.value, v.signal, v.histogram)
```

## Discovering Methods and Models

Before writing code, use the discovery script to find the right method and understand its parameters and return types:

```bash
# List ALL methods grouped by category
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py methods

# Get full signature + return model fields for a specific method
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py method get_aggs
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py method list_financials_income_statements

# Search by keyword (searches both methods and models)
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py search inflation
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py search snapshot
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py search earnings

# Inspect a return model's fields and types
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py model aggs.Agg
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py model snapshot.TickerSnapshot
```

**Always run `discover.py method <name>` before using a method you haven't used before.** It shows you exact parameter names, types, which are required vs optional, and all fields on the return model.

## Method Index (compact reference)

### Aggregates (OHLCV price data)
- `get_aggs(ticker, multiplier, timespan, from_, to)` -> List[Agg] -- single ticker bars
- `list_aggs(ticker, multiplier, timespan, from_, to)` -> Iterator[Agg] -- auto-paginates
- `get_grouped_daily_aggs(date)` -> List[GroupedDailyAgg] -- all tickers for one day
- `get_daily_open_close_agg(ticker, date)` -> DailyOpenCloseAgg
- `get_previous_close_agg(ticker)` -> PreviousCloseAgg

### Indicators
- `get_sma(ticker)` -> SingleIndicatorResults -- access `.values` (list of IndicatorValue: timestamp, value)
- `get_ema(ticker)` -> SingleIndicatorResults
- `get_rsi(ticker)` -> SingleIndicatorResults
- `get_macd(ticker)` -> MACDIndicatorResults -- access `.values` (list: value, signal, histogram)

### Snapshots
- `get_snapshot_ticker(market_type, ticker)` -> TickerSnapshot (day, prev_day, last_trade, last_quote)
- `get_snapshot_all(market_type)` -> List[TickerSnapshot]
- `list_universal_snapshots()` -> Iterator[UniversalSnapshot]
- `list_snapshot_options_chain(underlying_asset)` -> Iterator[OptionContractSnapshot]

### Economy
- `list_treasury_yields()` -> Iterator[TreasuryYield] -- yield_1_month through yield_30_year
- `list_inflation()` -> Iterator[FedInflation] -- cpi, pce, year-over-year
- `list_inflation_expectations()` -> Iterator[FedInflationExpectations]
- `list_labor_market_indicators()` -> Iterator[FedLaborMarket]

### Financials (requires higher-tier plan)
- `list_financials_income_statements()` -> Iterator[FinancialIncomeStatement]
- `list_financials_balance_sheets()` -> Iterator[FinancialBalanceSheet]
- `list_financials_cash_flow_statements()` -> Iterator[FinancialCashFlowStatement]
- `list_financials_ratios()` -> Iterator[FinancialRatio]

### Reference
- `get_ticker_details()` -> TickerDetails -- name, market_cap, description, sic_code, etc.
- `list_tickers()` -> Iterator[Ticker]
- `list_ticker_news()` -> Iterator[TickerNews]
- `get_related_companies()` -> RelatedCompany
- `list_dividends()` -> Iterator[Dividend]
- `list_splits()` -> Iterator[Split]
- `list_short_volume()` -> List[ShortVolume]
- `list_short_interest()` -> List[ShortInterest]

### Options
- `get_options_contract(ticker)` -> OptionsContract
- `list_options_contracts()` -> Iterator[OptionsContract]

### Trades & Quotes
- `get_last_trade(ticker)` -> LastTrade
- `list_trades(ticker)` -> Iterator[Trade]
- `get_last_quote(ticker)` -> LastQuote
- `list_quotes(ticker)` -> Iterator[Quote]

### Forex & Crypto
- `get_last_forex_quote(from_, to)` -> LastForexQuote
- `get_real_time_currency_conversion(from_, to)` -> RealTimeCurrencyConversion
- `get_last_crypto_trade(from_, to)` -> CryptoTrade
- Crypto/forex aggregates: use `get_aggs("X:BTCUSD", ...)` or `get_aggs("C:EURUSD", ...)`

### Other
- `get_market_status()` -> MarketStatus
- `get_market_holidays()` -> List[MarketHoliday]
- `list_stocks_filings_index()` -> Iterator[FilingIndex] -- SEC filings
- VX (experimental): `client.vx.list_ipos()`, `client.vx.list_stock_financials()`

## Key Patterns

### Chaining data from multiple sources
```python
import os
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)

# Fetch two tickers and merge
aapl = client.get_aggs("AAPL", 1, "day", "2026-01-01", "2026-03-31")
msft = client.get_aggs("MSFT", 1, "day", "2026-01-01", "2026-03-31")

df_a = [{"t": a.timestamp, "aapl": a.close} for a in aapl]
df_m = [{"t": m.timestamp, "msft": m.close} for m in msft]
# Merge and analyze as needed
```

### Filtering with optional params
Most `list_*` methods support filter params like `ticker=`, `limit=`, `sort=`, date ranges (`timestamp_gt=`, etc.). Run `discover.py method <name>` to see available filters.

```python
# Dividends for a specific ticker
divs = list(client.list_dividends(ticker="AAPL", limit=4))

# News with date filter
news = list(client.list_ticker_news(ticker="AAPL", limit=10))
```

### Iterator vs List methods
- `list_*` methods return iterators that auto-paginate -- use with `list()` or `for` loops
- `get_*` methods return a single object or a list (no pagination)
- **Watch out for rate limits** when iterating large result sets -- add `limit=` param

## Critical Gotchas

1. **Indicator methods return wrapper objects, NOT iterables.** Access `.values` to get the list.
2. **Parameter names use `tickers` (plural)** for financials methods, not `ticker`.
3. **Rate limits:** add `time.sleep(0.5)` between rapid-fire calls, or use `limit=` to reduce pagination.
4. **`get_grouped_daily_aggs` returns empty for non-trading days** (weekends/holidays) -- no error.
5. **Crypto tickers** use `X:` prefix (e.g., `X:BTCUSD`), **forex** uses `C:` prefix (e.g., `C:EURUSD`).
6. **Some endpoints require higher-tier plans** -- you'll get a `BadResponse` with `NOT_AUTHORIZED`.
