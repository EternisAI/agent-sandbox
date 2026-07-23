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

## Deployment (GitOps)

Deployment is a **separate concern** from the build/release workflows, which
only publish images. A deploy is a GitOps push: bump the image tag + digest in a
manifest in the target GitOps repo, commit as the Eternis DevOps Bot, push back,
and let Flux reconcile it onto the cluster. To support this handoff, each
producing job emits a small **`deploy-info` artifact** (JSON: `image`, `tag`,
`digest`, `git_sha`, `ref`, `environment`):

| Source | Image | Environment | Deploy workflow |
|--------|-------|-------------|-----------------|
| `build.yml` (main push) | `agent-sandbox` | `staging` | forthcoming |
| `release.yml` (regular) | `agent-sandbox` | `production` | forthcoming |
| `release.yml` (thai) | `agent-sandbox-thailand` | `siam-ai` | **`deploy-thailand.yml`** |

### `deploy-thailand.yml` — Thai image → `siam-ai` (implemented)

Pins `agent-sandbox-thailand` in the `EternisAI/gitops-siam-ai` repo
(`apps/clusters/oa1/axion/app/release/values.yaml`, keys
`axion.sandbox.image.tag` / `.digest`). Two entry points:

- **`workflow_run`** after "Release (promote tag)" succeeds — reads the released
  semver from that run's `deploy-info-siam-ai` artifact, then re-resolves the
  digest from GHCR.
- **`workflow_dispatch`** — deploys `inputs.image_tag` if set, else the
  dispatch branch's image (main / a feature branch).

What's pinned is always **immutable**: a semver (workflow_run or explicit input)
is pinned as-is, but an empty-input dispatch resolves the branch's moving tag
(`latest` / `<slug>`) and then **de-references it to the `sha-<short>` tag at the
same digest** — a mutable `latest` in a K8s manifest is a smell. (The build
pushes `sha-<short>` alongside every moving tag, so the match exists; the run
fails rather than pin a mutable tag if it somehow doesn't.)

The digest is always resolved from the registry (source of truth) and the run
**fails if the tag isn't published** — it never pins a non-existent image. The
`values.yaml` edit is a surgical `awk` line-replace anchored on the sandbox
image's `repository:` line, **not `yq`**: that file is human-maintained with
comments and alignment that `yq -i` would reflow. The edit is idempotent (a
re-run with the same pin is a no-op) and the push uses a rebase-retry loop to
survive a concurrent gitops push. It runs in the **`Axion Siam.AI`** GitHub
Environment (in THIS repo), which holds the `GITOPS_PAT` secret (fine-grained,
Contents:write on the gitops repo). No reconcile-watch is performed here (unlike
the axionhypothesis CD action) — that would add `KUBE_API_*` secrets +
`id-token` and is out of scope.

Notes for whoever wires up the remaining (staging / production) deploy workflows:

- The **registry is the source of truth** — `digest` is always re-resolvable
  from a tag via `oras resolve`, and images outlive artifacts. The artifact is
  therefore a short-lived (`retention-days: 7`) fast-path, not a record; deploys
  must tolerate its absence by reconstructing the digest, and fall back to a
  manual `workflow_dispatch` (with an explicit tag input) when the production
  semver can't be recovered.
- Deploys should pin by **digest** (`sha-<short>`/`<ver>` + `@sha256:…`), never
  the mutable `latest`. Builds set `provenance: false` / `sbom: false` so each
  push is a clean single-platform manifest with one stable digest.
- The fine-grained PAT used to push to the GitOps repo belongs in a **GitHub
  Environment** secret on the deploy workflow — never in these build workflows
  or this image. (`deploy-thailand.yml` already does this with `GITOPS_PAT` in
  the `Axion Siam.AI` environment; production/staging will each want their own.)
- The `deploy-info` artifact is produced with `actions/upload-artifact@v7`, so a
  deploy workflow that reads it must use `actions/download-artifact@v7` (upload
  and download artifacts are not compatible across majors) — as
  `deploy-thailand.yml` does on its `workflow_run` path.

## Skills

Skills live in `skills/<name>/SKILL.md` and are copied into every image at
`/home/sandbox/.agents/skills/`. The OpenCode runtime auto-discovers them; the
`description` frontmatter drives selection.

**The frontmatter must be valid YAML — this is stricter than Claude Code.**
Claude Code tolerates frontmatter that a real YAML parser rejects, so a manifest
copied from there can look fine and still be dropped here. The failure is
invisible: OpenCode silently skips a skill whose frontmatter does not parse (no
log line), and it does not consistently skip it — gray-matter caches the failed
parse, so OpenCode's sanitized-retry fallback rescues only the *first* parse in
a process. Since skills are rescanned per agent worktree, a broken manifest
loads for the first agent in a sandbox and disappears for every agent after it.
That is how `thai-government-data` never once loaded on Siam.

The trap in practice is a **`": "` inside an unquoted value** — a colon-space
starts a nested mapping, so one appearing mid-sentence makes the whole file
invalid:

```yaml
# BROKEN: "(state enterprise): population/census" makes this invalid YAML
description: Query Thai-government data (every ministry, department, province, state enterprise): population/census, public health, …

# CORRECT: a folded block scalar needs no escaping, ever
description: >-
  Query Thai-government data (every ministry, department, province, state enterprise): population/census, public health, …
```

Prefer `>-` over quoting: descriptions are long, punctuation-heavy prose that
already contains both apostrophes and `"quoted"` fragments, so single- and
double-quoting each need escaping that the next edit will get wrong. `>-` folds
to a single line and strips the trailing newline, so the parsed value is
identical to the plain form.

`plugins/validate_skills.py` is the contract — real YAML parse, required keys
(`name`, `description`, `allowed-tools`), `name` == directory,
`${CLAUDE_SKILL_DIR}` paths resolve. CI runs it with `--strict` via
`plugins/skill-manifests.test.js` (a violation fails the build); the sandbox
entrypoint runs it best-effort at container start, logging `WARN
skill-validation:` without wedging the sandbox. Check a manifest locally with:

```bash
python3 plugins/validate_skills.py --strict skills skills-thailand skills-dubai
```

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
- After a release, the deployed tag is updated: the **Thai** image auto-deploys
  to `siam-ai` via `deploy-thailand.yml` (GitOps push to `gitops-siam-ai`); the
  **regular** image's deploy is still forthcoming — today its tag lives in
  `backend-go/application.yaml` in the `axionhypothesis` repo.
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
