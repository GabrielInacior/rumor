"""Texturas pintadas proceduráis do RUMOR (reprodutível, sementes fixas).

Cada textura é um mapa de VALOR quase neutro (média de luminância ~0.5, pouca saturação): o shader
toon multiplica a cor da superfície por (tex * 2), então a paleta noite-azul de cada cena manda na
cor e a textura só acrescenta pincelada, variação de tom e estrutura (tábua, ladrilho, tijolo).
Tudo é pintado num "toro" (as pinceladas que saem por um lado voltam pelo outro): sem emenda.

Uso: python tools/art/gen_textures.py   (grava em game/assets/textures/ e uma folha de conferência
em docs/arte_exploracao/texturas_folha.png)
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "textures")
DOCS = os.path.join(ROOT, "docs", "arte_exploracao")
N = 512


# ------------------------------------------------------------------ ruído tileável
def soft_noise(rng, n=N, cut=6.0, aniso=(1.0, 1.0)):
    """Ruído suave e tileável: ruído branco filtrado no domínio da frequência (periódico por natureza).
    cut = frequência de corte em ciclos por textura; aniso estica (x, y)."""
    w = rng.standard_normal((n, n))
    f = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    k = np.sqrt(fx * fx + fy * fy)
    f *= np.exp(-(k / cut) ** 2)
    r = np.real(np.fft.ifft2(f))
    r -= r.mean()
    r /= r.std() + 1e-9
    return r


def blur_wrap(img, sigma):
    """Desfoque gaussiano periódico via FFT (canal único ou RGB)."""
    n = img.shape[0]
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(n)[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    if img.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(img) * g))
    return np.stack([np.real(np.fft.ifft2(np.fft.fft2(img[..., c]) * g)) for c in range(img.shape[2])], -1)


# ------------------------------------------------------------------ pincel
class Canvas:
    def __init__(self, base, rng, n=N):
        self.n = n
        self.c = np.ones((n, n, 3)) * np.array(base, float)
        self.rng = rng

    def stroke(self, x, y, ang, length, width, col, alpha=0.85, bristle=0.55, dry=0.5, jitter=0.05, curve=0.0):
        """Uma pincelada: faixa com cerdas (listras ao longo do traço), ponta que começa cheia e termina
        seca (as cerdas vão falhando), borda levemente irregular e cor variando de cerda em cerda."""
        rng = self.rng
        r = int(max(length, width) * 0.5 + 4)
        ys, xs = np.mgrid[-r:r + 1, -r:r + 1].astype(float)
        ca, sa = math.cos(ang), math.sin(ang)
        u = xs * ca + ys * sa
        v = -xs * sa + ys * ca
        if curve:
            v = v - curve * (u / (length * 0.5 + 1e-6)) ** 2 * width
        hw = width * 0.5
        hl = length * 0.5
        nb = max(6, int(width * 1.5))
        br = rng.random(nb)
        br = np.convolve(np.r_[br, br[:2]], [0.25, 0.5, 0.25], "valid")[:nb]
        vi = np.clip(((v / hw) * 0.5 + 0.5) * (nb - 1), 0, nb - 1).astype(int)
        bv = br[vi]
        # borda do traço ondula devagar ao longo do comprimento (mão humana, não régua)
        ph1, ph2 = rng.random() * 6.28, rng.random() * 6.28
        un = u / (length + 1e-6)
        wob = 1.0 + 0.07 * np.sin(un * 8.2 + ph1) + 0.035 * np.sin(un * 23.0 + ph2)
        m_across = np.clip((hw * wob - np.abs(v)) / 1.1, 0, 1)
        # ponta arredondada no começo; no fim as cerdas falham (pincel secando)
        vv = np.clip(np.abs(v) / max(hw, 1e-6), 0, 1)
        cap = hw * 0.5 * vv * vv
        m_along = np.clip((hl - np.abs(u) - cap) / 1.5, 0, 1)
        t = np.clip(u / (2 * hl) + 0.5, 0, 1)
        m_dry = np.clip((bv - (t ** 3.0) * dry * 0.9) * 4.0 + 0.6, 0, 1)
        a = alpha * m_across * m_along * m_dry * (1.0 - bristle * (1.0 - bv) * 0.35)
        if a.max() <= 0.001:
            return
        col = np.array(col, float)
        colpix = col[None, None, :] * (1.0 + (bv[..., None] - 0.5) * jitter * 2.0)
        rows = (int(round(y)) + np.arange(-r, r + 1)) % self.n
        cols = (int(round(x)) + np.arange(-r, r + 1)) % self.n
        ix = np.ix_(rows, cols)
        sub = self.c[ix]
        a3 = a[..., None]
        self.c[ix] = sub * (1 - a3) + colpix * a3

    def dab(self, x, y, rad, col, alpha=0.8):
        """Toque curto e redondo de ponta de pincel (lascas de granilite, agregado do concreto)."""
        self.stroke(x, y, self.rng.random() * math.pi, rad * 2.0 * (1 + self.rng.random() * 0.6), rad * 1.6, col, alpha, 0.3, 0.2)

    def line(self, pts, width, col, alpha=0.8, seg=10.0):
        """Linha pintada (rejunte, rachadura, emenda) feita de pinceladas curtas encadeadas."""
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            d = math.hypot(x1 - x0, y1 - y0)
            k = max(1, int(d / seg))
            for i in range(k):
                a = i / k
                b = (i + 1) / k
                xa, ya = x0 + (x1 - x0) * a, y0 + (y1 - y0) * a
                xb, yb = x0 + (x1 - x0) * b, y0 + (y1 - y0) * b
                ln = math.hypot(xb - xa, yb - ya) + width * 1.2
                self.stroke((xa + xb) / 2, (ya + yb) / 2, math.atan2(yb - ya, xb - xa), ln, width,
                            col * (1 + (self.rng.random() - 0.5) * 0.1), alpha, 0.3, 0.15)

    def mul(self, m):
        self.c *= m[..., None] if m.ndim == 2 else m

    def img(self):
        return self.c


def tone(v, warm=0.0):
    """Cinza com leve deriva de cor: warm>0 puxa para ocre, warm<0 para azul. Pouca saturação."""
    return np.array([v * (1 + 0.06 * warm), v, v * (1 - 0.07 * warm)])


def finish(c, contrast=1.0, sat=0.6):
    """Normaliza: luminância média 0.5, contraste controlado e saturação baixa (a cor vem da cena)."""
    lum = c @ np.array([0.3, 0.59, 0.11])
    chroma = c - lum[..., None]
    lum = (lum - lum.mean()) * contrast + 0.5
    out = lum[..., None] + chroma * sat
    return np.clip(out, 0, 1)


def kuwahara_wrap(img, r=2):
    """Filtro de Kuwahara periódico: achata microvariação em manchas de tinta (cara de óleo/guache)."""
    n = img.shape[0]
    pad = np.pad(img, ((r, r), (r, r), (0, 0)), mode="wrap")
    lum = pad @ np.array([0.3, 0.59, 0.11])

    def box(a, ox, oy):
        # média numa janela (r+1)x(r+1) com o canto deslocado
        acc = np.zeros((n, n) + a.shape[2:])
        for dy in range(r + 1):
            for dx in range(r + 1):
                acc += a[r + oy + dy - r: r + oy + dy - r + n, r + ox + dx - r: r + ox + dx - r + n]
        return acc / (r + 1) ** 2

    best = None
    bestv = None
    for ox, oy in ((0, 0), (r, 0), (0, r), (r, r)):
        m = box(pad, ox, oy)
        ml = box(lum, ox, oy)
        m2 = box(lum * lum, ox, oy)
        var = m2 - ml * ml
        if best is None:
            best, bestv = m, var
        else:
            sel = var < bestv
            best = np.where(sel[..., None], m, best)
            bestv = np.where(sel, var, bestv)
    return best


def save(name, c, size=N):
    os.makedirs(OUT, exist_ok=True)
    im = Image.fromarray((np.clip(c, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    if size != c.shape[0]:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(os.path.join(OUT, name + ".png"), optimize=True)
    return im


# ------------------------------------------------------------------ texturas
def tex_brush(seed=11):
    """Pincelada neutra (cinza): textura de tela para qualquer superfície lisa."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.5), rng)
    low = soft_noise(rng, cut=3.0)
    cv.mul(1.0 + low * 0.06)
    # camadas de pinceladas largas em direções que mudam devagar (campo de direção suave)
    field = soft_noise(rng, cut=2.0) * 1.2
    for layer, (cnt, ln, wd, amp) in enumerate(((260, (60, 140), (18, 34), 0.12), (700, (30, 80), (8, 16), 0.1), (900, (14, 34), (4, 8), 0.08))):
        for _ in range(cnt):
            x, y = rng.random() * N, rng.random() * N
            ang = field[int(y) % N, int(x) % N] + (rng.random() - 0.5) * 0.6 + layer * 0.5
            v = 0.5 + (rng.random() - 0.5) * 2 * amp
            cv.stroke(x, y, ang, rng.uniform(*ln), rng.uniform(*wd), tone(v), rng.uniform(0.35, 0.7), 0.7, 0.7, 0.12)
    # grão de tela: trama finíssima
    yy, xx = np.mgrid[0:N, 0:N]
    weave = (np.sin(xx * 2 * math.pi / 4) * np.sin(yy * 2 * math.pi / 4)) * 0.015
    c = cv.img() + weave[..., None]
    c = finish(c, 1.0, 0.0)
    return c


