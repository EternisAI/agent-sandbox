---
name: data-dubai
description: >-
  Query the Dubai open-data portal (data.dubai, run by the Dubai Data & Statistics Establishment). 617 government datasets across 11 themes and 76 issuing entities (RTA, Dubai Municipality, Customs, DLD, Police, DEWA, DHA, KHDA). Search or browse the catalog, read a dataset's schema and config, pull a quick row preview, or download the FULL dataset (uncapped) as parsed rows. Reverse-engineered from the portal's own Liferay backend, so no API key, no login, no vendor credentials. Use when users ask about Dubai/UAE government statistics: trade, licensing, population, transport, prices, employment, courts, utilities, and more.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# data.dubai Open Data

Direct HTTP wrapper around the public backend behind `data.dubai`, the Dubai Data & Statistics Establishment (DDSE) portal. It runs on Liferay, and everything below hits the same guest endpoints the browser UI uses. No API key, no login. Two backends:

- **Liferay headless catalog** (`/o/c/…`): dataset records, themes, subthemes, issuing entities. Supports full-text `search`, OData `filter`, `sort`, `fields`, and paging.
- **DDSE data-services** (`/o/dda/data-services/…`): per-dataset `pagination-config` (including the `isOpen` gate), an inline row **preview** (server-capped near 7000 rows), and **full-dataset download** through presigned `cdn.data.dubai` `.csv.gz` / `.json.gz` links. The download is uncapped; verified on a 527k-row dataset.

**How it connects.** `data.dubai` and `cdn.data.dubai` sit behind an F5 WAF that rejects requests by source-IP reputation (AWS/cloud egress gets an HTML "Request Rejected" page even on HTTP 200), so every call is routed through the Axion backend, which forwards it out via a UAE egress. Two env vars, set for you inside the sandbox, drive this — you never build either value:

- **`PROXY_BASE_URL`** — the backend base (`…/api/llm-proxy`); the helper swaps the suffix to `…/api/dubaidata-proxy` to get the Dubai-data route.
- **`PROXY_API_KEY`** — the per-thread bearer token, sent as `Authorization: Bearer <token>`.

If either is unset the helper raises immediately — this skill only works inside an Axion sandbox. No `data.dubai` credential is ever involved (the portal itself is keyless); the bearer authenticates the sandbox to the backend, not to Dubai.

**Access gate.** A dataset's `pagination-config.isOpen`. 616 of 617 datasets are open. The closed one returns the F5 WAF "Request Rejected" page instead of data and needs the separate Dubai Pulse API-key channel, which this skill does not use. `download_files()` and `fetch_dataset()` check the gate first and raise `RestrictedDatasetError` instead of handing back a WAF page.

**Data shapes.** CSV downloads parse with `csv.DictReader`. JSON comes two ways: small datasets as a pretty-printed array, large ones as NDJSON. `fetch_dataset(fmt="json")` handles both.

## Helper

Save as `data_dubai.py` (or paste inline) and import it. Pure stdlib, no dependencies.

