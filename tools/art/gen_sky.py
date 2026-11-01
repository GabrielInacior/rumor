"""Céus pintados do RUMOR: panoramas equirretangulares 2048x1024 para PanoramaSkyMaterial.

Duas variações com sementes fixas:
  sky_lua.png    noite limpa: faixas de azul pintadas, lua com halo em anéis, nuvens com borda acesa
  sky_chuva.png  nublado de chuva: teto de nuvens, lua só como clarão atrás delas, riscos de chuva
As duas têm, no horizonte, a silhueta da cidade com janelinhas amarelas acesas (360 graus, porque
os interiores enxergam o céu pelas janelas laterais).

Pintado com a frente da câmera (-Z) em u = 0.5 e +X em u = 0.75 (v = 0 é o zênite); ao gravar, o
arquivo gira meia volta porque o Godot usa a frente em u = 0.
Uso: python tools/art/gen_sky.py
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_textures import Canvas, kuwahara_wrap, soft_noise  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "textures")
DOCS = os.path.join(ROOT, "docs", "arte_exploracao")
W, H = 2048, 1024
PX_DEG = W / 360.0


def hexc(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def y_of(e):
    return (90.0 - e) / 180.0 * H


def e_of(y):
    return 90.0 - y / H * 180.0


def x_of(u):
    return u * W


def lerp_stops(stops, e):
    for (e0, c0), (e1, c1) in zip(stops[:-1], stops[1:]):
        if e0 >= e >= e1:
            t = (e0 - e) / (e0 - e1)
            return c0 * (1 - t) + c1 * t
    return stops[-1][1] if e < stops[-1][0] else stops[0][1]


class Sky:
    def __init__(self, seed, stops, bands, moon_u, moon_e, moon_r, halo_col, halo_r, halo_amt):
        self.rng = np.random.default_rng(seed)
        self.stops = [(e, hexc(c)) for e, c in stops]
        self.bands = bands
        self.cv = Canvas(lerp_stops(self.stops, 0), self.rng, H, W)
        self.moon = (x_of(moon_u), y_of(moon_e), moon_r * PX_DEG, moon_e)
        self.halo_col = hexc(halo_col)
        self.halo_r = halo_r * PX_DEG
        self.halo_amt = halo_amt

    def moon_dist(self, x, y):
        mx, my, _, me = self.moon
        dx = (x - mx + W / 2) % W - W / 2
        dx *= math.cos(math.radians(me))   # equirretangular estica na horizontal
        return math.hypot(dx, y - my)

    def sky_color(self, x, y, jitter=0.0, halo=True):
        """Cor do céu no ponto, já quantizada em faixas (cara de pintura, não degradê)."""
        e = e_of(y)
        # quantiza a elevação em faixas, com a borda da faixa ondulando devagar
        q = e + jitter
        lo, hi = -2.0, 70.0
        t = np.clip((q - lo) / (hi - lo), 0, 1) ** 0.55
        t = round(t * self.bands) / self.bands
        eq = lo + (t ** (1 / 0.55)) * (hi - lo)
        c = lerp_stops(self.stops, eq)
        if not halo:
            return c
        # halo da lua: anéis concêntricos (3 degraus), não brilho liso
        d = self.moon_dist(x, y)
        ring = max(0.0, 1.0 - d / self.halo_r)
        ring = math.floor(ring * 4.0) / 4.0
        c = c * (1 - ring * self.halo_amt) + self.halo_col * ring * self.halo_amt
        return c

    def paint_gradient(self, n=9000):
        rng = self.rng
        cv = self.cv
        # primeiro uma passada de fundo cheia (para não sobrar buraco), depois pinceladas por cima
        for y in range(H):
            cv.c[y, :, :] = self.sky_color(0, y, halo=False)
        for _ in range(n):
            # mais pinceladas perto do horizonte, onde a câmera olha
            e = 72 - (rng.random() ** 1.6) * 76   # acima de 72 graus ninguém olha: fica o fundo
            y = y_of(e)
            x = rng.random() * W
            col = self.sky_color(x, y, rng.normal(0, 1.6)) * (1 + rng.normal(0, 0.025))
            ln = min(360.0, rng.uniform(60, 240) / max(0.35, math.cos(math.radians(min(abs(e), 80)))))
            cv.stroke(x, y, rng.normal(0, 0.04), ln, rng.uniform(8, 22), col, rng.uniform(0.6, 0.9), 0.6, 0.6, 0.05)

    def cloud(self, u, e, length_deg, height_deg, body, rim, belly, density=1.0, lit_side=None):
        """Nuvem alongada feita de pinceladas horizontais: miolo, barriga escura e borda de cima acesa."""
        rng = self.rng
        cv = self.cv
        cx, cy = x_of(u), y_of(e)
        L = length_deg * PX_DEG
        Hh = height_deg * PX_DEG
        body, rim, belly = hexc(body), hexc(rim), hexc(belly)
        # silhueta em "lombadas": 3 a 6 elipses lado a lado, alturas diferentes
        lumps = []
        k = rng.integers(3, 7)
        for i in range(k):
            lx = cx + (i / (k - 1) - 0.5) * L * 0.8 + rng.normal(0, L * 0.04)
            lumps.append((lx, rng.uniform(0.5, 1.0) * Hh, rng.uniform(0.25, 0.45) * L))
        cnt = int(L * Hh / 40 * density) + 20
        for _ in range(cnt):
            x = cx + (rng.random() - 0.5) * L
            # altura disponível neste x: maior lombada que cobre o ponto
            top = 0.0
            for lx, lh, lw in lumps:
                dx = (x - lx) / lw
                if abs(dx) < 1:
                    top = max(top, lh * math.sqrt(1 - dx * dx))
            if top <= 1:
                continue
            yy = rng.random()
            y = cy - yy * top
            if yy > 0.82:
                col = rim
            elif yy < 0.22:
                col = belly
            else:
                col = body * (1 - (yy - 0.22) * 0.1) + rim * (yy - 0.22) * 0.25
            # lado virado para a lua ganha mais luz
            if lit_side is not None:
                d = self.moon_dist(x, y)
                k2 = max(0.0, 1.0 - d / (self.halo_r * 1.6))
                col = col * (1 - 0.45 * k2) + self.halo_col * 0.45 * k2 * (0.6 + yy * 0.6)
            cv.stroke(x, y, rng.normal(0, 0.05), rng.uniform(25, 80), rng.uniform(4, 11), col * (1 + rng.normal(0, 0.03)), rng.uniform(0.7, 0.95), 0.5, 0.6, 0.05)
        # fiapos soltos que escapam da nuvem
        for _ in range(int(L / 30)):
            x = cx + (rng.random() - 0.5) * L * 1.2
            y = cy + rng.normal(0, Hh * 0.15)
            cv.stroke(x, y, rng.normal(0, 0.03), rng.uniform(60, 160), rng.uniform(2, 5), body * 1.05, 0.45, 0.6, 0.9, 0.04)

    def paint_moon(self, glow_only=False):
        rng = self.rng
        cv = self.cv
        mx, my, r, me = self.moon
        sx = 1.0 / math.cos(math.radians(me))
        yy, xx = np.mgrid[0:H, 0:W].astype(float)
        dx = ((xx - mx + W / 2) % W - W / 2) / sx
        d = np.hypot(dx, yy - my)
        if glow_only:
            # lua escondida atrás das nuvens: clarão difuso em degraus
            g = np.clip(1 - d / (r * 5), 0, 1)
            g = np.floor(g * 5) / 5
            cv.c = cv.c * (1 - g[..., None] * 0.35) + hexc("#8fa6dc") * g[..., None] * 0.35
            return
        disc = np.clip(r - d + 0.8, 0, 1)
        base = hexc("#e8eeff")
        moonc = np.ones((H, W, 3)) * base
        # sombra do lado oposto à luz (quarto crescente gordo) e mares pintados
        shade = np.clip(((dx + r * 0.35) ** 2 + (yy - my + r * 0.2) ** 2) ** 0.5 / r - 0.95, 0, 1)
        moonc = moonc * (1 - 0.0 * shade[..., None])
        cv.c = cv.c * (1 - disc[..., None]) + moonc * disc[..., None]
        for _ in range(14):
            a = rng.random() * 6.28
            rr = rng.random() ** 0.7 * r * 0.75
            x = mx + math.cos(a) * rr * sx
            y = my + math.sin(a) * rr
            cv.stroke(x, y, rng.random() * 3, rng.uniform(0.2, 0.5) * r * sx, rng.uniform(0.12, 0.3) * r, hexc("#b9c6ea"), 0.55, 0.4, 0.3, 0.04)
        # borda acesa do lado de cima-esquerda
        rim = np.clip(1 - np.abs(d - r * 0.9) / (r * 0.12), 0, 1) * np.clip((-(dx) - (yy - my)) / r, 0, 1)
        cv.c = cv.c * (1 - rim[..., None] * 0.6 * disc[..., None]) + hexc("#ffffff") * (rim * 0.6 * disc)[..., None]
        # recorta de novo a borda (os mares não podem vazar para o céu)
        return disc

    def stars(self, n, min_e=14):
        rng = self.rng
        cv = self.cv
        for _ in range(n):
            e = min_e + (rng.random() ** 0.7) * (88 - min_e)
            x, y = rng.random() * W, y_of(e)
            if self.moon_dist(x, y) < self.halo_r * 1.1:
                continue
            b = rng.uniform(0.35, 0.9)
            col = hexc("#dfe8ff") * b + hexc("#ffe3a0") * (1 - b) * 0.3
            a = rng.uniform(0.4, 0.9)
            cv.stroke(x, y, rng.random() * 3, rng.uniform(1.6, 3.0), rng.uniform(1.2, 2.2), col, a, 0.1, 0.0, 0.0)
            if rng.random() < 0.035:
                # estrela grande: cruz de 4 pontas pintada
                for ang in (0.0, math.pi / 2):
                    cv.stroke(x, y, ang, rng.uniform(9, 14), 1.4, hexc("#eef3ff"), 0.75, 0.1, 0.0, 0.0)

    def city(self, haze_col, far_col, near_col, lit_prob=0.09, warm_glow=0.25):
        """Silhueta da cidade nos 360 graus: fila distante enevoada e fila próxima escura com janelas."""
        rng = self.rng
        cv = self.cv
        hz = y_of(0.0)
        # brilho da cidade logo acima do horizonte (poluição luminosa amarelada, em faixas)
        glow = hexc("#ffc83d")
        dens = soft_noise(rng, n=W, cut=6)[0]   # densidade da cidade varia ao longo do horizonte
        for band, (e0, a0) in enumerate(((5.0, 0.05), (2.8, 0.09), (1.2, 0.13))):
            for x in range(W):
                k = warm_glow * a0 * (1.0 + 0.6 * dens[x])
                y0 = int(y_of(e0))
                cv.c[y0:int(hz) + 1, x] = cv.c[y0:int(hz) + 1, x] * (1 - k) + glow * k
        # chão abaixo do horizonte: escuro
        cv.c[int(hz) + 1:, :] = hexc("#050a1a")

        def row(col, hmin, hmax, wmin, wmax, windows, tower_p):
            x = 0.0
            while x < W:
                w = rng.uniform(wmin, wmax) * PX_DEG
                h = rng.uniform(hmin, hmax) * (1.0 + 0.35 * dens[int(x) % W])
                if rng.random() < tower_p:
                    h *= rng.uniform(1.5, 2.2)
                top = y_of(h)
                x0, x1 = int(x), int(x + w)
                cols = np.arange(x0, x1) % W
                c = np.array(col) * (1 + rng.normal(0, 0.06))
                cv.c[int(top):int(hz) + 2][:, cols] = c
                # telhado: caixa d'água, antena ou degrau
                rr = rng.random()
                if rr < 0.2:
                    tw = max(3, int(w * 0.25))
                    tx = x0 + int(rng.random() * max(1, (x1 - x0 - tw)))
                    cv.c[int(top) - 5:int(top), np.arange(tx, tx + tw) % W] = c
                elif rr < 0.32:
                    ax = (x0 + (x1 - x0) // 2) % W
                    ah = int(rng.uniform(8, 18))
                    cv.c[int(top) - ah:int(top), ax] = c
                    if rng.random() < 0.5:
                        # luzinha de antena: rosa discreto
                        cv.c[int(top) - ah - 1:int(top) - ah + 1, ax] = hexc("#ff4fa3") * 0.8
                elif rr < 0.45:
                    sw = int(w * rng.uniform(0.3, 0.6))
                    cv.c[int(top) - 4:int(top), np.arange(x0, x0 + sw) % W] = c
                if windows:
                    # grade de janelas 2x2 px, poucas acesas (amarelo e branco quente), algumas azul de TV
                    for wy in range(int(top) + 3, int(hz) - 1, 4):
                        for wx in range(x0 + 2, x1 - 2, 4):
                            p = rng.random()
                            if p < lit_prob * (1 + 0.8 * dens[wx % W]):
                                wc = hexc("#ffc83d") if rng.random() < 0.7 else hexc("#ffe3a0")
                                cv.c[wy:wy + 2, np.arange(wx, wx + 2) % W] = wc * rng.uniform(0.75, 1.0)
                            elif p < lit_prob * 1.3 + 0.02:
                                cv.c[wy:wy + 2, np.arange(wx, wx + 2) % W] = hexc("#6f8fd8") * 0.7
                x += w + (rng.uniform(0, 1.2) * PX_DEG if rng.random() < 0.3 else 0)

        row(far_col, 1.6, 4.5, 1.0, 3.5, False, 0.06)
        # janelas da fileira distante: pontinhos esparsos
        for _ in range(900):
            x = rng.random() * W
            y = y_of(rng.uniform(0.3, 3.0))
            if cv.c[int(y), int(x)].mean() < 0.09 and rng.random() < 0.6:
                cv.c[int(y), int(x)] = hexc("#ffc83d") * rng.uniform(0.5, 0.85)
        row(near_col, 0.8, 3.2, 1.5, 4.5, True, 0.05)
        # leve névoa entre as fileiras: pinceladas horizontais finas cor de névoa
        hcol = hexc(haze_col)
        for _ in range(500):
            x = rng.random() * W
            y = y_of(rng.uniform(0.2, 2.5))
            cv.stroke(x, y, 0.0, rng.uniform(40, 140), rng.uniform(1.5, 3.5), hcol, 0.18, 0.5, 0.8, 0.03)

    def rain(self, n=2600, alpha=0.16):
        rng = self.rng
        cv = self.cv
        for _ in range(n):
            e = rng.uniform(-1, 60)
            x, y = rng.random() * W, y_of(e)
            cv.stroke(x, y, math.pi / 2 - 0.2, rng.uniform(18, 46), 1.2, hexc("#9fb4ec"), alpha * rng.uniform(0.5, 1.0), 0.2, 0.4, 0.0)

    def finish(self, path):
        c = kuwahara_wrap(self.cv.c, 1)
        im = Image.fromarray((np.clip(c, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        # o Godot põe a frente da câmera (-Z) em u = 0 (medido na sonda com um panorama de teste);
        # pintamos com a frente no meio (mais fácil de ver) e giramos meia volta só ao gravar
        Image.fromarray(np.roll(np.asarray(im), W // 2, axis=1)).save(path, optimize=True)
        return im


def sky_lua():
    s = Sky(101,
            [(90, "#03071a"), (55, "#071030"), (30, "#0e1b46"), (14, "#18295e"), (5, "#22397a"), (0, "#2f4b8e"), (-5, "#1a2a5a")],
            9, 0.474, 30.0, 3.6, "#6f8fd8", 22.0, 0.32)
    s.paint_gradient()
    s.stars(520)
    # nuvens: uma faixa longa cortando perto da lua, outras espalhadas pelo horizonte inteiro
    rng = s.rng
    s.cloud(0.51, 24.0, 34, 3.6, "#15224d", "#5b78bf", "#0c1638", lit_side=True)
    s.cloud(0.415, 36.0, 22, 2.8, "#122046", "#4f6db3", "#0b1434", lit_side=True)
    for _ in range(16):
        u = rng.random()
        if abs(u - 0.474) < 0.07:
            continue
        s.cloud(u, rng.uniform(7, 30), rng.uniform(14, 36), rng.uniform(2.0, 4.2), "#121e44", "#3f5a9e", "#0a1332", 0.8, lit_side=True)
    s.paint_moon()
    # um fiapo de nuvem passando na frente da parte de baixo da lua (dá profundidade)
    s.cloud(0.482, 28.0, 12, 0.9, "#1a2a5c", "#7f98d6", "#13204a", 1.4, lit_side=True)
    s.city("#2a3f78", hexc("#0f1a40"), hexc("#060b1f"), 0.09, 0.3)
    return s.finish(os.path.join(OUT, "sky_lua.png"))


def sky_chuva():
    s = Sky(202,
            [(90, "#060a1c"), (55, "#0b132e"), (30, "#121d42"), (14, "#1a2756"), (5, "#22336a"), (0, "#2c4280"), (-5, "#182658")],
            7, 0.44, 30.0, 3.6, "#8fa6dc", 26.0, 0.18)
    s.paint_gradient(7000)
    s.stars(60, 40)
    rng = s.rng
    # teto de nuvens quase fechado: muitas camadas largas, barrigas escuras, bordas pouco acesas
    for layer in range(3):
        for _ in range(26):
            u = rng.random()
            e = rng.uniform(6, 48) if layer < 2 else rng.uniform(4, 22)
            body = ["#141e44", "#18244e", "#1d2b5a"][layer]
            rim = ["#2c3f78", "#33498a", "#3d5598"][layer]
            s.cloud(u, e, rng.uniform(28, 60), rng.uniform(3.5, 7.0), body, rim, "#0b1230", 1.0, lit_side=True)
    s.paint_moon(glow_only=True)
    s.city("#2a3f78", hexc("#111c42"), hexc("#070c20"), 0.11, 0.42)
    s.rain()
    return s.finish(os.path.join(OUT, "sky_chuva.png"))


def sheet(ims):
    # folha: panorama inteiro + recorte do que a câmera do celular vê de frente (37 graus de largura)
    pw = 1600
    ph = pw // 2
    crop_w = int(W * 40 / 360)
    crop_h = int(H * 70 / 180)
    cw = 250
    chh = int(cw * crop_h / crop_w)
    sh = Image.new("RGB", (pw + cw * 2 + 32, (ph + 30) * len(ims) + 8), (5, 7, 15))
    d = ImageDraw.Draw(sh)
    for i, (name, im) in enumerate(ims):
        y = 8 + i * (ph + 30)
        sh.paste(im.resize((pw, ph), Image.LANCZOS), (8, y))
        d.text((8, y + ph + 6), name, fill=(255, 200, 61))
        # frente (-Z) e lado (+X), da elevação -5 a +65
        for k, u in enumerate((0.5, 0.75)):
            x0 = int(u * W - crop_w / 2)
            c = im.crop((x0, int(y_of(65)), x0 + crop_w, int(y_of(65)) + crop_h)).resize((cw, chh), Image.LANCZOS)
            sh.paste(c, (pw + 16 + k * (cw + 8), y))
            d.text((pw + 16 + k * (cw + 8), y + chh + 4), "frente" if k == 0 else "lado (+X)", fill=(160, 170, 200))
    os.makedirs(DOCS, exist_ok=True)
    sh.save(os.path.join(DOCS, "ceus_folha.png"))


if __name__ == "__main__":
    a = sky_lua()
    print("ok sky_lua")
    b = sky_chuva()
    print("ok sky_chuva")
    sheet([("sky_lua (noite limpa)", a), ("sky_chuva (nublado de chuva)", b)])
