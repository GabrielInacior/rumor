"""Montagem do trailer vertical do RUMOR (1080x1920, formato de celular para LinkedIn/Reels).

Uso: python tools/dev/build_trailer.py <pasta_clips> <saida.mp4>
  <pasta_clips> tem <nome>.avi + <nome>.t0 (gravados por tools/dev/record_trailer.sh).

Música "Bloodline": ~149,5 BPM. Introdução calma até 13,0 s (com batidas de preparação em
11,6 a 12,4 s); a explosão em 13,0 s abre o logo. Toda seção dura um número inteiro de batidas.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CL = sys.argv[1]
OUT = sys.argv[2]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
A = os.path.join(ROOT, "game", "assets")
MUSIC = os.path.join(A, "audio", "musica", "bloodline.mp3")
B = 60.0 / 149.5
DROP = 13.0
W, H, FPS = 1080, 1920, 30
XF = 0.12
TMP = os.path.join(CL, "_sec")
TXT = os.path.join(CL, "_txt")
os.makedirs(TMP, exist_ok=True)
os.makedirs(TXT, exist_ok=True)
FF = ["ffmpeg", "-v", "error", "-y"]
ENC = ["-c:v", "libx264", "-crf", "16", "-preset", "fast", "-pix_fmt", "yuv420p", "-r", str(FPS)]
GRADE = "eq=contrast=1.06:saturation=1.12,vignette=PI/6"

YEL = (255, 200, 61)
PINK = (255, 111, 174)
CYAN = (90, 170, 220)
PAPER = (232, 236, 248)


def font(name, size):
    return ImageFont.truetype(os.path.join(A, "fonts", name), size)


def run(args):
    r = subprocess.run(FF + args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-2000:])
        raise SystemExit("ffmpeg falhou")


def src(name):
    t0 = float(open(os.path.join(CL, name + ".t0")).read().strip() or 0) / FPS
    return os.path.join(CL, name + ".avi"), t0


def trio(d, xy, text, f, anchor="mm", main=YEL, shift=6):
    x, y = xy
    d.text((x - shift, y - shift), text, font=f, fill=CYAN, anchor=anchor)
    d.text((x + shift, y + shift), text, font=f, fill=PINK, anchor=anchor)
    d.text((x, y), text, font=f, fill=main, anchor=anchor)


def caption(name, big, small="", top=True):
    """Faixa escura em degradê + título grande em três cores + linha datilografada."""
    p = os.path.join(TXT, name + ".png")
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    band = 560
    g = Image.new("RGBA", (W, band))
    gp = g.load()
    for y in range(band):
        k = (1.0 - y / (band - 1)) if top else (y / (band - 1))
        a = int(250 * min(1.0, (k ** 0.9) * 1.35))
        for x in range(W):
            gp[x, y] = (6, 10, 28, a)
    img.alpha_composite(g, (0, 0 if top else H - band))
    d = ImageDraw.Draw(img)
    y0 = 190 if top else H - 330
    fs = 150 if len(big) <= 14 else (124 if len(big) <= 18 else 104)
    trio(d, (W // 2, y0), big, font("BebasNeue-Regular.ttf", fs))
    if small:
        d.text((W // 2, y0 + 118), small, font=font("SpecialElite-Regular.ttf", 44), fill=PAPER, anchor="mm")
    img.save(p)
    return p


def title_card(name, lines, sub=None):
    """Texto sobre fundo transparente (introdução)."""
    p = os.path.join(TXT, name + ".png")
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hh = 120 * len(lines) + (140 if sub else 40)
    ImageDraw.Draw(sh).rounded_rectangle((-60, H // 2 - hh // 2 - 140, W + 60, H // 2 + hh // 2), 80, fill=(4, 8, 24, 215))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(60)))
    d = ImageDraw.Draw(img)
    f = font("SpecialElite-Regular.ttf", 64)
    y = H // 2 - 60 * len(lines)
    for ln in lines:
        d.text((W // 2 + 3, y + 3), ln, font=f, fill=(0, 0, 0, 200), anchor="mm")
        d.text((W // 2, y), ln, font=f, fill=PAPER, anchor="mm")
        y += 96
    if sub:
        d.text((W // 2, y + 30), sub, font=font("BebasNeue-Regular.ttf", 70), fill=YEL, anchor="mm")
    img.save(p)
    return p


def logo_card(name, tagline=True, extra=None):
    p = os.path.join(TXT, name + ".png")
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.ellipse((40, H // 2 - 420, W - 40, H // 2 + 300), fill=(4, 8, 24, 210))
    sh = sh.filter(ImageFilter.GaussianBlur(90))
    img.alpha_composite(sh)
    d = ImageDraw.Draw(img)
    trio(d, (W // 2, H // 2 - 150), "RUMOR", font("BebasNeue-Regular.ttf", 330), shift=12)
    if tagline:
        d.text((W // 2, H // 2 + 60), "Nada começa como parece.", font=font("SpecialElite-Regular.ttf", 58), fill=PAPER, anchor="mm")
    if extra:
        y = H // 2 + 190
        for ln, col, f in extra:
            d.text((W // 2, y), ln, font=f, fill=col, anchor="mm")
            y += 92
    img.save(p)
    return p


def section(out, parts, overlay=None, ov_in=0.15, fade_in=0.0, fade_out=0.0, punch=False):
    """parts: [(clipe, início_útil_s, segundos[, velocidade])]. Corte seco entre as partes."""
    ins, flt = [], []
    n = len(parts)
    total = sum(p[2] for p in parts)
    for i, p in enumerate(parts):
        name, start, dur = p[0], p[1], p[2]
        speed = p[3] if len(p) > 3 else 1.0
        path, t0 = src(name)
        d = dur + (XF if i == n - 1 else 0.0)
        ins += ["-ss", f"{t0 + start:.3f}", "-t", f"{d * speed:.3f}", "-i", path]
        ch = f"[{i}:v]scale={W}:{H}:flags=lanczos,setsar=1"
        if speed != 1.0:
            ch += f",setpts=PTS/{speed}"
        ch += f",fps={FPS},format=yuv420p[v{i}]"
        flt.append(ch)
    want = total + XF
    flt.append("".join(f"[v{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0,tpad=stop_mode=clone:stop_duration=4,"
               f"trim=duration={want:.4f},setpts=PTS-STARTPTS[base]")
    last = "base"
    if punch:
        # leve aproximação contínua (dá vida a uma tela parada)
        flt.append(f"[{last}]scale=iw*1.08:ih*1.08,zoompan=z='1+0.06*on/({want * FPS:.0f})':d=1:s={W}x{H}:fps={FPS}:"
                   f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'[pz]")
        last = "pz"
    if overlay:
        ins += ["-loop", "1", "-i", overlay]
        k = n
        out_t = max(ov_in + 0.5, total - 0.3)
        flt.append(f"[{k}:v]format=rgba,fade=t=in:st={ov_in}:d=0.25:alpha=1,fade=t=out:st={out_t:.2f}:d=0.25:alpha=1[ov]")
        flt.append(f"[{last}][ov]overlay=0:0:shortest=1[ovl]")
        last = "ovl"
    tail = ""
    if fade_in:
        tail += f",fade=t=in:st=0:d={fade_in}"
    if fade_out:
        tail += f",fade=t=out:st={total - fade_out:.2f}:d={fade_out}"
    flt.append(f"[{last}]{GRADE}{tail}[out]")
    run(ins + ["-filter_complex", ";".join(flt), "-map", "[out]", "-t", f"{want:.4f}"] + ENC + [out])
    return out


def still(out, png_bg_clip, overlay, dur, fade_in=0.0, fade_out=0.0, blur=True):
    """Fundo: um clipe desfocado e escurecido; por cima, o cartão (logo/fim)."""
    path, t0 = src(png_bg_clip[0])
    want = dur + XF
    flt = (f"[0:v]scale={W}:{H},setsar=1,fps={FPS}" + (",boxblur=18:3,eq=brightness=-0.22" if blur else "") +
           f",tpad=stop_mode=clone:stop_duration=6,trim=duration={want:.4f},setpts=PTS-STARTPTS[bg];"
           f"[1:v]format=rgba,fade=t=in:st=0.05:d=0.35:alpha=1[ov];[bg][ov]overlay=0:0:shortest=1[x];"
           f"[x]{GRADE}" + (f",fade=t=in:st=0:d={fade_in}" if fade_in else "") +
           (f",fade=t=out:st={dur - fade_out:.2f}:d={fade_out}" if fade_out else "") + "[out]")
    run(["-ss", f"{t0 + png_bg_clip[1]:.3f}", "-t", f"{want:.3f}", "-i", path, "-loop", "1", "-i", overlay,
         "-filter_complex", flt, "-map", "[out]", "-t", f"{want:.4f}"] + ENC + [out])
    return out


def main():
    S = lambda n: os.path.join(TMP, n + ".mp4")
    bar = 4 * B
    plan = []   # (duração, arquivo)

    def add(d, path):
        plan.append((d, path))

    # ── INTRODUÇÃO (calma, até 11,6 s) ─────────────────────────────────────
    t1 = title_card("i1", ["Na escola,", "um boato corre mais", "rápido que a verdade."])
    t2 = title_card("i2", ["Oito pessoas.", "Oito versões."], "ALGUÉM ESTÁ MENTINDO")
    add(5.6, section(S("00_fachada"), [("room_fachada", 0.0, 5.6)], t1, ov_in=0.9, fade_in=1.2))
    add(3.6, section(S("01_corredor"), [("room_corredor", 0.6, 3.6)], t2, ov_in=0.3))
    add(2.4, section(S("02_rosto"), [("faces_rafa", 1.5, 2.4)]))
    # batidas de preparação 11,6 / 11,8 / 12,0 / 12,2 / 12,4: cortes rápidos
    add(0.4, section(S("03a"), [("board", 2.0, 0.4)]))
    add(0.4, section(S("03b"), [("faces_bia", 3.6, 0.4)]))
    add(0.6, section(S("03c"), [("board", 3.0, 0.6)]))
    # ── EXPLOSÃO 13,0 s: logo ──────────────────────────────────────────────
    add(2 * bar, still(S("04_logo"), ("board", 12.0), logo_card("logo"), 2 * bar))
    add(4 * bar, section(S("05_salas"), [("room_biblioteca", 0.4, bar), ("room_teatro", 0.4, bar),
                                         ("room_laboratorio", 0.4, bar), ("room_quadra", 0.4, bar)],
                         caption("c_explore", "EXPLORE A ESCOLA", "doze cômodos em 3D")))
    add(3 * bar, section(S("06_explorar"), [("explore", 0.2, 3 * bar)], caption("c_brilho", "TOQUE NO QUE BRILHA", "cada objeto pode ser uma pista")))
    add(4 * bar, section(S("07_interrogar"), [("talk", 1.0, 4 * bar)], caption("c_talk", "INTERROGUE", "e mostre a prova na hora certa")))
    add(3 * bar, section(S("08_rostos"), [("faces_jorge", 0.2, 2 * B), ("faces_jorge", 2.2, 2 * B), ("faces_bia", 2.2, 2 * B),
                                          ("faces_bia", 4.1, 2 * B), ("faces_rafa", 4.1, 2 * B), ("faces_rafa", 6.0, 2 * B)],
                         caption("c_faces", "CADA FALA, UMA REAÇÃO", "eles mentem, travam e se entregam")))
    add(3 * bar, section(S("09_duo"), [("duo", 1.0, 3 * bar)], caption("c_duo", "ACAREAÇÃO", "duas versões, frente a frente")))
    add(2 * bar, section(S("10_pistas"), [("clues", 0.6, 2 * bar, 1.3)], caption("c_pistas", "PISTAS DE VERDADE", "câmera, Pix, bilhete recortado")))
    add(6 * bar, section(S("11_quadro"), [("board", 0.6, 6 * bar, 1.12)], caption("c_quadro", "LIGUE OS FIOS", "e monte a história com a equipe")))
    add(2 * bar, section(S("12_prof"), [("host", 0.2, 2 * bar)], caption("c_prof", "O PROFESSOR VÊ TUDO", "ao vivo, do celular ou do telão")))
    add(2 * bar, section(S("13_voto"), [("vote", 0.0, 2 * bar)], caption("c_voto", "A EQUIPE DECIDE", "todo mundo vota a entrega")))
    add(2 * bar, section(S("14_vitoria"), [("victory", 0.4, 2 * bar)], caption("c_vit", "CASO RESOLVIDO", "e a história vira story", top=True)))
    fim = logo_card("fim", True, [("12 CASOS · EM EQUIPE OU SOLO", YEL, font("BebasNeue-Regular.ttf", 76)),
                                  ("no celular, direto no navegador", PAPER, font("SpecialElite-Regular.ttf", 46)),
                                  ("rumor.inaciodev.online", PINK, font("BebasNeue-Regular.ttf", 84))])
    add(4 * bar, still(S("15_fim"), ("room_fachada", 0.5), fim, 4 * bar, fade_out=1.6))

    ins, flt = [], []
    for _, p in plan:
        ins += ["-i", p]
    cur = "0:v"
    start = 0.0
    for i in range(1, len(plan)):
        start += plan[i - 1][0]
        flt.append(f"[{cur}][{i}:v]xfade=transition=fade:duration={XF}:offset={start - XF / 2:.4f}[x{i}]")
        cur = f"x{i}"
    total = sum(d for d, _ in plan)
    ins += ["-i", MUSIC]
    ai = len(plan)
    flt.append(f"[{ai}:a]atrim=0:{total:.2f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.8,"
               f"afade=t=out:st={total - 2.6:.2f}:d=2.6,volume=0.95[a]")
    run(ins + ["-filter_complex", ";".join(flt), "-map", f"[{cur}]", "-map", "[a]", "-c:v", "libx264", "-crf", "18",
               "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart",
               "-t", f"{total:.2f}", OUT])
    pre = sum(d for d, _ in plan[:6])
    print("OK", OUT, f"{total:.1f}s", f"logo entra em {pre:.2f}s")


if __name__ == "__main__":
    main()
