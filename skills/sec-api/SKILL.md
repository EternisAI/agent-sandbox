---
name: sec-api
description: Retrieve SEC filings and structured ownership, insider, fund, proxy, IPO, and private placement data using the sec-api Python SDK through the backend SEC proxy. Use when users ask for SEC filings content, forms, sections, or filing-derived datasets.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# SEC Filings API (sec-api via proxy)

Use the `sec-api` Python package through the backend SEC proxy. Do not use direct vendor API endpoints.

## Authentication and Proxy Base Override

```python
import os
from urllib.parse import quote
from sec_api import QueryApi, FullTextSearchApi, ExtractorApi, XbrlApi
from sec_api import InsiderTradingApi, Form13FHoldingsApi, Form13FCoverPagesApi
from sec_api import Form13DGApi, FormDApi, Form_S1_424B4_Api
from sec_api import ExecCompApi, DirectorsBoardMembersApi
from sec_api import FormNportApi, Form144Api, MappingApi

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/sec-proxy").rstrip("/")
api_key = os.environ["OPENROUTER_API_KEY"]

def bind_proxy(client, endpoint_path: str):
    token = quote(api_key)
    if endpoint_path:
        client.api_endpoint = f"{proxy_base}/{endpoint_path.lstrip('/')}?token={token}"
    else:
        client.api_endpoint = f"{proxy_base}?token={token}"
    return client

query_api = bind_proxy(QueryApi(api_key), "")
full_text_api = bind_proxy(FullTextSearchApi(api_key), "full-text-search")
extractor_api = bind_proxy(ExtractorApi(api_key), "extractor")
xbrl_api = bind_proxy(XbrlApi(api_key), "xbrl-to-json")
insider_api = bind_proxy(InsiderTradingApi(api_key), "insider-trading")
holdings_13f_api = bind_proxy(Form13FHoldingsApi(api_key), "form-13f/holdings")
cover_13f_api = bind_proxy(Form13FCoverPagesApi(api_key), "form-13f/cover-pages")
form_13dg_api = bind_proxy(Form13DGApi(api_key), "form-13d-13g")
form_d_api = bind_proxy(FormDApi(api_key), "form-d")
form_s1_424b4_api = bind_proxy(Form_S1_424B4_Api(api_key), "form-s1-424b4")
exec_comp_api = bind_proxy(ExecCompApi(api_key), "compensation")
directors_api = bind_proxy(DirectorsBoardMembersApi(api_key), "directors-and-board-members")
form_nport_api = bind_proxy(FormNportApi(api_key), "form-nport")
form_144_api = bind_proxy(Form144Api(api_key), "form-144")
mapping_api = bind_proxy(MappingApi(api_key), "mapping")
```

## Supported Retrieval Functions

| Form / Dataset | Signal | Cadence | Typical users | SDK/API path | Availability |
| --- | --- | --- | --- | --- | --- |
| 8-K | Material event between scheduled filings | Event-driven | HF, VC | Query API + Section Extractor (35 item types) | Supported |
| Form 4 | Insider buy/sell by officers/directors | Within 2 days | HF | Insider Trading API (`/insider-trading`) | Supported |
| 13D | Activist investor crosses 5% with intent | Within 5 business days | HF, VC | Form 13D/13G API (`/form-13d-13g`) | Business plan only |
| 10-Q | Quarterly financials, MD&A, risk updates | 3x per year | HF, VC | Query API + Section Extractor + XBRL-to-JSON | Supported |
| 13F | Institutional holdings ($100M+ AUM) | Quarterly | HF, VC | Form 13F API (`/form-13f`) | Supported |
| 10-K | Annual financials, risks, business overview | Yearly | HF, VC | Query API + Section Extractor + XBRL-to-JSON | Supported |
| SC TO | Tender offer / buyout offer | Event-driven | HF | Query API | Supported |
| S-1 | IPO registration prospectus | Pre-IPO | HF, VC | Form S-1/424B4 API (`/form-s1-424b4`) | Supported |
| 424B | Final prospectus terms | Per offering | HF | Form S-1/424B4 API (`/form-s1-424b4`) | Supported |
| DEF 14A (comp + directors) | Exec comp, votes, board composition | Annual | HF, VC | Executive Compensation API + Directors API | Supported |
| 13G | Passive investor crosses 5% | Annual/amended | HF, VC | Form 13D/13G API (`/form-13d-13g`) | Supported |
| 144 | Proposed restricted-securities sale notice | Pre-sale | HF | Form 144 API (`/form-144`) | Supported |
| 20-F | Foreign issuer annual report | Yearly | HF | Query API only | Supported |
| 6-K | Foreign issuer current report | Event-driven | HF | Query API only | Supported |
| N-PORT | Mutual fund monthly holdings | Monthly | HF, VC | Form N-PORT API (`/form-nport`) | Supported |
| Form D | Private placement filings | Within 15 days | VC | Form D API (`/form-d`) | Supported |

## Endpoint Reference

```python
from sec_api import QueryApi, FullTextSearchApi, ExtractorApi, XbrlApi
from sec_api import InsiderTradingApi, Form13FHoldingsApi, Form13FCoverPagesApi
from sec_api import Form13DGApi, FormDApi, Form_S1_424B4_Api
from sec_api import ExecCompApi, DirectorsBoardMembersApi
from sec_api import FormNportApi, Form144Api, MappingApi
```

