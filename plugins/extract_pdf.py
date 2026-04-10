#!/usr/bin/env python3
"""Extract text and/or render pages from PDF. Writes markdown to output file.

For text-heavy PDFs: extracts markdown with pymupdf4llm.
For image-only PDFs: renders pages as JPEG and writes paths into the markdown
so the agent can `read` each page image directly (OpenCode vision).
"""
import sys
import os
import pymupdf

MAX_TEXT_CHARS = 200_000  # ~50K tokens
MAX_IMAGE_PAGES = 10     # render at most 10 pages as images
RENDER_DPI = 72          # 72 DPI = 1920x1080 for letter-size, ~300KB JPEG per page

if len(sys.argv) != 3:
    print("Usage: extract_pdf.py <pdf_path> <output_md_path>", file=sys.stderr)
    sys.exit(1)

pdf_path = sys.argv[1]
output_path = sys.argv[2]
cache_dir = os.path.dirname(output_path)
base_name = os.path.splitext(os.path.basename(output_path))[0]

doc = pymupdf.open(pdf_path)
total_pages = len(doc)

# Quick text check on first 20 pages to classify the PDF
sample_text = ""
sample_pages = min(total_pages, 20)
for i in range(sample_pages):
    sample_text += doc[i].get_text("text")
has_substantial_text = len(sample_text.strip()) > 500

# --- Text extraction ---
md = ""
pages_extracted = 0
truncated = False

if has_substantial_text:
    import pymupdf4llm

    if total_pages <= 20:
        md = pymupdf4llm.to_markdown(pdf_path)
        pages_extracted = total_pages
    else:
        char_count = 0
        est_pages = 0
        for page in doc:
            char_count += len(page.get_text())
            est_pages += 1
            if char_count > MAX_TEXT_CHARS:
                break

        md = pymupdf4llm.to_markdown(pdf_path, pages=list(range(est_pages)))
        pages_extracted = est_pages

        if len(md) > MAX_TEXT_CHARS:
            md = md[:MAX_TEXT_CHARS]
            idx = md.rfind("\n")
            if idx > 0:
                md = md[:idx]
            pages_extracted = max(1, pages_extracted - 1)

    truncated = pages_extracted < total_pages
else:
    # Use raw text even if minimal
    md = sample_text.strip()
    pages_extracted = sample_pages
    truncated = sample_pages < total_pages

# --- Page image rendering ---
# Image-only PDFs: render up to MAX_IMAGE_PAGES pages
# Text+image PDFs: render only pages that contain embedded images (up to MAX_IMAGE_PAGES)
image_paths = []
image_count = sum(len(doc[i].get_images()) for i in range(min(total_pages, sample_pages)))

if not has_substantial_text:
    # Image-only: render first N pages sequentially
    pages_to_render = list(range(min(total_pages, MAX_IMAGE_PAGES)))
elif image_count > 0:
    # Text+image: render only pages that have embedded images
    pages_to_render = [
        i for i in range(min(total_pages, sample_pages))
        if len(doc[i].get_images()) > 0
    ][:MAX_IMAGE_PAGES]
else:
    pages_to_render = []

for i in pages_to_render:
    page = doc[i]
    pix = page.get_pixmap(dpi=RENDER_DPI)
    if pix.colorspace and pix.colorspace.n > 3:
        pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
    jpeg_path = os.path.join(cache_dir, f"{base_name}_page{i + 1}.jpg")
    jpeg_bytes = pix.tobytes("jpeg")
    with open(jpeg_path, "wb") as f:
        f.write(jpeg_bytes)
    image_paths.append((i + 1, jpeg_path))
    pix = None  # free memory immediately

# --- Build output markdown ---
output = f"# PDF: {pdf_path}\n\n"
output += f"Pages: {total_pages}"
if image_count > 0:
    output += f" | Embedded images: {image_count}"
output += "\n\n"

# Table of contents
toc = doc.get_toc()
if toc:
    output += "## Table of Contents\n\n"
    for level, title, page in toc:
        indent = "  " * (level - 1)
        output += f"{indent}- {title} (page {page})\n"
    output += "\n"

output += "---\n\n"

if md:
    output += md + "\n"
else:
    output += "This is an image-only PDF (no extractable text).\n"

if truncated:
    output += f"\n---\n"
    output += f"⚠️ TRUNCATED: Only {pages_extracted} of {total_pages} pages shown.\n"
    output += "To read remaining pages:\n"
    output += f"```python\nimport pymupdf4llm\nmd = pymupdf4llm.to_markdown(\"{pdf_path}\", pages=list(range({pages_extracted}, {total_pages})))\nprint(md)\n```\n"

if image_paths:
    output += f"\n## Page Images ({len(image_paths)} of {total_pages} pages)\n\n"
    output += "Use the `read` tool on each path below to view the page:\n\n"
    for page_num, p in image_paths:
        output += f"- {p} (page {page_num})\n"
    if len(image_paths) < total_pages:
        output += f"\nTo render additional pages:\n"
        output += f"```python\nimport pymupdf\ndoc = pymupdf.open(\"{pdf_path}\")\n"
        output += f"for i in [PAGE_NUMBERS_HERE]:  # 0-indexed\n"
        output += f"    pix = doc[i].get_pixmap(dpi=72)\n"
        output += f"    pix.save(f\"/tmp/page{{i+1}}.jpg\")\n```\n"

with open(output_path, "w") as f:
    f.write(output)
