"""Acrescenta ao student.glb (já riggado pelo Mixamo, com as animações) as peças novas do base_tpose.glb
(adultos), copiando os pesos de pele das peças adolescentes mais próximas. Funciona porque as juntas
são as mesmas nos dois modelos.
blender --background --factory-startup --python tools/blender/add_adult_parts.py -- <student.glb> <base_tpose.glb> <saida.glb>
"""
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
STUDENT, BASE, OUT = argv

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=STUDENT)
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
old = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
print("riggadas:", sorted(old))

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=BASE)
imported = [o for o in bpy.data.objects if o not in before]
new_meshes = []
for o in imported:
    if o.type != "MESH":
        continue
    nm = o.name.split(".")[0]
    if nm in old:
        continue
    new_meshes.append((nm, o))
print("novas:", [n for n, _ in new_meshes])


def wbbox(o):
    # pela malha de descanso (bound_box viria posado pela animação ativa)
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


# alinha o modelo base ao riggado pelo corpo (mesma peça nos dois): escala + deslocamento
ref_new = next(o for o in imported if o.type == "MESH" and o.name.split(".")[0] == "Body_m")
lo_a, hi_a = wbbox(old["Body_m"])
lo_b, hi_b = wbbox(ref_new)
s = (hi_a.z - lo_a.z) / (hi_b.z - lo_b.z)
print("escala", s)

# fonte de pesos: cópia unida das peças adolescentes (corpo, roupa, calça, sapato, cabelo, rosto)
src_parts = [o for n, o in old.items()]
bpy.ops.object.select_all(action="DESELECT")
copies = []
for o in src_parts:
    c = o.copy()
    c.data = o.data.copy()
    bpy.context.scene.collection.objects.link(c)
    copies.append(c)
for c in copies:
    # aplica a pose de descanso (armature modifier fica, mas usamos só os grupos de vértices)
    for m in list(c.modifiers):
        c.modifiers.remove(m)
    c.select_set(True)
bpy.context.view_layer.objects.active = copies[0]
bpy.ops.object.join()
src = bpy.context.view_layer.objects.active
src.name = "_src_weights"

for nm, o in new_meshes:
    # coloca a peça no espaço do modelo riggado
    o.parent = None
    mw = o.matrix_world.copy()
    o.matrix_world = mw
    bpy.context.view_layer.update()
    lo, hi = wbbox(o)
    # escala em torno da origem do base e reposiciona pelos pés do corpo de referência
    o.matrix_world = mw
    o.scale = o.scale * s
    bpy.context.view_layer.update()
    lo_r, _ = wbbox(ref_new)
    off_ref = (lo_b.x + hi_b.x) / 2, (lo_b.y + hi_b.y) / 2, lo_b.z
    # deslocamento calculado a partir do corpo de referência escalado
    o.location = o.location + (Vector(((lo_a.x + hi_a.x) / 2, (lo_a.y + hi_a.y) / 2, lo_a.z)) -
                               Vector(off_ref) * s)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.name = nm
    o.data.name = nm
    # grupos de vértices iguais aos da fonte e transferência de pesos pela superfície mais próxima
    o.vertex_groups.clear()
    for g in src.vertex_groups:
        o.vertex_groups.new(name=g.name)
    dt = o.modifiers.new("dt", "DATA_TRANSFER")
    dt.object = src
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.modifier_apply(modifier="dt")
    # limpa grupos vazios demais não é preciso; normaliza
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    # usa os mesmos materiais do modelo riggado (o jogo colore pelo nome M_skin, M_top...)
    for slot in o.material_slots:
        if slot.material and "." in slot.material.name:
            base = bpy.data.materials.get(slot.material.name.split(".")[0])
            if base:
                slot.material = base
    # mesma hierarquia/transformação do corpo adolescente (o skin do glTF depende disso);
    # os vértices são compensados para continuar no mesmo lugar do mundo
    ref = old["Body_m"]
    o.parent = ref.parent
    o.parent_bone = ref.parent_bone
    o.parent_type = ref.parent_type
    o.matrix_parent_inverse = ref.matrix_parent_inverse.copy()
    o.matrix_basis = ref.matrix_basis.copy()
    bpy.context.view_layer.update()
    o.data.transform(o.matrix_world.inverted())
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    print("pos", nm, [round(v, 3) for v in wbbox(o)[0]], [round(v, 3) for v in wbbox(o)[1]], "ref", [round(v, 3) for v in wbbox(ref)[1]])

# remove o que sobrou do base (esqueleto/vazios) e a fonte de pesos
for o in imported:
    if o.name not in bpy.data.objects:
        continue
    if o.type == "MESH" and any(o is m for _, m in new_meshes):
        continue
    bpy.data.objects.remove(o, do_unlink=True)
bpy.data.objects.remove(src, do_unlink=True)

for o in bpy.context.scene.objects:
    if o.type == "MESH":
        print("malha", o.name, len(o.data.polygons), [m.name for m in o.data.materials])

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                          export_yup=True, export_apply=False)
print("OK", OUT)
