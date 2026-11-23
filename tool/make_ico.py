#!/usr/bin/env python3
"""Arma un .ico con PNG por dentro (Windows Vista en adelante), a partir de los
íconos de la app de Mac. Uso: python3 tool/make_ico.py salida.ico 16 32 64 256"""
import struct, sys
from pathlib import Path

src = Path(__file__).resolve().parent.parent / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
out, sizes = sys.argv[1], [int(s) for s in sys.argv[2:]]
images = [(s, (src / f'app_icon_{s}.png').read_bytes()) for s in sizes]
header = struct.pack('<HHH', 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, data = b'', b''
for size, png in images:
    dim = 0 if size >= 256 else size  # 0 significa 256
    entries += struct.pack('<BBBBHHII', dim, dim, 0, 0, 1, 32, len(png), offset + len(data))
    data += png
Path(out).write_bytes(header + entries + data)
print(out, len(images), 'tamaños')
