import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { PdfReader } from "./pdf-reader.js";
import { readFileSync } from "node:fs";

const TEST_PDF = "/tmp/test-pdf-with-images.pdf";

describe("PdfReader plugin", async () => {
  let hook;

  before(async () => {
    const plugin = await PdfReader();
    hook = plugin["tool.execute.before"];
  });

  it("skips non-read tools", async () => {
    const output = { args: { filePath: "/foo.pdf" } };
    await hook({ tool: "write" }, output);
    assert.equal(output.args.filePath, "/foo.pdf");
  });

  it("skips non-PDF files", async () => {
    const output = { args: { filePath: "/foo.txt" } };
    await hook({ tool: "read" }, output);
    assert.equal(output.args.filePath, "/foo.txt");
  });

  it("rewrites PDF path to extracted .md file", async () => {
    const output = { args: { filePath: TEST_PDF } };
    await hook({ tool: "read" }, output);

    assert.ok(output.args.filePath.endsWith(".md"), "filePath should be rewritten to .md");
    assert.notEqual(output.args.filePath, TEST_PDF, "filePath should differ from original");

    const content = readFileSync(output.args.filePath, "utf-8");
    assert.ok(content.includes("Hello World"), "extracted content should contain PDF text");
  });

  it("caches extraction (second call is instant)", async () => {
    const output = { args: { filePath: TEST_PDF } };
    const start = Date.now();
    await hook({ tool: "read" }, output);
    assert.ok(Date.now() - start < 100, "cached extraction should be near-instant");
    assert.ok(output.args.filePath.endsWith(".md"));
  });

  it("passes through missing files (ENOENT)", async () => {
    const output = { args: { filePath: "/tmp/nonexistent.pdf" } };
    await hook({ tool: "read" }, output);
    assert.equal(output.args.filePath, "/tmp/nonexistent.pdf", "should not modify path for missing file");
  });

  it("throws with instructions on extraction failure", async () => {
    const { writeFileSync } = await import("node:fs");
    const badPdf = "/tmp/bad-test.pdf";
    writeFileSync(badPdf, "not a real pdf");
    const output = { args: { filePath: badPdf } };
    await assert.rejects(
      () => hook({ tool: "read" }, output),
      (err) => {
        assert.ok(err.message.includes("PDF extraction failed"), "should mention extraction failure");
        assert.ok(err.message.includes("pymupdf4llm"), "should suggest pymupdf4llm fallback");
        return true;
      },
    );
  });

  it("is non-blocking (returns a promise)", async () => {
    const plugin = await PdfReader();
    const beforeHook = plugin["tool.execute.before"];
    const output = { args: { filePath: TEST_PDF } };
    const result = beforeHook({ tool: "read" }, output);
    assert.ok(result instanceof Promise, "hook should return a promise (async/non-blocking)");
    await result;
  });
});
