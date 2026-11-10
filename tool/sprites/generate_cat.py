#!/usr/bin/env python3
"""Genera los spritesheets pixel art de las mascotas de PixelMate (gato,
perro y zorro).

Uso:  python3 tool/sprites/generate_cat.py [--sin-vistas]

Salida, por especie (<id> = cat | dog | fox):
  assets/pets/<id>/sheet.png      spritesheet (una fila por animación)
  assets/pets/<id>/pet.json       metadatos que lee la app
  assets/pets/<id>/accessories/   capas de accesorios
  build/sprites/<id>_preview.png  vista previa ampliada (no va en la app)

El gato se compone por piezas (cabeza, cuerpo, ojos, patas, accesorios) en
una cuadrícula de 32x32. Para cambiar el arte basta con editar este archivo y
volver a ejecutarlo, o reemplazar sheet.png por uno dibujado a mano con el
mismo formato. Sin dependencias: escribe PNG con zlib.
"""

import json
import math
import os
import struct
import sys
import zlib

SIZE = 32
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# --- Paleta ------------------------------------------------------------------
OUTLINE = (43, 29, 20)
BODY = (240, 208, 144)
SHADE = (200, 160, 96)
BELLY = (250, 230, 190)
EAR_IN = (232, 150, 150)
PINK = (255, 154, 176)
EYE = (42, 26, 16)
WHITE = (255, 255, 255)
GRAY = (92, 98, 112)
GRAY_DARK = (58, 62, 74)
SCREEN = (143, 211, 255)
BOOK = (192, 80, 77)
PAGE = (244, 236, 216)
PAD = (47, 47, 58)
BTN_A = (255, 90, 90)
BTN_B = (90, 200, 120)
PHONES = (58, 53, 80)
ACCENT = (124, 58, 237)
CUP = (250, 250, 250)
COFFEE = (120, 72, 40)
STEAM = (210, 214, 224)
ZZZ = (159, 180, 255)
GOLD = (255, 216, 74)
CONFETTI = [(255, 90, 90), (90, 200, 120), (90, 160, 255), (255, 216, 74), (200, 120, 255)]
DROP = (106, 183, 255)
ALERT = (255, 90, 90)


# --- Especies ------------------------------------------------------------------
# Todas comparten pose, cara y animaciones; cambian colores, orejas, cola y
# hocico. El gato es la especie por defecto (y su hoja no cambia).

SPECIES = {
    "cat": {
        "name": "Gato", "body": BODY, "shade": SHADE, "belly": BELLY,
        "ear_in": EAR_IN, "nose": PINK, "ears": "cat", "tail": "cat",
    },
    "dog": {
        "name": "Perro", "body": (204, 150, 98), "shade": (158, 106, 64),
        "belly": (246, 230, 206), "ear_in": (122, 80, 50),
        "nose": (52, 34, 26), "ears": "dog", "tail": "dog", "snout": True,
    },
    "fox": {
        "name": "Zorro", "body": (236, 132, 60), "shade": (192, 94, 40),
        "belly": (252, 244, 232), "ear_in": (250, 226, 200),
        "nose": (52, 34, 26), "ears": "fox", "tail": "fox", "cheeks": True,
        "tip": (252, 244, 232), "dark": (72, 44, 34),
    },
}
KIND = SPECIES["cat"]


def use_species(sid):
    """Cambia la paleta y las piezas que usan cat() y face()."""
    global KIND, BODY, SHADE, BELLY, EAR_IN
    KIND = SPECIES[sid]
    BODY, SHADE, BELLY, EAR_IN = (KIND["body"], KIND["shade"], KIND["belly"],
                                  KIND["ear_in"])


