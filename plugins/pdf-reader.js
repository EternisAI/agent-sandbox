import { execFile } from "node:child_process";
import { writeFileSync, statSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const CACHE_DIR = join(tmpdir(), "opencode-pdf-cache");
const MAX_IMAGES = 10;

function cacheKey(filePath, stat) {
  return createHash("sha256")
    .update(`${filePath}:${stat.size}:${stat.mtimeMs}`)
    .digest("hex");
}

function extractPdf(filePath) {
  const stat = statSync(filePath);
  const key = cacheKey(filePath, stat);
  const cachedJson = join(CACHE_DIR, `${key}.json`);

  if (existsSync(cachedJson)) {
    return Promise.resolve(JSON.parse(readFileSync(cachedJson, "utf-8")));
  }

  mkdirSync(CACHE_DIR, { recursive: true });

  const sizeMB = stat.size / (1024 * 1024);
  const timeout = Math.min(60000, Math.ceil(30000 + sizeMB * 500));

  const script = join(__dirname, "extract_pdf.py");
  return new Promise((resolve, reject) => {
    execFile("python3", [script, filePath], {
      encoding: "utf-8",
      timeout,
      killSignal: "SIGKILL",
      maxBuffer: 50 * 1024 * 1024,
    }, (err, stdout, stderr) => {
      if (stderr) console.error(`[pdf-reader] ${stderr.trim()}`);
      if (err) return reject(err);
      try {
        const result = JSON.parse(stdout);
        writeFileSync(cachedJson, stdout);
        resolve(result);
      } catch (e) {
        reject(e);
      }
    });
  });
}

export const PdfReader = async () => {
  let pendingImages = null;

  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "read") return;
      const filePath = output.args?.filePath || "";
      if (!filePath.toLowerCase().endsWith(".pdf")) return;

      mkdirSync(CACHE_DIR, { recursive: true });
      try {
        const result = await extractPdf(filePath);
        const stat = statSync(filePath);
        const key = cacheKey(filePath, stat);
        const mdPath = join(CACHE_DIR, `${key}.md`);
        if (!existsSync(mdPath)) {
          const md = result.markdown || "";
          let content = md.trim().length > 0 ? md : "No extractable text found. See attached page images.";
          if (result.truncated) {
            content += `\n\n---\n⚠️ DOCUMENT TRUNCATED: Only ${result.pages_extracted} of ${result.total_pages} pages shown. The PDF is at: ${filePath}`;
            if (result.toc) content += `\nTable of Contents:\n${result.toc}\n`;
          }
          writeFileSync(mdPath, content);
        }
        pendingImages = (result.images || []).slice(0, MAX_IMAGES);
        output.args.filePath = mdPath;
      } catch (e) {
        pendingImages = null;
        const fallbackPath = join(CACHE_DIR, `fallback-${Date.now()}.md`);
        writeFileSync(fallbackPath,
          `PDF extraction failed for ${filePath}: ${e.message}\n` +
          `The file is at: ${filePath}\n` +
          `Write a Python script using pymupdf to extract text.`);
        output.args.filePath = fallbackPath;
      }
    },

    "tool.execute.after": async (input, output) => {
      if (input.tool !== "read" || !pendingImages) return;
      const images = pendingImages;
      pendingImages = null;
      if (images.length > 0) {
        output.attachments = images.map((b64) => ({
          id: `prt_${randomUUID().replace(/-/g, "")}`,
          mime: "image/jpeg",
          url: `data:image/jpeg;base64,${b64}`,
        }));
      }
    },
  };
};
