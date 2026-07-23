---
name: substack
description: >-
  Read Substack posts from the publications the account is subscribed to — a strong source of forecasting "alpha" (analyst newsletters, macro/market commentary, expert long-form). Reached through the Axion backend's Substack proxy, which injects the logged-in session cookie so the account is identified automatically — this skill never knows or needs to specify which account. Use this for ANY question where a subscribed Substack newsletter likely has a relevant view: read the inbox feed of recent posts across all subscriptions, list the subscribed publications, read the full body of any post (incl. paywalled subscriber-only posts), browse one publication's archive, search publications, and read chart-heavy posts where the data lives in the images: download_post() pulls a post's full text plus every figure to disk in one call and writes a single Markdown file linking each chart by local path, so a vision-capable agent reads it with the `read` tool (great for SemiAnalysis and other quant/macro newsletters). Substack has no official API; this wraps its undocumented JSON API (/api/v1).
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *), Read
---

# Substack reader (via proxy)

Read the Substack content the account subscribes to. Substack ships **no
official API**; this wraps the same undocumented JSON endpoints (`/api/v1/...`)
the web app uses, routed through the **Axion backend's Substack proxy**.

**The account is already logged in and identified by the session cookie the
backend injects — you never know, choose, or pass an account/handle.** Just ask
for "my inbox" or "my subscriptions"; the cookie resolves whose. The credential
lives in backend config and is **never** exposed here.

## Two host shapes (both under `/api/v1`)

| Host | What's there |
|---|---|
| `substack.com` *(global)* | **The account's inbox feed + subscriptions list** (cookie-scoped, no handle), any post's full body by id, publication search. |
| `<subdomain>.substack.com` *(per-publication)* | One publication's **archive** (post list) and single post bodies — for deep-diving a specific newsletter. |

> When you do address a publication, use its **`subdomain`**
> (`{subdomain}.substack.com`), never its `custom_domain` — the proxy only allows
> `*.substack.com`. Note: a publication that has set a custom domain 301-redirects
> its subdomain archive to that domain, which the proxy can't reach, so
> `list_posts()` raises for those pubs — the global `inbox()` + `get_post_by_id()`
> path works for **every** publication regardless of custom domain.

## Egress and proxy model (read this — it prevents the #1 error)

Every request routes through the **Axion backend**, like every other Axion data
tool (fred, finnhub, …): the backend forwards the call to Substack with the
session cookie attached. The helper derives the route from standard sandbox env:

- **`PROXY_BASE_URL`** — the backend base (`…/api/llm-proxy`); the helper swaps
  the suffix to `…/api/substack-proxy`.
- **`PROXY_API_KEY`** — the per-thread bearer token, sent as
  `Authorization: Bearer <token>`. You never build either value yourself.

The upstream host travels in the path:
`…/api/substack-proxy/<host>/api/v1/<…>`. Allowed hosts: `substack.com`,
`*.substack.com`, and the image CDN `substackcdn.com` (for `get_image`) —
anything else → `403`. The session cookie is injected only for the API hosts,
never for the public CDN. If
`PROXY_BASE_URL`/`PROXY_API_KEY` are unset, the helper raises immediately — that
only happens outside an Axion sandbox.

**Auth scope:** the backend attaches the session cookie automatically, so
subscriber-only (`audience: "only_paid"`) post bodies and the full subscription
list come through. If the cookie is unset/expired in backend config, the inbox
and subscriptions come back empty and paywalled bodies are blank — that's a
backend-config issue you can't fix from here; report it.

## Helper

Run **everything** through this helper. Pure stdlib (`urllib`, `json`), throttled
to ~1 request/second (Substack is undocumented; be gentle), retries transient
failures, and turns errors into clear Python exceptions.

