---
name: cftc
description: Fetch CFTC Commitments of Traders (COT) positioning data — leveraged fund vs real money in financial futures (TFF) and managed money in commodity futures (Disaggregated). Use when asked about futures positioning, COT reports, hedge fund exposure, trader crowding, or speculative positioning in equities, rates, currencies, VIX, energy, or metals.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# CFTC Commitments of Traders (COT)

Weekly positioning data from the CFTC — who is long/short in futures markets and by how much. Unique in the stack: no other skill provides positioning/sentiment data for futures.

## Authentication

```python
import urllib.parse, urllib.request, json, os

DATASETS = {
    "tff":           "gpe5-46if",   # Traders in Financial Futures
    "disaggregated": "72hh-3qpy",  # Disaggregated (commodities)
}

def _cftc_get(dataset_key: str, params: dict) -> list:
    base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/cftc-proxy")
    token = os.environ["OPENROUTER_API_KEY"]
    query = urllib.parse.urlencode(params)
    url = f"{base.rstrip('/')}/{DATASETS[dataset_key]}.json?{query}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())
```

## Contract Name Maps

Use these to resolve natural language to exact CFTC `market_and_exchange_names` values (verified against live data).

```python
# TFF — sector filter (commodity_subgroup_name exact values)
TFF_SECTORS = {
    "equities":   "STOCK INDICES",
    "rates":      "Interest Rates - U.S. Treasury",
    "currencies": "CURRENCY",
}

# TFF — individual contract exact names
TFF_CONTRACTS = {
    "spx":     "S&P 500 Consolidated - CHICAGO MERCANTILE EXCHANGE",
    "nasdaq":  "NASDAQ-100 Consolidated - CHICAGO MERCANTILE EXCHANGE",
    "russell": "MICRO E-MINI RUSSELL 2000 INDX - CHICAGO MERCANTILE EXCHANGE",
    "10y":     "UST 10Y NOTE - CHICAGO BOARD OF TRADE",
    "2y":      "UST 2Y NOTE - CHICAGO BOARD OF TRADE",
    "5y":      "UST 5Y NOTE - CHICAGO BOARD OF TRADE",
    "30y":     "UST BOND - CHICAGO BOARD OF TRADE",
    "eur":     "EURO FX - CHICAGO MERCANTILE EXCHANGE",
    "jpy":     "JAPANESE YEN - CHICAGO MERCANTILE EXCHANGE",
    "gbp":     "BRITISH POUND - CHICAGO MERCANTILE EXCHANGE",
    "aud":     "AUSTRALIAN DOLLAR - CHICAGO MERCANTILE EXCHANGE",
    "cad":     "CANADIAN DOLLAR - CHICAGO MERCANTILE EXCHANGE",
    "chf":      "SWISS FRANC - CHICAGO MERCANTILE EXCHANGE",
    "vix":      "VIX FUTURES - CBOE FUTURES EXCHANGE",
    "nikkei":    "NIKKEI STOCK AVERAGE YEN DENOM - CHICAGO MERCANTILE EXCHANGE",
    "ultra_10y": "ULTRA UST 10Y - CHICAGO BOARD OF TRADE",
    "ultra_30y": "ULTRA UST BOND - CHICAGO BOARD OF TRADE",
    "sofr":      "SOFR-3M - CHICAGO MERCANTILE EXCHANGE",
    "fed_funds": "FED FUNDS - CHICAGO BOARD OF TRADE",
}

# Disaggregated — sector filter (commodity_subgroup_name exact values)
DISAG_SECTORS = {
    "precious_metals": "PRECIOUS METALS",
    "petroleum":       "PETROLEUM AND PRODUCTS",
    "natgas":          "NATURAL GAS AND PRODUCTS",
    "base_metals":     "BASE METALS",
    "grains":          "GRAINS",
}

# Disaggregated — individual contract exact names
DISAG_CONTRACTS = {
    "crude":  "WTI-PHYSICAL - NEW YORK MERCANTILE EXCHANGE",
    "brent":  "BRENT LAST DAY - NEW YORK MERCANTILE EXCHANGE",
    "natgas": "HENRY HUB - NEW YORK MERCANTILE EXCHANGE",
    "gold":   "GOLD - COMMODITY EXCHANGE INC.",
    "silver": "SILVER - COMMODITY EXCHANGE INC.",
    "copper": "COPPER- #1 - COMMODITY EXCHANGE INC.",  # note: space before #1, CFTC naming quirk
}
```

