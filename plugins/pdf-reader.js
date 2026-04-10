import { execFileSync } from "node:child_process";
import { statSync, existsSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const CACHE_DIR = join(tmpdir(), "opencode-pdf-cache");

function cacheKey(filePath, stat) {
  return createHash("sha256")
    .update(`${filePath}:${stat.size}:${stat.mtimeMs}`)
    .digest("hex");
}

function extractPdf(filePath) {
  const stat = statSync(filePath);
  const key = cacheKey(filePath, stat);
  const cachedMd = join(CACHE_DIR, `${key}.md`);

  if (existsSync(cachedMd)) {
    return cachedMd;
  }

  mkdirSync(CACHE_DIR, { recursive: true });

  const script = join(__dirname, "extract_pdf.py");
  execFileSync("python3", [script, filePath, cachedMd], {
    encoding: "utf-8",
    timeout: 120000,
    maxBuffer: 50 * 1024 * 1024,
  });

  return cachedMd;
}

export const PdfReader = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "read") return;
      const filePath = output.args?.filePath || "";
      if (!filePath.toLowerCase().endsWith(".pdf")) return;

      try {
        const mdPath = extractPdf(filePath);
        output.args.filePath = mdPath;
      } catch (e) {
        if (e.code === "ENOENT") return; // let read tool handle missing files
        throw new Error(
          `PDF extraction failed: ${e.message}. ` +
          `Write a Python script to extract text and images:\n` +
          `\`\`\`python\nimport pymupdf4llm\nmd = pymupdf4llm.to_markdown("${filePath}", pages=list(range(0, 20)))\nprint(md)\n\`\`\``,
        );
      }
    },
  };
};