```python
import os
import re
import json
import time
import html as _h
import urllib.request
import urllib.parse
import urllib.error

GLOBAL_HOST = "substack.com"
# A browser-like UA is required — Substack returns empty/degraded JSON otherwise.
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
_RETRYABLE_HTTP = {429, 500, 502, 503, 504}
_last_call = [0.0]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    # Don't follow redirects: a publication with a custom domain 301s its
    # subdomain archive to that domain, which the proxy can't route. Surfacing
    # the 3xx lets call() raise a clear message instead of wandering off-proxy.
    def redirect_request(self, *a):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _base() -> str:
    base = os.environ.get("PROXY_BASE_URL")
    if not base:
        raise RuntimeError(
            "PROXY_BASE_URL is not set. Substack is read through the Axion backend "
            "proxy — this skill only works inside an Axion sandbox."
        )
    return base.rstrip("/").replace("/api/llm-proxy", "/api/substack-proxy")


def _token() -> str:
    tok = os.environ.get("PROXY_API_KEY")
    if not tok:
        raise RuntimeError("PROXY_API_KEY is not set; cannot authenticate to the Axion backend proxy.")
    return tok


def _throttle(min_interval: float = 1.0) -> None:
    elapsed = time.monotonic() - _last_call[0]
    if elapsed < min_interval:
        time.sleep(min_interval - elapsed)
    _last_call[0] = time.monotonic()


def call(host: str, path: str, *, params: dict | None = None, timeout: int = 60, retries: int = 3):
    """Call a Substack /api/v1 endpoint on `host` ('substack.com' or
    '<subdomain>.substack.com') and return parsed JSON. `path` starts with
    '/api/v1/...'. GET only; throttled to ~1 req/s. Raises RuntimeError with a
    clear message on a non-retryable HTTP error, non-JSON response, or persistent
    failure."""
    if host != GLOBAL_HOST and not host.endswith(".substack.com"):
        raise ValueError(f"host {host!r} is not a *.substack.com host; the proxy will reject it.")
    url = f"{_base()}/{host}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    hdrs = {"Authorization": "Bearer " + _token(), "User-Agent": UA, "Accept": "application/json"}
    last = None
    for attempt in range(1, retries + 1):
        _throttle()
        try:
            req = urllib.request.Request(url, headers=hdrs, method="GET")
            with _OPENER.open(req, timeout=timeout) as r:
                text = r.read().decode("utf-8", "replace")
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                raise RuntimeError(
                    f"{host}{path} did not return JSON (likely a proxy/auth error page). "
                    f"First 160 chars: {text[:160]!r}"
                )
        except urllib.error.HTTPError as e:
            if 300 <= e.code < 400:
                loc = e.headers.get("Location", "")
                raise RuntimeError(
                    f"{host}{path} redirected ({e.code}) to {loc!r} — this publication uses a "
                    f"custom domain the proxy can't reach. Use inbox() (it includes this "
                    f"publication's posts) or get_post_by_id() instead of list_posts()/get_post()."
                )
            payload = e.read().decode("utf-8", "replace")[:200]
            if e.code not in _RETRYABLE_HTTP:
                raise RuntimeError(f"HTTP {e.code} for {host}{path} — {payload}")
            last = f"HTTP {e.code}: {payload}"
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            last = f"{type(e).__name__}: {e}"
        if attempt < retries:
            time.sleep(1.5 * attempt)
    raise RuntimeError(f"Request failed after {retries} attempts: {host}{path} — {last}")


# ---- The account's feed + subscriptions (cookie-scoped, NO handle) -----------

def inbox(limit: int = 20, offset: int = 0) -> dict:
    """The account's INBOX FEED — recent posts across ALL subscribed
    publications, newest first. This is the main "what's new in my subscriptions"
    read. Returns {'posts': [...], 'pubs': {pub_id: subdomain}, 'more': bool}.
    Each post: id, title, slug, post_date, audience, publication_id,
    canonical_url, reactions/restacks. `limit` is capped at 20 per page; paginate
    with `offset` (`more` is True when more pages exist). Fetch a post's full body
    with get_post_by_id(id)."""
    limit = max(1, min(limit, 20))
    d = call(GLOBAL_HOST, "/api/v1/reader/posts", params={"limit": limit, "offset": offset})
    pubs = {p["id"]: p.get("subdomain") for p in d.get("publications", [])}
    return {"posts": d.get("posts", []), "pubs": pubs, "more": d.get("more", False)}


def get_subscriptions() -> list:
    """The publications the account subscribes to (cookie-scoped). Each item:
    {id, name, subdomain}. Use `subdomain` to deep-dive a publication with
    list_posts()."""
    d = call(GLOBAL_HOST, "/api/v1/subscriptions", params={"tvOnly": "false"})
    return [{"id": p.get("id"), "name": p.get("name"), "subdomain": p.get("subdomain")}
            for p in d.get("publications", [])]


# ---- Post bodies -------------------------------------------------------------

def get_post_by_id(post_id: int) -> dict:
    """Full post by global numeric id — the primary body fetch, since inbox()
    yields ids. Returns the post object: {title, subtitle, body_html, audience,
    post_date, canonical_url, reactions, ...}. `body_html` of subscriber-only
    posts comes through via the backend session cookie. No subdomain needed."""
    d = call(GLOBAL_HOST, f"/api/v1/posts/by-id/{int(post_id)}")
    return d.get("post", d)


def get_post(subdomain: str, slug: str) -> dict:
    """Full post by (publication subdomain, slug) — use when you have a slug from
    list_posts() rather than an id. Same shape as get_post_by_id()."""
    return call(f"{subdomain}.substack.com", f"/api/v1/posts/{urllib.parse.quote(slug)}")


# ---- Deep-dive one publication ----------------------------------------------

def list_posts(subdomain: str, *, sort: str = "new", limit: int = 15, offset: int = 0,
               search: str | None = None, type: str | None = None) -> list:
    """One publication's archive (its own post list), for going deeper than the
    inbox feed on a specific newsletter. `subdomain` from get_subscriptions()/
    inbox() pubs. sort: 'new'|'top'|'pinned'|'community'; page size caps ~50,
    paginate with `offset`. `search` filters within the publication;
    type='podcast' limits to audio. Each item: id, title, slug, post_date,
    audience, canonical_url, description, comment_count, type."""
    params = {"sort": sort, "limit": limit, "offset": offset}
    if search:
        params["search"] = search
    if type:
        params["type"] = type
    return call(f"{subdomain}.substack.com", "/api/v1/archive", params=params)


# ---- Discovery ---------------------------------------------------------------

def search_publications(query: str, *, limit: int = 20, page: int = 0) -> list:
    """Find publications by name/topic (e.g. to check whether a newsletter exists
    or resolve a name → subdomain). Returns [{id, subdomain, custom_domain,
    name, ...}]."""
    res = call(GLOBAL_HOST, "/api/v1/publication/search",
               params={"query": query, "page": page, "limit": limit, "skipExplanation": "true"})
    return res.get("publications", res if isinstance(res, list) else [])


# ---- Figures / charts inside a post ------------------------------------------

def post_images(post: dict) -> list:
    """Extract the figures embedded in a post body, in order:
    [{'src': image_url, 'caption': text}]. `post` is what get_post_by_id() /
    get_post() returns. Captions are often just attribution ('Source: …') — the
    real content lives in the pixels, so fetch them with get_image(src) and read
    them with vision. Note: SemiAnalysis-style posts carry their data in charts,
    not prose, so reading the images matters."""
    html = post.get("body_html") or ""
    out, seen = [], set()
    for fig in re.findall(r"<figure.*?</figure>", html, re.S):
        m = re.search(r'<img[^>]+src="([^"]+)"', fig)
        if not m:
            continue
        cap = re.search(r"<figcaption[^>]*>(.*?)</figcaption>", fig, re.S)
        caption = re.sub(r"<[^>]+>", "", cap.group(1)).strip() if cap else ""
        out.append({"src": m.group(1), "caption": caption})
        seen.add(m.group(1))
    for m in re.finditer(r'<img[^>]+src="([^"]+)"', html):  # images outside <figure>
        if m.group(1) not in seen:
            out.append({"src": m.group(1), "caption": ""})
            seen.add(m.group(1))
    return out


def get_image(src: str, dest: str | None = None, *, timeout: int = 60, retries: int = 3) -> bytes:
    """Fetch a post image (chart/figure) through the proxy and return its bytes;
    if `dest` is given, also write them there for a vision read. `src` is an image
    URL from post_images()/body_html (Substack's CDN). The CDN picks a
    vision-friendly format (webp/png/jpeg) from the Accept header. Raises on
    failure."""
    parts = urllib.parse.urlsplit(src)  # leaves %2F in the embedded origin intact
    host = parts.netloc
    if host != "substackcdn.com" and not host.endswith(".substack.com"):
        raise ValueError(f"image host {host!r} is not allowed by the proxy.")
    proxy_url = f"{_base()}/{host}{parts.path}"
    if parts.query:
        proxy_url += "?" + parts.query
    hdrs = {"Authorization": "Bearer " + _token(), "User-Agent": UA,
            "Accept": "image/webp,image/png,image/jpeg,image/*"}
    last = None
    for attempt in range(1, retries + 1):
        _throttle()
        try:
            req = urllib.request.Request(proxy_url, headers=hdrs, method="GET")
            with _OPENER.open(req, timeout=timeout) as r:
                data = r.read()
            if dest:
                with open(dest, "wb") as fh:
                    fh.write(data)
            return data
        except urllib.error.HTTPError as e:
            body = e.read()[:200]
            if e.code not in _RETRYABLE_HTTP:
                raise RuntimeError(f"HTTP {e.code} fetching image {src[:80]}… — {body!r}")
            last = f"HTTP {e.code}"
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            last = f"{type(e).__name__}: {e}"
        if attempt < retries:
            time.sleep(1.5 * attempt)
    raise RuntimeError(f"Image fetch failed after {retries} attempts: {src[:80]}… — {last}")


# ---- One-shot: whole post (text + every figure) to disk ----------------------

def _sniff_ext(b: bytes) -> str:
    if b[:3] == b"\xff\xd8\xff":
        return "jpg"
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return "webp"
    if b[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if b[4:8] == b"ftyp":
        return "heic"
    return "img"


def _html_to_markdown(html_text: str) -> str:
    """Best-effort HTML→Markdown (stdlib only). <figure> blocks and <img> tags are
    replaced, in document order, by @@FIG{n}@@ placeholders the caller fills with
    local image links. Good enough for an LLM to read; not a strict converter."""
    n = [0]

    def _ph(_m):
        i = n[0]
        n[0] += 1
        return f"\n\n@@FIG{i}@@\n\n"

    html_text = re.sub(r"(?is)<(script|style|svg).*?</\1>", "", html_text)
    html_text = re.sub(r"(?is)<figure\b.*?</figure>", _ph, html_text)
    html_text = re.sub(r"(?is)<img\b[^>]*>", _ph, html_text)
    strip = lambda s: _h.unescape(re.sub(r"<[^>]+>", "", s)).strip()
    for lvl in range(1, 7):
        html_text = re.sub(rf"(?is)<h{lvl}[^>]*>(.*?)</h{lvl}>",
                           lambda m, l=lvl: f"\n\n{'#' * l} {strip(m.group(1))}\n", html_text)
    html_text = re.sub(r"(?is)<li[^>]*>(.*?)</li>", lambda m: f"\n- {strip(m.group(1))}", html_text)
    html_text = re.sub(r"(?is)<blockquote[^>]*>(.*?)</blockquote>",
                       lambda m: "\n\n> " + strip(m.group(1)).replace("\n", "\n> ") + "\n", html_text)
    html_text = re.sub(r'(?is)<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
                       lambda m: f"[{strip(m.group(2))}]({m.group(1)})", html_text)
    html_text = re.sub(r"(?is)</p\s*>", "\n\n", html_text)
    html_text = re.sub(r"(?is)<br\s*/?>", "\n", html_text)
    html_text = re.sub(r"(?is)<hr\b[^>]*>", "\n\n---\n\n", html_text)
    html_text = re.sub(r"(?s)<[^>]+>", "", html_text)
    html_text = _h.unescape(html_text)
    return re.sub(r"\n{3,}", "\n\n", html_text).strip()


def download_post(post_id: int, out_dir: str | None = None, *, max_images: int = 50) -> dict:
    """ONE-SHOT, context-friendly read of a chart-heavy post. Fetches the full
    body AND downloads every figure to disk in a single call, then writes one
    Markdown file (post.md) with each figure linked inline by its LOCAL path.

    This is the efficient pattern (mirrors the PDF reader): one call lands
    everything on disk; you then `read` post.md once for the complete text +
    figure map, and `read` only the figure image paths you actually need — the
    `read` tool renders them to vision. No per-image tool roundtrips, and the
    images never enter context unless you choose to read them.

    Returns a manifest: {dir, markdown_path, title, audience, post_date,
    canonical_url, word_count, figures: [{i, path, caption, error?}]}."""
    post = get_post_by_id(post_id)
    out_dir = out_dir or f"/tmp/substack/{int(post_id)}"
    os.makedirs(out_dir, exist_ok=True)

    saved = []
    for i, fig in enumerate(post_images(post)[:max_images]):
        rec = {"i": i, "path": None, "caption": fig["caption"]}
        try:
            data = get_image(fig["src"])
            rec["path"] = os.path.join(out_dir, f"figure_{i:02d}.{_sniff_ext(data[:16])}")
            with open(rec["path"], "wb") as fh:
                fh.write(data)
        except Exception as e:  # one bad image must not sink the whole post
            rec["error"] = str(e)
        saved.append(rec)

    body_md = _html_to_markdown(post.get("body_html") or "")

    def _fill(m):
        rec = saved[int(m.group(1))] if int(m.group(1)) < len(saved) else None
        if rec and rec["path"]:
            return f"![figure {rec['i']} — {rec['caption'] or 'chart'}]({rec['path']})"
        return f"_[figure {m.group(1)} unavailable]_"

    body_md = re.sub(r"@@FIG(\d+)@@", _fill, body_md)

    head = [f"# {post.get('title', '')}"]
    if post.get("subtitle"):
        head.append(f"\n*{post['subtitle']}*")
    meta = [x for x in (post.get("audience") and f"audience: {post['audience']}",
                        post.get("post_date") and f"date: {post['post_date']}",
                        post.get("canonical_url")) if x]
    if meta:
        head.append("\n" + " · ".join(meta))
    ok = [r for r in saved if r["path"]]
    if ok:
        head.append(f"\n> {len(ok)} figures downloaded to `{out_dir}` and linked inline "
                    f"below. **Use the `read` tool on a figure's path to view the chart** "
                    f"(vision) — for data-heavy newsletters the numbers live in the images.")
    head.append("\n---\n")
    md = "\n".join(head) + "\n" + body_md + "\n"

    md_path = os.path.join(out_dir, "post.md")
    with open(md_path, "w") as fh:
        fh.write(md)

    return {
        "dir": out_dir, "markdown_path": md_path, "title": post.get("title"),
        "audience": post.get("audience"), "post_date": post.get("post_date"),
        "canonical_url": post.get("canonical_url"), "word_count": len(body_md.split()),
        "figures": [{k: r[k] for k in ("i", "path", "caption") if k in r} | (
            {"error": r["error"]} if "error" in r else {}) for r in saved],
    }
```

