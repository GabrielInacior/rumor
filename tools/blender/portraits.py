"""Retratos de personagem (cartas do quadro) do RUMOR: busto estilizado em toon pintado.

blender --background --factory-startup --python tools/blender/portraits.py -- <entrada.json> <pasta_saida> [--folha <png>] [--so <id>]

<entrada.json>: lista [{"id":..., "look":{...}}] OU um caso (server/cases/*.json): lê os cards com
kind "pessoa" (id + look). Saída: <pasta_saida>/<id>.png, 256x320, fundo transparente.

look = {skin, hair: curto|longo|coque|cacheado|raspado|franja|rabo, hair_color, top (hex),
        accessory: nenhum|oculos|bone|fones|brinco|cachecol,
        opcionais: expression (confiante|desconfiado|nervoso|alegre|entediado|serio),
                   top_style (moletom|camisa|jaqueta|gola_alta|camiseta), eye_color, freckles (bool),
                   accessory_color, yaw (graus)}
Sem os opcionais, eles saem do hash do id (mesmo id = mesmo retrato sempre).

Técnica: toda a geometria é gerada por código (malhas próprias, sem primitivas do operador).
Material toon: Shader to RGB -> rampa constante com 4 faixas (sombra puxando para azul-noite),
ruído quebrando a borda (pincelada), contorno amarelo de lua/poste no lado direito por máscara
de normal em espaço de câmera. Contorno de tinta por casco invertido (Solidify + material preto
com backface culling). Rosto desenhado como "decalque" 2D projetado na cabeça (olhos, pálpebras,
sobrancelhas, boca e nariz são pinceladas com espessura variável), o que dá expressão de desenho
feito à mão. Renderiza em 4x e o pós-processo (versão leve do spike_post: Kuwahara curto,
retícula fina nas sombras, desalinhamento rosa discreto, grão) reduz para 256x320.
"""
import hashlib
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_W, OUT_H, SS = 256, 320, 4

HC = Vector((0.0, 0.0, 1.55))      # centro da cabeça
HA, HB, HCZ = 0.50, 0.47, 0.58     # semi-eixos da cabeça (largura, profundidade, altura)
FRONT_FLAT, BACK_BULGE = 0.93, 1.05


# ------------------------------------------------------------------ cor
def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return np.array([x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c])


NIGHT = lin("#1b2a5e")
NIGHT_DEEP = lin("#0b1533")
YELLOW = lin("#ffc83d")
PINK = lin("#ff4fa3")


def rgba(c, a=1.0):
    c = np.clip(np.asarray(c, float), 0, 4)
    return (float(c[0]), float(c[1]), float(c[2]), a)


def seeded(id_, salt=""):
    return int(hashlib.md5((id_ + salt).encode()).hexdigest()[:8], 16)


# ------------------------------------------------------------------ materiais
_mats = {}


def _nodes(m):
    if m.node_tree is None:
        m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return nt, nt.nodes, nt.links


def sock(node, ident, out=False):
    coll = node.outputs if out else node.inputs
    for s in coll:
        if s.identifier == ident:
            return s
    raise KeyError(ident)


def mix_rgb(N, L, a, b, fac):
    """Mix colorido; a/b/fac podem ser sockets ou valores."""
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    for ident, v in (("Factor_Float", fac), ("A_Color", a), ("B_Color", b)):
        s = sock(mx, ident)
        if hasattr(v, "is_output"):
            L.new(v, s)
        else:
            s.default_value = v
    return sock(mx, "Result_Color", out=True)


def math_node(N, L, op, a, b=None, clamp=False):
    n = N.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if hasattr(v, "is_output"):
            L.new(v, n.inputs[i])
        else:
            n.inputs[i].default_value = v
    return n.outputs[0]


