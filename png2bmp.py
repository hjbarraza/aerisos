#!/usr/bin/env python3
"""Convert an 8-bit RGB/RGBA non-interlaced PNG to a 24-bit BMP (for systemd-stub --splash).

Usage: python3 png2bmp.py in.png out.bmp
Stdlib only, so no ImageMagick/Pillow needed.
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("not a PNG")
    pos, idat = 8, b""
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            w, h, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"IDAT":
            idat += chunk
        pos += 12 + length
    if depth != 8 or color not in (2, 6) or interlace:
        sys.exit("need 8-bit RGB/RGBA non-interlaced PNG")
    bpp = 3 if color == 2 else 4
    raw, stride = zlib.decompress(idat), w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ftype, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 0xFF
            elif ftype == 2:
                line[x] = (line[x] + b) & 0xFF
            elif ftype == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 0xFF
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def write_bmp(path, w, h, bpp, rows):
    pad = (4 - (w * 3) % 4) % 4
    body = bytearray()
    for line in reversed(rows):  # BMP is bottom-up
        for x in range(w):
            r, g, b = line[x * bpp:x * bpp + 3]
            if bpp == 4:  # flatten alpha onto black
                al = line[x * bpp + 3]
                r, g, b = r * al // 255, g * al // 255, b * al // 255
            body += bytes((b, g, r))
        body += b"\0" * pad
    header = struct.pack("<2sIHHI", b"BM", 54 + len(body), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(body), 2835, 2835, 0, 0)
    open(path, "wb").write(header + info + body)


if __name__ == "__main__":
    write_bmp(sys.argv[2], *read_png(sys.argv[1]))