## The main flow — read recent alpha across all subscriptions

```python
feed = inbox(limit=20)
for p in feed["posts"]:
    print(p["post_date"], p["audience"], "|", p["title"],
          "| pub:", feed["pubs"].get(p["publication_id"]))

# Read the full body of an interesting one (works for paywalled posts too).
full = get_post_by_id(feed["posts"][0]["id"])
print(full["title"], "—", full["audience"])
print(full["body_html"][:2000])   # body_html is HTML; strip tags for plain text
```

### Reading a chart-heavy post (SemiAnalysis, macro/quant newsletters)

A post's real "alpha" often lives in the **charts**, not the prose. The efficient,
context-friendly way is **one** `download_post()` call — it pulls the full text
*and* every figure to disk and writes a single `post.md` that links each figure
inline by its local path. Then read `post.md` once, and use the `read` tool on
only the figure paths you actually need (the `read` tool renders images to
vision). The images never enter context unless you choose to read them — so this
does **not** flood context, and there are **no** per-image tool roundtrips.

```python
m = download_post(201544287)          # one call: text + all figures → disk
print(m["title"], m["audience"], m["word_count"], "words,", len(m["figures"]), "figures")
print("read this first:", m["markdown_path"])
# Now (as the agent): `read` m["markdown_path"] for the full article + figure map,
# then `read` e.g. m["figures"][0]["path"] to view that chart with vision.
```

