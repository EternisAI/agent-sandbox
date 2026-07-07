---
name: cbuae
description: Fetch structured monetary and banking-sector time series from the Central Bank of the UAE (centralbank.ae) — the canonical source for UAE M0/M1/M2/M3, central-bank balance sheet, gross international reserves, banking-sector aggregates (assets/liabilities/credit/deposits) by bank type and emirate, financial soundness indicators, and 7-year monthly cash-operations history. Data is published as XLSX files with ~2-month freshness lag — much fresher than the Finnhub macro feed, which lags UAE CPI by 2.5 years. Use this for any UAE macro / monetary policy / banking-system question that requires the actual numeric time series (not just the headline announcement, which is in WAM).
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# CBUAE (Central Bank of the UAE) Statistical Bulletins

CBUAE publishes monthly XLSX bulletins covering UAE monetary aggregates, the central bank balance sheet, the consolidated banking sector, banking aggregates by bank type (conventional vs Islamic, national vs foreign), banking aggregates by emirate (Abu Dhabi / Dubai / Other Emirates), and a 7-year monthly history of cash operations. This is the canonical source — fresher than any third-party macro feed.

## When to pick this skill

- **UAE M0 / M1 / M2 / M3** monthly history. Finnhub's UAE monetary aggregates exist but with uneven freshness; CBUAE is the source.
- **Central bank balance sheet** — total assets, gross international reserves, gold reserves, monthly.
- **Consolidated banking sector** — total assets, foreign assets, foreign liabilities, domestic credit, deposits, credit by economic activity.
- **By-bank-type breakdowns** — Conventional Banks (CB) vs Islamic Banks (IB), National Banks (NB) vs Foreign Banks (FB). For any question about Emirates NBD / FAB / DIB / ADIB / Mashreq positioning at the system level.
- **By-emirate breakdowns** — Abu Dhabi vs Dubai vs Other Emirates banking aggregates. For DIFC / ADGM competitive-positioning questions.
- **Core Financial Soundness Indicators (Core FSI)** — quarterly capital adequacy, asset quality, profitability for the UAE banking sector.
- **7-year cash operations history** — Jan 2019 → current month, monthly granularity, in a single 31KB file. Use for any cash / cheque / FTS volume trend.
- **Insurance sector** — gross written premiums, profits (annual + quarterly).

**Do NOT use this skill for:**

- **CBUAE rate decisions and policy announcements** — those are in **WAM** as wire articles within hours of each meeting (`search_cbuae_policy` in the `wam` skill). The XLSX bulletins do not carry the rate decision; they carry the resulting monetary aggregates.
- **Discovery of WHAT CBUAE has announced recently** — use WAM (`search_news` with `CBUAE` filter). This skill is for the structured numeric data behind those announcements.
- **Listed-bank fundamentals (Emirates NBD, FAB, DIB, etc.)** — use Finnhub at the security level. CBUAE gives system-level aggregates, not per-bank balance sheets.

## Authentication and gating model

**Two-tier surface.** This matters for how the agent calls the skill:

| Surface | Direct urllib | Notes |
|---|---|---|
| `/en/research-and-statistics/` and per-month landing pages | ❌ Cloudflare-gated (HTTP 403) | Routed through the backend Firecrawl proxy (`PROXY_BASE_URL` / `PROXY_API_KEY`). No vendor key in the sandbox. |
| `/media/<hash>/<file>.xlsx` and `/media/<hash>/<file>.pdf` | ✅ Public (HTTP 200) | Direct urllib download works, no auth, no UA tricks needed |

**Implication:** call `fetch_bulletin_index()` ONCE per session to discover the current bulletin URLs (the helper proxies a `rawHtml` scrape and parses it into `{dataset: [{month, xlsx_url, pdf_url}]}`), then call `download_bulletin(xlsx_url)` directly on each XLSX URL.

**Why `rawHtml`, not `markdown`.** The CBUAE landing page renders dataset file links through JavaScript filters that Firecrawl's `markdown` serializer drops — `markdown` returns dataset names as headings but with no XLSX URLs. The skill's helper requests `rawHtml` for you; do not override.

## Helper