## Call Graph (default workflow)

Always start from CIK resolution.

1. Mapping API: ticker -> CIK
2. Query API: CIK + form type + date filters -> accession number + filing URLs
3. Extractor API: filing details URL -> section text
4. XBRL API: accession number -> structured statements JSON

## Core Tool Gotchas

### Mapping API (`/mapping`)

- Response is always an array.
- Prefer ticker lookup over company-name matching.
- `cusip` can be a space-delimited string.
- Newly listed companies can lag due to daily update windows.

### Section Extractor (`/extractor`)

- Use `linkToFilingDetails` from Query API, not `linkToHtml`.
- Section codes are form-specific (`1A`, `part2item1a`, `2-2`).
- One section per call.
- Newly accepted filings can return `processing`; retry after a short delay.

### XBRL-to-JSON (`/xbrl-to-json`)

- Accession numbers must be hyphenated.
- Statement key names vary by filer; do not hardcode key names.
- Remove segment rows before summing consolidated totals.

## Document Retrieval APIs

### Query API (`/`)

Use for 10-K, 10-Q, 8-K, SC TO, S-3, 20-F, 6-K, and other filing retrieval.

- Strip leading zeros from CIK.
- `formType` is exact and case-sensitive (`"10-K"`, `"DEF 14A"`).
- `size` max is 50.
- Pagination hard cap is 10,000; narrow date ranges when needed.
- Use `periodOfReport` for fiscal-period filters and `filedAt` for acceptance-time filters.
- `items` filter only works for 8-K, Form 1-U, Form D, and Form ABS-15G.

### Full-Text Search (`/full-text-search`)

Use for filing content keyword queries across all forms.

### Insider Trading (`/insider-trading`)

- Filter by `documentType`, not `formType`.
- Use `issuer.cik` to find insiders at a company.
- Common transaction filters: `P` and `S` for open market activity.
- Non-derivative and derivative tables have different schemas.

### Form 13F (`/form-13f/holdings`, `/form-13f/cover-pages`)

- Use holdings and cover-pages classes together for complete output.
- `tableValueTotal` is absolute dollars.
- `periodOfReport` must be quarter-end.
- Use latest amendment by filing date.

### Form 13D/13G (`/form-13d-13g`)

- Use full strings: `SC 13D`, `SC 13G`, `SC 13D/A`, `SC 13G/A`.
- `cusip` is target company, `cik` is filer.
- 13D retrieval is business-plan gated.

### Form S-1/424B4 (`/form-s1-424b4`)

One endpoint for both registration and final prospectus retrieval.

### Executive Compensation (`/compensation`) and Directors (`/directors-and-board-members`)

- `year` filters are integer-based.
- Position titles are free-form text and not normalized.

### N-PORT (`/form-nport`), Form 144 (`/form-144`), Form D (`/form-d`)

- N-PORT is monthly fund holdings.
- Form 144 is proposed pre-sale notice data.
- Form D has no ticker; search by entity metadata.

## Example: CIK -> latest 10-K -> Risk Factors + XBRL

```python
import os
from urllib.parse import quote
from sec_api import MappingApi, QueryApi, ExtractorApi, XbrlApi

proxy_base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/sec-proxy").rstrip("/")
api_key = os.environ["OPENROUTER_API_KEY"]

def bind_proxy(client, endpoint_path: str):
    token = quote(api_key)
    if endpoint_path:
        client.api_endpoint = f"{proxy_base}/{endpoint_path}?token={token}"
    else:
        client.api_endpoint = f"{proxy_base}?token={token}"
    return client

mapping = bind_proxy(MappingApi(api_key), "mapping")
query = bind_proxy(QueryApi(api_key), "")
extractor = bind_proxy(ExtractorApi(api_key), "extractor")
xbrl = bind_proxy(XbrlApi(api_key), "xbrl-to-json")

# 1) ticker -> CIK
resolved = mapping.resolve("ticker", "AAPL")
cik = str(int(resolved[0]["cik"]))

# 2) latest 10-K
filings = query.get_filings({
    "query": f'cik:{cik} AND formType:"10-K"',
    "from": 0,
    "size": 1,
    "sort": [{"filedAt": {"order": "desc"}}]
})

f = filings["filings"][0]
details_url = f["linkToFilingDetails"]
accession_no = f["accessionNo"]

# 3) 10-K Item 1A risk factors
risk_text = extractor.get_section(details_url, "1A", "text")

# 4) structured statements
statements = xbrl.xbrl_to_json(accession_no)

print(f"CIK: {cik}")
print(f"Accession: {accession_no}")
print(f"Risk section chars: {len(risk_text)}")
print(f"XBRL statement groups: {len(statements.keys())}")
```

## Usage Rules

- Always process responses in Python and output concise summaries.
- Keep queries bounded (`size`, date windows, exact form types).
- When section extraction fails with `processing`, retry with short backoff.
- For filing retrieval tasks, prefer Mapping -> Query -> Extractor/XBRL flow.
