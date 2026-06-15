---
name: thai-government-data
description: Query official Thai-government data at the source — TWO CKAN portals, both reached through the sandbox's Thai egress proxy. (1) data.go.th — the national open-data catalog of ~39,000 datasets from ~1,000 agencies (every ministry, department, province, state enterprise): population/census, public health, education, agriculture and rice/crop output, transport and accidents, energy, tourism arrivals, labor, budget, procurement, registries, geographic data. (2) catalog.parliament.go.th — the Parliament/legislative catalog: bills and the bill-consideration pipeline (ร่างพระราชบัญญัติ, with sponsor + political party + status), Acts (พระราชบัญญัติ), Organic Acts, Royal Decrees (พระราชกฤษฎีกา), Emergency Decrees (พระราชกำหนด), parliamentary questions/interpellations (กระทู้ถาม), constitutional-court rulings and judgments, and the Constitution. Use this for ANY question needing official Thai statistics, registries, legislation, parliamentary proceedings/bill-tracking, or government records. Both portals speak the standard CKAN Action API (full-text search in Thai or English, dataset metadata, structured DataStore as JSON + SQL). ~15,000 resources on data.go.th are PDFs — route those to the pdf-reader. This skill ships only in the Thai-government sandbox image.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Thai Government Data — data.go.th + Parliament (CKAN)

Two official Thai-government **CKAN** portals, both at `/api/3/action/<action>`
returning `{"success": true/false, "result": ...}`, both reached through the
same Thai egress proxy:

| Portal key | Host | What's there |
|---|---|---|
| `data.go.th` *(default)* | `data.go.th` | National open data — **~39,000** datasets, **~1,000** agencies. Stats, registries, budgets, geo, PDFs. |
| `parliament` | `catalog.parliament.go.th` | Legislative catalog — **~10** curated datasets: bills, acts, decrees, interpellations, rulings, the Constitution. |

> Pick the portal by topic: **legislation / parliament / bills / acts / decrees /
> interpellations → `parliament`**; everything else → `data.go.th`.

## Egress and proxy model (read this — it prevents the #1 error)

Both portals sit behind a Cloudflare WAF that returns `403` to any non-Thai IP,
so the sandbox **cannot reach them directly**. Every request goes through the
Thai egress proxy, whose full endpoint (with credentials) is injected as the
environment variable **`THAI_DATA_PROXY_URL`** (e.g.
`http://<user>:<pass>@<host>:3128`). The helper installs it as a `urllib`
proxy for you — you never build the proxy URL yourself.

- The proxy is **destination-locked to all `.go.th`** — it reaches both portals
  *and* the federated file hosts (`*.gdcatalog.go.th`, `lis.parliament.go.th`,
  per-agency nodes) where some resources actually live. It is **not** a general
  proxy: any non-`.go.th` host is refused at CONNECT.
- If `THAI_DATA_PROXY_URL` is unset, the helper raises immediately with a clear
  message. That only happens outside the Thai-government sandbox (where this
  skill should not exist).

> Forward-looking note: today `THAI_DATA_PROXY_URL` is the GCP Bangkok egress
> proxy. The helper reads it from the environment precisely so it can later be
> swapped to a backend-proxied route without changing any call site here.

## Helper

Run **everything** through this helper. It is pure stdlib (`urllib`, `json`),
retries transient proxy/network failures, and turns CKAN/WAF errors into clear
Python exceptions so you don't burn turns guessing.