```python
import json
import os
import urllib.request
import openpyxl
import io
import re

UA = "Mozilla/5.0 (compatible; AxionAgent/1.0)"


def _firecrawl_proxy_base() -> str:
    return os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/firecrawl-proxy")


def _firecrawl_scrape(url: str, *, timeout_s: int = 120,
                      formats: list[str] | None = None) -> str:
    """Scrape via the backend Firecrawl proxy. Returns the page body as a
    string (rawHtml by default). The CBUAE landing page needs `formats=
    ["rawHtml"]` so the `<a href>` tags survive serialization."""
    body = {
        "url": url,
        "formats": formats or ["rawHtml"],
        "timeout": (timeout_s - 10) * 1000,
    }
    req = urllib.request.Request(
        _firecrawl_proxy_base().rstrip("/") + "/v1/scrape",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['PROXY_API_KEY']}",
            "Content-Type": "application/json",
            "User-Agent": UA,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as r:
        resp = json.loads(r.read().decode())
    if not resp.get("success"):
        raise RuntimeError(f"Firecrawl failed for {url}: {resp.get('error','no error msg')[:200]}")
    data = resp.get("data") or {}
    return data.get("rawHtml") or data.get("markdown") or ""

# Months → MM mapping shared across all date-normalization functions.
_MONTH_MAP = {
    "jan": "01", "feb": "02", "mar": "03", "apr": "04", "may": "05", "jun": "06",
    "jul": "07", "aug": "08", "sep": "09", "oct": "10", "nov": "11", "dec": "12",
    "january": "01", "february": "02", "march": "03", "april": "04",
    "june": "06", "july": "07", "august": "08", "september": "09",
    "october": "10", "november": "11", "december": "12",
}


def _fetch_bytes(url: str) -> bytes:
    """Download an XLSX (or PDF) file directly. Works for /media/<hash>/<file>.xlsx URLs."""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def _open_xlsx(data: bytes) -> openpyxl.Workbook:
    return openpyxl.load_workbook(io.BytesIO(data), data_only=True, read_only=True)


def _clean(s: str) -> str:
    """Strip outer whitespace and collapse embedded newlines/tabs in label strings.
    CBUAE bulletins sometimes carry labels like 'UAE Fund Transfer System (FTS) \\nInter-bank Payments'
    or sheet names like '1-Sel Ind ' with a trailing space. Without this, exact-match
    lookups KeyError and waste an agent turn."""
    if not isinstance(s, str):
        return s
    return re.sub(r"\s+", " ", s).strip()


def _normalize_date(label: str) -> str:
    """Normalize a CBUAE date label to ISO-ish form.

      'Jan 19'      → '2019-01'      (Banking Operations short form)
      'Feb-19'      → '2019-02'      (Banking Operations short form)
      'Apr 2025'    → '2025-04'      (Statistical Bulletin standard form)
      'Apr 2026 *'  → '2026-04'      (preliminary marker stripped)
      'Q1 2026'     → '2026-Q1'      (Core FSI quarterly form, space-separated)
      '2026Q1'      → '2026-Q1'      (Core FSI quarterly form, year-first)
      'Mar-26'      → '2026-03'      (some sheets)

    Unknown formats are returned unchanged so the caller can still see the original."""
    if not isinstance(label, str):
        return label
    s = label.strip().rstrip(" *")

    # Year-first quarterly: '2026Q1' → '2026-Q1'
    yq = re.match(r"^(\d{4})Q(\d)$", s, re.I)
    if yq:
        return f"{yq.group(1)}-Q{yq.group(2)}"

    # Quarterly: 'Q1 2026' or 'Q1-2026' → '2026-Q1'
    qm = re.match(r"^Q(\d)[\s-](\d{2,4})$", s, re.I)
    if qm:
        y = qm.group(2)
        if len(y) == 2:
            y = "20" + y
        return f"{y}-Q{qm.group(1)}"

    # Monthly: 'Apr 2025', 'Apr-25', 'Jan 19', 'April 2025'
    mm = re.match(r"^([A-Za-z]+)[\s-](\d{2,4})$", s)
    if mm:
        mon, y = mm.group(1).lower(), mm.group(2)
        if mon in _MONTH_MAP:
            if len(y) == 2:
                y = "20" + y
            return f"{y}-{_MONTH_MAP[mon]}"
    return s


def _resolve_sheet(wb, name: str) -> str:
    """Return the actual sheet name for a user-supplied lookup string. Tries:
      1. exact match
      2. exact match after whitespace cleanup
      3. case-insensitive prefix match
      4. case-insensitive substring match

    Raises KeyError with the closest candidates if nothing matches."""
    if name in wb.sheetnames:
        return name
    cleaned = _clean(name)
    for sn in wb.sheetnames:
        if _clean(sn) == cleaned:
            return sn
    lo = cleaned.lower()
    for sn in wb.sheetnames:
        if _clean(sn).lower().startswith(lo):
            return sn
    for sn in wb.sheetnames:
        if lo in _clean(sn).lower():
            return sn
    raise KeyError(
        f"Sheet '{name}' not found. Candidates: " +
        ", ".join(f"'{sn.strip()}'" for sn in wb.sheetnames[:8])
    )
```

## Supported methods

| Method | Purpose | Cost |
| --- | --- | --- |
| `fetch_bulletin_index` | One-call discovery: scrape the landing page via the backend Firecrawl proxy and parse it into a `{dataset: [{month, xlsx_url, pdf_url}]}` index | 1 Firecrawl scrape |
| `parse_bulletin_index` | Same parse step, on rawHtml you already have. Use when you have cached landing-page HTML; otherwise call `fetch_bulletin_index` | 0 (in-memory parse) |
| `download_bulletin` | Fetch any `/media/<hash>/<file>.xlsx` URL into memory | 1 HTTP request |
| `list_sheets` | List sheet names in a downloaded XLSX | 0 (in-memory) |
| `read_series` | Extract a named indicator as `{date: value}` time series | 0 (in-memory) |
| `read_full_history` | Pull the entire 7-year Banking Operations XLSX as `{column: {date: value}}` | 0 (in-memory) |
| `list_indicators` | List every indicator name on a sheet | 0 (in-memory) |

## Method signatures

