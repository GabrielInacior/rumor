"""Sons procedurais do RUMOR: tudo sintetizado aqui (numpy + wave), nada gravado nem baixado.

Gera WAV mono 22050 Hz 16-bit em game/assets/audio/sfx/ e uma folha de contato
(forma de onda + espectrograma de cada som) em docs/arte_exploracao/sfx_folha.png,
para conferir envelope e ausência de clipping "com os olhos". Nunca toca som.

    python tools/audio/gen_sfx.py

Regras: envelope em tudo (fade de entrada e saída, sem clique), pico normalizado a -3 dBFS
nos efeitos e mais baixo nos ambientes. Os loops são construídos de forma circular (ruído
moldado na FFT, eventos somados com módulo do comprimento, frequências com número inteiro de
ciclos no loop), então o fim emenda no começo sem costura.
"""
import struct
import wave
import zlib
from pathlib import Path

import numpy as np

SR = 22050
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "game" / "assets" / "audio" / "sfx"
SHEET = ROOT / "docs" / "arte_exploracao" / "sfx_folha.png"
PEAK_SFX_DB = -3.0
PEAK_AMB_DB = {"ambience_rain_loop": -12.0, "ambience_room_tone_loop": -15.0}

rng = np.random.default_rng(1947)


# ------------------------------------------------------------------ utilitários
def T(dur):
    return np.arange(int(dur * SR)) / SR


def n_(dur):
    return int(dur * SR)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def noise(dur, seed=None):
    r = rng if seed is None else np.random.default_rng(seed)
    return r.standard_normal(n_(dur))


def fft_shape(x, lo=None, hi=None, order=2, tilt=0.0, circular=False):
    """Filtro passa-faixa suave no domínio da frequência (Butterworth de magnitude).
    tilt < 0 escurece (tilt=-0.5 ~ ruído rosa). circular=True mantém periodicidade (loops)."""
    n = len(x)
    pad = 0 if circular else min(n, n_(0.25))
    xp = np.concatenate([x, np.zeros(pad)])
    X = np.fft.rfft(xp)
    f = np.fft.rfftfreq(len(xp), 1 / SR)
    f[0] = 1e-3
    g = np.ones_like(f)
    if lo:
        g *= 1 / np.sqrt(1 + (lo / f) ** (2 * order))
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    if tilt:
        g *= (np.maximum(f, 20) / 1000.0) ** tilt
    g[0] = 0
    y = np.fft.irfft(X * g, len(xp))
    return y[:n] if circular else y[:n]


def biquad_bp(x, f0, q):
    """Passa-faixa ressonante (RBJ) em laço; serve para 'corpo' de madeira/cortiça."""
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b0, b2 = al, -al
    a0, a1, a2 = 1 + al, -2 * np.cos(w0), 1 - al
    b0, b2, a1, a2 = b0 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b0 * xi + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def env_ad(dur, a=0.005, tau=0.1, power=1.0):
    """Ataque linear curto + decaimento exponencial."""
    t = T(dur)
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / tau)
    return e ** power


