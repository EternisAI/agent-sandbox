# Agent Sandbox

Docker image for OpenCode agent sessions. Published to `ghcr.io/eternisai/agent-sandbox`.

## Images

- **`ghcr.io/eternisai/agent-sandbox`** — the default image (`Dockerfile`).
- **`ghcr.io/eternisai/agent-sandbox-thailand`** — a thin overlay
  (`Dockerfile.thailand`) of the default image plus the Thailand-only skills in
  `skills-thailand/`. See the Thai-government image section below.

## CI pipelines

Three workflows in `.github/workflows/`. None of the build/overlay workflows
have a tag trigger — semver releases flow exclusively through `release.yml`,
which keeps `paths:` filtering correct (a tag push usually introduces zero
changed files, so a `paths:`-filtered tag trigger would be silently skipped).

### `build.yml` — default image, continuous

- **Triggers:** push to `main` (path-scoped to `Dockerfile`, `skills/**`,
  `plugins/**`, `agent/**`, `entrypoint.sh`, and the workflow file);
  `workflow_dispatch`.
- **Tags pushed:** `sha-<short>` always (immutable per-commit handle);
  `latest` on `main`; `<branch-slug>` for a manual dispatch from a feature
  branch.
- On success it triggers `build-thailand.yml` (via `workflow_run`).

### `build-thailand.yml` — overlay image, continuous

- **Triggers:**
  - `workflow_run` after "Build and Push" — overlays that exact commit's base
    (`agent-sandbox:sha-<short>`) and mirrors its moving tag.
  - `push` to `main` scoped to `skills-thailand/**` / `Dockerfile.thailand` /
    the workflow file — overlays the current `latest` base when only Thai
    skills changed. A guard skips this build when base-image paths *also*
    changed in the same push (the `workflow_run` path rebuilds off the fresh
    base instead, avoiding a duplicate build that would overlay a stale base).
  - `workflow_dispatch` with a `base_tag` input (default `latest`).

### `release.yml` — promote to a semver tag

- **Trigger:** pushing a `vX.Y.Z` git tag.
- **Image tag:** the leading `v` is stripped (`v0.3.0` → image `0.3.0`).
- **Behaviour:** it **promotes** (`oras tag`) the commit's already-built
  `sha-<short>` image to the version tag rather than rebuilding — so the
  released bytes are byte-identical to what CI built and staging tested, and
  immune to dependency drift from the Dockerfile's floating pins
  (`nodejs=24.7.*`, unpinned apt). A full build happens only as a fallback when
  the `sha-<short>` image doesn't exist (e.g. tagging a commit whose base build
  never ran). The Thai overlay mirrors the regular image's mode (promote when
  the regular image was promoted and `thai:sha-<short>` exists; otherwise
  rebuild the overlay off `agent-sandbox:<ver>`) so the released Thai image
  always sits on the exact regular image being released.

`concurrency` is set on all three: branch builds use
`cancel-in-progress: true` (newest commit on a ref wins); `release.yml` uses
`cancel-in-progress: false` (never cancel a release mid-flight).

### Manual / local build

Still works for ad-hoc builds (CI handles the versioned tags automatically):

```bash
docker buildx build --platform linux/amd64 -t ghcr.io/eternisai/agent-sandbox:<tag> --push .
```

## Deployment (GitOps — forthcoming)

Deployment is performed by separate workflows (a GitOps repo integration) and
is **not** part of this repo's build/release workflows — those only publish
images. To support it, each producing job emits a small **`deploy-info`
artifact** (JSON: `image`, `tag`, `digest`, `git_sha`, `ref`, `environment`)
that a downstream deploy workflow reads to substitute the image tag + digest in
the target Kubernetes manifest:

| Source | Image | Environment |
|--------|-------|-------------|
| `build.yml` (main push) | `agent-sandbox` | `staging` |
| `release.yml` (regular) | `agent-sandbox` | `production` |
| `release.yml` (thai) | `agent-sandbox-thailand` | `siam-ai` |

Notes for whoever wires up the deploy workflows:

- The **registry is the source of truth** — `digest` is always re-resolvable
  from a tag via `oras resolve`, and images outlive artifacts. The artifact is
  therefore a short-lived (`retention-days: 7`) fast-path, not a record; deploys
  must tolerate its absence by reconstructing the digest, and fall back to a
  manual `workflow_dispatch` (with an explicit tag input) when the production
  semver can't be recovered.
- Deploys should pin by **digest** (`sha-<short>`/`<ver>` + `@sha256:…`), never
  the mutable `latest`. Builds set `provenance: false` / `sbom: false` so each
  push is a clean single-platform manifest with one stable digest.
- The Thai image for a specific branch (`latest` for main, `<slug>` for a
  feature branch built via dispatch) can be deployed to `siam-ai` by a manual
  deploy dispatch that resolves the tag → digest on demand.
- The fine-grained PAT used to push to the GitOps repo belongs in a **GitHub
  Environment** secret on the deploy workflow — never in these build workflows
  or this image.
- The `deploy-info` artifact is produced with `actions/upload-artifact@v7`, so a
  deploy workflow that reads it must use `actions/download-artifact@v7` (upload
  and download artifacts are not compatible across majors).

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
from `Dockerfile.thailand`, which `FROM`s an ARG-templated base image (default
`latest`) and copies `skills-thailand/` on top — so the two never drift and the
Thai skills ship in this image only.

```bash
docker build -f Dockerfile.thailand \
  --build-arg BASE_IMAGE=ghcr.io/eternisai/agent-sandbox:<tag> \
  -t ghcr.io/eternisai/agent-sandbox-thailand:<tag> .
```

CI builds it via `build-thailand.yml` (see CI pipelines above). The
`thai-government-data` skill reaches the geo-blocked `.go.th` portals through the
Axion backend's Thai egress proxy (`/api/thaidata-proxy`), using the standard
`PROXY_BASE_URL` / `PROXY_API_KEY` env every sandbox already gets — no
Thai-specific runtime env is required. The backend egress endpoint and its
credentials live in backend config (`thaidata.proxyUrl`), never in this image.

## Versioning

- Cut a release by pushing a `vX.Y.Z` git tag; `release.yml` promotes the
  built image to the `X.Y.Z` image tag. Reference released images by the
  versioned tag (and ideally its digest), never `:latest`.
- After a release, update the deployed tag — via the GitOps repo (forthcoming)
  or, today, the tag in `backend-go/application.yaml` in the `axionhypothesis`
  repo.
- Pin all tool versions in the Dockerfile (opencode-ai, Node.js, pnpm, uv, etc.).

## Build context

`.dockerignore` is **shared** by `Dockerfile` and `Dockerfile.thailand` (same
`context: .`). It excludes only paths neither image COPYs (`.git`, `.github`,
docs, scratch dirs, env/OS cruft). It must **not** exclude `skills-thailand/`
or the Dockerfiles.

## Data Persistence

The `/data` directory is mounted as an S3-backed bucket per thread:

- `/data/opencode` -- OpenCode database and state (configured via `OPENCODE_DB` env var in `entrypoint.sh`)
- `/data/workspaces` -- per-agent working directories

When a sandbox is destroyed and recreated for the same thread, the bucket restores `/data` so sessions and workspaces persist.