```python
def fetch_bulletin_index() -> dict:
    """Scrape https://www.centralbank.ae/en/research-and-statistics/ through
    the backend Firecrawl proxy and parse the result. Returns the same
    `{dataset: [{month, xlsx_url, pdf_url}]}` structure as parse_bulletin_index.
    Call this ONCE per session, then download each XLSX directly."""

def parse_bulletin_index(rawhtml: str) -> dict:
    """Pure parser — pass rawHtml of the /en/research-and-statistics/ landing
    page (the format the Firecrawl proxy returns). Returns a dict of
    {dataset_name: [{month: "April 2026", xlsx_url: "...", pdf_url: "..."}, ...]}
    for each dataset CBUAE currently lists. Most callers should use
    fetch_bulletin_index() instead."""

def download_bulletin(xlsx_url: str) -> bytes:
    """Direct fetch of a /media/<hash>/<file>.xlsx URL. Returns raw bytes
    suitable for openpyxl.load_workbook(BytesIO(...))."""

def list_sheets(xlsx_bytes: bytes) -> list[str]:
    """Return the sheet names in the workbook. Useful when first inspecting
    a downloaded bulletin to find the relevant sheet."""

def list_indicators(xlsx_bytes: bytes, sheet_name: str) -> list[str]:
    """Return every indicator label found in column B (or wherever the labels
    live) on the given sheet. Use this to discover what series are inside
    before trying to read one."""

def read_series(xlsx_bytes: bytes, sheet_name: str, indicator: str) -> dict[str, float]:
    """Return {date_label: value} for a named indicator on a sheet.
    `indicator` is a substring match (case-insensitive) against the labels in
    column B. Date labels come from the English row of headers (typically
    row 6). Values in millions of AED unless the sheet header says otherwise.

    Raises KeyError if the indicator is not found on the sheet (suggesting
    you call list_indicators first)."""

def read_full_history(xlsx_bytes: bytes, iso_dates: bool = True) -> dict[str, dict[str, float]]:
    """Wide-format reader for the Banking Operations Statistics XLSX, which is
    a single sheet with End-of-Month rows × ~12 columns of cash-operations
    metrics (Coins/Notes/Total deposits, withdrawals, cheques, FTS). Returns
    {column_label: {date_label: value}}. 7-year monthly window: Jan 2019
    through the latest published month."""
```

## Return shapes

```python
# parse_bulletin_index
{
  "Statistical Bulletin - Banking & Monetary Statistics": [
    {"month": "April 2026", "xlsx_url": "https://www.centralbank.ae/media/iq1hjwzp/statistical-bulletin-april-2026.xlsx",
     "pdf_url": "https://www.centralbank.ae/media/03uh1djh/statistical-bulletin-april-2026.pdf"},
    {"month": "March 2026", ...},
    {"month": "February 2026", ...},
  ],
  "Banking Operations Statistics": [
    {"month": "April 2026", "xlsx_url": "https://www.centralbank.ae/media/ikcdbmbl/monthly-banking-operations-statisitics-2019-2026-_apr-2026.xlsx",
     "pdf_url": "..."},
  ],
  "Core Financial Soundness Indicators (Core FSI)": [
    {"month": "Q1 2026", "xlsx_url": "...", "pdf_url": "..."},
  ],
  "UAE Banking Indicators - Conventional vs Islamic": [...],
  "UAE Banking Indicators - National vs Foreign": [...],
  "UAE Banking Indicators by Emirate": [...],
}

# read_series — e.g. for "Money Supply M2" on the Selected Indicators sheet
{
  "Apr 2025": 2435625.052,
  "May 2025": 2473974.580,
  "Jun 2025": 2531165.122,
  ...
  "Feb 2026": 2823514.671,
}
```

## Implementation

