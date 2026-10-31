"""Kit de geração de modelos low-poly para o FortressChaos, reutilizado por
generate_all.py.

Convenção de eixos: Godot é Y-up (altura=Y, chão=XZ); Blender é Z-up
(altura=Z, chão=XY). to_bloc() converte uma posição lida de um Transform3D
do Godot (gx, gy, gz) para o local Blender (gx, gz, gy). O exportador glTF
cuida da reconversão para Y-up ao salvar o .glb, então todo o resto do jogo
(import, instance=ExtResource) já funciona sem mudança nenhuma.

Estilo alvo: low-poly facetado (flat shading) com **chanfro leve em toda
aresta dura** — o chanfro é o que dá a leitura "peça esculpida com carinho"
em vez de "caixa do Blender": ele cria uma faixa fina que pega a luz de
raspão em cada quina. Toda peça ganha textura pixel art gerada por pixel em
Python (nenhum asset externo) e UV por **projeção cúbica com densidade de
texel constante em metros** (`tex_scale` = quantos metros cabem num tile da
textura), de forma que um tijolo tem o mesmo tamanho numa parede grande e
numa pequena — antes o smart_project normalizava cada peça pra 0..1 e a
mesma textura aparecia gigante numa peça e minúscula noutra.

Aberturas (janelas, portas, frestas) são **recortes de verdade**: um
boolean escava um nicho na parede, o vidro/porta fica recuado no fundo do
nicho e a moldura sai pra fora — nada de caixinha chapada colada na parede.

## Luz e emissivo — lições repetidas por 4+ agentes de reskin de bioma, consolidadas aqui
Cada leva de reskin (Caverna, Tundra, Pântano, Deserto, Terra Abrasada)
redescobriu variações do mesmo problema por conta própria, gastando uma
rodada de captura cada vez. Leia isto ANTES de desenhar peça com brilho ou
cor saturada, pra não pagar o mesmo preço de novo:

1. **`pattern="crystal"` soma até +0.55 por canal no centro do tile**
   (`make_pixel_texture`). Ótimo numa gema de 10 cm; em qualquer superfície
   grande (corpo de criatura, parede) estoura pra branco/creme lavado.
   Regra: `crystal` só em peça PEQUENA (pingente, núcleo de olho, cristal de
   decoração). Massa grande usa `rock`/`soft` e ganha o brilho separado, por
   emissão, não pelo padrão da textura.
2. **`add_material(..., emission=cor)` liga a MESMA textura de albedo na
   emissão** — o parâmetro não pinta, só ativa o canal. Se o padrão de
   albedo já for `crystal`/saturado, a emissão herda o estouro do item 1.
3. **Energia emissiva acima de ~1.0 desloca a matiz pro amarelo-branco** sob
   o tonemap ACES do `Environment` do jogo, e o `glow` do bioma reforça isso
   a partir de ~1.05. Mantenha `emission_energy` abaixo de 1.0 pra cor
   saturada segurar a própria matiz; se precisar de mais brilho, prefira
   várias fontes pequenas a uma só mais forte.
4. **A cor que chega na tela NÃO é a albedo pura** — luz direta do bioma
   soma por cima e clareia o resultado (medido: albedo `(1.0, 0.36, 0.05)`
   chegou como `(1.0, 0.71, 0.20)`, um alaranjado bem mais claro que o
   pretendido). Se o objetivo é "laranja-magma profundo" na tela, autore a
   albedo mais escura/saturada do que parece certo no preview isolado do
   Blender — o preview não aplica o tonemap/exposure real do jogo.
5. **Bioma escuro (Caverna) e bioma claro (Deserto/Pântano/planície
   ensolarada) pedem valor de criatura INVERTIDO.** Escuro: corpo claro,
   pernas/detalhe escuro (senão a criatura vira "gaiola de gravetos" no
   escuro). Claro: corpo mais escuro que o chão do bioma, claro só em
   detalhe pequeno (senão a criatura some contra o chão iluminado). Não
   existe paleta que funcione nos dois — decida pelo bioma, sempre testando
   em `main.tscn` real com `FORTALEZA_BIOME=<id>`, nunca só no preview do
   Blender isolado.
"""

import bpy
import bmesh
import math
import random
from mathutils import Vector

_TEX_COUNTER = [0]
_MAT_CACHE = {}


# ----------------------------------------------------------------- básico

def to_bloc(gx: float, gy: float, gz: float) -> tuple:
    """Godot (x, altura, z) -> Blender (x, -z, altura).

    O sinal negativo NÃO é enfeite: o exportador glTF grava Blender (x,y,z)
    como glTF (x, z, -y), então a antiga conversão (gx, gz, gy) devolvia o
    modelo ESPELHADO em Z dentro do Godot — o que jogava toda construção
    2x2 (autorada centrada em (1, y, 1)) pra z = -1, ou seja, 2 metros fora
    do CollisionShape3D e do footprint dela no grid. Com o menos, a
    composição vira uma rotação (determinante +1) e o ponto autorado (gx,
    gy, gz) aparece no Godot exatamente em (gx, gy, gz)."""
    return (gx, -gz, gy)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MAT_CACHE.clear()
    # Estilo de textura volta pro padrão (pixel art) a cada builder: é isto que
    # permite ligar o estilo pintado numa peça só sem vazar pro resto do lote
    # quando `generate_all.py` roda os ~150 assets no mesmo processo.
    _STYLE["mode"] = "pixel"


def flat_shade(obj) -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = False


def jitter(obj, amount: float = 0.04) -> None:
    for v in obj.data.vertices:
        v.co.x += random.uniform(-amount, amount)
        v.co.y += random.uniform(-amount, amount)
        v.co.z += random.uniform(-amount * 0.7, amount * 0.7)


def _activate(obj):
    """Deixa `obj` ativo e sozinho na seleção; devolve o objeto ativo
    anterior pra ser restaurado depois."""
    prev = bpy.context.view_layer.objects.active
    for o in list(bpy.context.selected_objects):
        try:
            o.select_set(False)
        except ReferenceError:
            pass
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    return prev


def _restore(prev, current=None) -> None:
    """Restaura o objeto ativo anterior — tolerante a referência morta,
    porque no meio do caminho o objeto anterior pode ter sido apagado
    (cutter de boolean, peças que viraram uma só no join, etc.)."""
    if current is not None:
        try:
            current.select_set(False)
        except ReferenceError:
            pass
    if prev is None:
        return
    try:
        _ = prev.name
    except ReferenceError:
        return
    bpy.context.view_layer.objects.active = prev


def unwrap(obj, margin: float = 0.03) -> None:
    """UV unwrap por smart project (mantido para compatibilidade)."""
    prev = _activate(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    try:
        bpy.ops.uv.smart_project(island_margin=margin)
    except RuntimeError:
        pass
    bpy.ops.object.mode_set(mode='OBJECT')
    _restore(prev, obj)


def cube_unwrap(obj, tex_scale: float = 1.0) -> None:
    """UV por projeção cúbica com densidade constante: `tex_scale` metros
    correspondem a um tile completo da textura. É o que garante que o
    tijolo/telha/tábua tenha o mesmo tamanho aparente em todas as peças do
    modelo (e entre modelos diferentes).

    Feito à mão (sem `bpy.ops.uv.cube_project`) de propósito: o operador
    falhava silenciosamente em malhas que passaram por boolean, deixando a
    peça com a UV original 0..1 esticada — a parede do portão saía lisa e
    branca em vez de aparelhada. Aqui a projeção é planar por face, no eixo
    dominante da normal, usando coordenadas de MUNDO: assim o padrão
    continua alinhado de uma peça pra outra."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_data = mesh.uv_layers.active.data
    mw = obj.matrix_world
    scale = 1.0 / max(tex_scale, 1e-6)
    axis_pair = ((1, 2), (0, 2), (0, 1))
    for poly in mesh.polygons:
        n = poly.normal
        dom = 0
        if abs(n[1]) > abs(n[dom]):
            dom = 1
        if abs(n[2]) > abs(n[dom]):
            dom = 2
        a, b = axis_pair[dom]
        flip = -1.0 if n[dom] < 0.0 else 1.0
        for li in poly.loop_indices:
            co = mw @ mesh.vertices[mesh.loops[li].vertex_index].co
            uv_data[li].uv = (co[a] * scale * flip, co[b] * scale)


def bevel(obj, width: float = 0.025, segments: int = 1, angle_deg: float = 35.0) -> None:
    """Chanfro leve nas arestas duras — o detalhe que mais muda a leitura
    low-poly (cada quina vira uma faixa fininha que pega a luz)."""
    if width <= 0.0:
        return
    prev = _activate(obj)
    mod = obj.modifiers.new("Bevel", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle_deg)
    mod.miter_outer = 'MITER_ARC'
    mod.use_clamp_overlap = True
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError:
        obj.modifiers.remove(mod)
    _restore(prev, obj)


def clean_mesh(obj, merge_dist: float = 0.0002) -> None:
    """Solda vértices coincidentes e derrete geometria degenerada. Sem isso,
    o boolean EXACT deixa arestas de comprimento ~0 e o chanfro seguinte
    explode alguns vértices pro infinito."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=merge_dist)
    bmesh.ops.dissolve_degenerate(bm, dist=merge_dist, edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def boolean_diff(target, cutter, delete_cutter: bool = True) -> None:
    """Escava `cutter` de `target` (usado pros nichos de janela/porta)."""
    prev = _activate(target)
    mod = target.modifiers.new("Cut", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cutter
    mod.solver = 'EXACT'
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError:
        target.modifiers.remove(mod)
    _restore(prev, target)
    clean_mesh(target)
    # O boolean herda os slots de material do cutter (que não tem nenhum),
    # sobrando um slot VAZIO no índice 0; as faces originais continuavam
    # apontando pra ele e a peça saía branca/lisa. Zera tudo pra o material
    # que o finish() vai anexar depois cair no índice 0 e valer pra malha
    # inteira.
    target.data.materials.clear()
    for poly in target.data.polygons:
        poly.material_index = 0
    if delete_cutter:
        bpy.data.objects.remove(cutter, do_unlink=True)


# --------------------------------------------------------------- texturas

def _clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def _shade(color: tuple, factor: float) -> tuple:
    return (_clamp01(color[0] * factor), _clamp01(color[1] * factor), _clamp01(color[2] * factor))


def _jit(color: tuple, amount: float, rng: random.Random) -> tuple:
    return (
        _clamp01(color[0] + rng.uniform(-amount, amount)),
        _clamp01(color[1] + rng.uniform(-amount, amount)),
        _clamp01(color[2] + rng.uniform(-amount, amount)),
    )


def _block_rng(seed: int, bx: int, by: int) -> random.Random:
    """RNG determinístico por célula de grade (bloco/telha/ripa/folha)."""
    return random.Random(seed * 1_000_003 + bx * 9973 + by * 31)


def _tileable_value_noise(size: int, lattice: int, seed: int):
    """Ruído de valor suave e TILEÁVEL: pontos aleatórios numa treliça
    grosseira (`lattice` x `lattice`), interpolados com smoothstep. Mesma
    técnica de `generate_terrain_textures.py::value_noise` (reimplementada
    aqui porque este módulo não importa aquele script) — ao contrário de
    `_block_rng` por célula (valor CHAPADO com aresta reta na borda do
    bloco), aqui o campo varia continuamente e qualquer contorno de mancha
    cai onde o campo cruza um limiar, nunca alinhado a pixel de grade."""
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(lattice)] for _ in range(lattice)]
    scale = lattice / float(size)
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        fy = y * scale
        iy = int(fy)
        ty = fy - iy
        ty = ty * ty * (3.0 - 2.0 * ty)
        y0, y1 = iy % lattice, (iy + 1) % lattice
        row = out[y]
        for x in range(size):
            fx = x * scale
            ix = int(fx)
            tx = fx - ix
            tx = tx * tx * (3.0 - 2.0 * tx)
            x0, x1 = ix % lattice, (ix + 1) % lattice
            a = grid[y0][x0] * (1.0 - tx) + grid[y0][x1] * tx
            b = grid[y1][x0] * (1.0 - tx) + grid[y1][x1] * tx
            row[x] = a * (1.0 - ty) + b * ty
    return out


def _tileable_fbm(size: int, seed: int, octaves) -> list:
    """Soma de oitavas de `_tileable_value_noise`, normalizada pra 0..1.
    Oitava de treliça grossa = mancha ampla; treliça fina = variação local —
    a "pincelada de baixa frequência" já usada no chão de bioma."""
    acc = [[0.0] * size for _ in range(size)]
    total = 0.0
    for i, (lattice, weight) in enumerate(octaves):
        n = _tileable_value_noise(size, lattice, seed + i * 977)
        for y in range(size):
            arow = acc[y]
            nrow = n[y]
            for x in range(size):
                arow[x] += nrow[x] * weight
        total += weight
    for y in range(size):
        arow = acc[y]
        for x in range(size):
            arow[x] /= total
    return acc


# ------------------------------------------------- rampa, degrau, dithering
#
# ## Por que uma RAMPA de cor, e não `base_color × escalar` (recalibragem)
#
# Até esta rodada todo padrão pixel art era a cor base multiplicada por um
# número e somada a um chuvisco aleatório por pixel. Nada disso é errado em
# teoria, mas põe as construções num idioma visual DIFERENTE do resto do jogo,
# que migrou pra pixel art de alta produção (cartas, logo, placas de menu). Os
# três defeitos medidos em captura real, lado a lado com a UI nova:
#
# 1. **Multiplicar não sombreia.** Cor multiplicada mantém matiz e saturação
#    relativas, então a "sombra" é a mesma cor só que mais escura — e o olho lê
#    isso como recorte de papel colorido, não como volume. Toda a arte 2D do
#    jogo faz o contrário: sombra puxa pro FRIO e mais SATURADA, realce puxa
#    pro QUENTE e mais LAVADO. `_ramp` é essa regra, em código.
# 2. **Ruído por pixel não é dithering.** Jitter aleatório vira granulado
#    cinza na primeira mipmap e some; o xadrez ORDENADO (Bayer) da referência
#    sobrevive porque é ESTRUTURA, não ruído — e é ele que dá a sensação de
#    "muitos degraus de sombra" com uma paleta de 6 tons. `_quant` faz isso.
# 3. **A faixa de valor era estreita demais.** Os motivos antigos viviam entre
#    ×0,72 e ×1,18 da cor base; com o sol do jogo em 1,35 e o tonemap ACES por
#    cima (ver item 4 do cabeçalho deste arquivo), tudo isso colapsava perto do
#    branco — a pedra do Núcleo saía giz, o reboco saía papel. A rampa nova vai
#    de ×0,42 a ×1,30 em torno de um centro REBAIXADO (×0,92), justamente pra o
#    sol ter pra onde clarear sem estourar.
#
# Cada padrão passou a devolver só um CAMPO DE VALOR `t` (0 = sombra profunda,
# 1 = realce). Quem transforma isso em cor é sempre o mesmo par
# `_ramp(base, _quant(t, levels, dither))` — então mudar a identidade da paleta
# do jogo inteiro é mexer em três constantes aqui, e não em 100 builders.

## Bayer 4×4: a matriz de dithering ordenado clássica. 4×4 (e não 8×8) porque
## o motivo de um tile tem 3–8 px de lado — um xadrez de 8 px de período
## competiria com o próprio motivo em vez de sombreá-lo.
_BAYER4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)

## Faixa da rampa, em múltiplos da cor base. O CENTRO é 0.78 e não 1.0 de
## propósito, e o número saiu de captura, não de gosto: a albedo autorada nunca
## é o que chega na tela — o sol do bioma (1.35) mais o ambiente (0.65) somam
## por cima e clareiam ~35%. Com o centro em 1.0 a peça inteira vivia na METADE
## de cima da faixa de valor e o dithering, que é o ponto do estilo, se perdia
## no branco. Rebaixar o centro é o que devolve espaço pro sol modelar a peça —
## e é o que faz a pedra do Núcleo ler como ardósia (a referência do logo) em
## vez de giz.
_RAMP_LO = 0.26
_RAMP_MID = 0.78
_RAMP_HI = 1.30

## Teto de albedo. O sol do bioma é 1.35 e o `Environment` do jogo usa tonemap
## ACES: qualquer albedo acima disto chega na tela GRUDADO no branco, e um
## degrau de pixel art que virou branco deixou de ser um degrau. Medido em
## captura: o reboco (0.80) e a pedra clara do Núcleo saíam de giz, e o
## dithering — que é o ponto do estilo — sumia junto. O teto é aplicado por
## canal proporcionalmente, então corta a LUZ sem lavar a matiz.
_ALBEDO_CEIL = 0.76

## Quanto a sombra ganha de saturação e o realce perde. Sem isso a rampa vira
## escala de cinza multiplicada — o defeito nº 1 descrito acima. O valor é
## MODERADO (0.22, não 0.34) porque a maior parte da paleta do jogo já é pouco
## saturada: dessaturar 34% o realce de uma pedra azul-acinzentada entrega um
## realce BRANCO, e a parede volta a ler como giz.
_RAMP_SAT = 0.22

## Deriva de matiz. O frio tem uma pitada de violeta (e não azul puro) porque é
## essa a sombra das referências de arte do projeto (logo, cartas).
_RAMP_COOL = (0.86, 0.92, 1.18)
_RAMP_WARM = (1.12, 1.03, 0.85)
_RAMP_TINT = 0.52

## Luz ABSOLUTA que o realce soma numa cor escura (ver `_ramp`).
_RAMP_LIFT = 0.20

## Cor de neve pro padrão "leaf_snow" (Tundra) — branco levemente azulado,
## não branco puro: neve à sombra de conífera puxa pro frio nas referências
## do projeto (mesmo eixo frio/quente de `_RAMP_COOL`).
_SNOW_COLOR = (0.88, 0.93, 0.98)


def _ramp(base: tuple, t: float) -> tuple:
    """Converte um valor 0..1 numa cor da rampa do material.

    `t = 0.5` é o tom local (a cor autorada, levemente rebaixada); abaixo é
    sombra (mais fria e mais saturada), acima é luz (mais quente e mais
    lavada)."""
    k = _clamp01(t) * 2.0 - 1.0
    lum = (base[0] + base[1] + base[2]) / 3.0
    # O REALCE é proporcionalmente menor quanto mais clara já é a cor: uma cor
    # de 0.8 não tem 30% de espaço acima dela, e insistir só produz branco
    # chapado (era o reboco estourado da primeira captura). Cor escura, ao
    # contrário, precisa do realce inteiro pra o volume aparecer.
    hi_span = (_RAMP_HI - _RAMP_MID) * (1.0 - 0.62 * lum)
    f = _RAMP_MID + (_RAMP_MID - _RAMP_LO) * k if k < 0.0 else _RAMP_MID + hi_span * k
    sat = 1.0 - _RAMP_SAT * k
    tint = _RAMP_WARM if k > 0.0 else _RAMP_COOL
    a = abs(k) * _RAMP_TINT
    # Realce ADITIVO, proporcional ao quanto a cor é escura. Rampa puramente
    # multiplicativa não tem para onde clarear numa cor escura: o ferro
    # (0.17) subia de 0.156 pra 0.22 no rebite, ou seja, preto contra preto —
    # a chapa saía como uma silhueta chapada. O termo abaixo dá ~+0.15 de luz
    # absoluta numa cor escura e quase nada numa clara, que é o que separa
    # "metal escuro com rebite brilhando" de "buraco preto".
    lift = _RAMP_LIFT * max(k, 0.0) * (1.0 - lum)
    out = [
        _clamp01((lum + (base[0] - lum) * sat) * f * (1.0 + (tint[0] - 1.0) * a) + lift * tint[0]),
        _clamp01((lum + (base[1] - lum) * sat) * f * (1.0 + (tint[1] - 1.0) * a) + lift * tint[1]),
        _clamp01((lum + (base[2] - lum) * sat) * f * (1.0 + (tint[2] - 1.0) * a) + lift * tint[2]),
    ]
    top = max(out)
    if top > _ALBEDO_CEIL:
        s = _ALBEDO_CEIL / top
        out = [c * s for c in out]
    return (out[0], out[1], out[2])


