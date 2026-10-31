"""PERSONAGEM BASE estudante do RUMOR (para o auto-rig do Mixamo), reprodutível.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
        --python tools/blender/character_kit.py -- [--tiles <pasta>] [--no-render]

Faz tudo: (1) chama character_faces.py para desenhar os atlas de rosto, (2) modela, (3) exporta
game/assets/characters/base_tpose.fbx (Mixamo: cm, sem armature, sem animação, texturas embutidas) e
base_tpose.glb (teste no Godot), (4) troca os materiais por toon só na prévia, renderiza as capturas
em Eevee e (5) monta docs/arte_exploracao/personagem_base.png.

Convenções: metros, Z para cima, origem nos pés, frente para -Y (vira +Z no glTF/Godot), braço
esquerdo do personagem em +X. T-pose: braços na horizontal (altura do ombro z = 1.155), pernas
levemente afastadas, dedos juntos e polegar separado (palma para baixo, polegar para a frente).

Malhas (cada uma com um material; Hair_rabo e Hair_coque têm o elástico em M_acc):
  Body (M_skin: cabeça, orelhas, nariz, pescoço, mãos), Top (M_top), Pants (M_pants), Shoes (M_shoes),
  Face_eyes (M_face_eyes), Face_mouth (M_face_mouth), Hair_* (M_hair), Acc_* (M_acc).
Zonas de UV (opcional no Godot): em M_top e M_shoes, UV.x < 0.5 = zona A (tecido / cabedal) e
UV.x >= 0.5 = zona B (barra, punho, cordão / sola, biqueira, cadarço, meia). A textura *_zones.png
embutida já pinta as duas zonas; um shader pode usar mix(cor_a, cor_b, step(0.5, UV.x)).
Rosto: o UV de Face_eyes/Face_mouth cobre exatamente a célula (0,0) do atlas 4x2 (canto superior
esquerdo da imagem). No Godot: uv + cell / vec2(4, 2) (game/shaders/face_atlas.gdshader).
"""
import math
import os
import random
import subprocess
import sys

import bpy
from mathutils import Vector as V
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "characters")
DOCS = os.path.join(ROOT, "docs", "arte_exploracao")
FACES = os.path.join(ROOT, "tools", "blender", "character_faces.py")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TILES = ARGS[ARGS.index("--tiles") + 1] if "--tiles" in ARGS else os.path.join(
    os.environ.get("TEMP", OUT), "rumor_char_tiles")
DO_RENDER = "--no-render" not in ARGS

TAU = 2 * math.pi
ZA = (0.02, 0.48)          # zona A do UV
ZB = (0.52, 0.98)          # zona B do UV
ARM_Z = 1.155              # altura dos braços na T-pose
C = V((0.0, 0.015, 1.43))  # centro da cabeça (referência do cabelo)
HEAD_S = (1.10, 1.05)      # cabeça mais larga que a tabela (cara de animação); orelhas/acessórios seguem
HAND_S = 1.25              # mãos maiores (estilizado)


# ================================================================== construtor de malha
class MB:
    """Acumula vértices, faces, UV por canto e índice de material; vira um objeto no fim."""

    def __init__(self):
        self.v, self.f, self.uv, self.m = [], [], [], []

    def vert(self, p):
        self.v.append(V(p))
        return len(self.v) - 1

    def face(self, idx, uvs, mat=0):
        self.f.append(list(idx))
        self.uv.append(list(uvs))
        self.m.append(mat)

    def loft(self, rings, cap0=True, cap1=True, zone=ZA, mat=0, closed=False, tip0=None, tip1=None):
        R, n = len(rings), len(rings[0])
        u0, u1 = zone
        ids = [[self.vert(p) for p in r] for r in rings]
        segs = R if closed else R - 1
        for i in range(segs):
            a, b = ids[i], ids[(i + 1) % R]
            va, vb = i / max(1, segs), (i + 1) / max(1, segs)
            for j in range(n):
                j2 = (j + 1) % n
                ua, ub = u0 + (u1 - u0) * j / n, u0 + (u1 - u0) * (j + 1) / n
                self.face([a[j], a[j2], b[j2], b[j]], [(ua, va), (ub, va), (ub, vb), (ua, vb)], mat)
        if not closed:
            for r_ids, tip, cap, vv in ((ids[0], tip0, cap0, 0.0), (ids[-1], tip1, cap1, 1.0)):
                if not cap:
                    continue
                c = V(tip) if tip is not None else sum((self.v[k] for k in r_ids), V()) / n
                ci = self.vert(c)
                um = (u0 + u1) / 2
                for j in range(n):
                    j2 = (j + 1) % n
                    self.face([ci, r_ids[j2], r_ids[j]],
                              [(um, vv), (u0 + (u1 - u0) * (j + 1) / n, vv), (u0 + (u1 - u0) * j / n, vv)], mat)
        return ids

    def grid(self, pts, zone=ZA, mat=0):
        """pts[i][j] -> quads (superfície aberta)."""
        u0, u1 = zone
        ids = [[self.vert(p) for p in row] for row in pts]
        R, K = len(pts), len(pts[0])
        for i in range(R - 1):
            for j in range(K - 1):
                uvs = [(u0 + (u1 - u0) * j / (K - 1), i / (R - 1)), (u0 + (u1 - u0) * (j + 1) / (K - 1), i / (R - 1)),
                       (u0 + (u1 - u0) * (j + 1) / (K - 1), (i + 1) / (R - 1)), (u0 + (u1 - u0) * j / (K - 1), (i + 1) / (R - 1))]
                self.face([ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]], uvs, mat)
        return ids

    def merge(self, other):
        off = len(self.v)
        self.v += other.v
        self.f += [[k + off for k in f] for f in other.f]
        self.uv += other.uv
        self.m += other.m

    def bvh(self):
        return BVHTree.FromPolygons([tuple(p) for p in self.v], self.f)

    def mirrored_x(self):
        o = MB()
        o.v = [V((-p.x, p.y, p.z)) for p in self.v]
        o.f = [list(reversed(f)) for f in self.f]
        o.uv = [list(reversed(u)) for u in self.uv]
        o.m = list(self.m)
        return o


def ring(c, U, W, rxp, rxn, ryp, ryn, n, ex=2.0, a0=0.0):
    """Anel superelíptico no plano (U, W); raios diferentes em cada semi-eixo."""
    pts = []
    for j in range(n):
        a = a0 + TAU * j / n
        ca, sa = math.cos(a), math.sin(a)
        rx = rxp if ca >= 0 else rxn
        ry = ryp if sa >= 0 else ryn
        x = math.copysign(abs(ca) ** (2 / ex), ca) * rx
        y = math.copysign(abs(sa) ** (2 / ex), sa) * ry
        pts.append(V(c) + U * x + W * y)
    return pts


