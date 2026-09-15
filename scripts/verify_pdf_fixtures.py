#!/usr/bin/env python3
"""Optional fixture QA with pypdf/PyMuPDF. This does not exercise PDFKit/iOS."""
import json
from pathlib import Path
import pymupdf
from pypdf import PdfReader

root = Path(__file__).resolve().parents[1]
output = root / "TestResults/pdf-fixtures"
output.mkdir(parents=True, exist_ok=True)
results = []
for name in ("test-material.pdf", "test-material-large.pdf"):
    path = root / "Ninho/Resources" / name
    reader = PdfReader(path, strict=True)
    assert len(reader.pages) == 1
    assert "Ninho PDF sintetico" in reader.pages[0].extract_text()
    with pymupdf.open(path) as document:
        image = document[0].get_pixmap(colorspace=pymupdf.csRGB, alpha=False)
        samples = image.samples
        green = sum(1 for index in range(0, len(samples), 3)
                    if samples[index + 1] > 70 and samples[index + 1] > samples[index] + 20
                    and samples[index + 1] > samples[index + 2] + 20)
        fraction = green / (image.width * image.height)
        assert fraction > 0.04
        image.save(output / f"{path.stem}.png")
    results.append({"file": name, "bytes": path.stat().st_size, "pages": 1, "greenPixelFraction": fraction})
assert results[1]["bytes"] > 3 * 1024 * 1024
(output / "result.json").write_text(json.dumps({"engine": "pypdf + PyMuPDF, not Apple PDFKit", "results": results}, indent=2), encoding="utf-8")
print(json.dumps(results, indent=2))
