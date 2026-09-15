#!/usr/bin/env python3
"""Generate a tiny valid, unencrypted synthetic PDF for isolated Apple UI tests."""
from pathlib import Path


def pdf(large=False):
    stream = b"0.2 0.5 0.3 rg\n30 220 260 180 re f\nBT /F1 20 Tf 30 170 Td 0 0 0 rg (Ninho PDF sintetico) Tj ET\n"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 320 480] /Resources << /Font << /F1 4 0 R >> >> /Contents " + (b"[5 0 R 6 0 R]" if large else b"5 0 R") + b" >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream",
    ]
    if large:
        # Comment padding enlarges the PDF without changing the rendered page.
        comments = b"% Ninho synthetic content stream padding for large PDF regression\n" * 50_000
        objects.append(b"<< /Length " + str(len(comments)).encode() + b" >>\nstream\n" + comments + b"endstream")
    data = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for index, content in enumerate(objects, 1):
        offsets.append(len(data)); data.extend(f"{index} 0 obj\n".encode() + content + b"\nendobj\n")
    xref = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for offset in offsets:
        data.extend(f"{offset:010d} 00000 n \n".encode())
    data.extend(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return bytes(data)


if __name__ == "__main__":
    for large in (False, True):
        target = Path(__file__).resolve().parents[1] / f"Ninho/Resources/test-material{'-large' if large else ''}.pdf"
        target.write_bytes(pdf(large))
        print(target)