```python
import os
import json
import time
import urllib.request
import urllib.parse
import urllib.error

# The two Thai-government CKAN portals. `ckan(..., portal=...)` selects one.
PORTALS = {
    "data.go.th": "https://data.go.th/api/3/action/",
    "parliament": "https://catalog.parliament.go.th/api/3/action/",
}
DEFAULT_PORTAL = "data.go.th"
UA = "AxionThaiAgent/1.0"

# CKAN actions that are read-only and safe to retry on a transient failure.
_RETRYABLE_HTTP = {429, 500, 502, 503, 504}


def _proxy_url() -> str:
    """The Thai egress proxy endpoint (with basic-auth creds), injected by the
    Thai-government sandbox as THAI_DATA_PROXY_URL. Both portals are geo-blocked,
    so every request must go through it."""
    url = os.environ.get("THAI_DATA_PROXY_URL")
    if not url:
        raise RuntimeError(
            "THAI_DATA_PROXY_URL is not set. Thai government data is geo-blocked and "
            "must be reached through the Thai egress proxy — this skill only works "
            "inside the Thai-government sandbox image."
        )
    return url


def _opener() -> urllib.request.OpenerDirector:
    p = _proxy_url()
    return urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": p, "https": p})
    )


def _http(url: str, *, data: bytes | None = None, headers: dict | None = None,
          timeout: int = 90, retries: int = 3) -> str:
    """GET (or POST if `data`) through the proxy, with retry+backoff on transient
    errors. Returns the decoded body. Raises RuntimeError with a clear message on
    a non-retryable HTTP error, a WAF/HTML error page, or persistent failure."""
    method = "POST" if data is not None else "GET"
    last = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
            with _opener().open(req, timeout=timeout) as r:
                return r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")[:200]
            if e.code not in _RETRYABLE_HTTP:
                # 403 here usually means the proxy isn't engaged or the host is
                # outside .go.th; 404 means a bad action/id.
                raise RuntimeError(f"HTTP {e.code} for {url[:90]} — {body}")
            last = f"HTTP {e.code}: {body}"
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            last = f"{type(e).__name__}: {e}"
        if attempt < retries:
            time.sleep(1.5 * attempt)  # 1.5s, 3.0s backoff
    raise RuntimeError(f"Request failed after {retries} attempts: {url[:90]} — {last}")


def ckan(action: str, *, portal: str = DEFAULT_PORTAL, post: bool = False,
         timeout: int = 90, **params):
    """Call a CKAN Action API method on the chosen portal and return its
    `result`. Most read actions accept GET; pass `post=True` for long arguments
    (notably `datastore_search_sql`). Raises RuntimeError on `success: false`
    (surfacing CKAN's own error) or on a non-JSON response (a WAF/proxy page)."""
    base = PORTALS.get(portal)
    if base is None:
        raise ValueError(f"Unknown portal {portal!r}. Choose one of: {list(PORTALS)}")
    url = base + action
    if post:
        text = _http(url, data=json.dumps(params).encode(),
                     headers={"Content-Type": "application/json", "User-Agent": UA},
                     timeout=timeout)
    else:
        if params:
            url += "?" + urllib.parse.urlencode(params, doseq=True)
        text = _http(url, headers={"User-Agent": UA}, timeout=timeout)
    try:
        resp = json.loads(text)
    except json.JSONDecodeError:
        raise RuntimeError(
            f"{action} on '{portal}' did not return JSON — likely a proxy/WAF error "
            f"page (is THAI_DATA_PROXY_URL set and is the host a .go.th domain?). "
            f"First 160 chars: {text[:160]!r}"
        )
    if not resp.get("success"):
        raise RuntimeError(f"CKAN {action} on '{portal}' failed: {json.dumps(resp.get('error'))[:300]}")
    return resp["result"]


# ---- Generic wrappers (work on either portal via portal=) --------------------

def search_datasets(q: str = "*:*", rows: int = 10, start: int = 0,
                    fq: str | None = None, sort: str | None = None,
                    portal: str = DEFAULT_PORTAL) -> dict:
    """Full-text dataset search (Solr syntax; Thai or English). `fq` filters,
    e.g. 'res_format:CSV' or 'organization:<slug>'. Returns {count, results:[...]}.
    Use rows=0 for just a count."""
    p = {"q": q, "rows": rows, "start": start}
    if fq:
        p["fq"] = fq
    if sort:
        p["sort"] = sort
    return ckan("package_search", portal=portal, **p)


def get_dataset(name_or_id: str, portal: str = DEFAULT_PORTAL) -> dict:
    """Full metadata for one dataset incl. every resource (id, format, url,
    datastore_active)."""
    return ckan("package_show", portal=portal, id=name_or_id)


def list_datasets(portal: str = DEFAULT_PORTAL) -> list:
    """Every dataset slug on the portal. Cheap and reliable on the small
    parliament portal; on data.go.th prefer search_datasets (39k slugs)."""
    return ckan("package_list", portal=portal)


def datastore_query(resource_id: str, *, limit: int = 100, offset: int = 0,
                    q: str | None = None, filters: dict | None = None,
                    portal: str = DEFAULT_PORTAL) -> dict:
    """Read rows from a DataStore-backed resource as JSON. ONLY works where the
    resource's `datastore_active` is true (check get_dataset first). `filters` is
    {field: value} exact matches; `q` is free-text across fields. Returns
    {fields:[...], records:[...], total}."""
    p = {"resource_id": resource_id, "limit": limit, "offset": offset}
    if q:
        p["q"] = q
    if filters:
        p["filters"] = json.dumps(filters)
    return ckan("datastore_search", portal=portal, **p)


def datastore_fields(resource_id: str, portal: str = DEFAULT_PORTAL) -> list:
    """Just the column names of a datastore resource. Call this BEFORE writing a
    filter or SQL so you use real field names (they vary and many are Thai or
    Dublin-Core-style like 'dc.title')."""
    return [f["id"] for f in datastore_query(resource_id, limit=0, portal=portal)["fields"]]


def datastore_sql(sql: str, portal: str = DEFAULT_PORTAL) -> dict:
    """Read-only SQL against the DataStore (PostgreSQL). The table name is the
    resource_id and MUST be double-quoted:
        SELECT * FROM "<resource_id>" WHERE ... LIMIT 100
    Sent as POST. Returns {fields, records}."""
    return ckan("datastore_search_sql", portal=portal, post=True, sql=sql)


def list_organizations(all_fields: bool = False, portal: str = DEFAULT_PORTAL) -> list:
    """Publishing organizations. With all_fields=True each has title (Thai),
    package_count, etc."""
    return ckan("organization_list", portal=portal, all_fields=all_fields)


def get_organization(name_or_id: str, include_datasets: bool = False,
                     portal: str = DEFAULT_PORTAL) -> dict:
    return ckan("organization_show", portal=portal, id=name_or_id,
                include_datasets=include_datasets)


def list_tags(query: str | None = None, portal: str = DEFAULT_PORTAL) -> list:
    return ckan("tag_list", portal=portal, **({"query": query} if query else {}))


# ---- Parliament / legislative shortcuts (catalog.parliament.go.th) -----------
# The parliament portal has a FIXED, small set of datasets. Go straight to a
# slug below instead of searching — searching this tiny catalog is error-prone
# (Thai tokenization makes terms like 'รายงานการประชุม' return 0). See the slug
# table in "Parliament catalog" further down.

def parliament_dataset(slug: str) -> dict:
    """package_show on the parliament portal. `slug` is one of the fixed slugs
    (e.g. 'lis01' for the bill-consideration pipeline, '12_02' for the Acts
    list). Returns metadata + resources."""
    return ckan("package_show", portal="parliament", id=slug)


def parliament_rows(slug: str, *, limit: int = 100, offset: int = 0,
                    prefer: str = "JSON") -> dict:
    """One-call read of a parliament dataset's primary datastore resource as
    JSON rows. Resolves the dataset's first datastore-active resource (preferring
    `prefer` format when several exist) and runs datastore_search. Returns
    {fields, records, total, resource_id}."""
    pkg = parliament_dataset(slug)
    actives = [r for r in pkg.get("resources", []) if r.get("datastore_active")]
    if not actives:
        raise RuntimeError(f"Parliament dataset '{slug}' has no datastore-active resource; "
                           f"download a file URL instead: {[r.get('url') for r in pkg.get('resources', [])][:3]}")
    chosen = next((r for r in actives if (r.get("format") or "").upper() == prefer.upper()), actives[0])
    out = datastore_query(chosen["id"], limit=limit, offset=offset, portal="parliament")
    out["resource_id"] = chosen["id"]
    return out
```

