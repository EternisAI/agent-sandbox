---
name: port-watch
description: Fetch daily port traffic and chokepoint transit data from IMF PortWatch (2,065 ports + 28 chokepoints, daily, no auth). Covers Jebel Ali, Fujairah, Khor Fakkan, Abu Dhabi, Khalifa Port, Das Island, Ruwais LNG, plus Strait of Hormuz, Bab el-Mandeb, Suez Canal, Malacca, Cape of Good Hope. Use for vessel call counts, container/tanker/dry-bulk splits, import/export tonnage, chokepoint transit volumes, or short-run shipping disruption signals. Free, no auth.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# IMF PortWatch — Global Port Traffic & Chokepoint Transits

PortWatch is the IMF's open data system tracking AIS-derived vessel calls at **2,065 ports** and transits through **28 chokepoints**, updated daily. The closest free substitute for Kpler-style physical-flow data — gives vessel-class breakdowns (container, tanker, dry bulk, general cargo, RoRo) but no cargo-level commodity attribution.

**Dubai-specific value**: covers all 15 UAE ports + Hormuz/Bab el-Mandeb/Suez chokepoints by name. Daily granularity. No quota.

## Sandbox Environment

- Python 3.12 stdlib only (urllib, json, datetime)
- No installs needed
- No cache required — queries are small JSON and return immediately

## Endpoints

All routes are ArcGIS Feature Server queries under one base URL. No auth.

```python
import urllib.parse, urllib.request, json
from datetime import date, timedelta

BASE = "https://services9.arcgis.com/weJ1QsnbMYJlCHdG/arcgis/rest/services"

LAYERS = {
    "ports":            f"{BASE}/PortWatch_ports_database/FeatureServer/0/query",
    "chokepoints":      f"{BASE}/PortWatch_chokepoints_database/FeatureServer/0/query",
    "daily_ports":      f"{BASE}/Daily_Ports_Data/FeatureServer/0/query",
    "daily_chokepoints":f"{BASE}/Daily_Chokepoints_Data/FeatureServer/0/query",
    "disruptions":      f"{BASE}/portwatch_disruptions_database/FeatureServer/0/query",
}

def _query(layer: str, where: str = "1=1", out_fields: str = "*",
           order_by: str = None, limit: int = 100, offset: int = 0) -> list[dict]:
    """ArcGIS REST query. Returns flat list of attributes."""
    params = {
        "where": where,
        "outFields": out_fields,
        "f": "json",
        "resultRecordCount": limit,
        "resultOffset": offset,
    }
    if order_by:
        params["orderByFields"] = order_by
    url = LAYERS[layer] + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "opencode-portwatch-client/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.loads(r.read().decode())
    if "error" in data:
        raise RuntimeError(f"ArcGIS error on {layer}: {data['error']}")
    return [f["attributes"] for f in data.get("features", [])]

def _esc(s: str) -> str:
    """Escape single quotes for ArcGIS WHERE clause."""
    return s.replace("'", "''")
```

## Pre-baked UAE entities

