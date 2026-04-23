---
name: usaspending
description: Search federal grants, contracts, and SBIR awards from USASpending.gov. Use for VC R&D research — finding what companies are receiving federal funding, SBIR discovery by agency or sector, geo cluster analysis, company funding arcs, amendment timelines, and recipient entity resolution. No API key required.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# USASpending.gov API

Public API — no proxy, no API key. Call directly via HTTP.

## Base URL and Helpers

```python
import json
import urllib.request
import urllib.parse

BASE = "https://api.usaspending.gov"

def usa_post(path: str, body: dict) -> dict:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def usa_get(path: str) -> dict:
    with urllib.request.urlopen(f"{BASE}{path}", timeout=30) as r:
        return json.loads(r.read())
```

## Supported Tools

| Tool | Endpoint | What it returns |
| --- | --- | --- |
| `search_grants` | `POST /api/v2/search/spending_by_award/` | Grant award records — amount, recipient, CFDA program, description, dates |
| `search_contracts` | `POST /api/v2/search/spending_by_award/` | Contract award records — amount, recipient, awarding agency, description |
| `count_awards` | `POST /api/v2/search/spending_by_award_count/` | Count of grants/contracts matching filters before paging |
| `spending_trend` | `POST /api/v2/search/spending_over_time/` | Obligation totals by fiscal year/quarter — sector trends or per-company arc |
| `spending_by_state` | `POST /api/v2/search/spending_by_geography/` | Grant totals by state — identifies R&D geo clusters |
| `top_recipients` | `POST /api/v2/search/spending_by_category/recipient/` | Ranked recipients by total obligation for given filters |
| `top_programs` | `POST /api/v2/search/spending_by_category/cfda/` | Ranked CFDA programs by total obligation |
| `top_agencies` | `POST /api/v2/search/spending_by_category/awarding_agency/` | Ranked awarding agencies by total obligation |
| `amendment_timeline` | `POST /api/v2/search/spending_by_transaction/` | Per-transaction history — new awards vs modifications for a company |
| `resolve_recipient` | `POST /api/v2/recipient/` | Resolve company name → id, UEI, DUNS |
| `recipient_profile` | `GET /api/v2/recipient/<id>/` | Full profile — business types, address, parent entity |
| `award_detail` | `GET /api/v2/awards/<generated_internal_id>/` | Full award record — abstract, CFDA, period, location, funding |
| `find_cfda` | `POST /api/v2/autocomplete/cfda/` | Resolve program keyword → CFDA number and title |

## Examples

