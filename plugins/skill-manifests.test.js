// Contract test for every {skills,skills-thailand,skills-dubai}/*/SKILL.md manifest.
// Asserts:
//   1. YAML frontmatter exists and parses (start/end ---).
//   2. Required keys are present: name, description, allowed-tools.
//   3. `name` value matches the parent directory.
//   4. Any ${CLAUDE_SKILL_DIR}/<path> reference in allowed-tools resolves
//      to an existing file under the skill's directory.
//
// Lightweight on purpose: no js-yaml dependency, frontmatter is parsed by
// a small regex. New required keys can be added to REQUIRED_KEYS below.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, dirname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const REQUIRED_KEYS = ["name", "description", "allowed-tools"];

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");
// Base skills plus the region overlay dirs (Dockerfile.<region> COPYs each into
// the same runtime skills dir). Only dirs that exist are scanned, so adding a
// new overlay here before it exists is harmless.
const SKILL_ROOTS = ["skills", "skills-thailand", "skills-dubai"]
  .map((d) => join(REPO_ROOT, d))
  .filter((d) => existsSync(d));

function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return null;
  const body = match[1];
  const fields = {};
  for (const line of body.split(/\r?\n/)) {
    const m = line.match(/^([A-Za-z_-][A-Za-z0-9_-]*):\s*(.*)$/);
    if (m) fields[m[1]] = m[2].trim();
  }
  return fields;
}

function listSkillDirs() {
  const out = [];
  for (const root of SKILL_ROOTS) {
    for (const d of readdirSync(root, { withFileTypes: true })) {
      if (d.isDirectory() && existsSync(join(root, d.name, "SKILL.md"))) {
        out.push({ name: d.name, root });
      }
    }
  }
  return out;
}

describe("SKILL.md manifests", () => {
  const skills = listSkillDirs();

  it("at least one skill exists", () => {
    assert.ok(skills.length > 0, `no skills with SKILL.md found under ${SKILL_ROOTS.join(", ")}`);
  });

  for (const { name: skill, root } of skills) {
    describe(skill, () => {
      const manifestPath = join(root, skill, "SKILL.md");
      const content = readFileSync(manifestPath, "utf8");
      const fields = parseFrontmatter(content);

      it("has parseable frontmatter", () => {
        assert.ok(fields, `${manifestPath} is missing --- frontmatter delimiters`);
      });

      for (const key of REQUIRED_KEYS) {
        it(`frontmatter contains ${key}`, () => {
          assert.ok(fields[key], `${manifestPath} is missing required field "${key}"`);
        });
      }

      it("name matches the parent directory", () => {
        assert.equal(fields.name, skill, `${manifestPath} declares name="${fields.name}" but lives in ${skill}/`);
      });

      it("all ${CLAUDE_SKILL_DIR} script paths exist and stay inside the skill dir", () => {
        const tools = fields["allowed-tools"] || "";
        const re = /\$\{CLAUDE_SKILL_DIR\}\/([A-Za-z0-9._\/-]+)/g;
        const skillRoot = resolve(root, skill);
        const seen = new Set();
        for (const m of tools.matchAll(re)) {
          const rel = m[1];
          if (seen.has(rel)) continue;
          seen.add(rel);
          const fullPath = resolve(skillRoot, rel);
          assert.ok(
            fullPath === skillRoot || fullPath.startsWith(skillRoot + sep),
            `${manifestPath} references \${CLAUDE_SKILL_DIR}/${rel} which resolves outside ${skill}/`
          );
          assert.ok(
            existsSync(fullPath) && statSync(fullPath).isFile(),
            `${manifestPath} references \${CLAUDE_SKILL_DIR}/${rel} but ${fullPath} does not exist`
          );
        }
      });
    });
  }
});
