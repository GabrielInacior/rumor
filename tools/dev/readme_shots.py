"""Imagens do README a partir das gravações do trailer (celulares com moldura, fundo noir).
Uso: python tools/dev/readme_shots.py <pasta_clips>"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CL = sys.argv[1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
A = os.path.join(ROOT, "game", "assets")
OUT = os.path.join(ROOT, "docs", "img")
TMP = tempfile.mkdtemp()


def frame(clip, t):
    t0 = float(open(os.path.join(CL, clip + ".t0")).read()) / 30
    p = os.path.join(TMP, f"{clip}_{t}.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t0 + t:.2f}", "-i", os.path.join(CL, clip + ".avi"), "-frames:v", "1", p], check=True)
    return Image.open(p).convert("RGB")


def font(n, s):
    return ImageFont.truetype(os.path.join(A, "fonts", n), s)


def phone(img, w):
    h = int(w * img.height / img.width)
    sc = img.resize((w, h), Image.LANCZOS)
    pad = int(w * 0.035)
    body = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), int(w * 0.11), fill=(10, 12, 22, 255), outline=(60, 70, 110, 255), width=3)
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), int(w * 0.08), fill=255)
    body.paste(sc, (pad, pad), m)
    return body


def backdrop(W, H):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        k = y / H
        d.line([(0, y), (W, y)], fill=(int(12 + 12 * (1 - k)), int(18 + 20 * (1 - k)), int(44 + 46 * (1 - k))))
    for y in range(0, H, 14):
        for x in range(0, W, 14):
            d.ellipse((x, y, x + 2, y + 2), fill=(26, 38, 78))
    return img


def strip(name, shots, labels, title=None, pw=360):
    gap = 40
    ph = [phone(s, pw) for s in shots]
    W = len(ph) * ph[0].width + (len(ph) + 1) * gap
    top = 110 if title else 40
    H = ph[0].height + top + 110
    img = backdrop(W, H).convert("RGBA")
    d = ImageDraw.Draw(img)
    if title:
        d.text((W // 2, 58), title, font=font("BebasNeue-Regular.ttf", 64), fill=(255, 200, 61), anchor="mm")
    for i, p in enumerate(ph):
        x = gap + i * (p.width + gap)
        shadow = Image.new("RGBA", (p.width + 60, p.height + 60), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle((30, 40, p.width + 30, p.height + 40), 40, fill=(0, 0, 0, 150))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)), (x - 30, top - 30))
        img.alpha_composite(p, (x, top))
        d.text((x + p.width // 2, top + p.height + 52), labels[i], font=font("SpecialElite-Regular.ttf", 34), fill=(232, 236, 248), anchor="mm")
    img.convert("RGB").save(os.path.join(OUT, name + ".png"), optimize=True)
    print(name, img.size)


strip("telas", [frame("explore", 1.4), frame("talk", 4.8), frame("board", 16.8), frame("victory", 2.0)],
      ["explore em 3D", "interrogue", "ligue os fios", "compartilhe"])
strip("expressoes", [frame("faces_jorge", 0.8), frame("faces_jorge", 2.9), frame("faces_jorge", 4.8), frame("faces_jorge", 6.6), frame("faces_rafa", 4.6)],
      ["desconfiado", "surpreso", "triste", "feliz", "bravo"], "CADA FALA, UMA REAÇÃO", pw=300)
strip("professor", [frame("host", 1.0), frame("host", 4.2), frame("clues", 1.6), frame("duo", 3.5)],
      ["professor ao vivo", "equipes", "pistas com imagem", "acareação"])
