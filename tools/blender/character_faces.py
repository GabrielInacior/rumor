"""Rostos trocáveis do personagem base (RUMOR) + folhas de conferência.

Roda no Python do sistema (PIL). Chamado pelo character_kit.py, mas funciona sozinho:

    python tools/blender/character_faces.py atlas            # eyes_atlas.png + mouth_atlas.png + folha
    python tools/blender/character_faces.py sheet <tiles>    # junta as capturas do Blender

Atlas: 512x256, grade 4x2, célula 128x128, fundo transparente. Ordem (coluna, linha), linha 0 em cima:
  olhos: neutro, feliz, surpreso, bravo / desconfiado, triste, nervoso, piscando
  boca : neutra, sorriso, aberta A, aberta O / triste, torta, nervosa, meio-aberta E
Desenho em 4x e reduzido (traço de tinta grosso, antisserrilhado). Pixel transparente leva a cor da
tinta no RGB para o mipmap do Godot não criar franja clara.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "characters")
DOCS = os.path.join(ROOT, "docs", "arte_exploracao")
FONT_DIR = os.path.join(ROOT, "game", "assets", "fonts")

S = 4                      # supersample
CELL = 128 * S
INK = (12, 15, 33, 255)
WHITE = (252, 249, 240, 255)
IRIS = (74, 50, 38, 255)
IRIS_RIM = (40, 26, 22, 255)
MOUTH_IN = (78, 20, 36, 255)
TONGUE = (214, 98, 108, 255)
TEETH = (252, 250, 244, 255)
SWEAT = (150, 196, 255, 255)
BLUSH = (232, 92, 92, 255)
W = 22                     # traço base (em px do desenho 4x)

EYE_NAMES = ["neutro", "feliz", "surpreso", "bravo", "desconfiado", "triste", "nervoso", "piscando"]
MOUTH_NAMES = ["neutra", "sorriso", "aberta A", "aberta O", "triste", "torta", "nervosa", "meio-aberta E"]


# ------------------------------------------------------------------ geometria 2D
def clip(poly, a, b, c):
    """Sutherland-Hodgman: mantém a parte com a*x + b*y + c >= 0."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        fp, fq = a * p[0] + b * p[1] + c, a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def keep_below(poly, p0, p1):
    """Mantém o que fica abaixo (y maior) da reta p0-p1 (pálpebra de cima)."""
    (x0, y0), (x1, y1) = p0, p1
    # reta: (y - y0)(x1 - x0) - (x - x0)(y1 - y0) >= 0, com x1 > x0
    if x1 < x0:
        (x0, y0), (x1, y1) = (x1, y1), (x0, y0)
    a, b = -(y1 - y0), (x1 - x0)
    return clip(poly, a, b, -(a * x0 + b * y0))


def keep_above(poly, p0, p1):
    (x0, y0), (x1, y1) = p0, p1
    if x1 < x0:
        (x0, y0), (x1, y1) = (x1, y1), (x0, y0)
    a, b = (y1 - y0), -(x1 - x0)
    return clip(poly, a, b, -(a * x0 + b * y0))


def ellipse_pts(cx, cy, rx, ry, n=72, squash_top=1.0):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        s = math.sin(t)
        r = ry * (squash_top if s < 0 else 1.0)
        pts.append((cx + math.cos(t) * rx, cy + s * r))
    return pts


def quad_curve(p0, p1, p2, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
        out.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return out


def stroke(d, pts, w, col=INK):
    """Traço de pincel com pontas redondas."""
    d.line(pts, fill=col, width=int(w), joint="curve")
    r = w / 2
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=col)


def taper(d, pts, w0, w1, col=INK):
    """Traço afinando (sobrancelha, cílio): polígono com largura variável."""
    left, right = [], []
    n = len(pts)
    for i, p in enumerate(pts):
        q0 = pts[max(0, i - 1)]
        q1 = pts[min(n - 1, i + 1)]
        tx, ty = q1[0] - q0[0], q1[1] - q0[1]
        L = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / L, tx / L
        t = i / (n - 1)
        w = (w0 * (1 - t) + w1 * t) / 2 * (0.85 + 0.3 * math.sin(math.pi * t))
        left.append((p[0] + nx * w, p[1] + ny * w))
        right.append((p[0] - nx * w, p[1] - ny * w))
    d.polygon(left + right[::-1], fill=col)
    for p, w in ((pts[0], w0), (pts[-1], w1)):
        r = w / 2 * 0.85
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=col)