```python
"""data.dubai open-data helper: keyless access to Dubai Data & Statistics
Establishment (DDSE) open datasets via the portal's own Liferay backend."""
import csv as _csv
import gzip
import io
import json
import os
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://data.dubai"
_UA = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
    "Accept": "application/json",
}


class DataDubaiError(RuntimeError):
    pass


class RestrictedDatasetError(DataDubaiError):
    """Dataset is not open (isOpen=false); needs the API-key path."""


def _backend_base() -> str:
    """The backend's Dubai-data proxy route, derived from PROXY_BASE_URL exactly
    like every other Axion data tool. The backend forwards each call out through a
    UAE egress; data.dubai sits behind an F5 WAF that rejects non-UAE source IPs,
    so the sandbox never reaches it directly and no egress credential is ever
    exposed to the sandbox."""
    base = os.environ.get("PROXY_BASE_URL")
    if not base:
        raise DataDubaiError(
            "PROXY_BASE_URL is not set. data.dubai is IP-restricted (its F5 WAF "
            "rejects non-UAE addresses) and is reached through the Axion backend "
            "proxy — this skill only works inside an Axion sandbox.")
    return base.rstrip("/").replace("/api/llm-proxy", "/api/dubaidata-proxy")


def _token() -> str:
    tok = os.environ.get("PROXY_API_KEY")
    if not tok:
        raise DataDubaiError("PROXY_API_KEY is not set; cannot authenticate to the Axion backend proxy.")
    return tok


def _proxied(target: str) -> str:
    """Rewrite an upstream data.dubai / cdn.data.dubai URL to its backend-proxy
    path: 'https://data.dubai/o/c/datasets?x=1' -> '<backend>/data.dubai/o/c/datasets?x=1'.
    Query string (incl. CDN presigned signatures) is preserved verbatim."""
    u = urllib.parse.urlsplit(target)
    out = f"{_backend_base()}/{u.netloc}{u.path}"
    return out + ("?" + u.query if u.query else "")


def _raw(url, timeout=40, headers=None, max_retries=3, base_delay=1.0):
    """GET with retry on 429/5xx/timeout. Returns (status, bytes).
    Routed through the Axion backend Dubai-data proxy (UAE egress); the per-thread
    PROXY_API_KEY is attached as a Bearer token. Detects the F5 WAF 'Request
    Rejected' interstitial and raises DataDubaiError, since it comes back as
    HTTP 200 and would otherwise look like success."""
    h = dict(_UA)
    h.update(headers or {})
    h["Authorization"] = "Bearer " + _token()
    url = _proxied(url)
    last = None
    for attempt in range(max_retries + 1):
        try:
            req = urllib.request.Request(url, headers=h)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
                code = r.getcode()
                gzipped = r.headers.get("Content-Encoding") == "gzip"
            if gzipped:
                data = gzip.decompress(data)
            if b"The requested URL was rejected" in data[:600]:
                raise DataDubaiError(
                    "Blocked by data.dubai WAF (Request Rejected). Space out requests "
                    "and retry; this fires under rapid sequential access.")
            return code, data
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (429,) or 500 <= e.code < 600:
                if attempt < max_retries:
                    ra = e.headers.get("Retry-After") if e.headers else None
                    try:
                        delay = float(ra) if ra else base_delay * (2 ** attempt)
                    except ValueError:
                        delay = base_delay * (2 ** attempt)
                    time.sleep(max(delay, 1.0))
                    continue
            return e.code, e.read()
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt))
                continue
            raise DataDubaiError(f"Network error reaching {url}: {e}")
    raise DataDubaiError(f"Failed after retries: {last}")


def _get_json(url, timeout=40):
    code, data = _raw(url, timeout=timeout)
    try:
        obj = json.loads(data)
    except Exception:
        raise DataDubaiError(f"Non-JSON response ({code}) from {url}: {data[:200]!r}")
    return code, obj


# ---------------------------------------------------------------- catalog

def search_datasets(query=None, theme=None, entity_erc=None, sort=None,
                    take=20, skip=0, fields=None):
    """Search/browse the open-data catalog (617 datasets).

    query      full-text search (title/description/keywords)
    theme      exact theme filter, e.g. 'Trade' (see list_themes())
    entity_erc issuing-entity externalReferenceCode (see list_entities())
    sort       e.g. 'dateModified:desc'
    take       max rows to return (server caps a page at 100)
    skip       row offset; any value, not just multiples of take
    fields     restrict returned fields, e.g. 'id,title,themes'

    Returns {'total': int, 'items': [ {id,title,datasetName,themes,...}, ... ]}.
    """
    base_params = {}
    filt = []
    if theme:
        filt.append(f"themes eq '{theme}'")
    if entity_erc:
        filt.append(f"r_issuingEntityOfDataset_c_issuingEntityERC eq '{entity_erc}'")
    if filt:
        base_params["filter"] = " and ".join(filt)
    if query:
        base_params["search"] = query
    if sort:
        base_params["sort"] = sort
    if fields:
        base_params["fields"] = fields

    # The server paginates by page, not by arbitrary offset, so honor skip by
    # fetching the pages that span [skip, skip+take) and dropping the leading
    # remainder. Non-aligned skip just costs one extra page fetch at most.
    page_size = min(take, 100) if take else 100
    first_page = (skip // page_size) + 1
    lead = skip % page_size
    wanted = lead + take if take else None
    collected = []
    total = None
    page = first_page
    while True:
        params = dict(base_params, page=page, pageSize=page_size)
        url = f"{BASE}/o/c/datasets?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
        code, d = _get_json(url)
        if code != 200 or not isinstance(d, dict):
            raise DataDubaiError(f"catalog query failed ({code})")
        if total is None:
            total = d.get("totalCount")
        batch = d.get("items", [])
        collected.extend(batch)
        if wanted is None or len(collected) >= wanted or len(batch) < page_size:
            break
        page += 1
    items = collected[lead:wanted] if take else collected[lead:]
    return {"total": total, "items": items}


def get_dataset(dataset_id):
    """Full catalog record for one dataset (title, datasetName, themes, source,
    format, update frequency, dataAPIEndpoints, download counts, issuing entity)."""
    did = urllib.parse.quote(str(dataset_id), safe="")
    code, d = _get_json(f"{BASE}/o/c/datasets/{did}")
    if code != 200 or not isinstance(d, dict) or "id" not in d:
        raise DataDubaiError(f"dataset {dataset_id} not found ({code})")
    return d


# ---------------------------------------------------------------- citation

PORTAL = "Dubai Data & Statistics Establishment (DDSE) open-data portal, data.dubai"

_ENTITY_NAME_BY_ERC = {}


def _clean(s):
    """Strip the invisible mojibake some portal titles carry — trailing
    zero-width joiners and stray combining marks (seen e.g. on the DDSE entity
    name) that would render as tofu in a citation. Drops format/control chars
    anywhere and combining marks left dangling at the end, while keeping
    legitimate interior diacritics (Arabic entity names)."""
    s = "".join(c for c in s if unicodedata.category(c)[0] != "C").strip()
    while s and unicodedata.category(s[-1])[0] == "M":
        s = s[:-1]
    return s.strip()


def _entity_name(erc):
    """Resolve an issuing-entity ERC to its display name, caching the 76-row
    entity list after the first lookup. A dataset record carries only the
    issuing-entity ERC (r_issuingEntityOfDataset_c_issuingEntityERC), never the
    name, so a citation that names the publisher has to join through
    list_entities()."""
    if not erc:
        return ""
    if not _ENTITY_NAME_BY_ERC:
        for e in list_entities():
            if e.get("erc"):
                _ENTITY_NAME_BY_ERC[e["erc"]] = e.get("name") or ""
    return _ENTITY_NAME_BY_ERC.get(erc, "")


def citation(dataset, entity_name=None):
    """Build the source line to attribute a figure to. Pass a dataset record
    (from get_dataset() or a search item) or a bare dataset id.

    Cite THIS — the named dataset and its issuing entity on the DDSE portal —
    never the raw /o/c/… or /o/dda/… backend path, the presigned cdn.data.dubai
    download link, or a bare host. Those are internal machine endpoints reached
    only through the Axion proxy; they are not human-resolvable sources and must
    never appear in a citation shown to a user. The portal itself is
    UAE-geofenced, so the citation identifies the dataset by name + id rather
    than a clickable link. The issuing entity is resolved from the dataset's ERC
    via list_entities(); pass entity_name to skip that lookup.

    e.g. "Dubai Airport Freezone Utilities Reports — Dubai Airport Freezone —
    Dubai Data & Statistics Establishment (DDSE) open-data portal, data.dubai —
    dataset 470307"."""
    if not isinstance(dataset, dict):
        dataset = get_dataset(dataset)
    title = _clean((dataset.get("title_i18n") or {}).get("en_US")
                   or dataset.get("title") or dataset.get("datasetName") or "dataset")
    if entity_name is None:
        entity_name = _entity_name(
            dataset.get("r_issuingEntityOfDataset_c_issuingEntityERC")
            or dataset.get("issuingEntityOfDatasetERC"))
    entity_name = _clean(entity_name or "")
    did = dataset.get("id") or dataset.get("datasetName") or ""
    parts = [title or "dataset"]
    if entity_name:
        parts.append(entity_name)
    parts.append(PORTAL)
    if did:
        parts.append(f"dataset {did}")
    return " — ".join(parts)


def list_themes():
    code, d = _get_json(f"{BASE}/o/c/themes?pageSize=100")
    return d.get("items", []) if isinstance(d, dict) else []


def list_subthemes():
    code, d = _get_json(f"{BASE}/o/c/subthemes?pageSize=100")
    return d.get("items", []) if isinstance(d, dict) else []


def list_entities():
    """All 76 issuing entities (publishers). Returns [{'erc','name'}]; 'erc'
    joins to a dataset's r_issuingEntityOfDataset_c_issuingEntityERC."""
    out = []
    page = 1
    while True:
        code, d = _get_json(f"{BASE}/o/c/issuingentities?page={page}&pageSize=100")
        if code != 200 or not isinstance(d, dict):
            break
        items = d.get("items", [])
        for it in items:
            out.append({
                "erc": it.get("externalReferenceCode"),
                "name": (it.get("title_i18n") or {}).get("en_US") or it.get("title") or "",
            })
        if len(items) < 100:
            break
        page += 1
    return out


# ------------------------------------------------------------ data access

def dataset_config(dataset_id):
    """pagination-config for a dataset. Returns {'is_open','total_records',
    'page_size_limit','download_files_page_size_limit','raw'}.
    is_open=False means the keyless path is blocked (needs the API-key channel)."""
    did = urllib.parse.quote(str(dataset_id), safe="")
    code, d = _get_json(f"{BASE}/o/dda/data-services/pagination-config?datasetId={did}")
    if not isinstance(d, dict) or "data" not in d:
        raise DataDubaiError(f"pagination-config failed for {dataset_id} ({code})")
    cfg = d["data"]
    return {
        "is_open": cfg.get("isOpen"),
        "total_records": cfg.get("totalRecords"),
        "page_size_limit": cfg.get("pageSizeLimit"),
        "download_files_page_size_limit": cfg.get("downloadFilesPageSizeLimit"),
        "raw": cfg,
    }


def preview_rows(dataset_id):
    """Inline JSON preview rows (server-capped, typically <=7000). Good for a quick
    look or small datasets. For the COMPLETE dataset use fetch_dataset()/download_files().
    Some realtime datasets 404 the preview but still download; catch and fall back."""
    did = urllib.parse.quote(str(dataset_id), safe="")
    code, d = _get_json(f"{BASE}/o/dda/data-services/dataset-metadata?datasetId={did}")
    if code == 404:
        raise DataDubaiError(
            f"No preview cached for {dataset_id} (HTTP 404). Use fetch_dataset() instead.")
    if not isinstance(d, dict) or not d.get("success"):
        raise DataDubaiError(f"preview failed for {dataset_id} ({code}): {str(d)[:150]}")
    rows = d.get("data")
    return rows if isinstance(rows, list) else []


def download_files(dataset_id, fmt="csv"):
    """Resolve presigned CDN download link(s) for the FULL dataset. fmt: 'csv' or 'json'.
    Returns a list of {'file_url','file_name'}; links are valid ~600s. Chunked for
    large datasets. Raises RestrictedDatasetError if the dataset is not open."""
    cfg = dataset_config(dataset_id)
    if cfg["is_open"] is False:
        raise RestrictedDatasetError(
            f"Dataset {dataset_id} is not open (isOpen=false). Keyless download is "
            f"blocked; this dataset needs the Dubai Pulse API-key channel.")
    did = urllib.parse.quote(str(dataset_id), safe="")
    url = f"{BASE}/o/dda/data-services/dataset-download?datasetId={did}&format={fmt}"
    code, d = _get_json(url)
    if not isinstance(d, dict) or not d.get("success"):
        raise DataDubaiError(f"download resolve failed for {dataset_id} ({code}): {str(d)[:150]}")
    meta = (d.get("data") or {}).get("metadata") or []
    out = []
    want = ".json" if fmt == "json" else ".csv"
    for folder in meta:
        for f in folder.get("files", []):
            u = f.get("file_url", "")
            if want in u.split("?")[0]:
                out.append({"file_url": u, "file_name": u.split("?")[0].split("/")[-1]})
    if not out:  # fall back to whatever files are offered
        for folder in meta:
            for f in folder.get("files", []):
                u = f.get("file_url", "")
                out.append({"file_url": u, "file_name": u.split("?")[0].split("/")[-1]})
    if not out:
        raise DataDubaiError(f"no download files returned for {dataset_id}")
    return out


def _fetch_gz(url, timeout=90):
    code, data = _raw(url, timeout=timeout)
    if code != 200:
        raise DataDubaiError(f"CDN fetch failed ({code}) for {url[:80]}")
    try:
        return gzip.decompress(data)
    except Exception:
        return data  # already-decompressed edge case


def fetch_dataset(dataset_id, fmt="csv", max_rows=None):
    """Download and parse the FULL dataset into python rows (keyless).
    fmt='csv' -> list[dict] (via csv.DictReader); fmt='json' -> list[dict].
    max_rows caps parsing for large datasets (files can be hundreds of MB).
    Returns {'rows': [...], 'count': int, 'files': int, 'truncated': bool}."""
    files = download_files(dataset_id, fmt=fmt)
    rows = []
    truncated = False
    for f in files:
        blob = _fetch_gz(f["file_url"])
        text = blob.decode("utf-8", "ignore")
        if fmt == "json":
            # Small datasets arrive as a pretty-printed JSON array, large ones as
            # NDJSON (one object per line, no wrapper). Handle both.
            stripped = text.lstrip()
            if stripped[:1] == "[":
                try:
                    arr = json.loads(text)
                except Exception:
                    arr = []
                for rec in arr:
                    rows.append(rec)
                    if max_rows and len(rows) >= max_rows:
                        truncated = True
                        break
            else:
                for line in text.splitlines():
                    line = line.strip().rstrip(",")
                    if not line or line in ("[", "]"):
                        continue
                    try:
                        rows.append(json.loads(line))
                    except Exception:
                        continue
                    if max_rows and len(rows) >= max_rows:
                        truncated = True
                        break
        else:
            reader = _csv.DictReader(io.StringIO(text))
            for rec in reader:
                rows.append(rec)
                if max_rows and len(rows) >= max_rows:
                    truncated = True
                    break
        if truncated:
            break
    return {"rows": rows, "count": len(rows), "files": len(files), "truncated": truncated}
```

