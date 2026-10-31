"""Renderiza um ícone 2D (PNG, fundo transparente) de cada construção e
unidade recrutável, a partir do próprio modelo .glb já texturizado —
garante que o ícone da UI bate exatamente com o visual do modelo em jogo.
Câmera ortográfica em ângulo isométrico, motor Workbench (rápido, mostra
a textura sem precisar configurar luz de estúdio manualmente).

Rodar com:
  blender.exe --background --python tools/blender/render_icons.py
  blender.exe --background --python tools/blender/render_icons.py -- core mine
  blender.exe --background --python tools/blender/render_icons.py -- card

--------------------------------------------------------------------------
DUAS SAÍDAS PRO MESMO RENDER: O ÍCONE E O RETRATO DE CARTA
--------------------------------------------------------------------------
O modo `card` (só construções) renderiza o MESMO enquadramento a 512 px em
`<id>_card.png`, ao lado do `<id>.png` de sempre. Ele existe porque a carta de
DESCOBERTA de construção (`upgrade_card.gd`) mostra a peça num retrato de 174
px, e o ícone normal não serve pra isso: ele é importado com
`process/size_limit=64` (ver abaixo), ou seja, chega ao jogo com 64 px de lado.
A 36 px na grade do HUD isso é exatamente o que se quer; ampliado pra 174 numa
carta, é borrão — e borrão ao lado das 169 ilustrações de carta desenhadas em
512 é inconsistência que se vê de longe.

Não é o mesmo arquivo com dois `.import` (o Godot só admite um por arquivo),
nem o mesmo arquivo sem `size_limit` (isso devolveria o chiado na grade, que é
onde o ícone aparece o tempo todo). São dois arquivos porque são dois usos com
exigências opostas de amostragem: um vai pra 36 px sob NEAREST, o outro pra 174
sob LINEAR+mipmap.

--------------------------------------------------------------------------
POR QUE O ÍCONE DE HUD CONTINUA EM 256 E A REDUÇÃO ACONTECE NA IMPORTAÇÃO
--------------------------------------------------------------------------
O ícone aparece no jogo a 32-52 px (`hud.gd`: 36 na grade de construir/
recrutar e 32 na dica; `inspect_panel.gd`: 52) e o projeto roda com
`rendering/textures/canvas_textures/default_texture_filter=0` (NEAREST). Sair
de 256 direto pra 36 por amostragem pontual joga fora ~7 de cada 8 pixels: a
textura do modelo vira chiado e detalhe fino (ameia, seteira, telha) some ou
aparece dependendo do pixel que calhou de ser amostrado.

A saída NÃO foi baixar o RESOLUTION daqui. Foi pôr `process/size_limit=64` no
`.import` de cada PNG: o Godot reduz pra 64 px na importação, com filtro
cúbico, e o ponto-amostra final passa a ler uma imagem já lisa. Duas vantagens
sobre renderizar pequeno:

  * o master de 256 fica no repositório — se uma tela precisar do ícone
    grande, é só subir o `size_limit`, sem re-renderizar 22 modelos;
  * nada no enquadramento/iluminação muda, então não há risco de o conjunto
    aprovado sair diferente.

Este raciocínio é DIFERENTE do dos ícones de recurso (grade lógica 16x16
exportada a 4x, em `generate_ui_art.py`). Lá a arte é desenhada e pode ser
desenhada no tamanho final; aqui ela é derivada de modelo, e o que se escolhe
é ONDE a redução acontece — na importação com filtro, e não na amostragem da
GPU.
"""

import bpy
import sys
import math
from mathutils import Vector

MODELS_DIR = "C:/Project/game/assets/models"
ICONS_DIR = "C:/Project/game/assets/icons"
RESOLUTION = 256
## Retrato de carta (ver o cabeçalho): 512 pra chegar aos 174 px da carta
## REDUZIDO, que é a única faixa em que mipmap ajuda. Só construção — a carta de
## descoberta e a de aprimoramento falam de peça erguida, nunca de tropa nem de
## inimigo.
CARD_RESOLUTION = 512
CARD_SUFFIX = "_card"