**Default to `download_post()` whenever you intend to *read* a post's
figures — even if you only care about one chart.** It is a single call: it lands
the text and every figure on disk, and you then `read` only the figure paths you
want. Hand-rolling `get_post_by_id()` + `post_images()` + `get_image()` to view a
figure is strictly more tool calls for the same result and is the wrong move.
Reach for `post_images()`/`get_image()` directly **only** when you need an
image's raw bytes for non-vision processing (hashing, re-encoding, byte-size
checks) rather than to read it — not as a shortcut for "I just want one chart."

Deep-dive a single publication's back catalog:

```python
subs = get_subscriptions()
print([s["subdomain"] for s in subs])
posts = list_posts("notboring", sort="new", limit=10)   # subdomain from subs
body = get_post("notboring", posts[0]["slug"])
```

## How to avoid errors

1. **Never specify an account.** `inbox()` and `get_subscriptions()` are scoped to
   the logged-in account by the backend cookie. There is no handle to pass.
2. **Start with `inbox()`** for "what's new across my subscriptions" — it's the
   unified, cross-publication feed. Use `list_posts(subdomain)` only to go deeper
   on one newsletter.
3. **`get_post_by_id(id)`** is the primary body fetch **for text-only posts**
   (inbox yields ids). Use `get_post(subdomain, slug)` when you only have a slug
   from `list_posts()`. **If the post has charts/figures you want to read, use
   `download_post(id)` instead** — one call gets the text *and* every figure on
   disk; then `read` `post.md` plus only the figure paths you need. Do not
   hand-roll `post_images()` + `get_image()` just to view a single chart.
4. **The backend cookie unlocks paywalled content + the full lists.** Empty
   inbox/subscriptions or blank `body_html` means the backend's `SUBSTACK_COOKIE`
   is unset/expired — report it; you can't fix it from the sandbox.
5. **`body_html` is HTML.** Strip tags (`html.parser` or a small regex) when you
   need plain text for analysis.
6. **Paginate** with `offset` (`inbox` exposes `more`; archive page size caps
   ~50). Fetch the most recent N relevant to the question — don't scrape whole
   archives.
7. **Address publications by `subdomain`, not `custom_domain`** (the proxy only
   allows `*.substack.com`).
8. **Be gentle.** The helper throttles to ~1 req/s; don't bypass it. Substack is
   undocumented and may change without notice.
