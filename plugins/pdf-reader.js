import { execSync } from "node:child_process";
import { writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

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

      const tmpPdf = join(tmpdir(), `opencode-pdf-${Date.now()}.pdf`);
      try {
        writeFileSync(tmpPdf, Buffer.from(match[1], "base64"));

        const script = join(__dirname, "extract_pdf.py");
        const md = execSync(`python3 "${script}" "${tmpPdf}"`, {
          encoding: "utf-8",
          timeout: 60000,
          maxBuffer: 10 * 1024 * 1024,
        });

        if (md.trim().length === 0) {
          output.output =
            "PDF read successfully but no extractable text found (may be image-based).";
          output.attachments = [];
          return;
        }

        output.output = `<path>${filePath}</path>\n<type>file</type>\n<content>${md}</content>`;
        output.attachments = [];
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
