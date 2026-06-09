---
name: dubai-land
description: Query Dubai Land Department real-estate data — record-level sale transactions, Ejari rental contracts, valuations, brokers, developers, lands, buildings, and reference lookups (areas, property types). Reverse-engineered from the DLD public open-data backend (`gateway.dubailand.gov.ae`). No vendor keys required — the only credential is a `consumer-id` header that the skill auto-resolves from DLD's own public JS bundle. Use when users ask about Dubai property prices, recent sales, rental contracts, broker/developer registries, or area-level real estate metrics.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Dubai Land Department Open Data

Direct HTTP wrapper around the public DLD open-data backend powering `dubailand.gov.ae/en/open-data/real-estate-data/`. Auth model is a single `consumer-id` header — value is embedded in DLD's own public JS bundle and auto-resolved per session, so a rotation by DLD auto-heals on next call.

**Data tier:** sale transactions, rental contracts, valuations, broker registry, developer registry, lands, buildings, areas — record-level, free, no contractual data feed.

## Auth and helper

```python
import json, os, re, time, urllib.parse, urllib.request, urllib.error

_OPENDATA_PAGE = "https://dubailand.gov.ae/en/open-data/real-estate-data/"
_GATEWAY       = "https://gateway.dubailand.gov.ae"
_CACHE_DIR     = "/data/dubai-land"
_CACHE_FILE    = f"{_CACHE_DIR}/consumer-id.txt"

def _ua_headers():
    return {"User-Agent": "Mozilla/5.0 (compatible; AxionAgent/1.0)"}

def _open_with_retry(req, *, max_retries: int = 3, base_delay: float = 1.0, timeout: int = 30):
    """urlopen with retry on 429, 5xx, and network timeouts. Does NOT retry 401/403 —
    that's handled separately by the consumer-id refresh path."""
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            return urllib.request.urlopen(req, timeout=timeout).read().decode()
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (401, 403):
                raise  # leave to consumer-id refresh
            if e.code == 429 and attempt < max_retries:
                ra = e.headers.get("Retry-After") if e.headers else None
                try:
                    delay = float(ra) if ra else base_delay * (2 ** attempt)
                except ValueError:
                    delay = base_delay * (2 ** attempt)
                time.sleep(max(delay, 1.0)); continue
            if 500 <= e.code < 600 and attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt)); continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt)); continue
            raise
    raise last_err

def _fetch_consumer_id() -> str:
    """Scrape the live consumer-id from DLD's public open-data page. apiConfig is inlined as a JSON
    literal in window.apiConfig. Robust to rotation: every fresh call re-resolves."""
    req = urllib.request.Request(_OPENDATA_PAGE, headers=_ua_headers())
    html = _open_with_retry(req, timeout=20)
    m = re.search(r"window\.apiConfig\s*=\s*(\{.*?\});", html, re.DOTALL)
    if not m:
        raise RuntimeError("Could not locate window.apiConfig on DLD open-data page")
    cfg = json.loads(m.group(1))
    cid = cfg.get("consumerId")
    if not cid:
        raise RuntimeError("apiConfig did not contain consumerId")
    return cid

def get_consumer_id(force_refresh: bool = False) -> str:
    """Resolve and cache the consumer-id. Cached in /data/dubai-land/consumer-id.txt for the session."""
    if not force_refresh and os.path.exists(_CACHE_FILE):
        try:
            cid = open(_CACHE_FILE).read().strip()
            if cid: return cid
        except Exception:
            pass
    cid = _fetch_consumer_id()
    os.makedirs(_CACHE_DIR, exist_ok=True)
    with open(_CACHE_FILE, "w") as f:
        f.write(cid)
    return cid

def _dld_post(path: str, body: dict, retry_on_403: bool = True) -> dict:
    """POST to the DLD gateway with auto-resolved consumer-id.
    - 401/403 → refresh consumer-id once and retry (rotation auto-heal)
    - 429 / 5xx / timeouts → up to 3 retries with exponential backoff (via _open_with_retry)
    The two layers are independent so a stale id + a transient blip both recover."""
    cid = get_consumer_id()
    data = json.dumps(body).encode()
    headers = {**_ua_headers(), "Content-Type": "application/json", "consumer-id": cid}
    req = urllib.request.Request(f"{_GATEWAY}{path}", data=data, headers=headers, method="POST")
    try:
        return json.loads(_open_with_retry(req, timeout=30))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403) and retry_on_403:
            get_consumer_id(force_refresh=True)
            return _dld_post(path, body, retry_on_403=False)
        raise

def _dld_get(url: str) -> dict:
    """GET helper for endpoints that take query params (brokers, awards, area registry).
    The Umbraco surface endpoint at dubailand.gov.ae doesn't need consumer-id.
    Retries on 429/5xx/timeouts."""
    headers = _ua_headers()
    if "gateway.dubailand.gov.ae" in url:
        headers["consumer-id"] = get_consumer_id()
    req = urllib.request.Request(url, headers=headers)
    return json.loads(_open_with_retry(req, timeout=30))

def _fmt_date(d: str | None) -> str:
    """Convert ISO 'YYYY-MM-DD' or 'YYYY-MM' to DLD format 'MM/DD/YYYY'. Pass-through if already MM/DD/YYYY."""
    if not d: return ""
    if "/" in d: return d
    parts = d.split("-")
    if len(parts) == 3: return f"{parts[1]}/{parts[2]}/{parts[0]}"
    if len(parts) == 2: return f"{parts[1]}/01/{parts[0]}"
    return d
```

