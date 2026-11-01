"""Ajusta o .import das texturas pintadas: VRAM comprimida (S3TC/BPTC no desktop, ETC2/ASTC no
celular) e mipmaps nas texturas de superfície; céu comprimido sem mipmap (o panorama só é lido de
frente, e mipmap na emenda do equirretangular gera uma linha).
Rodar depois de gerar as texturas e antes do `godot --import`. Se o .import ainda não existe, rode o
import uma vez, rode este script e importe de novo.
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.path.join(ROOT, "game", "assets", "textures")
MAP = os.path.join(ROOT, "game", "assets", "map")

for imp in glob.glob(os.path.join(TEX, "*.png.import")) + glob.glob(os.path.join(MAP, "*.png.import")):
    s = open(imp, encoding="utf-8").read()
    sky = os.path.basename(imp).startswith("sky_")
    want = {
        "compress/mode": "2",
        "mipmaps/generate": "false" if sky else "true",
        "detect_3d/compress_to": "0",
    }
    for k, v in want.items():
        s = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), s, flags=re.M)
    open(imp, "w", encoding="utf-8").write(s)
    print("ok", os.path.basename(imp))