```python
# Verified against PortWatch live 2026-06-09 — these names match exactly.
UAE_PORTS = [
    "Jebel Ali", "Fujairah", "Khor Fakkan", "Abu Dhabi", "Khalifa Port",
    "Dubai", "Sharjah", "Ajman", "Mina Saqr", "Umm al Qaiwain",
    "Jabal Az Zannah-Ruways",     # Ruwais — major LNG/refinery export terminal
    "Jebel Dhanna",               # Murban crude export
    "Das Island", "Zirku Island", # Abu Dhabi offshore oil
    "Al Hamriyah LPG Terminal",
]

# Chokepoints most relevant to UAE/Dubai trade flows (subset of 28 globally).
DUBAI_CHOKEPOINTS = [
    "Strait of Hormuz",           # 20-30% of seaborne oil
    "Bab el-Mandeb Strait",       # Red Sea entry — Houthi disruption signal
    "Suez Canal",                 # Europe-Asia main artery
    "Malacca Strait",             # Asia-bound crude/LNG
    "Cape of Good Hope",          # Suez alternative
]

ALL_CHOKEPOINTS = [
    "Suez Canal", "Panama Canal", "Bosporus Strait", "Bab el-Mandeb Strait",
    "Malacca Strait", "Strait of Hormuz", "Cape of Good Hope", "Gibraltar Strait",
    "Dover Strait", "Oresund Strait", "Taiwan Strait", "Korea Strait",
    "Tsugaru Strait", "Luzon Strait", "Lombok Strait", "Ombai Strait",
    "Bohai Strait", "Torres Strait", "Sunda Strait", "Makassar Strait",
    "Magellan Strait", "Yucatan Channel", "Windward Passage", "Mona Passage",
    "Balabac Strait", "Bering Strait", "Mindoro Strait", "Kerch Strait",
]
```

> **Data lag**: PortWatch refreshes daily but typically lags by **5-14 days**. The "last N days" tools below return the **most recent N available rows** (date DESC ordering), so they always return data even when the latest row is 1-2 weeks old. Use `start_date`/`end_date` for explicit calendar ranges.

## Tool 1: `port_calls()` — daily port activity

```python
def port_calls(port_name: str, days: int = 30,
               start_date: str = None, end_date: str = None) -> list[dict]:
    """Daily vessel call counts at one port. Returns the most recent `days` rows by default;
    pass start_date / end_date (ISO 'YYYY-MM-DD') for an explicit calendar window.

    Fields per day:
      date, portcalls, portcalls_container, portcalls_dry_bulk,
      portcalls_general_cargo, portcalls_roro, portcalls_tanker, portcalls_cargo

    Note: 'portcalls' = grand total; 'portcalls_cargo' = sum of cargo subtypes (excludes tanker).
    """
    clauses = [f"portname='{_esc(port_name)}'"]
    if start_date: clauses.append(f"date >= DATE '{start_date}'")
    if end_date:   clauses.append(f"date <= DATE '{end_date}'")
    return _query(
        "daily_ports",
        where=" AND ".join(clauses),
        out_fields="date,portname,portcalls,portcalls_container,portcalls_dry_bulk,portcalls_general_cargo,portcalls_roro,portcalls_tanker,portcalls_cargo",
        order_by="date DESC",
        limit=days,
    )

# Example — get latest 7 available days (regardless of calendar lag)
for d in port_calls("Jebel Ali", days=7):
    print(f"{d['date']}: total={d['portcalls']} container={d['portcalls_container']} tanker={d['portcalls_tanker']}")
```

## Tool 2: `port_trade_volume()` — import/export tonnage

```python
def port_trade_volume(port_name: str, days: int = 30,
                      start_date: str = None, end_date: str = None) -> list[dict]:
    """Daily import/export volume broken down by vessel class.
    Useful when you want flow weight rather than vessel count.
    """
    clauses = [f"portname='{_esc(port_name)}'"]
    if start_date: clauses.append(f"date >= DATE '{start_date}'")
    if end_date:   clauses.append(f"date <= DATE '{end_date}'")
    return _query(
        "daily_ports",
        where=" AND ".join(clauses),
        out_fields="date,portname,import,import_container,import_dry_bulk,import_tanker,export,export_container,export_dry_bulk,export_tanker",
        order_by="date DESC",
        limit=days,
    )
```

## Tool 3: `chokepoint_transit()` — daily chokepoint traffic