ASSETS = [
    ("buildings", "gate"), ("buildings", "barracks"), ("buildings", "wall"),
    ("buildings", "house"), ("buildings", "mine"), ("buildings", "sawmill"),
    ("buildings", "farm"), ("buildings", "tower_support"), ("buildings", "core"),
    ("buildings", "tower_archer"), ("buildings", "tower_mage"), ("buildings", "tower_cannon"),
    # leva de defesa (5) — fecha a lacuna nº 1 do roster de defesa
    ("buildings", "tower_electric"), ("buildings", "tower_fire"),
    ("buildings", "tower_ice"), ("buildings", "tower_poison"), ("buildings", "tower_rune"),
    # lote de economia (16)
    ("buildings", "lumber_camp"), ("buildings", "quarry"), ("buildings", "deep_shaft"),
    ("buildings", "market"), ("buildings", "smeltery"), ("buildings", "mint"),
    ("buildings", "distillery"), ("buildings", "windmill"), ("buildings", "trade_post"),
    ("buildings", "apiary"), ("buildings", "treasury"), ("buildings", "plunder_post"),
    ("buildings", "cistern"), ("buildings", "geothermal_forge"),
    ("buildings", "alchemy_lab"), ("buildings", "salvage_yard"),
    ("buildings", "gold_mine"),
    # lote de buff/suporte (16)
    ("buildings", "command_banner"), ("buildings", "watch_post"),
    ("buildings", "drill_yard"), ("buildings", "signal_pyre"),
    ("buildings", "chapel"), ("buildings", "iron_forge"),
    ("buildings", "bulwark_stone"), ("buildings", "march_horn"),
    ("buildings", "engineer_workshop"), ("buildings", "tar_kiln"),
    ("buildings", "lightning_rod"), ("buildings", "forward_outpost"),
    ("buildings", "storm_dynamo"), ("buildings", "rune_pillar"),
    ("buildings", "reliquary"), ("buildings", "mana_obelisk"),
    # lote místico (12 templos) — só as CONSTRUÇÕES; a criatura não tem célula
    # na grade de construir, ela sai do templo
    ("buildings", "santuario_de_pedra"), ("buildings", "sacrario_glacial"),
    ("buildings", "ninho_do_grifo"), ("buildings", "tumulo_sussurrante"),
    ("buildings", "fosso_da_naga"), ("buildings", "cratera_votiva"),
    ("buildings", "pira_da_fenix"), ("buildings", "claustro_serafico"),
    ("buildings", "bosque_anciao"), ("buildings", "cume_do_trovao"),
    ("buildings", "armaria_runica"), ("buildings", "fonte_encantada"),
    # Observatório Arcano (místico, fonte de Sorte — docs/atributo_sorte.md)
    ("buildings", "observatorio_arcano"),
    # torres novas (docs/torres_novas.md, modelos em towers_new.py)
    ("buildings", "tower_reaper"), ("buildings", "tower_beam"), ("buildings", "tower_mortar"),
    ("buildings", "tower_ballista"), ("buildings", "tower_wind"), ("buildings", "tower_mines"),
    ("buildings", "tower_sentinel"), ("buildings", "tower_crypt"), ("buildings", "tower_quake"),
    ("buildings", "tower_acid"),
    # lote de quartéis (12) — só as CONSTRUÇÕES: a tropa não tem célula na
    # grade de construir, então não precisa de ícone de HUD
    ("buildings", "crossbow_house"), ("buildings", "halberd_yard"),
    ("buildings", "guard_hall"), ("buildings", "tourney_yard"),
    ("buildings", "hunters_blind"), ("buildings", "powder_house"),
    ("buildings", "siege_park"), ("buildings", "sapper_trench"),
    ("buildings", "outrider_post"), ("buildings", "mercenary_camp"),
    ("buildings", "sling_range"), ("buildings", "kennel"),
    # quartéis das 5 tropas ORIGINAIS (o Lanceiro já tinha o seu)
    ("buildings", "arms_house"), ("buildings", "archery_yard"),
    ("buildings", "engineer_guild"), ("buildings", "stable"),
    # curandeiros (docs/catalogo_conteudo.md): Enfermaria → Médico, Templo → Sacerdote
    ("buildings", "enfermaria"), ("buildings", "templo"),
    ("units", "spearman"), ("units", "archer"), ("units", "swordsman"),
    ("units", "engineer"), ("units", "cavalry"),
    # variantes do sistema de upgrades — o HUD pode querer mostrar o "antes
    # e depois"; o ícone sai no mesmo formato dos outros
    ("buildings", "mine_upgraded"), ("buildings", "sawmill_upgraded"),
    ("buildings", "wall_upgraded"), ("buildings", "tower_archer_upgraded"),
    ("buildings", "core_upgraded"),
]