```python
import json, urllib.request, urllib.parse

BASE = "https://api.usaspending.gov"

def usa_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def usa_get(path):
    with urllib.request.urlopen(f"{BASE}{path}", timeout=30) as r:
        return json.loads(r.read())

GRANT_CODES = ["02", "03", "04", "05"]
CONTRACT_CODES = ["A", "B", "C", "D"]

GRANT_FIELDS = [
    "Award ID", "generated_internal_id", "Recipient Name",
    "Start Date", "End Date", "Award Amount",
    "Awarding Agency", "Awarding Sub Agency",
    "Award Type", "CFDA Number", "CFDA Title", "Description",
    "Last Modified Date",
]
CONTRACT_FIELDS = [
    "Award ID", "generated_internal_id", "Recipient Name",
    "Start Date", "End Date", "Award Amount",
    "Awarding Agency", "Awarding Sub Agency",
    "Award Type", "Description",
]

def search_grants(filters: dict, limit: int = 25, page: int = 1) -> dict:
    """Search federal grant awards. filters must NOT include contract type codes."""
    body = {
        "filters": {"award_type_codes": GRANT_CODES, **filters},
        "fields": GRANT_FIELDS,
        "sort": "Award Amount", "order": "desc",
        "limit": limit, "page": page,
    }
    return usa_post("/api/v2/search/spending_by_award/", body)

def search_contracts(filters: dict, limit: int = 25, page: int = 1) -> dict:
    """Search federal contract awards. Separate call from grants — type codes cannot mix."""
    body = {
        "filters": {"award_type_codes": CONTRACT_CODES, **filters},
        "fields": CONTRACT_FIELDS,
        "sort": "Award Amount", "order": "desc",
        "limit": limit, "page": page,
    }
    return usa_post("/api/v2/search/spending_by_award/", body)

def count_awards(filters: dict) -> dict:
    """Pre-check how many grants/contracts match before paging. Returns counts by type."""
    return usa_post("/api/v2/search/spending_by_award_count/", {"filters": filters})

def spending_trend(filters: dict, group: str = "fiscal_year") -> list:
    """Obligation totals over time. group: 'fiscal_year', 'quarter', or 'month'."""
    r = usa_post("/api/v2/search/spending_over_time/",
        {"filters": filters, "group": group, "subawards": False})
    return r.get("results", [])

def spending_by_state(filters: dict, scope: str = "recipient_location") -> list:
    """Grant totals by state. scope: 'recipient_location' or 'place_of_performance'."""
    r = usa_post("/api/v2/search/spending_by_geography/",
        {"filters": filters, "scope": scope, "geo_layer": "state"})
    return sorted(r.get("results", []), key=lambda x: x.get("aggregated_amount", 0), reverse=True)

def top_recipients(filters: dict, limit: int = 10) -> list:
    r = usa_post("/api/v2/search/spending_by_category/recipient/",
        {"filters": filters, "limit": limit, "page": 1})
    return r.get("results", [])

def top_programs(filters: dict, limit: int = 10) -> list:
    r = usa_post("/api/v2/search/spending_by_category/cfda/",
        {"filters": filters, "limit": limit, "page": 1})
    return r.get("results", [])

def top_agencies(filters: dict, limit: int = 10) -> list:
    r = usa_post("/api/v2/search/spending_by_category/awarding_agency/",
        {"filters": filters, "limit": limit, "page": 1})
    return r.get("results", [])

def amendment_timeline(filters: dict, limit: int = 25) -> list:
    """Transaction-level history. Action type B=new award, C=modification."""
    body = {
        "filters": filters,
        "fields": ["Action Date", "Action Type", "Award ID", "Mod",
                   "Transaction Amount", "Awarding Agency", "Awarding Sub Agency",
                   "Recipient Name", "cfda_number"],
        "sort": "Action Date", "order": "desc",
        "limit": limit, "page": 1,
    }
    return usa_post("/api/v2/search/spending_by_transaction/", body).get("results", [])

def resolve_recipient(keyword: str, award_type: str = "all", limit: int = 5) -> list:
    """Resolve company name → id/UEI/DUNS. award_type: 'grants','contracts','all'."""
    r = usa_post("/api/v2/recipient/", {"keyword": keyword, "award_type": award_type, "limit": limit})
    return r.get("results", [])

def recipient_profile(recipient_id: str) -> dict:
    """Full profile from resolve_recipient id. Returns business types, address, parent."""
    return usa_get(f"/api/v2/recipient/{urllib.parse.quote(recipient_id, safe='')}/")

def award_detail(generated_internal_id: str) -> dict:
    """Full award record. Use generated_internal_id field from search_grants results."""
    return usa_get(f"/api/v2/awards/{urllib.parse.quote(generated_internal_id, safe='')}/")

def find_cfda(search_text: str, limit: int = 8) -> list:
    """Resolve program keyword → CFDA number + title."""
    r = usa_post("/api/v2/autocomplete/cfda/", {"search_text": search_text, "limit": limit})
    return r.get("results", [])
```

### Company Federal Profile (grants + contracts)

