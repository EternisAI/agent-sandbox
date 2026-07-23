// Contract test for every {skills,skills-thailand,skills-dubai}/*/SKILL.md manifest.
//
// The contract itself lives in plugins/validate_skills.py, which this test runs
// with --strict. It is shared with the sandbox entrypoint (best-effort mode
// there) so CI and the runtime can never disagree about what a valid manifest
// is — they did before: both parsed frontmatter with a line regex, and both
// passed four manifests whose YAML is genuinely invalid, one of which
// (thai-government-data) had never once loaded on the Siam deployment.
//
// Driving a Python checker from a node test mirrors pdf-reader.test.js, which
// exercises extract_pdf.py the same way. Requires PyYAML (pinned in the
// Dockerfile and installed by .github/workflows/test.yml).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");
const VALIDATOR = join(__dirname, "validate_skills.py");

// Base skills plus the region overlay dirs (Dockerfile.<region> COPYs each into
// the same runtime skills dir). Only dirs that exist are scanned, so adding a
// new overlay here before it exists is harmless.
const SKILL_ROOTS = ["skills", "skills-thailand", "skills-dubai"]
  .map((d) => join(REPO_ROOT, d))
  .filter((d) => existsSync(d));

describe("SKILL.md manifests", () => {
  it("all satisfy the manifest contract (validate_skills.py --strict)", () => {
    assert.ok(SKILL_ROOTS.length > 0, "no skill roots found");

    let output;
    try {
      output = execFileSync("python3", [VALIDATOR, "--strict", ...SKILL_ROOTS], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (e) {
      // Non-zero exit: the validator has already printed one WARN line per
      // violation, naming the file and what to fix. Surface them verbatim
      // rather than restating them less precisely.
      assert.fail(`${e.stdout ?? ""}${e.stderr ?? ""}`.trim() || String(e));
    }

    // Guard against the checker silently scanning nothing (a moved directory,
    // a bad glob): a passing run must report skills it actually loaded.
    const loaded = Number(output.match(/skill warm-up: (\d+) loaded/)?.[1] ?? 0);
    assert.ok(loaded > 0, `validator loaded no skills:\n${output}`);
  });
});
