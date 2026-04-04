#!/usr/bin/env python3
"""Extract text and images from PDF using pymupdf4llm. Outputs JSON to stdout."""
import sys
import json
import base64
import pymupdf
import pymupdf4llm

if len(sys.argv) != 2:
    print("Usage: extract_pdf.py <path>", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]

md = pymupdf4llm.to_markdown(path)

images = []
doc = pymupdf.open(path)
for page in doc:
    for img in page.get_images():
        xref = img[0]
        pix = pymupdf.Pixmap(doc, xref)
        if pix.colorspace and pix.colorspace.n > 3:
            pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
        png = pix.tobytes("png")
        images.append(base64.b64encode(png).decode())

json.dump({"markdown": md, "images": images}, sys.stdout)
