---
name: nih-reporter
description: Search NIH grant awards via NIH Reporter. Use for VC R&D research — finding what biotech and medtech startups are funded by NIH, SBIR phase detection, topic-based deal sourcing, PI background checks, disease-area screening by NIH institute, and identifying Phase II companies whose grants are expiring soon.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# NIH Reporter API

Public API — no proxy, no API key. Call directly via HTTP.

## Base URL and Helper

```python
import json
import urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path: str, body: dict) -> dict:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())
```

## Supported Tools

| Tool | What it returns |
| --- | --- |
| `search_by_company` | All NIH grants for a company — title, amount, activity code, abstract, PI, dates |
| `discover_sbir` | SBIR/STTR grants by phase, topic, institute, state, and amount range — deal sourcing |
| `search_by_topic` | Full-text search across grant terms or abstracts with optional SBIR filter |
| `search_by_pi` | All grants for a named principal investigator — founder background check |
| `search_by_institute` | Grants filtered by NIH institute (NCI, NHLBI, NIAID, etc.) — disease-area sourcing |
| `expiring_grants` | Active grants with end dates in a given window — warm sourcing list |
| `new_awards` | Grants that started within a date range — recent cohort of freshly funded companies |
| `get_publications` | PMIDs linked to a grant's core project number — verify publication output |

## Functions

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path: str, body: dict) -> dict:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def search_by_company(org_name: str, activity_codes: list = None,
                      fiscal_years: list = None, limit: int = 10) -> dict:
    """All NIH grants for a company. activity_codes and fiscal_years are optional filters."""
    criteria: dict = {"org_names": [org_name]}
    if activity_codes:
        criteria["activity_codes"] = activity_codes
    if fiscal_years:
        criteria["fiscal_years"] = fiscal_years
    return nih_post("/v2/projects/search", {
        "criteria": criteria,
        "offset": 0, "limit": limit,
        "sort_field": "fiscal_year", "sort_order": "desc",
    })

def discover_sbir(phase: int = 1, fiscal_years: list = None,
                  topic: str = None, institute: str = None,
                  states: list = None, min_amount: int = None,
                  max_amount: int = None, new_only: bool = False,
                  limit: int = 25) -> dict:
    """
    SBIR/STTR deal sourcing. phase=1 → R43/R41, phase=2 → R44/R42.
    topic: searched in MeSH-like grant terms.
    institute: NIH institute abbreviation (NCI, NHLBI, NIAID, etc.).
    states: list of 2-letter state codes, e.g. ["CA", "MA"].
    min_amount / max_amount: filter by award size in dollars.
    new_only: if True, restricts to new (non-renewal) applications via award_types=[1].
    """
    codes = {1: ["R43", "R41"], 2: ["R44", "R42"]}.get(phase, ["R43", "R44"])
    criteria: dict = {"activity_codes": codes}
    if fiscal_years:
        criteria["fiscal_years"] = fiscal_years
    if institute:
        criteria["agencies"] = [institute]
    if states:
        criteria["org_states"] = states
    if min_amount is not None or max_amount is not None:
        criteria["award_amount_range"] = {
            k: v for k, v in [("min_amount", min_amount), ("max_amount", max_amount)] if v is not None
        }
    if new_only:
        criteria["award_types"] = [1]  # 1=new application, 2=competing renewal, 5=non-competing continuation
    if topic:
        criteria["advanced_text_search"] = {
            "operator": "and", "search_field": "terms", "search_text": topic,
        }
    return nih_post("/v2/projects/search", {
        "criteria": criteria,
        "offset": 0, "limit": limit,
        "sort_field": "award_amount", "sort_order": "desc",
    })

def search_by_topic(text: str, search_field: str = "terms",
                    activity_codes: list = None, fiscal_years: list = None,
                    limit: int = 25) -> dict:
    """
    Full-text topic search. search_field: 'terms' (MeSH-like), 'abstract_text', or 'project_title'.
    Always pass activity_codes when doing SBIR sourcing — omitting it returns large institutional awards.
    """
    criteria: dict = {
        "advanced_text_search": {
            "operator": "and", "search_field": search_field, "search_text": text,
        }
    }
    if activity_codes:
        criteria["activity_codes"] = activity_codes
    if fiscal_years:
        criteria["fiscal_years"] = fiscal_years
    return nih_post("/v2/projects/search", {
        "criteria": criteria,
        "offset": 0, "limit": limit,
        "sort_field": "award_amount", "sort_order": "desc",
    })

