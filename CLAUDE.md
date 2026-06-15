# Agent Sandbox

Docker image for OpenCode agent sessions. Published to `ghcr.io/eternisai/agent-sandbox`.

## Build and Push

```bash
docker buildx build --platform linux/amd64 -t ghcr.io/eternisai/agent-sandbox:<version> --push .
```

After pushing, update the tag in `backend-go/application.yaml` in the `axionhypothesis` repo.

## Skills

Skills live in `skills/<name>/SKILL.md` and are copied into every image at
`/home/sandbox/.agents/skills/`. The OpenCode runtime auto-discovers them; the
`description` frontmatter drives selection.

**Per-customer skills are kept out of the default image.** Customer-specific
skills live in a sibling `skills-<customer>/` dir (NOT `skills/`) and are layered
on only by that customer's overlay image — see the Thai-government image below.

## Thai-government image

`ghcr.io/eternisai/agent-sandbox-thailand` is the default image **plus** the
Thailand-only skills in `skills-thailand/` (today: `thai-government-data`,
covering the data.go.th and Parliament CKAN portals). It is a thin overlay built
from `Dockerfile.thailand`, which `FROM`s the default image and copies
`skills-thailand/` on top — so the two never drift and the Thai skills ship in
this image only.

```bash
docker build -f Dockerfile.thailand \
  --build-arg BASE_IMAGE=ghcr.io/eternisai/agent-sandbox:<tag> \
  -t ghcr.io/eternisai/agent-sandbox-thailand:<tag> .
```

CI: `.github/workflows/build-thailand.yml` runs after the default "Build and
Push" workflow succeeds and overlays that same commit's base image. At runtime
the Thai sandbox must inject `THAI_DATA_PROXY_URL` (the Thai egress proxy
endpoint, with creds) so `thai-government-data` can reach the geo-blocked
`.go.th` portals.

## Versioning

- Always use versioned tags (e.g. `0.3.0`), never `:latest`
- Pin all tool versions in the Dockerfile (opencode-ai, Node.js, pnpm, uv, etc.)

## Data Persistence

The `/data` directory is mounted as an S3-backed bucket per thread:

- `/data/opencode` -- OpenCode database and state (configured via `OPENCODE_DB` env var in `entrypoint.sh`)
- `/data/workspaces` -- per-agent working directories

When a sandbox is destroyed and recreated for the same thread, the bucket restores `/data` so sessions and workspaces persist.
