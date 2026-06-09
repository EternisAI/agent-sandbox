---
name: faostat
description: Fetch FAO food and agriculture data via the JWT-authenticated FAOSTAT API. 77 domains covering 245 countries from 1961 — production, trade, prices, food balance, food security, consumer price indices. Use for UAE food imports (UAE imports ~85% of food), Dubai food inflation, global supply/demand of staples (wheat, rice, palm oil), or any country-vs-country agriculture comparison.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# FAOSTAT (UN Food & Agriculture Statistics)

The UN FAO's flagship dataset. Free, comprehensive, 77 data domains. Uses JWT auth via the new (2024+) developer portal.

**Why this matters for Dubai**: UAE imports an estimated **85% of its food** by value. FAOSTAT tells you (a) what UAE imports and from where, (b) how UAE food prices move, (c) global production trends in commodities UAE buys, (d) food security indicators for the region.

## Sandbox environment

- **Python 3.12** stdlib only (urllib, json, base64, time)
- **Env vars required** in `agent-sandbox/.env`:
  - `FAOSTAT_USERNAME` — your developer portal username
  - `FAOSTAT_PASSWORD` — your developer portal password
- **Token cache** at `/data/faostat-token.json` (per-thread persistent)
- **No installs needed**

## Auth flow (transparent to caller)

The skill handles all token lifecycle automatically:
1. First call → POST username+password to FAO login → returns AccessToken (60 min) + RefreshToken (~30 days)
2. Subsequent calls within 60 min → reuse cached AccessToken
3. After 60 min → use RefreshToken via Cognito → fresh AccessToken (no password)
4. After ~30 days → full re-login via env-var credentials

You never refresh anything by hand. Set env vars once.

```python
import os, json, time, base64, urllib.request, urllib.parse
from pathlib import Path

TOKEN_FILE = Path("/data/faostat-token.json")
LOGIN_URL = "https://faostatservices.fao.org/api/v1/auth/login"
COGNITO_URL = "https://cognito-idp.eu-west-1.amazonaws.com/"
COGNITO_CLIENT_ID = "2csltsigao85ivhp6ojp1aic7o"
API_BASE = "https://faostatservices.fao.org/api/v1/en"

def _decode_exp(jwt: str) -> int:
    payload_b64 = jwt.split(".")[1]
    payload_b64 += "=" * ((4 - len(payload_b64) % 4) % 4)
    return json.loads(base64.b64decode(payload_b64))["exp"]

UA = "Mozilla/5.0 (compatible; AxionAgent/1.0)"

def _login() -> dict:
    user = os.environ["FAOSTAT_USERNAME"]
    pw = os.environ["FAOSTAT_PASSWORD"]
    body = urllib.parse.urlencode({"username": user, "password": pw}).encode()
    req = urllib.request.Request(LOGIN_URL, data=body, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())["AuthenticationResult"]

def _refresh(refresh_token: str) -> dict:
    body = json.dumps({
        "AuthFlow": "REFRESH_TOKEN_AUTH",
        "ClientId": COGNITO_CLIENT_ID,
        "AuthParameters": {"REFRESH_TOKEN": refresh_token},
    }).encode()
    req = urllib.request.Request(COGNITO_URL, data=body, method="POST", headers={
        "Content-Type": "application/x-amz-json-1.1",
        "X-Amz-Target": "AWSCognitoIdentityProviderService.InitiateAuth",
        "User-Agent": UA,
    })
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())["AuthenticationResult"]

def get_access_token() -> str:
    """Returns a valid access token. Refreshes or re-logs in as needed."""
    now = int(time.time())
    state = {}
    if TOKEN_FILE.exists():
        try:
            state = json.loads(TOKEN_FILE.read_text())
        except Exception:
            state = {}
    # 1. Cached access token still valid? (5-min skew buffer)
    if state.get("access_token") and state.get("access_exp", 0) > now + 300:
        return state["access_token"]
    # 2. Refresh token still valid?
    if state.get("refresh_token") and state.get("refresh_exp", 0) > now + 300:
        try:
            ar = _refresh(state["refresh_token"])
            state["access_token"] = ar["AccessToken"]
            state["access_exp"] = _decode_exp(ar["AccessToken"])
            TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
            TOKEN_FILE.write_text(json.dumps(state))
            return state["access_token"]
        except Exception:
            pass  # fall through to full login
    # 3. Full login
    ar = _login()
    state = {
        "access_token": ar["AccessToken"],
        "access_exp": _decode_exp(ar["AccessToken"]),
        "refresh_token": ar["RefreshToken"],
        "refresh_exp": now + 30 * 86400,  # Cognito default 30-day refresh window
    }
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_FILE.write_text(json.dumps(state))
    return state["access_token"]
```