def catmull(pts, k):
    pts = [V(p) for p in pts]
    if len(pts) == 2:
        return [pts[0].lerp(pts[1], i / (k - 1)) for i in range(k)]
    P = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    segs = len(pts) - 1
    out = []
    for i in range(k):
        t = i / (k - 1) * segs
        s = min(int(t), segs - 1)
        u = t - s
        p0, p1, p2, p3 = P[s], P[s + 1], P[s + 2], P[s + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    return out


def tube_rings(pts, radii, n, up_fn, ex=2.0, a0=0.0):
    """Anéis ao longo de um caminho. radii[i] = (largura, espessura); a espessura segue `up`."""
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            T = pts[1] - pts[0]
        elif i == len(pts) - 1:
            T = pts[-1] - pts[-2]
        else:
            T = pts[i + 1] - pts[i - 1]
        T = T.normalized()
        up = up_fn(p, i)
        N = up - T * up.dot(T)
        if N.length < 1e-6:
            N = T.orthogonal()
        N.normalize()
        B = T.cross(N)
        rx, ry = radii[i]
        rings.append(ring(p, B, N, rx, rx, ry, ry, n, ex, a0))
    return rings


def wobble(rings, amp, seed):
    """Tremido de tecido: desloca vértices um pouco (nada de cilindro perfeito de CG)."""
    rng = random.Random(seed)
    for r in rings:
        for p in r:
            p += V((rng.uniform(-amp, amp), rng.uniform(-amp, amp), rng.uniform(-amp, amp)))
    return rings


def lerp(a, b, t):
    return a + (b - a) * t


def table_interp(table, x):
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x0 <= x <= x1:
            t = (x - x0) / (x1 - x0)
            t = t * t * (3 - 2 * t)
            return lerp(y0, y1, t)
    return table[-1][1] if x > table[-1][0] else table[0][1]


# ================================================================== materiais (exportação)
def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


BASE_COLORS = {
    "M_skin": "#c98d6b", "M_top": "#6b7aa6", "M_pants": "#2a3558", "M_shoes": "#3a3f52",
    "M_hair": "#2a2026", "M_acc": "#8a90a0", "M_face_eyes": "#ffffff", "M_face_mouth": "#ffffff",
}
ZONE_B = {"M_top": "#4a5680", "M_shoes": "#ece4d0"}
MATS = {}


def zone_image(name, a, b):
    img = bpy.data.images.new(name, 32, 8, alpha=False)
    ca, cb = srgb(a), srgb(b)
    px = []
    for y in range(8):
        for x in range(32):
            c = ca if x < 16 else cb
            # pixels guardam sRGB; srgb() devolve linear, então reconverte
            px += [lin2s(c[0]), lin2s(c[1]), lin2s(c[2]), 1.0]
    img.pixels[:] = px
    path = os.path.join(OUT, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def lin2s(x):
    return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


def make_materials():
    for name, col in BASE_COLORS.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = srgb(col)
        bsdf.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        img = None
        if name in ZONE_B:
            img = zone_image(name.lower()[2:] + "_zones", col, ZONE_B[name])
        elif name == "M_face_eyes":
            img = bpy.data.images.load(os.path.join(OUT, "eyes_atlas.png"))
        elif name == "M_face_mouth":
            img = bpy.data.images.load(os.path.join(OUT, "mouth_atlas.png"))
        if img is not None:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = img
            tex.interpolation = "Closest" if name in ZONE_B else "Linear"
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            if name.startswith("M_face"):
                nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
                m.surface_render_method = "DITHERED"
                try:
                    m.blend_method = "CLIP"
                except Exception:
                    pass
        MATS[name] = m


def build(name, mb, mats, sharp_deg=48):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in mb.v], [], [tuple(f) for f in mb.f])
    uvl = me.uv_layers.new(name="UVMap")
    for pi, poly in enumerate(me.polygons):
        for k, li in enumerate(poly.loop_indices):
            uvl.data[li].uv = mb.uv[pi][k]
        poly.material_index = mb.m[pi]
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # garante normal para fora em cada ilha (vale para superfícies abertas, como a calota do cabelo)
    seen = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        isl, stack = [], [f]
        seen.add(f.index)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        cen = sum((g.calc_center_median() for g in isl), V()) / len(isl)
        s = sum(g.normal.dot(g.calc_center_median() - cen) * g.calc_area() for g in isl)
        if s < 0:
            for g in isl:
                g.normal_flip()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(sharp_deg))
    except Exception:
        pass
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(MATS[m])
    return ob


# ================================================================== corpo
def head_mb():
    """Cabeça estilizada: crânio grande, queixo pequeno, frente achatada para o rosto pintado."""
    Z0 = 1.27
    # dz, cy, rx, r_frente, r_trás
    T = [(0.000, -0.058, 0.044, 0.022, 0.030), (0.015, -0.052, 0.066, 0.036, 0.050),
         (0.040, -0.038, 0.090, 0.060, 0.076), (0.075, -0.021, 0.113, 0.085, 0.100),
         (0.110, -0.008, 0.128, 0.100, 0.118), (0.150, 0.000, 0.138, 0.108, 0.135),
         (0.190, 0.006, 0.144, 0.109, 0.148), (0.230, 0.012, 0.145, 0.104, 0.155),
         (0.265, 0.016, 0.139, 0.096, 0.150), (0.293, 0.018, 0.124, 0.083, 0.132),
         (0.315, 0.018, 0.098, 0.064, 0.104), (0.328, 0.018, 0.060, 0.038, 0.064)]
    X, Y = V((1, 0, 0)), V((0, -1, 0))
    sx, sy = HEAD_S
    rings = [ring((0, cy * sy, Z0 + dz), X, Y, rx * sx, rx * sx, rf * sy, rb * sy, 20, 2.35)
             for dz, cy, rx, rf, rb in T]
    mb = MB()
    mb.loft(rings, tip0=(0, -0.045, Z0 - 0.004), tip1=(0, 0.018, Z0 + 0.333))
    return mb


def ellipsoid(mb, c, r, n=8, rows=5, rot=None, zone=ZA, mat=0, jitter=0.0, seed=0):
    rng = random.Random(seed)
    rings = []
    for i in range(1, rows):
        e = -math.pi / 2 + math.pi * i / rows
        rr = []
        for j in range(n):
            a = TAU * j / n
            p = V((math.cos(a) * math.cos(e) * r[0], math.sin(a) * math.cos(e) * r[1], math.sin(e) * r[2]))
            if jitter:
                p *= 1 + rng.uniform(-jitter, jitter)
            if rot is not None:
                p = rot @ p
            rr.append(V(c) + p)
        rings.append(rr)
    bot, top = V((0, 0, -r[2])), V((0, 0, r[2]))
    if rot is not None:
        bot, top = rot @ bot, rot @ top
    mb.loft(rings, tip0=V(c) + bot, tip1=V(c) + top, zone=zone, mat=mat)


def hand_mb():
    """Mão esquerda (+X). Palma para baixo, dedos juntos, polegar para a frente (-Y)."""
    mb = MB()
    U, W = V((0, -1, 0)), V((0, 0, 1))
    z = ARM_Z - 0.004
    wr = [ring((x, 0.0, z), U, W, ry, ry, rz, rz, 8) for x, ry, rz in
          ((0.600, 0.031, 0.026), (0.640, 0.029, 0.023), (0.672, 0.033, 0.022))]
    mb.loft(wr)
    palm = [ring((x, 0.002, z + dz), U, W, ry, ry, rzu, rzd, 10, 3.0) for x, ry, rzu, rzd, dz in
            ((0.655, 0.036, 0.021, 0.019, 0.0), (0.690, 0.046, 0.025, 0.019, 0.001),
             (0.722, 0.048, 0.023, 0.017, 0.0), (0.742, 0.045, 0.019, 0.015, -0.002))]
    mb.loft(palm)
    # dedos: indicador (frente) ... mínimo (trás); levemente curvados para baixo
    for y, L, r in ((-0.031, 0.072, 0.0118), (-0.0105, 0.080, 0.0122), (0.0105, 0.075, 0.0118), (0.030, 0.060, 0.0108)):
        x0 = 0.722 if abs(y) < 0.02 else 0.716
        ctrl = [V((x0, y, z)), V((x0 + L * 0.45, y, z - 0.002)), V((x0 + L * 0.85, y, z - 0.009)),
                V((x0 + L, y, z - 0.016))]
        pts = catmull(ctrl, 5)
        rad = [(r, r * 0.92), (r, r * 0.9), (r * 0.95, r * 0.86), (r * 0.85, r * 0.8), (r * 0.6, r * 0.55)]
        rings = tube_rings(pts[:-1], rad[:-1], 6, lambda p, i: V((0, 0, 1)))
        mb.loft(rings, tip1=pts[-1] + V((0.003, 0, 0.002)))
    # polegar
    ctrl = [V((0.664, -0.030, z - 0.004)), V((0.690, -0.056, z - 0.007)), V((0.716, -0.071, z - 0.010)),
            V((0.738, -0.078, z - 0.012))]
    pts = catmull(ctrl, 5)
    rad = [(0.016, 0.014), (0.015, 0.013), (0.0135, 0.012), (0.011, 0.010), (0.006, 0.006)]
    rings = tube_rings(pts[:-1], rad[:-1], 6, lambda p, i: V((0, 0, 1)))
    mb.loft(rings, tip1=pts[-1])
    return mb