## Supported Tools

| Function | Dataset | Use For |
|---|---|---|
| `get_cot_tff` | `gpe5-46if` | HF/CTA vs real money in equity indices, rates, currencies, VIX |
| `get_cot_disaggregated` | `72hh-3qpy` | Managed money in energy, metals, agriculture |
| `summarize_cot_tff` | — | Clean net/delta/% OI dict from TFF raw rows |
| `summarize_cot_disaggregated` | — | Clean net/delta/% OI dict from Disaggregated raw rows |

## Discovery

Search for contract names by keyword — use this before querying if a contract isn't in the maps above.

```python
def search_contracts(keyword: str, dataset_key: str = "tff") -> list[str]:
    """Return all active contract names containing keyword (case-insensitive, 2024+ data)."""
    rows = _cftc_get(dataset_key, {
        "$select": "distinct market_and_exchange_names",
        "$where": f"market_and_exchange_names LIKE '%{keyword.upper()}%' AND report_date_as_yyyy_mm_dd >= '2024-01-01'",
        "$order": "market_and_exchange_names",
        "$limit": 100,
    })
    return [r["market_and_exchange_names"] for r in rows]

# Examples
search_contracts("BITCOIN", "tff")      # → ['BITCOIN - CHICAGO MERCANTILE EXCHANGE', ...]
search_contracts("BRENT", "disaggregated")  # → ['BRENT LAST DAY - NEW YORK MERCANTILE EXCHANGE', ...]
search_contracts("CORN", "disaggregated")
```

To list all subgroup names:
```python
_cftc_get("tff", {"$select": "distinct commodity_subgroup_name", "$limit": 50})
_cftc_get("disaggregated", {"$select": "distinct commodity_subgroup_name", "$limit": 50})
```

## Examples

