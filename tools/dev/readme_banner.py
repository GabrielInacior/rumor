"""Gera o banner do README (docs/img/banner.png): noite azul, retícula, RUMOR em três cores,
polaroides presas por barbante vermelho. Uso: python tools/dev/readme_banner.py"""
import os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
A = os.path.join(ROOT, "game", "assets")
W, H = 1600, 600
img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
for y in range(H):
    k = y / H
    d.line([(0, y), (W, y)], fill=(int(14 + 10 * (1 - k)), int(22 + 18 * (1 - k)), int(52 + 40 * (1 - k))))
# luz de abajur amarela
glow = Image.new("L", (W, H), 0)
ImageDraw.Draw(glow).ellipse((W * 0.55, -260, W * 1.15, 360), fill=90)
glow = glow.filter(ImageFilter.GaussianBlur(120))
img = Image.composite(Image.new("RGB", (W, H), (255, 200, 61)), img, glow.point(lambda v: int(v * 0.35)))
d = ImageDraw.Draw(img)
for y in range(0, H, 14):
    for x in range(0, W, 14):
        d.ellipse((x, y, x + 2, y + 2), fill=(30, 42, 84))
# chuva
rnd = random.Random(3)
for _ in range(260):
    x, y = rnd.randint(0, W), rnd.randint(0, H)
    d.line([(x, y), (x - 6, y + 26)], fill=(70, 90, 150), width=1)

def font(name, size):
    return ImageFont.truetype(os.path.join(A, "fonts", name), size)

# polaroides presas no lado direito
pins = []
spots = [("caio", 1010, 70, -6), ("rafa", 1290, 110, 5), ("bia", 1120, 330, 4), ("lari", 1390, 360, -5)]
for pid, x, y, rot in spots:
    p = os.path.join(A, "portraits", pid + ".png")
    if not os.path.exists(p):
        continue
    ph = Image.open(p).convert("RGBA").resize((170, 170))
    card = Image.new("RGBA", (200, 236), (246, 241, 228, 255))
    card.paste(ph, (15, 15), ph)
    cd = ImageDraw.Draw(card)
    cd.text((100, 212), pid.upper(), font=font("PermanentMarker-Regular.ttf", 24), fill=(27, 33, 64), anchor="mm")
    sh = Image.new("RGBA", card.size, (0, 0, 0, 120))
    r = card.rotate(rot, expand=True, resample=Image.BICUBIC)
    rs = sh.rotate(rot, expand=True).filter(ImageFilter.GaussianBlur(8))
    img.paste(rs, (x + 8, y + 12), rs)
    img.paste(r, (x, y), r)
    pins.append((x + r.width // 2, y + 18))
d = ImageDraw.Draw(img)
for a, b in [(0, 1), (0, 2), (1, 3), (2, 3)]:
    d.line([pins[a], pins[b]], fill=(0, 0, 0), width=7)
    d.line([pins[a], pins[b]], fill=(226, 56, 79), width=4)
for p in pins:
    d.ellipse((p[0] - 10, p[1] - 10, p[0] + 10, p[1] + 10), fill=(255, 200, 61), outline=(27, 33, 64), width=2)
# RUMOR em três cores deslocadas (como o ícone)
f = font("BebasNeue-Regular.ttf", 290)
for off, col in [((-10, -6), (90, 170, 220)), ((10, 8), (240, 80, 160)), ((0, 0), (255, 200, 61))]:
    d.text((90 + off[0], 70 + off[1]), "RUMOR", font=f, fill=col)
d.text((100, 392), "Nada começa como parece.", font=font("SpecialElite-Regular.ttf", 46), fill=(232, 236, 248))
d.text((100, 470), "JOGO DE DETETIVE MULTIPLAYER PARA A SALA DE AULA", font=font("BebasNeue-Regular.ttf", 40), fill=(255, 111, 174))
img.save(os.path.join(ROOT, "docs", "img", "banner.png"), optimize=True)
print("ok")