def tex_plaster(seed=21):
    """Reboco/parede pintada: rolo e trincha em várias direções, manchas, poucas marcas."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.55, -0.2), rng)
    cv.mul(1.0 + soft_noise(rng, cut=2.5) * 0.07 + soft_noise(rng, cut=9) * 0.03)
    for _ in range(320):
        x, y = rng.random() * N, rng.random() * N
        ang = rng.choice([0.0, math.pi / 2, math.pi / 4, -math.pi / 4]) + (rng.random() - 0.5) * 0.5
        v = 0.55 + (rng.random() - 0.5) * 0.12
        cv.stroke(x, y, ang, rng.uniform(70, 170), rng.uniform(26, 48), tone(v, rng.uniform(-0.6, 0.4)), rng.uniform(0.25, 0.5), 0.8, 0.8, 0.08)
    for _ in range(900):
        x, y = rng.random() * N, rng.random() * N
        v = 0.55 + (rng.random() - 0.5) * 0.14
        cv.stroke(x, y, rng.random() * math.pi, rng.uniform(16, 44), rng.uniform(6, 14), tone(v, rng.uniform(-0.5, 0.5)), rng.uniform(0.2, 0.45), 0.7, 0.7, 0.1)
    # manchas de umidade escorrendo (verticais, raras)
    for _ in range(5):
        x, y = rng.random() * N, rng.random() * N
        for k in range(6):
            cv.stroke(x + rng.normal(0, 6), y + k * 22, math.pi / 2 + rng.normal(0, 0.05), rng.uniform(30, 60), rng.uniform(10, 22), tone(0.47, 0.6), 0.18, 0.8, 0.9)
    c = kuwahara_wrap(cv.img(), 2)
    return finish(c, 1.0, 0.7)


def tex_tile(seed=31):
    """Piso de granilite escolar em placas de 4x4 por textura: lascas, rejunte e brilho de cera."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.55), rng)
    T = N // 4
    for ty in range(4):
        for tx in range(4):
            v = 0.55 + (rng.random() - 0.5) * 0.08
            w = rng.uniform(-0.5, 0.5)
            for _ in range(26):
                x = tx * T + rng.random() * T
                y = ty * T + rng.random() * T
                cv.stroke(x, y, rng.choice([0.0, math.pi / 2]) + rng.normal(0, 0.15), rng.uniform(40, 90), rng.uniform(16, 30),
                          tone(v + (rng.random() - 0.5) * 0.05, w), 0.5, 0.7, 0.6, 0.06)
    # lascas do granilite: claras, escuras e algumas quentes
    for _ in range(2600):
        x, y = rng.random() * N, rng.random() * N
        k = rng.random()
        col = tone(0.78, 0.2) if k < 0.4 else (tone(0.3, -0.3) if k < 0.8 else tone(0.6, 1.5))
        cv.dab(x, y, rng.uniform(0.8, 2.4), col, rng.uniform(0.45, 0.85))
    # rejunte: linha escura com uma luz fina ao lado (canto da placa gasto)
    for i in range(4):
        p = i * T
        cv.line([(p, -4), (p, N + 4)], 3.2, tone(0.28, -0.3), 0.9, 14)
        cv.line([(-4, p), (N + 4, p)], 3.2, tone(0.28, -0.3), 0.9, 14)
        cv.line([(p + 3, -4), (p + 3, N + 4)], 1.6, tone(0.7), 0.35, 14)
        cv.line([(-4, p + 3), (N + 4, p + 3)], 1.6, tone(0.7), 0.35, 14)
    # brilho de cera: arcos largos de enceradeira, bem leves
    for _ in range(40):
        x, y = rng.random() * N, rng.random() * N
        cv.stroke(x, y, rng.random() * math.pi, rng.uniform(80, 180), rng.uniform(20, 40), tone(0.72), 0.12, 0.9, 0.9, 0.05, curve=0.6)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.05, 0.6)