def fades(x, fin=0.003, fout=0.012):
    x = x.copy()
    a, b = n_(fin), n_(fout)
    if a:
        x[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if b:
        x[-b:] *= np.cos(np.linspace(0, np.pi / 2, b)) ** 2
    return x


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    if j > i:
        dst[i:j] += src[: j - i]
    return dst


def chirp(f0, f1, dur, curve="exp"):
    t = T(dur)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * t / dur
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def karplus(freq, dur, damp=0.996, bright=0.5, seed=0):
    """Corda dedilhada (Karplus-Strong). bright baixo = som mais redondo (contrabaixo)."""
    total = n_(dur)
    N = max(2, int(round(SR / freq)))
    r = np.random.default_rng(seed)
    burst = r.uniform(-1, 1, N)
    for _ in range(int((1 - bright) * 6)):           # pré-filtra o ataque (menos estridente)
        burst = 0.5 * (burst + np.roll(burst, 1))
    y = np.zeros(total)
    y[:N] = burst
    for i in range(N, total):
        y[i] = damp * 0.5 * (y[i - N] + y[i - N - 1 if i - N - 1 >= 0 else 0])
    return y


def reverb(x, tail=1.2, wet=0.25, predelay=0.012, seed=3, bright=4500):
    """Reverb por convolução com resposta sintética (ruído decaindo e escurecendo)."""
    r = np.random.default_rng(seed)
    t = T(tail)
    ir = r.standard_normal(len(t)) * np.exp(-t / (tail / 6.9))
    dark = fft_shape(ir, hi=bright * 0.35, order=1)
    k = np.clip(t / tail, 0, 1)
    ir = ir * (1 - k) + dark * k * 1.8
    ir = np.concatenate([np.zeros(n_(predelay)), ir])
    ir /= np.sqrt(np.sum(ir ** 2))
    n = len(x) + len(ir)
    y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    dry = np.concatenate([x, np.zeros(len(ir))])
    return dry * (1 - wet) + y * wet * 2.2


def trim_tail(x, thresh_db=-48):
    """Corta silêncio no fim (arquivo pequeno), mantendo fade."""
    a = np.abs(x) / (np.max(np.abs(x)) + 1e-12)
    idx = np.where(a > 10 ** (thresh_db / 20))[0]
    end = min(len(x), (idx[-1] if len(idx) else len(x)) + n_(0.02))
    return x[:end]


# ------------------------------------------------------------------ instrumentos
def vibes(freq, dur=1.6, amp=1.0, trem=5.5):
    t = T(dur)
    parts = [(1.0, 1.0, 1.5), (3.93, 0.22, 0.45), (9.1, 0.06, 0.15)]
    y = sum(a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t / d) for r, a, d in parts)
    y *= 1 - 0.22 * (0.5 - 0.5 * np.cos(2 * np.pi * trem * t))
    y += 0.15 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / 0.03)   # mallet
    return fades(y * amp * np.minimum(t / 0.002, 1))


def piano(freq, dur=1.8, amp=1.0, seed=0):
    t = T(dur)
    y = np.zeros_like(t)
    B = 0.0004
    for k in range(1, 10):
        fk = freq * k * np.sqrt(1 + B * k * k)
        if fk > 9500:
            break
        y += (1 / k ** 1.3) * np.sin(2 * np.pi * fk * t + k) * np.exp(-t / (1.4 / k ** 0.7))
    ham = fft_shape(noise(dur, seed), lo=800, hi=4000) * np.exp(-t / 0.006) * 0.15
    return fades((y + ham) * amp * np.minimum(t / 0.003, 1))


def epiano(freq, dur=1.5, amp=1.0):
    """Piano elétrico (FM leve), o 'acorde de jazz'."""
    t = T(dur)
    idx = 0.4 + 1.6 * np.exp(-t / 0.15)
    y = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * t))
    y += 0.12 * np.sin(2 * np.pi * freq * 14 * t) * np.exp(-t / 0.02)       # tine
    y *= np.exp(-t / 0.9) * np.minimum(t / 0.004, 1)
    return fades(y * amp)


def brass(freq, dur, amp=1.0, attack=0.04, bright_peak=10.0):
    """Metal (aditivo com brilho variando), sem aliasing."""
    t = T(dur)
    env = np.minimum(t / attack, 1) * np.exp(-np.maximum(t - attack, 0) / (dur * 0.9))
    env = fades(env, 0.002, min(0.08, dur * 0.3))
    br = 1.5 + bright_peak * np.exp(-t / 0.18) * np.minimum(t / attack, 1)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(t / 0.3, 1)
    ph = 2 * np.pi * freq * np.cumsum(vib) / SR
    y = np.zeros_like(t)
    k = 1
    while k * freq < 8000:
        y += np.exp(-k / br) / k ** 0.6 * np.sin(k * ph)
        k += 1
    return y * env * amp


