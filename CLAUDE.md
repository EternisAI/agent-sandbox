# Agent Sandbox

Docker image for OpenCode agent sessions. Published to `ghcr.io/eternisai/agent-sandbox`.

## Build and Push

```bash
docker buildx build --platform linux/amd64 -t ghcr.io/eternisai/agent-sandbox:<version> --push .
```

After pushing, update the tag in `backend-go/application.yaml` in the `axionhypothesis` repo.

## Versioning

- Always use versioned tags (e.g. `0.3.0`), never `:latest`
- Pin all tool versions in the Dockerfile (opencode-ai, Node.js, pnpm, uv, etc.)

## Data Persistence

The `/data` directory is mounted as an S3-backed bucket per thread:

- `/data/opencode` -- OpenCode database and state (configured via `OPENCODE_DB` env var in `entrypoint.sh`)
- `/data/workspaces` -- per-agent working directories

When a sandbox is destroyed and recreated for the same thread, the bucket restores `/data` so sessions and workspaces persist.
