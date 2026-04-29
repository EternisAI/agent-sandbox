---
name: defillama
description: Fetch DeFi TVL, protocol details, stablecoin supply/market caps, yield/APY pools, perpetuals open interest, protocol fees, and protocol revenue from the DefiLlama free public API. Use when users ask about on-chain DeFi data, lending protocol TVL, stablecoin circulation, yield farming opportunities, perp exchange open interest, DEX fees, or chain-level revenue. No API key required.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# DefiLlama API (free public tier)

Use direct HTTP requests to DefiLlama's free public API. No authentication or proxy required.

## Base URLs

The API is split across three subdomains:

```python
import json, time, urllib.request, urllib.parse, urllib.error
from datetime import datetime, timezone

LLAMA_TVL    = "https://api.llama.fi"           # TVL, fees, perps
LLAMA_STABLE = "https://stablecoins.llama.fi"   # stablecoins
LLAMA_YIELDS = "https://yields.llama.fi"         # yield pools

def _get(base: str, path: str, params: dict | None = None) -> dict | list:
    url = f"{base}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    for attempt in range(4):
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "opencode-defillama/1.0", "Accept": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
```

## Supported Tools

| Function | Subdomain | Endpoint | Purpose |
| --- | --- | --- | --- |
| `get_protocols` | api | `GET /protocols` | All protocols with current TVL, chains, 1d/7d changes |
| `get_protocol` | api | `GET /protocol/{slug}` | Single protocol — chain TVL breakdown + full history |
| `get_protocol_tvl` | api | `GET /tvl/{slug}` | Current TVL as a single float |
| `get_chain_tvl_history` | api | `GET /v2/historicalChainTvl[/{chain}]` | Historical aggregate or per-chain TVL (epoch int dates) |
| `get_chains` | api | `GET /v2/chains` | Current TVL for every tracked chain |
| `get_stablecoins` | stablecoins | `GET /stablecoins` | All stablecoins with circulating supply and price |
| `get_stablecoin_history` | stablecoins | `GET /stablecoin/{id}` or `GET /stablecoincharts/{chain}` | Historical supply for one stablecoin (global or per-chain) |
| `get_stablecoin_chains` | stablecoins | `GET /stablecoinchains` | Current stablecoin supply summed per chain |
| `get_pools` | yields | `GET /pools` | All yield pools — filter client-side by chain/project/TVL |
| `get_pool_chart` | yields | `GET /chart/{pool}` | Historical APY and TVL for a single pool (ISO timestamps) |
| `get_open_interest` | api | `GET /overview/open-interest` | Perp exchange open interest — all protocols ranked |
| `get_fees` | api | `GET /overview/fees[/{chain}]` | Fee/revenue overview, optionally chain-scoped |
| `get_protocol_fees` | api | `GET /summary/fees/{slug}` | Full fee/revenue history for a single protocol |

## Examples

### TVL — Protocols, Chain History, and Chain Rankings

