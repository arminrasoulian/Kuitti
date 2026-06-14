#!/usr/bin/env python3
"""Rasterize the Kuitti icon/logo SVGs into PNG assets.

Pure-stdlib pipeline (no Pillow / cairosvg needed):
  1. `sips` rasterizes the SVG -> RGBA PNG at a chosen pixel size.
  2. A tiny stdlib zlib PNG re-encoder strips the alpha channel when an
     opaque RGB output is required (App Store marketing icons MUST NOT have
     an alpha channel; Xcode/altool reject RGBA 1024 icons).

Usage:
  render.py svg2png <in.svg> <out.png> <size> [--keep-alpha] [--matte RRGGBB]
"""
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path


def _sips_render(svg: Path, out_png: Path, size: int) -> None:
    """Render an SVG to a square PNG of `size`x`size` px using macOS sips."""
    # sips rasterizes the SVG at its intrinsic size, then -z resamples to target.
    subprocess.run(
        ["sips", "-s", "format", "png", "-z", str(size), str(size),
         str(svg), "--out", str(out_png)],
        check=True, capture_output=True,
    )


def _read_png(path: Path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, width, height, bitd, colt, idat = 8, None, None, None, None, b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            width, height, bitd, colt = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    assert bitd == 8, f"expected 8-bit, got {bitd}"
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colt]
    raw = zlib.decompress(idat)
    stride = width * ch
    out = bytearray()
    prev = bytearray(stride)

    def paeth(a, b, c):
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        return a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)

    p = 0
    for _ in range(height):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            x = line[i]
            if f == 1:   line[i] = (x + a) & 255
            elif f == 2: line[i] = (x + b) & 255
            elif f == 3: line[i] = (x + ((a + b) >> 1)) & 255
            elif f == 4: line[i] = (x + paeth(a, b, c)) & 255
        out += line
        prev = line
    return width, height, ch, bytes(out)


def _write_rgb_png(path: Path, width: int, height: int, rgb: bytes) -> None:
    """Encode a color-type-2 (RGB, no alpha) 8-bit PNG."""
    def chunk(typ, payload):
        return (struct.pack(">I", len(payload)) + typ + payload +
                struct.pack(">I", zlib.crc32(typ + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    stride = width * 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        raw += rgb[y * stride:(y + 1) * stride]
    idat = zlib.compress(bytes(raw), 9)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
                     chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def _flatten_to_rgb(src_png: Path, dst_png: Path, matte=(255, 255, 255)) -> None:
    w, h, ch, px = _read_png(src_png)
    rgb = bytearray(w * h * 3)
    mr, mg, mb = matte
    for i in range(w * h):
        o = i * ch
        if ch == 4:
            r, g, b, a = px[o], px[o + 1], px[o + 2], px[o + 3]
            if a == 255:
                rgb[i * 3:i * 3 + 3] = bytes((r, g, b))
            else:
                af = a / 255.0
                rgb[i * 3] = round(r * af + mr * (1 - af))
                rgb[i * 3 + 1] = round(g * af + mg * (1 - af))
                rgb[i * 3 + 2] = round(b * af + mb * (1 - af))
        elif ch == 3:
            rgb[i * 3:i * 3 + 3] = px[o:o + 3]
        elif ch == 2:  # gray + alpha
            rgb[i * 3:i * 3 + 3] = bytes((px[o], px[o], px[o]))
        else:           # gray
            rgb[i * 3:i * 3 + 3] = bytes((px[o], px[o], px[o]))
    _write_rgb_png(dst_png, w, h, bytes(rgb))


def svg2png(svg, out, size, keep_alpha=False, matte=(255, 255, 255)):
    svg, out = Path(svg), Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if keep_alpha:
        _sips_render(svg, out, size)
        return
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        tmp = Path(tf.name)
    try:
        _sips_render(svg, tmp, size)
        _flatten_to_rgb(tmp, out, matte)
    finally:
        tmp.unlink(missing_ok=True)


def _main(argv):
    if len(argv) < 4 or argv[0] != "svg2png":
        print(__doc__)
        return 1
    svg, out, size = argv[1], argv[2], int(argv[3])
    keep_alpha = "--keep-alpha" in argv
    matte = (255, 255, 255)
    if "--matte" in argv:
        hexv = argv[argv.index("--matte") + 1].lstrip("#")
        matte = tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4))
    svg2png(svg, out, size, keep_alpha, matte)
    print(f"wrote {out} ({size}x{size}, {'RGBA' if keep_alpha else 'RGB/no-alpha'})")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