def _planks(rng, plank_h, min_len, max_len, base_v, grain_amp, var, seam_dark, knots, gloss=0.0, warm=0.6):
    cv = Canvas(tone(base_v, warm), rng)
    rows = N // plank_h
    for r in range(rows):
        y0 = r * plank_h
        x = rng.random() * N
        end = x + N
        while x < end - 4:
            ln = min(rng.uniform(min_len, max_len), end - x)
            v = base_v + (rng.random() - 0.5) * var
            w = warm + rng.uniform(-0.4, 0.4)
            # base da tábua: pinceladas longas no sentido do veio
            for _ in range(int(ln * plank_h / 90) + 4):
                wd = rng.uniform(plank_h * 0.22, plank_h * 0.48)
                sl = min(rng.uniform(40, 120), ln)
                sx = x + sl / 2 + rng.random() * max(1.0, ln - sl)
                sy = y0 + wd / 2 + 2 + rng.random() * max(0.5, plank_h - wd - 4)
                cv.stroke(sx, sy, rng.normal(0, 0.015), sl, wd, tone(v + (rng.random() - 0.5) * 0.09, w), 0.8, 0.6, 0.55, 0.06)
            # veios finos
            for _ in range(int(ln / 7)):
                sl = min(rng.uniform(30, 110), ln)
                sx = x + sl / 2 + rng.random() * max(1.0, ln - sl)
                sy = y0 + 3 + rng.random() * (plank_h - 6)
                dv = (rng.random() - 0.6) * grain_amp
                cv.stroke(sx, sy, rng.normal(0, 0.02), sl, rng.uniform(1.2, 2.6), tone(v + dv, w), rng.uniform(0.35, 0.7), 0.4, 0.8, 0.05, curve=rng.normal(0, 0.25))
            # nó da madeira: anéis curtos em volta de um ponto
            if rng.random() < knots:
                kx = x + rng.uniform(0.2, 0.8) * ln
                ky = y0 + plank_h * rng.uniform(0.35, 0.65)
                for k in range(4):
                    cv.stroke(kx, ky, 0.0, 10 + k * 7, 3 + k * 2.4, tone(v - 0.1 + k * 0.025, w + 0.3), 0.55 - k * 0.1, 0.3, 0.3, 0.05)
            # emenda de topo
            cv.line([(x, y0 + 1), (x, y0 + plank_h - 1)], 2.0, tone(base_v - seam_dark, -0.2), 0.85, 6)
            x += ln
        # emenda comprida entre tábuas, com um fio de luz na borda de cima
        cv.line([(-4, y0), (N + 4, y0)], 2.4, tone(base_v - seam_dark, -0.2), 0.9, 16)
        cv.line([(-4, y0 + 2.5), (N + 4, y0 + 2.5)], 1.2, tone(base_v + 0.12), 0.3, 16)
    if gloss:
        # verniz: reflexos longos e claros no sentido das tábuas
        for _ in range(60):
            cv.stroke(rng.random() * N, rng.random() * N, rng.normal(0, 0.02), rng.uniform(120, 300), rng.uniform(6, 20), tone(base_v + 0.22, 0.2), gloss * rng.uniform(0.5, 1.0), 0.9, 0.95, 0.04)
    return cv