## How to avoid errors (do this and most calls just work)

1. **The proxy is mandatory.** Every call needs `THAI_DATA_PROXY_URL`; the helper
   handles it. A `403`/non-JSON error almost always means the proxy isn't
   engaged or you aimed at a non-`.go.th` host.
2. **Pick the right portal.** Legislation/parliament → `parliament`; everything
   else → `data.go.th`. Don't search data.go.th for bills — use the parliament
   slugs below.
3. **Don't full-text-search the tiny parliament catalog.** It has ~10 datasets
   and Thai tokenization makes many phrases return 0 hits. Use `parliament_dataset(slug)`
   / `parliament_rows(slug)` with the slug table.
4. **Call `datastore_fields(resource_id)` before filtering or SQL.** Field names
   vary per dataset and are often Thai or Dublin-Core (`dc.title`,
   `nalt.date.issuedBE`). Guessing field names is the most common cause of a
   `datastore_search_sql failed` error.
5. **Quote the resource_id in SQL**: `FROM "<resource_id>"` (double quotes), and
   always add a `LIMIT`.
6. **`datastore_query` only works on `datastore_active` resources.** For others,
   download the resource `url` through the proxy and parse the file. `parliament_rows`
   resolves the right resource for you and raises a clear message if none exists.
7. **Paginate** with `start`/`offset`; use `rows=0`/`limit=0` to get counts or
   field lists cheaply.
8. **Buddhist-Era years.** Many fields use พ.ศ. (BE = CE + 543), e.g. 2567 = 2024.
9. **PDF resources** → hand the `url` to the **pdf-reader** plugin; don't parse
   PDFs here. Many Thai government PDFs are scans (pdf-reader's image fallback
   handles them).