def body_mb():
    mb = head_mb()
    # orelhas (inclinadas para trás) com concha interna
    for s in (1, -1):
        from mathutils import Euler
        rot = Euler((0, math.radians(-8 * s), math.radians(-14 * s)), "XYZ").to_matrix()
        ellipsoid(mb, (s * 0.141 * HEAD_S[0], 0.022, 1.405), (0.013, 0.027, 0.037), 8, 5, rot)
    # nariz de botão + ponte
    ellipsoid(mb, (0, -0.106, 1.372), (0.018, 0.016, 0.015), 8, 4)
    ellipsoid(mb, (0, -0.101, 1.392), (0.010, 0.012, 0.024), 6, 4)
    # pescoço
    U, W = V((1, 0, 0)), V((0, -1, 0))
    neck = [ring((0, 0.022, z), U, W, 0.046, 0.046, 0.042, 0.046, 10) for z in (1.19, 1.27, 1.345)]
    mb.loft(neck)
    h = hand_mb()
    piv = V((0.60, 0.0, ARM_Z))
    h.v = [piv + (p - piv) * HAND_S for p in h.v]
    mb.merge(h)
    mb.merge(h.mirrored_x())
    return mb


def torso_rings():
    X, Y = V((1, 0, 0)), V((0, -1, 0))
    T = [(0.800, 0.000, 0.158, 0.100, 0.098), (0.860, 0.000, 0.151, 0.097, 0.094),
         (0.940, 0.000, 0.146, 0.095, 0.092), (1.020, 0.000, 0.152, 0.098, 0.096),
         (1.090, 0.000, 0.162, 0.101, 0.100), (1.140, 0.003, 0.166, 0.097, 0.100),
         (1.180, 0.006, 0.150, 0.084, 0.090), (1.210, 0.010, 0.110, 0.068, 0.074),
         (1.228, 0.012, 0.072, 0.054, 0.060)]
    return [ring((0, cy, z), X, Y, rx, rx, rf, rb, 16, 2.6) for z, cy, rx, rf, rb in T]


def conform_slab(mb, bvh, corners_fn, nx, nz, off_out, off_in, zone, ray_dir=V((0, 1, 0))):
    """Placa colada numa superfície (bolso, aplique): projeta uma grade na direção ray_dir."""
    top, bot = [], []
    for i in range(nz + 1):
        rt, rb = [], []
        for j in range(nx + 1):
            p = corners_fn(j / nx, i / nz)
            hit = bvh.ray_cast(p - ray_dir * 0.5, ray_dir)
            q = hit[0] if hit[0] is not None else p
            nrm = (hit[1] if hit[1] is not None else -ray_dir).normalized()
            if nrm.dot(ray_dir) > 0:
                nrm = -nrm
            nrm = (nrm - ray_dir).normalized()
            rt.append(q + nrm * off_out)
            rb.append(q + nrm * off_in)
        top.append(rt)
        bot.append(rb)
    a = mb.grid(top, zone)
    b = mb.grid(bot, zone)
    # laterais
    border = [(0, j) for j in range(nx + 1)] + [(i, nx) for i in range(1, nz + 1)] + \
             [(nz, j) for j in range(nx - 1, -1, -1)] + [(i, 0) for i in range(nz - 1, 0, -1)]
    u = (zone[0] + zone[1]) / 2
    for k in range(len(border)):
        i0, j0 = border[k]
        i1, j1 = border[(k + 1) % len(border)]
        mb.face([a[i0][j0], a[i1][j1], b[i1][j1], b[i0][j0]], [(u, 0), (u, 0), (u, 1), (u, 1)])


def top_mb():
    mb = MB()
    tr = wobble(torso_rings(), 0.0025, 3)
    torso = MB()
    torso.loft(tr, tip1=(0, 0.012, 1.234))
    bvh = torso.bvh()
    mb.merge(torso)
    X, Y = V((1, 0, 0)), V((0, -1, 0))
    # barra elástica
    hem = [ring((0, 0.0, z), X, Y, rx, rx, rf, rb, 16, 2.6) for z, rx, rf, rb in
           ((0.783, 0.156, 0.098, 0.096), (0.788, 0.165, 0.106, 0.104), (0.828, 0.163, 0.104, 0.102),
            (0.834, 0.154, 0.097, 0.095))]
    mb.loft(hem, zone=ZB)
    # mangas largas + punhos
    U, W = V((0, -1, 0)), V((0, 0, 1))
    for s in (1, -1):
        sl = [ring((s * x, 0.0, zc), U, W, ry * 1.13, ry * 1.13, rz * 1.13, rz * 1.13, 12) for x, ry, rz, zc in
              ((0.100, 0.062, 0.064, 1.158), (0.170, 0.066, 0.068, 1.157), (0.250, 0.058, 0.059, 1.155),
               (0.340, 0.052, 0.052, 1.154), (0.420, 0.050, 0.048, 1.153), (0.500, 0.053, 0.050, 1.152),
               (0.565, 0.054, 0.051, 1.152), (0.600, 0.049, 0.046, 1.152))]
        mb.loft(wobble(sl, 0.0025, 10 + s))
        cf = [ring((s * x, 0.0, ARM_Z - 0.003), U, W, r * 1.1, r * 1.1, r * 1.05, r * 1.05, 12) for x, r in
              ((0.594, 0.040), (0.600, 0.044), (0.636, 0.043), (0.642, 0.039))]
        mb.loft(cf, zone=ZB)
    # capuz caído: rolo da abertura em volta do pescoço (zona B = forro) ...
    pts = []
    for i in range(13):
        th = math.radians(-150 + 300 * i / 12)
        pts.append(V((math.sin(th) * 0.104, 0.02 + math.cos(th) * 0.086, 1.214 + 0.014 * math.cos(th))))
    rad = []
    for i in range(13):
        t = abs(i - 6) / 6
        rad.append((0.031 * (1 - 0.55 * t ** 2), 0.026 * (1 - 0.5 * t ** 2)))
    rings = tube_rings(pts, rad, 8, lambda p, i: V((0, 0, 1)))
    mb.loft(rings, zone=ZB)
    # ... e o saco do capuz deitado nas costas
    X2, Y2 = V((1, 0, 0)), V((0, 1, 0))
    bag = [ring((0, cy, z), X2, Y2, rx, rx, ryo, ryi, 12, 2.4) for z, cy, rx, ryo, ryi in
           ((1.228, 0.092, 0.100, 0.040, 0.03), (1.195, 0.116, 0.120, 0.052, 0.03),
            (1.135, 0.126, 0.118, 0.050, 0.03), (1.075, 0.126, 0.098, 0.040, 0.028),
            (1.025, 0.121, 0.064, 0.028, 0.024))]
    mb.loft(wobble(bag, 0.002, 21), tip1=(0, 0.113, 0.992))
    # cordões (zona B) descendo pelo peito, um mais comprido que o outro
    for s, zend, wig in ((1, 1.030, 0.006), (-1, 1.062, -0.004)):
        pts = []
        for i in range(8):
            t = i / 7
            z = lerp(1.196, zend, t)
            x = s * (0.036 + 0.006 * t) + wig * math.sin(t * 3.0)
            hit = bvh.ray_cast(V((x, -0.6, z)), V((0, 1, 0)))
            p = hit[0] if hit[0] is not None else V((x, -0.11, z))
            pts.append(p + V((0, -0.0075 - 0.004 * t, 0)))
        rings = tube_rings(pts, [(0.0055, 0.0055)] * 8, 5, lambda p, i: V((0, -1, 0)))
        mb.loft(rings, zone=ZB)
        d = (pts[-1] - pts[-2]).normalized()
        a0, a1 = pts[-1], pts[-1] + d * 0.024
        rings = tube_rings([a0, a0.lerp(a1, 0.5), a1], [(0.0075, 0.0075)] * 3, 6, lambda p, i: V((0, -1, 0)))
        mb.loft(rings, zone=ZB)
    # bolso canguru (trapézio com aberturas inclinadas nas laterais)
    def pocket(u, v):
        z = lerp(0.835, 0.965, v)
        half = lerp(0.112, 0.082, v)
        return V((lerp(-half, half, u), -0.3, z))
    conform_slab(mb, bvh, pocket, 6, 3, 0.010, 0.002, ZA)
    return mb