```python
import json, time, urllib.request, urllib.parse, urllib.error
from datetime import datetime, timezone

LLAMA_TVL = "https://api.llama.fi"

def _get(base, path, params=None):
    url = f"{base}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "opencode-defillama/1.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise

def get_protocols(limit: int = 20) -> list:
    data = _get(LLAMA_TVL, "protocols")
    data.sort(key=lambda p: p.get("tvl") or 0, reverse=True)
    return data[:limit]

def get_protocol(slug: str) -> dict:
    return _get(LLAMA_TVL, f"protocol/{slug}")

def get_protocol_tvl(slug: str) -> float:
    return _get(LLAMA_TVL, f"tvl/{slug}")

def get_chain_tvl_history(chain: str | None = None) -> list:
    """Returns [{date (epoch int), tvl}]. Pass chain='Ethereum' for single-chain history."""
    path = f"v2/historicalChainTvl/{chain}" if chain else "v2/historicalChainTvl"
    return _get(LLAMA_TVL, path)

def get_chains() -> list:
    data = _get(LLAMA_TVL, "v2/chains")
    return sorted(data, key=lambda c: c.get("tvl") or 0, reverse=True)

# Top 10 protocols by TVL
print("=== Top 10 DeFi Protocols ===")
for p in get_protocols(limit=10):
    chains = ", ".join((p.get("chains") or [])[:3])
    chg = p.get("change_1d") or 0
    print(f"{p['name']:<30} ${p['tvl']/1e9:>7.2f}B  1d={chg:+.1f}%  [{chains}]")

# Single protocol detail
print("\n=== Aave detail ===")
proto = get_protocol("aave")
chain_tvls = proto.get("currentChainTvls", {})
# filter out borrowed/staking sub-keys for cleaner output
top = {k: v for k, v in chain_tvls.items() if "-" not in k and k not in ("staking", "pool2", "borrowed")}
for chain, tvl in sorted(top.items(), key=lambda x: x[1], reverse=True)[:5]:
    print(f"  {chain:<20} ${tvl/1e9:.2f}B")
print(f"  Snapshot TVL: ${get_protocol_tvl('aave'):,.0f}")

# Historical chain TVL (last 5 days)
print("\n=== Ethereum TVL — last 5 days ===")
for e in get_chain_tvl_history("Ethereum")[-5:]:
    dt = datetime.fromtimestamp(e["date"], tz=timezone.utc).strftime("%Y-%m-%d")
    print(f"  {dt}: ${e['tvl']/1e9:.1f}B")

# Chain rankings
print("\n=== Top 5 chains by TVL ===")
for c in get_chains()[:5]:
    print(f"  {c['name']:<20} ${c['tvl']/1e9:.1f}B  ({c.get('tokenSymbol')})")
```

### Stablecoins — Supply, History, and Chain Distribution

```python
import json, time, urllib.request, urllib.parse, urllib.error
from datetime import datetime, timezone

LLAMA_STABLE = "https://stablecoins.llama.fi"

def _get(base, path, params=None):
    url = f"{base}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "opencode-defillama/1.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise

def get_stablecoins(include_prices: bool = False) -> list:
    result = _get(LLAMA_STABLE, "stablecoins", {"includePrices": "true"} if include_prices else None)
    return result.get("peggedAssets", [])

def get_stablecoin_history(asset_id: int, chain: str | None = None) -> list:
    """
    Global (no chain): returns tokens[] — each entry has epoch int `date` and
      `circulating.peggedUSD`.
    Per-chain: returns list of {date (epoch int string), totalCirculating.peggedUSD}.
    """
    if chain:
        return _get(LLAMA_STABLE, f"stablecoincharts/{chain}", {"stablecoin": asset_id})
    return _get(LLAMA_STABLE, f"stablecoin/{asset_id}").get("tokens", [])

def get_stablecoin_chains() -> list:
    """Current stablecoin supply per chain, sorted by peggedUSD descending."""
    data = _get(LLAMA_STABLE, "stablecoinchains")
    return sorted(data, key=lambda c: c.get("totalCirculatingUSD", {}).get("peggedUSD", 0), reverse=True)

# List top stablecoins
stables = get_stablecoins(include_prices=True)
print(f"Tracking {len(stables)} stablecoins")
for s in sorted(stables, key=lambda x: x.get("circulating", {}).get("peggedUSD", 0), reverse=True)[:5]:
    circ = s.get("circulating", {}).get("peggedUSD", 0)
    print(f"  id={s['id']}  {s['symbol']:<8} ${circ/1e9:.1f}B  peg={s['pegType']}  price={s.get('price')}")

# Global history for USDT (id=1) and USDC (id=2)
print("\n=== USDT vs USDC — last 5 days (global) ===")
for sym, sid in [("USDT", 1), ("USDC", 2)]:
    hist = get_stablecoin_history(sid)
    for e in hist[-5:]:
        circ = e.get("circulating", {}).get("peggedUSD", 0)
        dt = datetime.fromtimestamp(e["date"], tz=timezone.utc).strftime("%Y-%m-%d")
        print(f"  {sym} {dt}: ${circ/1e9:.1f}B")

# USDT on Ethereum only (last 3)
print("\n=== USDT on Ethereum — last 3 days ===")
for e in get_stablecoin_history(1, chain="Ethereum")[-3:]:
    circ = e.get("totalCirculating", {}).get("peggedUSD", 0)
    dt = datetime.fromtimestamp(int(e["date"]), tz=timezone.utc).strftime("%Y-%m-%d")
    print(f"  {dt}: ${circ/1e9:.1f}B")

# Chain distribution
print("\n=== Stablecoin supply by chain (top 5) ===")
for c in get_stablecoin_chains()[:5]:
    usd = c.get("totalCirculatingUSD", {}).get("peggedUSD", 0)
    print(f"  {c['name']:<20} ${usd/1e9:.1f}B")
```