## Supported Tools

### Open-data commands (record-level)

| Function | Underlying command | What it returns |
| --- | --- | --- |
| `get_transactions` | `transactions` | Sale transactions — number, date, value, area, project, property type |
| `get_rents` | `rents` | Ejari rental contracts — registration, amount, area, property type |
| `get_valuations` | `valuations` | Official property valuations by area / property type |
| `get_lands` | `lands` | Land plot registry (261k+ records) |
| `get_buildings` | `buildings` | Building registry |
| `get_brokers_data` | `brokers` | Broker records via open-data backend (paginated, ~42k brokers) |
| `get_developers` | `developers` | Registered developers (~138 records) |
| `get_projects_data` | `projects` | Real estate projects (filter values required) |
| `get_units_data` | `units` | Unit registry (filter values required) |

### Reference lookups

| Function | What it returns |
| --- | --- |
| `list_areas` | All 437 areas (English + Arabic names + AREA_ID) |
| `list_property_types` | 83 Ejari property types |
| `list_projects_lookup` | Project ID/name registry |
| `get_area_registry_alt` | Alternate area registry via umbraco surface — different ID schema, no consumer-id needed |

### Aux endpoints

| Function | What it returns |
| --- | --- |
| `get_broker_registry` | Authoritative broker registry via `/brokers/` — full contact info |
| `get_broker_awards` | Broker awards by category and year |
| `get_indexes` | Residential Sale Index / Rental Yields via GraphQL (production data not yet populated — returns test seed as of 2026-06-09) |

## Functions