def pants_mb():
    mb = MB()
    X, Y = V((1, 0, 0)), V((0, -1, 0))
    pel = [ring((0, 0.004, z), X, Y, rx, rx, rf, rb, 16, 2.4) for z, rx, rf, rb in
           ((0.700, 0.146, 0.090, 0.096), (0.760, 0.146, 0.090, 0.094), (0.880, 0.132, 0.082, 0.084))]
    mb.loft(pel)
    for s in (1, -1):
        L = [(0.80, 0.082), (0.70, 0.078), (0.60, 0.069), (0.50, 0.062), (0.42, 0.058), (0.34, 0.058),
             (0.26, 0.057), (0.20, 0.059), (0.172, 0.058)]
        rings = []
        for z, r in L:
            t = (0.80 - z) / 0.63
            cx = s * lerp(0.082, 0.106, t)
            cy = -0.006 * math.sin(t * math.pi)
            rings.append(ring((cx, cy, z), X, Y, r * 1.08, r * 1.08, r * 1.05, r * 1.08, 12))
        mb.loft(wobble(rings, 0.002, 30 + s))
        cx = s * 0.106
        cuff = [ring((cx, 0.0, z), X, Y, r * 1.08, r * 1.08, r * 1.08, r * 1.08, 12) for z, r in
                ((0.160, 0.059), (0.165, 0.065), (0.208, 0.065), (0.213, 0.060))]
        mb.loft(cuff, zone=ZB)
    return mb


def shoe_mb():
    """Tênis esquerdo (+X), parrudo: sola clara (zona B), cabedal (zona A), biqueira, cadarço, meia."""
    mb = MB()
    cx = 0.108
    U, W = V((1, 0, 0)), V((0, 0, 1))
    # sola
    SO = [(0.070, 0.036), (0.062, 0.050), (0.035, 0.056), (-0.020, 0.052), (-0.080, 0.058),
          (-0.130, 0.058), (-0.160, 0.050), (-0.178, 0.030)]
    rings = []
    for y, w in SO:
        lift = max(0.0, (-0.10 - y)) * 0.18
        rings.append(ring((cx, y, 0.018 + lift), U, W, w, w, 0.019, 0.018, 10, 4.0))
    mb.loft([[p.copy() for p in r] for r in rings], zone=ZB)
    # cabedal
    UP = [(0.064, 0.036, 0.100), (0.050, 0.045, 0.124), (0.020, 0.047, 0.122), (-0.020, 0.048, 0.110),
          (-0.060, 0.049, 0.090), (-0.100, 0.048, 0.072), (-0.135, 0.044, 0.061), (-0.158, 0.034, 0.053),
          (-0.170, 0.020, 0.046)]
    rings = []
    for y, w, h in UP:
        lift = max(0.0, (-0.10 - y)) * 0.18
        base = 0.036 + lift
        rings.append(ring((cx, y, base), U, W, w, w, h - base, 0.004, 10, 2.4))
    mb.loft(rings, zone=ZA)
    upper = MB()
    upper.loft(rings)
    ubvh = upper.bvh()
    # biqueira de borracha (zona B) por cima do bico
    TO = [(-0.105, 0.050, 0.060), (-0.135, 0.047, 0.056), (-0.158, 0.037, 0.050), (-0.174, 0.022, 0.044)]
    rings = []
    for y, w, h in TO:
        lift = max(0.0, (-0.10 - y)) * 0.18
        base = 0.034 + lift
        rings.append(ring((cx, y, base), U, W, w, w, h - base, 0.004, 10, 2.4))
    mb.loft(rings, zone=ZB)
    # cadarços: três barrinhas sobre o peito do pé
    for y in (-0.012, -0.036, -0.060):
        conform_slab(mb, ubvh, lambda u, v, y=y: V((cx + lerp(-0.026, 0.026, u), y + lerp(-0.006, 0.006, v), 0.5)),
                     3, 1, 0.006, 0.0, ZB, ray_dir=V((0, 0, -1)))
    # lingueta (zona A) saindo da boca do tênis
    conform_slab(mb, ubvh, lambda u, v: V((cx + lerp(-0.022, 0.022, u), lerp(0.008, 0.030, v), 0.5)),
                 2, 2, 0.012, 0.0, ZA, ray_dir=V((0, 0, -1)))
    # meia (zona B)
    X, Y = V((1, 0, 0)), V((0, -1, 0))
    sock = [ring((cx - 0.002, 0.018, z), X, Y, 0.042, 0.042, 0.040, 0.042, 10) for z in (0.090, 0.130, 0.185)]
    mb.loft(sock, zone=ZB)
    return mb


# ================================================================== rosto
def decal(name, mat, bvh, x0, x1, z0, z1, nx, nz, off=0.0028):
    mb = MB()
    pts = []
    for i in range(nz + 1):
        row = []
        z = lerp(z0, z1, i / nz)
        for j in range(nx + 1):
            x = lerp(x0, x1, j / nx)
            hit = bvh.ray_cast(V((x, -0.6, z)), V((0, 1, 0)))
            if hit[0] is None:
                hit = bvh.ray_cast(V((x, -0.6, z)), (V((0, 0.02, 1.36)) - V((x, -0.6, z))).normalized())
            hn = hit[1].normalized()
            if hn.y > 0:            # a normal do BVH segue o sentido das faces: garante 'para fora'
                hn = -hn
            n = (hn + V((0, -1, 0))).normalized()
            row.append(hit[0] + n * off)
        pts.append(row)
    ids = [[mb.vert(p) for p in row] for row in pts]
    # UV cobre a célula (0,0): u 0..0.25, v 0.5..1 (Blender, v=1 é o topo da imagem)
    for i in range(nz):
        for j in range(nx):
            uv = lambda jj, ii: (0.25 * jj / nx, 0.5 + 0.5 * ii / nz)
            mb.face([ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]],
                    [uv(j, i), uv(j + 1, i), uv(j + 1, i + 1), uv(j, i + 1)])
    me_ob = build(name, mb, [mat])
    # decalque aberto: força a normal para a frente (-Y)
    me = me_ob.data
    if sum(p.normal.y for p in me.polygons) > 0:
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        for f in bm.faces:
            f.normal_flip()
        bm.to_mesh(me)
        bm.free()
    return me_ob


# ================================================================== cabelo
HEAD_BVH = None