def bass_pluck(freq, dur, amp=1.0, seed=0):
    y = karplus(freq, dur, damp=0.9985, bright=0.15, seed=seed)
    y = fft_shape(y, lo=35, hi=900)
    t = T(dur)
    y += 0.5 * np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.5) * np.minimum(t / 0.01, 1)
    return fades(y * amp, 0.004, 0.06)


def bell(freq, dur=0.8, amp=1.0):
    t = T(dur)
    y = (np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.35)
         + 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.12)
         + 0.15 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.05))
    return fades(y * amp * np.minimum(t / 0.0015, 1))


def tick(freq, dur=0.04, tau=0.006, seed=0):
    t = T(dur)
    y = np.sin(2 * np.pi * freq * t) * np.exp(-t / tau)
    y += 0.6 * fft_shape(noise(dur, seed), lo=2500, hi=7000) * np.exp(-t / (tau * 0.4))
    return fades(y, 0.0005, 0.005)


# ------------------------------------------------------------------ os sons
def ui_tap():
    d = 0.07
    t = T(d)
    f = 1050 * (0.82 + 0.18 * np.exp(-t / 0.01))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.018)
    y += 0.25 * np.sin(2 * np.pi * 2100 * t) * np.exp(-t / 0.006)
    y += 0.2 * fft_shape(noise(d, 11), lo=1500, hi=5000) * np.exp(-t / 0.002)
    return fades(y, 0.001)


def ui_back():
    out = np.zeros(n_(0.14))
    for at, f, a in ((0.0, 880, 0.8), (0.045, 620, 1.0)):
        d = 0.08
        t = T(d)
        y = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.02) * a
        y += 0.2 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t / 0.006) * a
        place(out, fades(y, 0.001), at)
    return fades(out)


def card_pin():
    d = 0.34
    t = T(d)
    # ponta furando: estalo agudo bem curto
    y = 0.5 * fft_shape(noise(d, 21), lo=2500, hi=7500) * np.exp(-t / 0.0025)
    # thunk: corpo grave que desce
    f = 190 * (0.55 + 0.45 * np.exp(-t / 0.02))
    y += 1.0 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.035)
    # cortiça ressoando (madeira oca + chapa)
    exc = noise(d, 22) * np.exp(-t / 0.004)
    y += 0.9 * biquad_bp(exc, 520, 18) + 0.5 * biquad_bp(exc, 1180, 25) + 0.25 * biquad_bp(exc, 2350, 30)
    return fades(y, 0.0008, 0.03)


def card_pick():
    d = 0.2
    t = T(d)
    nz = noise(d, 31)
    # passa-faixa subindo (papel saindo da mesa) feito por blocos
    out = np.zeros_like(t)
    for i, (lo, hi) in enumerate(((600, 1800), (1000, 3000), (1600, 4800), (2400, 7000))):
        seg = fft_shape(nz, lo=lo, hi=hi)
        w = np.exp(-((t - 0.03 - i * 0.025) / 0.022) ** 2)
        out += seg * w
    out += 0.4 * tick(2600, d, 0.004, 32)                  # bordinha do cartão batendo
    return fades(out * 0.9, 0.004, 0.03)


def card_drop():
    d = 0.24
    t = T(d)
    slap = fft_shape(noise(d, 41), lo=300, hi=3500) * env_ad(d, 0.002, 0.02)
    thud = np.sin(2 * np.pi * np.cumsum(120 * (0.7 + 0.3 * np.exp(-t / 0.02))) / SR) * env_ad(d, 0.002, 0.05)
    flutter = fft_shape(noise(d, 42), lo=2000, hi=6000) * env_ad(d, 0.01, 0.03) * 0.3
    return fades(slap * 0.9 + thud * 0.8 + flutter, 0.001, 0.03)


