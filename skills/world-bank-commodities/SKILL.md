---
name: world-bank-commodities
description: Fetch World Bank "Pink Sheet" monthly commodity prices — 71 commodities including Crude oil (Brent, Dubai, WTI), Natural gas (US/Europe/Japan LNG), Coal, Gold, Silver, Aluminum, Copper, Iron ore, Wheat, Rice, Palm oil, Sugar, Fertilizers (Urea, DAP, Phosphate) — from 1960 to present. Use for long-run commodity price history, Dubai crude benchmark, global reference benchmarks, or month-over-month commodity moves. Free, no auth.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# World Bank Pink Sheet (Monthly Commodity Prices)

The World Bank's "Pink Sheet" publishes monthly nominal-USD prices for **71 commodities** spanning energy, metals, agriculture, and fertilizers. Series go back to **January 1960**. Released around the **2nd business day of each month**.

**Why this is the right Dubai skill**: includes the **Crude oil, Dubai** benchmark column directly — the Middle East sour crude reference price. Most free sources skip this.

## Sandbox Environment

- **Python 3.12** stdlib (urllib, json, re, csv, datetime)
- **`openpyxl`** required — install with `uv pip install openpyxl` if not present
- Free public endpoint — no API key, no quota
- Cache at `/data/world-bank-cache/` (per-thread persistent)

## Quick start

```python
import os, sys, re, time, json, urllib.request
from pathlib import Path

CACHE = Path("/data/world-bank-cache")
LANDING = "https://www.worldbank.org/en/research/commodity-markets"
DOC_BASE = "https://thedocs.worldbank.org/en/doc"
FALLBACK_DOC_ID = "74e8be41ceb20fa0da750cda2f6b9e4e-0050012026"   # June 2026; update when stale

def _discover_doc_id() -> str:
    """Scrape landing page once/24h for current doc-id. Falls back to FALLBACK_DOC_ID."""
    CACHE.mkdir(parents=True, exist_ok=True)
    cf = CACHE / "current-docid.txt"
    if cf.exists() and cf.stat().st_mtime > time.time() - 86400:
        return cf.read_text().strip()
    try:
        req = urllib.request.Request(LANDING, headers={"User-Agent": "opencode-wb-client/1.0"})
        with urllib.request.urlopen(req, timeout=15) as r:
            html = r.read().decode("utf-8", errors="ignore")
        m = re.search(r"/doc/([a-f0-9]+-\d+)/related/CMO-Historical-Data-Monthly\.xlsx", html)
        if m:
            cf.write_text(m.group(1))
            return m.group(1)
    except Exception:
        pass
    return FALLBACK_DOC_ID

def _download_pink_sheet(period: str = "monthly") -> Path:
    """Download xlsx (monthly or annual). Cached by release month."""
    assert period in ("monthly", "annual")
    doc_id = _discover_doc_id()
    fname = "CMO-Historical-Data-Monthly.xlsx" if period == "monthly" else "CMO-Historical-Data-Annual.xlsx"
    key = time.strftime("%Y-%m")
    out = CACHE / f"{period}-{key}.xlsx"
    if out.exists() and out.stat().st_size > 50_000:
        return out
    url = f"{DOC_BASE}/{doc_id}/related/{fname}"
    req = urllib.request.Request(url, headers={"User-Agent": "opencode-wb-client/1.0"})
    with urllib.request.urlopen(req, timeout=45) as r:
        out.write_bytes(r.read())
    return out
```

## Tool 1: `list_commodities()` — discover what's available

```python
import openpyxl

def list_commodities() -> list[dict]:
    """Returns [{'idx': col_index, 'name': commodity, 'unit': unit}, ...] for all 71 series."""
    path = _download_pink_sheet("monthly")
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb["Monthly Prices"]
    names, units = [], []
    for i, row in enumerate(ws.iter_rows(min_row=5, max_row=6, values_only=True)):
        (names if i == 0 else units).extend(list(row))
    out = []
    for idx, (n, u) in enumerate(zip(names, units)):
        if n:
            out.append({"idx": idx, "name": str(n).strip(), "unit": (u or "").strip()})
    return out

# Example
for c in list_commodities()[:5]:
    print(c)
# {'idx': 1, 'name': 'Crude oil, average', 'unit': '($/bbl)'}
# {'idx': 2, 'name': 'Crude oil, Brent', 'unit': '($/bbl)'}
# {'idx': 3, 'name': 'Crude oil, Dubai', 'unit': '($/bbl)'}
# ...
```