# --------------------------------------------------------------------------
# INIMIGOS — o retrato da ficha de inspeção
# --------------------------------------------------------------------------
# A ficha (`inspect_panel.gd`) mostra um nicho emoldurado com o retrato do que
# foi clicado, e até agora só construção e tropa tinham arte: clicar num
# inimigo abria uma ficha sem cara nenhuma. O modelo já existe em
# `assets/models/enemies/`, então o retrato sai da MESMA receita — nada de
# desenhar arte nova que fatalmente divergiria do bicho em campo.
#
# ORDEM IMPORTA: os ids BASE vêm primeiro e as skins de bioma depois. Um
# inimigo sempre carrega o id base (a skin só troca o `.glb` do nó `Model`,
# `enemy_base.gd::_apply_biome_skin`), então o ícone base é o que NUNCA pode
# faltar; o da skin é refinamento. Renderizar nessa ordem faz uma rodada
# interrompida no meio ainda deixar o elenco inteiro coberto.
ENEMIES_BASE = [
    # chefes (6)
    "arquimago_amaldicoado", "corvondir", "dragao_cinzas",
    "leviata_profundezas", "maquina_ceifadora", "rainha_enxame",
    # elenco comum
    "berserker", "brood_carrier", "bulbo_de_praga", "ceifador_glacial",
    "climber", "colossus", "cria_carniceira", "cuspidor_de_piche",
    "destroyer", "enxame_faiscante", "horde", "impaler", "juggernaut",
    "mage", "matriz_carniceira", "nucleo_magmatico", "oferente_maldito",
    "packhound", "pillager", "ratling", "sacerdote_profano",
    "shieldbearer", "siege", "tank", "vespa_arcana", "warbeast", "zealot",
    # enxames (corpos de MultiMesh: o modelo é o mesmo, só nunca tinham retrato)
    "swarm_ant", "swarm_drone", "swarm_hopper", "swarm_larva", "swarm_rat",
    "swarm_ravager", "swarm_scarab", "swarm_stalker",
]

