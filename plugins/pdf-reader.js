import { execFileSync } from "node:child_process";
import { writeFileSync, unlinkSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const MAX_PDF_BASE64 = 100 * 1024 * 1024; // 100MB base64 (~75MB PDF)
const MAX_IMAGES = 20;

export const PdfReader = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "read") return;

      const filePath = input.args?.filePath || "";
      if (!filePath.toLowerCase().endsWith(".pdf")) return;

      const attachments = output.attachments || [];
      const pdfAttachment = attachments.find(
        (a) => a.mime === "application/pdf" && a.url,
      );
      if (!pdfAttachment) return;

      const match = pdfAttachment.url.match(
        /^data:application\/pdf;base64,(.+)$/,
      );
      if (!match) return;

      if (match[1].length > MAX_PDF_BASE64) {
        output.output = `PDF too large to extract (>${Math.round(MAX_PDF_BASE64 * 3 / 4 / 1024 / 1024)}MB). The file exists at ${filePath}.`;
        output.attachments = [];
        return;
      }

      const tmpPdf = join(tmpdir(), `opencode-pdf-${Date.now()}.pdf`);
      try {
        writeFileSync(tmpPdf, Buffer.from(match[1], "base64"));

        const script = join(__dirname, "extract_pdf.py");
        const raw = execFileSync("python3", [script, tmpPdf], {
          encoding: "utf-8",
          timeout: 120000,
          maxBuffer: 50 * 1024 * 1024,
        });

        const result = JSON.parse(raw);
        const md = result.markdown || "";

        if (md.trim().length === 0) {
          output.output =
            "PDF read successfully but no extractable text found (may be image-based).";
          output.attachments = [];
          return;
        }

        let content = md;
        if (result.truncated) {
          const imgNote = result.total_images > 0
            ? `\n\n⚠️ IMAGES NOT EXTRACTED: This PDF contains ${result.total_images} embedded images (charts, graphs, figures) that were not included due to document size. To extract images from specific pages, use pymupdf:\n\`\`\`python\nimport pymupdf, base64\ndoc = pymupdf.open("${filePath}")\npage = doc[PAGE_NUMBER]  # 0-indexed\nfor img in page.get_images():\n    xref = img[0]\n    pix = pymupdf.Pixmap(doc, xref)\n    pix.save(f"image_{xref}.png")\n\`\`\`\n`
            : "";
          content += `\n\n---\n⚠️ DOCUMENT TRUNCATED: Only ${result.pages_extracted} of ${result.total_pages} pages shown (~50K token limit). To analyze remaining pages, write a Python script using pymupdf and pymupdf4llm (both pre-installed). The PDF is at: ${filePath}`;
          content += imgNote;
          content += `\nTo extract text from specific pages:\n\`\`\`python\nimport pymupdf4llm\nmd = pymupdf4llm.to_markdown("${filePath}", pages=list(range(START, END)))\nprint(md)\n\`\`\`\n`;
          if (result.toc) {
            content += `\nTable of Contents:\n${result.toc}\n`;
          }
        }

        output.output = `<path>${filePath}</path>\n<type>file</type>\n<content>${content}</content>`;

        // Generate unique IDs per image attachment, inheriting session/message metadata
        const images = (result.images || []).slice(0, MAX_IMAGES);
        output.attachments = images.map((b64) => ({
          ...pdfAttachment,
          id: randomUUID(),
          mime: "image/png",
          url: `data:image/png;base64,${b64}`,
        }));
      } catch (e) {
        output.output = `PDF text extraction failed: ${e.message}. The file exists at ${filePath}.`;
        output.attachments = [];
      } finally {
        try {
          unlinkSync(tmpPdf);
        } catch {}
      }
    },
  };
};