```python
import json, os, re, urllib.parse, urllib.request, urllib.error

# (auth helpers above)

# ---------- open-data record-level ----------

def get_transactions(date_from: str, date_to: str, area_id: str = "", usage_id: str = "",
                     property_type_id: str = "", is_offplan: str = "", is_freehold: str = "",
                     group_id: str = "", take: int = 50, skip: int = 0,
                     sort: str = "INSTANCE_DATE_DESC") -> dict:
    """Sale transactions. Dates accept 'YYYY-MM-DD' or 'MM/DD/YYYY'.
    Returns {total, rows, raw}. usage_id: residential/commercial filter. group_id: sales/mortgage type."""
    body = {
        "P_FROM_DATE": _fmt_date(date_from), "P_TO_DATE": _fmt_date(date_to),
        "P_GROUP_ID": group_id, "P_IS_OFFPLAN": is_offplan, "P_IS_FREE_HOLD": is_freehold,
        "P_AREA_ID": area_id, "P_USAGE_ID": usage_id, "P_PROP_TYPE_ID": property_type_id,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/transactions", body)
    rows = (r.get("response") or {}).get("result") or []
    total = rows[0].get("TOTAL") if rows else 0
    return {"total": total, "rows": rows, "raw": r}

def get_rents(date_from: str, date_to: str, area_id: str = "", usage_id: str = "",
              property_type_id: str = "", is_freehold: str = "", version: str = "",
              date_type: str = "", take: int = 50, skip: int = 0,
              sort: str = "REGISTRATION_DATE_DESC") -> dict:
    """Ejari rental contracts. Tight date ranges recommended (server times out on wide windows)."""
    body = {
        "P_FROM_DATE": _fmt_date(date_from), "P_TO_DATE": _fmt_date(date_to),
        "P_DATE_TYPE": date_type, "P_IS_FREE_HOLD": is_freehold, "P_VERSION": version,
        "P_AREA_ID": area_id, "P_USAGE_ID": usage_id, "P_PROP_TYPE_ID": property_type_id,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/rents", body)
    rows = (r.get("response") or {}).get("result") or []
    total = rows[0].get("TOTAL") if rows else 0
    return {"total": total, "rows": rows, "raw": r}

def get_valuations(date_from: str, date_to: str, area_id: str = "", property_type_id: str = "",
                   take: int = 50, skip: int = 0, sort: str = "INSTANCE_DATE_DESC") -> dict:
    body = {
        "P_FROM_DATE": _fmt_date(date_from), "P_TO_DATE": _fmt_date(date_to),
        "P_AREA_ID": area_id, "P_PROP_TYPE_ID": property_type_id,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/valuations", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

def get_lands(project: str = "", master_project: str = "", land_type_id: str = "",
              area_id: str = "", zone_id: str = "", is_freehold: str = "",
              prop_sub_type_id: str = "", take: int = 50, skip: int = 0,
              sort: str = "") -> dict:
    body = {
        "P_PROJECT": project, "P_MASTER_PROJECT": master_project, "P_LAND_TYPE_ID": land_type_id,
        "P_AREA_ID": area_id, "P_ZONE_ID": zone_id, "P_IS_FREE_HOLD": is_freehold,
        "P_PROP_SB_TYPE_ID": prop_sub_type_id, "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/lands", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

def get_buildings(date_from: str = "", date_to: str = "", area_id: str = "", zone_id: str = "",
                  is_freehold: str = "", is_leasehold: str = "", is_offplan: str = "",
                  take: int = 50, skip: int = 0, sort: str = "BUILDING_NAME_EN_ASC") -> dict:
    body = {
        "P_FROM_DATE": _fmt_date(date_from), "P_TO_DATE": _fmt_date(date_to),
        "P_IS_FREE_HOLD": is_freehold, "P_AREA_ID": area_id, "P_ZONE_ID": zone_id,
        "P_IS_LEASE_HOLD": is_leasehold, "P_IS_OFFPLAN": is_offplan,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/buildings", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

def get_brokers_data(gender: str = "", take: int = 50, skip: int = 0,
                     sort: str = "NAME_EN_ASC") -> dict:
    body = {"P_GENDER": gender, "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort}
    r = _dld_post("/open-data/brokers", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

def get_developers(date_from: str = "2000-01-01", date_to: str = "2030-12-31",
                   name: str = "", take: int = 50, skip: int = 0,
                   sort: str = "NAME_EN_ASC") -> dict:
    """Registered developers (~140 rows). The DLD developers endpoint requires
    a non-empty date window — empty `P_FROM_DATE` / `P_TO_DATE` silently return
    0 rows, and any narrow window (e.g. one month) also returns 0. The defaults
    here open the gate to cover the full registry; pass `name=` to filter by
    developer name."""
    body = {
        "P_FROM_DATE": _fmt_date(date_from), "P_TO_DATE": _fmt_date(date_to), "P_NAME": name,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/developers", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

def get_projects_data(date_from: str = "", date_to: str = "", date_type: str = "",
                      prj_type_id: str = "", prj_status: str = "", zone_id: str = "",
                      area_id: str = "", take: int = 50, skip: int = 0,
                      sort: str = "PROJECT_START_DATE_DESC") -> dict:
    """NOTE: empty filters frequently return 0 rows on this endpoint as of 2026-06-09.
    Try passing a specific area_id or prj_status to get results."""
    body = {
        "P_FROM_DATE": _fmt_date(date_from), "P_TO_DATE": _fmt_date(date_to),
        "P_DATE_TYPE": date_type, "P_PRJ_TYPE_ID": prj_type_id, "P_PRJ_STATUS": prj_status,
        "P_ZONE_ID": zone_id, "P_AREA_ID": area_id,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/projects", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

def get_units_data(area_id: str = "", zone_id: str = "", is_freehold: str = "",
                   is_leasehold: str = "", is_offplan: str = "",
                   take: int = 50, skip: int = 0, sort: str = "") -> dict:
    """NOTE: as of 2026-06-09 this endpoint returns 0 rows with empty filters and may
    500 with some area_id values. Filter shape needs further reverse-engineering."""
    body = {
        "P_AREA_ID": area_id, "P_ZONE_ID": zone_id, "P_IS_FREE_HOLD": is_freehold,
        "P_IS_LEASE_HOLD": is_leasehold, "P_IS_OFFPLAN": is_offplan,
        "P_TAKE": str(take), "P_SKIP": str(skip), "P_SORT": sort,
    }
    r = _dld_post("/open-data/units", body)
    rows = (r.get("response") or {}).get("result") or []
    return {"total": rows[0].get("TOTAL") if rows else 0, "rows": rows}

# ---------- reference lookups ----------

def list_areas() -> list[dict]:
    """437 Dubai areas with bilingual names + AREA_ID."""
    r = _dld_post("/open-data/carea-lookup", {})
    return (r.get("response") or {}).get("result") or []

def list_property_types() -> list[dict]:
    r = _dld_post("/open-data/ejari-property-types", {})
    return (r.get("response") or {}).get("result") or []

def list_projects_lookup() -> list[dict]:
    r = _dld_post("/open-data/projects-lookup", {})
    return (r.get("response") or {}).get("result") or []

def get_area_registry_alt() -> list[dict]:
    """Alternate area registry via umbraco surface controller — no consumer-id needed.
    Different ID schema from carea-lookup (numeric AreaID vs 'A-NNN' codes)."""
    r = _dld_get("https://dubailand.gov.ae/umbraco/surface/LandStatus/GetAreaList")
    return r.get("Result") or []

# ---------- aux endpoints ----------

def get_broker_registry(start_index: int = 0, max_rows: int = 50, name: str = "") -> list[dict]:
    """Authoritative broker registry — full contact info (card number, phone, expiry)."""
    params = {"startIndex": start_index, "maxRows": max_rows}
    if name:
        params["name"] = name
    url = f"{_GATEWAY}/brokers/?{urllib.parse.urlencode(params)}"
    r = _dld_get(url)
    return r.get("Response") or []

def get_broker_awards() -> list[dict]:
    """Broker awards by category and year (e.g. 'Oldest Active Broker, Expat Category')."""
    r = _dld_get(f"{_GATEWAY}/card/award")
    return r.get("Response") or []

def get_indexes(query: dict | None = None,
                fields: tuple = ("monthDate", "year", "quarter", "indexType",
                                 "priceIndex", "residentialRentalYield", "allRentalYield")) -> list[dict]:
    """GraphQL: Residential Sale Index, Speculation Indices, Rental Yields.
    NOTE (2026-06-09): production data not yet populated — returns test seed rows only.
    Schema is live so this stub will start returning real data the moment DLD populates the dataset.
    Uses _open_with_retry for 429/5xx/timeouts."""
    fields_str = " ".join(fields)
    query_lit = json.dumps(query or {})
    gql = f'{{ indexes(query: {query_lit}) {{ {fields_str} }} }}'
    body = {"query": gql}
    cid = get_consumer_id()
    headers = {**_ua_headers(), "Content-Type": "application/json", "consumer-id": cid}
    req = urllib.request.Request(f"{_GATEWAY}/indexes-api/", data=json.dumps(body).encode(),
                                 headers=headers, method="POST")
    resp = json.loads(_open_with_retry(req, timeout=20))
    return (resp.get("data") or {}).get("indexes") or []
```