def tex_wood_planks(seed=41):
    """Tábuas de assoalho/palco: 8 por textura, juntas desencontradas, veio e nós."""
    rng = np.random.default_rng(seed)
    cv = _planks(rng, N // 8, 140, 360, 0.52, 0.16, 0.12, 0.24, 0.35)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.0, 0.7)


def tex_wood_grain(seed=43):
    """Madeira de móvel (sem emendas): veio pintado e manchas do verniz."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.52, 0.6), rng)
    cv.mul(1.0 + soft_noise(rng, cut=5, aniso=(0.25, 1.6)) * 0.06)
    for _ in range(520):
        x, y = rng.random() * N, rng.random() * N
        v = 0.52 + (rng.random() - 0.5) * 0.1
        cv.stroke(x, y, rng.normal(0, 0.04), rng.uniform(80, 200), rng.uniform(10, 26), tone(v, rng.uniform(0.2, 1.0)), 0.45, 0.6, 0.75, 0.06)
    for _ in range(900):
        x, y = rng.random() * N, rng.random() * N
        dv = (rng.random() - 0.65) * 0.22
        cv.stroke(x, y, rng.normal(0, 0.05), rng.uniform(40, 160), rng.uniform(1.0, 2.4), tone(0.52 + dv, 0.7), rng.uniform(0.3, 0.6), 0.4, 0.8, 0.05, curve=rng.normal(0, 0.5))
    for _ in range(3):
        kx, ky = rng.random() * N, rng.random() * N
        for k in range(5):
            cv.stroke(kx, ky, 0.0, 14 + k * 9, 4 + k * 3, tone(0.4 + k * 0.03, 1.0), 0.5 - k * 0.07, 0.3, 0.3, 0.05)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.0, 0.7)


def tex_court(seed=51):
    """Quadra: réguas estreitas e compridas, envernizadas, reflexo longo do verniz."""
    rng = np.random.default_rng(seed)
    cv = _planks(rng, N // 16, 260, 520, 0.54, 0.1, 0.08, 0.16, 0.08, gloss=0.22, warm=0.8)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.0, 0.75)


def tex_metal(seed=61):
    """Metal pintado (armário, prateleira): trincha vertical, amassados, riscos e lascas."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.55, -0.3), rng)
    cv.mul(1.0 + soft_noise(rng, cut=4, aniso=(1.6, 0.3)) * 0.05)
    for _ in range(700):
        x, y = rng.random() * N, rng.random() * N
        v = 0.55 + (rng.random() - 0.5) * 0.08
        cv.stroke(x, y, math.pi / 2 + rng.normal(0, 0.03), rng.uniform(60, 180), rng.uniform(6, 18), tone(v, -0.3), 0.4, 0.75, 0.8, 0.05)
    # amassados: manchas escuras com luz de um lado
    for _ in range(9):
        x, y = rng.random() * N, rng.random() * N
        rr = rng.uniform(10, 24)
        cv.stroke(x, y, rng.random() * 3, rr * 2, rr * 1.2, tone(0.45, -0.3), 0.3, 0.3, 0.3, 0.03)
        cv.stroke(x - rr * 0.4, y - rr * 0.4, rng.random() * 3, rr * 1.2, rr * 0.5, tone(0.66), 0.25, 0.3, 0.3, 0.03)
    # riscos claros finos e lascas de tinta escura
    for _ in range(70):
        x, y = rng.random() * N, rng.random() * N
        cv.stroke(x, y, rng.normal(0.2, 0.6), rng.uniform(12, 50), rng.uniform(0.8, 1.6), tone(0.78), rng.uniform(0.4, 0.8), 0.2, 0.5, 0.02)
    for _ in range(40):
        cv.dab(rng.random() * N, rng.random() * N, rng.uniform(1.5, 4.0), tone(0.3, 0.8), 0.75)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.0, 0.6)


