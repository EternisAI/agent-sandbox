---
name: financial-data
description: Fetch financial market data (stocks, options, crypto, forex, economy, fundamentals) using the Massive Python SDK. Use when agents need stock prices, aggregates, snapshots, financials, indicators, or any market data. Supports all Massive.com/Polygon.io endpoints.
allowed-tools: Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py *), Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Massive Python SDK (Financial Market Data)

The `massive` Python package provides typed access to the full Massive.com (formerly Polygon.io) REST API. The API key is proxied through the backend -- never use a raw API key.

## Sandbox Environment

- **Python 3.12** with full standard library (including `math`, `statistics`, `datetime`, `json`, `csv`, `collections`, `bisect`, `itertools`)
- **`uv` package installer** is available -- run `uv pip install pandas numpy` if you need data analysis libraries (they are NOT pre-installed)
- **No pandas/numpy/scipy/matplotlib by default** -- use stdlib for calculations, or install with `uv pip install <package>` first
- **Bash** is available at `/usr/bin/bash`
- **Node.js 24** and **pnpm** are available

## Authentication

```python
import os
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)
```

## Getting the Current/Latest Price (recommended approach)

The most reliable way to get a ticker's current price that works on the basic plan regardless of market hours:

```python
import os
from datetime import date, timedelta
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)

# 1. Previous close -- always available, returns a LIST (access [0])
prev = client.get_previous_close_agg("AAPL")
p = prev[0]
print(f"Last close: ${p.close}  O:{p.open} H:{p.high} L:{p.low} Vol:{p.volume} VWAP:{p.vwap}")

# 2. Recent daily bars for context (returned in chronological order, oldest first)
today = date.today()
aggs = client.get_aggs("AAPL", 1, "day", str(today - timedelta(days=7)), str(today))
for a in aggs:
    print(f"  {a.timestamp}: O:{a.open} H:{a.high} L:{a.low} C:{a.close} V:{a.volume}")

# 3. Market status
status = client.get_market_status()
print(f"Market: {status.market}, Server time: {status.server_time}")
```

**Why this approach:** `get_last_trade`/`get_last_quote` require a higher-tier plan (NOT_AUTHORIZED on basic). `get_snapshot_ticker` returns None/zeroed fields when market is closed. `get_previous_close_agg` + `get_aggs` always work.

## Method Index with Field Names

All field values are **floats** unless noted. Timestamps are **int** (Unix epoch milliseconds). Dates are **str** (ISO format "YYYY-MM-DD").

### Aggregates (OHLCV price data)

- `get_aggs(ticker, multiplier, timespan, from_, to)` -> **List[Agg]** -- returns bars in **chronological order** (oldest first)
- `list_aggs(ticker, multiplier, timespan, from_, to)` -> Iterator[Agg] -- auto-paginates
- `get_grouped_daily_aggs(date)` -> List[GroupedDailyAgg] -- all tickers for one day
- `get_daily_open_close_agg(ticker, date)` -> DailyOpenCloseAgg
- `get_previous_close_agg(ticker)` -> **List[PreviousCloseAgg]** -- returns a list, access `[0]` for the single result

**Agg fields:** `open`, `high`, `low`, `close`, `volume`, `vwap`, `timestamp` (int, epoch ms), `transactions` (int), `otc` (bool)

### Indicators

- `get_sma(ticker)` -> SingleIndicatorResults -- access `.values` (list of IndicatorValue)
- `get_ema(ticker)` -> SingleIndicatorResults
- `get_rsi(ticker)` -> SingleIndicatorResults
- `get_macd(ticker)` -> MACDIndicatorResults -- access `.values` (list of MACDValue)

**IndicatorValue fields:** `timestamp`, `value`
**MACDValue fields:** `value`, `signal`, `histogram`

### Snapshots

- `get_snapshot_ticker(market_type, ticker)` -> TickerSnapshot -- **WARNING:** `last_trade` and `last_quote` will be `None` and `day` fields zeroed when market is closed. Always null-check before accessing nested fields.
- `get_snapshot_all(market_type)` -> List[TickerSnapshot]
- `get_snapshot_option(underlying_asset, option_contract)` -> OptionContractSnapshot -- single option contract snapshot
- `get_snapshot_direction(market_type, direction)` -> List[TickerSnapshot] -- `direction` is `"gainers"` or `"losers"`
- `get_snapshot_indices()` -> List[IndicesSnapshot] -- filter with `ticker_any_of=`
- `list_universal_snapshots()` -> Iterator[UniversalSnapshot]
- `list_snapshot_options_chain(underlying_asset)` -> Iterator[OptionContractSnapshot]