def search_by_pi(first_name: str, last_name: str, limit: int = 10) -> dict:
    """All grants for a named PI — founder background, publication trail, funding history."""
    return nih_post("/v2/projects/search", {
        "criteria": {"pi_names": [{"first_name": first_name, "last_name": last_name}]},
        "offset": 0, "limit": limit,
        "sort_field": "award_amount", "sort_order": "desc",
    })

def search_by_institute(institute: str, activity_codes: list = None,
                        fiscal_years: list = None, states: list = None,
                        limit: int = 25) -> dict:
    """
    Grants filtered by NIH institute abbreviation.
    Common codes: NCI, NHLBI, NIAID, NIMH, NIA, NIDDK, NINDS, NIBIB, NIDCR, NICHD.
    Combine with activity_codes=["R43","R44"] for SBIR sourcing by disease area.
    states: optional 2-letter state filter, e.g. ["TX", "FL"].
    """
    criteria: dict = {"agencies": [institute]}
    if activity_codes:
        criteria["activity_codes"] = activity_codes
    if fiscal_years:
        criteria["fiscal_years"] = fiscal_years
    if states:
        criteria["org_states"] = states
    return nih_post("/v2/projects/search", {
        "criteria": criteria,
        "offset": 0, "limit": limit,
        "sort_field": "award_amount", "sort_order": "desc",
    })

def expiring_grants(from_date: str, to_date: str, activity_codes: list = None,
                    active_only: bool = True, states: list = None,
                    min_amount: int = None, limit: int = 25) -> dict:
    """
    Grants with end dates in the given window. Dates: 'YYYY-MM-DD'.
    Default activity_codes=["R44","R42"] (Phase II SBIR/STTR) — companies likely raising Series A.
    states: optional geo filter. min_amount: exclude small awards.
    Sort ascending so soonest-expiring appear first.
    """
    if activity_codes is None:
        activity_codes = ["R44", "R42"]
    criteria: dict = {
        "activity_codes": activity_codes,
        "project_end_date": {"from_date": from_date, "to_date": to_date},
    }
    if active_only:
        criteria["is_active"] = True
    if states:
        criteria["org_states"] = states
    if min_amount is not None:
        criteria["award_amount_range"] = {"min_amount": min_amount}
    return nih_post("/v2/projects/search", {
        "criteria": criteria,
        "offset": 0, "limit": limit,
        "sort_field": "project_end_date", "sort_order": "asc",
    })

def new_awards(from_date: str, to_date: str, activity_codes: list = None,
               institute: str = None, states: list = None, limit: int = 25) -> dict:
    """
    Grants that started within a date range — recent cohort of freshly funded companies.
    Dates: 'YYYY-MM-DD'. Note: data lags ~6 months; FY2026 (Oct 2025+) not yet indexed.
    Default activity_codes=["R43","R44"] for SBIR. Combine with institute or states to narrow.
    """
    if activity_codes is None:
        activity_codes = ["R43", "R44"]
    criteria: dict = {
        "activity_codes": activity_codes,
        "project_start_date": {"from_date": from_date, "to_date": to_date},
    }
    if institute:
        criteria["agencies"] = [institute]
    if states:
        criteria["org_states"] = states
    return nih_post("/v2/projects/search", {
        "criteria": criteria,
        "offset": 0, "limit": limit,
        "sort_field": "project_start_date", "sort_order": "desc",
    })

def get_publications(project_num: str, limit: int = 25) -> dict:
    """
    Returns PMIDs linked to a grant. project_num: strip leading digit and trailing -NN suffix.
    Example: '2R44NS124351-04' → 'R44NS124351'. Response only has pmid/applid/coreproject.
    Use PMIDs with PubMed to fetch full title/abstract/author metadata.
    """
    # Normalize: strip leading digit prefix (e.g. '2R44...') and trailing supplement ('-04')
    import re
    core = re.sub(r"^\d+", "", project_num)  # strip leading digit
    core = re.sub(r"-\w+$", "", core)         # strip trailing -NN or -01A1 etc.
    return nih_post("/v2/publications/search", {
        "criteria": {"core_project_nums": [core]},
        "offset": 0, "limit": limit,
    })