## Tool 2: `get_prices()` — time series for selected commodities

```python
def get_prices(commodities: list[str] = None, start: str = None, end: str = None) -> list[dict]:
    """Returns [{'date': 'YYYY-MM', 'commodity': value, ...}, ...].
    commodities: substring matches against commodity names (case-insensitive).
                 e.g. ['Brent', 'Dubai', 'Gold'] matches "Crude oil, Brent", "Crude oil, Dubai", "Gold".
                 None = all 71 commodities.
    start, end: 'YYYY-MM' bounds (inclusive). None = no bound.
    """
    path = _download_pink_sheet("monthly")
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb["Monthly Prices"]
    # Header row 5 has names, row 6 has units
    rows_iter = ws.iter_rows(min_row=5, values_only=True)
    names = list(next(rows_iter))
    units = list(next(rows_iter))
    # Resolve which columns the user asked for
    if commodities:
        wanted = []
        for i, n in enumerate(names):
            if n and any(q.lower() in str(n).lower() for q in commodities):
                wanted.append((i, str(n).strip(), (units[i] or "").strip()))
    else:
        wanted = [(i, str(n).strip(), (units[i] or "").strip()) for i, n in enumerate(names) if n]
    out = []
    for row in rows_iter:
        d = row[0]
        if not d or not isinstance(d, str) or "M" not in d:
            continue
        date_iso = d.replace("M", "-")        # "1960M01" -> "1960-01"
        if start and date_iso < start: continue
        if end and date_iso > end: continue
        rec = {"date": date_iso}
        for idx, name, unit in wanted:
            v = row[idx]
            rec[name] = v if isinstance(v, (int, float)) else None
        out.append(rec)
    return out

# Example: Dubai crude + Brent for 2024
data = get_prices(["Brent", "Dubai"], start="2024-01", end="2024-12")
print(f"{len(data)} months")
for r in data:
    print(f"{r['date']}: Brent={r['Crude oil, Brent']:.2f}  Dubai={r['Crude oil, Dubai']:.2f}")
```

## Tool 3: `get_latest()` — current price for one or more commodities

```python
def get_latest(commodities: list[str] = None) -> dict:
    """Returns the most recent month's values. Same matching as get_prices."""
    all_rows = get_prices(commodities=commodities)
    return all_rows[-1] if all_rows else {}

# Example
print(get_latest(["Brent", "Dubai", "Gold"]))
# {'date': '2026-05', 'Crude oil, Brent': 107.54, 'Crude oil, Dubai': 94.67, 'Gold': 4587.21}
```

## Tool 4: `get_categories()` — group commodities by sector

```python
CATEGORIES = {
    "Energy": ["Crude oil", "Coal", "Natural gas", "Liquefied natural gas"],
    "Beverages": ["Cocoa", "Coffee", "Tea"],
    "Oils & Meals": ["Coconut oil", "Groundnut", "Palm oil", "Palm kernel oil", "Soybean", "Rapeseed oil", "Sunflower oil", "Fish meal"],
    "Grains": ["Barley", "Maize", "Sorghum", "Rice", "Wheat"],
    "Other Food": ["Banana", "Orange", "Beef", "Chicken", "Lamb", "Shrimps", "Sugar", "Tobacco"],
    "Raw Materials": ["Logs", "Sawnwood", "Plywood", "Cotton", "Rubber"],
    "Fertilizers": ["Phosphate", "DAP", "TSP", "Urea", "Potassium chloride"],
    "Metals": ["Aluminum", "Iron ore", "Copper", "Lead", "Tin", "Nickel", "Zinc"],
    "Precious Metals": ["Gold", "Platinum", "Silver"],
}

def get_categories() -> dict:
    """Returns {category: [commodity_names]}."""
    all_c = list_commodities()
    grouped = {k: [] for k in CATEGORIES}
    grouped["Uncategorized"] = []
    for c in all_c:
        placed = False
        for cat, prefixes in CATEGORIES.items():
            if any(c["name"].startswith(p) for p in prefixes):
                grouped[cat].append(c["name"])
                placed = True
                break
        if not placed:
            grouped["Uncategorized"].append(c["name"])
    return {k: v for k, v in grouped.items() if v}
```

## Dubai-relevant shortcuts