def string_stretch():
    d = 0.42
    t = T(d)
    f = 180 * (2.0 ** (t / d * 0.75))                     # glissando de ~9 semitons
    vib = 1 + 0.006 * np.sin(2 * np.pi * 17 * t)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    y = sum(np.sin(k * ph) / k ** 1.1 for k in range(1, 9))
    y *= np.sin(np.pi * np.clip(t / d, 0, 1)) ** 1.5         # incha e some
    creak = fft_shape(noise(d, 51), lo=900, hi=2600) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t)) ** 4
    creak *= np.sin(np.pi * t / d) * 0.35
    return fades(0.7 * y + creak, 0.01, 0.03)


def string_connect():
    d = 0.75
    t = T(d)
    snap = fft_shape(noise(d, 61), lo=2000, hi=9000) * np.exp(-t / 0.003)
    y = 0.9 * snap
    y += 0.9 * karplus(330, d, damp=0.9965, bright=0.65, seed=62)
    y += 0.35 * karplus(495, d, damp=0.995, bright=0.6, seed=63)
    y += 0.5 * np.sin(2 * np.pi * np.cumsum(140 * (0.6 + 0.4 * np.exp(-t / 0.015))) / SR) * np.exp(-t / 0.03)
    return fades(y, 0.0005, 0.08)


def string_cut():
    d = 0.42
    out = np.zeros(n_(d))
    for at, s in ((0.0, 71), (0.075, 72)):
        dd = 0.06
        t = T(dd)
        exc = noise(dd, s) * np.exp(-t / 0.002)
        y = (0.6 * biquad_bp(exc, 3100, 40) + 0.5 * biquad_bp(exc, 5300, 45) + 0.3 * biquad_bp(exc, 7200, 50))
        y += 0.6 * fft_shape(noise(dd, s + 10), lo=3000, hi=9000) * np.exp(-t / 0.004)
        place(out, fades(y, 0.0005, 0.01), at)
    # fio solto: twang descendo, curto e amortecido
    dd = 0.3
    t = T(dd)
    tw = chirp(260, 150, dd) * np.exp(-t / 0.07) * 0.5
    place(out, fades(tw, 0.002, 0.03), 0.09)
    return fades(out, 0.0005, 0.03)


def paper_flip():
    d = 0.32
    t = T(d)
    nz = noise(d, 81)
    out = np.zeros_like(t)
    bands = ((500, 1500), (900, 2600), (1500, 4200), (2200, 6500), (1200, 3500))
    for i, (lo, hi) in enumerate(bands):
        c = 0.03 + i * 0.05
        out += fft_shape(nz, lo=lo, hi=hi) * np.exp(-((t - c) / 0.035) ** 2)
    flutter = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 23 * t + 3 * np.sin(2 * np.pi * 5 * t)))
    out *= flutter
    out += 0.35 * tick(1800, d, 0.003, 82)                  # dobra do papel no fim
    return fades(out, 0.005, 0.04)


def clue_new():
    d = 2.2
    out = np.zeros(n_(d))
    place(out, piano(midi(36), 2.0, 0.55, 91), 0.0)          # C2 grave de piano
    place(out, piano(midi(48), 2.0, 0.35, 92), 0.0)
    place(out, vibes(midi(63), 1.8, 0.65), 0.0)              # Eb4
    place(out, vibes(midi(67), 1.7, 0.55), 0.16)             # G4
    place(out, vibes(midi(71), 1.7, 0.6), 0.32)              # B4: menor com sétima maior (noir)
    y = reverb(out, tail=1.4, wet=0.32)
    return fades(trim_tail(y), 0.002, 0.15)


def phone_buzz():
    d = 0.9
    t = T(d)
    gate = np.zeros_like(t)
    for a, b in ((0.0, 0.32), (0.46, 0.78)):
        g = np.clip((t - a) / 0.015, 0, 1) * np.clip((b - t) / 0.02, 0, 1)
        gate = np.maximum(gate, g)
    motor = np.tanh(2.5 * np.sin(2 * np.pi * 170 * t))       # quase quadrada, motor
    motor = fft_shape(motor, lo=90, hi=2200)
    rattle = 0.6 + 0.4 * np.sin(2 * np.pi * 34 * t)           # chacoalhar na mesa
    tick_n = fft_shape(noise(d, 101), lo=1500, hi=4000) * (np.sin(2 * np.pi * 170 * t) > 0.95) * 0.3
    return fades((motor * rattle + tick_n) * gate, 0.003, 0.02)


