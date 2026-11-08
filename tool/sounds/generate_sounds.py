#!/usr/bin/env python3
"""Genera los sonidos 8-bit de PixelMate (ondas cuadradas, como las consolas
de antes). Sin dependencias: escribe WAV con el módulo `wave`.

Uso:  python3 tool/sounds/generate_sounds.py
Salida: assets/sounds/<nombre>.wav
"""

import math
import os
import struct
import wave

RATE = 22050
VOLUME = 0.22  # suave: acompaña, no asusta
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def freq(note):
    """'C5' -> Hz (La4 = 440)."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n = names[note[0]] + (1 if "#" in note else 0)
    octave = int(note[-1])
    return 440.0 * 2 ** ((n + (octave - 4) * 12) / 12)


def tone(note, seconds, duty=0.5, shape="square"):
    """Una nota con un ataque y una caída cortos para que no haga clic."""
    f = freq(note)
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        phase = (i * f / RATE) % 1.0
        if shape == "triangle":
            v = 4 * abs(phase - 0.5) - 1
        else:
            v = 1.0 if phase < duty else -1.0
        attack = min(1.0, i / (RATE * 0.005))
        release = min(1.0, (n - i) / (RATE * 0.03))
        out.append(v * attack * release * VOLUME)
    return out


def silence(seconds):
    return [0.0] * int(RATE * seconds)


SOUNDS = {
    # Empieza un bloque de enfoque: subida corta y decidida.
    "focus": [("C5", .07), ("E5", .07), ("G5", .07), ("C6", .16)],
    # Descanso: bajada suave (onda triangular, más dulce).
    "rest": [("G5", .12, "triangle"), ("E5", .12, "triangle"),
             ("C5", .24, "triangle")],
    # Meta diaria cumplida: pequeña fanfarria.
    "goal": [("C5", .08), ("E5", .08), ("G5", .08), ("C6", .12),
             None, ("G5", .08), ("C6", .28)],
    # Subir de nivel: arpegio rápido y brillante.
    "level": [("C5", .05, "square", .25), ("G5", .05, "square", .25),
              ("C6", .05, "square", .25), ("E6", .05, "square", .25),
              ("G6", .05, "square", .25), ("C7", .3, "square", .25)],
    # Fin de la jornada: cierre tranquilo.
    "finish": [("G5", .14), ("C6", .14), ("E6", .14), ("C6", .34)],
}


def render(notes):
    samples = []
    for n in notes:
        if n is None:
            samples += silence(.04)
            continue
        note, secs = n[0], n[1]
        shape = n[2] if len(n) > 2 else "square"
        duty = n[3] if len(n) > 3 else 0.5
        samples += tone(note, secs, duty, shape)
        samples += silence(.012)
    return samples


def main():
    out = os.path.join(ROOT, "assets", "sounds")
    os.makedirs(out, exist_ok=True)
    for name, notes in SOUNDS.items():
        data = render(notes)
        with wave.open(os.path.join(out, f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(
                struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in data))
        print(f"{name}.wav  {len(data) / RATE:.2f} s")


if __name__ == "__main__":
    main()