**TickerSnapshot fields:** `ticker` (str), `day` (Agg), `prev_day` (Agg), `last_trade` (LastTrade or None), `last_quote` (LastQuote or None), `min` (MinuteSnapshot), `todays_change`, `todays_change_percent`, `updated` (int), `fair_market_value`

**IndicesSnapshot fields:** `ticker` (str), `value`, `name` (str), `type` (str), `market_status` (str), `session` (IndicesSession)

### Economy

- `list_treasury_yields()` -> Iterator[TreasuryYield]
- `list_inflation()` -> Iterator[FedInflation]
- `list_inflation_expectations()` -> Iterator[FedInflationExpectations]
- `list_labor_market_indicators()` -> Iterator[FedLaborMarket]

All economy methods accept date filters: `date=`, `date_gt=`, `date_gte=`, `date_lt=`, `date_lte=`, `limit=`, `sort=`, `order=`.

**TreasuryYield fields:** `date` (str), `yield_1_month`, `yield_3_month`, `yield_6_month`, `yield_1_year`, `yield_2_year`, `yield_3_year`, `yield_5_year`, `yield_7_year`, `yield_10_year`, `yield_20_year`, `yield_30_year`

**FedInflation fields:** `date` (str), `cpi`, `cpi_core`, `cpi_year_over_year`, `pce`, `pce_core`, `pce_spending` -- numeric fields may be `None` for recent/incomplete periods

### Financials (requires higher-tier plan)

- `list_financials_income_statements()` -> Iterator[FinancialIncomeStatement] -- **NOT_AUTHORIZED on current plan**
- `list_financials_balance_sheets()` -> Iterator[FinancialBalanceSheet] -- **NOT_AUTHORIZED on current plan**
- `list_financials_cash_flow_statements()` -> Iterator[FinancialCashFlowStatement] -- **NOT_AUTHORIZED on current plan**
- `list_financials_ratios()` -> Iterator[FinancialRatio] -- **NOT_AUTHORIZED on current plan**
- `list_stocks_floats()` -> Iterator[FinancialFloat] -- filter with `ticker=`, `limit=`

**FinancialFloat fields:** `ticker` (str), `effective_date` (str), `free_float` (int), `free_float_percent` (float)

### Reference

- `get_ticker_details()` -> TickerDetails -- name, market_cap, description, sic_code, etc.
- `list_tickers()` -> Iterator[Ticker]
- `list_ticker_news()` -> Iterator[TickerNews] -- **SLOW/large payloads**, always set `limit=5` to `limit=10`; prefer `next(iter(...))` for latest
- `get_related_companies()` -> RelatedCompany
- `get_ticker_events(ticker)` -> TickerChangeResults -- corporate events (name changes, mergers, etc.)
- `get_ticker_types()` -> List[TickerTypes] -- filter with `asset_class=`, `locale=`
- `list_dividends()` -> Iterator[Dividend]
- `list_splits()` -> Iterator[Split]
- `list_short_volume()` -> Iterator[ShortVolume] -- auto-paginates, wrap with `list()`
- `list_short_interest()` -> Iterator[ShortInterest] -- auto-paginates, wrap with `list()`
- `list_stocks_dividends()` -> Iterator[StockDividend] -- filter with `ticker=`, `ex_dividend_date=`, `limit=`
- `list_stocks_splits()` -> Iterator[StockSplit] -- filter with `ticker=`, `execution_date=`, `limit=`
- `get_exchanges()` -> List[Exchange] -- filter with `asset_class=`, `locale=`
- `list_conditions()` -> Iterator[Condition] -- filter with `asset_class=`, `data_type=`, `limit=`

**TickerChangeResults fields:** `name` (str), `composite_figi` (str), `cik` (str), `events` (list of TickerChangeEvent)

**TickerTypes fields:** `asset_class` (str), `code` (str), `description` (str), `locale` (str)