def hotspot_found():
    d = 1.3
    out = np.zeros(n_(d))
    notes = (84, 88, 91, 96, 100)                           # C6 E6 G6 C7 E7
    for i, m in enumerate(notes):
        place(out, bell(midi(m), 0.8, 0.55 - i * 0.05), i * 0.045)
    t = T(d)
    shimmer = fft_shape(noise(d, 111), lo=6000, hi=10000) * np.exp(-t / 0.25) * 0.08 * np.minimum(t / 0.05, 1)
    y = reverb(out + shimmer, tail=1.0, wet=0.35, bright=8000)
    return fades(trim_tail(y), 0.001, 0.1)


def submit_stamp():
    d = 0.5
    out = np.zeros(n_(d))
    tt = T(0.08)
    whoosh = fft_shape(noise(0.08, 121), lo=300, hi=1600) * np.sin(np.pi * tt / 0.08) ** 2 * 0.25
    place(out, whoosh, 0.0)
    dd = 0.4
    t = T(dd)
    thump = np.sin(2 * np.pi * np.cumsum(95 * (0.6 + 0.4 * np.exp(-t / 0.012))) / SR) * np.exp(-t / 0.07)
    slap = fft_shape(noise(dd, 122), lo=200, hi=2500) * np.exp(-t / 0.012)
    wood = biquad_bp(noise(dd, 123) * np.exp(-t / 0.003), 340, 12) * 0.6
    place(out, fades(thump + 0.9 * slap + wood, 0.0008, 0.04), 0.075)
    return fades(out, 0.003, 0.04)


def wrong():
    d = 1.0
    out = np.zeros(n_(d))
    place(out, bass_pluck(midi(43), 0.5, 0.9, 131), 0.0)     # G2
    place(out, bass_pluck(midi(39), 0.8, 1.0, 132), 0.2)     # Eb2: desce, sem castigo
    y = reverb(out, tail=0.8, wet=0.15, bright=2500)
    return fades(trim_tail(y), 0.003, 0.1)


def correct():
    d = 1.6
    out = np.zeros(n_(d))
    chord = (60, 64, 67, 71, 74)                            # Cmaj9 rolado para cima
    for i, m in enumerate(chord):
        place(out, epiano(midi(m), 1.3, 0.42), i * 0.045)
    place(out, bass_pluck(midi(36), 1.2, 0.6, 141), 0.0)
    y = reverb(out, tail=1.1, wet=0.25)
    return fades(trim_tail(y), 0.002, 0.12)


def victory():
    d = 2.6
    out = np.zeros(n_(d))
    # chamada em tercinas: A4 C5 E5 ... e acorde final Fmaj9 sustentado
    lead = ((0.00, 69, 0.14), (0.15, 72, 0.14), (0.30, 76, 0.14), (0.48, 77, 1.8))
    for at, m, du in lead:
        place(out, brass(midi(m), du, 0.5), at)
    for m in (53, 57, 60, 64, 67):                          # F3 A3 C4 E4 G4: Fmaj9
        place(out, brass(midi(m), 1.9, 0.18, attack=0.06, bright_peak=6), 0.48)
    # contrabaixo caminhando: D2 E2 F2
    for at, m in ((0.0, 38), (0.15, 40), (0.30, 41), (0.48, 29)):
        place(out, bass_pluck(midi(m), 0.6 if at < 0.4 else 1.8, 0.7, int(at * 100) + 150), at)
    # prato de vassourinha + brilho de vibrafone no final
    t = T(1.9)
    cym = fft_shape(noise(1.9, 151), lo=5000, hi=10500) * np.exp(-t / 0.5) * 0.18 * np.minimum(t / 0.004, 1)
    place(out, cym, 0.48)
    for i, m in enumerate((81, 84, 88)):
        place(out, vibes(midi(m), 1.5, 0.25), 0.62 + i * 0.07)
    y = reverb(out, tail=1.5, wet=0.28)
    y = y[: n_(d)]
    t = T(d)
    y *= np.where(t > d - 0.5, np.clip((d - t) / 0.5, 0, 1) ** 1.2, 1.0)   # cauda some suave
    return fades(y, 0.002, 0.05)