def _quant(t: float, levels: int, dither: float) -> float:
    """Prende `t` a um dos `levels` degraus da rampa, com DITHERING ORDENADO.

    O `dither` (0..1, vindo do Bayer) é comparado com a fração que sobra entre
    dois degraus: pixels vizinhos com a mesma fração caem em degraus
    diferentes, e o resultado é o xadrez da referência em vez de uma faixa
    chapada com degrau visível."""
    s = _clamp01(t) * (levels - 1)
    i = int(s)
    if (s - i) > dither:
        i += 1
    return min(max(i, 0), levels - 1) / float(levels - 1)


def _quant_soft(t: float, levels: int, x: int, y: int, dither: float) -> float:
    """Posterização com dithering Bayer de força REDUZIDA — fração de um
    degrau, não o degrau inteiro. Mesma técnica (e mesmo motivo) de
    `generate_terrain_textures.py::_posterize`: com dithering de força
    TOTAL (o que `_quant` acima faz, e que serve bem a motivo com estrutura
    própria — junta de pedra, veio de madeira), um campo que varia DEVAGAR
    fica quase constante em qualquer janela 4×4, e a zona de transição
    cobre a peça inteira — o resultado é o xadrez de Bayer cru, sem nenhuma
    banda chapada sobrando. Aqui só `dither` (fração do degrau, tipicamente
    0.4–0.5) participa da decisão; o resto do degrau fica CHAPADO, e o
    xadrez só aparece na ORLA entre duas bandas — pincelada, não trama."""
    step = 1.0 / float(levels - 1)
    bayer = (_BAYER4[y & 3][x & 3] + 0.5) / 16.0
    v = _clamp01(t) + (bayer - 0.5) * step * dither
    q = round(_clamp01(v) / step) * step
    return _clamp01(q)


## Resolução padrão do pixel art. Subiu de 16 pra 32 nesta recalibragem: com
## `tex_scale` típico de 0,4–0,7 m, 16 px punha um texel em ~4 cm, o que a 5 m
## de câmera vira um bloco de ~11 px de tela — grosso a ponto de a alvenaria
## virar papa. 32 px mantém o MESMO tamanho físico de tijolo/telha (todos os
## motivos abaixo são medidos em `u = size // 16`) e usa os pixels que sobram
## pra desenhar o que faltava: aresta de cima iluminada, pé do bloco na sombra,
## junta escura de verdade e o xadrez do dithering.
PIXEL_SIZE = 32