**StockDividend fields:** `ticker` (str), `cash_amount`, `currency` (str), `declaration_date` (str), `ex_dividend_date` (str), `pay_date` (str), `record_date` (str), `frequency` (int), `distribution_type` (str)

**StockSplit fields:** `ticker` (str), `execution_date` (str), `split_from`, `split_to`, `adjustment_type` (str)

**Exchange fields:** `id` (int), `name` (str), `acronym` (str), `mic` (str), `asset_class` (str), `locale` (str), `type` (str)

**Condition fields:** `id` (int), `name` (str), `description` (str), `asset_class` (str), `type` (str), `data_types` (list of str)

### Options

- `get_options_contract(ticker)` -> OptionsContract
- `list_options_contracts()` -> Iterator[OptionsContract] -- filter with `underlying_ticker=`, `contract_type=` ("call"/"put"), `expiration_date=`, `expiration_date_lte=`, `strike_price=`, `limit=`

**OptionsContract fields:** `ticker` (str, OCC format), `underlying_ticker` (str), `contract_type` (str: "call" or "put"), `expiration_date` (str), `strike_price`, `shares_per_contract`, `exercise_style` (str), `primary_exchange` (str)

**OptionContractSnapshot fields** (from `list_snapshot_options_chain`): `break_even_price`, `implied_volatility` (float, decimal ratio e.g. 0.30 = 30%), `open_interest`, `fair_market_value`, plus nested objects:
- `details`: `contract_type` (str: "call"/"put"), `expiration_date` (str), `strike_price`, `ticker` (str), `exercise_style` (str), `shares_per_contract`
- `greeks`: `delta`, `gamma`, `theta`, `vega` -- **can be `None`** for illiquid/far-OTM contracts or when market is closed. Always check `if c.greeks is not None` before accessing.
- `day`: `open`, `high`, `low`, `close`, `volume`, `vwap`, `change`, `change_percent`, `previous_close`, `last_updated` (int) -- **can be `None`** when market is closed. Always check `if c.day is not None` before accessing fields.
- `last_quote`: bid/ask data (may be None when market closed)
- `last_trade`: last trade data (may be None when market closed)
- `underlying_asset`: underlying ticker info

### Trades & Quotes (requires higher-tier plan)

- `get_last_trade(ticker)` -> LastTrade -- **NOT_AUTHORIZED on current plan**
- `list_trades(ticker)` -> Iterator[Trade] -- **NOT_AUTHORIZED on current plan**
- `get_last_quote(ticker)` -> LastQuote -- **NOT_AUTHORIZED on current plan**
- `list_quotes(ticker)` -> Iterator[Quote] -- **NOT_AUTHORIZED on current plan**

### Forex & Crypto

- `get_last_forex_quote(from_, to)` -> LastForexQuote
- `get_real_time_currency_conversion(from_, to)` -> RealTimeCurrencyConversion
- `get_last_crypto_trade(from_, to)` -> CryptoTrade
- Crypto/forex aggregates: use `get_aggs("X:BTCUSD", ...)` or `get_aggs("C:EURUSD", ...)`

### Other

- `get_market_status()` -> MarketStatus -- `market` (str: "open"/"closed"), `server_time` (str), `exchanges` (nested)
- `get_market_holidays()` -> List[MarketHoliday]

### Benzinga (analyst signal endpoints)

- `list_benzinga_ratings()` -> Iterator[...] -- maps to `/benzinga/v1/ratings`; analyst upgrades/downgrades/PT changes
- `list_benzinga_analysts()` -> Iterator[...] -- maps to `/benzinga/v1/analysts`; analyst track record and accuracy context

Example helper calls:

```python
ratings = list(client.list_benzinga_ratings(limit=50))
analysts = list(client.list_benzinga_analysts(limit=50))
```

### Blocked categories (NOT_AUTHORIZED on current plan)

The following SDK method groups exist in `massive==2.4.0` but are entirely blocked on the current plan. Do not call these -- they will all throw `BadResponse` with `NOT_AUTHORIZED`.

