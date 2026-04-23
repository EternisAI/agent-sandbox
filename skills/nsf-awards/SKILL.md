---
name: nsf-awards
description: Search NSF grant awards via the NSF Awards API. Use for VC R&D research — finding deeptech and AI/ML startups funded by NSF SBIR, topic-based deal sourcing, PI background checks, geo cluster analysis, expiring Phase II grants, and new award deal flow. Covers AI/ML, hardware, quantum, advanced materials, robotics, climate tech, and other non-health R&D that NIH does not fund. No API key required.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# NSF Awards API

Public API — no proxy, no API key. Call directly via HTTP GET.

## Base URL and Helper

```python
import json
import urllib.request
import urllib.parse

BASE = "https://api.nsf.gov/services/v1"

FIELDS = (
    "id,title,awardeeName,awardeeCity,awardeeStateCode,"
    "piFirstName,piLastName,pdPIName,coPDPI,"
    "startDate,expDate,estimatedTotalAmt,fundsObligatedAmt,"
    "fundProgramName,dirAbbr,orgLongName,orgLongName2,"
    "abstractText,program,transType,ueiNumber,activeAwd"
)

def nsf_get(params: dict) -> dict:
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(
        f"{BASE}/awards.json?{qs}",
        headers={"User-Agent": "curl/7.88.1"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def nsf_award(award_id: str) -> dict:
    req = urllib.request.Request(
        f"{BASE}/awards/{award_id}.json",
        headers={"User-Agent": "curl/7.88.1"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())
```

## Supported Tools

| Tool | What it returns |
| --- | --- |
| `search_sbir` | NSF SBIR/STTR awards by phase, keyword, state, amount range, active status |
| `search_by_company` | All NSF awards for a named company — full funding history with abstracts |
| `search_by_topic` | Keyword search across all NSF award types — broader than SBIR only |
| `search_by_pi` | All NSF awards for a named PI — founder background and research history |
| `expiring_awards` | SBIR grants with expiry dates in a given window — warm sourcing list |
| `new_awards` | SBIR grants that started within a date range — fresh deal flow cohort |
| `get_award` | Full award detail by ID |
| `get_project_outcomes` | PI's public outcomes report for a completed grant — what they actually built |

## Functions

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"

FIELDS = (
    "id,title,awardeeName,awardeeCity,awardeeStateCode,"
    "piFirstName,piLastName,pdPIName,coPDPI,"
    "startDate,expDate,estimatedTotalAmt,fundsObligatedAmt,"
    "fundProgramName,dirAbbr,orgLongName,orgLongName2,"
    "abstractText,program,transType,ueiNumber,activeAwd"
)