```python
import json
import os
import urllib.request, urllib.parse
import openpyxl
import io
import re
from typing import Optional

UA = "Mozilla/5.0 (compatible; AxionAgent/1.0)"


def _firecrawl_proxy_base() -> str:
    return os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/firecrawl-proxy")


def _firecrawl_scrape(url: str, *, timeout_s: int = 120,
                      formats: list[str] | None = None) -> str:
    body = {
        "url": url,
        "formats": formats or ["rawHtml"],
        "timeout": (timeout_s - 10) * 1000,
    }
    req = urllib.request.Request(
        _firecrawl_proxy_base().rstrip("/") + "/v1/scrape",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['PROXY_API_KEY']}",
            "Content-Type": "application/json",
            "User-Agent": UA,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as r:
        resp = json.loads(r.read().decode())
    if not resp.get("success"):
        raise RuntimeError(f"Firecrawl failed for {url}: {resp.get('error','no error msg')[:200]}")
    data = resp.get("data") or {}
    return data.get("rawHtml") or data.get("markdown") or ""


def _fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def _open_xlsx(data: bytes):
    return openpyxl.load_workbook(io.BytesIO(data), data_only=True, read_only=True)


# Patterns observed on CBUAE's /media/ URLs.
_XLSX_RE = re.compile(r'(?:href=")?(https?://www\.centralbank\.ae/media/[^"\s)]+\.xlsx)', re.I)
_PDF_RE  = re.compile(r'(?:href=")?(https?://www\.centralbank\.ae/media/[^"\s)]+\.pdf)', re.I)

_DATASET_HINTS = {
    "Statistical Bulletin - Banking & Monetary Statistics":
        re.compile(r"statistical-bulletin-([a-z]+-\d{4})", re.I),
    "Banking Operations Statistics":
        re.compile(r"monthly-banking-operations[^/]*_([a-z]+-\d{2,4})", re.I),
    "Core Financial Soundness Indicators (Core FSI)":
        re.compile(r"core-financial-soundness-indicators-([a-z0-9-]+-\d{4})", re.I),
    "UAE Banking Indicators - Conventional vs Islamic":
        re.compile(r"uae_cb_ib_([a-z]+-\d{2,4})", re.I),
    "UAE Banking Indicators - National vs Foreign":
        re.compile(r"uae_nb_fb_([a-z]+-\d{2,4})", re.I),
    "UAE Banking Indicators by Emirate":
        re.compile(r"uae_emirate_([a-z]+-\d{2,4})", re.I),
}


_LANDING_URL = "https://www.centralbank.ae/en/research-and-statistics/"


def fetch_bulletin_index() -> dict:
    """One-call discovery: scrape the CBUAE research-and-statistics landing
    page through the backend Firecrawl proxy and parse it into the bulletin
    index. Returns the same shape as parse_bulletin_index()."""
    rawhtml = _firecrawl_scrape(_LANDING_URL, formats=["rawHtml"])
    return parse_bulletin_index(rawhtml)


def parse_bulletin_index(markdown_or_html: str) -> dict:
    """Scan Firecrawl-scraped landing-page text for /media/ XLSX URLs and
    bucket them by dataset using filename patterns. Also pairs each XLSX with
    its PDF sibling if both are present. Entries within each dataset are
    sorted ascending by date so callers can use `entries[-1]` for the newest
    bulletin regardless of URL-hash alphabetization."""
    text = markdown_or_html
    # Make URLs absolute. Some Firecrawl outputs strip the scheme; restore it.
    text = re.sub(r"(?<![:\w])(/media/[^\s\"')]+)", r"https://www.centralbank.ae\1", text)

    xlsx_urls = set(_XLSX_RE.findall(text))
    pdf_urls = set(_PDF_RE.findall(text))

    out: dict = {name: [] for name in _DATASET_HINTS}

    seen_keys = {name: set() for name in _DATASET_HINTS}

    for xlsx in sorted(xlsx_urls):
        for name, pat in _DATASET_HINTS.items():
            m = pat.search(xlsx)
            if not m:
                continue
            key = m.group(1).lower()
            if key in seen_keys[name]:
                continue
            seen_keys[name].add(key)
            # Find a matching PDF in the same dataset bucket (by key substring).
            pdf_match = next((p for p in pdf_urls if pat.search(p) and pat.search(p).group(1).lower() == key), None)
            out[name].append({"month": _humanize_month(key), "xlsx_url": xlsx, "pdf_url": pdf_match,
                              "_sort_key": _bulletin_sort_key(key)})
            break

    # Sort each dataset ascending by real date so [-1] is the newest, then
    # strip the internal _sort_key field. Without this the order is the
    # alphabetical order of the random /media/<hash>/ prefixes.
    result: dict = {}
    for k, v in out.items():
        if not v:
            continue
        v.sort(key=lambda e: e["_sort_key"])
        for e in v:
            del e["_sort_key"]
        result[k] = v
    return result


_FILENAME_MONTHS = {
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}


def _bulletin_sort_key(filename_key: str) -> tuple:
    """Convert the dataset-hint capture (e.g. 'april-2026', 'apr-26', 'q1-2026')
    into a (year, month) tuple for ascending-by-date sorting."""
    s = filename_key.lower()
    # Quarter: 'q1-2026' → (2026, 3) [end-of-quarter month]
    qm = re.match(r"q(\d)-?(\d{2,4})", s)
    if qm:
        y = int(qm.group(2))
        if y < 100:
            y += 2000
        return (y, int(qm.group(1)) * 3)
    # Month: 'april-2026' or 'apr-26' → (2026, 4)
    fm = re.match(r"([a-z]+)-?(\d{2,4})", s)
    if fm:
        mon = _FILENAME_MONTHS.get(fm.group(1))
        if mon:
            y = int(fm.group(2))
            if y < 100:
                y += 2000
            return (y, mon)
    return (0, 0)


def _humanize_month(key: str) -> str:
    """Turn 'april-2026' or 'apr-26' or 'q1-2026' into 'April 2026' / 'Q1 2026'."""
    key_low = key.lower()
    # Quarter
    qm = re.match(r"q(\d)-?(\d{4})", key_low)
    if qm:
        return f"Q{qm.group(1)} {qm.group(2)}"
    # Full month name
    months_full = {"january": "January", "february": "February", "march": "March", "april": "April",
                   "may": "May", "june": "June", "july": "July", "august": "August",
                   "september": "September", "october": "October", "november": "November",
                   "december": "December"}
    months_short = {"jan": "January", "feb": "February", "mar": "March", "apr": "April",
                    "may": "May", "jun": "June", "jul": "July", "aug": "August",
                    "sep": "September", "oct": "October", "nov": "November", "dec": "December"}
    fm = re.match(r"([a-z]+)-?(\d{2,4})", key_low)
    if fm:
        m_str, y_str = fm.group(1), fm.group(2)
        full = months_full.get(m_str) or months_short.get(m_str) or m_str.title()
        if len(y_str) == 2:
            y_str = "20" + y_str
        return f"{full} {y_str}"
    return key


def download_bulletin(xlsx_url: str) -> bytes:
    return _fetch_bytes(xlsx_url)


def list_sheets(xlsx_bytes: bytes) -> list[str]:
    return list(_open_xlsx(xlsx_bytes).sheetnames)


_LABEL_COLS = (2, 3, 1)  # columns to scan for indicator labels (1-based: B, C, A)


def list_indicators(xlsx_bytes: bytes, sheet_name: str,
                    label_cols: tuple = _LABEL_COLS) -> list[str]:
    """Walk the candidate label columns (B, C, A by default) and return every
    non-empty label string. The bulletin format is inconsistent: some sheets
    put indicator labels in column B, others use B for section headers and
    put the indicators in column C. Scanning all three columns is safer
    than guessing per-sheet.

    Labels are returned with embedded newlines collapsed and trailing
    whitespace stripped. The returned list deduplicates while preserving
    first-seen order."""
    wb = _open_xlsx(xlsx_bytes)
    sheet_name = _resolve_sheet(wb, sheet_name)
    ws = wb[sheet_name]
    out, seen = [], set()
    for row in ws.iter_rows(min_row=1, values_only=True):
        for c in label_cols:
            if c - 1 < len(row):
                v = row[c - 1]
                if isinstance(v, str):
                    s = _clean(v)
                    if s and not s.startswith("(") and s not in seen:
                        seen.add(s)
                        out.append(s)
    return out


def read_series(xlsx_bytes: bytes, sheet_name: str, indicator: str,
                label_cols: tuple = _LABEL_COLS,
                header_row: int | None = None,
                iso_dates: bool = True) -> dict[str, float]:
    """Find the row whose label (in any of the candidate label columns) matches
    `indicator` (substring, case-insensitive) and return `{date_label: value}`.

    Date labels are normalized to ISO form by default: 'Apr 2026 *' → '2026-04',
    'Q1 2026' → '2026-Q1'. Pass `iso_dates=False` to keep the original
    bulletin labels verbatim (e.g. 'Apr 2026 *').

    The English date headers live in row 6 of standard bulletin sheets; the
    Arabic headers in row 5. We auto-detect by scanning rows 4-8 for the row
    whose cells most look like English month tokens.

    If multiple rows match the substring, the first one wins — use a longer
    or more specific substring to disambiguate (e.g. 'Money Supply M2' rather
    than 'M2', or 'Conventional Banks Total Assets' rather than 'Total
    Assets' on a sheet that has multiple bank-type subsections)."""
    wb = _open_xlsx(xlsx_bytes)
    sheet_name = _resolve_sheet(wb, sheet_name)
    ws = wb[sheet_name]
    rows = list(ws.iter_rows(values_only=True))

    if header_row is None:
        header_row = _detect_english_header_row(rows)
    if header_row is None:
        raise ValueError(f"Could not locate English date-header row on '{sheet_name}'.")

    headers = rows[header_row - 1]
    pattern = re.compile(re.escape(indicator), re.I)

    indicator_row_idx = None
    for i, row in enumerate(rows):
        for c in label_cols:
            if c - 1 < len(row):
                v = row[c - 1]
                if isinstance(v, str) and pattern.search(_clean(v)):
                    indicator_row_idx = i
                    break
        if indicator_row_idx is not None:
            break

    if indicator_row_idx is None:
        raise KeyError(f"Indicator matching '{indicator}' not found on '{sheet_name}'. "
                       f"Call list_indicators() to discover available labels.")

    data_row = rows[indicator_row_idx]
    out: dict = {}
    for j, header in enumerate(headers):
        if not isinstance(header, str):
            continue
        h = _clean(header)
        # Accept three header shapes:
        #   'Apr 2026' / 'Apr-26'      — monthly (Statistical Bulletin)
        #   'Q1 2026'  / 'Q1-2026'     — quarterly, Q-first
        #   '2026Q1'                   — quarterly, year-first (Core FSI)
        if not re.match(r"^(?:\d{4}Q\d|Q\d[\s-]?\d{2,4}|\w{3,9}[\s-]?\d{2,4})", h):
            continue
        val = data_row[j] if j < len(data_row) else None
        if val is None:
            continue
        key = _normalize_date(h) if iso_dates else h.rstrip(" *")
        out[key] = float(val) if isinstance(val, (int, float)) else val
    return out


_QUARTER_YEAR_RE = re.compile(r"^\d{4}Q\d$", re.I)


def _detect_english_header_row(rows: list) -> int | None:
    """Find the row index (1-based) whose cells most look like date headers.
    Recognises both 'Apr 2025'-style English month tokens and '2026Q1'-style
    year-first quarterly tokens (Core FSI sheets)."""
    month_tokens = {"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"}
    best = (0, None)
    for i, row in enumerate(rows[:12], start=1):
        score = 0
        for c in row:
            if not isinstance(c, str):
                continue
            lo = c.strip().lower()
            if lo[:3] in month_tokens and re.search(r"\d{2,4}", lo):
                score += 1
            elif _QUARTER_YEAR_RE.match(c.strip()):
                score += 1
        if score > best[0]:
            best = (score, i)
    return best[1] if best[0] >= 3 else None


_MONTH_LABEL_RE = re.compile(
    r"^(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[\s-]\d{2,4}$", re.I
)


def read_full_history(xlsx_bytes: bytes, iso_dates: bool = True) -> dict[str, dict[str, float]]:
    """For the Banking Operations Statistics XLSX (single sheet, rows = months,
    columns = metric categories). Returns {column_label: {month_label: value}}.

    The file ships with a sparse header layout: row 3 carries top-level group
    headers ("Cash Deposits at the Central Bank of the UAE (in AED)", "Cash
    Withdrawals From the Central Bank of the UAE (in AED)", "Image Cheque
    Clearing System (ICCS) Report", "UAE Fund Transfer System (FTS)"), each
    spanning multiple columns; row 4 carries sub-headers ("Coins", "Notes",
    "Total", "Number of Cheques Cleared", ...). The date column ("End of
    Month") lives in column B, not column A — we auto-detect by scanning the
    first data row for the first cell that matches a month-token pattern.
    """
    wb = _open_xlsx(xlsx_bytes)
    sn = wb.sheetnames[0]
    ws = wb[sn]
    rows = list(ws.iter_rows(values_only=True))

    # Find the header rows: the GROUP-header row carries the date-column label;
    # the SUB-header row immediately follows. CBUAE labels this cell as either
    # "End of Month" (April 2026 onward) or plain "Month" (older vintages).
    group_hdr_idx = None
    for i, row in enumerate(rows[:8]):
        for c in row:
            if isinstance(c, str) and c.strip().lower() in ("end of month", "month"):
                group_hdr_idx = i
                break
        if group_hdr_idx is not None:
            break
    if group_hdr_idx is None:
        raise ValueError("Could not locate group-header row (no 'End of Month' or 'Month' label found in first 8 rows).")
    sub_hdr_idx = group_hdr_idx + 1
    group_hdr = rows[group_hdr_idx]
    sub_hdr = rows[sub_hdr_idx] if sub_hdr_idx < len(rows) else ()

    # Auto-detect the date column from the first data row (group_hdr_idx + 2).
    data_start = group_hdr_idx + 2
    date_col = None
    for i, row in enumerate(rows[data_start:data_start + 3]):
        for j, c in enumerate(row):
            if isinstance(c, str) and _MONTH_LABEL_RE.match(c.strip()):
                date_col = j
                break
        if date_col is not None:
            break
    if date_col is None:
        raise ValueError("Could not locate date column (no month-token cell found in first 3 data rows).")

    # Build composite column labels, treating the date column as labelled "_date"
    # so we know to skip it.
    n_cols = max(len(group_hdr), len(sub_hdr))
    composite: list = []
    last_group = ""
    for i in range(n_cols):
        if i == date_col:
            composite.append("_date")
            continue
        g = group_hdr[i] if i < len(group_hdr) and isinstance(group_hdr[i], str) else None
        s = sub_hdr[i] if i < len(sub_hdr) and isinstance(sub_hdr[i], str) else None
        # The date-column anchor in the group header is either "End of Month"
        # or plain "Month" depending on bulletin vintage; ignore both so they
        # don't bleed into adjacent column labels.
        if g and _clean(g) and _clean(g).lower() not in ("end of month", "month"):
            last_group = _clean(g)
        label = f"{last_group} — {_clean(s)}" if s and _clean(s) else last_group
        composite.append(label)

    out: dict = {label: {} for label in composite if label and label != "_date"}
    for row in rows[data_start:]:
        if not row or date_col >= len(row):
            continue
        date_cell = row[date_col]
        if date_cell is None:
            continue
        date_label = str(date_cell).strip()
        if not date_label or not _MONTH_LABEL_RE.match(date_label):
            continue
        key = _normalize_date(date_label) if iso_dates else date_label
        for i, val in enumerate(row):
            if i >= len(composite):
                continue
            label = composite[i]
            if not label or label == "_date" or val is None:
                continue
            if isinstance(val, (int, float)):
                out[label][key] = float(val)
    return {k: v for k, v in out.items() if v}
```

