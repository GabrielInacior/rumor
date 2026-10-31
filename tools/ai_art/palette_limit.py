# Limita a paleta de um sprite já recortado por `sprite_icon.ps1`.
#
# O re-grid do `sprite_icon.ps1` pega a cor MAIS FREQUENTE de cada célula, mas a
# API devolve centenas de tons quase iguais (ruído de compressão), então o PNG
# final sai com ~300 cores — pixel art de verdade tem rampa curta, 3-4 tons por
# material. Isto reduz pra `k` cores (MAXCOVERAGE preserva o acento pequeno, ex.
# o lacre vermelho do "?" de evento, que MEDIANCUT engolia) e mantém o alfa
# binário intacto.
# Uso: python palette_limit.py <entrada.png> <saida.png> [k=10]
import sys
from PIL import Image

src = Image.open(sys.argv[1]).convert("RGBA")
k = int(sys.argv[3]) if len(sys.argv) > 3 else 10
q = src.convert("RGB").quantize(colors=k, method=Image.Quantize.MAXCOVERAGE).convert("RGBA")
q.putalpha(src.getchannel("A"))
q.save(sys.argv[2])
print("OK", sys.argv[2], "cores", len({p[:3] for p, a in zip(q.getdata(), src.getchannel("A").getdata()) if a}))