def hdir(az, el):
    a, e = math.radians(az), math.radians(el)
    return V((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def surf(az, el, lift=0.0):
    d = hdir(az, el)
    hit = HEAD_BVH.ray_cast(C + d * 0.6, -d)
    p = hit[0] if hit[0] is not None else C + d * 0.15
    return p + d * lift


def hp(az, el, lift=0.0, zt=None, out=0.0):
    """Ponto no couro cabeludo (azimute 0 = frente, 90 = lado esquerdo +X; elevação em graus).
    zt: altura absoluta (cabelo caindo abaixo da cabeça); out: empurra para fora na horizontal."""
    p = surf(az, el, lift)
    h = V((math.sin(math.radians(az)), -math.cos(math.radians(az)), 0))
    if zt is not None:
        p.z = zt
    return p + h * out


def hairline(front=56, temple=44, side=10, back=-30):
    def f(az):
        a = abs(((az + 180) % 360) - 180)
        return table_interp([(0, front), (35, temple), (70, side + 8), (95, side), (135, (side + back) / 2),
                             (180, back)], a)
    return f


def hair_cap(mb, hl, lo=0.010, hi=0.022, n=20, rows=8, mat=0):
    rings = [[surf(360 * j / n, hl(360 * j / n) - 2, 0.002) for j in range(n)]]
    for r in range(rows):
        t = r / (rows - 1)
        rings.append([surf(360 * j / n, lerp(hl(360 * j / n), 84, t), lerp(lo, hi, t)) for j in range(n)])
    mb.loft(rings, cap0=False, tip1=surf(0, 90, hi), mat=mat)


def outward(p, i):
    d = p - C
    return d.normalized() if d.length > 1e-6 else V((0, 0, 1))


def lock(mb, ctrl, w0, w1, k=5, n=6, thick=0.42, up=outward, bulge=0.3, mat=0, blunt=False):
    """Mecha: tubo achatado (lente) que afina até a ponta. ctrl: tuplas de hp() ou Vectors."""
    P = [c if isinstance(c, V) else hp(*c) for c in ctrl]
    pts = catmull(P, k)
    rad = []
    for i in range(k):
        t = i / (k - 1)
        w = lerp(w0, w1, t) * (1 + bulge * math.sin(math.pi * t))
        rad.append((w, w * thick))
    if blunt:
        rings = tube_rings(pts, rad, n, up)
        mb.loft(rings, mat=mat)
    else:
        rings = tube_rings(pts[:-1], rad[:-1], n, up)
        mb.loft(rings, tip1=pts[-1], mat=mat)


def puff(mb, c, r, seed, n=6, mat=0):
    """Cacho: bolinha irregular low-poly."""
    rng = random.Random(seed)
    rings = []
    for e in (-0.55, 0.0, 0.55):
        rr = []
        for j in range(n):
            a = TAU * j / n + e
            k = r * (1 + rng.uniform(-0.18, 0.18))
            rr.append(c + V((math.cos(a) * math.cos(e) * k, math.sin(a) * math.cos(e) * k, math.sin(e) * k * 0.9)))
        rings.append(rr)
    mb.loft(rings, tip0=c + V((0, 0, -r * 0.9)), tip1=c + V((0, 0, r * (0.95 + rng.uniform(0, 0.2)))), mat=mat)


def torus(mb, c, axis, R, r, n=10, m=5, mat=0):
    axis = V(axis).normalized()
    u = axis.orthogonal().normalized()
    w = axis.cross(u)
    pts = [V(c) + (u * math.cos(TAU * i / n) + w * math.sin(TAU * i / n)) * R for i in range(n)]
    rings = []
    for i, p in enumerate(pts):
        radial = (p - V(c)).normalized()
        rings.append(ring(p, radial, axis, r, r, r, r, m))
    mb.loft(rings, closed=True, mat=mat)


def spiral(mb, top, length, R, turns, w, seed, mat=0):
    pts = []
    for i in range(14):
        t = i / 13
        a = TAU * turns * t + seed
        pts.append(top + V((math.cos(a) * R, math.sin(a) * R, -length * t)))
    rad = [(w * (1 - 0.5 * i / 13), w * (1 - 0.5 * i / 13)) for i in range(14)]
    rings = tube_rings(pts[:-1], rad[:-1], 5, lambda p, i: V((0, 0, 1)))
    mb.loft(rings, tip1=pts[-1], mat=mat)


def hair_curto():
    mb, rng = MB(), random.Random(11)
    hl = hairline(56, 44, 10, -30)
    hair_cap(mb, hl, 0.010, 0.022)
    # topo bagunçado, varrido para a frente e para o lado esquerdo
    for i in range(8):
        ea = -62 + i * 17 + rng.uniform(-5, 5)
        ee = 51 + rng.uniform(-2, 4) if abs(ea) < 45 else hl(ea) + 6
        lock(mb, [(180 + rng.uniform(-25, 25), 66, 0.012), (ea * 0.5, 86, 0.032), (ea + 6, 70, 0.038),
                  (ea + 12, ee, 0.030)], 0.046, 0.014)
    # laterais e nuca em camadas
    for az in range(56, 305, 25):
        lock(mb, [(az, 74, 0.012), (az + 8, 50, 0.028), (az + 12, hl(az) + 12, 0.024),
                  (az + 15, hl(az) - 3, 0.012)], 0.052, 0.012)
    # franja de lado
    for k, (a0, a1) in enumerate(((-34, 30), (-14, 46), (-48, 12))):
        lock(mb, [(a0 - 10, 82, 0.016), (a0, 72, 0.040), (a1 - 8, 60, 0.042), (a1, 47 + 3 * k, 0.03)],
             0.05, 0.016, k=6)
    # redemoinho espetado na coroa
    for k in range(3):
        a = 160 + k * 22
        lock(mb, [(a, 66, 0.014), (a + 10, 74, 0.05), (a + 22, 64, 0.075)], 0.036, 0.01, k=4)
    return mb


def hair_longo():
    mb = MB()
    hl = hairline(56, 42, 8, -30)
    hair_cap(mb, hl, 0.010, 0.020)
    for s in (1, -1):
        for az, zt, w in ((56, 1.33, 0.05), (74, 1.27, 0.055), (90, 1.25, 0.06), (115, 1.22, 0.06),
                          (140, 1.12, 0.062), (163, 1.09, 0.06)):
            a = s * az
            lock(mb, [(s * 12, 86, 0.012), (s * az * 0.6, 68, 0.030), (a, 32, 0.036), (a, 2, 0.038, None, 0.006),
                      (a, -12, 0.034, (1.42 + zt) / 2, 0.022), (a, -12, 0.026, zt, 0.030)], w, 0.016, k=7)
    for az in (178, 196):
        lock(mb, [(az, 80, 0.012), (az, 40, 0.034), (az, 0, 0.038), (az, -25, 0.034, 1.25, 0.02),
                  (az, -25, 0.026, 1.07, 0.02)], 0.065, 0.02, k=7)
    # mechas que emolduram o rosto, saindo da risca
    for s in (1, -1):
        lock(mb, [(s * 8, 84, 0.014), (s * 28, 70, 0.032), (s * 62, 50, 0.028), (s * 76, 18, 0.020),
                  (s * 78, 0, 0.016, 1.36, 0.01)], 0.05, 0.014, k=7)
    for az in (100, 260, 180):
        lock(mb, [(az, 84, 0.016), (az, 60, 0.036), (az, 30, 0.03)], 0.07, 0.03, k=4)
    return mb


def hair_coque():
    mb = MB()
    hl = hairline(58, 46, 12, -28)
    hair_cap(mb, hl, 0.010, 0.016)
    bun_c = hp(180, 58, 0.050)
    for az in range(-150, 151, 30):
        if abs(az) < 70:
            ctrl = [(az, hl(az) + 3, 0.007), (az * 0.4, 84, 0.016), (180 - az * 0.25, 70, 0.02), bun_c]
        else:
            ctrl = [(az, hl(az) + 3, 0.007), (az + math.copysign(25, az), 48, 0.016),
                    (180 - (180 - abs(az)) * 0.3 * math.copysign(1, az), 56, 0.022), bun_c]
        lock(mb, ctrl, 0.05, 0.02, thick=0.3, bulge=0.1)
    ellipsoid(mb, bun_c + V((0, 0.01, 0.01)), (0.056, 0.05, 0.05), 10, 6, jitter=0.08, seed=4)
    # volta torcida em volta do coque
    pts = []
    for i in range(12):
        a = TAU * 1.1 * i / 11
        pts.append(bun_c + V((math.cos(a) * 0.05, 0.012 + math.sin(a) * 0.046, 0.015 + 0.03 * math.sin(a * 0.5))))
    lock(mb, pts, 0.02, 0.008, k=12, thick=0.7, up=lambda p, i: (p - bun_c).normalized())
    torus(mb, bun_c + V((0, -0.022, -0.012)), (0, 0.6, -0.8), 0.04, 0.011, 12, 5, mat=1)
    # fios soltos nas têmporas
    for s in (1, -1):
        lock(mb, [(s * 40, 54, 0.012), (s * 50, 36, 0.024), (s * 56, 16, 0.02, None, 0.006),
                  (s * 58, 0, 0.014, 1.36, 0.016), (s * 60, 0, 0.012, 1.33, 0.006)], 0.02, 0.006, k=7, thick=0.6)
    return mb


def hair_cacheado():
    mb = MB()
    hl = hairline(58, 44, 10, -30)
    hair_cap(mb, hl, 0.016, 0.034)
    golden = math.pi * (3 - math.sqrt(5))
    count = 0
    for i in range(50):
        y = 1 - (i / 49) * 1.3
        if y < -0.3:
            break
        az = math.degrees((i * golden) % TAU) - 180
        el = math.degrees(math.asin(max(-1, min(1, y))))
        if el < hl(az) + 4:
            continue
        r = 0.052 + 0.010 * (el > 35) + 0.006 * math.sin(i * 1.7)
        puff(mb, surf(az, el, 0.028 + 0.02 * (el > 50)), r, i, n=8)
        count += 1
    # dois cachinhos em mola caindo na testa
    for s, az in ((1, 18), (-1, -26)):
        spiral(mb, surf(az, 56, 0.02), 0.07, 0.012, 2.2, 0.011, s)
    return mb


def hair_raspado():
    mb, rng = MB(), random.Random(5)
    hl = hairline(56, 44, 12, -32)
    hair_cap(mb, hl, 0.012, 0.013)
    # topete curto em cima (laterais raspadas)
    for i, (az, el) in enumerate([(a, e) for e in (60, 74) for a in range(-150, 181, 30)]):
        a = az + rng.uniform(-6, 6)
        lock(mb, [(a, el, 0.008), (a * 0.85, el + 7, 0.026), (a * 0.7, el + 12, 0.024)], 0.042, 0.014, k=4)
    for a in (-24, 0, 24):
        lock(mb, [(a, 66, 0.01), (a + 4, 62, 0.03), (a + 8, 56, 0.03)], 0.045, 0.016, k=4)
    return mb


def hair_franja():
    mb = MB()
    hl = hairline(56, 42, 6, -30)
    hair_cap(mb, hl, 0.012, 0.024)
    for a in range(-48, 49, 16):
        lock(mb, [(a * 0.3, 86, 0.016), (a, 70, 0.036), (a * 1.05, 52, 0.032)], 0.05, 0.04, k=4, blunt=True)
    for az in list(range(58, 181, 20)) + list(range(-58, -181, -20)):
        lock(mb, [(az * 0.5, 84, 0.014), (az, 52, 0.036), (az, 8, 0.042, None, 0.004),
                  (az, -12, 0.036, 1.345, 0.018), (az, -12, 0.022, 1.31, 0.0)], 0.056, 0.018, k=6)
    return mb


def hair_rabo():
    mb = MB()
    hl = hairline(56, 44, 12, -30)
    hair_cap(mb, hl, 0.010, 0.017)
    tie = hp(180, 26, 0.018)
    for az in range(-150, 151, 30):
        if abs(az) < 70:
            ctrl = [(az, hl(az) + 3, 0.008), (az * 0.5, 84, 0.016), (180 - az * 0.3, 52, 0.016), tie]
        else:
            ctrl = [(az, hl(az) + 3, 0.008), (az + math.copysign(30, az), 34, 0.014),
                    (180 - (180 - abs(az)) * 0.3 * math.copysign(1, az), 28, 0.014), tie]
        lock(mb, ctrl, 0.05, 0.022, thick=0.3, bulge=0.1)
    torus(mb, tie + V((0, 0.012, 0)), (0, 1, 0.15), 0.022, 0.009, 10, 5, mat=1)
    # rabo de cavalo em 5 mechas com balanço
    for k, (dx, dy, w) in enumerate(((0, 0, 0.05), (0.022, 0.006, 0.04), (-0.022, 0.006, 0.04),
                                     (0.01, -0.012, 0.036), (-0.012, 0.014, 0.034))):
        b = tie + V((dx * 0.3, 0.02, 0))
        ctrl = [b, b + V((dx * 0.6, 0.08 + dy, 0.0)), b + V((dx, 0.13 + dy, -0.09)),
                b + V((dx * 1.4 + 0.012, 0.12 + dy, -0.2)), b + V((dx * 1.6 + 0.03, 0.10 + dy, -0.27))]
        lock(mb, ctrl, w, 0.012, k=7, thick=0.6, up=lambda p, i: V((0, 1, 0.2)))
    for s in (1, -1):
        lock(mb, [(s * 10, 76, 0.014), (s * 26, 64, 0.03), (s * 48, 52, 0.026)], 0.045, 0.012, k=4)
    return mb


HAIRS = {"curto": hair_curto, "longo": hair_longo, "coque": hair_coque, "cacheado": hair_cacheado,
         "raspado": hair_raspado, "franja": hair_franja, "rabo": hair_rabo}


# ================================================================== acessórios
def acc_oculos():
    mb = MB()
    zc, yf = 1.432, -0.132
    for s in (1, -1):
        cx = s * 0.047
        pts = []
        for i in range(16):
            a = TAU * i / 16
            x, z = math.cos(a), math.sin(a)
            x = math.copysign(abs(x) ** 0.7, x) * 0.036
            z = math.copysign(abs(z) ** 0.7, z) * 0.028
            pts.append(V((cx + x, yf + 0.006 * (x / 0.036) * s * -1 + 0.004 * abs(x) / 0.036, zc + z)))
        rings = []
        for i, p in enumerate(pts):
            T = (pts[(i + 1) % 16] - pts[i - 1]).normalized()
            N = V((0, -1, 0))
            B = T.cross(N)
            rings.append(ring(p, B, N, 0.0055, 0.0055, 0.0045, 0.0045, 4, 2.0, math.pi / 4))
        mb.loft(rings, closed=True)
        # haste até a orelha
        a = V((s * 0.083, yf + 0.004, zc + 0.012))
        ctrl = [a, V((s * 0.140, yf + 0.04, zc + 0.012)), V((s * 0.150, -0.01, zc + 0.006)), V((s * 0.150, 0.03, zc - 0.012)),
                V((s * 0.146, 0.05, zc - 0.034))]
        pts = catmull(ctrl, 7)
        mb.loft(tube_rings(pts, [(0.004, 0.006)] * 7, 4, lambda p, i: V((0, 0, 1)), a0=math.pi / 4))
    pts = catmull([V((-0.014, yf - 0.002, zc + 0.012)), V((0, yf - 0.004, zc + 0.018)), V((0.014, yf - 0.002, zc + 0.012))], 5)
    mb.loft(tube_rings(pts, [(0.004, 0.004)] * 5, 4, lambda p, i: V((0, -1, 0)), a0=math.pi / 4))
    return mb


def acc_bone():
    mb = MB()
    from mathutils import Euler
    rot = Euler((math.radians(-8), 0, 0), "XYZ").to_matrix()
    c = V((0, 0.012, 1.478))
    rings = []
    for i in range(6):
        e = math.radians(90 * i / 6)
        rr = []
        for j in range(16):
            a = TAU * j / 16
            ry = 0.136 if math.sin(a) < 0 else 0.186
            p = V((math.cos(a) * 0.176 * math.cos(e), math.sin(a) * ry * math.cos(e), math.sin(e) * 0.158))
            rr.append(c + rot @ p)
        rings.append(rr)
    mb.loft(rings, cap0=True, tip1=c + rot @ V((0, 0, 0.160)))
    # aba curva para a frente (placa com espessura)
    top, bot = [], []
    for i in range(4):
        t = i / 3
        rt, rb = [], []
        for j in range(9):
            u = -1 + 2 * j / 8
            ang = u * math.radians(62)
            r0 = 0.136
            depth = lerp(0.0, 0.082 * math.cos(u * 1.15), t)
            x = math.sin(ang) * (0.172 + depth * 0.4)
            y = -math.cos(ang) * (r0 + 0.004) - depth
            z = -0.002 - depth * 0.22 - 0.012 * (u * u) * t
            p = c + rot @ V((x, y, z))
            rt.append(p + V((0, 0, 0.005)))
            rb.append(p - V((0, 0, 0.004)))
        top.append(rt)
        bot.append(rb)
    a = mb.grid(top)
    b = mb.grid(bot)
    R, K = 4, 9
    border = [(0, j) for j in range(K)] + [(i, K - 1) for i in range(1, R)] + \
             [(R - 1, j) for j in range(K - 2, -1, -1)] + [(i, 0) for i in range(R - 2, 0, -1)]
    for k in range(len(border)):
        i0, j0 = border[k]
        i1, j1 = border[(k + 1) % len(border)]
        mb.face([a[i0][j0], a[i1][j1], b[i1][j1], b[i0][j0]], [(0.5, 0)] * 4)
    ellipsoid(mb, c + rot @ V((0, 0, 0.160)), (0.014, 0.014, 0.008), 6, 3)
    return mb


def _tmp_loft(rings):
    m = MB()
    m.loft(rings)
    return m


def acc_fones():
    mb = MB()
    pts = []
    for i in range(13):
        f = math.radians(-82 + 164 * i / 12)
        pts.append(V((math.sin(f) * 0.186, 0.012, 1.425 + math.cos(f) * 0.228)))
    mb.loft(tube_rings(pts, [(0.013, 0.0075)] * 13, 6, lambda p, i: (p - V((0, 0.012, 1.425))).normalized()))
    for s in (1, -1):
        U, W = V((0, -1, 0)), V((0, 0, 1))
        rings = [ring((s * x, 0.016, 1.408), U, W, r * 0.92, r * 0.92, r, r, 12) for x, r in
                 ((0.150, 0.040), (0.156, 0.047), (0.176, 0.049), (0.190, 0.042), (0.194, 0.030))]
        mb.loft(rings)
        # garfo ligando a concha ao arco
        mb.loft(tube_rings([V((s * 0.182, 0.012, 1.46)), V((s * 0.186, 0.012, 1.43)), V((s * 0.184, 0.014, 1.41))],
                           [(0.006, 0.006)] * 3, 4, lambda p, i: V((0, -1, 0))))
    return mb


def acc_cachecol():
    mb = MB()
    pts = []
    for i in range(16):
        th = TAU * i / 16
        pts.append(V((math.sin(th) * 0.112, 0.012 - math.cos(th) * 0.104, 1.236 + 0.022 * math.cos(th))))
    rings = []
    for i, p in enumerate(pts):
        T = (pts[(i + 1) % 16] - pts[i - 1]).normalized()
        rad = (p - V((0, 0.012, p.z)))
        rad.z = 0
        rad.normalize()
        N = rad
        B = T.cross(N)
        r = 0.032 + 0.006 * math.sin(i * 1.3)
        rings.append(ring(p, B, N, r * 0.95, r * 0.95, r * 0.9, r * 0.9, 8))
    mb.loft(wobble(rings, 0.003, 9), closed=True)
    # duas pontas caindo na frente, uma por cima da outra
    for k, (x0, zend, sw) in enumerate(((0.05, 0.99, 0.02), (0.075, 1.04, -0.01))):
        ctrl = [V((x0, -0.112 - 0.012 * k, 1.21)), V((x0 + 0.008, -0.13 - 0.012 * k, 1.15)),
                V((x0 + sw, -0.128 - 0.01 * k, 1.08)), V((x0 + sw * 1.5, -0.122 - 0.01 * k, zend))]
        pts = catmull(ctrl, 6)
        rings = tube_rings(pts, [(0.034, 0.008)] * 6, 6, lambda p, i: V((0, -1, 0)))
        mb.loft(rings)
        # franjas na ponta
        e = pts[-1]
        for f in range(4):
            x = e.x - 0.024 + 0.016 * f
            mb.loft(tube_rings([V((x, e.y, e.z + 0.004)), V((x, e.y, e.z - 0.022))], [(0.0045, 0.003)] * 2, 4,
                               lambda p, i: V((0, -1, 0))))
    return mb


def acc_brinco():
    mb = MB()
    torus(mb, (0.149, 0.018, 1.366), (1, 0, 0.2), 0.009, 0.0024, 10, 4)
    return mb


ACCS = {"oculos": acc_oculos, "bone": acc_bone, "fones": acc_fones, "cachecol": acc_cachecol, "brinco": acc_brinco}


# ================================================================== montagem e exportação
def build_all():
    global HEAD_BVH
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    head = head_mb()
    HEAD_BVH = head.bvh()
    objs = {}
    objs["Body"] = build("Body", body_mb(), ["M_skin"])
    objs["Top"] = build("Top", top_mb(), ["M_top"])
    objs["Pants"] = build("Pants", pants_mb(), ["M_pants"])
    sh = shoe_mb()
    sh.merge(sh.mirrored_x())
    objs["Shoes"] = build("Shoes", sh, ["M_shoes"])
    objs["Face_eyes"] = decal("Face_eyes", "M_face_eyes", HEAD_BVH, -0.105, 0.105, 1.335, 1.545, 8, 6)
    objs["Face_mouth"] = decal("Face_mouth", "M_face_mouth", HEAD_BVH, -0.05, 0.05, 1.272, 1.372, 6, 5)
    for k, fn in HAIRS.items():
        objs["Hair_" + k] = build("Hair_" + k, fn(), ["M_hair", "M_acc"], sharp_deg=180)
    for k, fn in ACCS.items():
        mb = fn()
        if k != "cachecol":
            mb.v = [V((p.x * HEAD_S[0], C.y + (p.y - C.y) * HEAD_S[1], p.z)) for p in mb.v]
        objs["Acc_" + k] = build("Acc_" + k, mb, ["M_acc"])
    # remove slots de material não usados (Hair_* sem elástico ficam só com M_hair)
    for ob in objs.values():
        used = {p.material_index for p in ob.data.polygons}
        if len(ob.data.materials) > 1 and used == {0}:
            ob.data.materials.pop(index=1)
    return objs


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def export(objs):
    os.makedirs(OUT, exist_ok=True)
    for ob in bpy.data.objects:
        ob.select_set(True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "base_tpose.fbx"), use_selection=False,
                             object_types={"MESH"}, apply_scale_options="FBX_SCALE_ALL", global_scale=1.0,
                             axis_forward="-Z", axis_up="Y", bake_anim=False, add_leaf_bones=False,
                             path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE",
                             use_mesh_modifiers=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "base_tpose.glb"), export_format="GLB",
                              export_yup=True, export_apply=True, export_animations=False)