def nsf_get(params: dict) -> dict:
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(
        f"{BASE}/awards.json?{qs}",
        headers={"User-Agent": "curl/7.88.1"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def nsf_award(award_id: str) -> dict:
    req = urllib.request.Request(
        f"{BASE}/awards/{award_id}.json",
        headers={"User-Agent": "curl/7.88.1"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def search_sbir(phase: int = None, keyword: str = None, state: str = None,
                date_start: str = None, date_end: str = None,
                active_only: bool = False, min_amount: int = None,
                max_amount: int = None, limit: int = 25) -> list:
    """
    NSF SBIR/STTR deal sourcing.
    phase: 1 → 'SBIR Phase I', 2 → 'SBIR Phase II', None → both.
    keyword: free text, supports AND/OR/NOT and quoted phrases.
    state: 2-letter code e.g. 'CA'.
    date_start/date_end: award date range, format 'mm/dd/yyyy'.
    active_only: True to filter to currently active awards only.
    min_amount/max_amount: filter by estimatedTotalAmt in dollars.
    """
    program_map = {1: "SBIR Phase I", 2: "SBIR Phase II"}
    params: dict = {"printFields": FIELDS, "rpp": min(limit, 250), "offset": 1}
    params["fundProgramName"] = program_map.get(phase, "SBIR")
    if keyword:
        params["keyword"] = keyword
    if state:
        params["awardeeStateCode"] = state
    if date_start:
        params["dateStart"] = date_start
    if date_end:
        params["dateEnd"] = date_end
    if active_only:
        params["ActiveAwards"] = "true"
    if min_amount is not None:
        params["estimatedTotalAmtFrom"] = min_amount
    if max_amount is not None:
        params["estimatedTotalAmtTo"] = max_amount
    r = nsf_get(params)
    return r.get("response", {}).get("award", [])

def search_by_company(name: str, sbir_only: bool = True, limit: int = 25) -> list:
    """
    All NSF awards for a named company. Uses keyword search — more reliable than awardeeName.
    Results may include non-exact matches; filter client-side by awardeeName if needed.
    sbir_only=True restricts to SBIR/STTR programs. Set False for all NSF award types.
    """
    params: dict = {"keyword": name, "printFields": FIELDS, "rpp": min(limit, 250), "offset": 1}
    if sbir_only:
        params["fundProgramName"] = "SBIR"
    r = nsf_get(params)
    awards = r.get("response", {}).get("award", [])
    # Filter to likely matches — name appears in awardeeName or title
    name_lower = name.lower()
    filtered = [a for a in awards if name_lower in (a.get("awardeeName") or "").lower()
                or name_lower in (a.get("title") or "").lower()]
    return filtered if filtered else awards  # fall back to raw results if no strong match

def search_by_topic(keyword: str, phase: int = None, state: str = None,
                    date_start: str = None, limit: int = 25) -> list:
    """
    Keyword search across NSF awards. Broader than search_sbir — covers all grant types.
    Use phase=1 or phase=2 to restrict to SBIR. keyword supports AND/OR/NOT operators.
    date_start format: 'mm/dd/yyyy'.
    """
    program_map = {1: "SBIR Phase I", 2: "SBIR Phase II"}
    params: dict = {"keyword": keyword, "printFields": FIELDS, "rpp": min(limit, 250), "offset": 1}
    if phase:
        params["fundProgramName"] = program_map[phase]
    if state:
        params["awardeeStateCode"] = state
    if date_start:
        params["dateStart"] = date_start
    r = nsf_get(params)
    return r.get("response", {}).get("award", [])

def search_by_pi(last_name: str, first_name: str = None, limit: int = 10) -> list:
    """All NSF awards for a named PI. last_name is required; first_name narrows results."""
    params: dict = {"piLastName": last_name, "printFields": FIELDS,
                    "rpp": min(limit, 250), "offset": 1}
    if first_name:
        params["piFirstName"] = first_name
    r = nsf_get(params)
    return r.get("response", {}).get("award", [])

def expiring_awards(from_date: str, to_date: str, phase: int = None,
                    state: str = None, min_amount: int = None, limit: int = 25) -> list:
    """
    SBIR grants expiring within the given window — companies likely raising next round.
    Dates: 'mm/dd/yyyy'. phase: 1 or 2. Results sorted by expiry date ascending.
    """
    program_map = {1: "SBIR Phase I", 2: "SBIR Phase II"}
    params: dict = {
        "expDateStart": from_date, "expDateEnd": to_date,
        "fundProgramName": program_map.get(phase, "SBIR"),
        "printFields": FIELDS, "rpp": min(limit, 250), "offset": 1,
        "sortKey": "startDate",
    }
    if state:
        params["awardeeStateCode"] = state
    if min_amount is not None:
        params["estimatedTotalAmtFrom"] = min_amount
    r = nsf_get(params)
    return r.get("response", {}).get("award", [])

def new_awards(from_date: str, to_date: str, phase: int = None,
               state: str = None, keyword: str = None, limit: int = 25) -> list:
    """
    SBIR grants that started within a date range — fresh deal flow.
    Dates: 'mm/dd/yyyy'. Much fresher than NIH Reporter — NSF data lags only ~2-4 weeks.
    """
    program_map = {1: "SBIR Phase I", 2: "SBIR Phase II"}
    params: dict = {
        "startDateStart": from_date, "startDateEnd": to_date,
        "fundProgramName": program_map.get(phase, "SBIR"),
        "printFields": FIELDS, "rpp": min(limit, 250), "offset": 1,
        "sortKey": "startDate",
    }
    if state:
        params["awardeeStateCode"] = state
    if keyword:
        params["keyword"] = keyword
    r = nsf_get(params)
    return r.get("response", {}).get("award", [])

def get_award(award_id: str) -> dict:
    """Full award record by NSF award ID."""
    r = nsf_award(award_id)
    return r.get("response", {}).get("award", [{}])[0]

def get_project_outcomes(award_id: str) -> str:
    """
    PI's public outcomes report for a completed grant — what they actually built.
    Only populated after the grant expires and the PI submits their report.
    Use before a Phase II meeting to validate Phase I delivery. Returns the outcomes text.
    """
    req = urllib.request.Request(
        f"{BASE}/awards/{award_id}/projectoutcomes.json",
        headers={"User-Agent": "curl/7.88.1"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    awards = data.get("response", {}).get("award", [])
    return awards[0].get("abstractText", "") if awards else ""
```

## Examples

### SBIR Deal Sourcing — AI/ML Phase II Active Awards

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"
FIELDS = "id,title,awardeeName,awardeeCity,awardeeStateCode,piFirstName,piLastName,startDate,expDate,estimatedTotalAmt,fundProgramName,dirAbbr,abstractText,ueiNumber,activeAwd"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

awards = nsf_get({
    "fundProgramName": "SBIR Phase II",
    "keyword": "artificial intelligence",
    "ActiveAwards": "true",
    "estimatedTotalAmtFrom": 750000,
    "printFields": FIELDS,
    "rpp": 20, "offset": 1,
}).get("response", {}).get("award", [])

print(f"Active NSF SBIR Phase II AI awards >$750K: {len(awards)}")
for a in awards:
    print(f"  ${int(a.get('estimatedTotalAmt',0)):>10,}  [{a.get('dirAbbr','')}]  {a.get('awardeeName','')[:40]}  {a.get('awardeeCity','')}, {a.get('awardeeStateCode','')}")
    print(f"    PI: {a.get('piFirstName','')} {a.get('piLastName','')}  |  {a.get('title','')[:65]}")
    print(f"    {a.get('abstractText','')[:150]}")
```

### Geo Cluster Analysis — NSF SBIR by State

```python
import json, urllib.request, urllib.parse
from collections import defaultdict

BASE = "https://api.nsf.gov/services/v1"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

# Pull large batch of recent SBIR awards and aggregate by state
awards = nsf_get({
    "fundProgramName": "SBIR", "dateStart": "01/01/2023",
    "printFields": "id,awardeeName,awardeeStateCode,estimatedTotalAmt,fundProgramName",
    "rpp": 250, "offset": 1,
}).get("response", {}).get("award", [])

by_state: dict = defaultdict(lambda: {"count": 0, "total": 0})
for a in awards:
    st = a.get("awardeeStateCode", "??")
    by_state[st]["count"] += 1
    by_state[st]["total"] += int(a.get("estimatedTotalAmt", 0))

print("NSF SBIR by state (sample batch):")
for st, d in sorted(by_state.items(), key=lambda x: x[1]["total"], reverse=True)[:12]:
    print(f"  {st}  ${d['total']:>12,}  ({d['count']} awards)")
```

### Topic Search — Quantum Computing Startups

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"
FIELDS = "id,title,awardeeName,awardeeCity,awardeeStateCode,piFirstName,piLastName,startDate,expDate,estimatedTotalAmt,fundProgramName,abstractText"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

awards = nsf_get({
    "keyword": "quantum computing",
    "fundProgramName": "SBIR",
    "dateStart": "01/01/2023",
    "printFields": FIELDS,
    "rpp": 25, "offset": 1,
}).get("response", {}).get("award", [])

print(f"NSF SBIR quantum computing grants: {len(awards)}")
for a in awards:
    print(f"  ${int(a.get('estimatedTotalAmt',0)):>10,}  [{a.get('fundProgramName','')[:15]}]  {a.get('awardeeName','')[:40]}  {a.get('awardeeStateCode','')}")
    print(f"    {a.get('title','')[:70]}")
    print(f"    {a.get('abstractText','')[:120]}")
```

### Expiring Phase II — Warm Sourcing List

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"
FIELDS = "id,title,awardeeName,awardeeCity,awardeeStateCode,piFirstName,piLastName,startDate,expDate,estimatedTotalAmt,abstractText,ueiNumber"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

# Phase II companies expiring in next 9 months — likely raising Series A
awards = nsf_get({
    "fundProgramName": "SBIR Phase II",
    "expDateStart": "04/23/2026", "expDateEnd": "01/31/2027",
    "estimatedTotalAmtFrom": 750000,
    "printFields": FIELDS,
    "rpp": 50, "offset": 1, "sortKey": "startDate",
}).get("response", {}).get("award", [])

print(f"NSF Phase II expiring by Jan 2027: {len(awards)}")
for a in awards:
    print(f"  exp {a.get('expDate','')}  ${int(a.get('estimatedTotalAmt',0)):>10,}  {a.get('awardeeName','')[:40]}  {a.get('awardeeCity','')}, {a.get('awardeeStateCode','')}")
    print(f"    PI: {a.get('piFirstName','')} {a.get('piLastName','')}  |  {a.get('title','')[:65]}")
```

### New Awards — Fresh Deal Flow

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"
FIELDS = "id,title,awardeeName,awardeeCity,awardeeStateCode,piFirstName,piLastName,startDate,expDate,estimatedTotalAmt,fundProgramName,dirAbbr,abstractText"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

# Awards that started in the last 3 months — NSF lags only ~2-4 weeks vs NIH's 6 months
awards = nsf_get({
    "fundProgramName": "SBIR",
    "startDateStart": "10/01/2025", "startDateEnd": "04/23/2026",
    "printFields": FIELDS,
    "rpp": 50, "offset": 1, "sortKey": "startDate",
}).get("response", {}).get("award", [])

print(f"New NSF SBIR awards Oct 2025 - Apr 2026: {len(awards)}")
for a in awards:
    print(f"  started {a.get('startDate','')}  [{a.get('fundProgramName','')[:15]}]  ${int(a.get('estimatedTotalAmt',0)):>8,}  {a.get('awardeeName','')[:40]}  {a.get('awardeeStateCode','')}")
    print(f"    {a.get('title','')[:70]}")
```

### Company Due Diligence — Tangible Robotics

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"
FIELDS = "id,title,awardeeName,awardeeCity,awardeeStateCode,piFirstName,piLastName,startDate,expDate,estimatedTotalAmt,fundProgramName,dirAbbr,abstractText,ueiNumber,activeAwd"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

name = "Tangible Robotics"
awards = nsf_get({
    "keyword": name, "fundProgramName": "SBIR",
    "printFields": FIELDS, "rpp": 25, "offset": 1,
}).get("response", {}).get("award", [])

# Filter to strong matches
name_lower = name.lower()
awards = [a for a in awards if name_lower in (a.get("awardeeName") or "").lower()] or awards

print(f"NSF SBIR awards for {name}: {len(awards)}")
for a in awards:
    status = "ACTIVE" if a.get("activeAwd") else "expired"
    print(f"  [{status}]  ${int(a.get('estimatedTotalAmt',0)):>10,}  [{a.get('fundProgramName','')[:15]}]  {a.get('startDate','')} → {a.get('expDate','')}")
    print(f"    PI: {a.get('piFirstName','')} {a.get('piLastName','')}  |  {a.get('title','')[:65]}")
    print(f"    {a.get('abstractText','')[:180]}")
```

### Phase I Outcomes Validation — Before a Phase II Meeting

```python
import json, urllib.request, urllib.parse

BASE = "https://api.nsf.gov/services/v1"

def nsf_get(params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE}/awards.json?{qs}", headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def get_project_outcomes(award_id):
    req = urllib.request.Request(
        f"{BASE}/awards/{award_id}/projectoutcomes.json",
        headers={"User-Agent": "curl/7.88.1"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    awards = data.get("response", {}).get("award", [])
    return awards[0].get("abstractText", "") if awards else ""

# Find a company's completed Phase I, then pull what they actually delivered
name = "Cache DNA"
awards = nsf_get({
    "keyword": name, "fundProgramName": "SBIR Phase I",
    "ExpiredAwards": "true",
    "printFields": "id,title,awardeeName,startDate,expDate,estimatedTotalAmt",
    "rpp": 5, "offset": 1,
}).get("response", {}).get("award", [])

name_lower = name.lower()
awards = [a for a in awards if name_lower in (a.get("awardeeName") or "").lower()] or awards

for a in awards:
    print(f"Award [{a['id']}]: {a.get('title','')[:65]}")
    print(f"  {a.get('awardeeName','')}  {a.get('startDate','')} → {a.get('expDate','')}")
    outcomes = get_project_outcomes(a["id"])
    if outcomes:
        print(f"  Outcomes: {outcomes[:400]}")
    else:
        print(f"  Outcomes: not yet submitted")
```

## Notes

- **No API key, no auth** — open public GET API, no headers required beyond User-Agent.
- **Date format is `mm/dd/yyyy`** — different from NIH Reporter's `YYYY-MM-DD`. Wrong format silently returns 0 results.
- **No `totalCount` in responses** — the API does not return a total record count. Hard cap is 3,000 results per search; refine filters if you need more.
- **`rpp` max is ~250** — documentation says 25 but values up to 250 are accepted. Higher values increase latency significantly (rpp=250 takes ~8s).
- **`awardeeName` search is unreliable** — uses substring matching and returns noisy results (e.g., "Shield AI" returns "SaferDrive AI LLC"). Use `search_by_company` which uses `keyword` and post-filters client-side instead.
- **`search_by_company` post-filters results** — keyword search is fuzzy; the function filters results where the company name appears in `awardeeName` or `title`, then falls back to raw results if nothing matches. Always verify `awardeeName` in the returned records.
- **`get_project_outcomes` only has data for completed grants** — returns empty string if the PI hasn't submitted their outcomes report yet (typically due 90 days after expiry). Most useful for Phase I grants that expired 6+ months ago.
- **NSF SBIR `fundProgramName` values:** `"SBIR Phase I"`, `"SBIR Phase II"`, `"STTR Phase I"`, `"STTR Phase II"`. Use `"SBIR"` to match both phases. Do not use just `"SBIR Phase"` — it won't match.
- **NSF directorate abbreviations (`dirAbbr`):** TIP (Technology, Innovation & Partnerships — SBIR home), CSE (Computing/AI/cybersecurity), ENG (Engineering), MPS (Math & Physical Sciences), BIO (Biological Sciences), GEO (Geosciences), EDU (STEM Education).
- **Data freshness is ~2-4 weeks** — significantly fresher than NIH Reporter's 6-month lag. Use `startDateStart`/`startDateEnd` to find genuinely recent awards.
- **Scheduled downtime: Friday 10PM – Sunday 12PM EST** — API unavailable during this window.
- **`projectoutcomes` endpoint** — `GET /services/v1/awards/{id}/projectoutcomes.json` returns the PI's public-facing outcomes report for completed grants. Useful for validating what a company actually built.
- **`offset` is 1-based** — first page is `offset=1`, not `offset=0`.
- **Boolean keyword search** — `keyword` supports `AND`, `OR`, `NOT` operators and quoted phrases (e.g., `"machine learning" AND biomedical`).
- **Response latency:** 0.4–0.7s for small requests; up to 8s for rpp=250.
