# Polymarket CLI Reference

## Installation

```bash
# macOS/Linux
brew tap Polymarket/polymarket-cli https://github.com/Polymarket/polymarket-cli
brew install polymarket

# or shell script
curl -sSL https://raw.githubusercontent.com/Polymarket/polymarket-cli/main/install.sh | sh

# or from source (requires Rust)
git clone https://github.com/Polymarket/polymarket-cli && cd polymarket-cli && cargo install --path .
```

## Authentication

Private key resolution (priority order):
1. `--private-key 0xabc...` flag
2. `POLYMARKET_PRIVATE_KEY` env var
3. `~/.config/polymarket/config.json`

Config file:
```json
{
  "private_key": "0x...",
  "chain_id": 137,
  "signature_type": "proxy"
}
```

Signature types: `proxy` (default), `eoa`, `gnosis-safe`

## All Commands

### Markets and Discovery (no auth)
| Command | Description |
|---------|-------------|
| `markets list --limit N` | List active markets |
| `markets search "term"` | Search markets |
| `markets get <id-or-slug>` | Market details |
| `events list --tag <tag>` | Events by tag |
| `tags list` | Available tags |
| `series list` | Market series |

### CLOB -- Prices (no auth)
| Command | Description |
|---------|-------------|
| `clob ok` | Health check |
| `clob price <token-id> --side buy` | Current price |
| `clob midpoint <token-id>` | Midpoint price |
| `clob book <token-id>` | Full order book |
| `clob price-history <token-id> --interval 1d` | Price history |

Price history intervals: `1m`, `1h`, `6h`, `1d`, `1w`, `max`

### CLOB -- Trading (auth required)
| Command | Description |
|---------|-------------|
| `clob create-order --token <id> --side buy --price 0.50 --size 10` | Limit order |
| `clob market-order --token <id> --side buy --amount 5` | Market order |
| `clob cancel <order-id>` | Cancel order |
| `clob cancel-all` | Cancel all |
| `clob orders` | Open orders |
| `clob trades` | Trade history |

### Data and Portfolio
| Command | Description |
|---------|-------------|
| `clob balance --asset-type collateral` | Balance (auth) |
| `data positions 0x<addr>` | Positions |
| `data value 0x<addr>` | Portfolio value |
| `data leaderboard --period month --order-by pnl` | Leaderboard |

### On-Chain
| Command | Description |
|---------|-------------|
| `approve check` | Check approvals |
| `approve set` | Set approvals |
| `ctf split --condition 0x... --amount 10` | Split tokens |
| `ctf merge --condition 0x... --amount 10` | Merge tokens |
| `ctf redeem --condition 0x...` | Redeem |

### Wallet
| Command | Description |
|---------|-------------|
| `wallet create` | New wallet |
| `wallet import 0x<key>` | Import key |
| `wallet address` | Show address |
| `wallet reset` | Reset config |

### Utility
| Command | Description |
|---------|-------------|
| `status` | API health |
| `shell` | Interactive REPL |
| `setup` | Setup wizard |

## Output

All commands support `-o json` for JSON output (default is table).
JSON mode outputs structured errors to stdout with non-zero exit codes.