## Recipes

**Find datasets by topic:**
```python
r = search_datasets(query="tourism", take=10)
for d in r["items"]:
    print(d["id"], d["title"])
```

**Browse a theme, newest first:**
```python
search_datasets(theme="Trade", sort="dateModified:desc", take=20)
```

**Everything from one publisher (e.g. RTA):**
```python
ents = list_entities()
erc = next(e["erc"] for e in ents if "Roads" in e["name"])   # RTA
search_datasets(entity_erc=erc, take=50)
```

**Quick look before committing to a full download:**
```python
cfg = dataset_config(470307)          # {'is_open': True, 'total_records': 72, ...}
if cfg["is_open"]:
    rows = preview_rows(470307)        # up to ~7000 rows inline
```

**Pull the COMPLETE dataset (uncapped):**
```python
out = fetch_dataset(470307, fmt="csv")            # {'rows':[...], 'count':72, ...}
big = fetch_dataset(461780, fmt="json", max_rows=5000)  # cap huge datasets
```

**Portal-wide data dictionary.** Dataset `1005464` ("Data.Dubai Open Data Catalog", 2419 rows) lists every column's name, datatype, description, category, entity, and primary-key flag across the whole portal. Call `fetch_dataset(1005464)` for the full schema map.

## Notes

- **Citing sources.** When a figure from this skill lands in an artifact or the final answer, attribute it to the named dataset on the DDSE portal — use `citation(dataset)` to format the line, or write "Source: <Dataset Title> — <Issuing Entity> — DDSE open-data portal, data.dubai". Never cite the raw `/o/c/…` or `/o/dda/…` backend path, the presigned `cdn.data.dubai` download link, or a bare `data.dubai` host stub: those are internal machine endpoints reached only through the Axion proxy, not human-resolvable sources. The portal is UAE-geofenced, so identify the dataset by name and id rather than a clickable link.
- **No Dubai credentials.** The open path needs no `data.dubai` key or login, so do not add one. The only `Authorization: Bearer` header is the backend `PROXY_API_KEY` (attached automatically by the helper) — that authenticates the sandbox to the Axion backend, not to Dubai. Only `isOpen:false` datasets require Dubai's paid API-key channel, which is out of scope here.
- **Themes and entities.** 11 themes (Society, Infrastructure, Economic Sectors, Trade, Prices, Population, National Accounts, Employment, Digital Society, Quality of Life, Polls), 44 subthemes, 76 issuing entities. Some entities publish nothing yet, so join on `erc` and expect gaps.
- **Preview vs download.** `preview_rows()` is capped near 7000 and a few realtime datasets 404 it. The download path is uncapped and more reliable, so prefer `fetch_dataset()` when you need every row. Download files are `.gz` and their links expire in about 600s; this skill fetches them immediately.
- **Rate limiting.** The F5 WAF throttles rapid sequential access and returns a "Request Rejected" HTML page (caught and raised as `DataDubaiError`). Space calls out; the built-in retry handles transient 429/5xx.
- **Reachability.** `data.dubai`'s F5 WAF blocks non-UAE source IPs, so all calls route through the backend `/api/dubaidata-proxy` route (UAE egress) — see "How it connects" above. If a call returns the "Request Rejected" page (raised as `DataDubaiError`), the UAE egress IP itself is being rejected; that is a backend-side proxy/egress issue, not something this skill can retry around.