```python
def chokepoint_transit(chokepoint: str, days: int = 30,
                       start_date: str = None, end_date: str = None) -> list[dict]:
    """Daily vessel transit counts + capacity through a chokepoint.

    Fields:
      date, n_total, n_container, n_dry_bulk, n_general_cargo, n_roro, n_tanker, n_cargo
      capacity, capacity_container, capacity_dry_bulk, capacity_tanker, ...
    """
    clauses = [f"portname='{_esc(chokepoint)}'"]
    if start_date: clauses.append(f"date >= DATE '{start_date}'")
    if end_date:   clauses.append(f"date <= DATE '{end_date}'")
    return _query(
        "daily_chokepoints",
        where=" AND ".join(clauses),
        out_fields="date,portname,n_total,n_container,n_dry_bulk,n_tanker,n_cargo,capacity,capacity_container,capacity_tanker",
        order_by="date DESC",
        limit=days,
    )

# Example: Hormuz last 7 available days
for d in chokepoint_transit("Strait of Hormuz", days=7):
    print(f"{d['date']}: {d['n_total']} vessels ({d['n_tanker']} tanker, {d['n_container']} container)")
```

## Tool 4: `port_metadata()` — static port reference

```python
def port_metadata(port_name: str = None, country: str = None) -> list[dict]:
    """Look up port location, vessel mix, country."""
    clauses = []
    if port_name: clauses.append(f"portname='{_esc(port_name)}'")
    if country:   clauses.append(f"country='{_esc(country)}'")
    where = " AND ".join(clauses) if clauses else "1=1"
    return _query(
        "ports",
        where=where,
        out_fields="portname,country,ISO3,lat,lon,vessel_count_total,vessel_count_container,vessel_count_dry_bulk,vessel_count_tanker",
        limit=50,
    )

def list_uae_ports() -> list[dict]:
    """All 15 PortWatch-tracked UAE ports with coordinates."""
    return _query(
        "ports",
        where="ISO3='ARE'",
        out_fields="portname,country,fullname,lat,lon,vessel_count_total",
        limit=20,
    )
```

## Tool 5: `compare_ports()` — multi-port comparison

```python
def compare_ports(port_names: list[str], metric: str = "portcalls", days: int = 7) -> dict:
    """Side-by-side: returns {port: [{date, value}, ...]}.

    metric: one of 'portcalls', 'portcalls_container', 'portcalls_tanker',
            'portcalls_dry_bulk', 'import', 'export', 'import_tanker', etc.
    """
    out = {}
    for p in port_names:
        rows = port_calls(p, days) if metric.startswith("portcalls") else port_trade_volume(p, days)
        out[p] = [{"date": r["date"], "value": r.get(metric, 0)} for r in rows]
    return out

# Example: container throughput Jebel Ali vs Khalifa Port
print(compare_ports(["Jebel Ali", "Khalifa Port"], metric="portcalls_container", days=7))
```

## Tool 6: `disruptions()` — shipping disruption events

```python
def disruptions(limit: int = 50, country: str = None,
                event_type: str = None, alert_level: str = None) -> list[dict]:
    """PortWatch's curated disruption database — tropical cyclones (TC), earthquakes (EQ),
    other (OT), conflicts, blockages. Used by IMF to flag shipping risk.

    Returned fields:
      eventid, eventtype, eventname, alertlevel ('RED'/'ORANGE'/'GREEN'),
      severitytext, country, fromdate (ISO), todate (ISO), editdate (ISO),
      affectedports, n_affectedports, lat, long

    Filter examples:
      disruptions(country="Yemen")                # Houthi-related Red Sea events
      disruptions(event_type="TC")                # tropical cyclones globally
      disruptions(alert_level="RED")              # most severe only
    """
    from datetime import datetime, timezone
    clauses = []
    if country:     clauses.append(f"country='{_esc(country)}'")
    if event_type:  clauses.append(f"eventtype='{_esc(event_type)}'")
    if alert_level: clauses.append(f"alertlevel='{_esc(alert_level)}'")
    where = " AND ".join(clauses) if clauses else "1=1"
    rows = _query(
        "disruptions",
        where=where,
        out_fields="eventid,eventtype,eventname,alertlevel,severitytext,country,fromdate,todate,editdate,affectedports,n_affectedports,lat,long",
        order_by="fromdate DESC",
        limit=limit,
    )
    # Convert epoch-ms dates to ISO strings
    for r in rows:
        for k in ("fromdate", "todate", "editdate"):
            v = r.get(k)
            if isinstance(v, (int, float)):
                r[k] = datetime.fromtimestamp(v / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    return rows
```