```python
def get_cot_tff(date_from: str, sector: str | None = None, contract: str | None = None, limit: int = 50) -> list:
    """Fetch TFF COT rows. sector/contract accept keys from TFF_SECTORS/TFF_CONTRACTS or raw exact values."""
    where = f"report_date_as_yyyy_mm_dd >= '{date_from}'"
    if sector:
        val = TFF_SECTORS.get(sector, sector)
        where += f" AND commodity_subgroup_name = '{val}'"
    if contract:
        val = TFF_CONTRACTS.get(contract, contract)
        where += f" AND market_and_exchange_names = '{val}'"
    return _cftc_get("tff", {"$where": where, "$order": "report_date_as_yyyy_mm_dd DESC", "$limit": limit})

def get_cot_disaggregated(date_from: str, sector: str | None = None, contract: str | None = None, limit: int = 50) -> list:
    """Fetch Disaggregated COT rows. sector/contract accept keys from DISAG_SECTORS/DISAG_CONTRACTS or raw exact values."""
    where = f"report_date_as_yyyy_mm_dd >= '{date_from}'"
    if sector:
        val = DISAG_SECTORS.get(sector, sector)
        where += f" AND commodity_subgroup_name = '{val}'"
    if contract:
        val = DISAG_CONTRACTS.get(contract, contract)
        where += f" AND market_and_exchange_names = '{val}'"
    return _cftc_get("disaggregated", {"$where": where, "$order": "report_date_as_yyyy_mm_dd DESC", "$limit": limit})

def summarize_cot_tff(rows: list) -> list:
    """Compute net positioning, weekly delta, and % OI from raw TFF rows."""
    out = []
    for r in rows:
        lev_long  = int(r.get("lev_money_positions_long", 0) or 0)
        lev_short = int(r.get("lev_money_positions_short", 0) or 0)
        d_long    = int(r.get("change_in_lev_money_long", 0) or 0)
        d_short   = int(r.get("change_in_lev_money_short", 0) or 0)
        am_long   = int(r.get("asset_mgr_positions_long", 0) or 0)
        am_short  = int(r.get("asset_mgr_positions_short", 0) or 0)
        out.append({
            "date":          r["report_date_as_yyyy_mm_dd"][:10],
            "contract":      r["market_and_exchange_names"],
            "net_lev_fund":  lev_long - lev_short,
            "lev_long":      lev_long,
            "lev_short":     lev_short,
            "lev_delta":     d_long - d_short,
            "pct_oi_lev_long": float(r.get("pct_of_oi_lev_money_long", 0) or 0),
            "asset_mgr_net": am_long - am_short,
            "open_interest": int(r.get("open_interest_all", 0) or 0),
        })
    return out

def summarize_cot_disaggregated(rows: list) -> list:
    """Compute net positioning, weekly delta, and % OI from raw Disaggregated rows."""
    out = []
    for r in rows:
        mm_long  = int(r.get("m_money_positions_long_all", 0) or 0)
        mm_short = int(r.get("m_money_positions_short_all", 0) or 0)
        d_long   = int(r.get("change_in_m_money_long_all", 0) or 0)
        d_short  = int(r.get("change_in_m_money_short_all", 0) or 0)
        out.append({
            "date":           r["report_date_as_yyyy_mm_dd"][:10],
            "contract":       r["market_and_exchange_names"],
            "net_mm":         mm_long - mm_short,
            "mm_long":        mm_long,
            "mm_short":       mm_short,
            "mm_delta":       d_long - d_short,
            "pct_oi_mm_long": float(r.get("pct_of_oi_m_money_long_all", 0) or 0),
            "open_interest":  int(r.get("open_interest_all", 0) or 0),
        })
    return out

# --- Usage ---

# SPX positioning last 10 weeks
rows = get_cot_tff("2025-01-01", contract="spx", limit=10)
summary = summarize_cot_tff(rows)
for s in summary:
    print(f"{s['date']}  net={s['net_lev_fund']:+,}  Δ={s['lev_delta']:+,}  {s['pct_oi_lev_long']:.1f}%OI")

# All equity index positioning latest week
rows = get_cot_tff("2025-01-01", sector="equities", limit=50)
summary = summarize_cot_tff(rows)
for s in summary[:10]:
    print(f"{s['date']}  {s['contract'][:40]:<40}  net={s['net_lev_fund']:+,}")

# Gold positioning last 10 weeks
rows = get_cot_disaggregated("2025-01-01", contract="gold", limit=10)
summary = summarize_cot_disaggregated(rows)
for s in summary:
    print(f"{s['date']}  net={s['net_mm']:+,}  Δ={s['mm_delta']:+,}  {s['pct_oi_mm_long']:.1f}%OI")
```

## Notes

- **3-day lag:** Tuesday close data published Friday 3:30 PM ET. Holiday weeks push to Monday.
- **Date field is ISO datetime** (`2026-04-14T00:00:00.000`) — summarize functions slice `[:10]` to get date string.
- **TFF has no `_all` suffix** on position fields (`lev_money_positions_long`, not `lev_money_positions_long_all`). Disaggregated uses `_all` throughout — inconsistent across report types.
- **Contract names use exact match `=`** — use the Discovery queries above to find names if a contract isn't in the maps.
- **`$order` is required** — without `$order=report_date_as_yyyy_mm_dd DESC`, row order is undefined.
- **`$limit` default is 1,000** — always set explicitly. For full sector pulls use `$limit=50000`.
- **`pct_of_oi_*` for cross-contract comparison** — raw counts vary by contract size.
- **`swap__positions_short_all`** (Disaggregated) has a double underscore — CFTC data bug. Avoid accessing swap dealer shorts directly.
- Process data in Python, print summaries — keep model context small.
