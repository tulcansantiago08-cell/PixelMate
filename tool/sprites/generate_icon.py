#!/usr/bin/env python3
"""Genera el ícono de la app (el gato pixel art sobre un fondo morado).

Uso:  python3 tool/sprites/generate_icon.py

Dibuja el gato con las mismas piezas que generate_cat.py, lo amplía sin
suavizar (píxeles nítidos) sobre un cuadrado redondeado con degradado, y
escribe los tamaños que pide macOS con `sips`.
"""

import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import generate_cat as g  # noqa: E402

SIZE = 1024
MARGIN = 100           # margen de la cuadrícula de íconos de macOS
RADIUS = 186
TOP = (139, 92, 246)   # #8B5CF6
BOTTOM = (76, 29, 149)  # #4C1D95
SHADOW = (40, 14, 82)
SCALE = 22             # 32 px del gato -> 704 px


def rounded_coverage(x, y):
    """Qué fracción del píxel cae dentro del cuadrado redondeado (4x4)."""
    lo, hi = MARGIN, SIZE - MARGIN
    inside = 0
    for sy in range(4):
        for sx in range(4):
            px, py = x + (sx + 0.5) / 4, y + (sy + 0.5) / 4
            cx = min(max(px, lo + RADIUS), hi - RADIUS)
            cy = min(max(py, lo + RADIUS), hi - RADIUS)
            if lo <= px <= hi and lo <= py <= hi and \
                    (px - cx) ** 2 + (py - cy) ** 2 <= RADIUS ** 2:
                inside += 1
    return inside / 16


def main():
    cv = g.Canvas()
    g.cat(cv, eyes="happy", mouth="smile", tail=1)

    # Caja del gato para centrarlo.
    xs = [x for y in range(32) for x in range(32) if cv.px[y][x]]
    ys = [y for y in range(32) for x in range(32) if cv.px[y][x]]
    w = (max(xs) - min(xs) + 1) * SCALE
    h = (max(ys) - min(ys) + 1) * SCALE
    ox = (SIZE - w) // 2 - min(xs) * SCALE
    oy = (SIZE - h) // 2 - min(ys) * SCALE + 18
    floor_y = oy + (max(ys) + 1) * SCALE

    rows = []
    lo, hi = MARGIN, SIZE - MARGIN
    for y in range(SIZE):
        t = min(max((y - lo) / (hi - lo), 0), 1)
        bg = [round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)]
        row = []
        near_edge_y = y < lo + RADIUS + 2 or y > hi - RADIUS - 2
        for x in range(SIZE):
            if x < lo - 1 or x > hi + 1 or y < lo - 1 or y > hi + 1:
                row += [0, 0, 0, 0]
                continue
            near_edge = near_edge_y and (x < lo + RADIUS + 2 or x > hi - RADIUS - 2)
            a = rounded_coverage(x, y) if (near_edge or x <= lo or x >= hi or y <= lo or y >= hi) else 1.0
            if a == 0:
                row += [0, 0, 0, 0]
                continue
            c = bg
            # Sombra suave bajo el gato.
            dx, dy = (x - SIZE / 2) / 300, (y - floor_y + 6) / 38
            if dx * dx + dy * dy <= 1:
                c = [round(c[i] * 0.55 + SHADOW[i] * 0.45) for i in range(3)]
            gx, gy = (x - ox) // SCALE, (y - oy) // SCALE
            if 0 <= gx < 32 and 0 <= gy < 32 and cv.px[gy][gx]:
                c = list(cv.px[gy][gx])
            row += [c[0], c[1], c[2], round(255 * a)]
        rows.append(row)

    out_dir = os.path.join(g.ROOT, "macos", "Runner", "Assets.xcassets",
                           "AppIcon.appiconset")
    big = os.path.join(out_dir, "app_icon_1024.png")
    g.write_png(big, SIZE, SIZE, rows)
    for s in (512, 256, 128, 64, 32, 16):
        subprocess.run(["sips", "-z", str(s), str(s), big, "--out",
                        os.path.join(out_dir, f"app_icon_{s}.png")],
                       check=True, capture_output=True)
    print("Ícono generado en", out_dir)


if __name__ == "__main__":
    main()
