---
name: polymarket
description: Query Polymarket prediction markets -- search markets, get prices/odds, view order books, check positions, and browse events. Use when the user asks about prediction markets, probabilities of events, market odds, or Polymarket data.
allowed-tools: Bash(polymarket *)
---

# Polymarket CLI

Query Polymarket prediction markets using the `polymarket` CLI. Most read commands need no wallet.

## Market Discovery

```bash
# List active markets
polymarket -o json markets list --limit 10

# Search markets by keyword
polymarket -o json markets search "bitcoin"

# Get specific market details
polymarket -o json markets get <market-id-or-slug>

# Browse events by tag
polymarket -o json events list --tag politics

# List available tags
polymarket -o json tags list
```

## Prices and Order Book

```bash
# Get current price for a token
polymarket -o json clob price <token-id> --side buy

# Get midpoint price
polymarket -o json clob midpoint <token-id>

# View full order book
polymarket -o json clob book <token-id>

# Price history (intervals: 1m, 1h, 6h, 1d, 1w, max)
polymarket -o json clob price-history <token-id> --interval 1d
```

## Portfolio and Data (requires wallet or address)

```bash
# Check positions for an address
polymarket -o json data positions 0x<wallet-address>

# Portfolio value
polymarket -o json data value 0x<wallet-address>

# Leaderboard
polymarket -o json data leaderboard --period month --order-by pnl
```

## Tips

- Always use `-o json` for structured output agents can parse
- Market discovery commands (markets, events, tags) need no auth
- Price/orderbook commands need a token ID from market details
- Set `POLYMARKET_PRIVATE_KEY` env var for authenticated commands

## Reference

For full command reference and trading commands, see [reference.md](reference.md).