def masked(img, poly, painter):
    """Pinta `painter(draw)` só dentro de `poly` (íris dentro do olho, dentes dentro da boca)."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    painter(ImageDraw.Draw(layer))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    img.paste(layer, (0, 0), Image.composite(layer, Image.new("RGBA", img.size, (0, 0, 0, 0)), mask))


def disc(d, cx, cy, r, col):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)


# ------------------------------------------------------------------ olhos
def eye(img, cx, cy, rx, ry, top=None, bottom=None, look=(0.0, 0.08), iris=0.62, pupil=0.5,
        shine=True, big_shine=False, lid_w=1.7, tiny=False):
    """Olho de animação: esclera branca, íris grande escura, brilho, pálpebra superior grossa.
    top/bottom: pares de pontos RELATIVOS (fração de rx, ry) para recortar a pálpebra."""
    d = ImageDraw.Draw(img)
    poly = ellipse_pts(cx, cy, rx, ry, squash_top=0.96)
    if top:
        (a, b), (c, e) = top
        poly = keep_below(poly, (cx + a * rx, cy + b * ry), (cx + c * rx, cy + e * ry))
    if bottom:
        (a, b), (c, e) = bottom
        poly = keep_above(poly, (cx + a * rx, cy + b * ry), (cx + c * rx, cy + e * ry))
    if len(poly) < 3:
        return
    d.polygon(poly, fill=WHITE)
    ix, iy = cx + look[0] * rx, cy + look[1] * ry
    ir = iris * rx

    def paint(dd):
        if tiny:
            disc(dd, ix, iy, ir, INK)
            disc(dd, ix - ir * 0.3, iy - ir * 0.35, ir * 0.32, WHITE)
            return
        disc(dd, ix, iy, ir, IRIS_RIM)
        disc(dd, ix, iy + ir * 0.06, ir * 0.82, IRIS)
        disc(dd, ix, iy, ir * pupil, INK)
        if shine:
            disc(dd, ix - ir * 0.36, iy - ir * 0.38, ir * (0.36 if big_shine else 0.27), WHITE)
            disc(dd, ix + ir * 0.38, iy + ir * 0.34, ir * (0.17 if big_shine else 0.11), WHITE)
    masked(img, poly, paint)
    d = ImageDraw.Draw(img)
    d.line(poly + [poly[0]], fill=INK, width=W, joint="curve")
    # pálpebra de cima mais grossa: parte superior do contorno
    upper = [p for p in poly if p[1] <= cy + ry * 0.12]
    upper.sort(key=lambda p: p[0])
    if len(upper) > 2:
        taper(d, upper, W * 0.9, W * lid_w)


def happy_eye(d, cx, cy, rx, ry):
    stroke(d, quad_curve((cx - rx, cy + ry * 0.25), (cx, cy - ry * 1.05), (cx + rx, cy + ry * 0.25)), W * 1.35)


def closed_eye(d, cx, cy, rx, ry, outer):
    pts = quad_curve((cx - rx, cy - ry * 0.05), (cx, cy + ry * 0.55), (cx + rx, cy - ry * 0.05))
    stroke(d, pts, W * 1.3)
    ox = cx + outer * rx
    stroke(d, [(ox, cy - ry * 0.05), (ox + outer * rx * 0.32, cy - ry * 0.32)], W * 0.8)


def brow(d, p0, p1, p2, w0=W * 1.9, w1=W * 0.9):
    taper(d, quad_curve(p0, p1, p2), w0, w1)


def blush(d, cx, cy, s=1.0):
    for k in range(3):
        x = cx + (k - 1) * 24 * s
        d.line([(x + 10 * s, cy - 14 * s), (x - 10 * s, cy + 14 * s)], fill=BLUSH, width=int(11 * s))


def drop(d, x, y, r, col):
    pts = [(x, y - r * 2.1)] + [(x + math.cos(t) * r, y + math.sin(t) * r)
                                for t in [math.pi * (i / 12) - 0.25 for i in range(13)]] + [(x, y - r * 2.1)]
    pts = [(x, y - r * 2.1)]
    for i in range(25):
        t = -0.35 + (math.pi + 0.7) * i / 24
        pts.append((x + math.cos(t) * r, y + math.sin(t) * r))
    d.polygon(pts, fill=col)
    d.line(pts + [pts[0]], fill=INK, width=int(W * 0.6), joint="curve")
    disc(d, x - r * 0.35, y - r * 0.1, r * 0.22, WHITE)


def draw_eyes(img, ox, oy, kind):
    d = ImageDraw.Draw(img)
    L, R = ox + 0.285 * CELL, ox + 0.715 * CELL      # L = esquerda da imagem (lado +X do rosto visto de frente? não: lado esquerdo de quem olha)
    cy = oy + 0.57 * CELL
    rx, ry = 0.112 * CELL, 0.152 * CELL
    by = oy + 0.24 * CELL                               # altura das sobrancelhas
    bw = 0.13 * CELL                                    # meia largura da sobrancelha

    if kind == "neutro":
        for cx in (L, R):
            eye(img, cx, cy, rx, ry, top=((-1.2, -0.8), (1.2, -0.84)))
        d = ImageDraw.Draw(img)
        brow(d, (L + bw, by + 18), (L, by - 18), (L - bw, by + 6))
        brow(d, (R - bw, by + 18), (R, by - 18), (R + bw, by + 6))
    elif kind == "feliz":
        for cx in (L, R):
            happy_eye(d, cx, cy + 10, rx * 1.05, ry * 0.75)
            blush(d, cx, cy + ry * 1.05, 1.0)
        brow(d, (L + bw, by + 4), (L, by - 44), (L - bw, by - 4))
        brow(d, (R - bw, by + 4), (R, by - 44), (R + bw, by - 4))
    elif kind == "surpreso":
        for cx in (L, R):
            eye(img, cx, cy + 6, rx * 1.18, ry * 1.12, look=(0, 0.02), iris=0.4, pupil=0.55, lid_w=1.2)
        d = ImageDraw.Draw(img)
        brow(d, (L + bw, by - 20), (L, by - 78), (L - bw, by - 30), W * 1.5, W * 0.8)
        brow(d, (R - bw, by - 20), (R, by - 78), (R + bw, by - 30), W * 1.5, W * 0.8)
    elif kind == "bravo":
        eye(img, L, cy + 8, rx, ry * 0.95, top=((-1.3, -0.95), (1.3, -0.05)), look=(0.12, 0.05), lid_w=2.1)
        eye(img, R, cy + 8, rx, ry * 0.95, top=((-1.3, -0.05), (1.3, -0.95)), look=(-0.12, 0.05), lid_w=2.1)
        d = ImageDraw.Draw(img)
        brow(d, (L + bw * 0.95, by + 70), (L, by + 30), (L - bw * 1.05, by - 6), W * 2.4, W * 1.2)
        brow(d, (R - bw * 0.95, by + 70), (R, by + 30), (R + bw * 1.05, by - 6), W * 2.4, W * 1.2)
        # vinco de raiva entre as sobrancelhas
        mx = ox + CELL / 2
        stroke(d, [(mx - 14, by + 40), (mx - 6, by + 74)], W * 0.55)
        stroke(d, [(mx + 14, by + 40), (mx + 6, by + 74)], W * 0.55)
    elif kind == "desconfiado":
        eye(img, L, cy + 6, rx, ry, top=((-1.2, -0.42), (1.2, -0.30)), bottom=((-1.2, 0.86), (1.2, 0.78)),
            look=(0.40, 0.12), iris=0.6, lid_w=2.2)
        eye(img, R, cy + 6, rx, ry, top=((-1.2, -0.30), (1.2, -0.42)), bottom=((-1.2, 0.78), (1.2, 0.86)),
            look=(0.40, 0.12), iris=0.6, lid_w=2.2)
        d = ImageDraw.Draw(img)
        brow(d, (L + bw, by + 4), (L, by - 52), (L - bw, by - 26), W * 1.9, W * 0.9)          # erguida
        brow(d, (R - bw, by + 52), (R, by + 46), (R + bw, by + 30), W * 2.0, W * 1.1)         # baixa e reta
    elif kind == "triste":
        eye(img, L, cy + 6, rx, ry, top=((-1.2, -0.1), (1.2, -0.85)), look=(0.05, 0.3), iris=0.66,
            big_shine=True, lid_w=1.6)
        eye(img, R, cy + 6, rx, ry, top=((-1.2, -0.85), (1.2, -0.1)), look=(-0.05, 0.3), iris=0.66,
            big_shine=True, lid_w=1.6)
        d = ImageDraw.Draw(img)
        brow(d, (L - bw, by + 40), (L, by + 18), (L + bw, by - 28), W * 1.2, W * 2.0)
        brow(d, (R + bw, by + 40), (R, by + 18), (R - bw, by - 28), W * 1.2, W * 2.0)
        drop(d, R + rx * 0.55, cy + ry * 1.25, 15, SWEAT)
    elif kind == "nervoso":
        for cx in (L, R):
            eye(img, cx, cy + 4, rx * 1.08, ry * 1.06, look=(0, 0.0), iris=0.22, tiny=True, lid_w=1.3)
        d = ImageDraw.Draw(img)
        for cx, s in ((L, 1), (R, -1)):
            pts = []
            for i in range(25):
                t = i / 24
                x = cx - s * bw + s * 2 * bw * t
                y = by + 30 - 58 * t + math.sin(t * math.pi * 3) * 9
                pts.append((x, y))
            taper(d, pts, W * 1.2, W * 1.8)
        drop(d, ox + CELL * 0.93, oy + CELL * 0.3, 20, SWEAT)
        drop(d, ox + CELL * 0.07, oy + CELL * 0.45, 13, SWEAT)
    elif kind == "piscando":
        closed_eye(d, L, cy + 6, rx, ry, -1)
        closed_eye(d, R, cy + 6, rx, ry, 1)
        brow(d, (L + bw, by + 26), (L, by - 6), (L - bw, by + 14))
        brow(d, (R - bw, by + 26), (R, by - 6), (R + bw, by + 14))


# ------------------------------------------------------------------ boca
def mouth_shape(img, poly, teeth_top=None, tongue=None, teeth_lines=None, wavy=False):
    d = ImageDraw.Draw(img)
    d.polygon(poly, fill=MOUTH_IN)

    def paint(dd):
        if tongue:
            tx, ty, trx, try_ = tongue
            dd.ellipse([tx - trx, ty - try_, tx + trx, ty + try_], fill=TONGUE)
            dd.line([(tx, ty - try_ * 0.6), (tx, ty + try_ * 0.1)], fill=(160, 60, 74, 255), width=8)
        if teeth_top is not None:
            ys = min(p[1] for p in poly)
            dd.rectangle([0, 0, img.size[0], teeth_top], fill=TEETH)
        if teeth_lines:
            for seg in teeth_lines:
                dd.line(seg, fill=INK, width=int(W * 0.45))
    masked(img, poly, paint)
    d = ImageDraw.Draw(img)
    d.line(poly + [poly[0]], fill=INK, width=W, joint="curve")


def corner(d, x, y, dx, dy):
    stroke(d, [(x, y), (x + dx, y + dy)], W * 0.7)


def draw_mouth(img, ox, oy, kind):
    d = ImageDraw.Draw(img)
    cx, cy = ox + CELL / 2, oy + CELL * 0.52
    if kind == "neutra":
        pts = quad_curve((cx - 105, cy + 2), (cx + 10, cy + 18), (cx + 100, cy - 6))
        stroke(d, pts, W * 1.15)
        corner(d, cx - 112, cy - 6, -8, 14)
    elif kind == "sorriso":
        top = quad_curve((cx - 140, cy - 46), (cx, cy - 18), (cx + 140, cy - 46), 30)
        bot = quad_curve((cx + 140, cy - 46), (cx, cy + 150), (cx - 140, cy - 46), 30)
        poly = top + bot[1:-1]
        mouth_shape(img, poly, teeth_top=cy + 2, tongue=(cx + 10, cy + 92, 70, 40))
        d = ImageDraw.Draw(img)
        corner(d, cx - 150, cy - 60, -18, -12)
        corner(d, cx + 150, cy - 60, 18, -12)
    elif kind == "aberta A":
        poly = []
        for i in range(48):
            t = 2 * math.pi * i / 48
            s = math.sin(t)
            rx = 92 * (1.0 - 0.18 * max(0.0, s))
            ry = 102 if s > 0 else 66
            poly.append((cx + math.cos(t) * rx, cy + 10 + s * ry))
        mouth_shape(img, poly, teeth_top=cy - 30, tongue=(cx + 6, cy + 92, 60, 40))
    elif kind == "aberta O":
        poly = ellipse_pts(cx, cy + 10, 58, 74, 48)
        mouth_shape(img, poly, tongue=(cx, cy + 74, 38, 22))
    elif kind == "triste":
        pts = quad_curve((cx - 100, cy + 46), (cx - 4, cy - 52), (cx + 100, cy + 40))
        pts = [(x, y + math.sin(i * 0.9) * 2.5) for i, (x, y) in enumerate(pts)]
        stroke(d, pts, W * 1.2)
        corner(d, cx - 108, cy + 52, -6, 14)
    elif kind == "torta":
        pts = [(cx - 100, cy + 18)] + quad_curve((cx - 40, cy + 22), (cx + 70, cy + 24), (cx + 112, cy - 40), 18)
        stroke(d, pts, W * 1.2)
        corner(d, cx + 118, cy - 48, 20, -6)
        stroke(d, quad_curve((cx + 132, cy - 70), (cx + 150, cy - 40), (cx + 140, cy - 6), 8), W * 0.6)
    elif kind == "nervosa":
        top, bot = [], []
        for i in range(31):
            t = i / 30
            x = cx - 130 + 260 * t
            top.append((x, cy - 36 + math.sin(t * math.pi * 5) * 9))
            bot.append((x, cy + 40 + math.sin(t * math.pi * 5 + 1.6) * 9))
        poly = top + bot[::-1]
        lines = [[(cx - 130, cy + 2), (cx + 130, cy + 2)]]
        for k in range(1, 6):
            x = cx - 130 + 260 * k / 6
            lines.append([(x, cy - 50), (x, cy + 54)])
        d.polygon(poly, fill=TEETH)
        mouth_shape(img, poly, teeth_top=10 ** 6, teeth_lines=lines)
    elif kind == "meio-aberta E":
        top = quad_curve((cx - 120, cy - 22), (cx, cy - 34), (cx + 120, cy - 22), 30)
        bot = quad_curve((cx + 120, cy - 22), (cx, cy + 120), (cx - 120, cy - 22), 30)
        mouth_shape(img, top + bot[1:-1], teeth_top=cy - 2, tongue=(cx, cy + 66, 62, 26))


# ------------------------------------------------------------------ saída
def finish(canvas):
    small = canvas.convert("RGBa").resize((canvas.width // S, canvas.height // S), Image.LANCZOS).convert("RGBA")
    px = small.load()
    for y in range(small.height):
        for x in range(small.width):
            r, g, b, a = px[x, y]
            if a == 0:
                px[x, y] = (INK[0], INK[1], INK[2], 0)
    return small


def build_atlas(drawer, names):
    canvas = Image.new("RGBA", (4 * CELL, 2 * CELL), (0, 0, 0, 0))
    for i, n in enumerate(names):
        drawer(canvas, (i % 4) * CELL, (i // 4) * CELL, n)
    return finish(canvas)


def font(size, name="PermanentMarker-Regular.ttf"):
    for p in (os.path.join(FONT_DIR, name), "C:/Windows/Fonts/arialbd.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def contact_sheet(eyes, mouth, path):
    """Cada célula ampliada sobre um 'rosto' cor de pele, para julgar leitura no tamanho de celular."""
    sc = 2
    cw = 128 * sc
    pad = 18
    W_ = 4 * (cw + pad) + pad
    H_ = 2 * (2 * (cw + 46) + 60) + 40
    sheet = Image.new("RGBA", (W_, H_), (6, 12, 31, 255))
    d = ImageDraw.Draw(sheet)
    f = font(26)
    ft = font(34)
    y = 14
    for title, atlas, names in (("OLHOS  eyes_atlas.png", eyes, EYE_NAMES), ("BOCA  mouth_atlas.png", mouth, MOUTH_NAMES)):
        d.text((pad, y), title, font=ft, fill=(255, 200, 61, 255))
        y += 50
        for i, n in enumerate(names):
            c, r = i % 4, i // 4
            x0 = pad + c * (cw + pad)
            y0 = y + r * (cw + 46)
            d.rounded_rectangle([x0, y0, x0 + cw, y0 + cw], 26, fill=(214, 160, 124, 255))
            cell = atlas.crop((c * 128, r * 128, c * 128 + 128, r * 128 + 128)).resize((cw, cw), Image.LANCZOS)
            sheet.alpha_composite(cell, (x0, y0))
            # miniatura no tamanho real de celular (célula a 48 px)
            mini = atlas.crop((c * 128, r * 128, c * 128 + 128, r * 128 + 128)).resize((48, 48), Image.LANCZOS)
            d.rounded_rectangle([x0 + cw - 54, y0 + cw - 54, x0 + cw - 4, y0 + cw - 4], 8, fill=(190, 140, 108, 255))
            sheet.alpha_composite(mini, (x0 + cw - 53, y0 + cw - 53))
            d.text((x0 + 6, y0 + cw + 4), f"{i}  ({c},{r})  {n}", font=f, fill=(222, 230, 255, 255))
        y += 2 * (cw + 46) + 16
    sheet.convert("RGB").save(path)


def cmd_atlas():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    eyes = build_atlas(draw_eyes, EYE_NAMES)
    mouth = build_atlas(draw_mouth, MOUTH_NAMES)
    eyes.save(os.path.join(OUT, "eyes_atlas.png"))
    mouth.save(os.path.join(OUT, "mouth_atlas.png"))
    contact_sheet(eyes, mouth, os.path.join(DOCS, "expressoes_folha.png"))
    print("atlas ok")


# ------------------------------------------------------------------ folha do personagem
def painted_bg(w, h, seed=0):
    bg = Image.new("RGBA", (w, h), (6, 12, 31, 255))
    d = ImageDraw.Draw(bg)
    for i in range(h):
        t = i / h
        c = (int(6 + 32 * (1 - t) * 0.6), int(12 + 52 * (1 - t) * 0.6), int(31 + 92 * (1 - t) * 0.6), 255)
        d.line([(0, i), (w, i)], fill=c)
    # poça de luz amarela no chão
    halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for k in range(10, 0, -1):
        a = int(10 + 8 * (10 - k))
        rx, ry = w * 0.36 * k / 10, h * 0.06 * k / 10
        hd.ellipse([w / 2 - rx, h * 0.93 - ry, w / 2 + rx, h * 0.93 + ry], fill=(255, 200, 61, min(a, 120)))
    bg.alpha_composite(halo)
    return bg


def cmd_sheet(tiles):
    """Monta docs/arte_exploracao/personagem_base.png a partir das capturas do Blender."""
    def tile(name, w, h, label, floor=True):
        p = os.path.join(tiles, name + ".png")
        im = Image.open(p).convert("RGBA").resize((w, h), Image.LANCZOS)
        bg = painted_bg(w, h) if floor else Image.new("RGBA", (w, h), (10, 18, 44, 255))
        if not floor:
            d = ImageDraw.Draw(bg)
            for i in range(h):
                t = i / h
                d.line([(0, i), (w, i)], fill=(int(14 + 30 * (1 - t)), int(24 + 46 * (1 - t)), int(58 + 80 * (1 - t)), 255))
        bg.alpha_composite(im)
        d = ImageDraw.Draw(bg)
        d.text((14, 8), label, font=font(30), fill=(255, 200, 61, 255))
        return bg

    big = 640
    row1 = [("front_v1", "frente  (T-pose)"), ("q34_v1", "3/4  curto + fones"),
            ("q34_v2", "3/4  rabo + oculos"), ("q34_v3", "3/4  cacheado + cachecol")]
    row2 = [("face_v1", "olhos feliz (1,0)  boca sorriso (1,0)"), ("face_v2", "desconfiado (0,1)  torta (1,1)"),
            ("face_v3", "surpreso (2,0)  aberta O (3,0)"), ("back_v2", "costas  capuz + rabo")]
    hairs = ["curto", "longo", "coque", "cacheado", "raspado", "franja", "rabo", "acessorios"]
    sm = big // 2
    W_ = 4 * big
    H_ = 2 * big + sm + 0
    sheet = Image.new("RGBA", (W_, H_), (6, 12, 31, 255))
    for i, (n, lab) in enumerate(row1):
        sheet.alpha_composite(tile(n, big, big, lab), (i * big, 0))
    for i, (n, lab) in enumerate(row2):
        sheet.alpha_composite(tile(n, big, big, lab, floor=(n.startswith("back"))), (i * big, big))
    for i, h in enumerate(hairs):
        sheet.alpha_composite(tile("hair_" + h, sm, sm, h, floor=False), (i * sm, 2 * big))
    d = ImageDraw.Draw(sheet)
    for i in range(1, 4):
        d.line([(i * big, 0), (i * big, 2 * big)], fill=(6, 12, 31, 255), width=4)
    d.line([(0, big), (W_, big)], fill=(6, 12, 31, 255), width=4)
    d.line([(0, 2 * big), (W_, 2 * big)], fill=(6, 12, 31, 255), width=4)
    out = os.path.join(DOCS, "personagem_base.png")
    sheet.convert("RGB").save(out)
    print("sheet ok", out)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "atlas"
    if cmd == "atlas":
        cmd_atlas()
    elif cmd == "sheet":
        cmd_sheet(sys.argv[2])