# ================================================================== prévia (toon Eevee)
def sk(node, name, out=False):
    """Socket colorido do nó Mix (ele tem várias entradas com o mesmo nome, uma por tipo)."""
    socks = node.outputs if out else node.inputs
    for x in socks:
        if x.name == name and x.type == "RGBA":
            return x
    return socks[name]


def toon_preview(objs):
    """Troca os materiais por toon de 3 faixas com sombra azulada (só para a captura)."""
    ink = bpy.data.materials.new("M_outline_preview")
    ink.use_nodes = True
    nt = ink.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = srgb("#070a1a")
    nt.links.new(e.outputs[0], o.inputs[0])
    ink.use_backface_culling = True
    handles = {}
    for name, m in MATS.items():
        img = None
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                img = n.image
        nt = m.node_tree
        nt.nodes.clear()
        L = nt.links.new
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
        s2r = nt.nodes.new("ShaderNodeShaderToRGB")
        L(diff.outputs[0], s2r.inputs[0])
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        L(s2r.outputs[0], bw.inputs[0])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.interpolation = "CONSTANT"
        cr.elements[0].position = 0.0
        cr.elements[0].color = (0.30, 0.36, 0.66, 1)
        cr.elements[1].position = 0.10
        cr.elements[1].color = (0.62, 0.68, 0.90, 1)
        e3 = cr.elements.new(0.30)
        e3.color = (1.0, 0.98, 0.94, 1)
        L(bw.outputs[0], ramp.inputs[0])
        base = nt.nodes.new("ShaderNodeMix")
        base.data_type = "RGBA"
        sk(base, "A").default_value = srgb(BASE_COLORS[name])
        sk(base, "B").default_value = srgb(ZONE_B.get(name, BASE_COLORS[name]))
        uv = nt.nodes.new("ShaderNodeUVMap")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        L(uv.outputs[0], sep.inputs[0])
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = "GREATER_THAN"
        gt.inputs[1].default_value = 0.5
        L(sep.outputs[0], gt.inputs[0])
        L(gt.outputs[0], base.inputs["Factor"])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        L(ramp.outputs["Color"], sk(mul, "A"))
        em = nt.nodes.new("ShaderNodeEmission")
        mapping = None
        if name.startswith("M_face"):
            mapping = nt.nodes.new("ShaderNodeMapping")
            L(uv.outputs[0], mapping.inputs["Vector"])
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = img
            L(mapping.outputs[0], tex.inputs["Vector"])
            # tinta do rosto quase sem sombra
            mix_l = nt.nodes.new("ShaderNodeMix")
            mix_l.data_type = "RGBA"
            mix_l.inputs["Factor"].default_value = 0.75
            sk(mix_l, "B").default_value = (1, 1, 1, 1)
            L(ramp.outputs["Color"], sk(mix_l, "A"))
            L(sk(mix_l, "Result", True), sk(mul, "A"))
            L(tex.outputs["Color"], sk(mul, "B"))
            L(sk(mul, "Result", True), em.inputs["Color"])
            tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            ms = nt.nodes.new("ShaderNodeMixShader")
            gt2 = nt.nodes.new("ShaderNodeMath")
            gt2.operation = "GREATER_THAN"
            gt2.inputs[1].default_value = 0.5
            L(tex.outputs["Alpha"], gt2.inputs[0])
            L(gt2.outputs[0], ms.inputs[0])
            L(tr.outputs[0], ms.inputs[1])
            L(em.outputs[0], ms.inputs[2])
            L(ms.outputs[0], out.inputs[0])
            m.surface_render_method = "DITHERED"
        else:
            L(sk(base, "Result", True), sk(mul, "B"))
            L(sk(mul, "Result", True), em.inputs["Color"])
            L(em.outputs[0], out.inputs[0])
        handles[name] = (base, mapping)
    for name, ob in objs.items():
        if name.startswith("Face_"):
            continue
        ob.data.materials.append(ink)
        md = ob.modifiers.new("outline", "SOLIDIFY")
        md.thickness = 0.0045 if (name.startswith("Hair") or name.startswith("Acc")) else 0.006
        md.offset = 1.0
        md.use_flip_normals = True
        md.use_rim = False
        md.material_offset = len(ob.data.materials) - 1
    return handles