## Examples

### Yesterday's sales transactions

```python
from datetime import date, timedelta
today = date.today().isoformat()
yesterday = (date.today() - timedelta(days=1)).isoformat()
r = get_transactions(yesterday, today, take=10)
print(f"Total sales in window: {r['total']}")
for t in r["rows"]:
    print(f"  {t['INSTANCE_DATE'][:10]}  AED {t['TRANS_VALUE']:>12,.0f}  "
          f"{t['AREA_EN'][:25]:<25}  {t.get('PROJECT_EN','') or '-'}")
```

### Top 10 areas by sale count this month

```python
from collections import Counter
r = get_transactions("2026-06-01", "2026-06-30", take=500)
counts = Counter(t["AREA_EN"] for t in r["rows"] if t.get("AREA_EN"))
for area, n in counts.most_common(10):
    print(f"  {area:<30} {n} sales")
```

### Rental contracts in a specific area

```python
areas = list_areas()
al_barsha = next(a for a in areas if a["NAME_EN"] == "Al Barsha")
r = get_rents("2026-06-01", "2026-06-08", area_id=al_barsha["AREA_ID"], take=20)
print(f"Al Barsha rentals last week: {r['total']}")
for c in r["rows"][:5]:
    print(f"  {c.get('REGISTRATION_DATE','')[:10]}  AED {c.get('AMOUNT',0):,.0f}/yr  {c.get('PROP_TYPE_EN','')}")
```

