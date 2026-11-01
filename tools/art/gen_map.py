"""Mapa da escola pintado (planta de arquiteto noir, vista de cima), retrato 1080x1600.

Papel azul-noite com pinceladas, paredes em traço de giz/tinta tremido à mão, mobília de cada sala
desenhada de cima, nomes escritos à mão e portas marcadas em amarelo. Reprodutível (sementes fixas).
Saídas:
  game/assets/map/school_map.png
  game/assets/map/school_map.json   {"size":[w,h], "rooms": {id: {"rect":[x,y,w,h], "label":..., "door":[x,y]}}}
  docs/arte_exploracao/mapa.png      folha de conferência (mapa + áreas tocáveis)
Uso: python tools/art/gen_map.py
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_textures import Canvas, kuwahara_wrap, soft_noise  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "map")
DOCS = os.path.join(ROOT, "docs", "arte_exploracao")
FONTS = os.path.join(ROOT, "game", "assets", "fonts")
W, H = 1080, 1600
SS = 2   # desenho em 2x e redução no fim: traço com borda macia

PAPER = "#13224a"
ROOM = "#1c2f62"
OUTSIDE = "#16294f"
CHALK = (214, 226, 255)
CHALK_DIM = (150, 170, 220)
YEL = (255, 200, 61)
PINK = (255, 79, 163)
CREAM = (255, 240, 205)

# salas: id -> (rect x, y, w, h), rótulo, lado da porta
ROOMS = {
    "teatro": ((40, 120, 390, 300), "Teatro", "r"),
    "biblioteca": ((40, 430, 390, 300), "Biblioteca", "r"),
    "sala_aula": ((40, 740, 390, 290), "Sala de aula", "r"),
    "sala_musica": ((40, 1040, 390, 280), "Sala de música", "r"),
    "sala_diretor": ((650, 120, 390, 230), "Sala do diretor", "l"),
    "sala_professores": ((650, 360, 390, 240), "Sala dos professores", "l"),
    "cantina": ((650, 610, 390, 270), "Cantina", "l"),
    "laboratorio": ((650, 890, 390, 220), "Laboratório", "l"),
    "deposito": ((650, 1120, 390, 200), "Depósito", "l"),
    "corredor": ((440, 120, 200, 1200), "Corredor", "b"),
    "patio": ((40, 1340, 500, 230), "Pátio", "t"),
    "quadra": ((550, 1340, 490, 230), "Quadra", "t"),
}


def hexc(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


class Ink:
    """Traço à mão: linhas tremidas (ruído suave ao longo do traço), desenhadas em 2x."""

    def __init__(self, img, rng):
        self.d = ImageDraw.Draw(img, "RGBA")
        self.rng = rng

    def line(self, pts, col, w=3, wob=1.6, seg=14):
        rng = self.rng
        out = []
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            n = max(2, int(math.hypot(x1 - x0, y1 - y0) / seg))
            ph = rng.random() * 6.28
            nx, ny = -(y1 - y0), (x1 - x0)
            ln = math.hypot(nx, ny) + 1e-6
            nx, ny = nx / ln, ny / ln
            for i in range(n + 1):
                t = i / n
                o = wob * (math.sin(t * 7.0 + ph) * 0.6 + (rng.random() - 0.5) * 0.5)
                out.append(((x0 + (x1 - x0) * t + nx * o) * SS, (y0 + (y1 - y0) * t + ny * o) * SS))
        self.d.line(out, fill=col, width=int(w * SS), joint="curve")

    def rect(self, x, y, w, h, col, lw=3, wob=1.6, over=6):
        # cantos passando um pouquinho do encontro, como em planta desenhada à mão
        o = over
        self.line([(x - o * 0.5, y), (x + w + o, y)], col, lw, wob)
        self.line([(x + w, y - o * 0.5), (x + w, y + h + o)], col, lw, wob)
        self.line([(x + w + o * 0.5, y + h), (x - o, y + h)], col, lw, wob)
        self.line([(x, y + h + o * 0.5), (x, y - o)], col, lw, wob)

    def circle(self, cx, cy, r, col, lw=2.5, wob=1.0):
        pts = []
        ph = self.rng.random() * 6.28
        for i in range(41):
            a = i / 40 * math.tau + ph
            rr = r + wob * math.sin(a * 3 + ph)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        self.line(pts, col, lw, 0.3, 50)

    def fill_rect(self, x, y, w, h, col):
        self.d.rectangle([x * SS, y * SS, (x + w) * SS, (y + h) * SS], fill=col)


# ------------------------------------------------------------------ mobília vista de cima
def furn_desks(k, x, y, w, h):
    # lousa no topo, carteiras em grade, mesa do professor
    k.line([(x + 60, y + 34), (x + w - 60, y + 34)], CHALK, 5)
    k.rect(x + 40, y + 52, 90, 40, CHALK_DIM, 2.5)
    for r in range(3):
        for c in range(4):
            dx = x + 52 + c * ((w - 104) / 3.6)
            dy = y + 115 + r * 50
            k.rect(dx, dy, 46, 24, CHALK_DIM, 2.2, 1.0, 3)
            k.circle(dx + 23, dy + 34, 7, CHALK_DIM, 1.8)


def furn_library(k, x, y, w, h):
    for i in range(4):
        sx = x + 30 + i * 46
        k.rect(sx, y + 40, 22, h - 120, CHALK_DIM, 2.2, 1.0, 3)
        for j in range(int((h - 120) / 16)):
            k.line([(sx + 3, y + 46 + j * 16), (sx + 19, y + 46 + j * 16)], CHALK_DIM, 1.2, 0.3)
    for cx, cy in ((x + w - 110, y + 95), (x + w - 110, y + 185)):
        k.circle(cx, cy, 30, CHALK, 2.5)
        for a in range(4):
            aa = a * math.pi / 2 + 0.4
            k.circle(cx + math.cos(aa) * 46, cy + math.sin(aa) * 46, 8, CHALK_DIM, 1.8)
    k.rect(x + w - 70, y + h - 70, 50, 34, CHALK_DIM, 2.2)   # balcão


def furn_theater(k, x, y, w, h):
    # palco no fundo com borda curva, cortinas, plateia em fileiras
    k.rect(x + 30, y + 34, w - 60, 80, CHALK, 3)
    k.line([(x + 30, y + 114), (x + w / 2, y + 138), (x + w - 30, y + 114)], CHALK, 3, 1.0, 30)
    for s in (0, 1):
        cx = x + 44 if s == 0 else x + w - 44
        for i in range(4):
            k.line([(cx - 8 + i * 5, y + 38), (cx - 8 + i * 5, y + 108)], (255, 120, 160, 200), 2, 0.6)
    k.circle(x + w / 2 + 40, y + 72, 18, YEL + (220,), 2.5)   # holofote no palco
    for r in range(4):
        for c in range(9):
            k.rect(x + 50 + c * ((w - 100) / 9), y + 160 + r * 30, 22, 18, CHALK_DIM, 1.8, 0.6, 2)


def furn_music(k, x, y, w, h):
    # piano encostado, bateria (círculos), cadeiras em meia-lua, estante
    k.rect(x + 26, y + 60, 46, 140, CHALK, 3)
    for i in range(12):
        k.line([(x + 72, y + 64 + i * 11), (x + 86, y + 64 + i * 11)], CHALK_DIM, 1.5, 0.2)
    for cx, cy, r in ((x + 200, y + 110, 30), (x + 160, y + 88, 15), (x + 240, y + 84, 15), (x + 236, y + 140, 18), (x + 168, y + 146, 12)):
        k.circle(cx, cy, r, CHALK, 2.4)
    for i in range(5):
        a = math.pi * (0.15 + i * 0.175)
        k.circle(x + 200 + math.cos(a) * 110, y + 120 + math.sin(a) * 90, 10, CHALK_DIM, 1.8)
    k.rect(x + w - 70, y + 40, 44, 90, CHALK_DIM, 2.2)


def furn_director(k, x, y, w, h):
    k.rect(x + 110, y + 70, 170, 50, CHALK, 3)   # mesa grande
    k.circle(x + 195, y + 50, 14, CHALK_DIM, 2)    # cadeira alta
    for cx in (x + 160, x + 230):
        k.rect(cx - 12, y + 140, 24, 22, CHALK_DIM, 2)
    k.rect(x + 80, y + 54, 230, 130, (255, 120, 160, 140), 2, 1.2)   # tapete
    k.rect(x + w - 70, y + 40, 40, 40, CHALK_DIM, 2.5)   # cofre
    k.line([(x + w - 70, y + 40), (x + w - 30, y + 80)], CHALK_DIM, 1.5)
    k.rect(x + 30, y + 40, 26, 120, CHALK_DIM, 2.2)   # estante de troféus


def furn_teachers(k, x, y, w, h):
    k.rect(x + 100, y + 80, 190, 70, CHALK, 3)
    for i in range(4):
        k.circle(x + 125 + i * 48, y + 66, 10, CHALK_DIM, 1.8)
        k.circle(x + 125 + i * 48, y + 164, 10, CHALK_DIM, 1.8)
    k.rect(x + w - 80, y + 40, 50, 150, CHALK_DIM, 2.2)   # bancada do café
    k.circle(x + w - 55, y + 70, 10, YEL + (220,), 2)
    k.rect(x + 30, y + 40, 60, 40, CHALK_DIM, 2.2)        # escaninho
    for i in range(3):
        k.line([(x + 30 + i * 20, y + 40), (x + 30 + i * 20, y + 80)], CHALK_DIM, 1.2, 0.2)


def furn_cantina(k, x, y, w, h):
    k.rect(x + 40, y + 34, w - 80, 40, CHALK, 3)   # balcão
    for i in range(4):
        k.rect(x + 60 + i * 70, y + 42, 50, 24, CHALK_DIM, 1.6, 0.4, 2)
    for r in range(2):
        ty = y + 120 + r * 70
        k.rect(x + 70, ty, w - 140, 26, CHALK, 2.6)
        k.line([(x + 80, ty - 12), (x + w - 80, ty - 12)], CHALK_DIM, 2.2)
        k.line([(x + 80, ty + 38), (x + w - 80, ty + 38)], CHALK_DIM, 2.2)


def furn_lab(k, x, y, w, h):
    for r in range(2):
        by = y + 60 + r * 80
        k.rect(x + 60, by, w - 140, 34, CHALK, 3)
        k.circle(x + w - 120, by + 17, 9, CHALK_DIM, 2)   # pia
        for c in range(4):
            k.circle(x + 90 + c * 55, by + 52, 8, CHALK_DIM, 1.6)
    k.rect(x + w - 60, y + 40, 34, 120, CHALK_DIM, 2.2)   # armário de vidros


def furn_storage(k, x, y, w, h):
    for bx, by, s in ((x + 40, y + 40, 50), (x + 96, y + 46, 40), (x + 50, y + 96, 44), (x + 150, y + 120, 46), (x + 210, y + 40, 52)):
        k.rect(bx, by, s, s, CHALK_DIM, 2.2, 1.0, 3)
        k.line([(bx, by), (bx + s, by + s)], CHALK_DIM, 1.4, 0.4)
        k.line([(bx + s, by), (bx, by + s)], CHALK_DIM, 1.4, 0.4)
    k.rect(x + w - 70, y + 30, 40, h - 70, CHALK, 2.6)   # prateleira
    k.circle(x + 200, y + 150, 10, YEL + (220,), 2)       # lâmpada pendurada


def furn_corridor(k, x, y, w, h):
    # armários dos dois lados e piso em ladrilho tracejado
    for i in range(int((h - 60) / 26)):
        yy = y + 30 + i * 26
        k.rect(x + 8, yy, 18, 22, CHALK_DIM, 1.4, 0.3, 1)
        k.rect(x + w - 26, yy, 18, 22, CHALK_DIM, 1.4, 0.3, 1)
    for i in range(int(h / 80)):
        k.line([(x + 60, y + 40 + i * 80), (x + w - 60, y + 40 + i * 80)], CHALK_DIM + (90,), 1.2, 0.5)


def furn_patio(k, x, y, w, h):
    k.circle(x + 90, y + 110, 52, CHALK, 3, 4)   # copa da árvore
    k.circle(x + 90, y + 110, 30, CHALK_DIM, 2, 3)
    k.rect(x + 190, y + 70, 90, 22, CHALK_DIM, 2.2)   # banco
    k.circle(x + 300, y + 60, 10, YEL + (230,), 2.5)  # poste
    for i, (dx, dy) in enumerate(((0, 0), (0, 30), (-15, 60), (15, 60), (0, 90))):
        k.rect(x + 370 + dx, y + 40 + dy, 28, 28, CHALK_DIM, 1.8, 0.6, 2)   # amarelinha
    k.circle(x + 230, y + 170, 26, CHALK_DIM + (120,), 1.6, 3)   # poça


def furn_court(k, x, y, w, h):
    m = 34
    k.rect(x + m, y + m, w - 2 * m, h - 2 * m, CHALK, 3)
    k.line([(x + w / 2, y + m), (x + w / 2, y + h - m)], CHALK, 2.6)
    k.circle(x + w / 2, y + h / 2, 34, CHALK, 2.4)
    for s in (0, 1):
        ax = x + m if s == 0 else x + w - m - 70
        k.rect(ax, y + h / 2 - 50, 70, 100, CHALK_DIM, 2.2)
    k.rect(x + w - 70, y + 6, 60, 22, CHALK_DIM, 2)   # placar


FURN = {
    "sala_aula": furn_desks, "biblioteca": furn_library, "teatro": furn_theater, "sala_musica": furn_music,
    "sala_diretor": furn_director, "sala_professores": furn_teachers, "cantina": furn_cantina,
    "laboratorio": furn_lab, "deposito": furn_storage, "corredor": furn_corridor, "patio": furn_patio,
    "quadra": furn_court,
}


def door_of(rect, side):
    x, y, w, h = rect
    if side == "r":
        return (x + w, y + h * 0.5)
    if side == "l":
        return (x, y + h * 0.5)
    if side == "t":
        return (x + w * 0.5, y)
    return (x + w * 0.5, y + h)


def main():
    rng = np.random.default_rng(404)
    # papel: azul-noite com pinceladas largas e manchas (planta de arquiteto antiga)
    cv = Canvas(hexc(PAPER), rng, H, W)
    cv.mul(1.0 + soft_noise(rng, n=H, cut=4)[:, :W] * 0.06)
    for _ in range(1500):
        x, y = rng.random() * W, rng.random() * H
        v = 1 + (rng.random() - 0.5) * 0.16
        cv.stroke(x, y, rng.normal(0.6, 0.4), rng.uniform(60, 180), rng.uniform(14, 34), hexc(PAPER) * v, 0.55, 0.7, 0.7, 0.06)
    # salas um tom acima do papel, pintadas por dentro; áreas externas com outra cor
    for rid, (r, _lab, _s) in ROOMS.items():
        x, y, w, h = r
        base = hexc(OUTSIDE if rid in ("patio", "quadra") else ROOM)
        if rid == "corredor":
            base = hexc("#1a2c5c")
        for _ in range(int(w * h / 900)):
            cv.stroke(x + 8 + rng.random() * (w - 16), y + 8 + rng.random() * (h - 16), rng.normal(0.0, 0.25) if w > h else math.pi / 2,
                      rng.uniform(30, min(120, w * 0.6)), rng.uniform(10, 22), base * (1 + (rng.random() - 0.5) * 0.12), 0.8, 0.6, 0.5, 0.05)
    c = kuwahara_wrap(cv.c, 1)
    # grade fraca de planta
    yy, xx = np.mgrid[0:H, 0:W]
    grid = ((xx % 40 == 0) | (yy % 40 == 0)).astype(float) * 0.05
    c = np.clip(c + grid[..., None] * np.array([0.6, 0.7, 1.0]), 0, 1)
    img = Image.fromarray((c * 255).astype(np.uint8)).resize((W * SS, H * SS), Image.BICUBIC).convert("RGBA")
    k = Ink(img, rng)

    marker = ImageFont.truetype(os.path.join(FONTS, "PermanentMarker-Regular.ttf"), 34 * SS)
    marker_s = ImageFont.truetype(os.path.join(FONTS, "PermanentMarker-Regular.ttf"), 26 * SS)
    bebas = ImageFont.truetype(os.path.join(FONTS, "BebasNeue-Regular.ttf"), 64 * SS)
    bebas_s = ImageFont.truetype(os.path.join(FONTS, "BebasNeue-Regular.ttf"), 26 * SS)

    data = {"size": [W, H], "rooms": {}}
    for rid, (r, lab, side) in ROOMS.items():
        x, y, w, h = r
        FURN[rid](k, x, y, w, h)
        # parede dupla (traço grosso + fino por dentro)
        k.rect(x, y, w, h, CHALK + (255,), 4.5, 1.8, 8)
        k.rect(x + 7, y + 7, w - 14, h - 14, CHALK_DIM + (150,), 1.6, 1.2, 0)
        dx, dy = door_of(r, side)
        data["rooms"][rid] = {"rect": [x, y, w, h], "label": lab, "door": [int(dx), int(dy)]}
    # portas: vão na parede (pinta o papel por cima) e arco de abertura em amarelo
    for rid, (r, lab, side) in ROOMS.items():
        if rid == "corredor":
            continue
        dx, dy = door_of(r, side)
        vertical = side in ("l", "r")
        half = 26
        # folha da porta aberta (traço reto) e o arco de giro pontilhado, como em planta de verdade
        if vertical:
            k.fill_rect(dx - 6, dy - half, 12, half * 2, (24, 40, 86, 255))
            sgn = 1 if side == "l" else -1   # abre para dentro da sala
            hx, hy = dx, dy - half
            k.line([(hx, hy), (hx + sgn * half * 2, hy)], YEL, 3.2, 0.4)
            pts = [(hx + sgn * math.cos(a) * half * 2, hy + math.sin(a) * half * 2) for a in np.linspace(0, math.pi / 2, 9)]
        else:
            k.fill_rect(dx - half, dy - 6, half * 2, 12, (24, 40, 86, 255))
            hx, hy = dx - half, dy
            k.line([(hx, hy), (hx, hy + half * 2)], YEL, 3.2, 0.4)
            pts = [(hx + math.sin(a) * half * 2, hy + math.cos(a) * half * 2) for a in np.linspace(0, math.pi / 2, 9)]
        for a, b in zip(pts[:-1:2], pts[1::2]):
            k.line([a, b], YEL + (170,), 2, 0.2)
    # passagem do corredor para o pátio e a quadra (vão largo embaixo)
    cx0, cy0, cw, chh = ROOMS["corredor"][0]
    k.fill_rect(cx0 + 40, cy0 + chh - 7, cw - 80, 14, (28, 46, 96, 255))

    d = ImageDraw.Draw(img, "RGBA")
    # nomes: placa de papel creme torta com letra de marcador (o corredor escrito na vertical)
    for rid, (r, lab, side) in ROOMS.items():
        x, y, w, h = r
        if rid == "corredor":
            continue
        font = marker if len(lab) < 14 else marker_s
        tw = d.textlength(lab, font=font) / SS
        tx = x + (w - tw) / 2
        ty = y + h - 58 if rid not in ("teatro", "quadra", "patio") else y + h - 56
        if rid == "quadra":
            ty = y + h / 2 + 52
        if rid == "teatro":
            ty = y + 120
        pad = 10
        tag = Image.new("RGBA", (int((tw + pad * 2) * SS), int(46 * SS)), (0, 0, 0, 0))
        td = ImageDraw.Draw(tag)
        td.rounded_rectangle([2, 2, tag.width - 3, tag.height - 3], radius=8 * SS, fill=CREAM + (235,), outline=(17, 26, 51, 255), width=3 * SS)
        td.text((pad * SS, 2 * SS), lab, font=font, fill=(17, 26, 51, 255))
        ang = float(rng.uniform(-3.5, 3.5))
        tag = tag.rotate(ang, resample=Image.BICUBIC, expand=True)
        img.alpha_composite(tag, (int(tx * SS - pad * SS), int(ty * SS)))
    # corredor: letreiro vertical
    cx, cy, cw2, ch2 = ROOMS["corredor"][0]
    lab = Image.new("RGBA", (int(400 * SS), int(60 * SS)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lab)
    ld.text((0, 0), "CORREDOR", font=ImageFont.truetype(os.path.join(FONTS, "PermanentMarker-Regular.ttf"), 40 * SS), fill=YEL + (255,))
    lab = lab.crop(lab.getbbox()).rotate(90, expand=True)
    img.alpha_composite(lab, (int((cx + cw2 / 2) * SS - lab.width / 2), int((cy + ch2 / 2) * SS - lab.height / 2)))
    # título, rosa dos ventos e carimbo
    d.text((40 * SS, 30 * SS), "PLANTA DA ESCOLA", font=bebas, fill=CREAM + (255,))
    d.text((44 * SS, 92 * SS), "turno da noite . não perder", font=bebas_s, fill=CHALK_DIM + (255,))
    rx, ry = W - 90, 64
    k.circle(rx, ry, 30, CHALK, 2.4)
    k.line([(rx, ry + 34), (rx, ry - 40)], CHALK, 3)
    k.line([(rx - 34, ry), (rx + 34, ry)], CHALK_DIM, 2)
    d.text(((rx + 38) * SS, (ry - 52) * SS), "N", font=bebas_s, fill=YEL + (255,))
    # alguém circulou a diretoria com caneta rosa (pista de leve, cor de acento discreta)
    x, y, w, h = ROOMS["sala_diretor"][0]
    k.circle(x + w - 50, y + h - 46, 26, PINK + (200,), 2.4, 3)
    d.text(((x + w - 64) * SS, (y + h - 64) * SS), "?", font=marker_s, fill=PINK + (230,))

    out = img.resize((W, H), Image.LANCZOS).convert("RGB")
    os.makedirs(OUT, exist_ok=True)
    out.save(os.path.join(OUT, "school_map.png"), optimize=True)
    with open(os.path.join(OUT, "school_map.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    # folha: mapa + áreas tocáveis em cima (conferência)
    sheet = Image.new("RGB", (W * 2 + 30, H + 20), (5, 7, 15))
    sheet.paste(out, (10, 10))
    ov = out.convert("RGBA")
    layer = Image.new("RGBA", ov.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(layer, "RGBA")
    for rid, r in data["rooms"].items():
        x, y, w, h = r["rect"]
        od.rectangle([x, y, x + w, y + h], outline=(255, 200, 61, 255), width=3, fill=(255, 200, 61, 40))
        dx, dy = r["door"]
        od.ellipse([dx - 8, dy - 8, dx + 8, dy + 8], fill=(255, 79, 163, 255))
        od.text((x + 8, y + 8), "%s %dx%d" % (rid, w, h), fill=(255, 255, 255, 255))
    ov.alpha_composite(layer)
    sheet.paste(ov.convert("RGB"), (W + 20, 10))
    os.makedirs(DOCS, exist_ok=True)
    sheet.save(os.path.join(DOCS, "mapa.png"))
    small = [rid for rid, r in data["rooms"].items() if r["rect"][2] < 200 or r["rect"][3] < 160]
    print("ok", "salas pequenas:", small)


if __name__ == "__main__":
    main()
