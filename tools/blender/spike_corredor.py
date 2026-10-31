"""ESBOÇO DESCARTÁVEL de direção de arte: corredor da escola à noite (noir azul + luz amarela).

Objetivo: provar que dá pra chegar num visual de "pintura" estilo Aranhaverso só com Blender,
sem IA de imagem. Técnica: sombreamento em faixas (Shader to RGB -> rampa constante) com ruído
quebrando a borda das faixas (cara de pincelada), contorno de tinta por casco invertido, luz da lua
atravessando o caixilho da janela e a luz amarela do celular como acento. O pós-processo
(`spike_post.py`) aplica filtro Kuwahara (tinta), retícula nas sombras e desalinhamento de impressão.

blender --background --factory-startup --python tools/blender/spike_corredor.py -- <saida.png>
"""
import math
import sys

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//corredor.png"


def hexc(h, a=1.0):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    # sRGB -> linear: a rampa e a cor base trabalham em linear no Blender
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (*c, a)


# ---------------------------------------------------------------- materiais
_mats = {}

SHADOW = hexc("#0b1533")
MIDSH = hexc("#2a3f78")


def toon(name, base, stroke=0.18, brush_scale=7.0, emit=None, emit_str=0.0):
    """Material 'pintado': faixas de luz + pincelada de ruído + tinta azul na sombra."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    N.clear()
    out = N.new("ShaderNodeOutputMaterial")
    diff = N.new("ShaderNodeBsdfDiffuse")
    s2r = N.new("ShaderNodeShaderToRGB")
    L.new(diff.outputs[0], s2r.inputs[0])
    bw = N.new("ShaderNodeRGBToBW")
    L.new(s2r.outputs["Color"], bw.inputs[0])

    # pincelada: ruído esticado num eixo desloca o valor de luz antes da faixa
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (brush_scale, brush_scale * 0.35, brush_scale)
    L.new(tc.outputs["Object"], mp.inputs[0])
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.0
    nz.inputs["Detail"].default_value = 6.0
    nz.inputs["Roughness"].default_value = 0.65
    L.new(mp.outputs[0], nz.inputs["Vector"])
    sub = N.new("ShaderNodeMath"); sub.operation = "SUBTRACT"; sub.inputs[1].default_value = 0.5
    L.new(nz.outputs["Fac"], sub.inputs[0])
    mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = stroke
    L.new(sub.outputs[0], mul.inputs[0])
    add = N.new("ShaderNodeMath"); add.operation = "ADD"; add.use_clamp = True
    L.new(bw.outputs[0], add.inputs[0]); L.new(mul.outputs[0], add.inputs[1])

    # faixas: sombra profunda azul -> meio-tom azul -> luz -> realce
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    el = ramp.color_ramp.elements
    el[0].position = 0.0; el[0].color = SHADOW
    el[1].position = 0.06; el[1].color = MIDSH
    e = el.new(0.22); e.color = (0.62, 0.68, 0.86, 1)
    e = el.new(0.55); e.color = (1.0, 1.0, 1.0, 1)
    e = el.new(0.95); e.color = (1.35, 1.3, 1.2, 1)
    L.new(add.outputs[0], ramp.inputs[0])

    # matiz da luz que chega (amarelo do celular, azul da lua) sem a intensidade
    mx = N.new("ShaderNodeMath"); mx.operation = "MAXIMUM"; mx.inputs[1].default_value = 0.03
    L.new(bw.outputs[0], mx.inputs[0])
    inv = N.new("ShaderNodeMath"); inv.operation = "DIVIDE"; inv.inputs[0].default_value = 1.0
    L.new(mx.outputs[0], inv.inputs[1])
    hue = N.new("ShaderNodeVectorMath"); hue.operation = "SCALE"
    L.new(s2r.outputs["Color"], hue.inputs[0]); L.new(inv.outputs[0], hue.inputs["Scale"])
    hmix = N.new("ShaderNodeMix"); hmix.data_type = "RGBA"
    fac = N.new("ShaderNodeMath"); fac.operation = "MULTIPLY"; fac.use_clamp = True
    fac.inputs[1].default_value = 4.0
    L.new(bw.outputs[0], fac.inputs[0])
    L.new(fac.outputs[0], hmix.inputs["Factor"])
    hmix.inputs["A"].default_value = (1, 1, 1, 1)
    L.new(hue.outputs[0], hmix.inputs["B"])

    # cor base com variação de pincel (manchas um pouco mais escuras/claras)
    bmix = N.new("ShaderNodeMix"); bmix.data_type = "RGBA"
    bmix.inputs["A"].default_value = tuple(c * 0.82 for c in base[:3]) + (1,)
    bmix.inputs["B"].default_value = tuple(min(1, c * 1.12) for c in base[:3]) + (1,)
    L.new(nz.outputs["Fac"], bmix.inputs["Factor"])

    m1 = N.new("ShaderNodeMix"); m1.data_type = "RGBA"; m1.blend_type = "MULTIPLY"
    m1.inputs["Factor"].default_value = 1.0
    L.new(bmix.outputs["Result"], m1.inputs["A"]); L.new(ramp.outputs["Color"], m1.inputs["B"])
    m2 = N.new("ShaderNodeMix"); m2.data_type = "RGBA"; m2.blend_type = "MULTIPLY"
    m2.inputs["Factor"].default_value = 1.0
    L.new(m1.outputs["Result"], m2.inputs["A"]); L.new(hmix.outputs["Result"], m2.inputs["B"])

    em = N.new("ShaderNodeEmission")
    L.new(m2.outputs["Result"], em.inputs["Color"])
    if emit is not None:
        em2 = N.new("ShaderNodeEmission")
        em2.inputs["Color"].default_value = emit
        em2.inputs["Strength"].default_value = emit_str
        addsh = N.new("ShaderNodeAddShader")
        L.new(em.outputs[0], addsh.inputs[0]); L.new(em2.outputs[0], addsh.inputs[1])
        L.new(addsh.outputs[0], out.inputs[0])
    else:
        L.new(em.outputs[0], out.inputs[0])
    _mats[name] = m
    return m


def flat_emit(name, color, strength=1.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    N = m.node_tree.nodes
    N.clear()
    out = N.new("ShaderNodeOutputMaterial")
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    m.node_tree.links.new(em.outputs[0], out.inputs[0])
    _mats[name] = m
    return m


INK = None


def ink_mat():
    global INK
    if INK is None:
        INK = flat_emit("ink", hexc("#050914"), 1.0)
        INK.use_backface_culling = True
    return INK


# ---------------------------------------------------------------- geometria
def obj_finish(o, mat, outline=0.012):
    o.data.materials.append(mat)
    if outline > 0:
        o.data.materials.append(ink_mat())
        sol = o.modifiers.new("ink", "SOLIDIFY")
        sol.thickness = outline
        sol.offset = 1.0
        sol.use_flip_normals = True
        sol.use_rim = False
        sol.material_offset = 1
    return o


def box(name, loc, size, mat, rot=(0, 0, 0), outline=0.012, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        b = o.modifiers.new("bv", "BEVEL"); b.width = bevel; b.segments = 2
    return obj_finish(o, mat, outline)


def cyl(name, loc, r, depth, mat, rot=(0, 0, 0), verts=16, outline=0.01, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.shade_smooth()
    return obj_finish(o, mat, outline)


def ball(name, loc, scale, mat, outline=0.012):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    return obj_finish(o, mat, outline)


# ---------------------------------------------------------------- cena
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

W = 2.4          # meia largura do corredor
H = 3.3          # pé-direito
LEN = 26.0       # comprimento (para -Y)

M_FLOOR_A = toon("piso_a", hexc("#5d6f9e"), stroke=0.22, brush_scale=3)
M_FLOOR_B = toon("piso_b", hexc("#46578a"), stroke=0.22, brush_scale=3)
M_WALL = toon("parede", hexc("#6d7fb0"), stroke=0.14, brush_scale=6)
M_WALL_LOW = toon("parede_baixa", hexc("#3b4c80"), stroke=0.14, brush_scale=6)
M_CEIL = toon("teto", hexc("#3a4878"), stroke=0.1, brush_scale=5)
M_LOCK = toon("armario", hexc("#5a7ab8"), stroke=0.16, brush_scale=5)
M_LOCK2 = toon("armario2", hexc("#4c68a6"), stroke=0.16, brush_scale=5)
M_LOCK_RED = toon("armario_verm", hexc("#b34a5e"), stroke=0.16, brush_scale=5)
M_DARK = toon("escuro", hexc("#1b2650"), stroke=0.1)
M_METAL = toon("metal", hexc("#9fb2dc"), stroke=0.1)
M_FRAME = toon("caixilho", hexc("#26335f"), stroke=0.1)
M_BOARD = toon("mural", hexc("#7a5a3e"), stroke=0.25, brush_scale=9)
M_PAPER = toon("papel", hexc("#e8e4d6"), stroke=0.2, brush_scale=12)
M_PAPER_Y = toon("papel_am", hexc("#ffd34d"), stroke=0.2, brush_scale=12)
M_PAPER_P = toon("papel_rosa", hexc("#ff7fb0"), stroke=0.2, brush_scale=12)
M_DOOR = toon("porta", hexc("#33406e"), stroke=0.15)
M_SKY = flat_emit("ceu", hexc("#3557a8"), 1.0)
M_GLOW_Y = flat_emit("brilho_am", hexc("#ffc83d"), 5.0)
M_RAIN = flat_emit("chuva", hexc("#9fb8f0"), 1.6)
M_MOON = flat_emit("lua", hexc("#e9f0ff"), 6.0)

# personagem
M_SKIN = toon("pele", hexc("#c98d6b"), stroke=0.12)
M_HOOD = toon("moletom", hexc("#2f3d70"), stroke=0.2, brush_scale=6)
M_SCARF = toon("cachecol", hexc("#ffc83d"), stroke=0.2, brush_scale=8)
M_JEANS = toon("jeans", hexc("#24305a"), stroke=0.2)
M_SHOE = toon("tenis", hexc("#e9e6dc"), stroke=0.1)
M_BAG = toon("mochila", hexc("#8a3a52"), stroke=0.2)
M_HAIR = toon("cabelo", hexc("#1c1830"), stroke=0.25, brush_scale=10)
M_PHONE = flat_emit("tela", hexc("#fff2b8"), 8.0)

# piso em ladrilhos (xadrez em faixas)
tile = 1.2
nx = int(2 * W / tile)
ny = int(LEN / tile)
for i in range(nx):
    for j in range(ny):
        x = -W + tile * (i + 0.5)
        y = -tile * (j + 0.5) + 2.0
        box(f"t{i}_{j}", (x, y, -0.05), (tile * 0.98, tile * 0.98, 0.1),
            M_FLOOR_A if (i + j) % 2 == 0 else M_FLOOR_B, outline=0.0)

# teto + luminárias apagadas
box("teto", (0, -LEN / 2 + 2, H + 0.05), (2 * W, LEN + 2, 0.1), M_CEIL, outline=0.0)
for j in range(7):
    box(f"lum{j}", (0, 0.5 - j * 3.6, H - 0.02), (1.4, 0.4, 0.05), M_DARK, outline=0.006)

# parede esquerda + armários
box("parede_e", (-W - 0.05, -LEN / 2 + 2, H / 2), (0.1, LEN + 2, H), M_WALL, outline=0.0)
box("rodape_e", (-W + 0.55, -LEN / 2 + 2, 0.06), (0.04, LEN + 2, 0.12), M_DARK, outline=0.0)
lw, lh, ld = 0.48, 1.95, 0.5
idx = 0
for k in range(44):
    y = 1.6 - k * lw
    if -9.2 < y < -7.4:     # vão do bebedouro / mural
        continue
    col = M_LOCK if k % 2 == 0 else M_LOCK2
    if k in (9, 23):
        col = M_LOCK_RED
    x0 = -W + ld / 2
    box(f"arm{k}", (x0, y, lh / 2 + 0.12), (ld, lw * 0.96, lh), col, outline=0.01)
    # aberturas de ventilação
    for v in range(3):
        box(f"vent{k}_{v}", (x0 + ld / 2 + 0.003, y, 1.75 - v * 0.07), (0.01, lw * 0.6, 0.025), M_DARK, outline=0.0)
    box(f"puxa{k}", (x0 + ld / 2 + 0.02, y - lw * 0.32, 1.05), (0.04, 0.03, 0.16), M_METAL, outline=0.004)
    box(f"num{k}", (x0 + ld / 2 + 0.006, y, 1.55), (0.01, 0.12, 0.06), M_METAL, outline=0.003)
    if k == 6:   # porta entreaberta com um bilhete amarelo pendurado
        box("porta_aberta", (x0 + ld / 2 + 0.2, y + 0.12, lh / 2 + 0.12), (0.03, lw * 0.95, lh * 0.98),
            col, rot=(0, 0, math.radians(-38)), outline=0.01)
    if k in (3, 14, 27, 31):
        box(f"adesivo{k}", (x0 + ld / 2 + 0.008, y + 0.05, 1.25 + 0.1 * (k % 3)), (0.01, 0.14, 0.14),
            M_PAPER_P if k % 2 else M_PAPER_Y, outline=0.003)
box("arm_topo", (-W + ld / 2, -LEN / 2 + 2, lh + 0.14), (ld + 0.04, LEN + 2, 0.05), M_DARK, outline=0.0)

# mural com papéis no vão
box("mural", (-W + 0.03, -8.3, 1.6), (0.05, 1.6, 1.1), M_BOARD, outline=0.012)
papers = [(-7.85, 1.85, M_PAPER), (-8.25, 1.75, M_PAPER_Y), (-8.7, 1.9, M_PAPER), (-8.0, 1.35, M_PAPER_P),
          (-8.55, 1.4, M_PAPER), (-8.95, 1.55, M_PAPER_Y)]
for n, (py, pz, pm) in enumerate(papers):
    box(f"papel{n}", (-W + 0.065, py, pz), (0.01, 0.3, 0.36), pm, rot=(math.radians((n * 7) % 11 - 5), 0, 0), outline=0.004)
# fio vermelho do detetive ligando dois papéis
cyl("fio", (-W + 0.075, -8.3, 1.62), 0.006, 0.9, toon("fio", hexc("#e2384f")), rot=(math.radians(64), 0, 0), outline=0.0)

# parede direita com janelas (vãos deixam a lua passar e desenhar o caixilho no chão)
xw = W + 0.05
win_z0, win_z1 = 1.0, 2.7
box("dir_baixo", (xw, -LEN / 2 + 2, win_z0 / 2), (0.1, LEN + 2, win_z0), M_WALL_LOW, outline=0.0)
box("dir_cima", (xw, -LEN / 2 + 2, (win_z1 + H) / 2), (0.1, LEN + 2, H - win_z1), M_WALL, outline=0.0)
box("peitoril", (W - 0.06, -LEN / 2 + 2, win_z0 + 0.02), (0.18, LEN + 2, 0.05), M_FRAME, outline=0.006)
pitch = 3.0
for j in range(9):
    yc = 0.5 - j * pitch
    box(f"pilar{j}", (xw, yc - pitch / 2, (win_z0 + win_z1) / 2), (0.14, 0.7, win_z1 - win_z0), M_WALL, outline=0.008)
    # caixilho: 1 travessa + 2 montantes por janela
    box(f"trav{j}", (xw, yc, (win_z0 + win_z1) / 2 + 0.15), (0.08, pitch - 0.7, 0.05), M_FRAME, outline=0.0)
    for m in (-0.55, 0.55):
        box(f"mont{j}_{m}", (xw, yc + m, (win_z0 + win_z1) / 2), (0.08, 0.05, win_z1 - win_z0), M_FRAME, outline=0.0)
# céu lá fora + chuva + lua
ceu = box("ceu", (W + 3.0, -LEN / 2, 3), (0.1, LEN * 3, 12), M_SKY, outline=0.0)
ceu.visible_shadow = False
import random
random.seed(7)
for r in range(260):
    y = random.uniform(-LEN + 2, 2)
    z = random.uniform(0.6, 3.4)
    box(f"chuva{r}", (W + random.uniform(0.25, 1.6), y, z), (0.008, 0.008, random.uniform(0.25, 0.6)), M_RAIN,
        rot=(math.radians(-12), 0, 0), outline=0.0).visible_shadow = False

# porta do fundo com janelinha acesa (acento amarelo no ponto de fuga)
yend = -LEN + 2
box("parede_fundo", (0, yend, H / 2), (2 * W, 0.1, H), M_WALL, outline=0.0)
box("porta_fundo", (0, yend + 0.06, 1.1), (1.3, 0.05, 2.2), M_DOOR, outline=0.015)
box("vidro_porta", (0, yend + 0.09, 1.6), (0.45, 0.02, 0.6), M_GLOW_Y, outline=0.0)
box("placa_saida", (0, yend + 0.08, 2.55), (0.7, 0.03, 0.22), flat_emit("saida", hexc("#ffd34d"), 3.0), outline=0.008)

# bilhete dobrado no chão, perto da câmera
box("bilhete", (-0.7, -1.4, 0.006), (0.22, 0.16, 0.008), M_PAPER_Y, rot=(0, 0, math.radians(24)), outline=0.004)

# ---------------------------------------------------------------- personagem (estilizado)
px, py = 0.35, -3.0
face = math.radians(-25)   # virado pra câmera, meio de lado


def P(dx, dy, dz):
    c, s = math.cos(face), math.sin(face)
    return (px + dx * c - dy * s, py + dx * s + dy * c, dz)


parts = []
parts.append(cyl("perna_e", P(-0.11, 0, 0.42), 0.085, 0.8, M_JEANS, r2=0.07))
parts.append(cyl("perna_d", P(0.11, 0, 0.42), 0.085, 0.8, M_JEANS, r2=0.07))
parts.append(box("tenis_e", P(-0.11, 0.06, 0.05), (0.15, 0.3, 0.1), M_SHOE, bevel=0.03))
parts.append(box("tenis_d", P(0.12, 0.08, 0.05), (0.15, 0.3, 0.1), M_SHOE, bevel=0.03))
parts.append(cyl("tronco", P(0, 0, 1.12), 0.26, 0.68, M_HOOD, r2=0.2, verts=20))
parts.append(ball("ombros", P(0, 0, 1.42), (0.3, 0.2, 0.12), M_HOOD))
parts.append(box("bolso", P(0, 0.2, 0.98), (0.3, 0.06, 0.14), M_HOOD, bevel=0.02))
parts.append(box("mochila", P(0, -0.27, 1.18), (0.38, 0.2, 0.5), M_BAG, bevel=0.05))
parts.append(ball("cachecol", P(0, 0.02, 1.5), (0.2, 0.17, 0.08), M_SCARF))
parts.append(ball("cabeca", P(0, 0.03, 1.72), (0.19, 0.18, 0.21), M_SKIN))
parts.append(ball("cabelo", P(0, -0.02, 1.8), (0.205, 0.2, 0.18), M_HAIR))
parts.append(ball("franja", P(0.06, 0.12, 1.85), (0.14, 0.08, 0.06), M_HAIR))
parts.append(ball("capuz", P(0, -0.12, 1.55), (0.26, 0.16, 0.16), M_HOOD))
# braços dobrados segurando o celular na frente do rosto
parts.append(cyl("braco_e", P(-0.25, 0.08, 1.22), 0.065, 0.42, M_HOOD, rot=(math.radians(-25), math.radians(-15), face)))
parts.append(cyl("braco_d", P(0.25, 0.08, 1.22), 0.065, 0.42, M_HOOD, rot=(math.radians(-25), math.radians(15), face)))
parts.append(cyl("antebraco_e", P(-0.14, 0.26, 1.12), 0.06, 0.32, M_HOOD, rot=(math.radians(-80), 0, face + 0.5)))
parts.append(cyl("antebraco_d", P(0.14, 0.26, 1.12), 0.06, 0.32, M_HOOD, rot=(math.radians(-80), 0, face - 0.5)))
parts.append(box("celular", P(0, 0.42, 1.2), (0.09, 0.012, 0.16), M_PHONE, rot=(math.radians(-55), 0, face), outline=0.006))

# luz do celular no rosto (o acento amarelo da cena)
bpy.ops.object.light_add(type="POINT", location=P(0, 0.38, 1.28))
ph = bpy.context.active_object.data
ph.color = (1.0, 0.78, 0.3)
ph.energy = 60
ph.shadow_soft_size = 0.05
# halo amarelo no chão em volta do personagem
bpy.ops.object.light_add(type="SPOT", location=P(0, 0.6, 1.9))
sp = bpy.context.active_object
sp.data.color = (1.0, 0.75, 0.28)
sp.data.energy = 120
sp.data.spot_size = math.radians(70)
sp.rotation_euler = (math.radians(10), 0, 0)
# luz amarela da porta do fundo
bpy.ops.object.light_add(type="POINT", location=(0, yend + 0.8, 1.7))
pd = bpy.context.active_object.data
pd.color = (1.0, 0.76, 0.3)
pd.energy = 260
pd.shadow_soft_size = 0.3

bpy.ops.object.light_add(type="AREA", location=P(0.2, -1.2, 2.2))
rim = bpy.context.active_object
rim.data.color = (0.6, 0.72, 1.0); rim.data.energy = 140; rim.data.size = 0.8
rim.rotation_euler = (Vector(P(0, 0, 1.3)) - rim.location).to_track_quat("-Z", "Y").to_euler()

# lua: sol vindo da direita, alto, desenhando o caixilho no chão e nos armários
bpy.ops.object.light_add(type="SUN", location=(0, 0, 10))
sun = bpy.context.active_object
sun.data.color = (0.62, 0.74, 1.0)
sun.data.energy = 4.5
sun.data.angle = math.radians(1.0)
d = Vector((-1.0, 0.35, -0.55)).normalized()
sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

# preenchimento azul fraco (o noir não é preto chapado)
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs[0].default_value = hexc("#2a3c78")
bg.inputs[1].default_value = 0.7

# ---------------------------------------------------------------- câmera e render
bpy.ops.object.camera_add(location=(-0.6, 2.4, 1.05))
cam = bpy.context.active_object
cam.data.lens = 26
target = Vector((0.4, -7.5, 1.55))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.rotation_euler.y += math.radians(-4)   # leve "dutch angle" de quadrinho
sc.camera = cam

for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        continue
sc.render.resolution_x = 1600
sc.render.resolution_y = 1000
sc.render.filepath = OUT
sc.view_settings.view_transform = "Standard"
try:
    sc.eevee.taa_render_samples = 32
    sc.eevee.use_shadows = True
except AttributeError:
    pass
bpy.ops.render.render(write_still=True)
print("RENDER OK", OUT)