def timer_tick():
    y = tick(1900, 0.05, 0.005, 161) * 0.9
    y += 0.4 * tick(950, 0.05, 0.004, 162)
    return fades(y, 0.0005, 0.01)


def timer_urgent():
    d = 0.2
    out = np.zeros(n_(d))
    place(out, tick(2500, 0.05, 0.004, 171), 0.0)
    place(out, tick(2500, 0.05, 0.004, 172) * 0.7, 0.07)
    t = T(0.18)
    pulse = np.sin(2 * np.pi * 75 * t) * np.exp(-t / 0.05) * np.minimum(t / 0.004, 1) * 0.9
    place(out, pulse, 0.0)
    return fades(out, 0.0005, 0.02)


def join_ping():
    d = 0.9
    out = np.zeros(n_(d))
    place(out, bell(midi(79), 0.7, 0.6), 0.0)                # G5
    place(out, bell(midi(86), 0.7, 0.7), 0.09)               # D6
    y = reverb(out, tail=0.8, wet=0.25, bright=7000)
    return fades(trim_tail(y), 0.001, 0.08)


def countdown_go():
    d = 0.8
    out = np.zeros(n_(d))
    for m in (55, 59, 62, 67):                              # G maior aberto
        place(out, brass(midi(m), 0.6, 0.3, attack=0.01, bright_peak=14), 0.0)
    t = T(0.25)
    kick = np.sin(2 * np.pi * np.cumsum(55 + 120 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.09)
    place(out, kick * 0.9, 0.0)
    tt = T(0.35)
    sweep = fft_shape(noise(0.35, 181), lo=2000, hi=9000) * (tt / 0.35) ** 2 * np.exp(-tt / 0.2) * 0.25
    place(out, sweep[::-1].copy(), 0.0)
    y = reverb(out, tail=0.7, wet=0.18)
    return fades(trim_tail(y), 0.0015, 0.06)


# ------------------------------------------------------------------ ambientes (loops)
def ambience_rain_loop():
    L = 8.0
    N = n_(L)
    t = np.arange(N) / SR
    base = fft_shape(noise(L, 201), lo=350, hi=7000, tilt=-0.45, circular=True)
    base /= np.std(base)
    # respiração da chuva: LFO com número inteiro de ciclos em 8 s (loop perfeito)
    lfo = 1 + 0.12 * np.sin(2 * np.pi * t * 2 / L) + 0.07 * np.sin(2 * np.pi * t * 5 / L + 1.3)
    y = base * 0.35 * lfo
    # gotas na janela: ticks curtos, somados com módulo do comprimento
    r = np.random.default_rng(202)
    drops = np.zeros(N)
    for _ in range(900):
        at = r.integers(0, N)
        f = r.uniform(1800, 5200)
        tau = r.uniform(0.002, 0.007)
        a = r.lognormal(-1.2, 0.6)
        dd = n_(0.04)
        tt = np.arange(dd) / SR
        g = np.sin(2 * np.pi * f * tt) * np.exp(-tt / tau) * a
        idx = (at + np.arange(dd)) % N
        np.add.at(drops, idx, g)
    # pingos maiores (plip com tom subindo), raros
    for _ in range(28):
        at = r.integers(0, N)
        dd = n_(0.06)
        tt = np.arange(dd) / SR
        f0 = r.uniform(900, 1500)
        f = f0 * (1 + 0.8 * tt / 0.06)
        g = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.012) * r.uniform(0.4, 0.9)
        idx = (at + np.arange(dd)) % N
        np.add.at(drops, idx, g)
    drops = fft_shape(drops, lo=600, hi=8000, circular=True)
    y = y + drops * 0.5
    y = fft_shape(y, lo=120, hi=8500, circular=True)       # vidro abafa um pouco
    return y