def tex_fabric(seed=71):
    """Tecido/carpete: trama em sarja, felpa manchada e marcas de uso."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    twill = np.sin((xx + yy) * 2 * math.pi / 6) * 0.5 + 0.5
    cross = np.sin(xx * 2 * math.pi / 3) * np.sin(yy * 2 * math.pi / 3) * 0.5 + 0.5
    cv = Canvas(tone(0.55, 0.2), rng)
    cv.mul(1.0 + soft_noise(rng, cut=7) * 0.07 + soft_noise(rng, cut=40) * 0.05)
    for _ in range(1500):
        x, y = rng.random() * N, rng.random() * N
        v = 0.55 + (rng.random() - 0.5) * 0.12
        cv.stroke(x, y, rng.random() * math.pi, rng.uniform(10, 30), rng.uniform(5, 12), tone(v, rng.uniform(-0.4, 0.6)), 0.35, 0.8, 0.6, 0.12)
    # marcas de pisada: caminhos mais escuros e amassados
    for _ in range(6):
        x, y = rng.random() * N, rng.random() * N
        cv.stroke(x, y, rng.random() * math.pi, rng.uniform(140, 260), rng.uniform(40, 70), tone(0.47), 0.22, 0.9, 0.9, 0.05)
    c = cv.img() * (0.93 + twill[..., None] * 0.08 + cross[..., None] * 0.04)
    c = kuwahara_wrap(c, 1)
    return finish(c, 1.0, 0.6)


def tex_concrete(seed=81):
    """Concreto/calçada: placas de 2 por textura, agregado, manchas de chuva e rachaduras."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.55, -0.1), rng)
    cv.mul(1.0 + soft_noise(rng, cut=3) * 0.08 + soft_noise(rng, cut=14) * 0.04)
    for _ in range(600):
        x, y = rng.random() * N, rng.random() * N
        v = 0.55 + (rng.random() - 0.5) * 0.12
        cv.stroke(x, y, rng.random() * math.pi, rng.uniform(30, 90), rng.uniform(12, 30), tone(v, rng.uniform(-0.5, 0.3)), 0.35, 0.8, 0.7, 0.08)
    for _ in range(2200):
        k = rng.random()
        cv.dab(rng.random() * N, rng.random() * N, rng.uniform(0.6, 1.8), tone(0.36 if k < 0.6 else 0.72), rng.uniform(0.35, 0.7))
    # manchas escuras de água parada
    for _ in range(10):
        x, y = rng.random() * N, rng.random() * N
        for k in range(3):
            cv.stroke(x + rng.normal(0, 10), y + rng.normal(0, 10), rng.random() * 3, rng.uniform(40, 90), rng.uniform(20, 40), tone(0.44, -0.4), 0.2, 0.8, 0.8, 0.04)
    # rachaduras: linha quebrada fina
    for _ in range(4):
        x, y = rng.random() * N, rng.random() * N
        ang = rng.random() * 6.28
        pts = [(x, y)]
        for _ in range(rng.integers(5, 10)):
            ang += rng.normal(0, 0.6)
            x += math.cos(ang) * rng.uniform(10, 24)
            y += math.sin(ang) * rng.uniform(10, 24)
            pts.append((x, y))
        cv.line(pts, 1.4, tone(0.25, -0.3), 0.85, 6)
    # junta de dilatação entre placas
    for p in (0, N // 2):
        cv.line([(p, -4), (p, N + 4)], 3.0, tone(0.3, -0.3), 0.85, 12)
        cv.line([(-4, p), (N + 4, p)], 3.0, tone(0.3, -0.3), 0.85, 12)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.0, 0.6)