class Canvas:
    """Cuadrícula de colores; `None` es transparente."""

    def __init__(self):
        self.px = [[None] * SIZE for _ in range(SIZE)]
        self.body = [[False] * SIZE for _ in range(SIZE)]

    def set(self, x, y, c, body=False):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.px[y][x] = c
            if body:
                self.body[y][x] = True

    def get(self, x, y):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            return self.px[y][x]
        return None

    def ellipse(self, cx, cy, rx, ry, c, body=True):
        for y in range(SIZE):
            for x in range(SIZE):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1:
                    self.set(x, y, c, body)

    def rect(self, x0, y0, x1, y1, c, body=False):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, c, body)

    def triangle(self, a, b, c_, col, body=True):
        def sign(p, q, r):
            return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])

        for y in range(SIZE):
            for x in range(SIZE):
                p = (x + 0.5, y + 0.5)
                d1, d2, d3 = sign(p, a, b), sign(p, b, c_), sign(p, c_, a)
                neg = d1 < 0 or d2 < 0 or d3 < 0
                pos = d1 > 0 or d2 > 0 or d3 > 0
                if not (neg and pos):
                    self.set(x, y, col, body)

    def line(self, pts, c, body=False):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
            for i in range(n + 1):
                t = i / max(n, 1)
                self.set(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c, body)

    def outline_body(self):
        """Contorno de 1 px alrededor de todo lo marcado como cuerpo."""
        add = []
        for y in range(SIZE):
            for x in range(SIZE):
                if self.body[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < SIZE and 0 <= ny < SIZE and self.body[ny][nx]:
                        add.append((x, y))
                        break
        for x, y in add:
            self.px[y][x] = OUTLINE

    def outline_color(self, color, outline=OUTLINE):
        """Contorno alrededor de los píxeles de un color (accesorios)."""
        add = []
        for y in range(SIZE):
            for x in range(SIZE):
                if self.px[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if self.get(x + dx, y + dy) == color:
                        add.append((x, y))
                        break
        for x, y in add:
            self.px[y][x] = outline


# --- Piezas del gato ------------------------------------------------------------

def cat(cv, dy=0, squash=0, eyes="open", mouth="smile", arms="down",
        tail=0, ears=0, look=0):
    """Dibuja el gato sentado.

    dy: desplazamiento vertical (respiración, saltos)
    squash: aplasta el cuerpo (dormir)
    eyes: open | closed | happy | half | wide | star | down
    mouth: smile | open | flat | yawn | sad
    arms: down | up | wave1 | wave2 | type1 | type2 | hold | none
    tail: fase del movimiento de la cola
    ears: 0 normal, 1 caídas
    look: -1/0/1 dirección de la mirada
    """
    hy = 12 + dy + squash
    # Cola (detrás del cuerpo)
    sway = [0, 1, 2, 1][tail % 4]
    if KIND["tail"] == "dog":  # corta y contenta, se menea
        wag = [0, 2, 3, 2][tail % 4]
        cv.line([(22, 27), (25, 25), (26 + wag // 2, 22 - wag // 2)], BODY, body=True)
        cv.line([(22, 28), (25, 26), (27 + wag // 2, 23 - wag // 2)], BODY, body=True)
    elif KIND["tail"] == "fox":  # grande y esponjosa, con la punta blanca
        cv.ellipse(25.5 + sway * 0.4, 23 - sway * 0.3, 3.4, 5.6, BODY)
        cv.ellipse(26 + sway * 0.5, 18.6 - sway * 0.4, 2.2, 2.2, KIND["tip"])
    else:
        cv.line([(22, 27), (25, 26), (27, 24 - sway // 2), (27, 21 - sway),
                 (26 + sway // 2, 19 - sway)], BODY, body=True)
        cv.line([(22, 28), (25, 27), (28, 24 - sway // 2)], BODY, body=True)
    # Cuerpo
    cv.ellipse(16, 23 + dy * 0.5 + squash * 0.6, 7.5, 6.5 - squash * 0.5, BODY)
    cv.ellipse(16, 24.5 + dy * 0.5 + squash * 0.6, 4.2, 3.6 - squash * 0.3, BELLY)
    # Pies
    cv.ellipse(11.5, 29.3, 2.4, 1.4, BODY)
    cv.ellipse(20.5, 29.3, 2.4, 1.4, BODY)
    # Orejas
    kind_ears = KIND["ears"]
    if kind_ears == "fox" and ears == 0:  # grandes, con las puntas oscuras
        cv.triangle((7, hy - 2.5), (8.5, hy - 12), (14, hy - 5.5), BODY)
        cv.triangle((25, hy - 2.5), (23.5, hy - 12), (18, hy - 5.5), BODY)
        cv.triangle((9, hy - 4.5), (9.6, hy - 9.5), (12.6, hy - 5.6), EAR_IN)
        cv.triangle((23, hy - 4.5), (22.4, hy - 9.5), (19.4, hy - 5.6), EAR_IN)
        cv.triangle((7.8, hy - 9), (8.5, hy - 12), (10.6, hy - 9.6), KIND["dark"])
        cv.triangle((24.2, hy - 9), (23.5, hy - 12), (21.4, hy - 9.6), KIND["dark"])
    elif kind_ears == "dog":
        pass  # caídas: se dibujan después de la cabeza
    elif ears == 0:
        cv.triangle((7.5, hy - 3), (9.5, hy - 10.5), (13.5, hy - 5.5), BODY)
        cv.triangle((24.5, hy - 3), (22.5, hy - 10.5), (18.5, hy - 5.5), BODY)
        cv.triangle((9, hy - 4.5), (10, hy - 8.5), (12.3, hy - 5.6), EAR_IN)
        cv.triangle((23, hy - 4.5), (22, hy - 8.5), (19.7, hy - 5.6), EAR_IN)
    else:  # caídas (cansada, triste)
        cv.triangle((7, hy - 2), (5.5, hy - 7), (12, hy - 5), BODY)
        cv.triangle((25, hy - 2), (26.5, hy - 7), (20, hy - 5), BODY)
    # Cabeza
    cv.ellipse(16, hy, 8.6, 6.8, BODY)
    if kind_ears == "dog":  # orejas que cuelgan a los lados
        low = 1.5 if ears else 0
        cv.ellipse(7.6, hy + low, 2.4, 4.6, EAR_IN)
        cv.ellipse(24.4, hy + low, 2.4, 4.6, EAR_IN)
    if KIND.get("cheeks"):  # mejillas blancas del zorro
        cv.ellipse(11.5, hy + 2.6, 3.4, 2.4, BELLY)
        cv.ellipse(20.5, hy + 2.6, 3.4, 2.4, BELLY)
    if KIND.get("snout"):  # hocico del perro
        cv.ellipse(16, hy + 2.4, 3.6, 2.4, BELLY)
    # Sombra bajo la cabeza
    for x in range(10, 23):
        if cv.body[min(SIZE - 1, int(hy + 7))][x]:
            cv.set(x, hy + 7, SHADE, body=True)
    # Brazos
    arm_pos = {
        "down": [(11.5, 24.5), (20.5, 24.5)],
        # Patas levantadas fuera de la silueta de la cabeza para que se lean.
        "up": [(4.5, hy - 4), (27.5, hy - 4)],
        "wave1": [(11.5, 24.5), (28, hy - 5)],
        "wave2": [(11.5, 24.5), (29, hy - 1)],
        "type1": [(12, 25), (20, 26)],
        "type2": [(12, 26), (20, 25)],
        "hold": [(12.5, 24), (19.5, 24)],
        "none": [],
    }[arms]
    for i, (ax, ay) in enumerate(arm_pos):
        if arms in ("up",) or (arms.startswith("wave") and i == 1):
            sx = 10 if i == 0 else 22
            sy = 20 + dy * 0.5
            cv.line([(sx, sy), (ax, ay)], BODY, body=True)
            cv.line([(sx + (1 if i == 0 else -1), sy + 1), (ax + (1 if i == 0 else -1), ay + 1)],
                    BODY, body=True)
        cv.ellipse(ax, ay, 1.9, 1.5, BODY)
    cv.outline_body()
    # Rasgos (encima del contorno)
    face(cv, hy, eyes, mouth, look)


def face(cv, hy, eyes, mouth, look):
    ey = int(hy) - 1
    lx, rx = 11 + look, 19 + look
    if eyes == "open":
        for x0 in (lx, rx):
            cv.rect(x0, ey, x0 + 1, ey + 1, EYE)
            cv.set(x0, ey, WHITE)
    elif eyes == "wide":
        for x0 in (lx, rx):
            cv.rect(x0, ey - 1, x0 + 1, ey + 1, EYE)
            cv.set(x0, ey - 1, WHITE)
    elif eyes == "closed":
        for x0 in (lx, rx):
            cv.rect(x0 - 1, ey + 1, x0 + 2, ey + 1, EYE)
    elif eyes == "half":
        for x0 in (lx, rx):
            cv.rect(x0 - 1, ey, x0 + 2, ey, EYE)
            cv.rect(x0, ey + 1, x0 + 1, ey + 1, EYE)
    elif eyes == "happy":
        for x0 in (lx, rx):
            cv.set(x0 - 1, ey + 1, EYE)
            cv.set(x0, ey, EYE)
            cv.set(x0 + 1, ey, EYE)
            cv.set(x0 + 2, ey + 1, EYE)
    elif eyes == "star":
        for x0 in (lx, rx):
            cv.set(x0, ey - 1, GOLD)
            cv.rect(x0 - 1, ey, x0 + 2, ey, GOLD)
            cv.set(x0, ey + 1, GOLD)
            cv.set(x0 + 1, ey + 1, GOLD)
    elif eyes == "down":  # mirando hacia abajo (laptop, libro)
        for x0 in (lx, rx):
            cv.rect(x0, ey + 1, x0 + 1, ey + 1, EYE)
            cv.rect(x0 - 1, ey, x0 + 2, ey, SHADE)
    # Mejillas y nariz
    cv.set(9 + look, ey + 3, PINK)
    cv.set(23 + look, ey + 3, PINK)
    cv.set(16 + look, ey + 2, KIND["nose"])
    my = ey + 3
    mx = 16 + look
    if mouth == "smile":
        cv.set(mx - 1, my, EYE)
        cv.set(mx + 1, my, EYE)
    elif mouth == "open":
        cv.rect(mx - 1, my, mx + 1, my + 1, EYE)
        cv.set(mx, my + 1, PINK)
    elif mouth == "flat":
        cv.rect(mx - 1, my, mx + 1, my, EYE)
    elif mouth == "yawn":
        cv.rect(mx - 1, my, mx + 1, my + 2, EYE)
        cv.set(mx, my + 1, PINK)
        cv.set(mx, my + 2, PINK)
    elif mouth == "sad":
        cv.set(mx - 1, my + 1, EYE)
        cv.set(mx, my, EYE)
        cv.set(mx + 1, my + 1, EYE)


# --- Accesorios -------------------------------------------------------------

def laptop(cv, frame):
    cv.rect(9, 20, 23, 27, GRAY)
    cv.rect(10, 21, 22, 26, GRAY_DARK)
    glow = [SCREEN, (200, 235, 255), SCREEN, (120, 190, 240)][frame % 4]
    cv.rect(15, 22, 17, 24, glow)
    cv.rect(7, 28, 25, 28, GRAY)
    cv.outline_color(GRAY)


def book(cv, frame):
    cv.rect(8, 20, 24, 27, BOOK)
    cv.rect(9, 20, 15, 26, PAGE)
    cv.rect(17, 20, 23, 26, PAGE)
    cv.line([(16, 20), (16, 27)], OUTLINE)
    for y in (22, 24):
        cv.line([(10, y), (14, y)], (190, 180, 160))
        cv.line([(18, y), (22, y)], (190, 180, 160))
    if frame == 2:  # pasando la página
        cv.triangle((17, 20), (23, 20), (20, 17), PAGE, body=False)
    cv.outline_color(BOOK)


def headphones(cv, dy):
    hy = 12 + dy
    pts = [(8, hy - 1), (9, hy - 6), (12, hy - 9), (16, hy - 10), (20, hy - 9),
           (23, hy - 6), (24, hy - 1)]
    cv.line(pts, PHONES)
    cv.rect(6, hy - 2, 8, hy + 2, PHONES)
    cv.rect(24, hy - 2, 26, hy + 2, PHONES)
    cv.set(7, hy, ACCENT)
    cv.set(25, hy, ACCENT)


def gamepad(cv, frame):
    cv.rect(10, 23, 22, 26, PAD)
    cv.rect(9, 24, 23, 26, PAD)
    cv.set(12, 24, (200, 200, 210))
    cv.set(11, 25, (200, 200, 210))
    cv.set(13, 25, (200, 200, 210))
    a, b = (BTN_A, BTN_B) if frame % 2 == 0 else (BTN_B, BTN_A)
    cv.set(20, 24, a)
    cv.set(21, 25, b)
    cv.outline_color(PAD)


def cup(cv, frame):
    cv.rect(23, 24, 27, 28, CUP)
    cv.rect(24, 24, 26, 24, COFFEE)
    cv.set(28, 25, CUP)
    cv.set(28, 26, CUP)
    cv.outline_color(CUP)
    for i, (x, y) in enumerate([(24, 22), (25, 21), (25, 20), (26, 19)]):
        if (i + frame) % 2 == 0:
            cv.set(x + (frame % 2), y - (frame % 3), STEAM)


def zzz(cv, frame):
    letters = [(23, 6), (26, 3), (28, 0)]
    for i, (x, y) in enumerate(letters[: frame % 4 + 1 if frame % 4 < 3 else 3]):
        s = 1 if i < 2 else 2
        cv.line([(x, y), (x + s + 1, y)], ZZZ)
        cv.line([(x + s + 1, y), (x, y + s + 1)], ZZZ)
        cv.line([(x, y + s + 1), (x + s + 1, y + s + 1)], ZZZ)


def sparkle(cv, x, y, c=GOLD):
    cv.set(x, y, c)
    cv.set(x - 1, y, c)
    cv.set(x + 1, y, c)
    cv.set(x, y - 1, c)
    cv.set(x, y + 1, c)


def confetti(cv, frame):
    pts = [(3, 4), (28, 6), (6, 12), (27, 14), (2, 20), (29, 22), (10, 2), (22, 1)]
    for i, (x, y) in enumerate(pts):
        cv.set(x, (y + frame * 2) % 26, CONFETTI[(i + frame) % len(CONFETTI)])


def sweat(cv, frame):
    y = 5 + frame % 3
    cv.set(25, y, DROP)
    cv.set(25, y + 1, DROP)
    cv.set(24, y + 1, DROP)


def exclamation(cv, frame):
    if frame % 2 == 0:
        cv.rect(28, 0, 29, 4, ALERT)
        cv.rect(28, 6, 29, 7, ALERT)


def tear(cv, frame):
    cv.set(12, 13 + frame % 4, DROP)


# --- Animaciones ---------------------------------------------------------------
# (nombre, fps, loop, [fotogramas]) - cada fotograma es una función que pinta.
# Las que duran mucho (reposo, trabajar, jugar) van a 3–4 fps: cada cuadro
# redibuja la ventana, y la app se queda abierta todo el día.

def anim_frames():
    A = {}

    def f(**kw):
        extra = kw.pop("extra", None)

        def draw(cv, i):
            cat(cv, **kw)
            if extra:
                extra(cv, i)
        # Pose del fotograma, para alinear las capas de accesorios.
        draw.pose = dict(kw)
        return draw

    A["idle"] = (3, True, [
        f(dy=0, tail=0), f(dy=0, tail=1), f(dy=1, tail=2), f(dy=1, tail=3, eyes="closed"),
    ])
    A["walk"] = (8, True, [
        f(dy=0, tail=0, arms="type1"), f(dy=-1, tail=1, arms="down"),
        f(dy=0, tail=2, arms="type2"), f(dy=-1, tail=3, arms="down"),
    ])
    A["sleep"] = (2, True, [
        f(squash=2, eyes="closed", mouth="flat", arms="none", extra=lambda cv, i: zzz(cv, 0)),
        f(squash=2, dy=1, eyes="closed", mouth="flat", arms="none", extra=lambda cv, i: zzz(cv, 1)),
        f(squash=2, dy=1, eyes="closed", mouth="flat", arms="none", extra=lambda cv, i: zzz(cv, 2)),
        f(squash=2, eyes="closed", mouth="flat", arms="none", extra=lambda cv, i: zzz(cv, 3)),
    ])
    A["wakeUp"] = (6, False, [
        f(squash=2, eyes="closed", mouth="flat", arms="none"),
        f(squash=1, eyes="half", mouth="flat", arms="none"),
        f(dy=-1, eyes="closed", mouth="yawn", arms="up"),
        f(dy=-1, eyes="closed", mouth="yawn", arms="up"),
        f(eyes="half", mouth="smile"),
        f(eyes="open", mouth="smile"),
    ])
    A["stretch"] = (6, False, [
        f(eyes="open"), f(dy=-1, eyes="closed", arms="up"), f(dy=-2, eyes="closed", mouth="yawn", arms="up"),
        f(dy=-2, eyes="closed", mouth="yawn", arms="up"), f(dy=-1, eyes="happy", arms="up"), f(eyes="open"),
    ])
    A["work"] = (4, True, [
        f(eyes="down", arms="type1", tail=0, extra=lambda cv, i: laptop(cv, 0)),
        f(eyes="down", arms="type2", tail=1, extra=lambda cv, i: laptop(cv, 1)),
        f(eyes="down", arms="type1", tail=2, extra=lambda cv, i: laptop(cv, 2)),
        f(eyes="down", arms="type2", tail=3, extra=lambda cv, i: laptop(cv, 3)),
    ])
    A["study"] = (3, True, [
        f(eyes="down", arms="hold", tail=0, extra=lambda cv, i: book(cv, 0)),
        f(eyes="down", arms="hold", tail=1, look=1, extra=lambda cv, i: book(cv, 1)),
        f(eyes="down", arms="hold", tail=2, extra=lambda cv, i: book(cv, 2)),
        f(eyes="closed", arms="hold", tail=3, extra=lambda cv, i: book(cv, 3)),
    ])
    A["gaming"] = (4, True, [
        f(eyes="wide", mouth="open", arms="hold", tail=0,
          extra=lambda cv, i: (gamepad(cv, 0), headphones(cv, 0))),
        f(dy=1, eyes="wide", mouth="smile", arms="hold", tail=1,
          extra=lambda cv, i: (gamepad(cv, 1), headphones(cv, 1))),
        f(eyes="wide", mouth="open", arms="hold", tail=2, look=1,
          extra=lambda cv, i: (gamepad(cv, 0), headphones(cv, 0))),
        f(dy=1, eyes="wide", mouth="smile", arms="hold", tail=3, look=-1,
          extra=lambda cv, i: (gamepad(cv, 1), headphones(cv, 1))),
    ])
    A["happy"] = (8, True, [
        f(eyes="happy", mouth="open", tail=0), f(dy=-2, eyes="happy", mouth="open", tail=1),
        f(dy=-3, eyes="happy", mouth="open", tail=2), f(dy=-1, eyes="happy", mouth="smile", tail=3),
    ])
    A["celebrate"] = (8, True, [
        f(dy=0, eyes="star", mouth="open", arms="up", extra=lambda cv, i: confetti(cv, 0)),
        f(dy=-2, eyes="star", mouth="open", arms="up",
          extra=lambda cv, i: (confetti(cv, 1), sparkle(cv, 4, 6))),
        f(dy=-4, eyes="happy", mouth="open", arms="up",
          extra=lambda cv, i: (confetti(cv, 2), sparkle(cv, 27, 9))),
        f(dy=-2, eyes="star", mouth="open", arms="up",
          extra=lambda cv, i: (confetti(cv, 3), sparkle(cv, 5, 15))),
        f(dy=0, eyes="happy", mouth="open", arms="up",
          extra=lambda cv, i: (confetti(cv, 4), sparkle(cv, 26, 3))),
        f(dy=1, eyes="star", mouth="smile", arms="down", extra=lambda cv, i: confetti(cv, 5)),
    ])
    A["tired"] = (3, True, [
        f(dy=1, eyes="half", mouth="flat", ears=1, extra=lambda cv, i: sweat(cv, 0)),
        f(dy=1, eyes="half", mouth="flat", ears=1, extra=lambda cv, i: sweat(cv, 1)),
        f(dy=2, eyes="closed", mouth="yawn", ears=1, extra=lambda cv, i: sweat(cv, 2)),
        f(dy=1, eyes="half", mouth="flat", ears=1, extra=lambda cv, i: sweat(cv, 0)),
    ])
    A["rest"] = (3, True, [
        f(eyes="happy", mouth="smile", arms="down", tail=0, extra=lambda cv, i: cup(cv, 0)),
        f(dy=1, eyes="happy", mouth="smile", arms="down", tail=1, extra=lambda cv, i: cup(cv, 1)),
        f(dy=1, eyes="closed", mouth="smile", arms="down", tail=2, extra=lambda cv, i: cup(cv, 2)),
        f(eyes="happy", mouth="smile", arms="down", tail=3, extra=lambda cv, i: cup(cv, 3)),
    ])
    A["alert"] = (6, True, [
        f(eyes="wide", mouth="open", look=1, extra=lambda cv, i: exclamation(cv, 0)),
        f(dy=-1, eyes="wide", mouth="open", look=1, extra=lambda cv, i: exclamation(cv, 1)),
        f(eyes="wide", mouth="open", look=-1, extra=lambda cv, i: exclamation(cv, 2)),
        f(dy=-1, eyes="wide", mouth="open", look=-1, extra=lambda cv, i: exclamation(cv, 3)),
    ])
    A["sad"] = (3, True, [
        f(dy=1, eyes="half", mouth="sad", ears=1, extra=lambda cv, i: tear(cv, 0)),
        f(dy=1, eyes="half", mouth="sad", ears=1, extra=lambda cv, i: tear(cv, 1)),
        f(dy=2, eyes="half", mouth="sad", ears=1, extra=lambda cv, i: tear(cv, 2)),
        f(dy=1, eyes="half", mouth="sad", ears=1, extra=lambda cv, i: tear(cv, 3)),
    ])
    A["wave"] = (8, False, [
        f(eyes="happy", mouth="open", arms="wave1"), f(eyes="happy", mouth="open", arms="wave2"),
        f(eyes="happy", mouth="open", arms="wave1"), f(eyes="happy", mouth="open", arms="wave2"),
        f(eyes="happy", mouth="open", arms="wave1"), f(eyes="open", mouth="smile"),
    ])
    return A


# --- Accesorios que se desbloquean por nivel ----------------------------------
# Cada accesorio es una capa aparte del mismo tamaño que la hoja: la app la
# dibuja encima del gato con el mismo fotograma, así sigue sus movimientos.

SCARF = (214, 64, 80)
SCARF_STRIPE = (250, 230, 190)
BOW = (255, 110, 170)
BOW_DARK = (200, 60, 120)
LENS = (24, 24, 34)
CROWN = GOLD
GEM = (90, 160, 255)

# Animaciones con algo delante del pecho (laptop, libro, mando).
_HOLDING = {"work", "study", "gaming"}


def _head(pose):
    return 12 + pose.get("dy", 0) + pose.get("squash", 0)


def acc_scarf(cv, pose, anim, i):
    hy = _head(pose)
    y = int(round(hy)) + 6
    cv.rect(10, y, 22, y + 1, SCARF)
    for x in range(12, 22, 4):  # rayas verticales
        cv.rect(x, y, x, y + 1, SCARF_STRIPE)
    if anim not in _HOLDING:  # la punta colgando, si no la tapa nada
        cv.rect(19, y + 2, 20, y + 4, SCARF)
        cv.set(19, y + 4, SCARF_STRIPE)
    cv.outline_color(SCARF)


def acc_bow(cv, pose, anim, i):
    hy = int(round(_head(pose)))
    cx, cy = (22, hy - 6) if pose.get("ears", 0) == 0 else (23, hy - 4)
    cv.rect(cx - 3, cy - 1, cx - 2, cy + 1, BOW)
    cv.rect(cx + 2, cy - 1, cx + 3, cy + 1, BOW)
    cv.set(cx - 1, cy, BOW)
    cv.set(cx + 1, cy, BOW)
    cv.set(cx, cy, BOW_DARK)
    cv.outline_color(BOW)


def acc_sunglasses(cv, pose, anim, i):
    ey = int(_head(pose)) - 1
    look = pose.get("look", 0)
    for x0 in (11 + look, 19 + look):
        cv.rect(x0 - 1, ey - 1, x0 + 2, ey + 1, LENS)
        cv.set(x0 - 1, ey - 1, (120, 130, 160))  # brillo
    cv.line([(13 + look, ey - 1), (18 + look, ey - 1)], LENS)
    cv.set(9 + look, ey - 1, LENS)
    cv.set(23 + look, ey - 1, LENS)


def acc_headphones(cv, pose, anim, i):
    headphones(cv, pose.get("dy", 0) + pose.get("squash", 0))


def acc_crown(cv, pose, anim, i):
    top = int(round(_head(pose) - 6.8))
    cv.rect(12, top - 1, 20, top, CROWN)
    for x in (12, 16, 20):
        cv.set(x, top - 2, CROWN)
    cv.set(14, top - 2, CROWN)
    cv.set(18, top - 2, CROWN)
    cv.set(16, top - 1, GEM)
    cv.outline_color(CROWN)


WIZARD = (70, 74, 190)
WIZARD_DARK = (46, 48, 140)
STAR = (255, 230, 120)
CAPE = (200, 40, 56)
CAPE_DARK = (150, 26, 40)


def acc_wizard_hat(cv, pose, anim, i):
    """Gorro de mago: cono azul con estrellas, un poco ladeado."""
    top = int(round(_head(pose) - 6.8))
    cv.rect(9, top, 23, top + 1, WIZARD_DARK)          # ala
    cv.triangle((11, top + 0.5), (21, top + 0.5), (18, top - 7), WIZARD, body=False)
    cv.set(17, top - 7, WIZARD)                         # punta
    cv.set(14, top - 2, STAR)
    cv.set(17, top - 4, STAR)
    cv.set(18, top - 1, STAR)
    cv.outline_color(WIZARD)
    cv.outline_color(WIZARD_DARK)


def acc_cape(cv, pose, anim, i):
    """Capa de héroe: cuello con broche y dos alas que asoman a los lados."""
    hy = int(round(_head(pose)))
    neck = hy + 6
    cv.rect(10, neck, 22, neck, CAPE)
    flutter = [0, 1, 1, 0][i % 4]
    for side in (-1, 1):
        x0 = 16 + side * 7
        for y in range(neck + 1, min(neck + 9, 30)):
            spread = (y - neck) // 3 + flutter
            cv.rect(min(x0, x0 + side * spread), y, max(x0, x0 + side * spread), y,
                    CAPE if y < neck + 7 else CAPE_DARK)
    cv.set(16, neck, STAR)                               # broche
    cv.outline_color(CAPE)
    cv.outline_color(CAPE_DARK)


ACCESSORIES = {
    "scarf": acc_scarf,
    "bow": acc_bow,
    "sunglasses": acc_sunglasses,
    "headphones": acc_headphones,
    "crown": acc_crown,
    "wizardHat": acc_wizard_hat,
    "cape": acc_cape,
}


# --- PNG ---------------------------------------------------------------------

def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def render_species(sid, previews=True):
    use_species(sid)
    anims = anim_frames()
    order = list(anims.keys())
    cols = max(len(frames) for _, _, frames in anims.values())
    width, height = cols * SIZE, len(order) * SIZE
    sheet = [[0, 0, 0, 0] * width for _ in range(height)]

    meta = {}
    for row, name in enumerate(order):
        fps, loop, frames = anims[name]
        for col, draw in enumerate(frames):
            cv = Canvas()
            draw(cv, col)
            for y in range(SIZE):
                for x in range(SIZE):
                    c = cv.px[y][x]
                    if c is not None:
                        i = (col * SIZE + x) * 4
                        sheet[row * SIZE + y][i:i + 4] = [c[0], c[1], c[2], 255]
        meta[name] = {"row": row, "frames": len(frames), "fps": fps, "loop": loop}

    out = os.path.join(ROOT, "assets", "pets", sid)
    write_png(os.path.join(out, "sheet.png"), width, height, sheet)

    # Capas de accesorios, alineadas fotograma a fotograma con la hoja.
    layers = {}
    for acc, draw_acc in ACCESSORIES.items():
        layer = [[0, 0, 0, 0] * width for _ in range(height)]
        for row, name in enumerate(order):
            for col, draw in enumerate(anims[name][2]):
                cv = Canvas()
                draw_acc(cv, draw.pose, name, col)
                for y in range(SIZE):
                    for x in range(SIZE):
                        c = cv.px[y][x]
                        if c is not None:
                            i = (col * SIZE + x) * 4
                            layer[row * SIZE + y][i:i + 4] = [c[0], c[1], c[2], 255]
        rel = f"assets/pets/{sid}/accessories/{acc}.png"
        write_png(os.path.join(ROOT, rel), width, height, layer)
        layers[acc] = layer
    with open(os.path.join(out, "pet.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "id": sid,
            "name": KIND["name"],
            "sheet": f"assets/pets/{sid}/sheet.png",
            "frameWidth": SIZE,
            "frameHeight": SIZE,
            "animations": meta,
            "accessories": {
                acc: f"assets/pets/{sid}/accessories/{acc}.png" for acc in ACCESSORIES
            },
        }, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    if not previews:
        return
    # Vista previa ampliada x4 sobre fondo oscuro, para revisar el arte.
    scale = 4
    bg = (30, 27, 46)
    preview = []
    for y in range(height * scale):
        row = []
        for x in range(width * scale):
            sx, sy = x // scale, y // scale
            px = sheet[sy][sx * 4: sx * 4 + 4]
            row += (px[:3] + [255]) if px[3] else [bg[0], bg[1], bg[2], 255]
        preview.append(row)
    write_png(os.path.join(ROOT, "build", "sprites", f"{sid}_preview.png"),
              width * scale, height * scale, preview)

    # Vista previa con cada accesorio puesto.
    for acc, layer in layers.items():
        rows = []
        for y in range(height * scale):
            row = []
            for x in range(width * scale):
                sx, sy = x // scale, y // scale
                top = layer[sy][sx * 4: sx * 4 + 4]
                px = top if top[3] else sheet[sy][sx * 4: sx * 4 + 4]
                row += (px[:3] + [255]) if px[3] else [bg[0], bg[1], bg[2], 255]
            rows.append(row)
        write_png(os.path.join(ROOT, "build", "sprites", f"{sid}_{acc}_preview.png"),
                  width * scale, height * scale, rows)
    print(f"{KIND['name']}: {len(order)} animaciones, hoja {width}x{height}")


def main():
    previews = "--sin-vistas" not in sys.argv
    for sid in SPECIES:
        render_species(sid, previews)
    use_species("cat")


if __name__ == "__main__":
    main()
