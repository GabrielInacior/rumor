"""Pós-processo de 'pintura de quadrinho' para os renders do Blender (esboço de direção de arte).

1. Kuwahara (média do quadrante de menor variância): achata a imagem em manchas com borda
   preservada, a cara de tinta/guache que o render limpo não tem.
2. Retícula: pontos azul-noite nas sombras, maiores quanto mais escuro (Aranhaverso).
3. Desalinhamento de impressão: um fantasma rosa/ciano deslocado nas bordas fortes.
4. Grão de papel e vinheta.

Uso: python spike_post.py entrada.png saida.png ["TEXTO DA CAIXA DE NARRAÇÃO"]
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def box_mean(a, r):
    # média em janela (2r+1)² via imagem integral, por canal
    k = 2 * r + 1
    pad = np.pad(a, ((r + 1, r), (r + 1, r), (0, 0)) if a.ndim == 3 else ((r + 1, r), (r + 1, r)), mode="edge")
    c = pad.cumsum(0).cumsum(1)
    s = c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]
    return s / (k * k)


def kuwahara(img, r=4):
    a = img.astype(np.float64)
    lum = a @ np.array([0.299, 0.587, 0.114])
    m = box_mean(a, r // 2 if r > 1 else 1)
    ml = box_mean(lum, r // 2 if r > 1 else 1)
    vl = box_mean(lum ** 2, r // 2 if r > 1 else 1) - ml ** 2
    h = r // 2 + 0
    H, W = lum.shape
    best = np.full((H, W), np.inf)
    out = np.zeros_like(a)
    for dy in (-h, h):
        for dx in (-h, h):
            v = np.roll(np.roll(vl, dy, 0), dx, 1)
            mm = np.roll(np.roll(m, dy, 0), dx, 1)
            sel = v < best
            best[sel] = v[sel]
            out[sel] = mm[sel]
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    caption = sys.argv[3] if len(sys.argv) > 3 else None
    im = np.asarray(Image.open(src).convert("RGB")).astype(np.float64)
    H, W, _ = im.shape

    pt = kuwahara(im, 6)
    pt = kuwahara(pt, 4)

    # retícula nas sombras
    lum = (pt @ np.array([0.299, 0.587, 0.114])) / 255.0
    cell = 7
    yy, xx = np.mgrid[0:H, 0:W]
    # grade girada 45° como na impressão
    u = (xx + yy) / (cell * 1.414)
    v = (xx - yy) / (cell * 1.414)
    du = (u - np.round(u))
    dv = (v - np.round(v))
    dist = np.sqrt(du ** 2 + dv ** 2)
    dark = np.clip((0.42 - lum) / 0.42, 0, 1)
    dots = dist < (dark ** 0.8) * 0.48
    ink = np.array([8, 14, 40], dtype=np.float64)
    pt[dots] = pt[dots] * 0.35 + ink * 0.65

    # realce das luzes amarelas com retícula amarela fina ao redor (brilho de quadrinho)
    yel = (pt[..., 0] > 170) & (pt[..., 1] > 130) & (pt[..., 2] < 140)
    ym = Image.fromarray((yel * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(8))
    yg = np.asarray(ym).astype(np.float64) / 255.0
    ydots = (dist < yg * 0.35) & ~yel
    pt[ydots] = pt[ydots] * 0.4 + np.array([255, 200, 61]) * 0.6

    # desalinhamento: fantasma rosa nas bordas fortes, deslocado
    e = Image.fromarray(np.clip(pt, 0, 255).astype(np.uint8)).convert("L").filter(ImageFilter.FIND_EDGES)
    ea = np.asarray(e).astype(np.float64) / 255.0
    ea = np.roll(np.roll(ea, 3, 0), 4, 1)
    ea = np.clip((ea - 0.18) * 2.2, 0, 1)[..., None]
    pt = pt * (1 - ea * 0.5) + np.array([255, 79, 163]) * ea * 0.5

    # grão de papel + vinheta
    rng = np.random.default_rng(3)
    pt += rng.normal(0, 6, (H, W, 1))
    cy, cx = H / 2, W / 2
    r = np.sqrt(((yy - cy) / cy) ** 2 + ((xx - cx) / cx) ** 2)
    pt *= (1 - np.clip(r - 0.7, 0, 1) * 0.55)[..., None]

    out = Image.fromarray(np.clip(pt, 0, 255).astype(np.uint8))
    if caption:
        d = ImageDraw.Draw(out)
        try:
            f = ImageFont.truetype("C:/Windows/Fonts/courbd.ttf", 34)
        except OSError:
            f = ImageFont.load_default()
        tw = d.textlength(caption, font=f)
        x0, y0 = 40, 36
        d.rectangle([x0 + 6, y0 + 6, x0 + tw + 46, y0 + 70], fill=(6, 10, 30))
        d.rectangle([x0, y0, x0 + tw + 40, y0 + 64], fill=(255, 200, 61), outline=(6, 10, 30), width=4)
        d.text((x0 + 20, y0 + 14), caption, font=f, fill=(6, 10, 30))
    out.save(dst)
    print("OK", dst)


if __name__ == "__main__":
    main()
