// Contract test for every skills/*/SKILL.md manifest.
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
const SKILLS_DIR = join(__dirname, "..", "skills");

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
  return readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .filter((name) => existsSync(join(SKILLS_DIR, name, "SKILL.md")));
}

describe("SKILL.md manifests", () => {
  const skills = listSkillDirs();

  it("at least one skill exists", () => {
    assert.ok(skills.length > 0, `no skills with SKILL.md found under ${SKILLS_DIR}`);
  });

  for (const skill of skills) {
    describe(skill, () => {
      const manifestPath = join(SKILLS_DIR, skill, "SKILL.md");
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
        assert.equal(fields.name, skill, `${manifestPath} declares name="${fields.name}" but lives in skills/${skill}/`);
      });

      it("all ${CLAUDE_SKILL_DIR} script paths exist and stay inside the skill dir", () => {
        const tools = fields["allowed-tools"] || "";
        const re = /\$\{CLAUDE_SKILL_DIR\}\/([A-Za-z0-9._\/-]+)/g;
        const skillRoot = resolve(SKILLS_DIR, skill);
        const seen = new Set();
        for (const m of tools.matchAll(re)) {
          const rel = m[1];
          if (seen.has(rel)) continue;
          seen.add(rel);
          const fullPath = resolve(skillRoot, rel);
          assert.ok(
            fullPath === skillRoot || fullPath.startsWith(skillRoot + sep),
            `${manifestPath} references \${CLAUDE_SKILL_DIR}/${rel} which resolves outside skills/${skill}/`
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