## Examples

### End-to-end: latest M1 / M2 / M3 print

```python
# Step 1: discover current bulletin URLs (one Firecrawl proxy call).
index = fetch_bulletin_index()
sb = index["Statistical Bulletin - Banking & Monetary Statistics"][-1]   # most recent
print(f"Latest bulletin: {sb['month']}")

# Step 2: download the XLSX (no auth, direct).
xlsx = download_bulletin(sb["xlsx_url"])

# Step 3: pull the monetary aggregates. Sheet name uses fuzzy resolution,
# so '1-Sel Ind' works the same as the bulletin's literal '1-Sel Ind ' (trailing space).
for ind in ["Money Supply M1", "Money Supply M2", "Money Supply M3"]:
    series = read_series(xlsx, "1-Sel Ind", ind)
    latest = list(series)[-1]
    print(f"  {ind} ({latest}): AED {series[latest]/1000:.1f}B")
# Example output (validated against the April 2026 bulletin):
#   Money Supply M1 (2026-04): AED 1064.3B
#   Money Supply M2 (2026-04): AED 2870.4B
#   Money Supply M3 (2026-04): AED 3407.7B
# Note ISO-style date keys ('2026-04') — pass iso_dates=False to read_series
# if you need the original 'Apr 2026 *' labels back.
```

