---
name: dubai-map
description: Draw a choropleth Map of Dubai communities (shade each community by a metric — price, rent, yield, transaction count, growth). The Map joins on an EXACT community name from a fixed, closed set; this skill explains how to discover the valid names with the list_map_communities tool and emit a correct Map via emit_artifact. Use whenever you want to show a value across Dubai neighbourhoods/communities on a map, or a "which areas" geographic comparison. Dubai only — no other city has boundary data.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Dubai community Map (choropleth)

The `Map` artifact shades Dubai community polygons by a numeric value. You emit it
with the **`emit_artifact`** tool (`component: "Map"`). The map joins each region
onto a polygon by **exact community name**, against a **fixed, closed set of ~410
Dubai communities**. The set carries a small **alias table** for a handful of
universal abbreviations (`JBR`, `JLT`, `DIFC`, `JVC`, …) that resolve to their
canonical community, but there is no general fuzzy matching and most marketing
names are not aliased. A name outside the set (and its aliases) is **rejected** by
`emit_artifact` (you get the closest matches back and must fix or drop it), and it
never renders.

So the one rule that matters: **never invent, abbreviate, or guess a community
name. Look it up first.**

## Step 1 — discover the valid names

Before emitting, call the **`list_map_communities`** tool to get the exact names.
Filter with a substring so you don't pull all 410:

- `list_map_communities` with `contains: "jumeirah"` → every community whose name
  contains "jumeirah" (e.g. `Jumeirah 3`, `Jumeirah Lakes Towers`,
  `Jumeirah Village Circle`, `Jumeirah Islands`, `Palm Jumeirah`, …).
- `list_map_communities` with `contains: "al quoz"` → `Al Quoz Community`,
  `Al Quoz Industrial Area 1`, `Al Quoz Industrial Area 2`, … (note the OSM
  splits, e.g. there is no bare "Al Quoz 1").
- `list_map_communities` with no `contains` → the full list.

Use the returned strings **verbatim** as each region's `name`. If you have a
popular/marketing name, look it up first. A few common abbreviations are aliased,
and `list_map_communities` surfaces the canonical community for them (e.g. `JBR` →
`Jumeirah Beach Residence`, `JLT` → `Jumeirah Lakes Towers`, `DIFC` → `Dubai
International Financial Centre`, `JVC` → `Jumeirah Village Circle`). Others
(e.g. "Dubai Hills Estate", "Dubai Sports City", "Dubai Islands") have **no polygon
at all**: if `list_map_communities` returns nothing close, that area cannot be
mapped — omit it rather than forcing a wrong match.

## Step 2 — emit the Map

`emit_artifact` with `component: "Map"` and props:

```jsonc
{
  "title": "Median price per sqft by community",
  "subtitle": "One-line framing of what the map answers",
  "metricLabel": "Median price / sqft",
  "format": "currency",                     // "number" | "percent" | "currency" (AED)
  "colorScheme": "sequential",              // "sequential" | "diverging" (omit for auto)
  "fit": "data",                            // "data" (zoom to valued) | "all" (whole Dubai)
  "regions": [
    { "name": "Business Bay", "value": 1850, "label": "Business Bay" },
    { "name": "Dubai Marina", "value": 1720 },
    { "name": "Jumeirah Village Circle", "value": 980 }
  ]
}
```

Rules for `regions`:

- **`name` is required and must be an exact name** from `list_map_communities`.
- **`value` is required and numeric.** For `format: "percent"` emit a **fraction**
  (`0.14` for 14%, not `14`). Raw numbers for `number`/`currency`.
- `label` is optional (defaults to the community name) — the on-map/tooltip text.
- Do **not** send a numeric `code`; the join is name-only.
- Communities you don't include render as neutral context, not blanks.

Colour: use **`diverging`** for signed change/delta data centred at zero
(e.g. YoY price change, over/under a benchmark) and **`sequential`** for levels
(price, rent, count). Omit `colorScheme` to let it auto-pick.

## If emit_artifact rejects your Map

You'll get an error listing each bad name with the closest valid matches, e.g.:

```text
"Business Bey" is not a Dubai community — did you mean: Business Bay?
"Dubai Hills Estate" is not a Dubai community and has no close match; remove this region or replace it with a real community
```

Fix each name to an exact community (or drop that region), then re-emit. Don't
re-send the same bad name — either correct it from the suggestions / a
`list_map_communities` lookup, or omit it.

## Example — discover, shape, emit

Say you have year-over-year price change for a handful of areas and want a
diverging choropleth.

1. Get the exact names for the areas you have (search a substring at a time):

   `list_map_communities` with `contains: "jumeirah"`, then `contains: "marina"`,
   … → returns e.g. `Dubai Marina`, `Jumeirah Lakes Towers`,
   `Jumeirah Village Circle`.

2. Shape your figures into the `regions` array, keyed by those **exact** names.
   For more than a few rows, build it with `python3` so the names stay verbatim
   and the values are formatted consistently:

   ```bash
   python3 - <<'PY'
   import json
   # keys MUST be exact list_map_communities names — never marketing/short forms
   data = {
       "Dubai Marina": 0.084,
       "Jumeirah Lakes Towers": -0.023,
       "Jumeirah Village Circle": 0.035,
   }
   print(json.dumps([{"name": k, "value": v} for k, v in data.items()]))
   PY
   ```

3. Call `emit_artifact` with `component: "Map"`, `format: "percent"`,
   `colorScheme: "diverging"`, and the `regions` array from step 2. If any name is
   rejected, fix it from the suggestions (or a `list_map_communities` lookup) and
   re-emit — don't re-send the same bad name.

## Notes

- Dubai only. No other deployment has community boundaries, so `Map` isn't offered
  elsewhere.
- The valid set is names like `Business Bay`, `Trade Centre`, `Za'abeel`,
  `Al Quoz Industrial Area 1`, `Al Barsha South 3` — cadastral/community names,
  not marketing districts. When in doubt, search `list_map_communities`; it is the
  single source of truth for what the map can paint.