### Yields — Pool Ranking and APY History

```python
import json, time, urllib.request, urllib.parse, urllib.error

LLAMA_YIELDS = "https://yields.llama.fi"

def _get(base, path, params=None):
    url = f"{base}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "opencode-defillama/1.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise

def get_pools(chain: str | None = None, project: str | None = None,
              min_tvl: float | None = None, limit: int = 50) -> list:
    all_pools = _get(LLAMA_YIELDS, "pools").get("data", [])
    filtered = [
        p for p in all_pools
        if (chain is None or p.get("chain", "").lower() == chain.lower())
        and (project is None or p.get("project", "").lower() == project.lower())
        and (min_tvl is None or (p.get("tvlUsd") or 0) >= min_tvl)
        and not p.get("outlier", False)
    ]
    filtered.sort(key=lambda p: p.get("apy") or 0, reverse=True)
    return filtered[:limit]

def get_pool_chart(pool_id: str) -> list:
    """Returns [{timestamp (ISO str), tvlUsd, apy, apyBase, apyReward}]."""
    return _get(LLAMA_YIELDS, f"chart/{pool_id}").get("data", [])

# Top pools by APY with min $5M TVL
print(f"{'Project':<20} {'Symbol':<15} {'Chain':<12} {'APY':>8} {'TVL':>12}")
print("-" * 73)
for p in get_pools(min_tvl=5_000_000, limit=10):
    apy = p.get("apy") or 0
    tvl = p.get("tvlUsd") or 0
    print(f"{p['project']:<20} {p['symbol']:<15} {p['chain']:<12} {apy:>7.2f}%  ${tvl/1e6:>7.1f}M")

# Historical APY for a specific pool (stETH on Lido — use pool UUID from get_pools())
# pool UUID is in the `pool` field; find it via: next(p for p in get_pools(project="lido") ...)
STETH_POOL_ID = "747c1d2a-c668-4682-b9f9-296708a3dd90"
chart = get_pool_chart(STETH_POOL_ID)
print(f"\nstETH/Lido — last 5 data points ({len(chart)} total):")
for e in chart[-5:]:
    print(f"  {e['timestamp'][:10]}: apy={e.get('apy')}%  tvl=${e.get('tvlUsd', 0)/1e9:.1f}B")
```

### Perps — Open Interest

```python
import json, time, urllib.request, urllib.parse, urllib.error

LLAMA_TVL = "https://api.llama.fi"

def _get(base, path, params=None):
    url = f"{base}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "opencode-defillama/1.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise

def get_open_interest(limit: int = 20) -> dict:
    """Returns {total24h, change_1d, allChains, protocols (sorted by OI desc)}."""
    result = _get(LLAMA_TVL, "overview/open-interest", {
        "excludeTotalDataChart": "true",
        "excludeTotalDataChartBreakdown": "true",
    })
    protos = sorted(result.get("protocols", []), key=lambda p: p.get("total24h") or 0, reverse=True)
    return {
        "total24h":  result.get("total24h"),
        "change_1d": result.get("change_1d"),
        "allChains": result.get("allChains", []),
        "protocols": protos[:limit],
    }

oi = get_open_interest(limit=10)
print(f"Total open interest: ${oi['total24h']:,.0f}  (1d change: {oi['change_1d']:+.2f}%)")
print(f"Active chains: {', '.join(oi['allChains'][:6])}")
print(f"\n{'Exchange':<35} {'Open Interest':>18}")
print("-" * 55)
for p in oi["protocols"]:
    val = p.get("total24h") or 0
    print(f"{p['name']:<35} ${val:>17,.0f}")
```

### Fees and Revenue — Protocol and Chain Level