### Central Bank balance sheet and gross reserves

```python
ws = "1-Sel Ind "  # the bulletin's main summary sheet
tot_assets = read_series(xlsx, ws, "Total Assets/Liabilities")
gross_res = read_series(xlsx, ws, "Gross International Reserves")
for m in list(tot_assets)[-6:]:
    print(f"  {m}: CB Assets AED {tot_assets[m]/1000:.1f}B, Gross Reserves AED {gross_res[m]/1000:.1f}B")
```

### Banking sector aggregates by bank type — Conventional vs Islamic

```python
# Conventional vs Islamic split sheets:
list_indicators(xlsx, "10 CB & IB Asts")
# Returns labels like: "Cash and Balances with CBUAE", "Total Loans and Advances",
#   "Total Assets", "Total Liabilities", "Total Capital and Reserves", ...

cb_ib = read_series(xlsx, "10 CB & IB Asts", "Total Assets")
# cb_ib has separate sub-rows for Conventional and Islamic; both will match by
# substring. To disambiguate, use a longer indicator string like
# "Conventional Banks Total Assets" or "Islamic Banks Total Assets" once you
# see what labels list_indicators returned.
```

### By emirate — Abu Dhabi / Dubai / Other Emirates

```python
list_indicators(xlsx, "16 UAE_BI_Emirate_AD_DXB_OE")
# Returns sectoral indicators split by emirate. The sheet groups three
# parallel sub-tables; pick the indicator and emirate column from the row
# labels, e.g. "Abu Dhabi Total Assets", "Dubai Total Assets".
```

