import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PdfReader } from "./pdf-reader.js";

const TEST_PDF = "/tmp/test-pdf-with-images.pdf";

// Simulate what OpenCode's read tool returns for a PDF file
function makeReadOutput(pdfPath) {
  const pdfBytes = readFileSync(pdfPath);
  const b64 = pdfBytes.toString("base64");
  return {
    title: pdfPath,
    output: "PDF read successfully",
    metadata: { preview: "PDF read successfully", truncated: false, loaded: [] },
    attachments: [
      {
        type: "file",
        mime: "application/pdf",
        url: `data:application/pdf;base64,${b64}`,
        id: "prt_0194c8a00001AbCdEfGhIjKlMn",
        sessionID: "ses_test123",
        messageID: "msg_test456",
      },
    ],
  };
}

describe("PdfReader plugin", async () => {
  let hook;

  before(async () => {
    const plugin = await PdfReader();
    hook = plugin["tool.execute.after"];
  });

  it("skips non-read tools", async () => {
    const output = { output: "original", attachments: [] };
    await hook({ tool: "write", args: { filePath: "/foo.pdf" } }, output);
    assert.equal(output.output, "original");
  });

  it("skips non-PDF files", async () => {
    const output = { output: "original", attachments: [] };
    await hook({ tool: "read", args: { filePath: "/foo.txt" } }, output);
    assert.equal(output.output, "original");
  });

  it("extracts text and images from a PDF with images", async () => {
    const input = { tool: "read", args: { filePath: TEST_PDF } };
    const output = makeReadOutput(TEST_PDF);

    await hook(input, output);

    // Should have replaced output with extracted markdown
    assert.ok(output.output.includes("<content>"), "output should contain <content> tag");
    assert.ok(
      output.output.includes("Test PDF with image"),
      "output should contain PDF text content",
    );

    // Should have image attachments with valid prt_ prefixed IDs
    assert.ok(output.attachments.length > 0, "should have image attachments");
    for (const att of output.attachments) {
      assert.equal(att.type, "file", "attachment type should be file");
      assert.equal(att.mime, "image/png", "attachment mime should be image/png");
      assert.ok(att.url.startsWith("data:image/png;base64,"), "attachment should be base64 PNG");
      assert.ok(att.id.startsWith("prt_"), `attachment ID "${att.id}" must start with "prt_"`);
      assert.equal(att.sessionID, "ses_test123", "should inherit sessionID from original");
      assert.equal(att.messageID, "msg_test456", "should inherit messageID from original");
    }
  });

  it("generates unique IDs per image attachment", async () => {
    const input = { tool: "read", args: { filePath: TEST_PDF } };
    const output = makeReadOutput(TEST_PDF);

    await hook(input, output);

    const ids = output.attachments.map((a) => a.id);
    const unique = new Set(ids);
    assert.equal(ids.length, unique.size, "all attachment IDs should be unique");
  });

  it("clears attachments when extraction produces no text", async () => {
    const input = { tool: "read", args: { filePath: TEST_PDF } };
    // Simulate a PDF attachment that decodes to garbage (not a valid PDF)
    const output = {
      output: "PDF read successfully",
      attachments: [
        {
          type: "file",
          mime: "application/pdf",
          url: "data:application/pdf;base64,bm90YXBkZg==",
          id: "prt_0194c8a00001AbCdEfGhIjKlMn",
          sessionID: "ses_test123",
          messageID: "msg_test456",
        },
      ],
    };

    await hook(input, output);

    // Should fail gracefully — extraction error, attachments cleared
    assert.ok(
      output.output.includes("failed") || output.output.includes("no extractable text"),
      "should indicate failure or no text",
    );
    assert.deepEqual(output.attachments, [], "attachments should be cleared on failure");
  });

  it("handles PDF with no attachments (no-op)", async () => {
    const output = { output: "some output", attachments: [] };
    await hook({ tool: "read", args: { filePath: "/some.pdf" } }, output);
    assert.equal(output.output, "some output", "should not modify output when no PDF attachment");
  });
});