## Parliament catalog (catalog.parliament.go.th) — fixed slug map

The portal exposes a small, stable set. Go directly to a slug — every dataset
below is DataStore-backed (queryable as JSON/SQL via `parliament_rows` /
`datastore_query`):

| Slug | Dataset (Thai) | Contents (EN) |
|---|---|---|
| `lis01` | ข้อมูลกระบวนการพิจารณาร่างพระราชบัญญัติ | **Bill-consideration pipeline** — every bill: session #, year (BE), title, **proposer + party**, status, deep-link to `lis.parliament.go.th`. The richest legislative dataset. |
| `12_02` | รายการพระราชบัญญัติ | List of **Acts** (statutes) |
| `12_03` | รายการพระราชบัญญัติประกอบรัฐธรรมนูญ | **Organic Acts** (constitutional-level statutes) |
| `12_04` | รายการพระราชกำหนด | **Emergency Decrees** |
| `12_05` | รายการพระราชกฤษฎีกา | **Royal Decrees** |
| `12_06` | รายการกระทู้ถาม | **Interpellations / parliamentary questions** to ministers |
| `12_07` | รายการคำวินิจฉัย เกี่ยวกับรัฐสภา | Rulings concerning Parliament |
| `12_08` | รายการคำพิพากษา | Court judgments |
| `12_01` | รัฐธรรมนูญและธรรมนูญการปกครอง | The **Constitution(s)** and interim charters |
| `12_10` | รายการประกาศ ระเบียบ คำสั่ง เกี่ยวกับรัฐสภา | Parliamentary announcements / regulations / orders |

> Coverage note: this catalog is **structured legislative metadata** (what bills
> exist, their stage, who proposed them, status) — NOT verbatim debate
> transcripts (Hansard / รายงานการประชุม), which are not published as open data.
> The per-bill detail link in `lis01` points to `lis.parliament.go.th` (reachable
> through the proxy) for the deeper document trail.

## Examples

### data.go.th — orient and search (Thai-language query)

```python
# Search in Thai: "ผลผลิตข้าว" (rice output). English works too.
hits = search_datasets("ผลผลิตข้าว", rows=5)
print(hits["count"])
for d in hits["results"]:
    org = (d.get("organization") or {}).get("title")
    print(" -", d["name"], "|", (d.get("title") or "")[:40], "| org:", org)
```

### data.go.th — read a dataset's DataStore

```python
pkg = get_dataset(hits["results"][0]["name"])
res = next(r for r in pkg["resources"] if r.get("datastore_active"))
print(datastore_fields(res["id"]))          # column names FIRST
rows = datastore_query(res["id"], limit=20)
print(rows["records"][:3])
```

### Parliament — the bill-consideration pipeline (no search needed)

```python
# Go straight to the slug. parliament_rows resolves the JSON datastore resource.
data = parliament_rows("lis01", limit=10)
print("total bills:", data["total"])
print("fields:", [f["id"] for f in data["fields"]])
for row in data["records"][:5]:
    print(row)   # title, session, year(BE), proposer+party, status, detail link
```

### Parliament — count Acts, or query with SQL by field

```python
acts = parliament_rows("12_02", limit=0)         # limit=0 → fields + total only
print("Acts on record:", acts["total"], "| fields:", [f["id"] for f in acts["fields"]])

# SQL: always quote the resource_id and check field names first.
rid = acts["resource_id"]
fields = datastore_fields(rid, portal="parliament")
# pick a real field from `fields`, e.g. a year column, then:
# rows = datastore_sql(f'SELECT * FROM "{rid}" LIMIT 50', portal="parliament")
```

### Parliament — interpellations (questions to ministers)

```python
q = parliament_rows("12_06", limit=20)
print("interpellations:", q["total"])
for r in q["records"][:5]:
    print(r)
```

## Caveats

- **Thai text.** Titles/fields are largely Thai; search works in ไทย or English.
  Thai has no inter-word spaces — don't tokenize on whitespace.
- **data.go.th quality is uneven** (~39k datasets, ~1k agencies): mixed schemas,
  stale resources, broken links, partial DataStore coverage. Check `format` and
  `datastore_active` before assuming you can read a resource.
- **Federation.** A resource `url` often points to the owning agency's node
  (`*.gdcatalog.go.th`, `catalog.parliament.go.th`, `lis.parliament.go.th`); the
  proxy reaches all `.go.th`, so these still download.
- **Be gentle.** Shared government portals behind one proxy — prefer `rows=0`
  counts, targeted `fq`/SQL, and the parliament slug table over scraping.