## Generic request helper

```python
def faostat_get(path: str, params: dict = None) -> dict:
    """GET an authenticated endpoint, returns parsed JSON."""
    token = get_access_token()
    params = params or {}
    qs = urllib.parse.urlencode(params)
    url = f"{API_BASE}/{path.lstrip('/')}" + (f"?{qs}" if qs else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())
```

## Pre-baked UAE constants

```python
UAE_AREA_CODE = "225"   # FAOSTAT internal code (not ISO/M49). Verified live.
UAE_ISO3 = "ARE"
UAE_M49 = "784"
```

## Tool 1: `list_domains()` — what's available

```python
def list_domains() -> list[dict]:
    """Returns all 77 FAOSTAT data domains with their codes, names, and last update date.

    Each record: {group_code, group_name, domain_code, domain_name, date_update, ...}
    Use domain_code as the {DOMAIN} arg in other tools.
    """
    return faostat_get("groupsanddomains").get("data", [])

# Example
for d in list_domains()[:5]:
    print(f"  {d['domain_code']:<8} {d['domain_name']:<50} (updated {d['date_update']})")
```

### Most important domains for Dubai

| Code | Domain | Why for Dubai |
|---|---|---|
| `CP` | Consumer Price Indices | UAE food inflation, general inflation |
| `PP` | Producer Prices | Origin-country prices of imports |
| `TM` | Detailed Trade Matrix | UAE imports broken down by partner + commodity |
| `TCL` | Crops and livestock products trade | Trade volumes for staples |
| `QCL` | Crops and Livestock Production | Global production of staples UAE imports |
| `FBS` | Food Balance Sheets | UAE supply/utilization per commodity |
| `FS` | Suite of Food Security Indicators | UAE caloric supply, import dependency ratios |
| `RFN` | Fertilizers by Nutrient | Fertilizer demand (UAE is large exporter of urea) |
| `QV` | Value of Agricultural Production | UAE agricultural sector size |
| `FO` | Forestry Trade Flows | Wood imports |

## Tool 2: `query_dataset()` — main data tool

**Critical:** FAOSTAT uses **different filter parameter names per domain**. The skill's `query_dataset` wraps this so callers always use the same friendly args.

```python
# Per-domain dimension param mapping. Verified live 2026-06-09 by probing
# /dimensions/{DOMAIN}. Most domains use 'area'/'item'/'element'/'year' (legacy aliases
# that still work). TM and a few others use dim-id prefixes; FS uses years3.
_DOMAIN_PARAMS = {
    # Standard: area, item, element, year
    "CP":  {"area": "area",          "year": "year",   "extra": {}},
    "PP":  {"area": "area",          "year": "year",   "extra": {}},
    "QCL": {"area": "area",          "year": "year",   "extra": {}},
    "QV":  {"area": "area",          "year": "year",   "extra": {}},
    "FBS": {"area": "area",          "year": "year",   "extra": {}},
    "RFN": {"area": "area",          "year": "year",   "extra": {}},
    # Trade Matrix — UAE is the reporter
    "TM":  {"area": "reporterarea",  "year": "years",  "extra": {"partner_param": "partnerarea"}},
    # Food security uses 3-year averages
    "FS":  {"area": "area",          "year": "years3", "extra": {}},
}

def query_dataset(domain: str, area: str = UAE_AREA_CODE, item: str = None,
                  element: str = None, year_range: tuple = None,
                  partner: str = None, limit: int = 1000) -> list[dict]:
    """Query a FAOSTAT data domain. area defaults to UAE (225).

    Args:
      domain: domain code (e.g. 'CP', 'TM', 'QCL').
      area: FAOSTAT area code. UAE = 225. For TM this means the reporter country.
      item: item code (e.g. '15' for Wheat). Use search_items() to discover.
      element: element code (e.g. '5610' = Import Quantity). FILTERED CLIENT-SIDE
               because the FAOSTAT URL param is broken (returns 0 rows when set).
      year_range: (start, end) inclusive. None = all years.
      partner: only for TM domain — filter by partner country code.
      limit: max URL rows (filtered subset will be smaller).
    """
    cfg = _DOMAIN_PARAMS.get(domain, {"area": "area", "year": "year", "extra": {}})
    params = {cfg["area"]: area, "limit": str(limit)}
    if item:    params["item"] = item
    if year_range:
        # FAOSTAT quirk: hyphen ranges silently return 0 rows. Enumerate years comma-separated.
        params[cfg["year"]] = ",".join(str(y) for y in range(year_range[0], year_range[1] + 1))
    if partner and domain == "TM":
        params["partnerarea"] = partner
    rows = faostat_get(f"data/{domain}", params).get("data", [])
    # Client-side element filter — work around broken URL param
    if element:
        wanted = set(element.split(","))
        rows = [r for r in rows if r.get("Element Code") in wanted]
    return rows

# Examples
# UAE Food CPI 2020-2024 monthly
rows = query_dataset("CP", area="225", item="23013", element="6125", year_range=(2020, 2024))

# UAE wheat imports (as reporter) 2022 — note this is SLOW (15-20s) due to TM size
rows = query_dataset("TM", area="225", item="15", element="5610", year_range=(2022, 2022))

# Global wheat production top-10 (UAE doesn't produce wheat — skip area)
rows = query_dataset("QCL", area="", item="15", element="5510", year_range=(2022, 2022))
```

