#!/usr/bin/env python3
"""Extract text and images from PDF using pymupdf4llm. Writes markdown to output file."""
import sys
import pymupdf
import pymupdf4llm

MAX_TEXT_CHARS = 200_000  # ~50K tokens

if len(sys.argv) != 3:
    print("Usage: extract_pdf.py <pdf_path> <output_md_path>", file=sys.stderr)
    sys.exit(1)

pdf_path = sys.argv[1]
output_path = sys.argv[2]

doc = pymupdf.open(pdf_path)
total_pages = len(doc)

# Extract text — for large PDFs, estimate pages needed then extract only those
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

    page_list = list(range(est_pages))
    md = pymupdf4llm.to_markdown(pdf_path, pages=page_list)
    pages_extracted = est_pages

    if len(md) > MAX_TEXT_CHARS:
        md = md[:MAX_TEXT_CHARS]
        md = md[:md.rfind("\n")]

truncated = pages_extracted < total_pages

# Count total images
total_images = sum(len(page.get_images()) for page in doc)

# Build table of contents
toc = doc.get_toc()
toc_str = ""
if toc:
    toc_lines = []
    for level, title, page in toc:
        indent = "  " * (level - 1)
        toc_lines.append(f"{indent}- {title} (page {page})")
    toc_str = "\n".join(toc_lines)

# Build output markdown
output = f"# PDF: {pdf_path}\n\n"
output += f"Pages: {total_pages} | Images: {total_images}\n\n"

if toc_str:
    output += f"## Table of Contents\n\n{toc_str}\n\n"

output += "---\n\n"
output += md

if truncated:
    output += f"\n\n---\n"
    output += f"⚠️ TRUNCATED: Only {pages_extracted} of {total_pages} pages shown.\n"
    output += f"To read remaining pages:\n"
    output += f"```python\nimport pymupdf4llm\nmd = pymupdf4llm.to_markdown(\"{pdf_path}\", pages=list(range({pages_extracted}, {total_pages})))\nprint(md)\n```\n"

if total_images > 0:
    output += f"\n📎 This PDF contains {total_images} embedded images (not shown).\n"
    output += f"To extract images:\n"
    output += f"```python\nimport pymupdf\ndoc = pymupdf.open(\"{pdf_path}\")\nfor i, page in enumerate(doc):\n    for j, img in enumerate(page.get_images()):\n        pix = pymupdf.Pixmap(doc, img[0])\n        if pix.colorspace and pix.colorspace.n > 3:\n            pix = pymupdf.Pixmap(pymupdf.csRGB, pix)\n        pix.save(f\"page{{i}}_img{{j}}.png\")\n```\n"

with open(output_path, "w") as f:
    f.write(output)