# Skins de bioma que JÁ têm `.glb` exportado. Cada uma é opcional: sem ícone
# próprio a ficha cai no retrato do id base (ver `_icon_for` no
# `inspect_panel.gd`), que continua sendo a mesma espécie.
ENEMIES_SKINS = [
    "arquimago_amaldicoado_floresta", "berserker_abrasada",
    "brood_carrier_pantano", "bulbo_de_praga_pantano",
    "climber_abrasada", "climber_caverna", "climber_floresta",
    "climber_pantano", "colossus_abrasada", "colossus_caverna",
    "horde_abrasada", "horde_caverna", "horde_deserto", "horde_floresta",
    "horde_pantano", "juggernaut_abrasada", "juggernaut_tundra",
    "leviata_profundezas_tundra", "maquina_ceifadora_deserto",
    "packhound_abrasada", "packhound_caverna", "packhound_deserto",
    "packhound_floresta", "packhound_tundra", "rainha_enxame_pantano",
    "ratling_caverna", "ratling_deserto", "shieldbearer_deserto",
    "tank_tundra", "warbeast_floresta", "warbeast_pantano",
    "warbeast_tundra",
    # Planalto Trovejante: inimigo e chefe novos (ids base) + as 6 skins.
    "bisao_trovejante", "touro_bronze",
    "horde_planalto", "packhound_planalto", "zealot_planalto",
    "warbeast_planalto", "climber_planalto", "destroyer_planalto",
    # Selva das Monções: chefe, inimigo novo e girino (ids base) + as 6 skins.
    "rei_moncao", "druida_moncao", "girino_moncao",
    "horde_selva", "mage_selva", "sacerdote_profano_selva",
    "oferente_maldito_selva", "nucleo_magmatico_selva", "berserker_selva",
    # Salinas de Coral: chefe e inimigo novo (ids base) + as 6 skins.
    "ermitao_naufragio", "caranguejo_sitiante",
    "horde_salinas", "siege_salinas", "impaler_salinas",
    "cuspidor_de_piche_salinas", "pillager_salinas", "destroyer_salinas",
    # Cicatriz Prismática: chefe, estilhaço e inimigo novo (ids base) + as 6 skins.
    "colosso_vitral", "estilhaco_prismar", "golem_vitral",
    "horde_prisma", "shieldbearer_prisma", "tank_prisma",
    "juggernaut_prisma", "ceifador_glacial_prisma", "destroyer_prisma",
    # Arquipélago Celeste: chefe e inimigo novo (ids base) + as 6 skins.
    "baleia_celeste", "medusa_eter",
    "horde_celeste", "bulbo_de_praga_celeste", "brood_carrier_celeste",
    "matriz_carniceira_celeste", "enxame_faiscante_celeste", "ratling_celeste",
    # Chefe FINAL (Fortaleza em Ruínas): Vharzul, o Rei Eclipsado.
    "rei_eclipsado",
    # Evento raro Horror Cósmico: Ul'Thagor, o Sonhador do Abismo.
    "sonhador_abissal",
    # Subchefe do mesmo evento: Vorh'Naal, o Pastor do Abismo.
    "pastor_abissal",
    # Evento raro Floresta Desperta: o Velho Carvalho Insone e o molde de árvore (página do Códice).
    "anciao_floresta", "anciao_floresta_pedra", "anciao_floresta_cristal", "anciao_floresta_areia", "awakened_tree",
    # Evento raro dos Titãs: o chefe Morhuld e o retrato da página do Códice
    # (o Andarilho é o rosto do evento).
    "titan_carapaca", "titan_andarilho",
]

ASSETS += [("enemies", e) for e in ENEMIES_BASE + ENEMIES_SKINS]

# --------------------------------------------------------------------------
# RESKINS DE CIVILIZAÇÃO — o ícone tem que ser a peça que vai SER erguida
# --------------------------------------------------------------------------
# `BuildingBase._apply_civilization_skin()` troca o `.glb` do nó `Model` por
# `<structure_id>_<sufixo>.glb` quando a civilização da expedição tem arte
# própria. O `structure_id` NÃO muda — é o mesmo "tower_archer" — então, sem
# ícone próprio, a grade de construir mostrava a torre MEDIEVAL e o jogador
# erguia uma torre egípcia. O ícone precisa da mesma variação que o modelo, e
# pela mesma receita (render do próprio `.glb`), senão as duas artes divergem.
#
# Vale a mesma tolerância dos inimigos: ícone civ-específico é OPCIONAL. Quem
# resolve (`BuildingCatalog.icon_of()`) cai no ícone padrão quando o arquivo
# não existe, então construção sem reskin não precisa de nada aqui.
CIV_SUFFIXES = ["nordica", "japonesa", "egipcia", "grega", "longxuan", "xolotec"]


def civ_skinned_assets():
    """Lê do DISCO quais reskins existem, em vez de manter lista à mão.

    Reskin novo entra por `generate_all.py`, que é um arquivo de 20 mil linhas
    com outro dono; obrigar quem escreve um builder a lembrar de uma segunda
    lista aqui é garantir que um dia o `.glb` novo saia sem ícone — e a falta
    de ícone é SILENCIOSA (cai no medieval, ninguém vê). Varrendo a pasta, o
    ciclo vira: exportou o modelo, rodou o render, tem ícone.
    """
    import os
    found = []
    for name in sorted(os.listdir("%s/buildings" % MODELS_DIR)):
        if not name.endswith(".glb"):
            continue
        base = name[:-4]
        for civ in CIV_SUFFIXES:
            if base.endswith("_%s" % civ):
                found.append(("buildings", base))
    return found