**Performance**: TM and TCL (trade matrix) queries are **slow (10-25 seconds)** because the underlying dataset is large. Cache results in the calling agent when possible. CP/QCL/FS queries are sub-second.

## Tool 3: definition lookups — discover codes

```python
def list_areas(domain: str) -> list[dict]:
    """All areas (countries+regions) available in a domain."""
    return faostat_get(f"definitions/domain/{domain}/area").get("data", [])

def list_items(domain: str) -> list[dict]:
    """All items (commodities) available in a domain."""
    return faostat_get(f"definitions/domain/{domain}/item").get("data", [])

def list_elements(domain: str) -> list[dict]:
    """All elements (measurements like 'Export Quantity', 'Value') in a domain."""
    return faostat_get(f"definitions/domain/{domain}/element").get("data", [])

def search_items(domain: str, query: str) -> list[dict]:
    """Find item codes by keyword (case-insensitive substring match on label)."""
    q = query.lower()
    return [i for i in list_items(domain) if q in (i.get("Item") or "").lower()]

def search_areas(domain: str, query: str) -> list[dict]:
    """Find area codes by keyword."""
    q = query.lower()
    return [a for a in list_areas(domain) if q in (a.get("Country") or "").lower()]

# Example
print(search_items("TM", "wheat"))   # find item codes for wheat in trade matrix
print(search_areas("TM", "india"))   # India as a partner
```

## Dubai-relevant shortcuts

```python
# UAE food inflation (Consumer Price Indices)
def uae_food_cpi(year_start: int = 2018, year_end: int = 2026) -> list[dict]:
    """UAE Food CPI (2015=100) annual values."""
    return query_dataset("CP", area="225",
        item="23013",            # Consumer Prices, Food Indices (2015=100)
        element="6125",          # Value
        year_range=(year_start, year_end),
        limit=500)

def uae_general_cpi(year_start: int = 2018, year_end: int = 2026) -> list[dict]:
    """UAE General CPI (2015=100) annual values."""
    return query_dataset("CP", area="225",
        item="23012",            # Consumer Prices, General Indices
        element="6125",
        year_range=(year_start, year_end),
        limit=500)

def uae_food_inflation_rate(year_start: int = 2018, year_end: int = 2026) -> list[dict]:
    """UAE food price inflation (% change)."""
    return query_dataset("CP", area="225",
        item="23014",            # Food price inflation
        year_range=(year_start, year_end),
        limit=500)

# UAE food imports — trade matrix (SLOW: 15-25 sec due to dataset size)
def uae_imports(item_code: str, year_start: int = 2022, year_end: int = 2022) -> list[dict]:
    """UAE imports of a specific commodity, by partner country.
    item_code: find with search_items('TM', 'wheat') etc. Wheat = "15".
    Default to a single year to keep response time manageable.
    Returns rows with partner country and quantity/value.
    """
    return query_dataset("TM", area="225",
        item=item_code,
        element="5610",          # Import Quantity (use 5622 for value)
        year_range=(year_start, year_end),
        limit=2000)

# UAE food security indicators
def uae_food_security(year_start: int = 2018, year_end: int = 2024) -> list[dict]:
    """UAE food security suite — caloric supply, import dependency, severity of food insecurity."""
    return query_dataset("FS", area="225",
        year_range=(year_start, year_end),
        limit=1000)

# Global production of staples UAE imports heavily
def global_staple_production(item_code: str, year_start: int = 2018, year_end: int = 2023,
                             top_n: int = 10) -> list[dict]:
    """Top producing countries of a staple. item_code from search_items('QCL', 'wheat').
    Returns rows for ALL producing countries; sort by Value descending and slice top_n in caller.
    Uses area="" (no area filter) to get every country, not area=5000 which would be
    only the World aggregate (3 rows).
    """
    return query_dataset("QCL",
        area="",                 # empty = no area filter = all countries
        item=item_code,
        element="5510",          # Production quantity
        year_range=(year_start, year_end),
        limit=1000)

def global_total_production(item_code: str, year_start: int = 2018, year_end: int = 2023) -> list[dict]:
    """World-aggregate production (single row per year). For totals/trends.
    Uses FAOSTAT's special "World" area code 5000."""
    return query_dataset("QCL",
        area="5000",             # World aggregate (verified)
        item=item_code,
        element="5510",
        year_range=(year_start, year_end),
        limit=200)
```

