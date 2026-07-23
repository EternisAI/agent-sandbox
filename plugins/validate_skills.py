#!/usr/bin/env python3
"""Validate SKILL.md manifests against the repo's contract.

Single source of truth for that contract, used from two places so they can
never disagree (they did: both the CI test and the entrypoint warm-up used to
parse frontmatter with a line regex, and both reported four genuinely broken
manifests as valid):

  - CI, via plugins/skill-manifests.test.js, with --strict: a violation fails
    the build.
  - The sandbox entrypoint, at container start, best-effort: a violation is
    logged and startup continues, because a bad optional skill must not wedge
    the sandbox.

The contract:
  1. --- frontmatter delimiters are present.
  2. The frontmatter parses as strict YAML *on the first attempt* — explicitly
     not "parses after sanitization". OpenCode's loader retries a failed parse
     against a sanitized copy, but gray-matter caches the failure keyed on the
     original string, so every later parse in that process returns empty data
     without throwing and the skill is dropped with no log line. A manifest
     that only survives via the fallback therefore loads for the first agent in
     a sandbox and disappears for every agent after it.
  3. name, description and allowed-tools are present and non-empty.
  4. name equals the skill's directory name.
  5. Every ${CLAUDE_SKILL_DIR}/<path> in allowed-tools resolves to a file that
     exists and stays inside the skill directory.

Usage:
  validate_skills.py [--strict] [--marker PATH] ROOT [ROOT ...]
"""

import argparse
import os
import pathlib
import re
import sys

import yaml

REQUIRED_KEYS = ("name", "description", "allowed-tools")
FRONTMATTER = re.compile(r"^---\r?\n(.*?)\r?\n---", re.DOTALL)
SKILL_DIR_REF = re.compile(r"\$\{CLAUDE_SKILL_DIR\}/([A-Za-z0-9._/-]+)")


def validate(manifest: pathlib.Path) -> tuple[str | None, list[str]]:
    """Return (skill name, failures). The name is None when nothing loaded."""
    try:
        text = manifest.read_text(encoding="utf-8")
    except Exception as e:  # unreadable file, bad encoding
        return None, [f"{manifest}: unreadable: {e}"]

    m = FRONTMATTER.match(text)
    if not m:
        return None, [f"{manifest}: missing --- frontmatter"]

    try:
        data = yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        detail = str(e).splitlines()[0]
        hint = ""
        # By far the most common cause, and not obvious from the parser error:
        # an unquoted value containing ": " starts a nested mapping.
        if ": " in m.group(1):
            hint = ' — an unquoted value containing ": " must use a block scalar (description: >-)'
        return None, [f"{manifest}: frontmatter is not valid YAML: {detail}{hint}"]

    if not isinstance(data, dict):
        return None, [f"{manifest}: frontmatter is not a YAML mapping"]

    failures = []
    missing = [k for k in REQUIRED_KEYS if not data.get(k)]
    if missing:
        failures.append(f"{manifest}: missing frontmatter key(s): {', '.join(missing)}")

    name = data.get("name")
    if name and name != manifest.parent.name:
        failures.append(f'{manifest}: name="{name}" != dir "{manifest.parent.name}"')

    tools = data.get("allowed-tools") or ""
    if isinstance(tools, list):
        tools = " ".join(str(t) for t in tools)
    skill_root = manifest.parent.resolve()
    for rel in dict.fromkeys(SKILL_DIR_REF.findall(str(tools))):
        target = (skill_root / rel).resolve()
        if target != skill_root and not str(target).startswith(str(skill_root) + os.sep):
            failures.append(f"{manifest}: ${{CLAUDE_SKILL_DIR}}/{rel} resolves outside {manifest.parent.name}/")
        elif not target.is_file():
            failures.append(f"{manifest}: ${{CLAUDE_SKILL_DIR}}/{rel} does not exist")

    if failures:
        return None, failures
    return name, []


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("roots", nargs="+", help="directories containing <skill>/SKILL.md")
    ap.add_argument("--strict", action="store_true", help="exit non-zero on any violation (CI)")
    ap.add_argument("--marker", help="path to write the loaded-skill count to (runtime readiness)")
    args = ap.parse_args()

    # Invalidate any stale marker up front so an aborted scan can't leave a
    # previous run's count in place (matters only when the marker is on a
    # persistent path; /tmp is fresh per container).
    if args.marker:
        try:
            pathlib.Path(args.marker).unlink(missing_ok=True)
        except Exception as e:
            print(f"WARN skills-ready marker not cleared ({args.marker}): {e}", flush=True)

    loaded, failed = [], []
    for root in args.roots:
        p = pathlib.Path(root)
        if not p.is_dir():
            continue
        for manifest in sorted(p.glob("**/SKILL.md")):
            name, failures = validate(manifest)
            if name:
                loaded.append(name)
            failed.extend(failures)

    print(f"skill warm-up: {len(loaded)} loaded ({', '.join(sorted(loaded))}), {len(failed)} failed", flush=True)
    for f in failed:
        print(f"WARN skill-validation: {f}", flush=True)

    if args.marker:
        # Publish the count atomically (temp file in the same dir, then rename)
        # so a reader never sees a partial write and a failed run leaves no
        # marker at all.
        try:
            tmp = f"{args.marker}.tmp"
            with open(tmp, "w") as fh:
                fh.write(f"{len(loaded)}\n")
            os.replace(tmp, args.marker)
        except Exception as e:
            print(f"WARN skills-ready marker not written ({args.marker}): {e}", flush=True)

    if not loaded:
        print("WARN skill-validation: no SKILL.md found under " + ", ".join(args.roots), flush=True)
        if args.strict:
            return 1

    return 1 if (args.strict and failed) else 0


if __name__ == "__main__":
    sys.exit(main())
