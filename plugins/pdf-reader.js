import { execFile } from "node:child_process";
import { stat as fsStat, access, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const CACHE_DIR = join(tmpdir(), "opencode-pdf-cache");

function cacheKey(filePath, st) {
  return createHash("sha256")
    .update(`${filePath}:${st.size}:${st.mtimeMs}`)
    .digest("hex");
}

async function extractPdf(filePath) {
  const st = await fsStat(filePath);
  const key = cacheKey(filePath, st);
  const cachedMd = join(CACHE_DIR, `${key}.md`);

  try {
    await access(cachedMd);
    return cachedMd;
  } catch {
    // cache miss — extract below
  }

  await mkdir(CACHE_DIR, { recursive: true });

  const script = join(__dirname, "extract_pdf.py");
  await execFileAsync("python3", [script, filePath, cachedMd], {
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
        const mdPath = await extractPdf(filePath);
        output.args.filePath = mdPath;
      } catch (e) {
        if (e.code === "ENOENT" && e.syscall === "stat") return; // PDF file missing — let read tool handle it
        throw new Error(
          `PDF extraction failed: ${e.message}. ` +
          `Write a Python script to extract text and images:\n` +
          `\`\`\`python\nimport pymupdf4llm\nmd = pymupdf4llm.to_markdown("${filePath}", pages=list(range(0, 20)))\nprint(md)\n\`\`\``,
        );
      }
    },
  };
};