```python
import json, time, urllib.request, urllib.parse, urllib.error

LLAMA_TVL = "https://api.llama.fi"

def _get(base, path, params=None):
    url = f"{base}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "opencode-defillama/1.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** attempt)
            else:
                raise

def get_fees(chain: str | None = None, data_type: str = "dailyFees", limit: int = 20) -> list:
    """data_type: 'dailyFees' | 'dailyRevenue' | 'dailyHoldersRevenue'. chain uses lowercase."""
    path = f"overview/fees/{chain}" if chain else "overview/fees"
    result = _get(LLAMA_TVL, path, {
        "excludeTotalDataChart": "true",
        "excludeTotalDataChartBreakdown": "true",
        "dataType": data_type,
    })
    protos = result.get("protocols", [])
    protos.sort(key=lambda p: p.get("total24h") or 0, reverse=True)
    return protos[:limit]

def get_protocol_fees(protocol: str, data_type: str = "dailyFees") -> dict:
    """Full history for a single protocol. data_type switches fees vs revenue."""
    return _get(LLAMA_TVL, f"summary/fees/{protocol}", {"dataType": data_type})

# Uniswap: fees vs revenue
fees = get_protocol_fees("uniswap", "dailyFees")
rev  = get_protocol_fees("uniswap", "dailyRevenue")
print(f"{fees['name']}")
print(f"  Fees   — 24h: ${fees['total24h']:>12,.0f}  7d: ${fees['total7d']:>13,.0f}  all-time: ${fees['totalAllTime']:>16,.0f}")
print(f"  Revenue— 24h: ${rev['total24h']:>12,.0f}  7d: ${rev['total7d']:>13,.0f}  all-time: ${rev['totalAllTime']:>16,.0f}")

# Top protocols by 24h fees across all chains
print("\n=== Top 10 protocols by 24h fees (all chains) ===")
for p in get_fees(data_type="dailyFees", limit=10):
    print(f"  {p['name']:<28} 24h=${p.get('total24h') or 0:>12,.0f}  7d=${p.get('total7d') or 0:>13,.0f}")

# Chain-level fees (Ethereum)
print("\n=== Top 5 protocols by 24h fees on Ethereum ===")
for p in get_fees(chain="ethereum", data_type="dailyFees", limit=5):
    print(f"  {p['name']:<28} 24h=${p.get('total24h') or 0:>12,.0f}")
```

## Notes

- **No API key or proxy needed** — hit the public subdomains directly.
- **Three subdomains:** `api.llama.fi` (TVL/fees/perps), `stablecoins.llama.fi`, `yields.llama.fi`.
- **Protocol slugs** are lowercase-hyphenated (e.g. `aave`, `uniswap-v3`, `lido`). Find exact slugs via `get_protocols()`.
- **Chain casing differs by endpoint:** `get_chain_tvl_history` uses title-case (`Ethereum`); `get_fees(chain=...)` uses lowercase (`ethereum`); `get_pools` chain filter is case-insensitive client-side.
- **Date formats vary:** `get_chain_tvl_history` and `get_stablecoin_history` (global) return epoch int dates; chain variant of `get_stablecoin_history` returns epoch int as a string — always cast with `int(e["date"])`. `get_pool_chart` returns ISO timestamp strings.
- **Stablecoin IDs** are integers from `get_stablecoins()` — USDT=1, USDC=2.
- **Pool IDs** are UUIDs in the `pool` field from `get_pools()` — use these for `get_pool_chart`.
- **`get_pools()` returns 19,000+ pools** — always filter by `chain`, `project`, or `min_tvl` and apply a `limit`.
- **`data_type` for fees/revenue:** `"dailyFees"` (gross fees paid), `"dailyRevenue"` (protocol-retained), `"dailyHoldersRevenue"` (to token holders).
- **Overview fee endpoints** pass `excludeTotalDataChart=true` and `excludeTotalDataChartBreakdown=true` to avoid large chart payloads.
- **Retries:** `_get` retries up to 3 times with exponential backoff (1s, 2s, 4s) on 429/5xx and network errors.
- Process data in Python and print concise summaries — avoid dumping raw JSON.
