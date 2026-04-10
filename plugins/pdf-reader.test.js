import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { PdfReader } from "./pdf-reader.js";
import { existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CACHE_DIR = join(tmpdir(), "opencode-pdf-cache");
const TEST_PDF_TEXT = "/tmp/test-text-small.pdf";
const TEST_PDF_IMAGES = "/tmp/test-image-small.pdf";

async function simulateRead(beforeHook, afterHook, filePath) {
  const beforeOutput = { args: { filePath } };
  await beforeHook({ tool: "read" }, beforeOutput);
  const redirected = beforeOutput.args.filePath !== filePath;

  const afterOutput = { output: "(content)", attachments: [] };
  await afterHook({ tool: "read", args: { filePath: beforeOutput.args.filePath } }, afterOutput);
  return { ...afterOutput, redirected, redirectedPath: beforeOutput.args.filePath };
}

describe("PdfReader plugin", () => {
  let beforeHook;
  let afterHook;

  before(async () => {
    execSync("rm -rf " + CACHE_DIR);
    const plugin = await PdfReader();
    beforeHook = plugin["tool.execute.before"];
    afterHook = plugin["tool.execute.after"];
  });

  it("skips non-read tools", async () => {
    const output = { args: { filePath: "/foo.pdf" } };
    await beforeHook({ tool: "write" }, output);
    assert.equal(output.args.filePath, "/foo.pdf");
  });

  it("skips non-PDF files", async () => {
    const output = { args: { filePath: "/foo.txt" } };
    await beforeHook({ tool: "read" }, output);
    assert.equal(output.args.filePath, "/foo.txt");
  });

  it("redirects PDF to markdown and adds page images", async () => {
    if (!existsSync(TEST_PDF_TEXT)) return;

    const result = await simulateRead(beforeHook, afterHook, TEST_PDF_TEXT);
    assert.ok(result.redirected, "before hook should redirect filePath");
    const jpgs = result.attachments.filter(a => a.mime === "image/jpeg");
    assert.ok(jpgs.length >= 1, `should have page images, got ${jpgs.length}`);
  });

  it("does not re-inject images on second read of cached markdown", async () => {
    if (!existsSync(TEST_PDF_TEXT)) return;

    // First read sets up the cache
    await simulateRead(beforeHook, afterHook, TEST_PDF_TEXT);

    // Second read of the same cached .md — after hook must NOT inject images
    const afterOutput = { output: "(cached)", attachments: [] };
    await afterHook({ tool: "read", args: { filePath: join(CACHE_DIR, "anything.md") } }, afterOutput);
    assert.equal(afterOutput.attachments.length, 0, "no images on second read");
  });

  it("renders page images from image-based PDF", async () => {
    if (!existsSync(TEST_PDF_IMAGES)) return;
    execSync("rm -rf " + CACHE_DIR);

    const result = await simulateRead(beforeHook, afterHook, TEST_PDF_IMAGES);
    assert.ok(result.redirected, "before hook should redirect");
    const jpgs = result.attachments.filter(a => a.mime === "image/jpeg");
    assert.ok(jpgs.length >= 1, `should have page images, got ${jpgs.length}`);
    for (const att of jpgs) {
      assert.ok(att.url.startsWith("data:image/jpeg;base64,"), "JPEG data URL");
    }
  });

  it("uses cache on second read", async () => {
    if (!existsSync(TEST_PDF_TEXT)) return;

    const start = Date.now();
    const result = await simulateRead(beforeHook, afterHook, TEST_PDF_TEXT);
    assert.ok(Date.now() - start < 100, "cached read should be fast");
    assert.ok(result.redirected, "cached read still redirects");
  });
});
