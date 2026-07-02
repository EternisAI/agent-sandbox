---
name: axion-memory
description: Read curated memory about the user and about Axion's own accumulated knowledge, staged read-only at /data/memory. Use to recall who the user is, their durable positions, durable facts on companies/tickers, and lessons Axion has learned about its own forecasting — before researching from scratch.
allowed-tools: Bash(cat /data/memory/*), Bash(ls /data/memory*), Bash(grep * /data/memory*)
---

# Axion Memory (read-only)

`/data/memory/` may hold curated context the backend staged for this thread. It
is **optional background**: consult it when relevant, never depend on it, and it
may be empty or absent. **Never write to it** — it is rebuilt centrally.

## What's there

- `profile.md` — a dated prior on who the user is and what they care about.
  Treat it as a hypothesis, not ground truth. Let fresh evidence in the current
  thread override it, and never let a stored profile bias an objective analysis.
- `theses/<slug>.md` — the user's durable, high-conviction positions.
- `shared/INDEX.md` — a map of Axion's cross-user knowledge.
- `shared/entities/<ticker>.md` — durable, factual dossiers on companies/assets.
- `shared/lessons/forecasting.md` — patterns Axion has distilled about its own
  forecasting (e.g. where it tends to be overconfident).

Every file carries YAML frontmatter (`title`, `type`, `updated`, …). Check
`updated` to judge staleness before leaning on a fact.

## How to read it

Plain Markdown files — read them with your normal tools. The directory may be
absent (nothing staged); check before assuming it's there.

```bash
ls -R /data/memory                          # what's staged (empty/absent = no memory)
cat /data/memory/profile.md                 # the user profile
cat /data/memory/theses/*.md                # the user's durable positions
cat /data/memory/shared/INDEX.md            # the shared knowledge index
cat /data/memory/shared/entities/nvda.md    # a company dossier
grep -rin "datacenter capex" /data/memory   # search across all files
```

Your built-in `read` / `grep` / `list` tools work just as well.

## When to use it

- At the start of a user-specific task, glance at `profile.md` and `theses/` to
  ground your framing.
- Before researching a company from scratch, check
  `shared/entities/<ticker>.md` for durable facts already on file.
- When forecasting, skim `shared/lessons/forecasting.md` for known failure modes
  to correct for.

Pull in only what bears on the current task. Do not dump memory into your
output, and always prefer fresh, thread-specific evidence over a stored prior.