- **Benzinga (8 methods blocked):** `list_benzinga_analyst_insights`, `list_benzinga_bulls_bears_say`, `list_benzinga_consensus_ratings`, `list_benzinga_earnings`, `list_benzinga_firms`, `list_benzinga_guidance`, `list_benzinga_news`, `list_benzinga_news_v2`
- **ETF Global (5 methods):** `get_etf_global_analytics`, `get_etf_global_constituents`, `get_etf_global_fund_flows`, `get_etf_global_profiles`, `get_etf_global_taxonomies` -- use `composite_ticker=` param (not `ticker=`)
- **Futures (9 methods):** `get_futures_snapshot`, `list_futures_aggregates`, `list_futures_contracts`, `list_futures_exchanges`, `list_futures_market_statuses`, `list_futures_products`, `list_futures_quotes`, `list_futures_schedules`, `list_futures_trades`
- **Summaries (1 method):** `get_summaries`
- **TMX (1 method):** `list_tmx_corporate_events`
- **SEC Filings (5 methods) -- use `sec-api` skill instead:** `list_stocks_filings_index`, `list_stocks_filings_10k_sections`, `list_stocks_filings_8k_text`, `list_stocks_filings_risk_factors`, `list_stocks_taxonomies_risk_factors` (Polygon responses time out on real payloads even with `limit=1`)

### Deprecated / broken

- `get_snapshot_crypto_book(ticker)` -- returns 404, likely deprecated. Use `get_aggs("X:BTCUSD", ...)` for crypto data instead.

## Examples by Category

### Multi-ticker comparison (stdlib only)

```python
import os, math, time
from datetime import date, timedelta
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)

tickers = ["AAPL", "MSFT", "GOOGL", "AMZN"]
today = date.today()
start = str(today - timedelta(days=45))  # overshoot to get ~30 trading days

for ticker in tickers:
    aggs = client.get_aggs(ticker, 1, "day", start, str(today))
    time.sleep(0.5)  # rate limit
    closes = [a.close for a in aggs][-31:]
    ret = (closes[-1] - closes[0]) / closes[0] * 100
    daily_rets = [(closes[i] - closes[i-1]) / closes[i-1] for i in range(1, len(closes))]
    mean_r = sum(daily_rets) / len(daily_rets)
    vol = math.sqrt(sum((r - mean_r)**2 for r in daily_rets) / (len(daily_rets) - 1)) * math.sqrt(252) * 100
    sharpe = (mean_r / (vol / 100 / math.sqrt(252))) * math.sqrt(252) if vol > 0 else 0
    print(f"{ticker}: Return={ret:+.2f}%  AnnVol={vol:.1f}%  Sharpe={sharpe:.2f}")
```

### Treasury yields vs inflation (real yield analysis)

```python
import os
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)

# Treasury yields are daily, inflation is monthly -- both have .date (str "YYYY-MM-DD")
yields = list(client.list_treasury_yields(limit=30, sort="date", order="desc"))
inflation = list(client.list_inflation(limit=12, sort="date", order="desc"))

# Latest inflation reading for real yield calc
latest_cpi_yoy = inflation[0].cpi_year_over_year if inflation else 0

print(f"Latest CPI YoY: {latest_cpi_yoy:.2f}%")
print(f"\n{'Date':<12} {'10Y Nominal':>12} {'Real Yield':>11}")
for y in yields[:10]:
    real = y.yield_10_year - latest_cpi_yoy
    print(f"{y.date:<12} {y.yield_10_year:>11.3f}% {real:>10.3f}%")
```

### Options chain analysis

```python
import os
from datetime import date, timedelta
from massive import RESTClient

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/massive-proxy")
client = RESTClient(api_key=os.environ["OPENROUTER_API_KEY"], base=proxy_base)

cutoff = str(date.today() + timedelta(days=30))
chain = list(client.list_snapshot_options_chain("AAPL"))

puts, calls = 0, 0
volume_by_strike = {}

for c in chain:
    # Use c.details for contract info, c.day for volume (may be None when market closed)
    if c.details.expiration_date > cutoff:
        continue
    if c.details.contract_type == "call":
        calls += 1
    elif c.details.contract_type == "put":
        puts += 1
    strike = c.details.strike_price
    vol = c.day.volume if c.day is not None else 0
    volume_by_strike[strike] = volume_by_strike.get(strike, 0) + (vol or 0)

print(f"Put/Call Ratio: {puts/calls:.2f} ({puts} puts / {calls} calls)")
print("\nTop 10 strikes by volume:")
for strike, vol in sorted(volume_by_strike.items(), key=lambda x: -x[1])[:10]:
    print(f"  ${strike}: {vol:,.0f}")
```