```python
def dubai_energy_basket(start: str = None, end: str = None) -> list[dict]:
    """Brent, Dubai crude, WTI, Henry Hub gas, EU gas, JKM LNG, Coal."""
    return get_prices(
        ["Brent", "Dubai", "WTI", "Natural gas, US", "Natural gas, Europe", "Liquefied natural gas, Japan", "Coal, Australian"],
        start=start, end=end,
    )

def uae_food_import_basket(start: str = None, end: str = None) -> list[dict]:
    """Staples UAE imports heavily: wheat, rice, palm oil, sugar, soybean oil, maize."""
    return get_prices(
        ["Wheat, US HRW", "Rice, Thai 5", "Palm oil", "Sugar, world", "Soybean oil", "Maize"],
        start=start, end=end,
    )

def dmcc_precious_metals(start: str = None, end: str = None) -> list[dict]:
    """Gold, Silver, Platinum — DMCC commodity hub relevance."""
    return get_prices(["Gold", "Silver", "Platinum"], start=start, end=end)
```

## Tool 5: `get_indices()` — monthly indices (2010=100)

```python
# Column-to-label map for the "Monthly Indices" sheet (verified against June 2026 release).
# Labels live across rows 6-9 in a staggered hierarchy; the layout has been stable for years.
_INDEX_COLS = {
    1: "Total Index", 2: "Energy", 3: "Non-energy",
    4: "Agriculture", 5: "Beverages", 6: "Food",
    7: "Oils & Meals", 8: "Grains", 9: "Other Food",
    10: "Raw Materials", 11: "Timber", 12: "Other Raw Materials",
    13: "Fertilizers", 14: "Metals & Minerals",
    15: "Base Metals (ex. iron ore)", 16: "Precious Metals",
}

def get_indices(start: str = None, end: str = None, indices: list[str] = None) -> list[dict]:
    """Returns monthly index series (2010=100). 16 indices: Total, Energy, Food, Grains, Metals, etc.
    indices: optional substring filter (case-insensitive). None = all 16.
    """
    path = _download_pink_sheet("monthly")
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb["Monthly Indices"]
    if indices:
        cols = {i: lab for i, lab in _INDEX_COLS.items()
                if any(q.lower() in lab.lower() for q in indices)}
    else:
        cols = _INDEX_COLS
    out = []
    for row in ws.iter_rows(min_row=10, values_only=True):
        d = row[0]
        if not d or not isinstance(d, str) or "M" not in d:
            continue
        date_iso = d.replace("M", "-")
        if start and date_iso < start: continue
        if end and date_iso > end: continue
        rec = {"date": date_iso}
        for i, lab in cols.items():
            v = row[i] if i < len(row) else None
            rec[lab] = v if isinstance(v, (int, float)) else None
        out.append(rec)
    return out

# Example
print(get_indices(start="2024-01", end="2024-03", indices=["Energy", "Food", "Total"]))
# [{'date': '2024-01', 'Total Index': ..., 'Energy': ..., 'Food': ...}, ...]
```

## Critical gotchas

1. **The Pink Sheet doc-id rotates monthly.** `_discover_doc_id` scrapes the landing page; if scraping fails, `FALLBACK_DOC_ID` kicks in. Update `FALLBACK_DOC_ID` periodically if the scrape breaks.
2. **`openpyxl` may not be pre-installed.** First run: `uv pip install openpyxl` (logs ~3s install once).
3. **Date format is `YYYYMmm`** (e.g. `1960M01`) — not ISO. The skill converts to `YYYY-MM` automatically.
4. **Early-period cells may be `'…'` (ellipsis string) for unavailable data**, not None. The skill filters non-numeric to None.
5. **Monthly Prices sheet** has commodity names in **row 5**, units in **row 6**, data from **row 7**. The Monthly Indices sheet is different — headers span rows 6-9.
6. **No daily data.** Pink Sheet is monthly only. For daily oil prices use a different source (FRED has WTI daily; EIA for spot prices).
7. **Updates around the 2nd of each month.** Latest month may not yet be available in the first day or two.

## Pattern: process data, return summaries

```python
# BAD — dumps 800 rows
data = get_prices(["Brent"])
print(data)

# GOOD — summarize
data = get_prices(["Brent"], start="2024-01")
closes = [r["Crude oil, Brent"] for r in data if r["Crude oil, Brent"] is not None]
print(f"Brent: {len(closes)} months, range ${min(closes):.2f}-${max(closes):.2f}, latest ${closes[-1]:.2f}")
```
