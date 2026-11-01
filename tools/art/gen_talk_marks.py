"""Marcas das pessoas conversáveis na cena 3D, pintadas à mão (sementes fixas):
  bubble_talk.png  balão creme com borda de tinta, rabicho e "..." (pode conversar)
  bubble_done.png  balão cinza-azulado com um check (já conversou)
  ring_floor.png   anel amarelo pincelado para o chão, aos pés da pessoa (aditivo)
  aura.png         aura de quadrinho atrás do corpo: contorno de cápsula brilhando e faixas de luz
                   pinceladas subindo (aditivo, em tons de cinza: a cor vem do material)
Uso: python tools/art/gen_talk_marks.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_textures import Canvas  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "textures")
S = 256


def hexc(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def bubble_mask(scale=1.0):
    """Silhueta do balão: elipse um pouco torta + rabicho para baixo-esquerda, desenhada em 4x."""
    big = Image.new("L", (S * 4, S * 4), 0)
    d = ImageDraw.Draw(big)
    cx, cy = S * 2, S * 1.75
    rx, ry = S * 1.62 * scale, S * 1.1 * scale
    pts = []
    for i in range(72):
        a = i / 72 * math.tau
        wob = 1 + 0.025 * math.sin(a * 3 + 0.7) + 0.015 * math.sin(a * 7)
        pts.append((cx + math.cos(a) * rx * wob, cy + math.sin(a) * ry * wob))
    d.polygon(pts, fill=255)
    # rabicho
    d.polygon([(cx - rx * 0.35, cy + ry * 0.7), (cx - rx * 0.05, cy + ry * 0.8), (cx - rx * 0.55, cy + ry * 1.55)], fill=255)
    return np.asarray(big.resize((S, S), Image.LANCZOS)).astype(float) / 255.0


def paint_bubble(seed, fill_col, ink_col, mark, scale):
    rng = np.random.default_rng(seed)
    m = bubble_mask(scale)
    cv = Canvas(hexc(fill_col), rng, S)
    for _ in range(140):
        x, y = rng.random() * S, rng.random() * S
        v = 1 + (rng.random() - 0.5) * 0.1
        cv.stroke(x, y, rng.normal(-0.4, 0.3), rng.uniform(30, 80), rng.uniform(10, 22), hexc(fill_col) * v, 0.6, 0.6, 0.6, 0.05)
    col = np.clip(cv.c, 0, 1)
    # borda de tinta: anel da máscara (dilatada menos ela mesma), engrossando embaixo
    mi = Image.fromarray((m * 255).astype(np.uint8))
    dil = np.asarray(mi.filter(ImageFilter.MaxFilter(13))).astype(float) / 255.0
    edge = np.clip(dil - m * 0.85, 0, 1)
    alpha = np.clip(np.maximum(m, dil), 0, 1)
    ink = hexc(ink_col)
    col = col * (1 - edge[..., None]) + ink * edge[..., None]
    img = Image.fromarray((np.dstack([col, alpha]) * 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S * 0.44
    inkc = tuple(int(c * 255) for c in ink) + (255,)
    if mark == "dots":
        for k in (-1, 0, 1):
            r = 13 * scale
            x = cx + k * 44 * scale
            d.ellipse([x - r, cy - r + (k * 2), x + r, cy + r + (k * 2)], fill=inkc)
    else:
        w = int(16 * scale)
        d.line([(cx - 38 * scale, cy), (cx - 8 * scale, cy + 28 * scale), (cx + 44 * scale, cy - 30 * scale)], fill=inkc, width=w, joint="curve")
    return img


def ring():
    rng = np.random.default_rng(7)
    cv = Canvas(np.zeros(3), rng, S)
    for _ in range(90):
        a = rng.random() * math.tau
        r = S * 0.38 + rng.normal(0, 4)
        x, y = S / 2 + math.cos(a) * r, S / 2 + math.sin(a) * r
        cv.stroke(x, y, a + math.pi / 2, rng.uniform(30, 60), rng.uniform(8, 16), np.ones(3) * rng.uniform(0.7, 1.0), 0.7, 0.6, 0.7, 0.05, curve=0.4)
    v = cv.c[..., 0]
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.hypot(xx - S / 2, yy - S / 2) / (S / 2)
    glow = np.clip(1 - np.abs(d - 0.76) / 0.25, 0, 1) ** 2 * 0.35
    a = np.clip(v + glow, 0, 1) * (d < 0.98)
    col = hexc("#ffc83d")
    img = np.dstack([np.ones((S, S, 3)) * col, a])
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA")


def aura():
    rng = np.random.default_rng(9)
    w, h = 256, 512
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    # distância a uma cápsula vertical (o corpo); a aura é uma faixa logo fora dela
    cx, r = w / 2, w * 0.24
    y0, y1 = h * 0.2, h * 0.86
    cy = np.clip(yy, y0, y1)
    d = np.hypot(xx - cx, yy - cy) - r
    band = np.clip(1 - np.abs(d - 14) / 26, 0, 1) ** 1.5
    soft = np.clip(1 - d / 70, 0, 1) ** 2 * 0.35 * (d > 0)
    cv = Canvas(np.zeros(3), rng, h, w)
    # faixas de luz subindo, mais fortes nas laterais, que somem no alto
    for _ in range(70):
        side = rng.choice([-1, 1])
        x = cx + side * (r + rng.uniform(4, 40))
        y = rng.uniform(h * 0.15, h * 0.9)
        cv.stroke(x, y, -math.pi / 2 + rng.normal(0, 0.08), rng.uniform(40, 120), rng.uniform(3, 8), np.ones(3) * rng.uniform(0.5, 1.0), 0.8, 0.5, 0.9, 0.05)
    streak = cv.c[..., 0] * np.clip((yy - h * 0.05) / (h * 0.5), 0, 1)
    a = np.clip(band * 0.35 + soft * 0.8 + streak * 0.75, 0, 1)
    # base esmaece (os pés já têm o anel do chão) e topo esmaece
    a *= np.clip((h * 0.97 - yy) / (h * 0.1), 0, 1) * np.clip(yy / (h * 0.12), 0, 1)
    img = np.dstack([np.ones((h, w, 3)), a])
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    aura().save(os.path.join(OUT, "aura.png"))
    os.makedirs(OUT, exist_ok=True)
    paint_bubble(1, "#fff4d6", "#111a33", "dots", 1.0).save(os.path.join(OUT, "bubble_talk.png"))
    paint_bubble(2, "#8a96b8", "#26335f", "check", 1.0).save(os.path.join(OUT, "bubble_done.png"))
    ring().save(os.path.join(OUT, "ring_floor.png"))
    print("ok")