## Discovering Methods and Models

Use `discover.py` when you need details beyond what's documented above (e.g., less common models, exact parameter signatures):

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py methods              # list all methods
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py method get_aggs      # full signature + return model
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py model aggs.Agg       # model fields
python3 ${CLAUDE_SKILL_DIR}/scripts/discover.py search snapshot      # keyword search
```

## Key Patterns

### Process data in code, return only summaries

Avoid printing raw API responses. Process and filter data in Python, then print only the final summary. This keeps model context small:

```python
# BAD -- dumps raw data into context
aggs = client.get_aggs("AAPL", 1, "day", "2026-01-01", "2026-03-31")
print(aggs)  # hundreds of lines

# GOOD -- process in code, print summary only
aggs = client.get_aggs("AAPL", 1, "day", "2026-01-01", "2026-03-31")
closes = [a.close for a in aggs]
print(f"AAPL: {len(closes)} bars, range ${min(closes):.2f}-${max(closes):.2f}, latest ${closes[-1]:.2f}")
```

### Chaining data from multiple sources

```python
# Fetch two tickers and merge by timestamp
aapl = client.get_aggs("AAPL", 1, "day", "2026-01-01", "2026-03-31")
msft = client.get_aggs("MSFT", 1, "day", "2026-01-01", "2026-03-31")

aapl_by_ts = {a.timestamp: a.close for a in aapl}
msft_by_ts = {m.timestamp: m.close for m in msft}

common_ts = sorted(set(aapl_by_ts) & set(msft_by_ts))
for ts in common_ts[-5:]:
    print(f"{ts}: AAPL=${aapl_by_ts[ts]:.2f}  MSFT=${msft_by_ts[ts]:.2f}")
```

### Filtering with optional params

Most `list_*` methods support filter params: `ticker=`, `limit=`, `sort=`, `order=`, date ranges (`date_gt=`, `date_lte=`, etc.).

```python
divs = list(client.list_dividends(ticker="AAPL", limit=4))
news = list(client.list_ticker_news(ticker="AAPL", limit=10))
```

### Iterator vs List methods

- `list_*` methods return iterators that auto-paginate -- use with `list()` or `for` loops
- `get_*` methods return a single object or a list (no pagination)
- **Always use `limit=`** to avoid unbounded pagination

## Critical Gotchas

1. **`get_previous_close_agg` returns a list**, not a single object. Access `[0]` for the result.
2. **`get_aggs` returns bars in chronological order** (oldest first). The last element is the most recent bar.
3. **`get_snapshot_ticker` fields can be `None`/zeroed when market is closed.** `last_trade` and `last_quote` will be `None`, `day` OHLCV will be all zeros. Always null-check: `if snap.last_trade is not None:`.
4. **`get_last_trade`, `get_last_quote`, `list_trades`, `list_quotes` require a higher-tier plan.** They throw `BadResponse` with `NOT_AUTHORIZED`. Use `get_previous_close_agg` + `get_aggs` instead.
5. **Financials endpoints (`list_financials_*`) require higher-tier plans** -- same `NOT_AUTHORIZED` error. `list_stocks_floats` works on the current plan.
6. **Indicator methods return wrapper objects, NOT iterables.** Access `.values` to get the list.
7. **Parameter names use `tickers` (plural)** for financials methods, not `ticker`. ETF Global methods use `composite_ticker=`, not `ticker=`.
8. **Rate limits:** add `time.sleep(0.5)` between rapid-fire calls, or use `limit=` to reduce pagination.
9. **`get_grouped_daily_aggs` returns empty for non-trading days** (weekends/holidays) -- no error.
10. **Crypto tickers** use `X:` prefix (e.g., `X:BTCUSD`), **forex** uses `C:` prefix (e.g., `C:EURUSD`).
11. **All timestamps are Unix epoch milliseconds (int).** Convert with `datetime.fromtimestamp(ts / 1000)`.
12. **Economy data frequencies differ:** treasury yields are daily, inflation is monthly. Align dates when combining.
13. **Options `contract_type` values are lowercase strings:** `"call"` or `"put"`.
14. **`get_snapshot_crypto_book` is deprecated** (returns 404). Use crypto aggregates instead.