def ambience_room_tone_loop():
    L = 6.0
    N = n_(L)
    t = np.arange(N) / SR
    air = fft_shape(noise(L, 211), lo=40, hi=500, tilt=-0.6, circular=True)
    air /= np.std(air)
    hum = (0.5 * np.sin(2 * np.pi * 60 * t) + 0.35 * np.sin(2 * np.pi * 120 * t + 0.4)
           + 0.12 * np.sin(2 * np.pi * 180 * t + 1.1))
    # reator de lâmpada fluorescente: 120 Hz rico em harmônicos, bem baixinho
    buzz = sum(np.sin(2 * np.pi * 120 * k * t + k) / k ** 1.6 for k in range(2, 16))
    buzz *= 1 + 0.25 * np.sin(2 * np.pi * t * 3 / L)
    hiss = fft_shape(noise(L, 212), lo=2000, hi=6000, circular=True)
    hiss /= np.std(hiss)
    swell = 1 + 0.15 * np.sin(2 * np.pi * t * 1 / L + 0.5) + 0.08 * np.sin(2 * np.pi * t * 4 / L)
    return (air * 0.6 * swell + hum * 0.35 + buzz * 0.08 + hiss * 0.03)


SOUNDS = [ui_tap, ui_back, card_pin, card_pick, card_drop, string_stretch, string_connect,
          string_cut, paper_flip, clue_new, phone_buzz, hotspot_found, submit_stamp, wrong,
          correct, victory, timer_tick, timer_urgent, join_ping, countdown_go,
          ambience_rain_loop, ambience_room_tone_loop]


# ------------------------------------------------------------------ saída
def normalize(x, db):
    return x / (np.max(np.abs(x)) + 1e-12) * 10 ** (db / 20)


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return pcm


# ------------------------------------------------------------------ folha de contato (PNG puro)
FONT = {
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
    "_": "000000000000111", ".": "000000000000010", "-": "000000111000000", ":": "000010000010000",
    " ": "000000000000000", "/": "001001010100100",
}


def draw_text(img, x, y, s, color, scale=2):
    for ch in s.upper():
        g = FONT.get(ch, FONT[" "])
        for i, b in enumerate(g):
            if b == "1":
                r, c = divmod(i, 3)
                img[y + r * scale:y + (r + 1) * scale, x + c * scale:x + (c + 1) * scale] = color
        x += 4 * scale


def write_png(path, img):
    h, w, _ = img.shape
    raw = b"".join(b"\x00" + img[r].tobytes() for r in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)


BG = hexrgb("#060c1f")
MID = hexrgb("#26407a")
LIGHT = hexrgb("#4e6fc0")
YEL = hexrgb("#ffc83d")
PINK = hexrgb("#ff4fa3")


def colormap(v):
    """0..1 -> noite azul -> azul claro -> amarelo."""
    stops = np.array([[6, 12, 31], [38, 64, 122], [78, 111, 192], [190, 200, 230], [255, 200, 61]], float)
    pos = np.array([0, 0.35, 0.6, 0.82, 1.0])
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(v, pos, stops[:, c])
    return out.astype(np.uint8)