> **Event types**: `TC` = tropical cyclone, `EQ` = earthquake, `OT` = other (covers conflict, sanctions, blockages, accidents). Alert levels: `RED` (most severe), `ORANGE`, `GREEN`.

## Dubai-relevant shortcuts

```python
def hormuz_snapshot(days: int = 30) -> list[dict]:
    """Daily Strait of Hormuz transit — the single most important shipping
    signal for UAE/Dubai economic exposure."""
    return chokepoint_transit("Strait of Hormuz", days)

def jebel_ali_throughput(days: int = 30) -> list[dict]:
    """Jebel Ali port calls — Dubai's main container/dry-bulk artery."""
    return port_calls("Jebel Ali", days)

def fujairah_bunker_activity(days: int = 30) -> list[dict]:
    """Fujairah port calls — proxy for bunker fuel demand. Tanker count is the key signal."""
    return port_calls("Fujairah", days)

def uae_all_ports_summary(days: int = 7) -> dict:
    """All 15 UAE ports, last N days, total vessel calls. Quick map of where activity is."""
    out = {}
    for p in UAE_PORTS:
        try:
            rows = port_calls(p, days)
            out[p] = sum(r.get("portcalls", 0) or 0 for r in rows)
        except Exception as e:
            out[p] = None
    return out

def dubai_chokepoint_dashboard(days: int = 7) -> dict:
    """5 key chokepoints for Dubai trade routing. Returns {chokepoint: total_vessels_in_window}."""
    out = {}
    for c in DUBAI_CHOKEPOINTS:
        try:
            rows = chokepoint_transit(c, days)
            out[c] = {
                "total_vessels": sum(r.get("n_total", 0) or 0 for r in rows),
                "tanker_vessels": sum(r.get("n_tanker", 0) or 0 for r in rows),
                "container_vessels": sum(r.get("n_container", 0) or 0 for r in rows),
            }
        except Exception as e:
            out[c] = None
    return out
```

## Critical gotchas

1. **Port names must match exactly** (case-sensitive). Use `UAE_PORTS` constant or `port_metadata()` to discover the canonical spelling.
2. **`Bab el-Mandeb Strait`** has a space-dash-space, not hyphens. **`Khalifa Port`** has "Port" suffix. **`Khor Fakkan`** is two words.
3. **WHERE clauses need ArcGIS SQL** — use `DATE 'YYYY-MM-DD'` literal for date comparisons, not raw strings. Escape single quotes with `''`.
4. **Default `resultRecordCount` is 1000** — daily data is small (1 row/day/port), so `days + 5` is plenty of headroom.
5. **Data latency** — Daily port/chokepoint files lag by 2-5 days. The most recent date is rarely "today".
6. **`portcalls_cargo` vs `portcalls`** — cargo excludes tanker. `portcalls` is the grand total. Don't add them.
7. **Disruptions database** has irregular schema (different events have different fields). Use `out_fields="*"` and filter in Python.

## Pattern: small responses, summarize in Python

```python
# BAD — dumps every row to context
print(port_calls("Jebel Ali", days=90))

# GOOD — process then print summary
rows = port_calls("Jebel Ali", days=90)
tcalls = [r["portcalls"] for r in rows if r.get("portcalls") is not None]
avg = sum(tcalls) / len(tcalls) if tcalls else 0
print(f"Jebel Ali 90d: avg={avg:.1f} calls/day, peak={max(tcalls)}, last={tcalls[0]}")
```