def set_look(handles, objs, look):
    for name, (base, mapping) in handles.items():
        if name in look.get("colors", {}):
            a = look["colors"][name]
            sk(base, "A").default_value = srgb(a[0])
            sk(base, "B").default_value = srgb(a[1] if len(a) > 1 else a[0])
    for name, ob in objs.items():
        if name.startswith("Hair_"):
            ob.hide_render = name != "Hair_" + look.get("hair", "curto")
        elif name.startswith("Acc_"):
            ob.hide_render = name[4:] not in look.get("acc", [])
    for key, cell in (("M_face_eyes", look.get("eyes", (0, 0))), ("M_face_mouth", look.get("mouth", (0, 0)))):
        mp = handles[key][1]
        # mesmo deslocamento que o Godot faz (uv + cell/grid), aqui com v do Blender (para baixo = -v)
        mp.inputs["Location"].default_value = (cell[0] * 0.25, -cell[1] * 0.5, 0)


def setup_scene():
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = srgb("#26407a")
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    sc.world = w
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(52), math.radians(-18), math.radians(-28))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def aim(cam, target, az, el, dist, lens=None, ortho=None):
    t = V(target)
    d = hdir(az, el)
    cam.location = t + d * dist
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens or 50


def render(name, w, h):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.filepath = os.path.join(TILES, name + ".png")
    bpy.ops.render.render(write_still=True)