### Compute empirical rental price by property type for an area

```python
import statistics
r = get_rents("2026-01-01", "2026-06-08", area_id="A-292", take=1000)
by_type = {}
for c in r["rows"]:
    by_type.setdefault(c.get("PROP_TYPE_EN", "?"), []).append(c.get("AMOUNT", 0))
for t, vs in by_type.items():
    vs = [v for v in vs if v > 0]
    if vs:
        print(f"  {t:<20} n={len(vs):<5} median AED {statistics.median(vs):>10,.0f}  "
              f"p90 AED {statistics.quantiles(vs, n=10)[-1]:>10,.0f}")
```

### Broker registry search

```python
hits = get_broker_registry(start_index=0, max_rows=5, name="Mohamed")
for b in hits:
    print(f"  card={b['CardNumber']:<6} {b['CardHolderNameEn']:<35} expires {b['CardExpiryDate'][:10]}")
```

### Refresh consumer-id manually (if needed)

```python
new_cid = get_consumer_id(force_refresh=True)
print(f"Resolved consumer-id: {new_cid}")
```

## Notes

- **No vendor API key.** The single credential — `consumer-id` — is auto-resolved from `dubailand.gov.ae/en/open-data/real-estate-data/` (regex extract of `window.apiConfig`). Cached in `/data/dubai-land/consumer-id.txt`. On any 401/403, the helper force-refreshes once and retries — so a rotation by DLD auto-heals.
- **Date format:** internally `MM/DD/YYYY` (US-style); helpers accept ISO `YYYY-MM-DD` and convert.
- **`projects` and `units` quirk:** these endpoints return HTTP 200 with 0 rows when filters are empty, and `units` can 500 with some area_id values. Pass non-empty filters; quirk is documented in `plans/dubai_gov_data.md` and may be a server-side requirement we haven't fully reverse-engineered.
- **Date range vs. server stability:** `rents` and `transactions` over multi-month ranges can time out. Iterate week-by-week and aggregate client-side for long backfills.
- **Two area-id schemas exist:** `carea-lookup` returns `A-NNN` codes used by the open-data endpoints, while `LandStatus/GetAreaList` returns numeric `AreaID`s used by older property-status tooling. Don't mix them.
- **IndexesApi (`get_indexes`)** schema is live but production data is not yet populated (as of 2026-06-09). The stub will become useful immediately when DLD migrates real data — no code change needed. Schema fields: `priceIndex`, `speculationIndex*` (4 variants by property class), `residentialRentalYield`, `commercialRentalYield`, `allRentalYield`, time dimensions.
- **CSV/Excel/PDF export endpoints** exist at `{base}/{command}/export/{format}` (verified in DLD JS) — not wrapped here; add helpers when needed.
- **DLD API Gateway** (`api.dubailand.gov.ae`, AED 30k/yr/product) covers different products (EJARI lifecycle, Mollak service charges, Trakheesi). For most public-data analytics use cases, this skill is sufficient and avoids the paid-subscription path. See `plans/dubai_gov_data.md` for the full comparison.
- **Always summarize:** result rows are wide (40+ columns each). Print only the fields you need.