### Tier 2 — 7-year monthly Banking Operations history

The Banking Operations XLSX is a single 31KB file that holds Jan 2019 → current
month for the full set of cash-operations metrics. Use it directly for any
banking-system trend question.

```python
bo = index["Banking Operations Statistics"][0]
print(f"Banking Operations through {bo['month']}")
bo_bytes = download_bulletin(bo["xlsx_url"])

history = read_full_history(bo_bytes)
print(f"Metrics available: {list(history.keys())[:6]}")
# e.g. ['Cash Deposits — Coins', 'Cash Deposits — Notes', 'Cash Deposits — Total',
#       'Cash Withdrawals — Coins', 'Cash Withdrawals — Notes', 'Cash Withdrawals — Total']

deposits = history["Cash Deposits — Total"]
months = list(deposits)
print(f"  Date range: {months[0]} through {months[-1]}  ({len(months)} months)")
# → Date range: Jan 19 through Apr-26  (88+ months — 7+ years)

# Trend: compute YoY change for the last 12 months.
print("  Last 12 months cash deposits (AED B):")
for m in months[-12:]:
    print(f"    {m}: AED {deposits[m]/1e9:.2f}B")
```

### Core Financial Soundness Indicators (quarterly)

```python
fsi = index["Core Financial Soundness Indicators (Core FSI)"][0]
fsi_bytes = download_bulletin(fsi["xlsx_url"])
print(list_sheets(fsi_bytes))
# Typically: 'Selected Indicators', 'Capital Adequacy', 'Asset Quality',
#            'Earnings and Profitability', 'Liquidity'
# Use read_series with the FSI metric name (Capital Adequacy Ratio, NPL Ratio,
# Return on Assets, etc.) — same call shape as the Statistical Bulletin.
```

## Statistical Bulletin sheet directory

**Vintage caveat.** CBUAE renames and reorganises sheets between bulletin
vintages. The April 2026 bulletin has 41 sheets with the names below; the
February 2026 vintage had 60 sheets with a different naming scheme (e.g.
`9 NB Asts` / `11 FB Asts` split where April uses `8 NB & FB Asts`). Always
call `list_sheets(xlsx_bytes)` first on a freshly downloaded file — that is
the source of truth, the table below is only the current snapshot.

Each April 2026 bulletin XLSX contains 41 sheets. Quick reference:

| Sheet | What it carries |
|---|---|
| `1-Sel Ind ` | Headline mix — CB balance sheet, gross reserves, M1/M2/M3, bank total assets, foreign asset/liability ratios |
| `2 Mon Survey` | Monetary Survey (net foreign assets, net domestic assets, broad money components) |
| `3 Mon Base` | Monetary base (currency in circulation, bank reserves at CBUAE) |
| `4 CB BS` | Central Bank balance sheet — full breakdown of CB assets and liabilities |
| `5 CB Intnl Res` | Central Bank international reserves — gold, foreign currency, SDRs |
| `6 Bank Asts` / `7 Bank Liab` | Banking sector consolidated assets / liabilities |
| `8 NB & FB Asts` / `9 NB & FB Liab` | Split: National Banks vs Foreign Banks |
| `10 CB & IB Asts` / `11 CB & IB Liab` | Split: Conventional vs Islamic |
| `12 Memo` | Memo items |
| `13 UAE_BI_All` | UAE Banking Indicators — full system |
| `14 UAE_BI_Natnl_Fgn_Banks` | Banking Indicators by National vs Foreign |
| `15 UAE_BI_Conv_Islamic_Banks` | Banking Indicators by Conventional vs Islamic |
| `16 UAE_BI_Emirate_AD_DXB_OE` | Banking Indicators by Emirate (AD/DXB/Other) |
| `17 Fgn Ast-Liab` | Foreign assets and liabilities (consolidated) |
| `18 NB & FB Fgn Ast-Liab` / `19 CB & IB Fgn Ast-Liab` | Foreign positions by bank type |
| `20 Dom Crd` | Domestic credit (total) |
| `21 NB & FB Dom Crd` / `22 CB & IB Dom Crd` | Domestic credit by bank type |
| `23 Res Crd by Act` | Resident credit by economic activity (quarterly: real estate, construction, manufacturing, services, ...) |
| `24 Non Res Crd by Act` | Non-resident credit by activity |
| `25 Dep` | Total deposits |
| `26 NB & FB Dep` / `27 CB & IB Dep` | Deposits by bank type |
| `28 Dep by Size` | Deposit distribution by ticket size |
| `29 Dep by Cy` | Deposits by currency (AED vs FX) |
| `30 NB & FB Dep by Cy` / `31 CB & IB Dep by Cy` | Currency split by bank type |
| `32 Time Dep` and `33-34` | Time deposits, total and by bank type |
| `35 Currency ` | Currency in circulation |
| `36 Cheques` | Cheque clearing volumes and values |
| `37 FTS` | Funds Transfer System (UAEFTS) volumes |
| `38 Branch NW` | Bank branch network — count by emirate |

Most sheets carry a **rolling 13-month window** ending in the bulletin's reference month (the latest column is marked with `*` as preliminary). Sheet `23 Res Crd by Act` and similar quarterly sheets carry **5 quarters**. The Banking Operations XLSX (a separate file, not in the bulletin) carries the full **7-year monthly history**.

## Coverage and freshness

- **Statistical Bulletin** — monthly cadence, published with ~2-month lag (April 2026 bulletin contains data through February 2026 with March 2026 as a preliminary `*` column).
- **Banking Operations Statistics** — monthly cadence, ~1-month lag (April 2026 file ships through April 2026 itself).
- **Core Financial Soundness Indicators** — quarterly, ~3-month lag (Q1 2026 file ships in late Q2).
- **Banking Indicators by bank type / emirate** — monthly, ~3-month lag (February 2026 file is the latest at the time of writing).

Compared with Finnhub's UAE macro feed, where CPI is stuck at 2023-12-31 and 8-year-old series exist, CBUAE is the only path to fresh UAE monetary/banking data.

## Archive depth

- **Forward-looking** — each new bulletin carries ~12 months of history in its summary sheets and a longer rolling window in some subsheets.
- **Backward-looking** — the public site only links the most recent 2–3 months of each dataset. There is **no flat archive index** for historical bulletins; per-month landing pages exist at predictable URL slugs (`/.../statistical-bulletin-january-2024/`) but are Cloudflare-gated and not discoverable except by guessing.
- **Workaround for historical depth** — the **Banking Operations XLSX is multi-year by construction** (Jan 2019 → current). For any banking-system question with a "trend since 2019" angle, this single file is the answer.
- **For trends pre-2019 or for older Statistical Bulletin snapshots**, the WAM wire announces each monthly release as a dated article (`search_news` on `CBUAE issues monetary and banking developments`) — the agent can use WAM to enumerate the announcement timeline and then ask the user to retrieve a specific historical bulletin if absolutely needed.

## Usage rules

- **Two-step discovery + download.** Step 1 is `fetch_bulletin_index()` — routes a `rawHtml` scrape through the backend Firecrawl proxy (`PROXY_BASE_URL` / `PROXY_API_KEY`) and parses it. Step 2 calls `download_bulletin` on each XLSX URL. Do NOT call urllib directly on the HTML landing page — it returns Cloudflare 403.
- **Direct urllib on `/media/<hash>/<file>.xlsx` is fine** — no auth, no headers, no Cloudflare on the data files themselves. The skill helpers use only stdlib + openpyxl + the proxy for the landing page.
- **All AED values in millions** unless the sheet's `(In Millions of AED)` header says otherwise. Divide by `1000` to get billions for headline reporting (e.g. `M2 ≈ AED 2823B`), and **always quote the as-of month** since CBUAE prints recent months as preliminary (`*` suffix).
- **Use list_indicators first** when reading from a sheet you have not used before — sheet labels can have minor wording variations across bulletin vintages, and the substring match on `read_series` will pick the first row matching your substring. Confirm the label before quoting a number.
- **Currency conversion.** USD/AED is pegged at 3.6725 since 1997. Multiply AED values by 0.27225 to get a USD comparison. Quote AED first in any user-facing field; USD is supplementary.
- **Do NOT call this skill for rate decisions or policy announcements.** Those are in the `wam` skill (`search_cbuae_policy`). This skill is for structured time series only.