def tex_brick(seed=91):
    """Tijolo aparente (fachada): aparelho corrido 8x16 por textura, argamassa clara, tijolos variando."""
    rng = np.random.default_rng(seed)
    cv = Canvas(tone(0.68, 0.0), rng)   # argamassa
    cv.mul(1.0 + soft_noise(rng, cut=10) * 0.05)
    bw, bh = N // 8, N // 16
    mort = 3.0
    for r in range(16):
        off = (bw // 2) * (r % 2)
        for c in range(8):
            x0 = c * bw + off
            y0 = r * bh
            v = 0.48 + (rng.random() - 0.5) * 0.14
            w = rng.uniform(0.2, 1.4)
            if rng.random() < 0.12:
                v -= 0.08   # tijolo queimado
            cx = x0 + bw / 2
            cy = y0 + bh / 2
            # corpo do tijolo em 3 a 4 pinceladas horizontais
            for k in range(4):
                cv.stroke(cx + rng.normal(0, 3), y0 + mort + (k + 0.5) * (bh - 2 * mort) / 4, rng.normal(0, 0.02),
                          bw - mort * 1.6, (bh - 2 * mort) / 2.4, tone(v + (rng.random() - 0.5) * 0.05, w), 0.9, 0.5, 0.25, 0.06)
            # luz na aresta de cima, sombra na de baixo
            cv.stroke(cx, y0 + mort + 1.5, 0, bw - mort * 2.2, 2.0, tone(v + 0.1, w), 0.45, 0.4, 0.4, 0.04)
            cv.stroke(cx, y0 + bh - mort - 1.2, 0, bw - mort * 2.2, 2.2, tone(v - 0.1, w), 0.5, 0.4, 0.4, 0.04)
            # lascas
            for _ in range(rng.integers(0, 3)):
                cv.dab(x0 + rng.random() * bw, y0 + rng.random() * bh, rng.uniform(1.0, 2.5), tone(0.62), 0.6)
    # escorrido de chuva bem leve
    for _ in range(14):
        x = rng.random() * N
        cv.stroke(x, rng.random() * N, math.pi / 2, rng.uniform(80, 200), rng.uniform(8, 18), tone(0.42, -0.5), 0.15, 0.9, 0.9, 0.03)
    c = kuwahara_wrap(cv.img(), 1)
    return finish(c, 1.0, 0.7)


TEXTURES = {
    "brush": tex_brush,
    "plaster": tex_plaster,
    "tile": tex_tile,
    "wood_planks": tex_wood_planks,
    "wood_grain": tex_wood_grain,
    "court": tex_court,
    "metal": tex_metal,
    "fabric": tex_fabric,
    "concrete": tex_concrete,
    "brick": tex_brick,
}

# cor típica de cena para a folha de conferência (a textura é neutra; aqui vemos ela "em uso")
PREVIEW_TINT = {
    "brush": "#4e6fc0", "plaster": "#4c5c94", "tile": "#5d6f9e", "wood_planks": "#7a5a3e", "wood_grain": "#7a5a3e",
    "court": "#8e6c4c", "metal": "#5a7ab8", "fabric": "#94485f", "concrete": "#3a4a7a", "brick": "#8a4a46",
}


def sheet(images):
    # cada célula: 2x2 da textura (mostra que não tem emenda) já tingida com a cor da cena
    cell = 300
    names = list(images)
    cols = 5
    rows = (len(names) + cols - 1) // cols
    sh = Image.new("RGB", (cols * (cell + 8) + 8, rows * (cell + 30) + 8), (5, 7, 15))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sh)
    for i, n in enumerate(names):
        a = np.asarray(images[n]).astype(float) / 255.0
        tint = np.array([int(PREVIEW_TINT[n][k:k + 2], 16) / 255.0 for k in (1, 3, 5)])
        t = np.clip(a * 2.0 * tint, 0, 1)
        t = np.tile(t, (2, 2, 1))
        im = Image.fromarray((t * 255).astype(np.uint8)).resize((cell, cell), Image.LANCZOS)
        x = 8 + (i % cols) * (cell + 8)
        y = 8 + (i // cols) * (cell + 30)
        sh.paste(im, (x, y))
        d.text((x, y + cell + 6), n, fill=(255, 200, 61))
    os.makedirs(DOCS, exist_ok=True)
    sh.save(os.path.join(DOCS, "texturas_folha.png"))


def main():
    import sys
    only = sys.argv[1:]
    images = {}
    for name, fn in TEXTURES.items():
        if only and name not in only:
            p = os.path.join(OUT, name + ".png")
            if os.path.exists(p):
                images[name] = Image.open(p).convert("RGB")
            continue
        c = fn()
        images[name] = save(name, c)
        print("ok", name)
    sheet(images)


if __name__ == "__main__":
    main()