```python
import json, urllib.request, urllib.parse

BASE = "https://api.usaspending.gov"
def usa_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

company = "Anduril Industries"
date_filter = {"time_period": [{"start_date": "2020-01-01", "end_date": "2026-01-01"}]}

# Grants and contracts must be separate calls — type codes cannot mix
grants = usa_post("/api/v2/search/spending_by_award/", {
    "filters": {"award_type_codes": ["02","03","04","05"],
                "recipient_search_text": [company], **date_filter},
    "fields": ["Award ID","generated_internal_id","Recipient Name","Award Amount",
               "Awarding Sub Agency","CFDA Number","CFDA Title","Description","Start Date","End Date"],
    "sort": "Award Amount", "order": "desc", "limit": 10, "page": 1,
})
contracts = usa_post("/api/v2/search/spending_by_award/", {
    "filters": {"award_type_codes": ["A","B","C","D"],
                "recipient_search_text": [company], **date_filter},
    "fields": ["Award ID","generated_internal_id","Recipient Name","Award Amount",
               "Awarding Sub Agency","Award Type","Description","Start Date","End Date"],
    "sort": "Award Amount", "order": "desc", "limit": 10, "page": 1,
})

print(f"Grants ({len(grants.get('results',[]))}):")
for r in grants.get("results", []):
    print(f"  ${r['Award Amount']:>12,.0f}  [{r.get('CFDA Number','')}] {r.get('CFDA Title','')[:40]}  {r.get('Awarding Sub Agency','')[:30]}")

print(f"\nContracts ({len(contracts.get('results',[]))}):")
for r in contracts.get("results", []):
    print(f"  ${r['Award Amount']:>12,.0f}  {r.get('Awarding Sub Agency','')[:40]}  {r.get('Description','')[:50]}")
```

### SBIR Discovery — Biotech Startups from NIH

```python
import json, urllib.request

BASE = "https://api.usaspending.gov"
def usa_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

# Count first
count = usa_post("/api/v2/search/spending_by_award_count/", {"filters": {
    "award_type_codes": ["04", "05"],
    "agencies": [{"type": "awarding", "tier": "subtier", "name": "National Institutes of Health"}],
    "recipient_type_names": ["small_business"],
    "time_period": [{"start_date": "2024-01-01", "end_date": "2026-01-01"}],
}})
print(f"Total NIH small business grants: {count['results']['grants']}")

# Then fetch
results = usa_post("/api/v2/search/spending_by_award/", {
    "filters": {
        "award_type_codes": ["04", "05"],
        "agencies": [{"type": "awarding", "tier": "subtier", "name": "National Institutes of Health"}],
        "recipient_type_names": ["small_business"],
        "time_period": [{"start_date": "2024-01-01", "end_date": "2026-04-01"}],
    },
    "fields": ["Award ID", "generated_internal_id", "Recipient Name", "Award Amount",
               "CFDA Number", "CFDA Title", "Description", "Start Date", "End Date"],
    "sort": "Award Amount", "order": "desc", "limit": 25, "page": 1,
})
for r in results.get("results", []):
    print(f"  ${r['Award Amount']:>10,.0f}  {r['Recipient Name'][:40]}  [{r.get('CFDA Number','')}]")
    print(f"    {r.get('Description','')[:80]}")
```

### Company Funding Arc + Entity Resolution

```python
import json, urllib.request, urllib.parse

BASE = "https://api.usaspending.gov"
def usa_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())
def usa_get(path):
    with urllib.request.urlopen(f"{BASE}{path}", timeout=30) as r:
        return json.loads(r.read())

company = "Cognition Therapeutics"

# Funding arc — full fiscal year history
trend = usa_post("/api/v2/search/spending_over_time/", {
    "filters": {"award_type_codes": ["02","03","04","05"],
                "recipient_search_text": [company]},
    "group": "fiscal_year", "subawards": False,
})
print("Funding arc:")
for row in trend.get("results", []):
    fy = row["time_period"].get("fiscal_year", "?")
    amt = row.get("aggregated_amount", 0)
    if amt:
        print(f"  FY{fy}  ${amt:>12,.0f}")

# Entity resolution → profile
matches = usa_post("/api/v2/recipient/", {"keyword": company, "award_type": "grants", "limit": 1})
if matches.get("results"):
    rec = matches["results"][0]
    print(f"\nUEI: {rec.get('uei')}  DUNS: {rec.get('duns')}")
    profile = usa_get(f"/api/v2/recipient/{urllib.parse.quote(rec['id'], safe='')}/")
    print(f"Business types: {profile.get('business_types')}")
    loc = profile.get("location", {})
    print(f"Address: {loc.get('address_line1')}, {loc.get('city_name')}, {loc.get('state_code')} {loc.get('zip5')}")
    print(f"Parent: {profile.get('parent_name') or 'None'}")
```

### Geo Cluster + Top Recipients

