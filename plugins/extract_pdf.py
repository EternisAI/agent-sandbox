#!/usr/bin/env python3
"""Extract text from PDF using pymupdf4llm. Outputs Markdown to stdout."""
import sys
import pymupdf4llm

if len(sys.argv) != 2:
    print("Usage: extract_pdf.py <path>", file=sys.stderr)
    sys.exit(1)

md = pymupdf4llm.to_markdown(sys.argv[1])
sys.stdout.write(md)
