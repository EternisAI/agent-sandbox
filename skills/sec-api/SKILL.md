---
name: sec-api
description: Retrieve SEC filings and structured ownership, insider, fund, proxy, IPO, and private placement data via HTTP requests to the backend SEC proxy. Use when users ask for SEC filings content, forms, sections, or filing-derived datasets.
allowed-tools: Bash(curl *), Bash(jq *)
---

# SEC Filings API (HTTP via proxy)

Use HTTP requests to the backend SEC proxy. Do not use the `sec-api` Python SDK and do not call direct vendor API endpoints.

## Authentication and Proxy Base Override

```bash
PROXY_BASE="${OPENROUTER_BASE_URL%/api/llm-proxy}/api/sec-proxy"
TOKEN_ENC="$(jq -nr --arg v "${OPENROUTER_API_KEY}" '$v|@uri')"

# Base Query API endpoint (root path)
QUERY_URL="${PROXY_BASE}?token=${TOKEN_ENC}"

# Examples of other endpoint URLs
MAPPING_URL="${PROXY_BASE}/mapping?token=${TOKEN_ENC}"
EXTRACTOR_URL="${PROXY_BASE}/extractor?token=${TOKEN_ENC}"
XBRL_URL="${PROXY_BASE}/xbrl-to-json?token=${TOKEN_ENC}"
```

## Supported Retrieval Functions

| Form / Dataset | Signal | Cadence | Typical users | Endpoint | Availability |
| --- | --- | --- | --- | --- | --- |
| 8-K | Material event between scheduled filings | Event-driven | HF, VC | `POST /` + `POST /extractor` (35 item types) | Supported |
| Form 4 | Insider buy/sell by officers/directors | Within 2 days | HF | `POST /insider-trading` | Supported |
| 13D | Activist investor crosses 5% with intent | Within 5 business days | HF, VC | `POST /form-13d-13g` + `POST /extractor` | Supported |
| 10-Q | Quarterly financials, MD&A, risk updates | 3x per year | HF, VC | `POST /` + `POST /extractor` + `GET /xbrl-to-json` | Supported |
| 13F | Institutional holdings ($100M+ AUM) | Quarterly | HF, VC | `POST /form-13f/holdings` + `POST /form-13f/cover-pages` | Supported |
| 10-K | Annual financials, risks, business overview | Yearly | HF, VC | `POST /` + `POST /extractor` + `GET /xbrl-to-json` | Supported |
| SC TO | Tender offer / buyout offer | Event-driven | HF | `POST /` | Supported |
| S-1 | IPO registration prospectus | Pre-IPO | HF, VC | `POST /form-s1-424b4` | Supported |
| 424B | Final prospectus terms | Per offering | HF | `POST /form-s1-424b4` | Supported |
| DEF 14A (comp + directors) | Exec comp, votes, board composition | Annual | HF, VC | `POST /compensation` + `POST /directors-and-board-members` | Supported |
| 13G | Passive investor crosses 5% | Annual/amended | HF, VC | `POST /form-13d-13g` | Supported |
| 144 | Proposed restricted-securities sale notice | Pre-sale | HF | `POST /form-144` | Supported |
| 20-F | Foreign issuer annual report | Yearly | HF | `POST /` only | Supported |
| 6-K | Foreign issuer current report | Event-driven | HF | `POST /` only | Supported |
| N-PORT | Mutual fund monthly holdings | Monthly | HF, VC | `POST /form-nport` | Supported |
| Form D | Private placement filings | Within 15 days | VC | `POST /form-d` | Supported |

## Call Graph (default workflow)

Always start from CIK resolution.

1. `POST /mapping`: ticker -> CIK
2. `POST /`: CIK + form type + date filters -> accession number + filing URLs
3. `POST /extractor`: filing details URL -> section text
4. `GET /xbrl-to-json`: accession number -> structured statements JSON

## Core Tool Gotchas

### Mapping (`POST /mapping`)

- Response is always an array.
- Prefer ticker lookup over company-name matching.
- `cusip` can be a space-delimited string.
- Newly listed companies can lag due to daily update windows.

### Section Extractor (`POST /extractor`)

- Use `linkToFilingDetails` from Query API, not `linkToHtml`.
- Section codes are form-specific (`1A`, `part2item1a`, `2-2`).
- One section per call.
- Newly accepted filings can return `processing`; retry after a short delay.

### XBRL-to-JSON (`GET /xbrl-to-json`)

- Accession numbers must be hyphenated.
- Statement key names vary by filer; do not hardcode key names.
- Remove segment rows before summing consolidated totals.

## Document Retrieval APIs