LOOKS = {
    "v1": {"hair": "curto", "acc": ["fones"], "eyes": (1, 0), "mouth": (1, 0),
           "colors": {"M_skin": ["#8d5a3c"], "M_top": ["#ffc83d", "#d99a1c"], "M_pants": ["#26407a"],
                      "M_shoes": ["#1d2238", "#ece4d0"], "M_hair": ["#1a1418"], "M_acc": ["#e8ecf4"]}},
    "v2": {"hair": "rabo", "acc": ["oculos", "brinco"], "eyes": (0, 1), "mouth": (1, 1),
           "colors": {"M_skin": ["#f0c4a4"], "M_top": ["#4e6fc0", "#2c4280"], "M_pants": ["#1a1d2e"],
                      "M_shoes": ["#e9e6dc", "#c94a4a"], "M_hair": ["#7a3b22"], "M_acc": ["#1b2650"]}},
    "v3": {"hair": "cacheado", "acc": ["cachecol"], "eyes": (2, 0), "mouth": (3, 0),
           "colors": {"M_skin": ["#5a3424"], "M_top": ["#2b3a66", "#ffc83d"], "M_pants": ["#5d6478"],
                      "M_shoes": ["#ffc83d", "#f2eee2"], "M_hair": ["#2a1c22"], "M_acc": ["#ffc83d"]}},
}


def render_previews(objs):
    os.makedirs(TILES, exist_ok=True)
    handles = toon_preview(objs)
    cam = setup_scene()
    mid = V((0, 0, 0.82))
    set_look(handles, objs, LOOKS["v1"])
    aim(cam, mid, 0, 4, 6, ortho=1.86)
    render("front_v1", 720, 720)
    for k in ("v1", "v2", "v3"):
        set_look(handles, objs, LOOKS[k])
        aim(cam, mid + V((0, 0, 0.0)), 34, 12, 6, lens=55)
        cam.data.lens = 48
        aim(cam, mid + V((0.04, 0, 0.02)), 34, 10, 3.3, lens=50)
        render("q34_" + k, 720, 720)
        aim(cam, V((0, -0.02, 1.43)), 24, 6, 1.25, lens=70)
        render("face_" + k, 720, 720)
    set_look(handles, objs, LOOKS["v2"])
    aim(cam, mid + V((0, 0, 0.1)), 160, 14, 3.9, lens=50)
    render("back_v2", 720, 720)
    base = dict(LOOKS["v1"])
    base["acc"] = []
    base["eyes"], base["mouth"] = (0, 0), (0, 0)
    base["colors"] = dict(base["colors"], M_hair=["#5b3426"], M_skin=["#b07850"])
    for k in HAIRS:
        lk = dict(base, hair=k)
        set_look(handles, objs, lk)
        aim(cam, V((0, 0.03, 1.42)), 48, 10, 1.55, lens=70)
        render("hair_" + k, 400, 400)
    lk = dict(LOOKS["v2"], hair="raspado", acc=["bone", "brinco"], eyes=(3, 0), mouth=(2, 1))
    set_look(handles, objs, lk)
    aim(cam, V((0, 0.0, 1.43)), 38, 8, 1.6, lens=70)
    render("hair_acessorios", 400, 400)


def main():
    subprocess.run(["python", FACES, "atlas"], check=True)
    objs = build_all()
    total, rep = 0, []
    for name, ob in sorted(objs.items()):
        t = tri_count(ob)
        total += t
        rep.append(f"{name:16s} {t:6d}  {[m.name for m in ob.data.materials]}")
    print("\n".join(rep))
    print("TOTAL arquivo", total)
    export(objs)
    if DO_RENDER:
        render_previews(objs)
        subprocess.run(["python", FACES, "sheet", TILES], check=True)


main()
