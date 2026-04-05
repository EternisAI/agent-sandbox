#!/usr/bin/env python3
"""Extract text and images from PDF using pymupdf4llm. Outputs JSON to stdout."""
import sys
import json
import base64
import pymupdf
import pymupdf4llm

MAX_TEXT_CHARS = 200_000  # ~50K tokens

if len(sys.argv) != 2:
    print("Usage: extract_pdf.py <path>", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]
doc = pymupdf.open(path)
total_pages = len(doc)

# Get table of contents
toc = doc.get_toc()

# Extract text — for large PDFs, estimate pages needed then extract only those
if total_pages <= 20:
    md = pymupdf4llm.to_markdown(path)
    pages_extracted = total_pages
else:
    # Fast pass: estimate how many pages fit in the text budget using raw text
    char_count = 0
    est_pages = 0
    for page in doc:
        char_count += len(page.get_text())
        est_pages += 1
        if char_count > MAX_TEXT_CHARS:
            break

    # Extract only the estimated pages with pymupdf4llm for quality markdown
    page_list = list(range(est_pages))
    md = pymupdf4llm.to_markdown(path, pages=page_list)
    pages_extracted = est_pages

    # Trim if markdown is longer than raw text estimate
    if len(md) > MAX_TEXT_CHARS:
        md = md[:MAX_TEXT_CHARS]
        md = md[:md.rfind("\n")]  # trim to last complete line
truncated = pages_extracted < total_pages

# Count total images in the PDF
total_images = sum(len(page.get_images()) for page in doc)

# Extract images only for small PDFs (≤20 pages)
images = []
if total_pages <= 20:
    for page in doc:
        for img in page.get_images():
            xref = img[0]
            pix = pymupdf.Pixmap(doc, xref)
            if pix.colorspace and pix.colorspace.n > 3:
                pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
            png = pix.tobytes("png")
            images.append(base64.b64encode(png).decode())

# Build TOC string for large docs
toc_str = ""
if toc:
    toc_lines = []
    for level, title, page in toc:
        indent = "  " * (level - 1)
        toc_lines.append(f"{indent}- {title} (page {page})")
    toc_str = "\n".join(toc_lines)

result = {
    "markdown": md,
    "images": images,
    "truncated": truncated,
    "pages_extracted": pages_extracted,
    "total_pages": total_pages,
    "total_images": total_images,
    "toc": toc_str,
}

json.dump(result, sys.stdout)