## Critical gotchas

1. **Area code 225 = UAE (FAOSTAT internal)** — NOT the ISO 784 or M49 784. FAOSTAT has its own numbering. Use `list_areas(domain)` to verify other countries' codes.
2. **The `element` URL parameter is broken on FAOSTAT — it silently returns 0 rows when set**, even with valid element codes. The skill filters element client-side; pass `element="5610"` to `query_dataset` and the wrapper does the right thing.
3. **TM uses `reporterarea` + `partnerarea`**, not `area`. The skill maps this automatically via `_DOMAIN_PARAMS`.
4. **TM queries are SLOW** — 15-25 seconds because the bilateral trade matrix is huge. Filter by item + year before calling.
5. **FS domain uses `years3`** (3-year averages) instead of `years`. The skill maps this automatically.
6. **Year range syntax**: FAOSTAT wants **comma-separated explicit years** (e.g. `year=2020,2021,2022,2023`). Hyphen ranges silently return 0 rows. The skill enumerates years automatically when you pass `year_range=(start, end)`.
7. **Element codes vary by domain.** Common ones:
   - CP: `6125` = Value
   - QCL: `5510` = Production, `5312` = Area harvested, `5412` = Yield
   - TM: `5610` = Import Quantity, `5622` = Import Value, `5910` = Export Quantity
   - PP: `5532` = Producer Price (USD/tonne)
8. **Token cache at `/data/faostat-token.json`** — per-thread persistent. Each new thread cold-starts (~200ms login).
9. **Use the new portal** — `faostatservices.fao.org`. The legacy `fenixservices.fao.org` is dead (Cloudflare 521).
10. **No bulk via API.** For full dataset dumps: `https://bulks-faostat.fao.org/production/{DATASET}_E_All_Data_(Normalized).zip` (no auth).

## Pattern: process in Python, return summary

```python
# BAD — dumps all import rows (hundreds for a single commodity)
print(uae_imports("15", 2018, 2023))  # Wheat = item 15

# GOOD — summarize
rows = uae_imports("15", 2022, 2022)
by_partner = {}
for r in rows:
    if r.get("Element") == "Import Quantity":
        p = r.get("Reporter Countries") or r.get("Partner Countries") or "?"
        by_partner[p] = by_partner.get(p, 0) + float(r.get("Value") or 0)
top5 = sorted(by_partner.items(), key=lambda x: -x[1])[:5]
print(f"UAE wheat imports 2022, top 5 partners: {top5}")
```

## Token cache inspection (debug only)

```python
import json
from pathlib import Path
state = json.loads(Path("/data/faostat-token.json").read_text())
print({
    "access_token_chars": len(state.get("access_token","")),
    "access_expires_in_min": (state["access_exp"] - int(time.time())) // 60,
    "refresh_token_chars": len(state.get("refresh_token","")),
    "refresh_expires_in_days": (state["refresh_exp"] - int(time.time())) // 86400,
})
```