### Query (`POST /`)

Use for 10-K, 10-Q, 8-K, SC TO, S-3, 20-F, 6-K, and other filing retrieval.

- Strip leading zeros from CIK.
- `formType` is exact and case-sensitive (`"10-K"`, `"DEF 14A"`).
- `size` max is 50.
- Pagination hard cap is 10,000; narrow date ranges when needed.
- Use `periodOfReport` for fiscal-period filters and `filedAt` for acceptance-time filters.
- `items` filter only works for 8-K, Form 1-U, Form D, and Form ABS-15G.

### Full-Text Search (`POST /full-text-search`)

Use for filing content keyword queries across all forms.

### Insider Trading (`POST /insider-trading`)

- Filter by `documentType`, not `formType`.
- Use `issuer.cik` to find insiders at a company.
- Common transaction filters: `P` and `S` for open market activity.
- Non-derivative and derivative tables have different schemas.

### Form 13F (`POST /form-13f/holdings`, `POST /form-13f/cover-pages`)

- Use holdings and cover-pages classes together for complete output.
- `tableValueTotal` is absolute dollars.
- `periodOfReport` must be quarter-end.
- Use latest amendment by filing date.

### Form 13D/13G (`POST /form-13d-13g`)

- Use full strings: `SC 13D`, `SC 13G`, `SC 13D/A`, `SC 13G/A`.
- `cusip` is target company, `cik` is filer.
- Use `POST /form-13d-13g` for 13D filings; combine with Section Extractor for detailed text extraction.

### Form S-1/424B4 (`POST /form-s1-424b4`)

One endpoint for both registration and final prospectus retrieval.

### Executive Compensation (`POST /compensation`) and Directors (`POST /directors-and-board-members`)

- `year` filters are integer-based.
- Position titles are free-form text and not normalized.

### N-PORT (`POST /form-nport`), Form 144 (`POST /form-144`), Form D (`POST /form-d`)

- N-PORT is monthly fund holdings.
- Form 144 is proposed pre-sale notice data.
- Form D has no ticker; search by entity metadata.

## Example: CIK -> latest 10-K -> Risk Factors + XBRL

```bash
set -euo pipefail

PROXY_BASE="${OPENROUTER_BASE_URL%/api/llm-proxy}/api/sec-proxy"
TOKEN_ENC="$(jq -nr --arg v "${OPENROUTER_API_KEY}" '$v|@uri')"

# 1) ticker -> CIK
CIK="$(curl -sS -X POST "${PROXY_BASE}/mapping?token=${TOKEN_ENC}" \
  -H 'Content-Type: application/json' \
  -d '{"query":"ticker:AAPL"}' | jq -r '.[0].cik | tonumber')"

# 2) latest 10-K
FILING_JSON="$(curl -sS -X POST "${PROXY_BASE}?token=${TOKEN_ENC}" \
  -H 'Content-Type: application/json' \
  -d "{\"query\":\"cik:${CIK} AND formType:\\\"10-K\\\"\",\"from\":0,\"size\":1,\"sort\":[{\"filedAt\":{\"order\":\"desc\"}}]}")"

DETAILS_URL="$(jq -r '.filings[0].linkToFilingDetails' <<<"${FILING_JSON}")"
ACCESSION_NO="$(jq -r '.filings[0].accessionNo' <<<"${FILING_JSON}")"

# 3) 10-K Item 1A risk factors
RISK_TEXT="$(curl -sS -X POST "${PROXY_BASE}/extractor?token=${TOKEN_ENC}" \
  -H 'Content-Type: application/json' \
  -d "{\"url\":\"${DETAILS_URL}\",\"item\":\"1A\",\"type\":\"text\"}")"

# 4) structured statements
XBRL_JSON="$(curl -sS "${PROXY_BASE}/xbrl-to-json?token=${TOKEN_ENC}&accession-no=${ACCESSION_NO}")"

printf 'CIK: %s\n' "${CIK}"
printf 'Accession: %s\n' "${ACCESSION_NO}"
printf 'Risk section chars: %s\n' "$(wc -c <<<"${RISK_TEXT}" | tr -d ' ')"
printf 'XBRL statement groups: %s\n' "$(jq 'keys | length' <<<"${XBRL_JSON}")"
```

## Usage Rules

- Always use HTTP requests to sec-proxy endpoints; do not use the sec-api Python SDK.
- Parse JSON responses and output concise summaries.
- Keep queries bounded (`size`, date windows, exact form types).
- When section extraction fails with `processing`, retry with short backoff.
- For filing retrieval tasks, prefer Mapping -> Query -> Extractor/XBRL flow.
