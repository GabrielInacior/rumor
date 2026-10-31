"""Monta o personagem final do jogo a partir das exportações do Mixamo.

idle.fbx traz malha + esqueleto (com pele); os outros trazem só o esqueleto animado. Cada ação vira
uma faixa NLA com o nome usado pelo jogo (idle, falando, pensando...), e o glTF sai com todas.
blender --background --factory-startup --python tools/blender/assemble_student.py -- <pasta_raw> <saida.glb>
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
RAW, OUT = argv[0], argv[1]
NAMES = ["idle", "falando", "pensando", "nervoso", "negando", "apontando", "dando_de_ombros", "rindo", "walking"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(RAW, "idle.fbx"), automatic_bone_orientation=False)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
arm.name = "Rig"
base_act = arm.animation_data.action
base_act.name = "idle"

for n in NAMES[1:]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(RAW, n + ".fbx"), automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    other = next(o for o in new if o.type == "ARMATURE")
    act = other.animation_data.action
    act.name = n
    act.use_fake_user = True
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)

# todas as ações viram faixas NLA no mesmo esqueleto (o exportador glTF gera uma animação por faixa)
ad = arm.animation_data
ad.action = None
for n in NAMES:
    act = bpy.data.actions.get(n)
    if act is None:
        print("FALTOU", n)
        continue
    tr = ad.nla_tracks.new()
    tr.name = n
    st = tr.strips.new(n, int(act.frame_range[0]), act)
    st.name = n
    tr.mute = False

for o in bpy.context.scene.objects:
    if o.type == "MESH":
        print("malha", o.name, [m.name for m in o.data.materials], len(o.data.polygons))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                          export_yup=True, export_apply=False)
print("OK", OUT)