```python
import json, urllib.request

BASE = "https://api.usaspending.gov"
def usa_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

NIH = {"type": "awarding", "tier": "subtier", "name": "National Institutes of Health"}
filters = {
    "award_type_codes": ["04", "05"],
    "agencies": [NIH],
    "recipient_type_names": ["small_business"],
    "time_period": [{"start_date": "2024-01-01", "end_date": "2026-01-01"}],
}

geo = usa_post("/api/v2/search/spending_by_geography/",
    {"filters": filters, "scope": "recipient_location", "geo_layer": "state"})
states = sorted(geo.get("results", []), key=lambda x: x.get("aggregated_amount", 0), reverse=True)
print("NIH SBIR by state:")
for s in states[:8]:
    print(f"  {s.get('display_name',''):<20}  ${s.get('aggregated_amount', 0):>12,.0f}")

recipients = usa_post("/api/v2/search/spending_by_category/recipient/",
    {"filters": filters, "limit": 8, "page": 1})
print("\nTop recipients:")
for r in recipients.get("results", []):
    print(f"  ${r.get('amount', 0):>12,.0f}  {r.get('name','')[:50]}")
```

### Award Detail

```python
import json, urllib.request, urllib.parse

BASE = "https://api.usaspending.gov"
def usa_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())
def usa_get(path):
    with urllib.request.urlopen(f"{BASE}{path}", timeout=30) as r:
        return json.loads(r.read())

# Get generated_internal_id from a search first
results = usa_post("/api/v2/search/spending_by_award/", {
    "filters": {"award_type_codes": ["04","05"],
                "recipient_search_text": ["Cognition Therapeutics"]},
    "fields": ["Award ID", "generated_internal_id", "Recipient Name", "Award Amount"],
    "sort": "Award Amount", "order": "desc", "limit": 1, "page": 1,
})
if results.get("results"):
    gid = results["results"][0]["generated_internal_id"]
    d = usa_get(f"/api/v2/awards/{urllib.parse.quote(gid, safe='')}/")
    print(f"Recipient: {d['recipient']['recipient_name']}")
    print(f"Period: {d['period_of_performance']['start_date']} → {d['period_of_performance']['end_date']}")
    loc = d.get("place_of_performance", {})
    print(f"Place of performance: {loc.get('city_name')}, {loc.get('state_code')}")
    print(f"Description: {d.get('description','')[:300]}")
    for cfda in d.get("cfda_info", []):
        print(f"CFDA: {cfda.get('cfda_number')} — {cfda.get('cfda_title')}")
```

## Notes

- **Grant and contract type codes cannot mix in one request.** Use `search_grants` and `search_contracts` as separate calls.
- **`keyword` filter breaks with SBIR-only award codes** — combining `keyword` with `award_type_codes: ["04","05"]` returns HTTP 422. Use the broader grant codes `["02","03","04","05"]` when also filtering by keyword, then filter SBIR vs non-SBIR client-side via the `Award Type` field in results.
- **NAICS codes do not filter grants** — they only apply to contracts. Do not use `naics_codes` when `award_type_codes` contains grant codes.
- **No `total` in `page_metadata`** — only `hasNext`. Use `count_awards` as a pre-check before paging.
- **`award_detail` requires `generated_internal_id`** — request this field explicitly in `search_grants`; format is `ASST_NON_R01AG065248_075`. The numeric `Award ID` alone will 404.
- **`spending_trend` FY2026 data is unreliable** — includes partial-year deobligations. Treat current fiscal year with caution.
- **`subawards: True` returns corrupt amounts** — subaward transaction amounts can show $1T+ values, a known source data quality issue. Always use `subawards: False` (the default in `spending_trend`).
- **`recipient_type_names: ["small_business"]`** is noisy for NSF — includes nonprofits. Use agency subtier `"National Institutes of Health"` for cleaner SBIR signal.
- **Agency filter tiers:** `"toptier"` (e.g. `"National Science Foundation"`) or `"subtier"` (e.g. `"National Institutes of Health"`).
- **Response latency:** narrow queries 0.9–1.5s; broad queries 2–5s; `spending_by_geography` ~3s.
- **No rate limit documented** — avoid aggressive parallel calls.