def cell(x, name, cw=600, wh=70, sh=90):
    img = np.zeros((wh + sh + 22, cw, 3), np.uint8)
    img[:] = BG
    dur = len(x) / SR
    peak = np.max(np.abs(x))
    pdb = 20 * np.log10(peak + 1e-12)
    clipped = peak >= 0.999
    draw_text(img, 4, 4, f"{name}  {dur:.2f}S  PICO {pdb:.1f}DB", PINK if clipped else YEL)
    top = 20
    # forma de onda (min/max por coluna) + linhas de -3 dBFS e 0 dBFS
    mid = top + wh // 2
    edges = np.linspace(0, len(x), cw + 1).astype(int)
    for c in range(cw):
        seg = x[edges[c]:max(edges[c + 1], edges[c] + 1)]
        lo_, hi_ = seg.min(), seg.max()
        y0 = int(mid - hi_ * (wh / 2 - 1))
        y1 = int(mid - lo_ * (wh / 2 - 1))
        img[y0:y1 + 1, c] = LIGHT
    lvl = 10 ** (-3 / 20) * (wh / 2 - 1)
    for yy in (int(mid - lvl), int(mid + lvl)):
        img[yy, ::4] = MID
    img[top, :] = MID
    img[top + wh - 1, :] = MID
    img[mid, ::2] = MID
    # espectrograma (dB, 0..11 kHz)
    nfft, hop = 512, 64
    xp = np.concatenate([np.zeros(nfft // 2), x, np.zeros(nfft)])
    frames = np.lib.stride_tricks.sliding_window_view(xp, nfft)[::hop] * np.hanning(nfft)
    S = np.abs(np.fft.rfft(frames, axis=1))
    S = 20 * np.log10(S + 1e-9)
    S = (S - (S.max() - 75)) / 75
    cols = np.linspace(0, S.shape[0] - 1, cw).astype(int)
    rows = np.linspace(S.shape[1] - 1, 0, sh).astype(int)
    img[top + wh + 2:top + wh + 2 + sh] = colormap(S[cols][:, rows].T)
    return img


def contact_sheet(clips):
    cols = 2
    cells = [cell(x, n) for n, x in clips]
    ch, cw = cells[0].shape[:2]
    rows = (len(cells) + cols - 1) // cols
    pad = 12
    W = cols * cw + (cols + 1) * pad
    H = rows * ch + (rows + 1) * pad + 30
    sheet = np.zeros((H, W, 3), np.uint8)
    sheet[:] = hexrgb("#03060f")
    draw_text(sheet, pad, 8, "RUMOR - SFX PROCEDURAIS - ONDA COM LINHAS DE -3DB / ESPECTRO 0-11KHZ", YEL, 3)
    for i, c in enumerate(cells):
        r, k = divmod(i, cols)
        y = 30 + pad + r * (ch + pad)
        x = pad + k * (cw + pad)
        sheet[y:y + ch, x:x + cw] = c
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    write_png(SHEET, sheet)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    clips = []
    print(f"{'som':26s} {'dur(s)':>7s} {'pico dBFS':>10s} {'KB':>6s}  loop-emenda")
    for fn in SOUNDS:
        name = fn.__name__
        x = fn().astype(np.float64)
        is_loop = name.endswith("_loop")
        # tira DC/subgrave antes do fade (subtrair a média depois deixaria degrau = clique no fim)
        x = fft_shape(x, lo=25, order=2, circular=is_loop)
        if not is_loop:
            x = fades(x, 0.002, 0.01)
        x = normalize(x, PEAK_AMB_DB.get(name, PEAK_SFX_DB))
        path = OUT_DIR / f"{name}.wav"
        pcm = write_wav(path, x)
        back = pcm.astype(np.float64) / 32767
        peak_db = 20 * np.log10(np.max(np.abs(back)) + 1e-12)
        seam = ""
        if is_loop:
            # salto na emenda comparado ao passo típico entre amostras vizinhas
            jump = abs(back[0] - back[-1])
            typ = np.percentile(np.abs(np.diff(back)), 99)
            seam = f"salto {jump:.4f} (p99 vizinho {typ:.4f})"
        print(f"{name:26s} {len(back) / SR:7.2f} {peak_db:10.2f} {path.stat().st_size / 1024:6.1f}  {seam}")
        clips.append((name, back))
    contact_sheet(clips)
    print("folha:", SHEET)


if __name__ == "__main__":
    main()