def toon(name, base, stroke=0.16, brush=7.0, rim=1.0, soft=False, shadow_mix=0.38):
    """Material pintado. base em linear (np.array). soft=True: sombra mais clara (olho)."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    nt, N, L = _nodes(m)
    out = N.new("ShaderNodeOutputMaterial")
    diff = N.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = N.new("ShaderNodeShaderToRGB")
    L.new(diff.outputs[0], s2r.inputs[0])
    bw = N.new("ShaderNodeRGBToBW")
    L.new(s2r.outputs["Color"], bw.inputs[0])

    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (brush, brush * 0.35, brush)
    L.new(tc.outputs["Object"], mp.inputs[0])
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.0
    nz.inputs["Detail"].default_value = 6.0
    nz.inputs["Roughness"].default_value = 0.65
    L.new(mp.outputs[0], nz.inputs["Vector"])
    jit = math_node(N, L, "MULTIPLY", math_node(N, L, "SUBTRACT", nz.outputs["Fac"], 0.5), stroke)
    lum = math_node(N, L, "ADD", bw.outputs[0], jit, clamp=True)

    b = np.asarray(base, float)
    if soft:
        cols = [b * 0.62 + NIGHT * 0.12, b * 0.8 + NIGHT * 0.06, b, b * 1.04]
    else:
        cols = [b * shadow_mix + NIGHT * 0.32, b * 0.66 + NIGHT * 0.16, b, b * 1.16 + np.array([0.03, 0.025, 0.0])]
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    el = ramp.color_ramp.elements
    el[0].position = 0.0
    el[0].color = rgba(cols[0])
    el[1].position = 0.17
    el[1].color = rgba(cols[1])
    e = el.new(0.40)
    e.color = rgba(cols[2])
    e = el.new(0.86)
    e.color = rgba(cols[3])
    L.new(lum, ramp.inputs[0])

    # variação de pigmento (manchas de pincel)
    pv = math_node(N, L, "ADD", math_node(N, L, "MULTIPLY", nz.outputs["Fac"], 0.2), 0.9)
    vs = N.new("ShaderNodeVectorMath")
    vs.operation = "SCALE"
    L.new(ramp.outputs["Color"], vs.inputs[0])
    L.new(pv, vs.inputs["Scale"])
    color = vs.outputs[0]

    if rim > 0:
        # contorno de luz amarela no lado direito da tela (luz de poste/janela atrás)
        lw = N.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.35
        fac = math_node(N, L, "ADD", lw.outputs["Facing"], math_node(N, L, "MULTIPLY", jit, 0.8))
        r1 = math_node(N, L, "GREATER_THAN", fac, 0.62)
        geo = N.new("ShaderNodeNewGeometry")
        vt = N.new("ShaderNodeVectorTransform")
        vt.vector_type = "NORMAL"
        vt.convert_from = "WORLD"
        vt.convert_to = "CAMERA"
        L.new(geo.outputs["Normal"], vt.inputs[0])
        sx = N.new("ShaderNodeSeparateXYZ")
        L.new(vt.outputs[0], sx.inputs[0])
        r2 = math_node(N, L, "GREATER_THAN", sx.outputs[0], 0.28)
        r3 = math_node(N, L, "LESS_THAN", sx.outputs[1], 0.75)
        rimf = math_node(N, L, "MULTIPLY", math_node(N, L, "MULTIPLY", r1, r2), r3)
        rimf = math_node(N, L, "MULTIPLY", rimf, rim)
        rimcol = rgba(b * 0.45 + YELLOW * 0.7)
        color = mix_rgb(N, L, color, rimcol, rimf)

    em = N.new("ShaderNodeEmission")
    L.new(color, em.inputs["Color"])
    L.new(em.outputs[0], out.inputs[0])
    _mats[name] = m
    return m


def flat(name, color, strength=1.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    nt, N, L = _nodes(m)
    out = N.new("ShaderNodeOutputMaterial")
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = rgba(color)
    em.inputs["Strength"].default_value = strength
    L.new(em.outputs[0], out.inputs[0])
    _mats[name] = m
    return m


def ink():
    if "ink" not in _mats:
        m = flat("ink", lin("#050914"))
        m.use_backface_culling = True
        for attr in ("use_backface_culling_shadow",):
            if hasattr(m, attr):
                setattr(m, attr, True)
    return _mats["ink"]


# ------------------------------------------------------------------ construção de malha
class MB:
    """Acumula vértices/faces com índice de material e vira um objeto só (poucas draw calls)."""

    def __init__(self):
        self.v, self.f, self.m = [], [], []

    def add(self, verts, faces, mi=0):
        o = len(self.v)
        self.v += [tuple(p) for p in verts]
        self.f += [tuple(i + o for i in f) for f in faces]
        self.m += [mi] * len(faces)

    def build(self, name, mats, outline=0.0, smooth=True):
        if not self.f:
            return None
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.validate()
        me.update()
        for m in mats:
            me.materials.append(m)
        n = len(me.polygons)
        mi = self.m[:n] if len(self.m) >= n else self.m + [0] * (n - len(self.m))
        me.polygons.foreach_set("material_index", mi)
        me.polygons.foreach_set("use_smooth", [smooth] * n)
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        if outline > 0:
            for _ in mats:
                me.materials.append(ink())
            sol = o.modifiers.new("ink", "SOLIDIFY")
            sol.thickness = outline
            sol.offset = 1.0
            sol.use_flip_normals = True
            sol.use_rim = False
            sol.material_offset = len(mats)
        return o


def ellipsoid(c, r, segs=24, rings=14, rot=None, keep=None, deform=None):
    """Elipsoide (verts, faces). keep(u)->bool filtra pelo vetor unitário (corta calotas)."""
    us = [Vector((0, 0, -1))]
    for i in range(1, rings):
        ph = -math.pi / 2 + math.pi * i / rings
        for j in range(segs):
            th = 2 * math.pi * j / segs
            us.append(Vector((math.cos(ph) * math.cos(th), math.cos(ph) * math.sin(th), math.sin(ph))))
    us.append(Vector((0, 0, 1)))
    faces = []
    for j in range(segs):
        faces.append((0, 1 + (j + 1) % segs, 1 + j))
    for i in range(rings - 2):
        for j in range(segs):
            a = 1 + i * segs + j
            b = 1 + i * segs + (j + 1) % segs
            faces.append((a, b, b + segs, a + segs))
    top = len(us) - 1
    base = 1 + (rings - 2) * segs
    for j in range(segs):
        faces.append((base + j, base + (j + 1) % segs, top))
    rm = rot if rot is not None else Matrix.Identity(3)
    verts = []
    for u in us:
        p = Vector((u.x * r[0], u.y * r[1], u.z * r[2]))
        if deform:
            p = deform(u, p)
        verts.append(rm @ p + Vector(c))
    if keep:
        ok = [keep(u) for u in us]
        faces = [f for f in faces if all(ok[i] for i in f)]
        used = sorted({i for f in faces for i in f})
        remap = {o: n for n, o in enumerate(used)}
        verts = [verts[i] for i in used]
        faces = [tuple(remap[i] for i in f) for f in faces]
    return verts, faces


def catmull(pts, per=6):
    pts = [Vector(p) for p in pts]
    if len(pts) < 3:
        out = []
        for k in range(per * 2 + 1):
            out.append(pts[0].lerp(pts[-1], k / (per * 2)))
        return out
    P = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def tube(pts, radii, flat=1.0, ring=8, per=6, center=None):
    """Mecha/tubo ao longo de pontos, seção elíptica achatada contra a cabeça."""
    P = catmull(pts, per)
    n = len(P)
    tk = np.linspace(0, 1, len(radii))
    R = np.interp(np.linspace(0, 1, n), tk, radii)
    c0 = center if center is not None else HC
    verts, faces = [], []
    for i, p in enumerate(P):
        T = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        out = p - Vector((c0.x, c0.y, min(p.z, c0.z)))
        Nn = out - T * out.dot(T)
        if Nn.length < 1e-4:
            Nn = Vector((0, -1, 0)) - T * T.y
        Nn.normalize()
        Bv = T.cross(Nn)
        for k in range(ring):
            a = 2 * math.pi * k / ring
            verts.append(p + Bv * math.cos(a) * R[i] + Nn * math.sin(a) * R[i] * flat)
    for i in range(n - 1):
        for k in range(ring):
            a = i * ring + k
            b = i * ring + (k + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    ci = len(verts)
    verts.append(P[0])
    for k in range(ring):
        faces.append((ci, (k + 1) % ring, k))
    return verts, faces


def S(th, ph, off=0.0):
    """Ponto sobre a cabeça: th azimute em graus (0 = frente, + = direita da tela), ph elevação."""
    t, p = math.radians(th), math.radians(ph)
    y = -math.cos(t) * math.cos(p)
    by = HB * (FRONT_FLAT if y < 0 else BACK_BULGE)
    return HC + Vector((HA * (1 + off) * math.sin(t) * math.cos(p), by * (1 + off) * y, HCZ * (1 + off) * math.sin(p)))


# ------------------------------------------------------------------ cabeça e rosto
FACE = {"jaw": 0.34, "cheek": 0.045, "chin": 0.03, "long": 1.0}


def head_deform(u, p):
    s = u.z
    x, y, z = p
    z *= FACE["long"] if s < 0 else 1.0
    if s < 0.18:
        k = (0.18 - s) / 1.18
        x *= 1 - FACE["jaw"] * k ** 1.15
        y *= 1 - 0.10 * k
    x *= 1 + FACE["cheek"] * math.exp(-((s + 0.05) / 0.22) ** 2)   # maçã do rosto
    y *= FRONT_FLAT if u.y < 0 else BACK_BULGE
    if u.y < 0 and s < -0.55:                               # queixo um pouco à frente
        y -= FACE["chin"] * (-0.55 - s) / 0.45
    return Vector((x, y, z))


class Face:
    """Desenha no rosto: formas e pinceladas 2D (u, v relativos ao centro da cabeça) projetadas."""

    def __init__(self, head_verts, head_faces):
        self.bvh = BVHTree.FromPolygons([Vector(v) for v in head_verts], head_faces)
        self.mb = MB()

    def proj(self, u, v, off):
        o = Vector((HC.x + u, -3.0, HC.z + v))
        hit, nrm, _, _ = self.bvh.ray_cast(o, Vector((0, 1, 0)))
        if hit is None:
            return Vector((HC.x + u, HC.y - HB, HC.z + v))
        if nrm.y > 0:
            nrm = -nrm
        return hit + nrm * off

    def shape(self, pts, mi, off):
        pts = [np.array(p, float) for p in pts]
        c = sum(pts) / len(pts)
        n = len(pts)
        verts = [self.proj(*c, off)]
        verts += [self.proj(*(c + (p - c) * 0.5), off) for p in pts]
        verts += [self.proj(*p, off) for p in pts]
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.append((0, 1 + i, 1 + j))
            faces.append((1 + i, 1 + n + i, 1 + n + j, 1 + j))
        self.mb.add(verts, faces, mi)

    def stroke(self, pts, width, mi, off, taper=(0.25, 0.6), per=8, wfun=None):
        P = [np.array([p.x, p.z]) for p in catmull([Vector((p[0], 0, p[1])) for p in pts], per)]
        n = len(P)
        L, R = [], []
        for i, p in enumerate(P):
            t = i / (n - 1)
            d = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
            d = d / (np.linalg.norm(d) + 1e-9)
            nn = np.array([-d[1], d[0]])
            if wfun:
                w = wfun(t) * width
            else:
                a, b = taper
                w = width * min(1.0, (t / a) if a > 0 else 1.0) ** 0.7 * min(1.0, ((1 - t) / b) if b > 0 else 1.0) ** 0.7
                w = max(w, width * 0.08)
            L.append(p + nn * w / 2)
            R.append(p - nn * w / 2)
        verts = [self.proj(*q, off) for q in L] + [self.proj(*q, off) for q in R]
        faces = [(i, i + 1, n + i + 1, n + i) for i in range(n - 1)]
        self.mb.add(verts, faces, mi)

    def circle(self, cu, cv, r, mi, off, clip=None, k=20, sx=1.0):
        pts = []
        for i in range(k):
            a = 2 * math.pi * i / k
            x, y = cu + r * math.cos(a) * sx, cv + r * math.sin(a)
            if clip:
                q = clip(x, y)
                if q is None:
                    continue
                x, y = q
            pts.append((x, y))
        if len(pts) >= 3:
            self.shape(pts, mi, off)


# índices de material do rosto
F_WHITE, F_LIDSH, F_IRIS, F_IRIS_L, F_PUPIL, F_HI, F_LINE, F_SKDK, F_MOUTH, F_TEETH, F_BROW, F_GLINT, F_TONGUE, F_BLUSH = range(14)

EXPR = {
    #            lid(L,R)    lowerlid  brows (inner, mid, outer) L / R           gaze      mouth        roll
    "confiante":   dict(lid=(0.22, 0.30), lr=0.12, bL=(0.00, 0.02, -0.01), bR=(0.03, 0.06, 0.03), gaze=(0.25, 0.0), mouth="smirk", roll=-3),
    "desconfiado": dict(lid=(0.42, 0.48), lr=0.18, bL=(-0.035, -0.01, 0.0), bR=(-0.02, 0.0, 0.01), gaze=(0.55, -0.05), mouth="side", roll=2),
    "nervoso":     dict(lid=(0.00, 0.02), lr=0.0, bL=(0.05, 0.035, -0.005), bR=(0.05, 0.035, -0.005), gaze=(-0.2, -0.1), mouth="worried", roll=4),
    "alegre":      dict(lid=(0.10, 0.10), lr=0.38, bL=(0.035, 0.045, 0.02), bR=(0.035, 0.045, 0.02), gaze=(0.0, 0.0), mouth="smile_open", roll=-4),
    "entediado":   dict(lid=(0.52, 0.55), lr=0.05, bL=(0.0, 0.0, -0.01), bR=(0.01, 0.01, 0.0), gaze=(-0.35, 0.25), mouth="flat", roll=5),
    "serio":       dict(lid=(0.25, 0.25), lr=0.08, bL=(-0.015, 0.0, 0.0), bR=(-0.015, 0.0, 0.0), gaze=(0.1, 0.0), mouth="line", roll=0),
}


def draw_eye(face, side, ex, ey, w, h, lid, lr, gaze, wing=0.1):
    """side=+1 olho na direita da tela. Formato de lente com canto externo levemente erguido."""
    s = side

    def up(x):
        xx = np.clip(x, -1, 1)
        bump = 1 + 0.16 * (-xx * s)               # pico mais para o lado de dentro
        return h * (1 - lid) * (1 - xx * xx) ** 0.5 * bump + h * 0.10 * xx * s

    def lo(x):
        xx = np.clip(x, -1, 1)
        return -h * 0.62 * (1 - xx * xx) ** 0.75 * (1 - lr) + h * 0.10 * xx * s

    xs = np.linspace(-1, 1, 19)
    outline = [(ex + x * w, ey + up(x)) for x in xs] + [(ex + x * w, ey + lo(x)) for x in xs[::-1]]
    face.shape(outline, F_WHITE, 0.004)

    def clip(x, y, m=0.0):
        xn = (x - ex) / w
        if abs(xn) >= 0.985:
            return None
        u_, l_ = ey + up(xn) - m, ey + lo(xn) + m
        if u_ <= l_:
            return None
        return (x, min(max(y, l_), u_))

    ri = h * 0.98
    icx, icy = ex + gaze[0] * w * 0.42, ey + gaze[1] * h * 0.5 - h * 0.08
    face.circle(icx, icy, ri, F_IRIS, 0.006, clip, k=28, sx=0.92)
    face.circle(icx, icy - ri * 0.25, ri * 0.62, F_IRIS_L, 0.0065,
                lambda x, y: clip(x, y) if y < icy - ri * 0.12 else None, k=24)
    face.circle(icx, icy, ri * 0.48, F_PUPIL, 0.007, clip, k=20)
    hx, hy = icx - ri * 0.38 * s * 0.6 - ri * 0.2, icy + ri * 0.36
    if clip(hx, hy) and clip(hx, hy)[1] == hy:
        face.circle(hx, hy, ri * 0.24, F_HI, 0.010, k=12)
    hx2, hy2 = icx + ri * 0.35, icy - ri * 0.35
    if clip(hx2, hy2) and clip(hx2, hy2)[1] == hy2:
        face.circle(hx2, hy2, ri * 0.1, F_HI, 0.010, k=8)
    # sombra da pálpebra sobre o olho
    sh = [(ex + x * w, ey + up(x) - h * 0.12) for x in np.linspace(-0.95, 0.95, 9)]
    face.stroke(sh, h * 0.32, F_LIDSH, 0.0085, taper=(0.2, 0.2))
    # linha da pálpebra superior, mais grossa para fora, com "asa" no canto
    lidl = [(ex + x * w, ey + up(x)) for x in np.linspace(-1.08, 1.0, 9)]
    if s < 0:
        lidl = [(ex + x * w, ey + up(x)) for x in np.linspace(1.08, -1.0, 9)]
    lidl.append((ex + s * w * (1.04 + wing * 0.9), ey + up(s * 1.0) + h * (0.05 + wing)))
    face.stroke(lidl, h * 0.34, F_LINE, 0.011, wfun=lambda t: 0.35 + 0.65 * math.sin(min(t, 0.92) * math.pi * 0.62) * (1 - max(0, t - 0.85) * 5))
    # vinco da pálpebra (dobra) e cílio de baixo
    crease = [(ex + x * w, ey + up(x) * 0.15 + h * (1.0 - lid * 0.6) + h * 0.32) for x in np.linspace(-0.55 * s, 0.95 * s, 6)]
    face.stroke(crease, h * 0.1, F_SKDK, 0.0105, taper=(0.4, 0.4))
    lower = [(ex + x * w, ey + lo(x)) for x in np.linspace(0.05 * s, 1.0 * s, 6)]
    face.stroke(lower, h * 0.11, F_SKDK, 0.0105, taper=(0.5, 0.3))
    if lr > 0.25:   # bochecha empurrando o olho (sorriso)
        ch = [(ex + x * w, ey + lo(x) - h * 0.32) for x in np.linspace(-0.5 * s, 0.8 * s, 6)]
        face.stroke(ch, h * 0.09, F_SKDK, 0.0105, taper=(0.5, 0.5))


def draw_brow(face, side, bx, by, raise_):
    s = side
    ri, rm, ro = raise_
    pts = [(bx + s * -0.105, by + ri - 0.012), (bx + s * -0.03, by + rm + 0.012), (bx + s * 0.05, by + rm + 0.008),
           (bx + s * 0.115, by + ro - 0.022)]
    face.stroke(pts, 0.042, F_BROW, 0.012, wfun=lambda t: (0.75 + 0.25 * math.sin(t * math.pi)) * (1 - t ** 3 * 0.85))
    # fios soltos na ponta de dentro (pelo, não carimbo)
    for k in range(3):
        x0 = bx + s * (-0.1 + k * 0.022)
        face.stroke([(x0, by + ri - 0.02 + k * 0.004), (x0 + s * 0.012, by + ri + 0.012 + k * 0.006)], 0.008, F_BROW, 0.0125,
                    taper=(0.3, 0.6))


def draw_mouth(face, kind, mv=-0.335):
    lipc = F_SKDK
    if kind == "smirk":
        face.stroke([(-0.085, mv - 0.004), (-0.02, mv - 0.008), (0.05, mv - 0.002), (0.105, mv + 0.032)], 0.02, F_MOUTH, 0.011,
                    taper=(0.3, 0.3))
        face.stroke([(0.1, mv + 0.044), (0.118, mv + 0.024), (0.11, mv + 0.006)], 0.01, lipc, 0.011, taper=(0.4, 0.4))
        face.stroke([(-0.035, mv - 0.05), (0.035, mv - 0.048)], 0.014, lipc, 0.011, taper=(0.5, 0.5))
    elif kind == "side":
        face.stroke([(-0.09, mv + 0.004), (-0.02, mv - 0.002), (0.05, mv - 0.008), (0.085, mv - 0.022)], 0.018, F_MOUTH, 0.011,
                    taper=(0.3, 0.3))
        face.stroke([(-0.03, mv - 0.05), (0.03, mv - 0.052)], 0.013, lipc, 0.011, taper=(0.5, 0.5))
    elif kind == "worried":
        face.stroke([(-0.06, mv - 0.012), (-0.025, mv + 0.002), (0.0, mv - 0.008), (0.03, mv + 0.002), (0.062, mv - 0.012)], 0.016,
                    F_MOUTH, 0.011, taper=(0.25, 0.25))
        face.stroke([(-0.025, mv - 0.045), (0.025, mv - 0.045)], 0.012, lipc, 0.011, taper=(0.5, 0.5))
        # gota de suor
        face.shape([(0.36, 0.06), (0.375, 0.02), (0.37, 0.0), (0.355, -0.005), (0.345, 0.012), (0.35, 0.035)], F_HI, 0.012)
    elif kind == "smile_open":
        up = [(-0.115, mv + 0.035), (-0.06, mv + 0.008), (0.0, mv + 0.002), (0.06, mv + 0.008), (0.115, mv + 0.035)]
        low = [(0.09, mv + 0.0), (0.045, mv - 0.055), (0.0, mv - 0.07), (-0.045, mv - 0.055), (-0.09, mv + 0.0)]
        face.shape(up + low, F_MOUTH, 0.0095)
        face.stroke([(-0.085, mv + 0.012), (0.0, mv - 0.008), (0.085, mv + 0.012)], 0.022, F_TEETH, 0.0105,
                    taper=(0.15, 0.15))
        face.shape([(-0.04, mv - 0.05), (0.0, mv - 0.035), (0.04, mv - 0.05), (0.0, mv - 0.066)], F_TONGUE, 0.0102)
        face.stroke(up, 0.016, F_LINE, 0.011, taper=(0.2, 0.2))
        for s in (-1, 1):
            face.stroke([(s * 0.122, mv + 0.055), (s * 0.135, mv + 0.03), (s * 0.122, mv + 0.008)], 0.01, lipc, 0.011,
                        taper=(0.4, 0.4))
    elif kind == "flat":
        face.stroke([(-0.07, mv - 0.004), (0.0, mv - 0.006), (0.065, mv - 0.012)], 0.016, F_MOUTH, 0.011, taper=(0.3, 0.3))
        face.stroke([(-0.03, mv - 0.048), (0.03, mv - 0.05)], 0.013, lipc, 0.011, taper=(0.5, 0.5))
    else:  # line (sério)
        face.stroke([(-0.08, mv), (0.0, mv - 0.004), (0.08, mv)], 0.017, F_MOUTH, 0.011, taper=(0.3, 0.3))
        face.stroke([(-0.032, mv - 0.05), (0.032, mv - 0.05)], 0.013, lipc, 0.011, taper=(0.5, 0.5))


# ------------------------------------------------------------------ cabelo
def hairline(th_deg, style):
    a = abs(((th_deg + 180) % 360) - 180)
    if style == "raspado":
        return float(np.interp(a, [0, 40, 70, 95, 130, 180], [24, 22, 14, 8, -30, -48]))
    return float(np.interp(a, [0, 18, 34, 48, 62, 80, 95, 120, 180], [25, 24, 20, 14, 16, 10, 8, -32, -52]))


def cap(style, scale, mi, segs=72, rows=22):
    """Calota de cabelo em grade que começa exatamente na linha do cabelo (borda lisa e curva)."""
    rnd = np.random.default_rng(7)
    verts, faces = [], []
    for i in range(rows):
        for j in range(segs):
            th = -180 + 360 * j / segs
            hl = hairline(th, style) - 1.5 + (0.0 if i else 1.2 * math.sin(math.radians(th) * 9))
            ph = hl + (89.0 - hl) * (i / rows) ** 0.85
            t, p = math.radians(th), math.radians(ph)
            y = -math.cos(t) * math.cos(p)
            by = HB * (FRONT_FLAT if y < 0 else BACK_BULGE)
            # sobe um pouco no topo (volume) e afina rente à borda
            sc = scale * (1 + 0.04 * max(0.0, math.sin(p))) * (0.985 if i == 0 else 1.0)
            verts.append(HC + Vector((HA * sc * math.sin(t) * math.cos(p), by * sc * y, HCZ * sc * math.sin(p))))
    for i in range(rows - 1):
        for j in range(segs):
            a0 = i * segs + j
            b0 = i * segs + (j + 1) % segs
            faces.append((a0, b0, b0 + segs, a0 + segs))
    top = len(verts)
    verts.append(HC + Vector((0, 0, HCZ * scale * 1.04)))
    base = (rows - 1) * segs
    for j in range(segs):
        faces.append((base + j, base + (j + 1) % segs, top))
    return (verts, faces), mi


def build_hair(look, rnd, mats):
    """Retorna MB do cabelo. mats: [base, claro, escuro]."""
    style = look.get("hair", "curto")
    mb = MB()
    J = lambda a: rnd.uniform(-a, a)
    (cv, cf), mi = cap(style, 1.035 if style != "raspado" else 1.018, 0)
    mb.add(cv, cf, mi)
    pick = lambda i: (0, 1, 0, 2)[i % 4]
    sweep = 12 if seeded(look.get("_id", ""), "sw") % 2 else -12

    def lock(pts, r0, r1, i, flat=0.5, mid=None):
        radii = [r0, (mid if mid else (r0 + r1) / 2 * 1.15), r1 * 0.5 + 0.004] if len(pts) > 2 else [r0, r1]
        v, f = tube(pts, radii + [0.003], flat=flat)
        mb.add(v, f, pick(i))

    if style == "curto":
        for i in range(15):
            th = -78 + 156 * i / 14 + J(5)
            tip = S(th * 0.8 + sweep, 19 + J(4) + abs(th) * 0.08, 0.16)
            lock([S(th * 0.2 + 180 * 0, 84, 0.02), S(th * 0.9 + sweep * 0.5, 58, 0.13), S(th + sweep, 36, 0.14), tip],
                 0.085, 0.03, i, flat=0.55)
        for i, th in enumerate(range(80, 200, 18)):
            for s in (-1, 1):
                t = s * (th + J(5))
                lock([S(t * 0.7, 70, 0.03), S(t, 30, 0.08), S(t, 0 if abs(t) < 110 else -25, 0.075)], 0.08, 0.025, i, flat=0.45)
    elif style == "longo":
        part = sweep * 0.8
        for s in (-1, 1):       # franja cortina: abre do repartido para os lados, cobre a linha da testa
            for k in range(3):
                lock([S(part, 86, 0.02), S(part * 0.5 + s * (6 + k * 8), 52, 0.13), S(s * (16 + k * 12), 22 - k * 2, 0.12),
                      S(s * (34 + k * 12), 4 - k * 3, 0.13), S(s * (46 + k * 10), -14 - k * 4, 0.15)],
                     0.085, 0.03, k + 1, flat=0.45, mid=0.095)
        for s in (-1, 1):
            for k in range(6):
                th = s * (42 + k * 24 + J(4))
                endx = s * (0.5 + 0.06 * k + J(0.03))
                endy = -0.12 + 0.07 * k
                lock([S(part, 84, 0.02), S(s * (18 + k * 20), 52, 0.11), S(th, 14, 0.13),
                      HC + Vector((endx * 0.98, endy, -0.30 + J(0.03))),
                      HC + Vector((endx * 1.04, endy + 0.02, -0.66 + J(0.06))),
                      HC + Vector((endx * 0.92 - s * 0.05, endy - 0.04, -0.86 + J(0.05)))],
                     0.12, 0.035, k + (s > 0), flat=0.5, mid=0.13)
        for i in range(9):
            th = 120 + i * 15
            x = math.sin(math.radians(th)) * 0.45
            lock([S(th * 0.3, 80, 0.03), S(th, 30, 0.1), HC + Vector((x, 0.32, -0.5)), HC + Vector((x * 1.1, 0.28, -0.88))],
                 0.11, 0.04, i)
        v, f = ellipsoid(HC + Vector((0, 0.2, -0.34)), (0.6, 0.36, 0.6), 20, 12)
        mb.add(v, f, 2)
    elif style == "franja":
        for i in range(10):
            th = -44 + 88 * i / 9 + J(3)
            lock([S(th * 0.3, 82, 0.02), S(th, 48, 0.13), S(th * 1.03, 24, 0.13), S(th * 1.06, 11 + J(2.5), 0.08)],
                 0.075, 0.035, i, flat=0.45, mid=0.085)
        for s in (-1, 1):
            for k in range(4):
                th = s * (54 + k * 14)
                lock([S(th * 0.6, 75, 0.03), S(th, 22, 0.13), S(th + s * 8, -18, 0.17),
                      HC + Vector((s * (0.5 + 0.03 * k), -0.12 + 0.08 * k, -0.42 - 0.03 * k)),
                      HC + Vector((s * (0.42 + 0.03 * k), -0.18 + 0.08 * k, -0.5 - 0.03 * k))], 0.09, 0.035, k + (s > 0), flat=0.5)
        for i in range(8):
            th = 125 + i * 16
            x = math.sin(math.radians(th)) * 0.5
            lock([S(th * 0.4, 78, 0.03), S(th, 20, 0.12), HC + Vector((x, 0.36, -0.45)), HC + Vector((x * 0.9, 0.3, -0.55))],
                 0.1, 0.04, i)
        v, f = ellipsoid(HC + Vector((0, 0.18, -0.18)), (0.55, 0.36, 0.42), 20, 12)
        mb.add(v, f, 2)
    elif style == "coque":
        bun = S(185, 70, 0.16)
        for i in range(13):
            th = -84 + 168 * i / 12
            lock([S(th, hairline(th, style) + 1, 0.03), S(th * 0.75, 52, 0.07), S(th * 0.35, 80, 0.07), bun + Vector((0, 0, -0.08))],
                 0.05, 0.05, i, flat=0.35, mid=0.06)
        for i, th in enumerate(range(100, 270, 20)):
            lock([S(th, hairline(th, style) + 1, 0.03), S(th, 40, 0.07), bun + Vector((0, 0, -0.1))], 0.05, 0.05, i, flat=0.35)
        v, f = ellipsoid(bun, (0.2, 0.19, 0.17), 20, 12)
        mb.add(v, f, 0)
        for k in range(3):   # voltas do coque
            r = 0.2 - k * 0.04
            pts = [bun + Vector((math.cos(a) * r, math.sin(a) * r * 0.95, 0.03 + k * 0.05 - 0.04 * math.sin(a)))
                   for a in np.linspace(0.3 + k, 0.3 + k + 5.2, 9)]
            v, f = tube(pts, [0.05, 0.06, 0.003], flat=0.7, center=bun)
            mb.add(v, f, 1 + k % 2)
        for s in (-1, 1):    # mechas soltas na frente
            lock([S(s * 58, 20, 0.04), HC + Vector((s * 0.47, -0.22, -0.12)), HC + Vector((s * 0.43, -0.27, -0.33)),
                  HC + Vector((s * 0.46, -0.25, -0.42))], 0.03, 0.012, 1, flat=0.6)
    elif style == "cacheado":
        n = 0
        tries = 0
        while n < 190 and tries < 3000:
            tries += 1
            th = rnd.uniform(-180, 180)
            ph = rnd.uniform(-40, 88)
            if ph < hairline(th, style) - 6:
                continue
            if abs(th) < 55 and ph < 24:
                continue
            hgt = (ph + 40) / 128
            off = 0.06 + 0.22 * hgt * rnd.uniform(0.5, 1.0) + (0.06 if abs(th) > 60 else 0)
            c = S(th, ph, off)
            r = rnd.uniform(0.065, 0.1)
            v, f = ellipsoid(c, (r, r, r * 0.9), 10, 7)
            mb.add(v, f, (0, 1, 2, 0, 1)[n % 5])
            n += 1
        for i in range(16):   # cachos em espiral pendendo na frente e nos lados
            th = rnd.choice([-1, 1]) * rnd.uniform(25, 110)
            base = S(th, 22 if abs(th) < 60 else 0, 0.16)
            pts = [base + Vector((math.cos(a) * 0.045, math.sin(a) * 0.045, -a * 0.022)) for a in np.linspace(0, 12, 14)]
            v, f = tube(pts, [0.03, 0.03, 0.012], flat=0.9, ring=6, per=3, center=base + Vector((0, 0, 0.5)))
            mb.add(v, f, 1 if i % 2 else 0)
    elif style == "raspado":
        pass   # só a calota justa; a textura vem do material
    elif style == "rabo":
        tie = S(185, 22, 0.1)
        for i in range(13):
            th = -84 + 168 * i / 12
            lock([S(th, hairline(th, style) + 1, 0.03), S(th * 0.8, 55, 0.075), S(180 - th * 0.15, 52, 0.075), tie],
                 0.05, 0.045, i, flat=0.35, mid=0.06)
        for i, th in enumerate(range(100, 270, 22)):
            lock([S(th, hairline(th, style) + 1, 0.03), tie], 0.05, 0.045, i, flat=0.35)
        lock([S(sweep, 80, 0.03), S(-sweep * 0.5, 45, 0.12), S(-sweep * 2.5, 18, 0.1), S(-sweep * 3.6, 6, 0.08)], 0.07, 0.025, 1,
             flat=0.5)
        # rabo caindo por cima do ombro (aparece no 3/4)
        for k in range(7):
            dx = (k - 3) * 0.028
            lock([tie, tie + Vector((dx + 0.12, 0.16, -0.06)), HC + Vector((0.34 + dx, 0.34, -0.36)),
                  HC + Vector((0.5 + dx, 0.12, -0.66)), HC + Vector((0.5 + dx * 1.2, -0.3, -0.86)),
                  HC + Vector((0.44 + dx * 1.3, -0.46, -1.22 + J(0.05)))],
                 0.12, 0.04, k, flat=0.75, mid=0.14)
    return mb


# ------------------------------------------------------------------ roupa e acessórios
def ring_pts(center, radius, normal, n=16, squash=1.0):
    nrm = Vector(normal).normalized()
    a = nrm.orthogonal().normalized()
    b = nrm.cross(a)
    return [center + (a * math.cos(t) + b * math.sin(t) * squash) * radius for t in np.linspace(0, 2 * math.pi, n + 1)]


def loop_tube(center, radius, normal, r, squash=1.0, n=18):
    pts = ring_pts(center, radius, normal, n, squash)
    v, f = tube(pts, [r, r], flat=1.0, ring=8, per=3, center=center)
    return v, f


def build_body(look, rnd, top_style, skin_m, M):
    """M: dict de materiais (top, top_dk, top_lt, inner, acc...). Retorna lista de objetos."""
    objs = []
    sk = MB()
    neck_top = HC.z - 0.34
    neck_bot = HC.z - 0.95
    pts = [Vector((0, 0.03, neck_bot)), Vector((0, 0.03, neck_top))]
    v, f = tube(pts, [0.165, 0.15], flat=1.0, ring=14, per=2, center=Vector((0, 0.5, neck_top)))
    sk.add(v, f, 0)
    objs.append(sk.build("pescoco", [skin_m], outline=0.012))

    tb = MB()
    sh_z = HC.z - 1.02
    # tronco por "loft" de seções superelípticas: ombro em trapézio, não almofada
    LV = [(0.30, 0.22, 0.18), (0.24, 0.40, 0.25), (0.15, 0.57, 0.30), (0.04, 0.65, 0.33), (-0.20, 0.67, 0.35), (-1.0, 0.65, 0.34)]
    zs = [l[0] for l in LV]

    def front_y(x, zr):
        w = float(np.interp(zr, zs[::-1], [l[1] for l in LV][::-1]))
        d = float(np.interp(zr, zs[::-1], [l[2] for l in LV][::-1]))
        q = max(0.0, 1 - abs(x / w) ** 2.6)
        return 0.04 - d * q ** (1 / 2.6)

    prof = catmull([Vector(l) for l in LV], 4)
    ring = 32
    verts, faces = [], []
    for i, pr in enumerate(prof):
        zr, w, d = pr
        for k in range(ring):
            t = 2 * math.pi * k / ring
            c, sn = math.cos(t), math.sin(t)
            x = w * math.copysign(abs(c) ** (2 / 2.6), c)
            y = d * math.copysign(abs(sn) ** (2 / 2.6), sn)
            verts.append((x, 0.04 + y, sh_z + zr))
    for i in range(len(prof) - 1):
        for k in range(ring):
            a0 = i * ring + k
            b0 = i * ring + (k + 1) % ring
            faces.append((a0, a0 + ring, b0 + ring, b0))
    ci = len(verts)
    verts.append((0, 0.04, sh_z + LV[0][0]))
    for k in range(ring):
        faces.append((ci, k, (k + 1) % ring))
    tb.add(verts, faces, 0)
    # braços ao lado do tronco (o contorno separa braço e peito)
    for s in (-1, 1):
        v, f = tube([Vector((s * 0.5, -0.02, sh_z + 0.1)), Vector((s * 0.66, -0.03, sh_z - 0.02)), Vector((s * 0.76, -0.05, sh_z - 0.3)),
                     Vector((s * 0.8, -0.03, sh_z - 0.65)), Vector((s * 0.8, 0.0, sh_z - 1.1))],
                    [0.12, 0.17, 0.18, 0.18, 0.17], flat=1.0, ring=16, per=4, center=Vector((s * 0.8, -0.03, sh_z + 2)))
        tb.add(v, f, 0)
        # dobras de tecido no peito e na manga (pinceladas)
        for k, (x0, z0, ln) in enumerate(((0.3, -0.25, 0.22), (0.42, -0.48, 0.18))):
            pts = [Vector((s * x0, front_y(s * x0, z0) - 0.012, sh_z + z0)),
                   Vector((s * (x0 + 0.05), front_y(s * (x0 + 0.05), z0 - ln * 0.5) - 0.012, sh_z + z0 - ln * 0.5)),
                   Vector((s * (x0 + 0.03), front_y(s * (x0 + 0.03), z0 - ln) - 0.012, sh_z + z0 - ln))]
            v, f = tube(pts, [0.006, 0.016, 0.004], flat=0.4, ring=6, per=4, center=Vector((0, 0.5, sh_z + z0)))
            tb.add(v, f, 1)
        pts = [Vector((s * 0.66, -0.24, sh_z - 0.35)), Vector((s * 0.7, -0.255, sh_z - 0.5)), Vector((s * 0.68, -0.25, sh_z - 0.62))]
        v, f = tube(pts, [0.005, 0.014, 0.004], flat=0.4, ring=6, per=4, center=Vector((s * 0.8, 0.3, sh_z - 0.5)))
        tb.add(v, f, 1)

    acc = MB()
    if top_style == "moletom":
        # capuz amontoado atrás do pescoço + borda + cordões
        v, f = ellipsoid(Vector((0, 0.3, HC.z - 0.62)), (0.5, 0.3, 0.34), 24, 12)
        tb.add(v, f, 1)
        v, f = loop_tube(Vector((0, 0.03, neck_bot + 0.2)), 0.25, (0, 0.25, 1), 0.075, squash=0.95)
        tb.add(v, f, 2)
        for s in (-1, 1):
            p0 = Vector((s * 0.1, -0.22, neck_bot + 0.16))
            v, f = tube([p0, p0 + Vector((s * 0.01, -0.06, -0.18)), p0 + Vector((s * 0.03, -0.1, -0.36))], [0.014, 0.014], ring=6, per=4)
            acc.add(v, f, 0)
            v, f = ellipsoid(p0 + Vector((s * 0.03, -0.1, -0.4)), (0.02, 0.02, 0.045), 8, 6)
            acc.add(v, f, 1)
        for s in (-1, 1):   # ilhoses
            v, f = ellipsoid(Vector((s * 0.1, -0.23, neck_bot + 0.17)), (0.022, 0.012, 0.022), 8, 6)
            acc.add(v, f, 1)
    elif top_style == "camisa":
        v, f = loop_tube(Vector((0, 0.03, neck_bot + 0.17)), 0.19, (0, 0.2, 1), 0.035)
        tb.add(v, f, 2)
        for s in (-1, 1):   # golas pontudas
            a = Vector((s * 0.03, -0.2, neck_bot + 0.2))
            b = Vector((s * 0.2, -0.13, neck_bot + 0.26))
            c = Vector((s * 0.12, -0.31, neck_bot - 0.05))
            n = (b - a).cross(c - a).normalized() * (-s) * 0.025
            vs = [a, b, c, a + n, b + n, c + n]
            fs = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
            tb.add(vs, fs, 2)
        v, f = tube([Vector((0, front_y(0, 0.05) - 0.01, neck_bot - 0.02)), Vector((0, front_y(0, -0.7) - 0.01, sh_z - 0.7))], [0.012, 0.012], ring=6, per=2,
                    center=Vector((0, 0.3, sh_z)))
        tb.add(v, f, 1)
        for k in range(3):
            v, f = ellipsoid(Vector((0.04, front_y(0.04, -0.03 - k * 0.17) - 0.01, neck_bot - 0.1 - k * 0.17)), (0.022, 0.012, 0.022), 8, 6)
            acc.add(v, f, 1)
    elif top_style == "jaqueta":
        # camiseta por dentro (V) + gola levantada de detetive
        vs = [Vector((-0.2, front_y(0.2, 0.17) - 0.01, neck_bot + 0.1)), Vector((0.2, front_y(0.2, 0.17) - 0.01, neck_bot + 0.1)), Vector((0, front_y(0, -0.75) - 0.01, sh_z - 0.75))]
        acc.add(vs, [(0, 1, 2)], 2)
        v, f = loop_tube(Vector((0, 0.03, neck_bot + 0.14)), 0.17, (0, 0.2, 1), 0.03)
        acc.add(v, f, 2)
        for s in (-1, 1):
            a = Vector((s * 0.12, -0.24, neck_bot + 0.08))
            b = Vector((s * 0.32, 0.0, neck_bot + 0.34))
            c = Vector((s * 0.28, -0.12, neck_bot + 0.38))
            d = Vector((s * 0.06, front_y(0.06, -0.55) - 0.03, sh_z - 0.55))
            n = Vector((0, -0.03, 0))
            vs = [a, b, c, d, a + n, b + n, c + n, d + n]
            fs = [(0, 3, 1, 2), (4, 6, 5, 7), (0, 4, 7, 3), (3, 7, 5, 1), (1, 5, 6, 2), (2, 6, 4, 0)]
            tb.add(vs, fs, 2)
            v, f = tube([Vector((s * 0.06, front_y(0.06, -0.5) - 0.035, sh_z - 0.5)), Vector((s * 0.1, front_y(0.1, -0.9) - 0.035, sh_z - 0.9))], [0.01, 0.01], ring=6, per=2,
                        center=Vector((0, 0.3, sh_z)))
            tb.add(v, f, 1)
    elif top_style == "gola_alta":
        v, f = tube([Vector((0, 0.03, neck_bot + 0.05)), Vector((0, 0.03, neck_top - 0.16))], [0.21, 0.19], flat=1.0, ring=16,
                    per=2, center=Vector((0, 0.5, neck_top)))
        tb.add(v, f, 0)
        for k in range(3):
            v, f = loop_tube(Vector((0, 0.03, neck_bot + 0.1 + k * 0.1)), 0.205 - k * 0.006, (0, 0, 1), 0.03)
            tb.add(v, f, (1, 2, 1)[k])
    else:  # camiseta
        v, f = loop_tube(Vector((0, 0.03, neck_bot + 0.16)), 0.2, (0, 0.22, 1), 0.04)
        tb.add(v, f, 1)
        # emblema no peito (estrela simples) no lado da luz
        c = Vector((-0.3, front_y(-0.3, -0.38) - 0.004, sh_z - 0.38))
        pts = []
        for k in range(10):
            a = math.pi / 2 + k * math.pi / 5
            r = 0.075 if k % 2 == 0 else 0.032
            pts.append(c + Vector((math.cos(a) * r, -0.005, math.sin(a) * r)))
        vs = [c + Vector((0, -0.008, 0))] + pts
        acc.add(vs, [(0, 1 + k, 1 + (k + 1) % 10) for k in range(10)], 3)

    objs.append(tb.build("roupa", [M["top"], M["top_dk"], M["top_lt"]], outline=0.014))
    objs.append(acc.build("roupa_det", [M["cord"], M["metal"], M["inner"], M["patch"]], outline=0.008))
    return objs


def build_accessory(look, kind, M, face):
    """Acessórios presos na cabeça (giram junto). Retorna objetos."""
    mb = MB()
    objs = []
    if kind == "oculos":
        ex, ey, w, h = 0.19, -0.06, 0.112, 0.085
        for s in (-1, 1):
            pts = []
            for k in range(25):
                a = 2 * math.pi * k / 24
                x = math.copysign(abs(math.cos(a)) ** 0.6, math.cos(a)) * (w + 0.03)
                y = math.copysign(abs(math.sin(a)) ** 0.7, math.sin(a)) * (h + 0.03)
                pts.append(face.proj(s * ex + x, ey + 0.005 + y, 0.075))
            v, f = tube(pts, [0.016, 0.016], ring=6, per=2)
            mb.add(v, f, 0)
            v, f = tube([face.proj(s * (ex + w + 0.03), ey + 0.03, 0.075), S(s * 78, 2, 0.05), S(s * 96, -2, 0.04)],
                        [0.013, 0.013], ring=6, per=4)
            mb.add(v, f, 0)
            # reflexo no vidro
            for k, (du, ln) in enumerate(((-0.04, 0.06), (0.0, 0.035))):
                p0 = face.proj(s * ex + du - 0.03, ey + 0.05, 0.08)
                p1 = face.proj(s * ex + du + 0.02, ey + 0.05 - ln, 0.08)
                v, f = tube([p0, p1], [0.009, 0.009], ring=6, per=2)
                mb.add(v, f, 1)
        v, f = tube([face.proj(-ex + w * 0.75, ey + 0.05, 0.08), face.proj(0, ey + 0.07, 0.09), face.proj(ex - w * 0.75, ey + 0.05, 0.08)],
                    [0.013, 0.013], ring=6, per=4)
        mb.add(v, f, 0)
        objs.append(mb.build("oculos", [M["frame"], M["glint"]], outline=0.006))
    elif kind == "bone":
        def keep(u):
            th = math.degrees(math.atan2(u.x, -u.y))
            ph = math.degrees(math.asin(max(-1, min(1, u.z))))
            return ph >= (26 if abs(th) < 60 else (14 if abs(th) < 110 else 4))

        v, f = ellipsoid(HC + Vector((0, 0.0, 0.03)), (HA * 1.16, HB * 1.12, HCZ * 1.08), 32, 18, keep=keep,
                         deform=lambda u, p: Vector((p.x, p.y * (FRONT_FLAT if u.y < 0 else BACK_BULGE), p.z)))
        mb.add(v, f, 0)
        brim_c = S(0, 22, 0.1) + Vector((0, -0.2, -0.02))
        rot = Matrix.Rotation(math.radians(-14), 3, "X")
        v, f = ellipsoid(brim_c, (0.42, 0.3, 0.028), 24, 8, rot=rot)
        mb.add(v, f, 1)
        v, f = ellipsoid(S(0, 90, 0.11), (0.05, 0.05, 0.03), 10, 6)
        mb.add(v, f, 1)
        v, f = ellipsoid(S(0, 46, 0.12) + Vector((0, -0.02, 0)), (0.085, 0.03, 0.075), 12, 8,
                         rot=Matrix.Rotation(math.radians(30), 3, "X"))
        mb.add(v, f, 2)
        for th in (-50, 50):   # costuras dos gomos
            pts = [S(th * (1 - k / 6), 30 + k * 10, 0.14) for k in range(7)]
            v, f = tube(pts, [0.008, 0.008], ring=5, per=2)
            mb.add(v, f, 1)
        objs.append(mb.build("bone", [M["acc"], M["acc_dk"], M["patch"]], outline=0.012))
    elif kind == "brinco":
        for s in (-1, 1):
            c = Vector((s * HA * 1.0, 0.04, HC.z - 0.25))
            v, f = loop_tube(c, 0.04, (1, 0.2, 0), 0.01)
            mb.add(v, f, 0)
            v, f = ellipsoid(c + Vector((s * 0.0, 0, 0.04)), (0.015, 0.015, 0.015), 8, 6)
            mb.add(v, f, 0)
        objs.append(mb.build("brinco", [M["gold"]], outline=0.004))
    return objs


def build_neck_phones(M):
    """Fones de ouvido descansando no pescoço (jeito de adolescente)."""
    mb = MB()
    z = HC.z - 0.8
    pts = [Vector((math.sin(t) * 0.36, 0.03 + math.cos(t) * 0.33, z + 0.06 * math.cos(t))) for t in np.linspace(-1.9, 1.9, 9)]
    v, f = tube(pts, [0.035, 0.035], flat=0.7, ring=8, per=4, center=Vector((0, 0.03, z)))
    mb.add(v, f, 0)
    for s in (-1, 1):
        c = Vector((s * 0.3, -0.24, z - 0.06))
        rot = Matrix.Rotation(math.radians(-s * 35), 3, "Z") @ Matrix.Rotation(math.radians(70), 3, "X")
        v, f = ellipsoid(c, (0.13, 0.12, 0.06), 18, 10, rot=rot)
        mb.add(v, f, 0)
        n = rot @ Vector((0, 0, -1))
        v, f = loop_tube(c + n * 0.045, 0.085, n, 0.02)
        mb.add(v, f, 1)
        v, f = ellipsoid(c + n * 0.062, (0.05, 0.05, 0.012), 10, 6, rot=rot)
        mb.add(v, f, 1)
    return mb.build("fones", [M["acc"], M["patch"]], outline=0.012)


def build_scarf(M):
    mb = MB()
    z = HC.z - 0.86
    for k, (dz, r, th) in enumerate(((0.0, 0.27, 0.09), (0.12, 0.235, 0.08))):
        pts = [Vector((math.sin(t) * r, 0.03 + math.cos(t) * r * 0.95, z + dz - 0.03 * math.cos(t))) for t in np.linspace(0, 2 * math.pi, 19)]
        v, f = tube(pts, [th, th], flat=0.75, ring=10, per=3, center=Vector((0, 0.03, z + dz)))
        mb.add(v, f, 0)
        for t in np.linspace(-1.2, 1.2, 4) + k * 0.4:   # listras na volta
            c = Vector((math.sin(t) * r, 0.03 - math.cos(t) * r * 0.95, z + dz + 0.03 * math.cos(t)))
            nrm = Vector((math.cos(t), math.sin(t) * 0.95, 0)).normalized()
            v, f = loop_tube(c, th * 1.03, nrm, 0.012, squash=0.8, n=12)
            mb.add(v, f, 1)
    # duas pontas caindo à esquerda da tela, largas e achatadas, com franjinha
    for j, (x0, dx, ln) in enumerate(((-0.3, -0.06, 0.42), (-0.17, -0.01, 0.32))):
        top = Vector((x0, -0.3, z + 0.02))
        pts = [top, top + Vector((dx * 0.5, -0.06, -ln * 0.4)), top + Vector((dx, -0.08, -ln))]
        v, f = tube(pts, [0.085, 0.095, 0.09], flat=0.28, ring=10, per=4, center=top + Vector((0, 0.6, 0)))
        mb.add(v, f, j % 2)
        for q in range(5):
            b = top + Vector((dx - 0.06 + q * 0.03, -0.085, -ln - 0.01))
            v, f = tube([b, b + Vector((0, -0.005, -0.06))], [0.009, 0.006], ring=5, per=2, center=b + Vector((0, 0.5, 0)))
            mb.add(v, f, 1)
    return mb.build("cachecol", [M["acc"], M["acc_dk"]], outline=0.012)


# ------------------------------------------------------------------ montagem
TOP_STYLES = ["moletom", "camisa", "jaqueta", "gola_alta", "camiseta"]
EYE_COLORS = ["#3a2216", "#5a3a22", "#2a1c14", "#4a5a3a", "#3b5a7a", "#6a4a2a"]


def build_portrait(pid, look):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    look = dict(look)
    look["_id"] = pid
    rnd = np.random.default_rng(seeded(pid))
    import random as _r
    rr = _r.Random(seeded(pid, "r"))

    skin = lin(look.get("skin", "#c98d6b"))
    hairc = lin(look.get("hair_color", "#1c1830"))
    topc = lin(look.get("top", "#2f3d70"))
    expr_name = look.get("expression") or list(EXPR)[seeded(pid, "e") % len(EXPR)]
    ex = EXPR.get(expr_name, EXPR["serio"])
    top_style = look.get("top_style") or TOP_STYLES[seeded(pid, "t") % len(TOP_STYLES)]
    if look.get("accessory") == "cachecol" and top_style == "moletom":
        top_style = "camiseta"
    eye = lin(look.get("eye_color") or EYE_COLORS[seeded(pid, "o") % len(EYE_COLORS)])
    freckles = look.get("freckles", seeded(pid, "f") % 4 == 0)
    accessory = look.get("accessory", "nenhum")
    acc_col = lin(look["accessory_color"]) if look.get("accessory_color") else None

    # materiais
    M_SKIN = toon("pele", skin, stroke=0.12, brush=6)
    hair_stroke = 0.35 if look.get("hair") == "raspado" else 0.24
    M_HAIR = [toon("cabelo", hairc, stroke=hair_stroke, brush=14),
              toon("cabelo_claro", hairc * 1.45 + 0.004, stroke=hair_stroke, brush=14),
              toon("cabelo_escuro", hairc * 0.62, stroke=hair_stroke, brush=14)]
    lum_top = float(topc @ np.array([0.2126, 0.7152, 0.0722]))
    M = {
        "top": toon("roupa", topc, stroke=0.2, brush=6),
        "top_dk": toon("roupa_esc", topc * 0.6, stroke=0.2, brush=6),
        "top_lt": toon("roupa_clara", topc * 1.35 + 0.01, stroke=0.2, brush=6),
        "inner": toon("camiseta_dentro", lin("#d8d2c0") if lum_top < 0.25 else lin("#1d2340"), stroke=0.15),
        "cord": toon("cordao", lin("#e6e0cf"), stroke=0.1, rim=0.5),
        "metal": toon("metal", lin("#b9c3dc"), stroke=0.08),
        "patch": toon("emblema", YELLOW * 0.95, stroke=0.1, rim=0.3),
        "frame": toon("armacao", lin("#1a1c2a"), stroke=0.08),
        "glint": flat("reflexo", lin("#e8eeff"), 1.0),
        "gold": toon("ouro", YELLOW, stroke=0.08, rim=0.4),
    }
    acc_default = {"bone": "#2b3a6e", "fones": "#20263f", "cachecol": "#b8892e"}.get(accessory, "#2b3a6e")
    ac = acc_col if acc_col is not None else lin(acc_default)
    M["acc"] = toon("acessorio", ac, stroke=0.2, brush=8)
    M["acc_dk"] = toon("acessorio_esc", ac * 0.55 if accessory != "cachecol" else lin("#1d2340"), stroke=0.2, brush=8)

    fr = _r.Random(seeded(pid, "rosto"))
    FACE.update(jaw=fr.uniform(0.26, 0.42), cheek=fr.uniform(0.02, 0.07), chin=fr.uniform(0.0, 0.05), long=fr.uniform(0.96, 1.06))
    head_objs = []
    # cabeça
    hv, hf = ellipsoid(HC, (HA, HB, HCZ), 56, 36, deform=head_deform)
    hb = MB()
    hb.add(hv, hf, 0)
    face = Face(hv, hf)
    head_objs.append(hb.build("cabeca", [M_SKIN], outline=0.014))
    # orelhas
    eb = MB()
    for s in (-1, 1):
        v, f = ellipsoid(HC + Vector((s * HA * 0.96, 0.04, -0.13)), (0.06, 0.055, 0.11), 14, 10,
                         rot=Matrix.Rotation(math.radians(-s * 10), 3, "Z"))
        eb.add(v, f, 0)
    head_objs.append(eb.build("orelhas", [M_SKIN], outline=0.01))
    # nariz (volume sutil, só pega sombra)
    nb = MB()
    v, f = ellipsoid(face.proj(0.0, -0.19, -0.03), (0.05, 0.06, 0.075), 16, 10)
    nb.add(v, f, 0)
    v, f = ellipsoid(face.proj(0.0, -0.12, -0.035), (0.035, 0.05, 0.08), 12, 8)
    nb.add(v, f, 0)
    head_objs.append(nb.build("nariz", [M_SKIN], outline=0.0))

    # rosto desenhado
    skdk = skin * 0.42 + NIGHT * 0.12
    face_mats = [
        toon("olho_branco", lin("#dfe3ee"), stroke=0.05, rim=0.0, soft=True),
        flat("olho_sombra", lin("#9aa3c4") * 0.85),
        flat("iris", eye),
        flat("iris_clara", eye * 1.9 + 0.02),
        flat("pupila", lin("#07070d")),
        flat("brilho", lin("#ffffff"), 1.2),
        flat("linha", lin("#0a0b16")),
        flat("pele_escura", skdk),
        flat("boca", lin("#3b1420")),
        flat("dentes", lin("#e9e6dd")),
        flat("sobrancelha", hairc * 0.55 if float(hairc.mean()) > 0.08 else lin("#0c0a12")),
        flat("glint", lin("#ffffff")),
        flat("lingua", lin("#b0475c")),
        flat("rubor", skin * np.array([1.0, 0.55, 0.6]) * 0.9 + PINK * 0.08),
    ]
    wing = float(look.get("lashes", fr.choice([0.04, 0.08, 0.14, 0.24])))
    eyw, eyh, eyx, eyy = fr.uniform(0.098, 0.115), fr.uniform(0.072, 0.088), fr.uniform(0.18, 0.2), -0.06
    for i, s in enumerate((-1, 1)):
        draw_eye(face, s, s * eyx, eyy, eyw, eyh, ex["lid"][i], ex["lr"], (ex["gaze"][0], ex["gaze"][1]), wing=wing)
        draw_brow(face, s, s * eyx, 0.075 + (eyh - 0.08) * 0.8, ex["bL"] if s < 0 else ex["bR"])
    # nariz: traço no lado da sombra + narina
    nose = seeded(pid, "nariz") % 3
    if nose == 0:     # reto, traço longo no lado da sombra
        face.stroke([(0.035, -0.11), (0.05, -0.2), (0.035, -0.235), (0.0, -0.24)], 0.014, F_SKDK, 0.011, taper=(0.3, 0.4))
        face.stroke([(-0.045, -0.228), (-0.03, -0.236)], 0.012, F_SKDK, 0.011, taper=(0.3, 0.3))
    elif nose == 1:   # arrebitado, só a base
        face.stroke([(0.05, -0.2), (0.03, -0.228), (-0.005, -0.232)], 0.014, F_SKDK, 0.011, taper=(0.3, 0.4))
        face.circle(-0.028, -0.222, 0.008, F_SKDK, 0.011, k=8)
        face.circle(0.022, -0.222, 0.008, F_SKDK, 0.011, k=8)
    else:             # largo, asas marcadas
        face.stroke([(0.06, -0.19), (0.07, -0.22), (0.045, -0.24)], 0.013, F_SKDK, 0.011, taper=(0.3, 0.3))
        face.stroke([(-0.06, -0.19), (-0.07, -0.22), (-0.045, -0.24)], 0.011, F_SKDK, 0.011, taper=(0.3, 0.3))
        face.stroke([(-0.02, -0.245), (0.02, -0.245)], 0.01, F_SKDK, 0.011, taper=(0.4, 0.4))
    if expr_name in ("alegre", "nervoso"):   # rubor em hachura (desenho à mão)
        for s in (-1, 1):
            for k in range(3):
                x0 = s * (0.2 + k * 0.03) - 0.012
                face.stroke([(x0, -0.15), (x0 + 0.022, -0.125)], 0.01, F_BLUSH, 0.0105, taper=(0.4, 0.4))
    draw_mouth(face, ex["mouth"], mv=-0.335 * FACE["long"])
    if freckles:
        for k in range(14):
            s = -1 if k % 2 else 1
            u = s * (0.17 + rr.uniform(-0.07, 0.07))
            vv = -0.17 + rr.uniform(-0.04, 0.04)
            face.circle(u, vv, rr.uniform(0.006, 0.01), F_SKDK, 0.0105, k=6)
    head_objs.append(face.mb.build("rosto", face_mats, outline=0.0, smooth=True))

    # cabelo
    hmats = list(M_HAIR)
    hmb = build_hair(look, rr, hmats)
    head_objs.append(hmb.build("cabelo", M_HAIR, outline=0.012))
    if look.get("hair") == "raspado":
        # risco raspado na lateral (detalhe)
        sb = MB()
        pts = [S(84, 38, 0.03), S(100, 30, 0.03), S(116, 24, 0.03)]
        v, f = tube(pts, [0.009, 0.009], flat=0.4, ring=6, per=4)
        sb.add(v, f, 0)
        head_objs.append(sb.build("risco", [M_SKIN], outline=0.0))
    if look.get("hair") == "rabo":
        tb_ = MB()
        v, f = loop_tube(S(185, 22, 0.1), 0.06, (0, 1, -0.2), 0.03)
        tb_.add(v, f, 0)
        head_objs.append(tb_.build("elastico", [toon("elastico", PINK * 0.8, stroke=0.1)], outline=0.006))

    if accessory in ("oculos", "bone", "brinco"):
        head_objs += build_accessory(look, accessory, M, face)

    body_objs = build_body(look, rr, top_style, M_SKIN, M)
    if accessory == "cachecol":
        body_objs.append(build_scarf(M))
    if accessory == "fones":
        body_objs.append(build_neck_phones(M))

    # pose: cabeça gira 3/4 e inclina conforme a expressão; corpo acompanha pela metade
    yaw = look.get("yaw", -16 if seeded(pid, "y") % 3 else 12)
    pivot = Vector((0, 0.02, HC.z - 0.62))
    root_h = bpy.data.objects.new("raiz_cabeca", None)
    bpy.context.scene.collection.objects.link(root_h)
    root_h.location = pivot
    root_b = bpy.data.objects.new("raiz_corpo", None)
    bpy.context.scene.collection.objects.link(root_b)
    root_b.location = pivot
    bpy.context.view_layer.update()
    for o in head_objs:
        if o:
            o.parent = root_h
            o.matrix_parent_inverse = root_h.matrix_world.inverted()
    for o in body_objs:
        if o:
            o.parent = root_b
            o.matrix_parent_inverse = root_b.matrix_world.inverted()
    root_h.rotation_euler = (math.radians(-3), math.radians(ex["roll"]), math.radians(yaw))
    root_b.rotation_euler = (0, 0, math.radians(yaw * 0.45))

    setup_scene()
    return expr_name, top_style


class _HairRnd:
    """Adaptador: build_hair usa rnd.uniform/choice."""

    def __init__(self, r):
        self.r = r

    def uniform(self, a, b):
        return self.r.uniform(a, b)

    def choice(self, seq):
        return self.r.choice(seq)


def setup_scene():
    sc = bpy.context.scene
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 10))
    sun = bpy.context.active_object
    sun.data.color = (0.86, 0.9, 1.0)
    sun.data.energy = 3.3
    sun.data.angle = math.radians(2.0)
    d = Vector((0.62, 0.62, -0.48)).normalized()
    sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

    w = bpy.data.worlds.new("w")
    sc.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    if w.node_tree:
        bg = w.node_tree.nodes.get("Background")
        if bg:
            bg.inputs[0].default_value = rgba(lin("#2a3c78"))
            bg.inputs[1].default_value = 0.35

    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 85
    cam_d.sensor_fit = "VERTICAL"
    cam_d.sensor_height = 24
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    target = Vector((0, 0, HC.z - 0.27))
    cam.location = target + Vector((0, -7.6, 0.3))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam

    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = OUT_W * SS
    sc.render.resolution_y = OUT_H * SS
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 16
    except AttributeError:
        pass


# ------------------------------------------------------------------ pós-processo leve
def box_mean(a, r):
    k = 2 * r + 1
    pw = ((r + 1, r), (r + 1, r), (0, 0)) if a.ndim == 3 else ((r + 1, r), (r + 1, r))
    c = np.pad(a, pw, mode="edge").cumsum(0).cumsum(1)
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def kuwahara(a, r):
    lum = a @ np.array([0.299, 0.587, 0.114])
    rr = max(1, r // 2)
    m = box_mean(a, rr)
    ml = box_mean(lum, rr)
    vl = box_mean(lum ** 2, rr) - ml ** 2
    h = r // 2
    best = np.full(lum.shape, np.inf)
    out = a.copy()
    for dy in (-h, h):
        for dx in (-h, h):
            v = np.roll(np.roll(vl, dy, 0), dx, 1)
            mm = np.roll(np.roll(m, dy, 0), dx, 1)
            sel = v < best
            best[sel] = v[sel]
            out[sel] = mm[sel]
    return out


def postprocess(src, dst, seed=0):
    img = bpy.data.images.load(src)
    W, H = img.size
    px = np.empty(W * H * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    a = px.reshape(H, W, 4).astype(np.float64)       # de baixo para cima (padrão Blender)
    rgb, al = a[..., :3], a[..., 3:4]
    pre = rgb * al
    # 1) Kuwahara curto em 4x: mancha de tinta sem borrar o rosto na resolução final
    pre_k = kuwahara(pre, 4)
    al_k = al
    rgb = np.where(al_k > 0.01, pre_k / np.maximum(al_k, 1e-4), 0)
    # 2) retícula fina azul-noite só nas sombras profundas
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    yy, xx = np.mgrid[0:H, 0:W]
    cell = 10.0
    u = (xx + yy) / (cell * 1.414)
    v = (xx - yy) / (cell * 1.414)
    dist = np.sqrt((u - np.round(u)) ** 2 + (v - np.round(v)) ** 2)
    dark = np.clip((0.3 - lum) / 0.3, 0, 1)
    dots = (dist < dark ** 0.9 * 0.42)[..., None]
    inkc = np.array([8, 14, 40]) / 255
    rgb = np.where(dots, rgb * 0.55 + inkc * 0.45, rgb)
    # 3) desalinhamento rosa discreto nas bordas fortes (só por dentro da silhueta)
    g = lum
    gx = np.abs(np.roll(g, 1, 1) - np.roll(g, -1, 1))
    gy = np.abs(np.roll(g, 1, 0) - np.roll(g, -1, 0))
    e = np.clip((gx + gy - 0.35) * 1.5, 0, 1)
    e = np.roll(np.roll(e, -5, 0), 6, 1)[..., None] * (al > 0.5)
    rgb = rgb * (1 - e * 0.22) + (np.array([255, 79, 163]) / 255) * e * 0.22
    # 4) reduz 4x com média pré-multiplicada (borda limpa no alfa)
    pre = rgb * al
    h2, w2 = H // SS, W // SS
    pre = pre.reshape(h2, SS, w2, SS, 3).mean((1, 3))
    al2 = al.reshape(h2, SS, w2, SS, 1).mean((1, 3))
    rgb2 = np.where(al2 > 1e-4, pre / np.maximum(al2, 1e-4), 0)
    # 5) grão de papel leve
    r = np.random.default_rng(seed)
    rgb2 = rgb2 + r.normal(0, 0.018, (h2, w2, 1))
    out = np.concatenate([np.clip(rgb2, 0, 1), np.clip(al2, 0, 1)], axis=2).astype(np.float32)
    save_rgba(out, dst)
    return out


def save_rgba(arr, path):
    h, w, _ = arr.shape
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    im.pixels.foreach_set(arr.astype(np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


# ------------------------------------------------------------------ folha de contato
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
    "_": "000000000000111", ".": "000000000000010", "-": "000000111000000", " ": "000000000000000",
    "/": "001001010100100",
}


def text_td(img, x, y, s, color, sc=2):
    for ch in s.upper():
        g = FONT.get(ch, FONT[" "])
        for i, b in enumerate(g):
            if b == "1":
                r, c = divmod(i, 3)
                img[y + r * sc:y + (r + 1) * sc, x + c * sc:x + (c + 1) * sc, :3] = color
                img[y + r * sc:y + (r + 1) * sc, x + c * sc:x + (c + 1) * sc, 3] = 1
        x += 4 * sc


def contact_sheet(items, path, cols=4, zoom=2):
    """items: [(id, legenda, arr de baixo-para-cima)]."""
    cw, ch = OUT_W * zoom, OUT_H * zoom
    pad, lab = 16, 22
    rows = (len(items) + cols - 1) // cols
    W = cols * cw + (cols + 1) * pad
    H = rows * (ch + lab) + (rows + 1) * pad
    sheet = np.zeros((H, W, 4))
    sheet[..., :3] = np.array([6, 12, 31]) / 255
    sheet[..., 3] = 1
    card = np.array([22, 34, 74]) / 255
    for i, (pid, cap_, arr) in enumerate(items):
        r, c = divmod(i, cols)
        x0 = pad + c * (cw + pad)
        y0 = pad + r * (ch + lab + pad)
        td = arr[::-1]
        up = td.repeat(zoom, 0).repeat(zoom, 1)
        a = up[..., 3:4]
        sheet[y0:y0 + ch, x0:x0 + cw, :3] = up[..., :3] * a + card * (1 - a)
        text_td(sheet, x0 + 4, y0 + ch + 5, f"{pid} - {cap_}", np.array([255, 200, 61]) / 255)
    save_rgba(sheet[::-1].astype(np.float32), path)


# ------------------------------------------------------------------ entrada
def load_people(path):
    data = json.load(open(path, encoding="utf-8"))
    people = []
    if isinstance(data, list):
        for e in data:
            if "look" in e:
                people.append((e["id"], e["look"]))
        return people
    cards = data.get("cards") or data.get("cartas") or []
    for c in cards:
        if c.get("kind") != "pessoa":
            continue
        look = c.get("look") or c.get("visual") or c.get("retrato")
        if not look:
            print("AVISO: pessoa sem look:", c.get("id"))
            continue
        people.append((c["id"], look))
    return people


def main():
    if len(ARGS) < 2:
        print(__doc__)
        return
    src, out_dir = os.path.abspath(ARGS[0]), os.path.abspath(ARGS[1])
    sheet = os.path.abspath(ARGS[ARGS.index("--folha") + 1]) if "--folha" in ARGS else None
    only = ARGS[ARGS.index("--so") + 1] if "--so" in ARGS else None
    os.makedirs(out_dir, exist_ok=True)
    people = load_people(src)
    tmp = os.path.join(bpy.app.tempdir or os.environ.get("TEMP", "."), "rumor_portrait_raw.png")
    items = []
    for pid, look in people:
        if only and pid != only:
            continue
        expr, top = build_portrait(pid, look)
        sc = bpy.context.scene
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        dst = os.path.join(out_dir, f"{pid}.png")
        arr = postprocess(tmp, dst, seed=seeded(pid))
        items.append((pid, f"{look.get('hair')} {expr}", arr))
        print("RETRATO OK", dst, expr, top)
    if sheet and items:
        os.makedirs(os.path.dirname(sheet), exist_ok=True)
        contact_sheet(items, sheet)
        print("FOLHA OK", sheet)


main()