```

## Examples

### Company Due Diligence — EpiCypher

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

r = nih_post("/v2/projects/search", {
    "criteria": {
        "org_names": ["EpiCypher"],
        "activity_codes": ["R43", "R44", "R41", "R42"],
    },
    "offset": 0, "limit": 15,
    "sort_field": "fiscal_year", "sort_order": "desc",
})
print(f"Total NIH SBIR grants: {r['meta']['total']}")
for p in r.get("results", []):
    org = p.get("organization") or {}
    print(f"  FY{p['fiscal_year']}  ${p.get('award_amount',0):>10,.0f}  [{p['activity_code']}]  {p['project_num']}")
    print(f"    {p.get('project_title','')[:70]}")
    print(f"    Abstract: {str(p.get('abstract_text',''))[:150]}")
    print(f"    Terms: {str(p.get('pref_terms',''))[:120]}")
```

### SBIR Deal Sourcing — Phase I Oncology Startups

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

r = nih_post("/v2/projects/search", {
    "criteria": {
        "activity_codes": ["R43"],
        "agencies": ["NCI"],
        "fiscal_years": [2024, 2025],
    },
    "offset": 0, "limit": 20,
    "sort_field": "award_amount", "sort_order": "desc",
})
print(f"NCI Phase I SBIR 2024-2025: {r['meta']['total']} total")
for p in r.get("results", []):
    org = p.get("organization") or {}
    print(f"  ${p.get('award_amount',0):>8,.0f}  {org.get('org_name','')[:40]}  {org.get('org_city','')}, {org.get('org_state','')}")
    print(f"    PI: {p.get('contact_pi_name','')}  |  {p.get('project_title','')[:65]}")
```

### Topic Search — CRISPR SBIR Grants

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

r = nih_post("/v2/projects/search", {
    "criteria": {
        "advanced_text_search": {
            "operator": "and", "search_field": "terms", "search_text": "CRISPR",
        },
        "activity_codes": ["R43", "R44"],
        "fiscal_years": [2024, 2025],
    },
    "offset": 0, "limit": 15,
    "sort_field": "award_amount", "sort_order": "desc",
})
print(f"CRISPR SBIR grants 2024-2025: {r['meta']['total']}")
for p in r.get("results", []):
    org = p.get("organization") or {}
    print(f"  ${p.get('award_amount',0):>10,.0f}  [{p['activity_code']}]  {org.get('org_name','')[:40]}")
    print(f"    {p.get('project_title','')[:70]}")
    print(f"    {str(p.get('abstract_text',''))[:120]}")
```

### Expiring Phase II — Warm Sourcing List

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

# Phase II companies whose grants expire in the next 9 months — likely raising Series A
r = nih_post("/v2/projects/search", {
    "criteria": {
        "activity_codes": ["R44", "R42"],
        "is_active": True,
        "project_end_date": {"from_date": "2026-04-23", "to_date": "2027-01-31"},
    },
    "offset": 0, "limit": 25,
    "sort_field": "project_end_date", "sort_order": "asc",
})
print(f"Phase II grants expiring by Jan 2027: {r['meta']['total']}")
for p in r.get("results", []):
    org = p.get("organization") or {}
    print(f"  ends {p.get('project_end_date','')[:10]}  ${p.get('award_amount',0):>10,.0f}  {org.get('org_name','')[:40]}  {org.get('org_city','')}, {org.get('org_state','')}")
    print(f"    {p.get('project_title','')[:70]}")
```

### New Awards — Recent Deal Flow Cohort

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

# Grants that started Jul-Sep 2025 — most recent available cohort (~6 month lag)
r = nih_post("/v2/projects/search", {
    "criteria": {
        "activity_codes": ["R43", "R44"],
        "project_start_date": {"from_date": "2025-07-01", "to_date": "2025-09-30"},
    },
    "offset": 0, "limit": 25,
    "sort_field": "project_start_date", "sort_order": "desc",
})
print(f"New SBIR grants Jul-Sep 2025: {r['meta']['total']}")
for p in r.get("results", []):
    org = p.get("organization") or {}
    print(f"  started {p.get('project_start_date','')[:10]}  [{p['activity_code']}]  ${p.get('award_amount',0):>9,.0f}  {org.get('org_name','')[:40]}")
    print(f"    {p.get('project_title','')[:70]}")
```

