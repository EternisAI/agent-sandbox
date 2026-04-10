#!/usr/bin/env python3
"""Extract text and page images from PDF. Outputs JSON to stdout.

Each page is rendered as a JPEG image (like Claude API and OpenAI do internally).
Text is also extracted where available. Both are passed to the LLM — the vision
model reads the page images directly, no OCR needed.
"""
import os
import sys
import json
import base64
import time
import pymupdf

MAX_TEXT_CHARS = 200_000
MAX_IMAGE_PAGES = 10
MAX_PAGE_LONG_EDGE = 1568
MAX_TOTAL_IMAGE_BYTES = 15_000_000
# 72 DPI produces ~612x792 for letter-size pages — enough for LLM vision.
# Higher DPI (150) causes rendering to take 50+ seconds for 18 pages.
RENDER_DPI = 72

if len(sys.argv) != 2:
    print("Usage: extract_pdf.py <path>", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]
file_size = os.path.getsize(path)
t0 = time.time()

print(f"[extract_pdf] opening {path} ({file_size / 1024 / 1024:.1f}MB)", file=sys.stderr)

# Copy to local /tmp if the file is on a network/fuse mount (e.g. GCS Fuse at /data).
# Reading large files through Fuse is extremely slow — pymupdf needs random access
# and Fuse may re-fetch blocks on each seek.
import shutil
import tempfile

local_path = path
_tmp_copy = None
if path.startswith("/data") and file_size > 5_000_000:
    _tmp_copy = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
    print(f"[extract_pdf] copying to local {_tmp_copy.name}...", file=sys.stderr)
    shutil.copy2(path, _tmp_copy.name)
    local_path = _tmp_copy.name
    print(f"[extract_pdf] copy done, elapsed={time.time()-t0:.1f}s", file=sys.stderr)

doc = pymupdf.open(local_path)
total_pages = len(doc)
toc = doc.get_toc()

print(f"[extract_pdf] {total_pages} pages, render_dpi={RENDER_DPI}, elapsed={time.time()-t0:.1f}s", file=sys.stderr)

# --- Fast text extraction using pymupdf directly ---
pages_to_extract = min(total_pages, 20)
raw_text = ""
for i in range(pages_to_extract):
    raw_text += doc[i].get_text("text")

has_substantial_text = len(raw_text.strip()) > 500
print(f"[extract_pdf] text={len(raw_text)} chars, substantial={has_substantial_text}, elapsed={time.time()-t0:.1f}s", file=sys.stderr)

if has_substantial_text:
    import pymupdf4llm

    if total_pages <= 20:
        md = pymupdf4llm.to_markdown(local_path)
        pages_extracted = total_pages
    else:
        char_count = 0
        est_pages = 0
        for page in doc:
            char_count += len(page.get_text())
            est_pages += 1
            if char_count > MAX_TEXT_CHARS:
                break

        est_pages = max(1, est_pages)
        md = pymupdf4llm.to_markdown(local_path, pages=list(range(est_pages)))
        pages_extracted = est_pages

        if len(md) > MAX_TEXT_CHARS:
            md = md[:MAX_TEXT_CHARS]
            idx = md.rfind("\n")
            if idx > 0:
                md = md[:idx]
    truncated = pages_extracted < total_pages
else:
    md = raw_text.strip()
    pages_extracted = pages_to_extract
    truncated = pages_extracted < total_pages

print(f"[extract_pdf] text extraction done, elapsed={time.time()-t0:.1f}s", file=sys.stderr)

# --- Page image rendering ---
images = []
total_image_bytes = 0
image_pages = min(total_pages, MAX_IMAGE_PAGES)

for i in range(image_pages):
    page = doc[i]
    pix = page.get_pixmap(dpi=RENDER_DPI)

    if pix.colorspace and pix.colorspace.n > 3:
        pix = pymupdf.Pixmap(pymupdf.csRGB, pix)

    long_edge = max(pix.width, pix.height)
    if long_edge > MAX_PAGE_LONG_EDGE:
        factor = max(2, long_edge // MAX_PAGE_LONG_EDGE)
        pix.shrink(factor)

    jpeg_bytes = pix.tobytes("jpeg")
    b64 = base64.b64encode(jpeg_bytes).decode()
    total_image_bytes += len(b64)
    if total_image_bytes > MAX_TOTAL_IMAGE_BYTES:
        break
    images.append(b64)
    if (i + 1) % 5 == 0:
        print(f"[extract_pdf] rendered {i+1}/{image_pages} pages, {total_image_bytes/1024:.0f}KB, elapsed={time.time()-t0:.1f}s", file=sys.stderr)

print(f"[extract_pdf] done: {len(images)} images, {total_image_bytes/1024:.0f}KB total, elapsed={time.time()-t0:.1f}s", file=sys.stderr)

toc_str = ""
if toc:
    toc_lines = []
    for level, title, pg in toc:
        indent = "  " * (level - 1)
        toc_lines.append(f"{indent}- {title} (page {pg})")
    toc_str = "\n".join(toc_lines)

result = {
    "markdown": md,
    "images": images,
    "image_format": "jpeg",
    "truncated": truncated,
    "pages_extracted": pages_extracted,
    "pages_rendered": len(images),
    "total_pages": total_pages,
    "toc": toc_str,
}

json.dump(result, sys.stdout)

if _tmp_copy is not None:
    os.unlink(_tmp_copy.name)