ASSETS += civ_skinned_assets()


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_bounds(objects):
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        if obj.type != 'MESH':
            continue
        for corner in obj.bound_box:
            world_co = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, world_co.x)
            mins.y = min(mins.y, world_co.y)
            mins.z = min(mins.z, world_co.z)
            maxs.x = max(maxs.x, world_co.x)
            maxs.y = max(maxs.y, world_co.y)
            maxs.z = max(maxs.z, world_co.z)
    center = (mins + maxs) / 2.0
    size = max(maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z, 0.2)
    return center, size


def model_path(category: str, asset_id: str) -> str:
    """O `.glb` que o JOGO mostra pra esse id. Tropas e inimigos humanoides do
    rework v2 vivem em `<id>_v2.glb` (a cena aponta pra ele; o `<id>.glb` antigo
    fica guardado até o rework terminar), então o ícone sai do `_v2` quando ele
    existe — senão o retrato mostraria o modelo de caixa que ninguém mais vê."""
    import os
    v2 = "%s/%s/%s_v2.glb" % (MODELS_DIR, category, asset_id)
    if os.path.exists(v2):
        return v2
    return "%s/%s/%s.glb" % (MODELS_DIR, category, asset_id)


def render_icon(category: str, asset_id: str, resolution: int = RESOLUTION,
                suffix: str = "") -> None:
    clear_scene()
    glb_path = model_path(category, asset_id)
    bpy.ops.import_scene.gltf(filepath=glb_path)

    imported = list(bpy.context.selected_objects)
    center, size = world_bounds(imported)

    direction = Vector((1.0, -1.0, 0.85)).normalized()
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = size * 1.35
    cam_obj = bpy.data.objects.new("IconCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = center + direction * size * 4.0
    look_dir = (center - cam_obj.location).normalized()
    cam_obj.rotation_euler = look_dir.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam_obj

    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.studio_light = 'Default'
    scene.display.shading.studiolight_rotate_z = math.radians(35)
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_shadows = True
    scene.display.shading.shadow_intensity = 0.25
    scene.render.film_transparent = True
    scene.view_settings.exposure = 0.7
    scene.view_settings.view_transform = 'Standard'
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    out_path = "%s/%s/%s%s.png" % (ICONS_DIR, category, asset_id, suffix)
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("ICON_OK:", out_path)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    # sem argumento renderiza tudo; com argumento, só os ids pedidos (o ciclo
    # "ajustei um builder, quero ver só esse ícone de novo" fica instantâneo)
    # O filtro aceita id ("core") OU categoria inteira ("enemies"): com o
    # elenco de inimigos passando de 60 modelos, "renderiza só a pasta que eu
    # mexi" virou o ciclo normal, e listar 60 ids na linha de comando não é.
    # `card` é MODO, não id: renderiza o retrato de carta (512, sufixo
    # `_card`) das construções em vez do ícone de HUD. Sai da lista de filtros
    # antes de qualquer coisa pra não ser confundido com um asset chamado
    # "card"; o resto do argv continua filtrando ids/categorias como sempre,
    # então `-- card mine` regenera o retrato só da mina.
    card_mode = "card" in argv
    if card_mode:
        argv = [a for a in argv if a != "card"]

    todo = [a for a in ASSETS if not argv or a[1] in argv or a[0] in argv]
    if card_mode:
        todo = [a for a in todo if a[0] == "buildings"]
        for cat, asset_id in todo:
            render_icon(cat, asset_id, CARD_RESOLUTION, CARD_SUFFIX)
    else:
        for cat, asset_id in todo:
            render_icon(cat, asset_id)
    print("ALL_ICONS_DONE:", len(todo))