def make_pixel_texture(name: str, base_color: tuple, pattern: str = "soft",
                        size: int = PIXEL_SIZE, seed: int = 0):
    """Gera uma textura pixel art pequena e tileável, pixel a pixel, sem
    nenhum arquivo externo. `pattern` controla o motivo visual.

    Todo motivo é medido em `u = size // 16`, então trocar `size` muda a
    DENSIDADE de pixel sem mudar o tamanho físico do tijolo/telha/tábua."""
    rng = random.Random(seed)
    img = bpy.data.images.new(name, width=size, height=size, alpha=False)
    pixels = [0.0] * (size * size * 4)
    u = max(1, size // 16)

    knot_x = rng.uniform(size * 0.2, size * 0.8)
    knot_y = rng.uniform(size * 0.2, size * 0.8)
    knot_r = 1.6 * u

    # Campo de valor pré-calculado da folhagem: precisa existir ANTES do
    # laço por pixel (é uma soma de oitavas sobre a textura inteira, não algo
    # que dá pra amostrar célula a célula) e só pros padrões que usam — pagar
    # esse custo pra `wood`/`stone`/etc seria trabalho jogado fora.
    leaf_field = None
    snow_field = None
    if pattern in ("leaf", "leaf_snow"):
        # Treliças pequenas (3/6/11, não 8/16/32 como no chão de 128 px):
        # numa tela de 32 px uma treliça fina troca de mancha a cada 2-3
        # pixels e a posterização devolve chuvisco em vez de mancha — mesma
        # lição documentada em `_grass_value_field`.
        leaf_field = _tileable_fbm(size, seed + 601,
                                    ((3, 0.55), (6, 0.30), (11, 0.15)))
        if pattern == "leaf_snow":
            # Ruído SEPARADO (não o mesmo `leaf_field`) pra orla da neve: se
            # viesse do mesmo campo, a mancha de neve colaria exatamente na
            # mancha de folhagem e o resultado seria "sombra vira neve" em
            # vez de duas camadas independentes.
            snow_field = _tileable_fbm(size, seed + 823, ((3, 0.6), (7, 0.4)))

    for y in range(size):
        for x in range(size):
            # `acc` = cor SOMADA depois da rampa (veio de minério, glifo de
            # runa): é material embutido, não sombra do material principal.
            acc = None
            # `snow_amount` = quanto este pixel LERPA pra cor de neve DEPOIS
            # da rampa — ver `_quant_soft` para o porquê de ser lerp e não
            # `acc` (aditivo): folhagem verde-escura + branco aditivo vira
            # ciano, não branco; lerp de verdade é o que dá neve de verdade.
            snow_amount = 0.0
            levels = 6
            if pattern == "wood":
                # Veio HORIZONTAL (viga, tora deitada, cabo de ferramenta).
                row = y // (3 * u)
                t = 0.56 + (0.10 if row % 2 == 0 else -0.08)
                if y % (3 * u) == 0:
                    t = 0.06                       # linha do veio, bem funda
                elif y % (3 * u) == (3 * u) - 1:
                    t += 0.16                      # fibra que pega a luz
                d_knot = ((x - knot_x) ** 2 + (y - knot_y) ** 2) ** 0.5
                if d_knot < knot_r:
                    t = 0.12
                elif d_knot < knot_r * 1.45:
                    t = 0.32
                t += rng.uniform(-0.06, 0.06)
            elif pattern == "planks":
                # Tábuas VERTICAIS (porta, portão, carroceria, deque).
                plank_w = 4 * u
                col_i = x // plank_w
                prng = _block_rng(seed, col_i, 0)
                t = prng.uniform(0.40, 0.74)
                local = x % plank_w
                if local == 0:
                    t = 0.03                       # fresta entre tábuas
                elif local == 1:
                    t = min(t, 0.34)               # sombra que a fresta joga
                elif local == plank_w - 1:
                    t += 0.14                      # quina da tábua na luz
                if (y // u) % 5 == 2:
                    t -= 0.10                      # veio correndo na tábua
                t += rng.uniform(-0.05, 0.05)
            elif pattern == "stone":
                block_w, block_h = 4 * u, 3 * u
                row = y // block_h
                shift = (block_w // 2) if row % 2 == 1 else 0
                col_i = (x + shift) // block_w
                lx = (x + shift) % block_w
                ly = y % block_h
                brng = _block_rng(seed, col_i, row)
                # Faixa ESTREITA de valor por bloco (e não 0.38–0.72): com 6
                # degraus de rampa, uma faixa larga joga blocos vizinhos em
                # degraus distantes e a parede vira tabuleiro de xadrez branco
                # e azul. Quem carrega o contraste da alvenaria é a JUNTA
                # escura, não a diferença entre uma pedra e a vizinha.
                t = brng.uniform(0.42, 0.62)
                if ly == block_h - 1:
                    t += 0.18                      # aresta de cima do bloco
                elif ly == 1:
                    t -= 0.18                      # pé do bloco, na sombra
                if lx == block_w - 1:
                    t += 0.08
                elif lx == 1:
                    t -= 0.14                      # lateral do bloco na sombra
                if ly == 0 or lx == 0:
                    # Junta PRETA, não "escura". É ela que carrega o contraste
                    # da alvenaria (medido contra a arte do menu principal: a
                    # diferença entre a parede daqui e a de lá estava toda no
                    # quão fundo o p5 chegava, não na variação entre pedras).
                    t = 0.02
                elif brng.random() < 0.10 and (lx * 7 + ly * 13) % 11 < 2:
                    t -= 0.22                      # lasca/cratera na pedra
                t += rng.uniform(-0.05, 0.05)
            elif pattern == "rock":
                # Rocha bruta: manchas do tamanho de uma placa, não chuvisco.
                crng = _block_rng(seed, x // (2 * u), y // (2 * u))
                t = crng.uniform(0.30, 0.78) + rng.uniform(-0.09, 0.09)
                if (x % (2 * u) == 0) != (y % (2 * u) == 0):
                    t -= 0.16                      # fenda entre placas
                levels = 5
            elif pattern == "ore":
                crng = _block_rng(seed, x // (2 * u), y // (2 * u))
                t = crng.uniform(0.22, 0.60) + rng.uniform(-0.08, 0.08)
                # O veio é sorteado por CÉLULA de 2u e depois afinado por
                # pixel: sorteado só por pixel ele vira confete dourado
                # espalhado por igual, que lê como ruído e não como filão.
                vrng = _block_rng(seed + 7, x // (2 * u), y // (2 * u))
                if vrng.random() < 0.16 and _block_rng(seed + 9, x, y).random() < 0.55:
                    acc = (0.34, 0.27, 0.08)       # veio de minério
                    t += 0.20
                levels = 5
            elif pattern == "metal":
                # Chapa batida: costura de painel + rebite + escovado
                # diagonal. Faixa de valor mais ESTREITA que a da pedra de
                # propósito — metal tem albedo quase uniforme, quem desenha a
                # batida é o brilho especular, e exagerar aqui dá o efeito
                # "gelo rachado" já documentado no motor pintado.
                panel = 8 * u
                # Uma única direção de estrutura (escovado diagonal) + a
                # costura horizontal da chapa. A versão com costura nos DOIS
                # eixos mais risco diagonal virava xadrez escocês na peça
                # grande — chapa batida não tem grade.
                t = 0.54 + 0.13 * math.sin((x + y * 2.0) * math.pi / (3.0 * u))
                if y % panel == 0:
                    t = 0.20                       # costura entre chapas
                elif y % panel == 1:
                    t -= 0.12
                if x % panel == 2 * u and y % panel == 4 * u:
                    t = 0.98                       # rebite
                t += rng.uniform(-0.04, 0.04)
                levels = 5
            elif pattern == "roof_tile":
                tile_w, tile_h = 4 * u, 3 * u
                row = y // tile_h
                shift = (tile_w // 2) if row % 2 == 1 else 0
                col_i = (x + shift) // tile_w
                lx = (x + shift) % tile_w
                ly = y % tile_h
                trng = _block_rng(seed, col_i, row)
                t = trng.uniform(0.42, 0.64)
                # Barriga da telha em DOIS eixos: escura embaixo (onde a
                # fileira de cima cobre) e clara em cima, mais uma abóbada
                # lateral (seno) que arredonda a escama. Só o gradiente
                # vertical deixava a telha lendo como TIJOLO deitado.
                t += 0.26 * (ly / float(max(tile_h - 1, 1))) - 0.06
                t += 0.16 * math.sin(math.pi * (lx + 0.5) / float(tile_w)) - 0.06
                if ly == 0 or lx == 0:
                    t = 0.03                       # sulco entre telhas
                t += rng.uniform(-0.04, 0.04)
            elif pattern == "thatch":
                strand = _block_rng(seed, x, y // (4 * u))
                t = strand.uniform(0.32, 0.82)
                if y % (4 * u) == 0:
                    t = 0.06                       # sombra sob a fiada
                t += rng.uniform(-0.07, 0.07)
                levels = 5
            elif pattern == "cloth":
                # Pano: DOBRA larga (o que se lê a 16 m) + trama fina (o que se
                # lê no zoom). A dobra é o que separa estandarte de plástico.
                frng = _block_rng(seed, x // (5 * u), 0)
                # Amplitude MODERADA: numa túnica de tropa (o corpo tem ~10
                # texels de largura) uma dobra forte vira pijama listrado. A
                # dobra existe pro estandarte de 1 m, não pro peito de 30 cm.
                t = 0.38 + 0.26 * frng.random()
                t += 0.07 * math.sin(x * math.pi / (2.5 * u))
                if (x // u + y // u) % 2 == 0:
                    t += 0.05                      # trama
                if y % (6 * u) == 0:
                    t -= 0.10                      # costura horizontal
                t += rng.uniform(-0.04, 0.04)
            elif pattern == "grass":
                brng = _block_rng(seed, x // u, y // (2 * u))
                t = brng.uniform(0.26, 0.84) + rng.uniform(-0.08, 0.08)
                levels = 5
            elif pattern == "crop":
                # Lavoura: sulcos verticais alternando terra e broto.
                furrow = (x // (3 * u)) % 2
                t = 0.68 if furrow == 0 else 0.38
                if x % (3 * u) == 0:
                    t = 0.16
                t += rng.uniform(-0.08, 0.08)
                levels = 5
            elif pattern == "dirt":
                crng = _block_rng(seed, x // (2 * u), y // (2 * u))
                t = crng.uniform(0.32, 0.70) + rng.uniform(-0.10, 0.10)
                prng = _block_rng(seed + 3, x // u, y // u)
                if prng.random() < 0.08:
                    t += 0.24                      # pedrisco
                levels = 5
            elif pattern == "leaf":
                # Campo de valor CONTÍNUO (`leaf_field`, pré-calculado antes
                # do laço — ver lá) em vez do antigo `_block_rng` por célula
                # fixa de 2u: isso tira a ARESTA RETA da mancha, mas sozinho
                # não bastava — ver o `_quant_soft` abaixo.
                t = 0.20 + 0.80 * leaf_field[y][x] + rng.uniform(-0.03, 0.03)
                levels = 5
            elif pattern == "leaf_snow":
                # Copa NEVADA (Tundra, `pinheiro_nevado`/`moita_gelada`):
                # mesmo campo orgânico do `leaf` pra estrutura verde, mais um
                # viés VERTICAL de neve — acúmulo na ponta do galho, verde
                # sobrevivendo embaixo/nas bordas, não a copa inteira
                # embranquecida (pedido explícito do usuário).
                #
                # Mapeamento de eixo (confirmado em captura real, não só
                # dedução): `Builder.cone`/`prism` dão V=0 na BASE do galho e
                # V crescendo até a PONTA (ver "PILOTO de textura real por
                # UV" em `prop_meshes.gd`). Blender grava o buffer de pixel
                # de BAIXO PRA CIMA (`Canvas.flat()` no motor pintado
                # documenta isso) e inverte automaticamente ao exportar PNG —
                # então a linha `y = size-1` deste laço vira o TOPO do PNG
                # salvo, e é o TOPO do PNG que o sampler do Godot lê como
                # V=0. Ou seja: `y` ALTO (topo do laço) = V baixo = BASE do
                # galho; `y` BAIXO (fundo do laço) = V alto = PONTA do galho.
                # A neve mora em `y` baixo por isso, não por acaso.
                t = 0.20 + 0.80 * leaf_field[y][x] + rng.uniform(-0.03, 0.03)
                levels = 5
                vertical = 1.0 - (y / float(size - 1))  # 0 na base, 1 na ponta
                edge = snow_field[y][x]
                # Limiar alto (0.55) + ganho (2.6): só a metade de cima do
                # galho, MAIS a borda que o ruído recorta, vira neve — não um
                # degradê suave cobrindo a peça inteira.
                snow_amount = _clamp01((vertical * 0.85 + edge * 0.55 - 0.62) * 2.6)
            elif pattern == "window":
                border = (x < u) or (y < u) or (x >= size - u) or (y >= size - u)
                muntin = abs(x - size // 2) < u or abs(y - size // 2) < u
                if border:
                    t = 0.06
                elif muntin:
                    t = 0.22
                else:
                    # Vidraça: gradiente diagonal (a luz entrando) em degraus.
                    t = 0.52 + 0.42 * ((x + y) / float(2 * size))
                    t += rng.uniform(-0.05, 0.05)
            elif pattern == "glass":
                # Vitral em losangos de chumbo, com brilho diagonal amplo.
                # A vareta mora onde a diagonal ZERA — a primeira versão testava
                # o contrário (distância máxima) e desenhava um xadrez de
                # cruzes no MEIO de cada losango em vez do caixilho.
                per = 6 * u
                d1 = (x + y) % per
                d2 = (x - y) % per
                lead = min(min(d1, per - d1), min(d2, per - d2))
                t = 0.46 + 0.46 * ((x * 0.6 + y * 0.4) / float(size))
                if lead < u:
                    t = 0.20                       # vareta de chumbo
                t += rng.uniform(-0.04, 0.04)
            elif pattern == "picket":
                picket_w = 3 * u
                col_i = x // picket_w
                prng = _block_rng(seed, col_i, 0)
                t = prng.uniform(0.42, 0.74)
                local = x % picket_w
                if local == 0:
                    t = 0.10
                elif local == picket_w - 1:
                    t += 0.14
                if size // 2 - u <= y < size // 2 + u:
                    t -= 0.16                      # travessa da cerca
                t += rng.uniform(-0.05, 0.05)
            elif pattern == "rune":
                # Pedra arcana: base ESCURA com glifos claros esparsos. O glifo
                # entra como acento aditivo (violeta), não como valor, senão a
                # rampa o lavaria junto com o resto.
                t = 0.30 + rng.uniform(-0.08, 0.08)
                grng = _block_rng(seed, x // (4 * u), y // (4 * u))
                if grng.random() < 0.22 and (x % (4 * u)) // u in (1, 2) \
                        and (y % (4 * u)) // u in (1, 2):
                    acc = (0.30, 0.16, 0.46)
                    t += 0.34
                levels = 5
            elif pattern == "crystal":
                # Gema/chama: núcleo branco PEQUENO e corpo que segura a matiz.
                # A versão antiga somava +0.55 em todo canal a partir do centro
                # e, multiplicada pela emissão, entregava uma bolota branca —
                # é o defeito nº 1 do cabeçalho deste arquivo. Agora o realce é
                # exponencial (t**2.4), então só os poucos pixels do miolo
                # chegam ao branco e a borda continua laranja/violeta.
                cx, cy = size / 2.0, size / 2.0
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                r = _clamp01(1.0 - d / (size / 2.0))
                t = 0.42 + 0.58 * (r ** 2.4)
                levels = 5
            elif pattern == "hay":
                strand = _block_rng(seed, x, y // (3 * u))
                t = strand.uniform(0.34, 0.84)
                if y % (3 * u) == 0:
                    t -= 0.18
                t += rng.uniform(-0.07, 0.07)
                levels = 5
            else:  # "soft" — reboco, couro, pele, pano liso
                # Mosqueado de DUAS escalas: mancha larga (o que dá volume a
                # uma parede de reboco vista a 16 m) + poro fino. Antes era só
                # jitter por pixel, e uma parede inteira de reboco saía como
                # uma folha de papel com granulado.
                brng = _block_rng(seed, x // (5 * u), y // (5 * u))
                frng = _block_rng(seed + 5, x // u, y // u)
                # Amplitude BAIXA de propósito: `soft` é o reboco de toda
                # fachada enxaimel e a pele de todo humanoide. Mosqueado forte
                # aqui não lê como reboco, lê como mofo — e num rosto de 8 px
                # vira sujeira.
                t = 0.44 + 0.18 * brng.random() + 0.09 * frng.random()
                t += rng.uniform(-0.03, 0.03)
                levels = 5
            if pattern in ("leaf", "leaf_snow"):
                # `_quant` normal (usado por TODO o resto do arquivo) trata o
                # valor do Bayer como limiar de FORÇA TOTAL — a zona de
                # dithering cobre o degrau INTEIRO entre dois tons. Isso é o
                # look pixel art pretendido pra motivo com estrutura própria
                # (junta de pedra, veio de madeira), mas um campo que varia
                # DEVAGAR (como `leaf_field`, pincelada de baixa frequência)
                # fica quase constante em qualquer janela 4×4 — e dithering de
                # força total num campo quase constante devolve o próprio
                # xadrez de Bayer cru, pixel a pixel, de ponta a ponta: era
                # exatamente o "tecido quadriculado" que o usuário via de
                # perto na copa do pinheiro. `_quant_soft` é a MESMA técnica
                # já validada pro chão do bioma
                # (`generate_terrain_textures.py::_posterize`, parâmetro
                # `dither` em fração de degrau, não degrau inteiro): só uma
                # fatia do degrau dithera, o resto fica chapado, e o xadrez
                # sobrevive só na ORLA entre duas manchas — como pincelada,
                # não como trama de pano.
                col = _ramp(base_color, _quant_soft(t, levels, x, y, 0.45))
            else:
                dither = (_BAYER4[y & 3][x & 3] + 0.5) / 16.0
                col = _ramp(base_color, _quant(t, levels, dither))
            if acc is not None:
                col = (_clamp01(col[0] + acc[0]), _clamp01(col[1] + acc[1]),
                       _clamp01(col[2] + acc[2]))
            if snow_amount > 0.0:
                # LERP pra cor de neve (não `acc` aditivo): folhagem escura
                # + branco somado vira ciano, não neve — ver o comentário no
                # laço acima.
                sc = _SNOW_COLOR
                col = (col[0] + (sc[0] - col[0]) * snow_amount,
                       col[1] + (sc[1] - col[1]) * snow_amount,
                       col[2] + (sc[2] - col[2]) * snow_amount)
            idx = (y * size + x) * 4
            pixels[idx] = col[0]
            pixels[idx + 1] = col[1]
            pixels[idx + 2] = col[2]
            pixels[idx + 3] = 1.0

    img.pixels[:] = pixels
    img.pack()
    return img


def save_pixel_texture_png(path: str, base_color: tuple, pattern: str, size: int, seed: int) -> None:
    img = make_pixel_texture("Export_%d" % seed, base_color, pattern, size=size, seed=seed)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()


# ------------------------------------------------------- textura PINTADA
#
# Segunda técnica de textura do projeto, criada no revamp visual "estilo
# Valheim". `make_pixel_texture` continua existindo e continua sendo o padrão
# de todo builder antigo — nada aqui muda o que ele já gera.
#
# ── Por que uma técnica nova, e não "a mesma coisa maior" ────────────────
# O look pixel art vem de DUAS coisas ao mesmo tempo: resolução baixíssima
# (16 px) e decisão por pixel (dithering, jitter aleatório por pixel, degrau
# duro de cor). Só subir a resolução do gerador antigo daria chuvisco em alta
# resolução, não pintura. A textura pintada troca a decisão por pixel por
# CAMPOS CONTÍNUOS combinados, que é como uma textura pintada à mão se
# comporta: manchas grandes de valor, estrutura no meio, e quase nada de
# frequência alta.
#
# ── Por que numpy, e não nó procedural do Blender ────────────────────────
# `ShaderNodeTexNoise`/`ShaderNodeTexVoronoi` seriam o caminho "nativo", mas
# NÃO sobrevivem ao glTF: o exportador só grava IMAGEM, então uma árvore de
# ruído viraria "material sem textura" dentro do Godot. Assar o nó pra imagem
# exigiria `bpy.ops.object.bake` (Cycles + UV de bake + segundos por
# material) — inviável para ~150 assets. numpy já vem no Blender e resolve um
# campo de 256² em milissegundos, contra segundos do mesmo laço em Python
# puro; é a diferença entre iterar o visual e não iterar.
#
# ── As quatro camadas de toda textura pintada ────────────────────────────
#  1. ESTRUTURA: o motivo do material (fiada de blocos, veio da madeira,
#     placa martelada, dobra do pano), gerado como campo de ALTURA `h`.
#  2. AO/CAVIDADE: `h` menos `h` borrado. É o que escurece junta, fresta e
#     vinco — e é de longe o que mais dá leitura de "peça esculpida" numa
#     malha low-poly, sem custar SSAO nem oclusão de tela em runtime.
#  3. PINCELADA: ruído ANISOTRÓPICO de baixa frequência somado ao valor.
#     Variação de luz/sombra do tamanho de uma pincelada — o oposto do
#     jitter por pixel, que é justamente o chuvisco do estilo antigo.
#  4. DERIVA DE MATIZ POR VALOR: sombra puxa pro frio e mais saturado, luz
#     puxa pro quente e mais lavada. É o truque de pintura digital que separa
#     "cor multiplicada por um número" de "cor pintada".
#
# ── Normal map ───────────────────────────────────────────────────────────
# Como a camada 1 já produz um campo de altura, o normal map sai de graça
# (uma derivada) e resolve o problema que nenhuma textura de albedo resolve:
# a luz do jogo é DIRECIONAL e se move, e sem normal a "junta de pedra"
# pintada não muda com o sol — lê como adesivo. Ele é gerado em METADE da
# resolução do albedo, porque normal é um campo suave e a economia de bytes
# no .glb é direta.
#
# Tudo continua TILEÁVEL (treliça que dá a volta / distância toroidal) e 100%
# procedural, sem nenhum arquivo externo.

try:
    import numpy as _np
except ImportError:  # pragma: no cover — Blender sempre traz numpy
    _np = None

## Estilo em vigor. `clear_scene()` devolve pro padrão pixel de propósito:
## assim um builder que liga o modo pintado NUNCA vaza o estilo pro builder
## seguinte quando `generate_all.py` roda os ~150 assets no mesmo processo.
_STYLE = {"mode": "pixel", "size": 256, "normal": True}


def use_painted(enabled: bool = True, size: int = 256, normal: bool = True) -> None:
    """Liga o estilo PINTADO para os próximos `add_material()` deste builder.

    Chame logo DEPOIS de `clear_scene()` (que reseta o estilo). Uma linha por
    builder é de propósito: é assim que o revamp avança asset por asset sem
    um "big bang" que reexporta o catálogo inteiro de uma vez."""
    if enabled and _np is None:
        raise RuntimeError("estilo pintado exige numpy (Blender já traz)")
    _STYLE["mode"] = "painted" if enabled else "pixel"
    _STYLE["size"] = size
    _STYLE["normal"] = normal


def painted_style() -> bool:
    return _STYLE["mode"] == "painted"


# ------------------------------------------------------ campos (numpy)

def _pt_noise(size: int, cells_x: int, cells_y: int, seed: int):
    """Ruído de valor TILEÁVEL. `cells_x != cells_y` dá ruído ANISOTRÓPICO
    (esticado num eixo) — é o que produz veio de madeira, escovado de metal e
    pincelada direcional sem precisar rotacionar nada (rotação quebraria o
    ladrilho)."""
    rng = _np.random.default_rng(seed & 0x7FFFFFFF)
    g = rng.random((cells_y, cells_x))
    fx = _np.arange(size) * (cells_x / float(size))
    fy = _np.arange(size) * (cells_y / float(size))
    ix = fx.astype(_np.int64)
    iy = fy.astype(_np.int64)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    x0 = ix % cells_x
    x1 = (ix + 1) % cells_x
    y0 = iy % cells_y
    y1 = (iy + 1) % cells_y
    a = g[_np.ix_(y0, x0)] * (1.0 - tx)[None, :] + g[_np.ix_(y0, x1)] * tx[None, :]
    b = g[_np.ix_(y1, x0)] * (1.0 - tx)[None, :] + g[_np.ix_(y1, x1)] * tx[None, :]
    return a * (1.0 - ty)[:, None] + b * ty[:, None]


def _pt_noise_at(uf, vf, cells_x: int, cells_y: int, seed: int):
    """Mesmo ruído, mas amostrado em COORDENADAS ARBITRÁRIAS (campos `uf`/`vf`
    em unidades de ladrilho).

    Existe pra permitir estria DIAGONAL: passando `uf = u+v` e `vf = u-v` a
    treliça é cisalhada, e um cisalhamento de coeficientes INTEIROS preserva o
    ladrilho (ao contrário de uma rotação livre, que abriria costura). É o que
    deixa a grama vista de cima ter talo apontando pra quatro direções em vez
    de só duas."""
    rng = _np.random.default_rng(seed & 0x7FFFFFFF)
    g = rng.random((cells_y, cells_x))
    fx = uf * cells_x
    fy = vf * cells_y
    ix = _np.floor(fx).astype(_np.int64)
    iy = _np.floor(fy).astype(_np.int64)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    x0 = ix % cells_x
    x1 = (ix + 1) % cells_x
    y0 = iy % cells_y
    y1 = (iy + 1) % cells_y
    a = g[y0, x0] * (1.0 - tx) + g[y0, x1] * tx
    b = g[y1, x0] * (1.0 - tx) + g[y1, x1] * tx
    return a * (1.0 - ty) + b * ty


def _pt_combed(size: int, seed: int, across: int, along: int, sharp=(0.42, 0.86)):
    """Campo de "talos penteados": quatro camadas de estria (horizontal,
    vertical e as duas diagonais) misturadas por uma máscara de baixa
    frequência, de forma que cada região do ladrilho tem uma direção
    dominante. Um único eixo de estria lê como tecido riscado; quatro
    direções misturadas lêem como mato."""
    u, v = _pt_uv(size)
    dirs = ((u, v), (v, u), (u + v, u - v), (u - v, u + v))
    m = _pt_noise(size, 3, 3, seed + 441) * 4.0
    total = None
    weight_sum = None
    for i, (uf, vf) in enumerate(dirs):
        layer = _pt_step(sharp[0], sharp[1], _pt_noise_at(uf, vf, across, along, seed + 400 + i * 17))
        w = _np.exp(-((m - (0.5 + i)) / 0.75) ** 2)
        total = layer * w if total is None else total + layer * w
        weight_sum = w if weight_sum is None else weight_sum + w
    return total / _np.maximum(weight_sum, 1e-6)


def _pt_fbm(size: int, seed: int, octaves=((3, 0.55), (6, 0.30), (12, 0.15))):
    acc = None
    total = 0.0
    for i, (cells, weight) in enumerate(octaves):
        n = _pt_noise(size, cells, cells, seed + i * 977) * weight
        acc = n if acc is None else acc + n
        total += weight
    return acc / total


def _pt_blur(a, iterations: int = 1):
    """Borrão com EMBRULHO (np.roll): mantém a textura tileável, ao contrário
    de qualquer filtro que trate a borda como fim de imagem."""
    for _ in range(iterations):
        a = (a * 2.0 + _np.roll(a, 1, 0) + _np.roll(a, -1, 0)
             + _np.roll(a, 1, 1) + _np.roll(a, -1, 1)) / 6.0
    return a


def _pt_step(e0: float, e1: float, x):
    t = _np.clip((x - e0) / max(e1 - e0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _pt_worley(size: int, count: int, seed: int):
    """F1, F2 e índice da célula mais próxima, com distância TOROIDAL (é o
    toroidal que mantém as placas contínuas na emenda do ladrilho)."""
    rng = _np.random.default_rng(seed & 0x7FFFFFFF)
    pts = rng.random((count, 2))
    u = (_np.arange(size) + 0.5) / float(size)
    ux = u[None, :]
    uy = u[:, None]
    f1 = _np.full((size, size), 9.0)
    f2 = _np.full((size, size), 9.0)
    ids = _np.zeros((size, size), dtype=_np.int64)
    for i in range(count):
        dx = _np.abs(ux - pts[i, 0])
        dx = _np.minimum(dx, 1.0 - dx)
        dy = _np.abs(uy - pts[i, 1])
        dy = _np.minimum(dy, 1.0 - dy)
        d = _np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = _np.where(closer, f1, _np.minimum(f2, d))
        ids = _np.where(closer, i, ids)
        f1 = _np.where(closer, d, f1)
    return f1, f2, ids


def _pt_uv(size: int):
    u = ((_np.arange(size) + 0.5) / float(size))[None, :]
    v = ((_np.arange(size) + 0.5) / float(size))[:, None]
    return u + _np.zeros((size, size)), v + _np.zeros((size, size))


def _pt_bricks(size: int, seed: int, cols: int, rows: int, mortar: float,
               warp: float = 0.10):
    """Fiada de blocos assentada à mão: a grade é DEFORMADA por ruído antes de
    ser cortada, então nenhum bloco fica igual ao vizinho e a junta serpenteia
    de leve. Grade perfeita é o que faz alvenaria procedural parecer papel de
    parede. Devolve (máscara do bloco 0..1, valor por bloco, fu, fv)."""
    u, v = _pt_uv(size)
    u = u + (_pt_noise(size, 5, 5, seed + 71) - 0.5) * warp / cols
    v = v + (_pt_noise(size, 5, 5, seed + 83) - 0.5) * warp / rows
    fv_all = v * rows
    row = _np.floor(fv_all)
    fv = fv_all - row
    # `rows` PAR é obrigatório: a fiada alternada desloca meio bloco por linha
    # ímpar, e com `rows` ímpar essa alternância não fecha na emenda.
    bu = u * cols + 0.5 * (row % 2.0)
    col = _np.floor(bu)
    fu = bu - col
    mu = mortar * cols
    mv = mortar * rows
    mask = _np.minimum(_pt_step(0.0, mu, _np.minimum(fu, 1.0 - fu)),
                       _pt_step(0.0, mv, _np.minimum(fv, 1.0 - fv)))
    rng = _np.random.default_rng((seed + 601) & 0x7FFFFFFF)
    table = rng.random((rows, cols)) * 0.34 + 0.83
    vals = table[(row.astype(_np.int64) % rows), (col.astype(_np.int64) % cols)]
    return mask, vals, fu, fv


def _pt_fields(pattern: str, size: int, seed: int):
    """Devolve (altura 0..1, sombreamento ~0.5..1.3, acento) do padrão.

    `acento` é uma tupla (máscara, cor somada) ou None — usada só por padrões
    que têm um segundo material embutido (veio de minério, glifo de runa)."""
    rng = _np.random.default_rng((seed * 2654435761) & 0x7FFFFFFF)
    macro = _pt_fbm(size, seed + 11)
    fine = _pt_fbm(size, seed + 23, ((12, 0.6), (24, 0.4)))
    accent = None

    if pattern in ("stone", "brick"):
        mask, vals, fu, fv = _pt_bricks(size, seed, cols=3, rows=4, mortar=0.014)
        # Barriga do bloco: a pedra aparelhada é levemente abaulada, e é essa
        # curvatura que faz a luz rasante desenhar cada bloco separadamente.
        dome = (_np.sin(_np.pi * _np.clip(fu, 0.0, 1.0)) ** 0.35
                * _np.sin(_np.pi * _np.clip(fv, 0.0, 1.0)) ** 0.35)
        chip = _np.clip(fine - 0.66, 0.0, 1.0) * 2.4          # lascas nas quinas
        h = _np.clip(mask * (0.70 + 0.30 * dome) - chip * 0.25, 0.0, 1.0)
        # Aresta de cima do bloco pegando luz e base do bloco na sombra da
        # fiada de cima: é o par claro/escuro por bloco que faz alvenaria
        # pintada ler como PEDRA ASSENTADA, e não como grade desenhada.
        rim = _pt_step(0.86, 1.0, fv) * mask
        foot = (1.0 - _pt_step(0.0, 0.16, fv)) * mask
        pit = _pt_step(0.60, 0.90, _pt_fbm(size, seed + 37, ((18, 0.6), (37, 0.4))))
        shade = vals * (0.50 + 0.50 * mask) * (0.93 + 0.16 * macro)
        shade = shade * (1.0 + 0.20 * rim - 0.16 * foot - 0.14 * pit) * (0.97 + 0.06 * fine)
        h = _np.clip(h - 0.18 * pit, 0.0, 1.0)

    elif pattern in ("rock", "ore"):
        f1, f2, ids = _pt_worley(size, max(8, size // 18), seed + 91)
        plate = rng.random(max(8, size // 18)) * 0.34 + 0.82
        crack = _pt_step(0.0, 0.030, f2 - f1)
        bumps = _pt_fbm(size, seed + 101, ((6, 0.5), (13, 0.3), (26, 0.2)))
        h = _np.clip(crack * (0.45 + 0.55 * bumps), 0.0, 1.0)
        shade = plate[ids] * (0.52 + 0.48 * crack) * (0.88 + 0.26 * bumps)
        if pattern == "ore":
            vein = _pt_step(0.62, 0.80, fine) * (1.0 - crack * 0.4)
            accent = [(vein, (0.46, 0.38, 0.14))]

    elif pattern in ("wood", "log"):
        # Veio: anéis quase paralelos deformados por ruído esticado. O `abs`
        # do seno dá a linha ESCURA fina do veio, e não uma onda suave.
        warp = (_pt_noise(size, 3, 14, seed + 131) - 0.5) * 1.6
        _u, v = _pt_uv(size)
        rings = _np.abs(_np.sin(_np.pi * (v * 7.0 + warp)))
        fiber = _pt_noise(size, 2, 48, seed + 137)
        knot_d = _np.sqrt((_pt_uv(size)[0] - float(rng.random())) ** 2
                          + (v - float(rng.random())) ** 2)
        knot = 1.0 - _pt_step(0.03, 0.13, knot_d)
        h = _np.clip(0.35 + 0.5 * rings + 0.15 * fiber - knot * 0.5, 0.0, 1.0)
        shade = (0.80 + 0.30 * rings) * (0.92 + 0.14 * fiber) * (0.94 + 0.14 * macro)
        shade = shade * (1.0 - knot * 0.42)

    elif pattern in ("planks", "picket", "crop"):
        # Tábuas VERTICAIS com veio dentro de cada uma e fresta funda entre
        # elas (a fresta é o que separa tábua de "parede listrada").
        cols = 4
        u, v = _pt_uv(size)
        bu = u * cols
        col_i = _np.floor(bu)
        fu = bu - col_i
        gap = _pt_step(0.0, 0.05, _np.minimum(fu, 1.0 - fu))
        table = rng.random(cols) * 0.30 + 0.85
        vals = table[col_i.astype(_np.int64) % cols]
        # O veio corre AO LONGO da tábua (vertical). A primeira versão usava a
        # mesma fórmula do `wood` (veio horizontal) e as linhas cruzavam as
        # tábuas em ângulo reto — o resultado parecia mármore, não madeira.
        warp = (_pt_noise(size, 4, 3, seed + 151) - 0.5) * 0.9
        rings = _np.abs(_np.sin(_np.pi * (fu * 3.0 + warp)))
        h = _np.clip(gap * (0.55 + 0.45 * rings), 0.0, 1.0)
        shade = vals * (0.46 + 0.54 * gap) * (0.86 + 0.26 * rings) * (0.95 + 0.12 * macro)

    elif pattern == "metal":
        # Placa MARTELADA: mossas arredondadas (Worley borrado) + riscos finos.
        # Sem painel/rebite regular de propósito — a grade de rebites do estilo
        # antigo lê como chapa industrial, não como armadura batida à mão.
        count = max(10, size // 14)
        f1, f2, ids = _pt_worley(size, count, seed + 171)
        # Cada mossa é uma calota: fundo do martelo no centro da célula,
        # borda erguida onde duas mossas se encontram.
        dome = _np.clip(1.0 - f1 / 0.09, 0.0, 1.0) ** 0.7
        rim = _pt_step(0.0, 0.020, f2 - f1)
        face = rng.random(count) * 0.22 + 0.90
        scratch = _pt_step(0.72, 0.95, _pt_noise(size, 5, 90, seed + 181))
        h = _np.clip(0.30 + 0.55 * dome + 0.15 * rim, 0.0, 1.0)
        # A mossa é ESCURA no fundo e clara na borda erguida (é onde o polimento
        # sobrevive), mas com amplitude PEQUENA: metal tem albedo quase
        # uniforme, e quem desenha a batida é o normal map. A primeira versão
        # usava 0.34/0.22 aqui e a armadura saiu com uma teia branca de gelo
        # rachado — o erro clássico de tratar o mapa de altura como se fosse
        # iluminação.
        shade = (face[ids] * (0.90 + 0.13 * (1.0 - dome) + 0.07 * (1.0 - rim))
                 * (0.98 + 0.10 * scratch) * (0.97 + 0.08 * macro))

    elif pattern in ("cloth", "tent"):
        # Pano: DOBRA larga (o que se lê a 20 m de câmera) + trama fina (o que
        # se lê no zoom máximo). A trama entra fraquíssima de propósito.
        fold = _pt_noise(size, 2, 7, seed + 191) * 0.65 + _pt_noise(size, 6, 3, seed + 197) * 0.35
        u, v = _pt_uv(size)
        weave = (_np.sin(u * _np.pi * 2.0 * 20.0) * _np.sin(v * _np.pi * 2.0 * 20.0)) * 0.5 + 0.5
        h = _np.clip(0.30 + 0.60 * fold + 0.10 * weave, 0.0, 1.0)
        cav = h - _pt_blur(h, 8)
        # A DOBRA entra direto no valor (e não só via cavidade): pano visto a
        # 20 m de câmera só se distingue de plástico pintado pela dobra larga.
        shade = (0.76 + 0.44 * fold) * (1.0 + 1.4 * cav) * (0.97 + 0.06 * weave)
        shade = shade * (0.94 + 0.13 * macro)

    elif pattern in ("thatch", "hay", "leaf", "grass"):
        # Feixes/folhas: ruído muito esticado num eixo, cortado em degraus —
        # cada degrau vira um talo com sombra própria embaixo.
        strand = _pt_combed(size, seed + 211, across=40, along=7, sharp=(0.36, 0.80))
        band = _pt_noise(size, 3, 22, seed + 223)
        h = _np.clip(0.20 + 0.60 * strand + 0.30 * band, 0.0, 1.0)
        cav = h - _pt_blur(h, 4)
        shade = (0.80 + 0.34 * strand) * (0.90 + 0.22 * band) * (1.0 + 0.7 * cav)
        shade = shade * (0.93 + 0.14 * macro)

    elif pattern == "roof_tile":
        # Telha: fiada de escamas. A ALTURA cai pra zero na sobreposição de
        # cima, que é onde a telha de baixo entra por baixo — e é essa sombra
        # em faixa que faz um telhado parecer telhado, mesmo sem geometria.
        mask, vals, fu, fv = _pt_bricks(size, seed + 5, cols=4, rows=6, mortar=0.008,
                                        warp=0.05)
        scallop = _np.sin(_np.pi * _np.clip(fu, 0.0, 1.0)) ** 0.5
        lip = _pt_step(0.0, 0.45, fv)
        h = _np.clip(mask * scallop * (0.25 + 0.75 * lip), 0.0, 1.0)
        shade = vals * (0.45 + 0.55 * h) * (0.94 + 0.13 * macro)

    elif pattern in ("glass", "window"):
        # Vidro soprado: losangos de chumbo e um brilho diagonal amplo. Quase
        # nenhuma estrutura — o resto vem do material (roughness/emissão).
        u, v = _pt_uv(size)
        lead = _np.minimum(_np.abs(((u + v) * 5.0) % 1.0 - 0.5),
                           _np.abs(((u - v) * 5.0) % 1.0 - 0.5))
        lead_mask = _pt_step(0.02, 0.10, lead)
        sheen = _pt_step(0.2, 0.9, (u * 0.6 + v * 0.4 + macro * 0.35))
        h = lead_mask
        shade = (0.72 + 0.28 * lead_mask) * (0.92 + 0.38 * sheen)

    elif pattern == "crystal":
        # Facetas de gema: células de Worley com valor por faceta e brilho
        # concentrado no MEIO da faceta (não no meio do tile, que era o que
        # estourava a peça grande no gerador antigo).
        f1, f2, ids = _pt_worley(size, max(5, size // 30), seed + 231)
        face = rng.random(max(5, size // 30)) * 0.5 + 0.75
        edge = _pt_step(0.0, 0.05, f2 - f1)
        h = edge
        # O brilho vive no MIOLO da faceta (f1 pequeno), não na aresta — e com
        # amplitude BAIXA: `crystal` é usado quase sempre com `emission`, e
        # qualquer clareamento aqui é multiplicado pela energia emissiva. Era
        # o defeito documentado no cabeçalho deste arquivo (item 1) e a versão
        # pintada não pode reintroduzi-lo.
        shade = face[ids] * (0.62 + 0.30 * edge) * (1.0 + 0.14 * (1.0 - _pt_step(0.0, 0.10, f1)))

    elif pattern in ("dirt", "soil"):
        clod = _pt_fbm(size, seed + 241, ((5, 0.5), (11, 0.3), (23, 0.2)))
        count = max(16, size // 8)
        f1, _f2, ids = _pt_worley(size, count, seed + 247)
        # Pedrisco: só as células menores viram pedra (senão o chão inteiro
        # vira calçamento), e cada uma com o próprio tom.
        pick = rng.random(count)
        pebble = (_np.clip(1.0 - f1 / 0.030, 0.0, 1.0) ** 0.6) * (pick[ids] > 0.62)
        h = _np.clip(0.45 * clod + 0.55 * pebble, 0.0, 1.0)
        cav = h - _pt_blur(h, 5)
        shade = ((0.78 + 0.46 * clod) * (1.0 + 1.3 * cav) * (0.95 + 0.10 * macro)
                 * (1.0 + 0.22 * pebble))

    elif pattern == "ground_grass":
        # Chão gramado visto DE CIMA. Único padrão pensado pra ladrilhar em
        # METROS (3 m por tile) e ser visto de cima, então a escala do detalhe
        # é outra: o "talo" aqui tem ~4 cm, não 1 cm — talo de 1 cm vira papa
        # cinza na primeira mipmap e o chão volta a parecer chapado.
        #
        # A leitura vem dos TRAÇOS PENTEADOS (`_pt_combed`), não de células:
        # a primeira versão usava Worley pra "moita" e o resultado foi
        # camuflagem poligonal — célula de Worley tem borda RETA, e nada num
        # gramado tem borda reta.
        blades = _pt_combed(size, seed + 251, across=56, along=10, sharp=(0.38, 0.82))
        tuft = _pt_fbm(size, seed + 257, ((7, 0.55), (15, 0.30), (31, 0.15)))
        h = _np.clip(0.20 + 0.50 * blades + 0.40 * tuft, 0.0, 1.0)
        cav = h - _pt_blur(h, 5)
        shade = ((0.62 + 0.60 * blades) * (0.84 + 0.34 * tuft)
                 * (1.0 + 1.1 * cav) * (0.90 + 0.22 * macro))
        # Manchas SECAS (mais amarelas) e terra aparecendo: as duas raras e de
        # borda suave. Confete de terra a cada metro é o defeito clássico de
        # chão procedural — aqui a mancha tem o tamanho de uma pisada.
        dry = _pt_step(0.58, 0.86, macro) * 0.55
        bare = _pt_step(0.86, 0.98, macro) * 0.7
        flower = _pt_step(0.988, 0.997, _pt_noise(size, size // 5, size // 5, seed + 271))
        accent = [(dry, (0.10, 0.06, -0.05)),
                  (bare, (0.14, 0.07, 0.01)),
                  (flower, (0.55, 0.50, 0.10))]

    else:  # "soft" — couro, pele, pano liso, e todo padrão ainda não portado
        # Mosqueado orgânico: manchas largas + poro fino. Serve de rede de
        # segurança pro fan-out: padrão sem implementação própria sai pintado
        # em vez de quebrar o builder.
        f1, _f2, _ids = _pt_worley(size, max(12, size // 10), seed + 271)
        pore = _pt_step(0.0, 0.05, f1)
        h = _np.clip(0.35 + 0.45 * macro + 0.20 * pore, 0.0, 1.0)
        cav = h - _pt_blur(h, 5)
        shade = (0.88 + 0.26 * macro) * (1.0 + 0.9 * cav) * (0.96 + 0.08 * fine)

    # --- camada 3: pincelada (variação de valor larga e direcional) --------
    brush = (_pt_noise(size, 3, 11, seed + 311) + _pt_noise(size, 11, 3, seed + 317)) * 0.5
    shade = shade * (0.90 + 0.20 * brush)
    # --- "tooth" da tinta: granulado mínimo, só pra não ficar plástico -----
    shade = shade * (0.985 + 0.03 * _pt_noise(size, size // 3, size // 3, seed + 331))
    return _np.clip(h, 0.0, 1.0), shade, accent


def painted_rgb(base_color: tuple, pattern: str = "soft", size: int = 256, seed: int = 0):
    """Albedo (H×W×3 float) + altura (H×W float) do padrão pintado.

    Separado de `make_painted_texture` porque quem exporta PNG de terreno
    (`generate_terrain_textures.py`) precisa dos pixels, não de um datablock
    de imagem do Blender."""
    h, shade, accent = _pt_fields(pattern, size, seed)
    base = _np.array(base_color, dtype=_np.float64)[None, None, :]
    # Camada 4: deriva de matiz por valor. `k` é o quanto o pixel está acima
    # (>0) ou abaixo (<0) do valor médio do material.
    k = _np.clip((shade - 1.0) / 0.35, -1.0, 1.0)[:, :, None]
    lum = float(base.mean())
    # Sombra mais SATURADA, luz mais LAVADA — o contrário do que um simples
    # multiplicador faz, e o que dá a sensação de tinta em vez de filtro.
    sat = 1.0 - 0.24 * k
    col = lum + (base - lum) * sat
    warm = _np.array([1.05, 1.00, 0.92])[None, None, :]
    cool = _np.array([0.94, 0.98, 1.08])[None, None, :]
    tint = _np.where(k > 0.0, 1.0 + (warm - 1.0) * k, 1.0 + (cool - 1.0) * (-k))
    rgb = _np.clip(col * shade[:, :, None] * tint, 0.0, 1.0)
    if accent is not None:
        # Componente NEGATIVA é legítima: tirar azul é como se puxa uma mancha
        # de grama pro amarelo-seco sem lavar a cor toda.
        for mask, acc in (accent if isinstance(accent, list) else [accent]):
            rgb = _np.clip(rgb + _np.array(acc)[None, None, :] * mask[:, :, None], 0.0, 1.0)
    return rgb, h


def painted_grass_card(size: int = 256, seed: int = 0, blades: int = 9,
                        lean: float = 0.30):
    """Textura de UMA TOUCEIRA pra "grass card" (quad com recorte por alfa).

    Devolve (valor RGB em CINZA, alfa). O cinza é de propósito: quem pinta a
    grama é o bioma, dentro do shader (`color_base`/`color_tip`), e uma
    textura já verde multiplicaria cor por cor — o musgo azul da Caverna
    sairia verde-azulado sujo. Aqui a textura carrega só o DESENHO (silhueta
    da folha, base escura, ponta clara, nervura) e o bioma carrega a cor.

    Por que card e não malha: um quad (2 triângulos) mostra uma touceira
    inteira, contra 9 triângulos de uma moita de 3 lâminas em geometria. No
    mesmo orçamento de instância dá pra ter várias vezes mais grama — que é
    exatamente o que a referência (Valheim) pede."""
    rng = _np.random.default_rng((seed * 7919 + 13) & 0x7FFFFFFF)
    val = _np.zeros((size, size))
    alpha = _np.zeros((size, size))
    xs = _np.arange(size) + 0.5
    for b in range(blades):
        # Folha de base larga que afina até a ponta, com curvatura acumulada:
        # reta ela lê como palito de fósforo, e é a curva que dá o "peso" de
        # folha caindo pro lado.
        x0 = rng.uniform(0.10, 0.90) * size
        tilt = rng.uniform(-lean, lean) * size
        bow = rng.uniform(0.3, 1.0) * tilt
        # Folha LARGA (3–6% da largura do card, não 2–4%): a referência tem
        # folha de capim, não agulha de pinheiro — e folha fina demais vira
        # chuvisco assim que a mipmap entra.
        w0 = rng.uniform(0.030, 0.062) * size
        top = rng.uniform(0.52, 1.0) * size
        tone = rng.uniform(0.80, 1.14)
        rows = int(top)
        if rows < 4:
            continue
        t = (_np.arange(rows) + 0.5) / float(rows)
        cx = x0 + tilt * t + bow * t * t
        hw = _np.maximum(w0 * (1.0 - t) ** 0.65, 0.6)
        d = _np.abs(xs[None, :] - cx[:, None])
        a = _np.clip(hw[:, None] - d + 0.5, 0.0, 1.0)
        # Nervura: centro mais claro que a borda. Sem isso a folha é uma fita
        # chapada e a touceira inteira vira uma mancha só.
        rib = 1.0 - 0.30 * _np.clip(d / _np.maximum(hw[:, None], 0.6), 0.0, 1.0) ** 2
        v = (0.32 + 0.56 * t)[:, None] * tone * rib
        band = slice(0, rows)
        val[band] = val[band] * (1.0 - a) + v * a
        alpha[band] = _np.maximum(alpha[band], a)
    # Camada 3 do estilo pintado também aqui: variação de valor larga, pra as
    # folhas não saírem todas com o mesmo tom.
    val = val * (0.92 + 0.16 * _pt_fbm(size, seed + 313, ((3, 0.6), (7, 0.4))))
    rgb = _np.clip(_np.repeat(val[:, :, None], 3, axis=2), 0.0, 1.0)
    return rgb, alpha


def painted_ground_patch(base_color: tuple = (0.40, 0.30, 0.19), size: int = 256,
                          seed: int = 0, pattern: str = "dirt"):
    """Mancha de chão batido (terra) com BORDA ORGÂNICA em alfa.

    É o pátio de terra que todo RTS desenha em volta de uma construção. A
    borda não é um círculo nem um quadrado: é um quadrado arredondado
    deformado por ruído, porque borda geométrica limpa denuncia na hora que é
    um decalque colado."""
    rgb, _h = painted_rgb(base_color, pattern, size=size, seed=seed)
    u, v = _pt_uv(size)
    au = _np.abs(2.0 * u - 1.0)
    av = _np.abs(2.0 * v - 1.0)
    # Expoente 4 = quadrado de cantos arredondados. Quadrado puro (max) daria
    # canto vivo; círculo deixaria os cantos do footprint com grama por dentro.
    d = (au ** 4.0 + av ** 4.0) ** 0.25
    d = d + (_pt_fbm(size, seed + 91, ((4, 0.6), (9, 0.4))) - 0.5) * 0.18
    # A rampa começa em 0.78, e NÃO em 0.58 como na primeira versão. O número
    # parece cosmético e não é: ele decide se o pátio existe na tela.
    #
    # O quad do pátio tem o tamanho do footprint MAIS a margem, e o miolo opaco
    # cobre só `rampa × meia-largura` dele. Com 0.58, o pátio de 5,5 m do Núcleo
    # (footprint de 4 m + 0,75 de margem) só era opaco nos 3,2 m centrais — ou
    # seja, INTEIRAMENTE debaixo de um prédio de 4,2 m. O que sobrava pra fora
    # era só a cauda da transparência, invisível contra o chão. O pátio estava
    # sendo desenhado o tempo todo; ninguém conseguia vê-lo. (A depuração
    # perseguiu ordem de nó, altura do decalque e instante de entrada na árvore
    # antes de cair aqui — ver `GrassField._spawn_apron`.)
    #
    # Com 0.78 o miolo opaco chega perto da borda do quad e a transparência
    # vira o que ela devia ser desde o começo: o acabamento macio da beirada,
    # não a maior parte do decalque.
    alpha = 1.0 - _pt_step(0.78, 1.0, d)
    return rgb, _np.clip(alpha, 0.0, 1.0)


def painted_ground_detail(size: int = 512, seed: int = 0, contrast: float = 1.0):
    """Mapa de DETALHE do chão do platô — cinza, sem cor nenhuma.

    Por que cinza e não a textura pintada colorida: o chão da área jogável não
    é desenhado por um `StandardMaterial3D` com albedo, e sim pelo
    `ground.gdshader`, que recebe do bioma as duas cores do terreno
    (`ground_tint`/`ground_tint_alt`) e PRECISA continuar mandando na cor — é
    ela que faz a emenda com o relevo decorativo (`terrain.gdshader`)
    desaparecer, e é ela que separa o gramado da Floresta da neve da Tundra e
    da rocha da Terra Abrasada. Uma textura já verde multiplicada por cima
    sujaria os biomas sem grama, que é exatamente o defeito que o usuário
    mandou remover do chão na rodada passada (chão "sujo" de pixel art).

    Então o que sai daqui é só o DESENHO — a pincelada, o talo de ~4 cm, a
    cava entre as moitas — empacotado em três canais que o shader combina com
    a paleta do bioma:

    * **R** = valor (sombreamento) centrado em 0.5. `0.5` = neutro, abaixo é
      sombra, acima é luz. O shader converte de volta pra multiplicador.
    * **G** = mancha SECA/gasta, de borda macia. O shader usa como peso da
      mistura `tint` → `tint_alt`, ou seja, a mancha sai na cor que o bioma
      escolheu pro seu próprio segundo tom — nunca num amarelo fixo.
    * **B** = terra aparecendo (raro, menor que a mancha seca). Mesmo destino,
      só que com peso maior — é o núcleo da mancha gasta.

    Ladrilha em METROS (o `ground_grass` foi desenhado pra ~3 m por tile) e
    NÃO em UV de malha: o platô é um plano de 102 m e uma UV única esticaria
    um texel por metro."""
    _h, shade, _accent = _pt_fields("ground_grass", size, seed)
    # `shade` sai do motor em torno de ~0.5..1.3. Recentrar em 0.5 aqui (e não
    # no shader) é o que permite guardar tudo num PNG de 8 bits sem estourar
    # nem achatar a faixa útil.
    #
    # A média é normalizada pela MÉDIA MEDIDA, e não pelo 1.0 nominal: cada
    # padrão do motor tem seu próprio viés (o `ground_grass` sai perto de 0.9,
    # porque a cava entre as moitas escurece mais do que a ponta clareia). Sem
    # isto o mapa entra no shader como um multiplicador médio de ~0.93 e
    # ESCURECE a cor do bioma — o chão da Tundra deixaria de ser a mesma neve
    # que o relevo decorativo desenha, e a emenda platô ↔ relevo voltaria a
    # aparecer. Neutro na média é o contrato: o mapa dá textura, nunca cor.
    val = _np.clip(0.5 + (shade / float(shade.mean()) - 1.0) * 0.85 * contrast,
                   0.0, 1.0)
    # As duas máscaras vêm do MESMO `macro` que o padrão usa pros acentos de
    # cor (ver `_pt_fields`, ramo "ground_grass"), com os mesmos limiares: é o
    # que faz a mancha de valor e a mancha de cor caírem no mesmo lugar, em
    # vez de brigarem uma com a outra.
    macro = _pt_fbm(size, seed + 11)
    dry = _pt_step(0.56, 0.88, macro)
    bare = _pt_step(0.86, 0.99, macro)
    rgb = _np.stack([val, dry, bare], axis=-1)
    return _np.clip(rgb, 0.0, 1.0)


def save_painted_rgb_png(path: str, rgb) -> None:
    """PNG opaco (sem canal alfa) — mapa de dados lido por shader.

    Separado do `save_painted_rgba_png` porque o import do Godot decide o
    formato de compressão pela presença de alfa: um mapa de 3 canais gravado
    com alfa constante vira RGBA na VRAM e paga 33% a mais por nada."""
    img = _pt_image("PaintedRGB", rgb)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def save_painted_rgba_png(path: str, rgb, alpha) -> None:
    img = _pt_image("PaintedRGBA", rgb, alpha=alpha, use_alpha=True)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def _pt_image(name: str, rgb, alpha=1.0, non_color: bool = False,
              use_alpha: bool = False):
    size_y, size_x = rgb.shape[0], rgb.shape[1]
    img = bpy.data.images.new(name, width=size_x, height=size_y, alpha=use_alpha)
    flat = _np.empty((size_y, size_x, 4), dtype=_np.float32)
    flat[:, :, 0:3] = rgb
    flat[:, :, 3] = alpha
    img.pixels.foreach_set(flat.reshape(-1))
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.pack()
    return img


def make_painted_texture(name: str, base_color: tuple, pattern: str = "soft",
                          size: int = 256, seed: int = 0, normal: bool = True,
                          normal_strength: float = 2.4):
    """Devolve (albedo, normal|None) já como datablocks de imagem empacotados.

    O normal sai em METADE da resolução: é um campo suave, ninguém enxerga a
    diferença na tela, e ele é a maior fatia de bytes que a textura pintada
    acrescenta ao .glb."""
    rgb, h = painted_rgb(base_color, pattern, size=size, seed=seed)
    img = _pt_image(name, rgb)
    if not normal:
        return img, None
    half = h.reshape(size // 2, 2, size // 2, 2).mean(axis=(1, 3))
    # Derivada central COM embrulho: normal map de textura tileável não pode
    # tratar a borda como fim de imagem, senão aparece um vinco na emenda.
    dx = (_np.roll(half, -1, 1) - _np.roll(half, 1, 1)) * normal_strength
    dy = (_np.roll(half, -1, 0) - _np.roll(half, 1, 0)) * normal_strength
    inv = 1.0 / _np.sqrt(dx * dx + dy * dy + 1.0)
    nrm = _np.stack([(-dx * inv) * 0.5 + 0.5, (-dy * inv) * 0.5 + 0.5, inv * 0.5 + 0.5], axis=-1)
    return img, _pt_image(name + "_N", nrm, non_color=True)


def save_painted_texture_png(path: str, base_color: tuple, pattern: str, size: int,
                              seed: int) -> None:
    """Exporta a textura pintada como PNG solto (usado pelo chão do platô)."""
    rgb, _h = painted_rgb(base_color, pattern, size=size, seed=seed)
    img = _pt_image("PaintedExport_%d" % seed, rgb)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def add_material(obj, color: tuple, pattern: str = "soft", roughness: float = 0.85,
                  metallic: float = 0.0, emission: tuple = None, emission_energy: float = 1.8,
                  texture_size: int = 0, style: str = None) -> None:
    """Materiais idênticos são compartilhados (cache) — menos texturas
    embutidas no .glb, arquivo menor e import do Godot mais limpo.

    `style` força "pixel" ou "painted" nesta peça; sem ele vale o estilo do
    builder (`use_painted()`). Repare que roughness/metallic/emission NÃO
    mudam de significado entre os dois estilos: o revamp visual troca a
    TEXTURA, não o modelo de material."""
    mode = style or _STYLE["mode"]
    # `texture_size` só é respeitado quando o builder pediu um tamanho de
    # propósito; sem pedido (0), cada estilo usa a resolução DELE — 256 px no
    # pintado, `PIXEL_SIZE` no pixel art. Antes o sentinela era o literal 16, o
    # que amarrava a resolução do pixel art dentro de um `if` do modo pintado.
    if texture_size <= 0:
        texture_size = _STYLE["size"] if mode == "painted" else PIXEL_SIZE
    # Quantiza a cor em degraus de 0.05 pra colapsar tons quase idênticos
    # (peças "meio tom mais escuras") num material só — cada material vira
    # uma superfície separada no Godot, ou seja, uma draw call por prédio.
    def q(c):
        return round(round(c / 0.05) * 0.05, 3)
    key = (tuple(q(c) for c in color), pattern, round(roughness, 1), round(metallic, 1),
           None if emission is None else tuple(q(c) for c in emission),
           round(emission_energy, 1), texture_size, mode)
    mat = _MAT_CACHE.get(key)
    if mat is None:
        _TEX_COUNTER[0] += 1
        idx = _TEX_COUNTER[0]
        mat = bpy.data.materials.new(name="Mat_%s_%d" % (pattern, idx))
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic

        normal_img = None
        if mode == "painted":
            img, normal_img = make_painted_texture(
                "Tex_%s_%d" % (pattern, idx), color, pattern,
                size=texture_size, seed=idx * 17 + 3, normal=_STYLE["normal"])
        else:
            img = make_pixel_texture("Tex_%s_%d" % (pattern, idx), color, pattern,
                                      size=texture_size, seed=idx * 17 + 3)
        tex_node = nodes.new("ShaderNodeTexImage")
        tex_node.image = img
        # 'Closest' é o que preserva o degrau duro do pixel art; na textura
        # pintada ele faria justamente o contrário do pretendido.
        tex_node.interpolation = 'Closest' if mode == "pixel" else 'Linear'
        tex_node.extension = 'REPEAT'
        links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])

        if normal_img is not None:
            nrm_node = nodes.new("ShaderNodeTexImage")
            nrm_node.image = normal_img
            nrm_node.interpolation = 'Linear'
            nrm_node.extension = 'REPEAT'
            # O `Normal Map` no meio não é enfeite: sem ele o exportador glTF
            # não reconhece a imagem como mapa de normal e ela sai como uma
            # textura de cor qualquer (ou não sai).
            map_node = nodes.new("ShaderNodeNormalMap")
            links.new(nrm_node.outputs["Color"], map_node.inputs["Color"])
            links.new(map_node.outputs["Normal"], bsdf.inputs["Normal"])

        if emission is not None:
            bsdf.inputs["Emission Strength"].default_value = emission_energy
            links.new(tex_node.outputs["Color"], bsdf.inputs["Emission Color"])
        _MAT_CACHE[key] = mat

    obj.data.materials.append(mat)


def finish(obj, color: tuple, pattern: str = "soft", jitter_amount: float = 0.0,
           bevel_width: float = 0.022, tex_scale: float = 1.0, uv: str = "cube",
           **mat_kwargs):
    """Fecha uma peça: chanfro -> jitter -> flat shading -> UV -> material."""
    bevel(obj, bevel_width)
    if jitter_amount > 0.0:
        jitter(obj, jitter_amount)
    flat_shade(obj)
    if uv == "cube":
        cube_unwrap(obj, tex_scale)
    else:
        unwrap(obj)
    add_material(obj, color, pattern, **mat_kwargs)
    return obj


# ------------------------------------------------------------- primitivas

def make_box(name: str, size: tuple, loc: tuple, rot: tuple = (0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    obj.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def add_box(name: str, size: tuple, loc: tuple, color: tuple, rot: tuple = (0, 0, 0),
            jitter_amount: float = 0.0, pattern: str = "soft", bevel_width: float = 0.022,
            tex_scale: float = 1.0, **mat_kwargs):
    obj = make_box(name, size, loc, rot)
    if rot != (0, 0, 0):
        _activate(obj)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        obj.select_set(False)
    return finish(obj, color, pattern, jitter_amount, bevel_width, tex_scale, **mat_kwargs)


def add_cylinder(name: str, top_r: float, bottom_r: float, height: float, loc: tuple,
                  color: tuple, vertices: int = 8, rot: tuple = (0, 0, 0), pattern: str = "soft",
                  bevel_width: float = 0.02, tex_scale: float = 1.0, jitter_amount: float = 0.0,
                  squash: tuple = None, **mat_kwargs):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=bottom_r, radius2=top_r,
                                     depth=height, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    _squash(obj, squash)
    return finish(obj, color, pattern, jitter_amount, bevel_width, tex_scale, **mat_kwargs)


def _squash(obj, squash: tuple) -> None:
    """Escala NÃO uniforme aplicada antes do acabamento.

    Precisa ser APLICADA (transform_apply) e não deixada na escala do objeto:
    `cube_unwrap` projeta a UV usando `matrix_world`, então uma escala pendente
    esticaria a textura junto com a peça — a mesma pedra ficaria com tijolo
    achatado num lugar e redondo noutro."""
    if squash is None:
        return
    obj.scale = squash
    prev = _activate(obj)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    _restore(prev, obj)


def add_sphere(name: str, radius: float, loc: tuple, color: tuple, subdivisions: int = 1,
               jitter_amount: float = 0.0, pattern: str = "soft", tex_scale: float = 1.0,
               squash: tuple = None, **mat_kwargs):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    _squash(obj, squash)
    return finish(obj, color, pattern, jitter_amount, 0.0, tex_scale, **mat_kwargs)


def add_capsule(name: str, radius: float, height: float, loc: tuple, color: tuple,
                 jitter_amount: float = 0.03, pattern: str = "soft", tex_scale: float = 1.0,
                 **mat_kwargs):
    """Corpo low-poly tipo 'pill': ico sphere esticada no eixo Z (altura)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    stretch = max(height / (radius * 2.0), 1.0)
    obj.scale = (1.0, 1.0, stretch)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, color, pattern, jitter_amount, 0.0, tex_scale, **mat_kwargs)


def make_prism(name: str, profile: list, depth: float, loc: tuple, axis: str = 'Y',
                rot: tuple = (0, 0, 0)):
    """Extruda um perfil 2D ao longo de `axis` (X, Y ou Z), centrado em `loc`.
    Para axis='Y' o perfil é lido como (x, z); para 'X' como (y, z); para 'Z'
    como (x, y). Base de arcos, empenas triangulares e cortes pontiagudos."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    h = depth / 2.0
    front, back = [], []
    for a, b in profile:
        if axis == 'Y':
            front.append(bm.verts.new((a, -h, b)))
            back.append(bm.verts.new((a, h, b)))
        elif axis == 'X':
            front.append(bm.verts.new((-h, a, b)))
            back.append(bm.verts.new((h, a, b)))
        else:
            front.append(bm.verts.new((a, b, -h)))
            back.append(bm.verts.new((a, b, h)))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = rot
    if rot != (0, 0, 0):
        _activate(obj)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        obj.select_set(False)
    return obj


def add_prism(name: str, profile: list, depth: float, loc: tuple, color: tuple,
              axis: str = 'Y', rot: tuple = (0, 0, 0), pattern: str = "soft",
              bevel_width: float = 0.02, tex_scale: float = 1.0, jitter_amount: float = 0.0,
              **mat_kwargs):
    obj = make_prism(name, profile, depth, loc, axis, rot)
    return finish(obj, color, pattern, jitter_amount, bevel_width, tex_scale, **mat_kwargs)


# ------------------------------------------------------------------ faces

_FACES = {
    '+Z': ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0)),
    '-Z': ((0.0, 0.0, -1.0), (-1.0, 0.0, 0.0)),
    '+X': ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
    '-X': ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
}


def _fpos(center: tuple, face: str, u: float, v: float, w: float) -> tuple:
    """Posição em Godot a partir de coordenadas locais da fachada:
    u = lateral, v = altura, w = pra fora da parede."""
    out, right = _FACES[face]
    return (center[0] + right[0] * u + out[0] * w,
            center[1] + v,
            center[2] + right[2] * u + out[2] * w)


def _fsize(face: str, width: float, thick: float, height: float) -> tuple:
    """Tamanho em eixos Blender pra uma peça colada numa fachada."""
    if face in ('+Z', '-Z'):
        return (width, thick, height)
    return (thick, width, height)


# Sinal do bico da ogiva por fachada. As duas metades do arco são caixas
# giradas em torno de um eixo do Blender, e o sentido "pra cima no meio" não
# é o mesmo nas quatro faces — sem esta tabela, duas das fachadas saíam com o
# arco de cabeça pra baixo (um V em vez de um ^). Valores conferidos num
# probe com janela ogival nas 4 faces (tools/blender/_arch_probe.py).
_ARCH_FLIP = {'+Z': -1.0, '-Z': 1.0, '+X': 1.0, '-X': -1.0}


def _faxis(face: str) -> str:
    """Eixo de extrusão (Blender) pra um prisma encaixado na fachada."""
    return 'Y' if face in ('+Z', '-Z') else 'X'


# ------------------------------------------------------- aberturas 3D reais

WOOD_DARK = (0.30, 0.20, 0.12)
WOOD_MID = (0.44, 0.31, 0.19)
IRON = (0.17, 0.17, 0.19)
GLASS_WARM = (0.95, 0.72, 0.32)


def cut_niche(wall, center: tuple, face: str, width: float, height: float,
              depth: float, arch: float = 0.0) -> None:
    """Escava um nicho (cego, não atravessa) na parede. `arch` > 0 dá topo
    pontiagudo/ogival de altura `arch`."""
    if wall is None:
        return
    out_len = 0.25
    total = depth + out_len
    w_center = (out_len - depth) / 2.0
    loc = to_bloc(*_fpos(center, face, 0.0, 0.0, w_center))
    hw, hh = width / 2.0, height / 2.0
    if arch > 0.0:
        profile = [(-hw, -hh), (hw, -hh), (hw, hh - arch), (0.0, hh), (-hw, hh - arch)]
        cutter = make_prism("_Cut", profile, total, loc, _faxis(face))
    else:
        cutter = make_box("_Cut", _fsize(face, width, total, height), loc)
    boolean_diff(wall, cutter)


def add_window_3d(prefix: str, wall, center: tuple, width: float, height: float,
                   face: str = '+Z', depth: float = 0.16, arch: float = 0.0,
                   frame_color: tuple = WOOD_DARK, glass_color: tuple = GLASS_WARM,
                   lit: bool = True, mullions: bool = True, sill: bool = True,
                   shutters: bool = False, frame_t: float = 0.075,
                   frame_out: float = 0.055) -> list:
    """Janela de verdade: nicho escavado na parede, vidro recuado no fundo
    do nicho, moldura de 4 peças saindo pra fora, peitoril e (opcional)
    cruzeta e postigos. `center` é o centro da abertura NA SUPERFÍCIE
    externa da parede, em coordenadas Godot."""
    objs = []
    cut_niche(wall, center, face, width, height, depth, arch)

    glass_w = width - 0.02
    glass_h = height - 0.02 + (arch * 0.5)
    glass_v = arch * 0.25
    kw = {}
    if lit:
        kw = dict(emission=glass_color, emission_energy=1.35)
    objs.append(add_box(prefix + "_Glass", _fsize(face, glass_w, 0.05, glass_h),
                        to_bloc(*_fpos(center, face, 0.0, glass_v, -depth + 0.05)),
                        glass_color, pattern="glass", roughness=0.2, metallic=0.05,
                        bevel_width=0.0, tex_scale=max(glass_w, glass_h), **kw))

    # moldura: 2 montantes + verga + soleira, sobrando pra fora da parede
    stile_h = height + frame_t * 2.0 + arch
    objs.append(add_box(prefix + "_FrameL", _fsize(face, frame_t, frame_out + 0.06, stile_h),
                        to_bloc(*_fpos(center, face, -(width + frame_t) / 2.0, arch * 0.5,
                                       frame_out / 2.0 - 0.03)),
                        frame_color, pattern="wood", bevel_width=0.016, tex_scale=0.5))
    objs.append(add_box(prefix + "_FrameR", _fsize(face, frame_t, frame_out + 0.06, stile_h),
                        to_bloc(*_fpos(center, face, (width + frame_t) / 2.0, arch * 0.5,
                                       frame_out / 2.0 - 0.03)),
                        frame_color, pattern="wood", bevel_width=0.016, tex_scale=0.5))
    top_w = width + frame_t * 2.0
    if arch > 0.0:
        # verga em duas peças inclinadas formando o bico da ogiva
        span = (width + frame_t) / 2.0
        ang = math.atan2(arch, span)
        seg = math.sqrt(span * span + arch * arch)
        for sgn, tag in ((-1.0, "L"), (1.0, "R")):
            flip = _ARCH_FLIP[face]
            rot_y = -sgn * ang * flip if face in ('+Z', '-Z') else 0.0
            rot_x = -sgn * ang * flip if face in ('+X', '-X') else 0.0
            objs.append(add_box(prefix + "_Arch" + tag,
                                _fsize(face, seg, frame_out + 0.06, frame_t),
                                to_bloc(*_fpos(center, face, sgn * span / 2.0,
                                               height / 2.0 + arch / 2.0,
                                               frame_out / 2.0 - 0.03)),
                                frame_color, pattern="wood", rot=(rot_x, rot_y, 0.0),
                                bevel_width=0.016, tex_scale=0.5))
    else:
        objs.append(add_box(prefix + "_Lintel", _fsize(face, top_w, frame_out + 0.06, frame_t),
                            to_bloc(*_fpos(center, face, 0.0, (height + frame_t) / 2.0,
                                           frame_out / 2.0 - 0.03)),
                            frame_color, pattern="wood", bevel_width=0.016, tex_scale=0.5))
    if sill:
        objs.append(add_box(prefix + "_Sill", _fsize(face, top_w + 0.10, frame_out + 0.10, 0.065),
                            to_bloc(*_fpos(center, face, 0.0, -(height + frame_t) / 2.0,
                                           frame_out / 2.0 + 0.02)),
                            frame_color, pattern="wood", bevel_width=0.02, tex_scale=0.5))
    else:
        objs.append(add_box(prefix + "_Base", _fsize(face, top_w, frame_out + 0.06, frame_t),
                            to_bloc(*_fpos(center, face, 0.0, -(height + frame_t) / 2.0,
                                           frame_out / 2.0 - 0.03)),
                            frame_color, pattern="wood", bevel_width=0.016, tex_scale=0.5))

    if mullions:
        objs.append(add_box(prefix + "_MullV", _fsize(face, 0.05, 0.06, height - 0.02 + arch * 0.5),
                            to_bloc(*_fpos(center, face, 0.0, arch * 0.25, -depth + 0.10)),
                            frame_color, pattern="wood", bevel_width=0.012, tex_scale=0.4))
        objs.append(add_box(prefix + "_MullH", _fsize(face, width - 0.02, 0.06, 0.05),
                            to_bloc(*_fpos(center, face, 0.0, 0.0, -depth + 0.10)),
                            frame_color, pattern="wood", bevel_width=0.012, tex_scale=0.4))

    if shutters:
        # dobradiça VERTICAL: o postigo gira em torno do eixo de altura
        # (Blender Z) em qualquer fachada — girar em torno da normal da
        # parede deixava o postigo deitado, tipo prateleira.
        for sgn, tag in ((-1.0, "L"), (1.0, "R")):
            u = sgn * (width / 2.0 + frame_t + width * 0.25)
            objs.append(add_box(prefix + "_Shutter" + tag,
                                _fsize(face, width * 0.52, 0.055, height * 0.96),
                                to_bloc(*_fpos(center, face, u, 0.0, frame_out + 0.02)),
                                (0.36, 0.26, 0.20), pattern="planks",
                                rot=(0.0, 0.0, sgn * 0.36),
                                bevel_width=0.012, tex_scale=0.55))
    return objs


def add_door_3d(prefix: str, wall, center_bottom: tuple, width: float, height: float,
                 face: str = '+Z', depth: float = 0.22, arch: float = 0.0,
                 door_color: tuple = (0.34, 0.22, 0.13), frame_color: tuple = WOOD_DARK,
                 straps: bool = True, step: bool = True, frame_t: float = 0.10,
                 frame_out: float = 0.07) -> list:
    """Porta de verdade: vão escavado na parede, folha recuada no fundo do
    vão, batentes + verga saindo pra fora, ferragens e degrau de pedra.
    `center_bottom` é o ponto no CHÃO, no meio do vão, na superfície da
    parede (coordenadas Godot)."""
    objs = []
    center = (center_bottom[0], center_bottom[1] + height / 2.0, center_bottom[2])
    cut_niche(wall, center, face, width, height, depth, arch)

    leaf_h = height - 0.02 + arch * 0.55
    objs.append(add_box(prefix + "_Leaf", _fsize(face, width - 0.03, 0.09, leaf_h),
                        to_bloc(*_fpos(center, face, 0.0, arch * 0.27, -depth + 0.09)),
                        door_color, pattern="planks", bevel_width=0.014,
                        tex_scale=max(width, 0.7)))
    if straps:
        for vy in (height * 0.26, -height * 0.26):
            objs.append(add_box(prefix + "_Strap%d" % int(vy * 100),
                                _fsize(face, width - 0.10, 0.05, 0.075),
                                to_bloc(*_fpos(center, face, 0.0, vy, -depth + 0.15)),
                                IRON, pattern="metal", metallic=0.6, roughness=0.45,
                                bevel_width=0.01, tex_scale=0.6))
        objs.append(add_sphere(prefix + "_Knob", 0.05,
                               to_bloc(*_fpos(center, face, width * 0.32, -0.04, -depth + 0.17)),
                               (0.72, 0.58, 0.24), pattern="metal", metallic=0.7, roughness=0.35))

    stile_h = height + frame_t + arch
    for sgn, tag in ((-1.0, "L"), (1.0, "R")):
        objs.append(add_box(prefix + "_Jamb" + tag,
                            _fsize(face, frame_t, frame_out + 0.08, stile_h),
                            to_bloc(*_fpos(center, face, sgn * (width + frame_t) / 2.0,
                                           (arch - frame_t) * 0.5 + frame_t * 0.5,
                                           frame_out / 2.0 - 0.04)),
                            frame_color, pattern="wood", bevel_width=0.018, tex_scale=0.6))
    if arch > 0.0:
        span = (width + frame_t) / 2.0
        ang = math.atan2(arch, span)
        seg = math.sqrt(span * span + arch * arch)
        for sgn, tag in ((-1.0, "L"), (1.0, "R")):
            flip = _ARCH_FLIP[face]
            rot_y = -sgn * ang * flip if face in ('+Z', '-Z') else 0.0
            rot_x = -sgn * ang * flip if face in ('+X', '-X') else 0.0
            objs.append(add_box(prefix + "_Arch" + tag,
                                _fsize(face, seg, frame_out + 0.08, frame_t),
                                to_bloc(*_fpos(center, face, sgn * span / 2.0,
                                               height / 2.0 + arch / 2.0,
                                               frame_out / 2.0 - 0.04)),
                                frame_color, pattern="wood", rot=(rot_x, rot_y, 0.0),
                                bevel_width=0.018, tex_scale=0.6))
    else:
        objs.append(add_box(prefix + "_Lintel",
                            _fsize(face, width + frame_t * 2.0, frame_out + 0.08, frame_t),
                            to_bloc(*_fpos(center, face, 0.0, (height + frame_t) / 2.0,
                                           frame_out / 2.0 - 0.04)),
                            frame_color, pattern="wood", bevel_width=0.018, tex_scale=0.6))
    if step:
        objs.append(add_box(prefix + "_Step", _fsize(face, width + 0.30, 0.34, 0.10),
                            to_bloc(*_fpos(center, face, 0.0, -height / 2.0 + 0.05, 0.10)),
                            (0.55, 0.53, 0.50), pattern="stone", bevel_width=0.022,
                            tex_scale=0.8))
    return objs


def add_arrow_slit(prefix: str, wall, center: tuple, face: str, height: float = 0.75,
                    width: float = 0.14, depth: float = 0.22,
                    cross: bool = True, stone_color: tuple = (0.06, 0.06, 0.07)) -> list:
    """Fresta de flecha: recorte fino e alto (com travessa em cruz) escavado
    de verdade na torre, com escuro no fundo em vez de caixa colada."""
    objs = []
    cut_niche(wall, center, face, width, height, depth)
    if cross:
        cut_niche(wall, center, face, width * 3.0, width, depth * 0.8)
    objs.append(add_box(prefix + "_Dark", _fsize(face, width + 0.02, 0.04, height + 0.02),
                        to_bloc(*_fpos(center, face, 0.0, 0.0, -depth + 0.03)),
                        stone_color, pattern="soft", bevel_width=0.0, tex_scale=0.5,
                        roughness=1.0))
    return objs


# ------------------------------------------------------------------ telhado

def add_gable_roof(name: str, size: tuple, loc: tuple, color: tuple, pattern: str = "roof_tile",
                    **mat_kwargs):
    """Compatibilidade: cunha sólida simples (usada como empena/sótão).
    size = (largura_x, altura, profundidade_y) em eixos Blender."""
    sx, sy, sz = size
    hx, hz = sx / 2.0, sz / 2.0
    obj = make_prism(name, [(-hx, 0.0), (hx, 0.0), (0.0, sy)], sz, loc, 'Y')
    return finish(obj, color, pattern, 0.0, 0.02, 1.0, **mat_kwargs)


def add_roof(prefix: str, center: tuple, width: float, depth: float, rise: float,
              color: tuple = (0.42, 0.17, 0.14), gable_color: tuple = None,
              thickness: float = 0.13, overhang: float = 0.20,
              pattern: str = "roof_tile", ridge: bool = True,
              rafters: bool = True, gable_pattern: str = "wood",
              gable_tex_scale: float = 1.0) -> list:
    """Telhado de duas águas de verdade: duas lâminas inclinadas com
    espessura e beiral saliente + empena triangular fechando as pontas +
    cumeeira + pontas de caibro aparecendo sob o beiral. `center` é o ponto
    (Godot) no meio da base do telhado (topo da parede).

    O cume corre ao longo de Z (Godot) — a fachada frontal é +Z."""
    objs = []
    cx, cy, cz = center
    half_w = width / 2.0 + overhang
    slope = math.sqrt(half_w * half_w + rise * rise) + thickness * 0.6
    ang = math.atan2(rise, half_w)
    gc = gable_color if gable_color is not None else color

    # empena/sótão triangular sólido (fecha o vão sob as águas)
    objs.append(add_prism(prefix + "_Gable",
                          [(-width / 2.0, 0.0), (width / 2.0, 0.0), (0.0, rise)],
                          depth, to_bloc(cx, cy, cz), gc, axis='Y', pattern=gable_pattern,
                          bevel_width=0.02, tex_scale=gable_tex_scale))

    for sgn, tag in ((1.0, "R"), (-1.0, "L")):
        mx = sgn * half_w / 2.0 + sgn * math.sin(ang) * thickness * 0.5
        mz = rise / 2.0 + math.cos(ang) * thickness * 0.5
        objs.append(add_box(prefix + "_Slope" + tag,
                            (slope, depth + overhang * 2.0, thickness),
                            to_bloc(cx + mx, cy + mz, cz),
                            color, rot=(0.0, sgn * ang, 0.0), pattern=pattern,
                            bevel_width=0.018, tex_scale=0.8))
    if ridge:
        objs.append(add_box(prefix + "_Ridge", (0.20, depth + overhang * 2.0 + 0.05, 0.13),
                            to_bloc(cx, cy + rise + 0.03, cz), _shade(color, 0.82),
                            pattern=pattern, bevel_width=0.02, tex_scale=0.5))
    if rafters:
        n = max(2, int(depth / 0.62))
        for i in range(n + 1):
            t = -0.5 + i / float(n)
            zz = cz + t * depth
            for sgn in (1.0, -1.0):
                objs.append(add_box(prefix + "_Rafter%d%s" % (i, "R" if sgn > 0 else "L"),
                                    (overhang * 1.5, 0.09, 0.09),
                                    to_bloc(cx + sgn * (width / 2.0 + overhang * 0.35),
                                            cy + rise * (1.0 - (width / 2.0 + overhang * 0.35) / half_w) - 0.06,
                                            zz),
                                    WOOD_DARK, pattern="wood", bevel_width=0.01, tex_scale=0.4))
    return objs


def add_cone_roof(prefix: str, center: tuple, radius: float, height: float,
                   color: tuple = (0.42, 0.17, 0.14), sides: int = 8,
                   skirt: float = 0.16, finial: bool = True,
                   pattern: str = "roof_tile") -> list:
    """Telhado cônico de torre, com saia (beiral) na base e ponteira."""
    objs = []
    cx, cy, cz = center
    objs.append(add_cylinder(prefix + "_Skirt", radius + skirt * 0.75, radius + skirt, 0.14,
                             to_bloc(cx, cy + 0.07, cz), _shade(color, 0.85), vertices=sides,
                             pattern=pattern, bevel_width=0.02, tex_scale=0.7))
    objs.append(add_cylinder(prefix + "_Cone", 0.0, radius + skirt * 0.7, height,
                             to_bloc(cx, cy + 0.14 + height / 2.0, cz), color, vertices=sides,
                             pattern=pattern, bevel_width=0.02, tex_scale=0.7))
    if finial:
        objs.append(add_cylinder(prefix + "_Finial", 0.028, 0.028, 0.30,
                                 to_bloc(cx, cy + 0.14 + height + 0.12, cz), IRON,
                                 vertices=6, pattern="metal", metallic=0.7, roughness=0.4,
                                 bevel_width=0.0))
        objs.append(add_sphere(prefix + "_Ball", 0.075,
                               to_bloc(cx, cy + 0.14 + height + 0.30, cz), (0.72, 0.58, 0.24),
                               pattern="metal", metallic=0.75, roughness=0.3))
    return objs


# ------------------------------------------------------------- fortificação

def add_crenellation(prefix: str, center: tuple, half_x: float, half_z: float, y: float,
                      merlon_w: float = 0.30, merlon_h: float = 0.34, merlon_t: float = 0.18,
                      gap: float = 0.24, color: tuple = (0.56, 0.54, 0.50)) -> list:
    """Merlões (ameias) ao longo das 4 bordas de um topo retangular."""
    objs = []
    cx, cy, cz = center[0], y, center[2]
    step = merlon_w + gap
    nx = max(1, int((half_x * 2.0) / step))
    nz = max(1, int((half_z * 2.0) / step))
    i = 0
    for k in range(nx + 1):
        t = -half_x + (2.0 * half_x) * (k / float(nx))
        for sz in (1.0, -1.0):
            objs.append(add_box("%s_M%d" % (prefix, i), (merlon_w, merlon_t, merlon_h),
                                to_bloc(cx + t, cy + merlon_h / 2.0, cz + sz * half_z),
                                color, pattern="stone", bevel_width=0.02, tex_scale=0.55))
            i += 1
    for k in range(1, nz):
        t = -half_z + (2.0 * half_z) * (k / float(nz))
        for sx in (1.0, -1.0):
            objs.append(add_box("%s_M%d" % (prefix, i), (merlon_t, merlon_w, merlon_h),
                                to_bloc(cx + sx * half_x, cy + merlon_h / 2.0, cz + t),
                                color, pattern="stone", bevel_width=0.02, tex_scale=0.55))
            i += 1
    return objs


def add_crenellation_ring(prefix: str, center: tuple, radius: float, y: float, count: int = 8,
                           merlon_w: float = 0.30, merlon_h: float = 0.34, merlon_t: float = 0.20,
                           color: tuple = (0.56, 0.54, 0.50)) -> list:
    """Merlões distribuídos num anel — pra torres cilíndricas."""
    objs = []
    cx, cz = center[0], center[2]
    for i in range(count):
        ang = (i / float(count)) * math.tau
        px, pz = cx + math.sin(ang) * radius, cz + math.cos(ang) * radius
        objs.append(add_box("%s_M%d" % (prefix, i), (merlon_w, merlon_t, merlon_h),
                            to_bloc(px, y + merlon_h / 2.0, pz), color,
                            rot=(0.0, 0.0, ang), pattern="stone", bevel_width=0.02,
                            tex_scale=0.55))
    return objs


def add_buttress(name: str, base: tuple, width: float, depth: float, height: float,
                  face: str = '+Z', color: tuple = (0.5, 0.48, 0.45)) -> list:
    """Contraforte encostado numa parede, com talude inclinado no topo (dá
    peso e verticalidade à silhueta). `base` é o pé do contraforte na
    superfície da parede, em coordenadas Godot."""
    objs = []
    bx, by, bz = base
    body_h = height - 0.3
    objs.append(add_box(name, _fsize(face, width, depth, body_h),
                        to_bloc(*_fpos((bx, by + body_h / 2.0, bz), face, 0.0, 0.0, depth / 2.0)),
                        color, pattern="stone", bevel_width=0.03, tex_scale=0.8))
    # talude: prisma triangular que "encosta" de volta na parede
    out, right = _FACES[face]
    prof = [(0.0, 0.0), (depth, 0.0), (0.0, 0.34)]
    axis = 'X' if face in ('+Z', '-Z') else 'Y'
    sign = 1.0 if face in ('+Z', '+X') else -1.0
    prof = [(a * sign, b) for a, b in prof]
    objs.append(add_prism(name + "_Slope", prof, width,
                          to_bloc(bx, by + body_h, bz) if face in ('+Z', '-Z')
                          else to_bloc(bx, by + body_h, bz),
                          color, axis=axis, pattern="stone", bevel_width=0.02, tex_scale=0.8))
    return objs


# -------------------------------------------------------------- cenografia

def add_fence_ring(prefix: str, center: tuple, half_size: float, height: float = 0.5,
                    thickness: float = 0.08, gap_width: float = 0.5,
                    color: tuple = (0.42, 0.3, 0.18), post_step: float = 0.42) -> list:
    """Cerca de estacas de verdade (postes individuais + duas travessas),
    com vão na frente (+Z) alinhado com a porta. Muito mais legível que o
    painel liso com textura de ripa que existia antes."""
    cx, cz = center
    objs = []
    rail_y = (height * 0.35, height * 0.75)

    def run(tag, x0, z0, x1, z1):
        length = math.hypot(x1 - x0, z1 - z0)
        if length < 0.05:
            return
        n = max(1, int(round(length / post_step)))
        for i in range(n + 1):
            t = i / float(n)
            px, pz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
            h = height * (1.0 if i % 2 == 0 else 0.9)
            objs.append(add_box("%s_%s_P%d" % (prefix, tag, i), (thickness, thickness, h),
                                to_bloc(px, h / 2.0, pz), color, pattern="wood",
                                bevel_width=0.012, tex_scale=0.35))
        ang = math.atan2(x1 - x0, z1 - z0)
        for j, ry in enumerate(rail_y):
            objs.append(add_box("%s_%s_R%d" % (prefix, tag, j),
                                (length, thickness * 0.62, thickness * 0.72),
                                to_bloc((x0 + x1) / 2.0, ry, (z0 + z1) / 2.0), _shade(color, 0.88),
                                rot=(0.0, 0.0, ang - math.pi / 2.0), pattern="wood",
                                bevel_width=0.01, tex_scale=0.4))

    run("L", cx - half_size, cz - half_size, cx - half_size, cz + half_size)
    run("R", cx + half_size, cz - half_size, cx + half_size, cz + half_size)
    run("B", cx - half_size, cz - half_size, cx + half_size, cz - half_size)
    seg = half_size - gap_width / 2.0
    if seg > 0.08:
        run("F1", cx - half_size, cz + half_size, cx - gap_width / 2.0, cz + half_size)
        run("F2", cx + gap_width / 2.0, cz + half_size, cx + half_size, cz + half_size)
    return objs


def add_smoke_plume(prefix: str, base: tuple, count: int = 4, radius: float = 0.10,
                     rise: float = 0.15, drift: float = 0.09,
                     color: tuple = (0.74, 0.73, 0.71)) -> list:
    """Fumacinha: baforadas ACHATADAS que sobem crescendo e desviando pro lado.

    As baforadas ficam SEPARADAS (o passo vertical é maior que o raio) e
    pequenas em relação à chaminé de propósito: aglomeradas e grandes elas
    fundiam num bolo faceteado que, sob a luz de estúdio do render de ícone,
    lia como um cristal/jóia de metal em cima do telhado em vez de fumaça."""
    objs = []
    bx, by, bz = base
    for i in range(count):
        t = i / float(max(1, count - 1))
        r = radius * (0.62 + t * 0.78)
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=2, radius=r,
            location=to_bloc(bx + drift * t * t, by + rise * i * (1.0 + t * 0.5),
                             bz + drift * 0.35 * t))
        obj = bpy.context.active_object
        obj.name = "%s_Puff%d" % (prefix, i)
        obj.scale = (1.0, 0.9, 0.62)
        _activate(obj)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.select_set(False)
        jitter(obj, 0.012)
        flat_shade(obj)
        cube_unwrap(obj, 0.5)
        add_material(obj, color, "soft", roughness=1.0)
        objs.append(obj)
    return objs


def add_chimney_with_smoke(prefix: str, base_loc: tuple, height: float = 0.7,
                            color: tuple = (0.50, 0.47, 0.43)) -> list:
    """Chaminé de alvenaria com capa saliente e fumaça em baforadas.
    `base_loc` é o CENTRO da chaminé em coordenadas Godot."""
    objs = []
    bx, by, bz = base_loc
    objs.append(add_box(prefix, (0.26, 0.26, height), to_bloc(bx, by, bz), color,
                        pattern="stone", bevel_width=0.022, tex_scale=0.55))
    objs.append(add_box(prefix + "_Cap", (0.36, 0.36, 0.09),
                        to_bloc(bx, by + height / 2.0 + 0.03, bz), _shade(color, 0.8),
                        pattern="stone", bevel_width=0.02, tex_scale=0.5))
    objs.append(add_box(prefix + "_Flue", (0.13, 0.13, 0.07),
                        to_bloc(bx, by + height / 2.0 + 0.10, bz), (0.09, 0.08, 0.08),
                        pattern="soft", bevel_width=0.0, roughness=1.0))
    objs += add_smoke_plume(prefix + "_Smoke", (bx, by + height / 2.0 + 0.13, bz),
                            count=4, radius=0.078, rise=0.115, drift=0.085)
    return objs


def add_barrel(name: str, center: tuple, radius: float = 0.20, height: float = 0.52,
                color: tuple = (0.40, 0.28, 0.17), rot: tuple = (0, 0, 0)) -> list:
    objs = []
    cx, cy, cz = center
    objs.append(add_cylinder(name, radius * 0.88, radius * 0.88, height,
                             to_bloc(cx, cy, cz), color, vertices=8, rot=rot,
                             pattern="wood", bevel_width=0.016, tex_scale=0.35))
    for sgn in (1.0, -1.0):
        objs.append(add_cylinder(name + ("_HoopT" if sgn > 0 else "_HoopB"),
                                 radius * 0.95, radius * 0.95, 0.055,
                                 to_bloc(cx, cy + sgn * height * 0.30, cz), IRON, vertices=8,
                                 rot=rot, pattern="metal", metallic=0.6, roughness=0.5,
                                 bevel_width=0.0))
    return objs


def add_crate(name: str, center: tuple, size: float = 0.34,
               color: tuple = (0.48, 0.35, 0.21), rot_y: float = 0.0) -> list:
    objs = []
    cx, cy, cz = center
    objs.append(add_box(name, (size, size, size), to_bloc(cx, cy, cz), color,
                        rot=(0.0, 0.0, rot_y), pattern="planks", bevel_width=0.02,
                        tex_scale=size))
    for sgn in (1.0, -1.0):
        objs.append(add_box(name + ("_BandT" if sgn > 0 else "_BandB"),
                            (size * 1.04, size * 1.04, 0.045),
                            to_bloc(cx, cy + sgn * size * 0.3, cz), _shade(color, 0.7),
                            rot=(0.0, 0.0, rot_y), pattern="wood", bevel_width=0.0,
                            tex_scale=0.4))
    return objs


def add_log_pile(prefix: str, center: tuple, length: float = 1.25, radius: float = 0.16,
                  rows: int = 2, along: str = 'X', color: tuple = (0.47, 0.34, 0.21),
                  bark: tuple = (0.33, 0.23, 0.14)) -> list:
    """Pilha de toras empilhada em pirâmide, com topo mais claro (madeira
    cortada) e casca escura na lateral."""
    objs = []
    cx, cy, cz = center
    rot = (0.0, math.pi / 2.0, 0.0) if along == 'X' else (math.pi / 2.0, 0.0, 0.0)
    i = 0
    for r in range(rows):
        n = rows - r
        for c in range(n):
            off = (c - (n - 1) / 2.0) * radius * 2.05
            px = cx + (0.0 if along == 'X' else off)
            pz = cz + (off if along == 'X' else 0.0)
            py = cy + radius + r * radius * 1.78
            objs.append(add_cylinder("%s_%d" % (prefix, i), radius, radius, length,
                                     to_bloc(px, py, pz), bark, vertices=8, rot=rot,
                                     pattern="wood", bevel_width=0.014, tex_scale=0.4))
            for sgn in (1.0, -1.0):
                ex = px + (sgn * length / 2.0 if along == 'X' else 0.0)
                ez = pz + (0.0 if along == 'X' else sgn * length / 2.0)
                objs.append(add_cylinder("%s_%d_End%d" % (prefix, i, int(sgn)),
                                         radius * 0.93, radius * 0.93, 0.03,
                                         to_bloc(ex, py, ez), color, vertices=8, rot=rot,
                                         pattern="wood", bevel_width=0.0, tex_scale=0.25))
            i += 1
    return objs


def add_pine(prefix: str, base: tuple, scale: float = 1.0,
              leaf: tuple = (0.17, 0.40, 0.20), trunk: tuple = (0.32, 0.22, 0.14)) -> list:
    """Pinheiro low-poly em 3 saias de folhagem — muito mais legível como
    árvore que o cone único de antes."""
    objs = []
    bx, by, bz = base
    objs.append(add_cylinder(prefix + "_Trunk", 0.06 * scale, 0.09 * scale, 0.42 * scale,
                             to_bloc(bx, by + 0.21 * scale, bz), trunk, vertices=6,
                             pattern="wood", bevel_width=0.0, tex_scale=0.3))
    tiers = [(0.36 * scale, 0.52 * scale, 0.55 * scale, 1.0),
             (0.44 * scale, 0.40 * scale, 0.95 * scale, 0.9),
             (0.52 * scale, 0.30 * scale, 1.30 * scale, 0.8)]
    for i, (r, h, y, sh) in enumerate(tiers):
        objs.append(add_cylinder("%s_Tier%d" % (prefix, i), r * 0.18, r, h,
                                 to_bloc(bx, by + y, bz), _shade(leaf, sh + i * 0.12),
                                 vertices=7, pattern="leaf", bevel_width=0.0, tex_scale=0.5,
                                 jitter_amount=0.03))
    return objs


def add_banner(prefix: str, top: tuple, width: float = 0.42, height: float = 0.95,
                color: tuple = (0.62, 0.16, 0.14), pole_h: float = 0.0,
                face: str = '+Z') -> list:
    """Estandarte pendurado (com ponta em V embaixo) e, opcional, mastro."""
    objs = []
    tx, ty, tz = top
    if pole_h > 0.0:
        objs.append(add_cylinder(prefix + "_Pole", 0.035, 0.035, pole_h,
                                 to_bloc(tx, ty - pole_h / 2.0 + 0.02, tz), WOOD_DARK,
                                 vertices=6, pattern="wood", bevel_width=0.0, tex_scale=0.3))
    body_h = height * 0.78
    tail = height - body_h
    objs.append(add_box(prefix + "_Cloth", _fsize(face, width, 0.045, body_h),
                        to_bloc(*_fpos((tx, ty - body_h / 2.0, tz), face, 0.0, 0.0, 0.0)),
                        color, pattern="cloth", bevel_width=0.008, tex_scale=0.45))
    prof = [(-width / 2.0, 0.0), (width / 2.0, 0.0), (0.0, -tail)]
    objs.append(add_prism(prefix + "_Tail", prof, 0.045,
                          to_bloc(tx, ty - body_h, tz), color,
                          axis=_faxis(face), pattern="cloth", bevel_width=0.0, tex_scale=0.45))
    objs.append(add_box(prefix + "_Rod", _fsize(face, width + 0.10, 0.05, 0.05),
                        to_bloc(tx, ty + 0.03, tz), WOOD_DARK, pattern="wood",
                        bevel_width=0.0, tex_scale=0.3))
    return objs


def add_pennant(prefix: str, base: tuple, pole_h: float, length: float = 0.72,
                 height: float = 0.34, color: tuple = (0.72, 0.18, 0.15),
                 pole_color: tuple = WOOD_DARK, tip: bool = True) -> list:
    """Mastro com flâmula triangular tremulando pro lado (+X) — lê como
    bandeira mesmo de longe, ao contrário de um paninho retangular colado
    no topo, que vira 'chaminé' na silhueta."""
    objs = []
    bx, by, bz = base
    objs.append(add_cylinder(prefix + "_Pole", 0.035, 0.045, pole_h,
                             to_bloc(bx, by + pole_h / 2.0, bz), pole_color, vertices=6,
                             pattern="wood", bevel_width=0.0, tex_scale=0.3))
    top = by + pole_h
    prof = [(0.0, 0.0), (0.0, -height), (length, -height * 0.30),
            (length * 0.62, -height * 0.52), (length * 0.86, -height * 0.72)]
    objs.append(add_prism(prefix + "_Cloth", prof, 0.04, to_bloc(bx + 0.03, top - 0.06, bz),
                          color, axis='Y', pattern="cloth", bevel_width=0.0, tex_scale=0.4))
    if tip:
        objs.append(add_sphere(prefix + "_Tip", 0.055, to_bloc(bx, top + 0.05, bz),
                               (0.78, 0.62, 0.24), pattern="metal", metallic=0.7,
                               roughness=0.3))
    return objs


def add_ladder(prefix: str, base: tuple, height: float, width: float = 0.36,
                face: str = '+Z', color: tuple = WOOD_MID, lean: float = 0.0) -> list:
    objs = []
    bx, by, bz = base
    for sgn, tag in ((-1.0, "L"), (1.0, "R")):
        objs.append(add_box("%s_Rail%s" % (prefix, tag), _fsize(face, 0.055, 0.055, height),
                            to_bloc(*_fpos((bx, by + height / 2.0, bz), face,
                                           sgn * width / 2.0, 0.0, 0.0)),
                            color, rot=(0.0, 0.0, 0.0), pattern="wood", bevel_width=0.0,
                            tex_scale=0.3))
    n = max(2, int(height / 0.3))
    for i in range(n):
        y = by + 0.16 + i * (height - 0.3) / float(max(1, n - 1))
        objs.append(add_box("%s_Rung%d" % (prefix, i), _fsize(face, width, 0.045, 0.045),
                            to_bloc(bx, y, bz), _shade(color, 0.9), pattern="wood",
                            bevel_width=0.0, tex_scale=0.3))
    return objs


def add_torch(prefix: str, base: tuple, height: float = 0.55,
               flame: tuple = (1.0, 0.62, 0.18)) -> list:
    objs = []
    bx, by, bz = base
    objs.append(add_cylinder(prefix + "_Stick", 0.035, 0.045, height,
                             to_bloc(bx, by + height / 2.0, bz), WOOD_DARK, vertices=6,
                             pattern="wood", bevel_width=0.0, tex_scale=0.3))
    objs.append(add_cylinder(prefix + "_Cup", 0.085, 0.055, 0.10,
                             to_bloc(bx, by + height + 0.03, bz), IRON, vertices=6,
                             pattern="metal", metallic=0.6, roughness=0.5, bevel_width=0.0))
    # chama em duas bolinhas (base larga + ponta) — uma esfera só vira
    # "pedra preciosa amarela espetada num pau"
    objs.append(add_sphere(prefix + "_Flame", 0.075, to_bloc(bx, by + height + 0.11, bz),
                           flame, subdivisions=2, jitter_amount=0.02, pattern="crystal",
                           roughness=0.3, emission=flame, emission_energy=3.2))
    objs.append(add_sphere(prefix + "_FlameTip", 0.045,
                           to_bloc(bx, by + height + 0.19, bz),
                           (1.0, 0.85, 0.45), subdivisions=2, jitter_amount=0.015,
                           pattern="crystal", roughness=0.3, emission=(1.0, 0.8, 0.4),
                           emission_energy=3.6))
    return objs


def add_rails(prefix: str, start: tuple, end: tuple, gauge: float = 0.52,
               rail_h: float = 0.085, sleeper_step: float = 0.40,
               rail_color: tuple = (0.55, 0.52, 0.50),
               sleeper_color: tuple = (0.33, 0.24, 0.15)) -> list:
    """Trilho de mina: dois trilhos de metal sobre dormentes de madeira,
    de `start` a `end` (coordenadas Godot no chão, y = altura da base)."""
    objs = []
    x0, y0, z0 = start
    x1, _y1, z1 = end
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    ang = math.atan2(dx, dz)
    mx, mz = (x0 + x1) / 2.0, (z0 + z1) / 2.0
    perp = (math.cos(ang), -math.sin(ang))

    n = max(2, int(length / sleeper_step))
    for i in range(n + 1):
        t = i / float(n)
        px, pz = x0 + dx * t, z0 + dz * t
        objs.append(add_box("%s_Sleeper%d" % (prefix, i), (gauge + 0.26, 0.15, 0.075),
                            to_bloc(px, y0 + 0.038, pz), sleeper_color,
                            rot=(0.0, 0.0, ang), pattern="wood", bevel_width=0.01,
                            tex_scale=0.3))
    for sgn, tag in ((-1.0, "L"), (1.0, "R")):
        ox, oz = perp[0] * sgn * gauge / 2.0, perp[1] * sgn * gauge / 2.0
        objs.append(add_box("%s_Rail%s" % (prefix, tag), (0.075, length, rail_h),
                            to_bloc(mx + ox, y0 + 0.075 + rail_h / 2.0, mz + oz),
                            rail_color, rot=(0.0, 0.0, ang), pattern="metal",
                            metallic=0.55, roughness=0.45, bevel_width=0.008,
                            tex_scale=0.35))
    return objs


def add_mine_cart(name: str, center: tuple, rot_y: float = 0.0, scale: float = 1.0,
                   body_color: tuple = (0.36, 0.26, 0.16),
                   ore_color: tuple = (0.42, 0.36, 0.34)) -> list:
    """Carrinho de minério: caixa aberta com bordas, 4 rodas e minério
    transbordando. TODAS as peças ficam sob um único objeto pai chamado
    `name` (via parent) — mas como o exportador glTF preserva hierarquia,
    o gerador junta tudo num só mesh pra o Godot achar 1 nó só."""
    objs = []
    cx, cy, cz = center
    w, d, h = 0.60 * scale, 0.70 * scale, 0.38 * scale
    body_y = cy + 0.20 * scale
    objs.append(add_box(name + "_Floor", (w, d, 0.06 * scale),
                        to_bloc(cx, body_y - h / 2.0, cz), body_color, rot=(0.0, 0.0, rot_y),
                        pattern="planks", bevel_width=0.012, tex_scale=0.4))
    for sgn in (1.0, -1.0):
        objs.append(add_box(name + ("_SideR" if sgn > 0 else "_SideL"),
                            (0.055 * scale, d, h),
                            to_bloc(cx + math.cos(rot_y) * sgn * w / 2.0, body_y,
                                    cz - math.sin(rot_y) * sgn * w / 2.0),
                            body_color, rot=(0.0, 0.0, rot_y), pattern="planks",
                            bevel_width=0.012, tex_scale=0.4))
        objs.append(add_box(name + ("_EndF" if sgn > 0 else "_EndB"),
                            (w, 0.055 * scale, h),
                            to_bloc(cx + math.sin(rot_y) * sgn * d / 2.0, body_y,
                                    cz + math.cos(rot_y) * sgn * d / 2.0),
                            body_color, rot=(0.0, 0.0, rot_y), pattern="planks",
                            bevel_width=0.012, tex_scale=0.4))
    for i, (ox, oz, r) in enumerate([(-0.26, -0.20, 0.115), (0.26, -0.20, 0.115),
                                      (-0.26, 0.20, 0.115), (0.26, 0.20, 0.115)]):
        wx = cx + (math.cos(rot_y) * ox + math.sin(rot_y) * oz) * scale
        wz = cz + (-math.sin(rot_y) * ox + math.cos(rot_y) * oz) * scale
        objs.append(add_cylinder(name + "_Wheel%d" % i, r * scale, r * scale, 0.055 * scale,
                                 to_bloc(wx, cy + r * scale * 0.55, wz), IRON, vertices=8,
                                 rot=(0.0, math.pi / 2.0, rot_y), pattern="metal",
                                 metallic=0.55, roughness=0.5, bevel_width=0.0))
    for i, (ox, oy, oz, r) in enumerate([(-0.10, 0.16, -0.12, 0.115), (0.09, 0.18, 0.10, 0.13),
                                          (0.0, 0.20, 0.0, 0.14), (-0.05, 0.15, 0.16, 0.10)]):
        wx = cx + (math.cos(rot_y) * ox + math.sin(rot_y) * oz) * scale
        wz = cz + (-math.sin(rot_y) * ox + math.cos(rot_y) * oz) * scale
        objs.append(add_sphere(name + "_Ore%d" % i, r * scale,
                               to_bloc(wx, body_y + oy * scale, wz), ore_color,
                               jitter_amount=0.04, pattern="ore", roughness=0.75))
    return objs


## Nomes ESTÁVEIS dos membros que `add_humanoid(separate_limbs=True)` deixa
## FORA da fusão final. Servem de contrato entre três lugares:
##   1. este kit, que nomeia os objetos assim no Blender;
##   2. o builder, que repassa a tupla em `finalize(..., keep=HUMANOID_LIMBS)`;
##   3. `scripts/units/limb_animator.gd`, que procura estes nomes dentro do
##      nó `Model` da cena pra girar cada membro em runtime.
## Mudar um nome aqui quebra silenciosamente a animação de todo mundo — o
## `LimbAnimator` só emite um aviso e desliga. Não renomeie: acrescente.
HUMANOID_LIMBS = ("LegL", "LegR", "ArmL", "ArmR")


def attach_to_limb(limb_name: str, objs: list):
    """Solda peças (arma, escudo, adereço) DENTRO de um membro separado, pra
    elas acompanharem o balanço do braço/perna em vez de ficarem flutuando no
    ar enquanto o membro se mexe.

    Tem que ser chamada DEPOIS de `add_humanoid(separate_limbs=True)` e ANTES
    de `finalize()`. A origem do membro é preservada (o `join` do Blender
    mantém a do objeto ativo, e o membro entra como ativo), então o pivô
    continua no ombro/quadril — que é o ponto todo.

    Ex.: a lança do Lanceiro nasce como dois cilindros soltos; sem isto, o
    braço direito balança e a lança fica parada no ar.

    Cada item de `objs` pode ser o objeto do Blender ou o NOME dele — vários
    helpers do gerador (`_shield`, por exemplo) não devolvem o que criaram."""
    limb = bpy.data.objects.get(limb_name)
    if limb is None:
        print("attach_to_limb: membro '%s' não existe (faltou separate_limbs=True?)" % limb_name)
        return None
    parts = []
    for o in objs:
        if o is None:
            continue
        resolved = bpy.data.objects.get(o) if isinstance(o, str) else o
        if resolved is None:
            print("attach_to_limb: peça '%s' não existe" % o)
            continue
        parts.append(resolved)
    return join_objects([limb] + parts, limb_name)


def _limb_segment(name: str, a: tuple, b: tuple, r_top: float, r_bottom: float,
                   color: tuple, vertices: int = 6, pattern: str = "soft",
                   bevel_width: float = 0.005, tex_scale: float = 0.3,
                   **mat_kwargs):
    """Segmento de membro (braço/antebraço, coxa/canela) ligando dois pontos
    GODOT `a` → `b` de verdade — orientado por QUATERNION, não por um Euler
    chutado. Existe porque cotovelo/joelho dobra num plano que não é só X
    nem só Y: um `rot=(ang, 0, 0)` funciona pra uma dobra reta pra frente,
    mas quebra assim que o osso também abre pro lado (braço afastando do
    tronco). Girar o eixo Z do cone até apontar pra `b-a` resolve os dois
    eixos de uma vez, sem álgebra de Euler composta."""
    pa = Vector(to_bloc(*a))
    pb = Vector(to_bloc(*b))
    d = pb - pa
    length = d.length
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r_bottom, radius2=r_top,
                                     depth=length, location=(pa + pb) / 2.0)
    obj = bpy.context.active_object
    obj.name = name
    if length > 1e-6:
        obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
        obj.rotation_mode = 'QUATERNION'
    _activate(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.select_set(False)
    return finish(obj, color, pattern, 0.0, bevel_width, tex_scale, **mat_kwargs)


def _sculpted_body(prefix: str, base: tuple, h: float, leg_h: float, torso_h: float,
                    torso_y: float, lean: float, cloth: tuple, skin: tuple,
                    leather: tuple, boots: tuple, helmet_color: tuple, shoulders: bool,
                    cloth_pattern: str, skin_pattern: str,
                    objs: list, leg_parts: dict, arm_parts: dict) -> None:
    """Corpo do `add_humanoid(sculpt=True)`. Ver o docstring de lá pro porquê.

    Regra que não pode ser quebrada aqui: as ALTURAS e os PONTOS DE PIVÔ são
    os mesmos do corpo em caixas (quadril em `leg_h`, ombro em
    `torso_y + 0.16h`). É isso que deixa o mesmo `separate_limbs`, o mesmo
    `attach_to_limb` e as mesmas posições de arma dos builders continuarem
    valendo — o corpo mudou de forma, não de esqueleto."""
    bx, by, bz = base
    # --- quadril: a peça que mais mata o "caixote" ------------------------
    objs.append(add_cylinder(prefix + "_Hip", 0.158 * h, 0.126 * h, 0.11 * h,
                             to_bloc(bx, by + leg_h + 0.015 * h, bz + lean * 0.4),
                             leather, vertices=8, pattern="soft", bevel_width=0.006 * h,
                             tex_scale=0.3, squash=(1.0, 0.66, 1.0)))
    for sgn in (-1.0, 1.0):
        lx = bx + sgn * 0.095 * h
        # Coxa → tornozelo afilando: um tronco de cone de 6 lados custa 24
        # triângulos e resolve sozinho metade da leitura "perna de LEGO".
        leg = add_cylinder("%s_Leg%d" % (prefix, int(sgn)), 0.050 * h, 0.078 * h,
                           leg_h * 0.96, to_bloc(lx, by + leg_h * 0.52, bz),
                           leather, vertices=6, pattern="soft", bevel_width=0.005 * h,
                           tex_scale=0.3)
        # Bota: elipsoide (não caixa) — o pé é a peça que mais aparece de cima
        # na câmera de RTS, e caixa de pé lê como tijolo.
        boot = add_sphere("%s_Boot%d" % (prefix, int(sgn)), 0.076 * h,
                          to_bloc(lx, by + 0.048 * h, bz + 0.022 * h), boots,
                          subdivisions=1, pattern="soft", tex_scale=0.25,
                          squash=(1.0, 1.38, 0.62))
        objs.append(leg)
        objs.append(boot)
        leg_parts[sgn] = [leg, boot]

    # --- tronco em duas frustas achatadas ---------------------------------
    objs.append(add_cylinder(prefix + "_Abdomen", 0.170 * h, 0.140 * h, 0.16 * h,
                             to_bloc(bx, by + leg_h + 0.078 * h, bz + lean * 0.6),
                             cloth, vertices=8, pattern=cloth_pattern,
                             bevel_width=0.006 * h, tex_scale=0.35, squash=(1.0, 0.62, 1.0)))
    objs.append(add_cylinder(prefix + "_Chest", 0.186 * h, 0.168 * h, 0.19 * h,
                             to_bloc(bx, by + leg_h + 0.245 * h, bz + lean),
                             cloth, vertices=8, pattern=cloth_pattern,
                             bevel_width=0.006 * h, tex_scale=0.35, squash=(1.0, 0.62, 1.0)))
    objs.append(add_cylinder(prefix + "_Belt", 0.166 * h, 0.160 * h, 0.05 * h,
                             to_bloc(bx, by + leg_h + 0.022 * h, bz + lean * 0.4),
                             (0.24, 0.17, 0.11), vertices=8, pattern="soft",
                             bevel_width=0.004 * h, tex_scale=0.25, squash=(1.0, 0.68, 1.0)))
    objs.append(add_cylinder(prefix + "_Neck", 0.048 * h, 0.062 * h, 0.06 * h,
                             to_bloc(bx, by + leg_h + torso_h + 0.01 * h, bz + lean * 1.2),
                             skin, vertices=6, pattern=skin_pattern, bevel_width=0.0,
                             tex_scale=0.2, roughness=0.85))

    for sgn in (-1.0, 1.0):
        ax = bx + sgn * 0.225 * h
        # Cotovelo articulado: braço reto único era metade do que lia como
        # "boneco de Lego" (a outra metade era a cabeça sem rosto, ver os
        # olhos em `add_humanoid`). Dois segmentos (braço + antebraço)
        # dobrando num cotovelo de verdade — mas o PUNHO continua EXATAMENTE
        # no mesmo ponto do braço reto de antes (`hand_pt`, idêntica à
        # fórmula velha): é ali que cada um dos ~53 builders solda arma ou
        # escudo com coordenada própria (`attach_to_limb`), e mover esse
        # ponto desalinharia toda arma já ajustada. O cotovelo fica no meio
        # do caminho ombro→punho (o mesmo pivô de ombro usado por
        # `set_origin` em `add_humanoid`), deslocado pra FORA e um pouco pra
        # FRENTE — a dobra de um braço relaxado, não uma pose de ataque.
        shoulder_pt = (ax, torso_y + 0.16 * h, bz + lean)
        hand_pt = (ax + sgn * 0.02 * h, torso_y - 0.14 * h, bz + lean)
        mid = tuple((s + e) / 2.0 for s, e in zip(shoulder_pt, hand_pt))
        elbow_pt = (mid[0] + sgn * 0.05 * h, mid[1], mid[2] + 0.05 * h)

        upper = _limb_segment("%s_Upper%d" % (prefix, int(sgn)), shoulder_pt, elbow_pt,
                              0.052 * h, 0.040 * h, cloth, vertices=6,
                              pattern=cloth_pattern, bevel_width=0.005 * h, tex_scale=0.3)
        fore = _limb_segment("%s_Fore%d" % (prefix, int(sgn)), elbow_pt, hand_pt,
                             0.038 * h, 0.030 * h, cloth, vertices=6,
                             pattern="soft", bevel_width=0.004 * h, tex_scale=0.28)
        elbow = add_sphere("%s_Elbow%d" % (prefix, int(sgn)), 0.036 * h,
                           to_bloc(*elbow_pt), cloth, subdivisions=1,
                           pattern=cloth_pattern, tex_scale=0.3, squash=(1.0, 1.0, 0.92))
        # Deltoide: vai JUNTO do braço (ao contrário da ombreira), porque o
        # ombro carnudo acompanha o giro — parado, abriria buraco no tronco.
        delt = add_sphere("%s_Delt%d" % (prefix, int(sgn)), 0.064 * h,
                          to_bloc(ax, torso_y + 0.145 * h, bz + lean), cloth,
                          subdivisions=1, pattern=cloth_pattern, tex_scale=0.3,
                          squash=(1.05, 0.95, 0.88))
        hand = add_sphere("%s_Hand%d" % (prefix, int(sgn)), 0.050 * h,
                          to_bloc(*hand_pt), skin, pattern=skin_pattern, roughness=0.8,
                          squash=(1.0, 0.82, 1.10))
        objs.extend([upper, fore, elbow, delt, hand])
        arm_parts[sgn] = [upper, fore, elbow, delt, hand]
        if shoulders:
            # Ombreira curva de verdade (calota achatada), não placa reta.
            objs.append(add_sphere("%s_Pauldron%d" % (prefix, int(sgn)), 0.092 * h,
                                   to_bloc(bx + sgn * 0.215 * h, torso_y + 0.148 * h,
                                           bz + lean),
                                   helmet_color, subdivisions=1, pattern="metal",
                                   metallic=0.5, roughness=0.45, tex_scale=0.3,
                                   squash=(1.12, 1.02, 0.58)))


def add_humanoid(prefix: str, base: tuple, height: float,
                  cloth: tuple = (0.35, 0.40, 0.52), skin: tuple = (0.80, 0.62, 0.46),
                  leather: tuple = (0.34, 0.24, 0.16), boots: tuple = (0.23, 0.16, 0.11),
                  helmet: str = "none", helmet_color: tuple = (0.66, 0.67, 0.70),
                  shoulders: bool = False, hunched: float = 0.0,
                  cloth_pattern: str = "cloth", skin_pattern: str = "soft",
                  separate_limbs: bool = False, sculpt: bool = True) -> list:
    """Bonequinho low-poly: pernas, botas, tronco, cinto, braços, mãos e
    cabeça, com opção de elmo/capuz/chifres e ombreiras. Todas as medidas
    são fração da altura total, então a mesma função serve pro aldeão de
    1.2m e pro colosso de 3.4m sem virar um boneco esticado.

    `base` é o ponto no CHÃO (Godot); `height` é a altura total até o topo
    da cabeça — é o que mantém compatibilidade com o CollisionShape3D que
    cada cena já tinha.

    ## `separate_limbs` — membros animáveis (padrão: desligado)

    Com `False` (padrão) NADA muda: as peças saem soltas e o `finalize()` do
    builder funde tudo num mesh só, exatamente como sempre foi. É por isso
    que nenhum dos ~137 builders existentes precisa ser tocado.

    Com `True`, quatro membros passam a ser objetos próprios com nomes fixos
    (`HUMANOID_LIMBS`: "LegL", "LegR", "ArmL", "ArmR"):

      • cada perna já vem com a BOTA soldada nela, e cada braço com a MÃO —
        senão a bota ficaria plantada no chão enquanto a perna gira;
      • a origem de cada membro é movida pro PIVÔ anatômico (quadril pra
        perna, ombro pro braço) com `set_origin`. Sem isso a peça giraria em
        torno do próprio centro e a perna sairia do corpo. Como o exportador
        glTF grava a origem do objeto como translação do nó, no Godot cada
        membro nasce como um `Node3D` posicionado no pivô e com base
        IDENTIDADE — girar em X é girar pra frente/trás, direto;
      • ombreira (`shoulders`) NÃO vai junto do braço de propósito: ela cobre
        o topo do ombro, que é justamente o ponto que não se mexe, e soldada
        no braço abriria um buraco no tronco a cada passada.

    O builder tem então DUAS obrigações: passar `keep=HUMANOID_LIMBS` no
    `finalize()` (senão os membros são fundidos de volta e a animação some
    sem erro nenhum) e soldar a arma no membro certo com `attach_to_limb()`.

    Convenção L/R: o eixo +X do Godot é a DIREITA do boneco quando ele encara
    -Z, que é o "frente" do `look_at`. Como o balanço é em contra-fase e
    simétrico, trocar L com R não estraga a caminhada — só o lado em que a
    arma aparece.

    ## `sculpt` — corpo esculpido (padrão: LIGADO desde a leva de
    ## articulação — ver "cotovelo" abaixo)

    Com `False` o corpo é o antigo: sete CAIXAS empilhadas (duas pernas,
    duas botas, tronco, cinto, dois braços). Lê como "caixote com cabeça" —
    foi exatamente a crítica que abriu o revamp visual, e nenhuma unidade
    nova deveria voltar a usar `False` de propósito. O parâmetro continua
    existindo (não foi removido) só porque não custa nada manter o caminho
    antigo vivo pra quem precisar comparar lado a lado.

    Com `True` (padrão) o mesmo esqueleto (mesmas alturas, mesmos pivôs,
    mesma silhueta geral) é remontado com VOLUMES CÔNICOS de 6–10 lados:

      • tronco em duas frustas empilhadas e ACHATADAS na profundidade
        (peito largo → cintura estreita), em vez de um paralelepípedo;
      • quadril próprio, que é a peça que mais some com o "caixote": sem ele
        as pernas nascem direto na base do tronco;
      • braço e perna afilando do ombro/quadril pro punho/tornozelo, com
        deltoide arredondado que ACOMPANHA o braço na animação;
      • bota com bico (peça própria), cabeça em ovo, elmo em calota com aba
        e nasal;
      • **cotovelo articulado**: o braço deixou de ser UM cone reto do ombro
        até a mão (a segunda metade do "boneco de Lego" — a primeira era a
        cabeça sem rosto, ver os `_Eye` logo abaixo do bloco de cabeça) e
        virou DOIS segmentos (`_limb_segment`, orientado por quaternion, não
        por Euler chutado) dobrando num cotovelo deslocado pra fora e pra
        frente. O PUNHO fica EXATAMENTE onde ficava no braço reto de antes —
        é o contrato que permite ~53 builders continuarem soldando arma e
        escudo com a MESMA coordenada `attach_to_limb` de sempre, sem precisar
        retocar um por um. `LimbAnimator` não precisou mudar: ele já girava o
        nó "ArmR"/"ArmL" inteiro, rígido, pelo pivô do ombro — o cotovelo é
        uma dobra ESTÁTICA assada na malha, que gira junto como uma peça só
        (mesmo motivo de sempre: não há esqueleto, ver `finalize()`).

    Custo MEDIDO (corpo de 1,50 m com elmo, ombreiras e cotovelo, já com
    chanfro): 592 → ~1.050 triângulos. Uma onda de 40 tropas sai de ~24 mil
    pra ~42 mil triângulos — nada perto dos ~150 mil do campo de grama, e
    menos ainda perto de qualquer construção. O teto prático que fica
    documentado é **~1.100 triângulos por humanoide**: acima disso o ganho de
    silhueta já não se lê na altura de câmera do RTS (a tropa tem ~90 px de
    altura na tela), e quem paga a conta passa a ser a contagem de unidades em
    onda grande, não o detalhe de cada uma."""
    objs = []
    # Peças que viram membro quando `separate_limbs` está ligado, indexadas
    # pelo sinal do lado (-1 = esquerda em +X, ver a convenção no docstring).
    leg_parts = {}
    arm_parts = {}
    bx, by, bz = base
    h = height
    leg_h = 0.34 * h
    torso_h = 0.33 * h
    head_r = 0.105 * h
    torso_y = by + leg_h + torso_h / 2.0
    lean = hunched * 0.05 * h

    if sculpt:
        _sculpted_body(prefix, base, h, leg_h, torso_h, torso_y, lean, cloth, skin,
                       leather, boots, helmet_color, shoulders, cloth_pattern,
                       skin_pattern, objs, leg_parts, arm_parts)
    else:
        for sgn in (-1.0, 1.0):
            leg = add_box("%s_Leg%d" % (prefix, int(sgn)),
                          (0.125 * h, 0.135 * h, leg_h),
                          to_bloc(bx + sgn * 0.095 * h, by + leg_h / 2.0, bz),
                          leather, pattern="soft", bevel_width=0.018 * h, tex_scale=0.3)
            boot = add_box("%s_Boot%d" % (prefix, int(sgn)),
                           (0.15 * h, 0.20 * h, 0.09 * h),
                           to_bloc(bx + sgn * 0.095 * h, by + 0.045 * h, bz + 0.025 * h),
                           boots, pattern="soft", bevel_width=0.016 * h, tex_scale=0.25)
            objs.append(leg)
            objs.append(boot)
            leg_parts[sgn] = [leg, boot]
        objs.append(add_box(prefix + "_Torso", (0.36 * h, 0.23 * h, torso_h),
                            to_bloc(bx, torso_y, bz + lean), cloth, pattern=cloth_pattern,
                            bevel_width=0.028 * h, tex_scale=0.35))
        objs.append(add_box(prefix + "_Belt", (0.38 * h, 0.25 * h, 0.05 * h),
                            to_bloc(bx, by + leg_h + 0.02 * h, bz), (0.24, 0.17, 0.11),
                            pattern="soft", bevel_width=0.012 * h, tex_scale=0.25))
        for sgn in (-1.0, 1.0):
            arm = add_box("%s_Arm%d" % (prefix, int(sgn)),
                          (0.105 * h, 0.115 * h, 0.29 * h),
                          to_bloc(bx + sgn * 0.225 * h, torso_y + 0.03 * h, bz + lean),
                          cloth, pattern=cloth_pattern, bevel_width=0.018 * h, tex_scale=0.3)
            hand = add_sphere("%s_Hand%d" % (prefix, int(sgn)), 0.052 * h,
                              to_bloc(bx + sgn * 0.225 * h, torso_y - 0.14 * h, bz + lean),
                              skin, pattern=skin_pattern, roughness=0.8)
            objs.append(arm)
            objs.append(hand)
            arm_parts[sgn] = [arm, hand]
            if shoulders:
                objs.append(add_box("%s_Pauldron%d" % (prefix, int(sgn)),
                                    (0.15 * h, 0.20 * h, 0.09 * h),
                                    to_bloc(bx + sgn * 0.215 * h, torso_y + 0.15 * h, bz + lean),
                                    helmet_color, pattern="metal", metallic=0.5, roughness=0.45,
                                    bevel_width=0.016 * h, tex_scale=0.3))
    head_y = by + leg_h + torso_h + head_r * 0.8
    objs.append(add_sphere(prefix + "_Head", head_r,
                           to_bloc(bx, head_y, bz + lean * 1.4), skin, subdivisions=1,
                           pattern=skin_pattern, roughness=0.85,
                           # Cabeça em OVO (mais alta que larga e um pouco mais
                           # estreita nas têmporas): a esfera perfeita é o que
                           # deixava a cabeça lendo como "bolinha espetada".
                           squash=(0.94, 0.90, 1.12) if sculpt else None))
    # Olhos: a cabeça sem NENHUM traço de rosto era a outra metade do "boneco
    # de Lego" (a outra é o braço reto, ver acima). Duas esferas escuras
    # cravadas na superfície — mesma matemática de posição do nasal do elmo
    # cônico logo abaixo, só um pouco ACIMA (sobrancelha) em vez de na linha
    # do nariz. Barato (2 esferas de 1 subdivisão) e vale pras DUAS versões
    # de corpo, não só a esculpida — por isso mora aqui, fora do `if sculpt`.
    eye_r = head_r * 0.115
    for sgn in (-1.0, 1.0):
        objs.append(add_sphere("%s_Eye%d" % (prefix, int(sgn)), eye_r,
                               to_bloc(bx + sgn * head_r * 0.36, head_y + head_r * 0.10,
                                       bz + lean * 1.4 + head_r * 0.86),
                               (0.05, 0.04, 0.05), subdivisions=0, pattern="soft",
                               roughness=0.35))
    if helmet == "dome":
        if sculpt:
            # Elmo em calota + aba + nasal. A calota é meia esfera achatada, e
            # não um cilindro: cilindro de 8 lados no topo da cabeça lê como
            # balde, que é exatamente a crítica de "unidade quadrada".
            objs.append(add_sphere(prefix + "_Helm", head_r * 1.10,
                                   to_bloc(bx, head_y + head_r * 0.34, bz + lean * 1.4),
                                   helmet_color, subdivisions=1, pattern="metal",
                                   metallic=0.55, roughness=0.4, tex_scale=0.3,
                                   squash=(1.0, 1.0, 0.86)))
            objs.append(add_cylinder(prefix + "_HelmRim", head_r * 1.16, head_r * 1.20,
                                     head_r * 0.20,
                                     to_bloc(bx, head_y + head_r * 0.26, bz + lean * 1.4),
                                     helmet_color, vertices=10, pattern="metal", metallic=0.6,
                                     roughness=0.35, bevel_width=0.006 * h, tex_scale=0.25))
            objs.append(add_box(prefix + "_Nasal", (head_r * 0.20, head_r * 0.16, head_r * 0.75),
                                to_bloc(bx, head_y + head_r * 0.02,
                                        bz + lean * 1.4 + head_r * 1.02),
                                helmet_color, pattern="metal", metallic=0.6, roughness=0.35,
                                bevel_width=0.005 * h, tex_scale=0.2))
        else:
            objs.append(add_cylinder(prefix + "_Helm", head_r * 0.55, head_r * 1.12, head_r * 1.15,
                                     to_bloc(bx, head_y + head_r * 0.55, bz + lean * 1.4),
                                     helmet_color, vertices=8, pattern="metal", metallic=0.55,
                                     roughness=0.4, bevel_width=0.01 * h))
    elif helmet == "hood":
        objs.append(add_sphere(prefix + "_Hood", head_r * 1.13,
                               to_bloc(bx, head_y + head_r * 0.26, bz + lean * 1.4 - head_r * 0.18),
                               helmet_color, subdivisions=1, pattern="cloth", roughness=0.9))
    elif helmet == "cone":
        objs.append(add_cylinder(prefix + "_Helm", 0.0, head_r * 1.16,
                                 head_r * (1.7 if not sculpt else 1.55),
                                 to_bloc(bx, head_y + head_r * 0.95, bz + lean * 1.4),
                                 helmet_color, vertices=10 if sculpt else 8, pattern="metal",
                                 metallic=0.55, roughness=0.4, bevel_width=0.0))
        if sculpt:
            # Aba + protetor nasal: dois detalhes minúsculos que fazem o elmo
            # cônico ler como PEÇA DE ARMADURA e não como chapéu de bruxa.
            objs.append(add_cylinder(prefix + "_HelmRim", head_r * 1.18, head_r * 1.24,
                                     head_r * 0.22,
                                     to_bloc(bx, head_y + head_r * 0.22, bz + lean * 1.4),
                                     helmet_color, vertices=10, pattern="metal", metallic=0.6,
                                     roughness=0.35, bevel_width=0.006 * h, tex_scale=0.25))
            objs.append(add_box(prefix + "_Nasal", (head_r * 0.20, head_r * 0.16, head_r * 0.72),
                                to_bloc(bx, head_y - head_r * 0.02,
                                        bz + lean * 1.4 + head_r * 1.02),
                                helmet_color, pattern="metal", metallic=0.6, roughness=0.35,
                                bevel_width=0.005 * h, tex_scale=0.2))
    elif helmet == "horns":
        objs.append(add_cylinder(prefix + "_Skull", head_r * 0.6, head_r * 1.1, head_r * 1.0,
                                 to_bloc(bx, head_y + head_r * 0.5, bz + lean * 1.4),
                                 helmet_color, vertices=8, pattern="metal", metallic=0.4,
                                 roughness=0.55, bevel_width=0.01 * h))
        for sgn in (-1.0, 1.0):
            objs.append(add_cylinder("%s_Horn%d" % (prefix, int(sgn)), 0.0, head_r * 0.35,
                                     head_r * 1.5,
                                     to_bloc(bx + sgn * head_r * 0.95, head_y + head_r * 1.25,
                                             bz + lean * 1.4),
                                     (0.86, 0.82, 0.72), vertices=6,
                                     rot=(0.0, sgn * 0.55, 0.0), pattern="soft",
                                     roughness=0.7, bevel_width=0.0))
    if not separate_limbs:
        return objs

    # --- membros animáveis (ver o bloco `separate_limbs` do docstring) ------
    # Cada membro vira UM objeto com a origem no pivô anatômico. A ordem
    # importa: primeiro `join_objects` (que herda a origem do primeiro
    # objeto), depois `set_origin` (que reposiciona sem mexer na geometria).
    merged = []
    absorbed = set()
    for sgn, name, pivot in (
        (1.0, "LegR", (bx + 1.0 * 0.095 * h, by + leg_h, bz)),
        (-1.0, "LegL", (bx - 1.0 * 0.095 * h, by + leg_h, bz)),
    ):
        parts = leg_parts[sgn]
        absorbed.update(id(p) for p in parts)
        limb = join_objects(parts, name)
        set_origin(limb, pivot)
        merged.append(limb)
    # O pivô do braço fica um pouco ABAIXO do topo da manga (0.16h contra
    # 0.175h): girando pelo topo exato aparecia uma fresta entre manga e
    # tronco nos ângulos grandes do golpe.
    for sgn, name in ((1.0, "ArmR"), (-1.0, "ArmL")):
        parts = arm_parts[sgn]
        absorbed.update(id(p) for p in parts)
        limb = join_objects(parts, name)
        set_origin(limb, (bx + sgn * 0.225 * h, torso_y + 0.16 * h, bz + lean))
        merged.append(limb)
    # Os objetos absorvidos pelo `join` foram REMOVIDOS do arquivo — só o
    # `id()` pode ser consultado sem estourar ReferenceError.
    return [o for o in objs if id(o) not in absorbed] + merged


def add_ore_chunks(prefix: str, center: tuple, count: int = 5, spread: float = 0.5,
                    radius: float = 0.16, color: tuple = (0.44, 0.38, 0.35),
                    seed: int = 1) -> list:
    rng = random.Random(seed)
    objs = []
    cx, cy, cz = center
    for i in range(count):
        a = rng.uniform(0.0, math.tau)
        r = rng.uniform(0.0, spread)
        s = radius * rng.uniform(0.6, 1.25)
        objs.append(add_sphere("%s_%d" % (prefix, i), s,
                               to_bloc(cx + math.sin(a) * r, cy + s * 0.55, cz + math.cos(a) * r),
                               color, jitter_amount=0.05, pattern="ore", roughness=0.8))
    return objs


def join_objects(objs: list, name: str):
    """Junta vários objetos num só mesh com o nome pedido — usado nas peças
    animadas (SawBlade, MineCart) pra o Godot encontrar UM nó só por nome."""
    objs = [o for o in objs if o is not None and o.name in bpy.data.objects]
    if not objs:
        return None
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    prev = _activate(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.select_set(False)
    return joined


def set_origin(obj, godot_point: tuple) -> None:
    """Move a origem do objeto pra um ponto do mundo (Godot) sem mover a
    geometria — essencial pra peça girar/andar em torno do eixo certo."""
    target = bpy.context.scene.cursor.location.copy()
    bpy.context.scene.cursor.location = to_bloc(*godot_point)
    prev = _activate(obj)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    _restore(prev, obj)
    bpy.context.scene.cursor.location = target


# ------------------------------------------------ compatibilidade (antigos)

def add_window(name: str, size: tuple, loc: tuple, rot: tuple = (0, 0, 0),
               color: tuple = (0.85, 0.72, 0.35)):
    """Janela chapada antiga — mantida só pra não quebrar scripts legados."""
    return add_box(name, size, loc, color, rot=rot, pattern="window", roughness=0.25,
                   metallic=0.1, bevel_width=0.012, tex_scale=max(size))


def add_door(name: str, size: tuple, loc: tuple, rot: tuple = (0, 0, 0),
             color: tuple = (0.3, 0.19, 0.11)):
    return add_box(name, size, loc, color, rot=rot, pattern="planks", roughness=0.85,
                   bevel_width=0.014, tex_scale=max(size))


def export(path: str) -> None:
    # Skins arquitetônicas: a pegada não pode passar da do modelo original (ver `arch_fit.py`).
    try:
        import arch_fit
        arch_fit.fit(path)
    except ImportError:
        pass
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB')
    print("EXPORTED_OK:", path)