### PI Background Check

```python
import json, urllib.request

BASE = "https://api.reporter.nih.gov"

def nih_post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

r = nih_post("/v2/projects/search", {
    "criteria": {
        "pi_names": [{"first_name": "Jennifer", "last_name": "Doudna"}],
    },
    "offset": 0, "limit": 10,
    "sort_field": "fiscal_year", "sort_order": "desc",
})
print(f"Total NIH grants: {r['meta']['total']}")
for p in r.get("results", []):
    org = p.get("organization") or {}
    print(f"  FY{p['fiscal_year']}  ${p.get('award_amount',0):>10,.0f}  [{p['activity_code']}]  {org.get('org_name','')[:35]}")
    print(f"    {p.get('project_title','')[:70]}")
    # Show all co-investigators
    pis = p.get("principal_investigators") or []
    names = [pi["full_name"] for pi in pis if pi.get("full_name")]
    if names:
        print(f"    Co-PIs: {', '.join(names[:4])}")
```

## Notes

- **No API key, no auth** — completely open public endpoint, call directly with no headers beyond Content-Type.
- **`organization` is always a nested dict** — access as `p.get("organization") or {}`. Fields: `org_name`, `org_city`, `org_state`, `org_ueis`, `primary_uei`, `org_duns`.
- **`include_fields` drops `organization`** — omit `include_fields` entirely to get all fields including org location.
- **`pref_terms`** is a semicolon-separated string of structured MeSH-like terms (cleaner than raw `terms`). Use for topic tagging and categorization.
- **`principal_investigators`** is a list. Each has `full_name`, `is_contact_pi`, `first_name`, `last_name`, `profile_id`.
- **SBIR activity codes:** R43 = Phase I, R44 = Phase II, R41 = STTR Phase I, R42 = STTR Phase II.
- **NIH institute abbreviations:** NCI (cancer), NHLBI (heart/lung/blood), NIAID (infectious disease), NIMH (mental health), NIA (aging), NIDDK (diabetes/digestive/kidney), NINDS (neurology), NIBIB (biomedical imaging), NICHD (child health).
- **`search_by_topic` without `activity_codes`** returns large institutional awards — always pass `activity_codes=["R43","R44"]` when sourcing startups.
- **Data lag ~6 months** — `project_start_date` queries for FY2026 (Oct 2025+) return 0 results. Most recent indexed data is Sept/Oct 2025. Use `fiscal_years` for the latest available cohort.
- **`award_notice_date` criteria** — works with ISO `YYYY-MM-DD` dates. The notice date (when NIH issues the award notice) is slightly earlier than the project start date, both lag ~6 months.
- **`award_types` criteria** — integer codes: 1=new application, 2=competing renewal, 5=non-competing continuation. Use `award_types=[1]` to exclude renewals and see only freshly minted grants.
- **`newly_added_projects_only`** — returns records added to the database in the last batch load. Works alone (~700 results) but returns 0 when combined with activity code filters like SBIR (transient state — only useful without other filters).
- **Publications endpoint** — `/v2/publications/search` only accepts `core_project_nums`, `appl_ids`, or `pmids` as criteria. Response only contains `pmid`, `applid`, `coreproject` — no title, author, or journal. Use PMIDs with the PubMed API (`https://pubmed.ncbi.nlm.nih.gov/{pmid}/`) to get full metadata.
- **Core project number format** — strip leading digit and trailing supplement: `2R44NS124351-04` → `R44NS124351`. The `get_publications` helper does this automatically.
- **Offset cap ~10,000** — queries with `offset` above ~10,000 time out. Use filters to narrow result sets rather than deep pagination.
- **Rate limit** — not officially documented; stay under ~60 req/min to avoid throttling.
- **`limit` max is 500** per request.
- **Pagination:** `meta.total` is accurate (unlike USASpending). Use `offset` to page through results.
- **`project_detail_url`** in each result links directly to the NIH Reporter web page for that grant.
- **Response latency:** 0.4–0.7s for most queries.
