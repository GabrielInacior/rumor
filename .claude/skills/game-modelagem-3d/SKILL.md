---
name: game-modelagem-3d
description: OBRIGATÓRIA antes de criar ou refazer qualquer modelo 3D deste jogo (personagem, NPC, cenário, prop, construção). Régua de qualidade herdada do FortressChaos, técnica de Blender headless em Python, orçamentos, desempenho em Godot e o ciclo de captura e comparação que impede modelo feio de entrar.
---

# Modelagem 3D: padrão obrigatório

Herdado do projeto FortressChaos (`C:\Project\game`), onde esse padrão foi aprovado pelo usuário.
Se for delegar a um agente, cole o essencial desta skill no briefing (agentes novos não a leem sozinhos).

## 1. A régua

Um modelo só entra se **ler como o que ele é à primeira vista, na câmera do jogo**. Bloco reto,
"armário", recolor de outro modelo e silhueta genérica são reprovados. O usuário julga arte por
"cara de feito com carinho": detalhe, variação, desgaste, acessórios do papel. Vale igual para
qualquer modelo de IA e em qualquer sessão. Se não chegar lá, itere; nunca entregue "quase lá".

Imagens que atingiram a régua no outro jogo: `docs/referencias_visuais_fortresschaos/`
(tropas humanoides, criatura, chefes). Use como nível de acabamento, não como estilo a copiar;
quando este jogo tiver as próprias referências aprovadas, crie `docs/referencias_visuais/`.

O que todo modelo precisa:
- **Silhueta legível** na câmera real, proporção estilizada (humanoide: cabeça, mãos e pés maiores).
- **Peças separadas com contorno** (peça escura um pouco maior por baixo da clara, ou outline shader).
- **Detalhe de personalidade**: rosto, adornos, objetos do papel.
- **Paleta rica e coerente**, acento de cor, emissivo só onde faz sentido (janela, lâmpada, runa).
- **Texturas pixel art** 32 px pintadas por código (não textura lisa nem foto), se o estilo do jogo for esse.

## 2. Técnica (Blender headless)

- Blender: `C:/Program Files/Blender Foundation/Blender 5.2/blender.exe`.
  `blender --background --factory-startup --python tools/blender/<script>.py -- <args>`
- `tools/blender/fortaleza_kit.py` (copiado do FortressChaos): primitivas, `add_material()` com
  Principled BSDF, `make_pixel_texture(name, base_color, pattern, size, seed)` com ~20 padrões
  (`wood`, `stone`, `metal`, `glass`, `rune`, `crystal`...) e o motor de textura pintada
  (`save_painted_texture_png`). Leia a seção "Luz e emissivo" do docstring antes de mexer em
  emissivo (ACES puxa emissivo > 1 pro branco; luz de sol clareia albedo mais que o autorado).
- `tools/blender/render_icons.py`: renderiza `.glb` como ícone (ortográfica, fundo transparente).
- Biblioteca de consulta (não copiada, é grande e acoplada): `C:\Project\game\tools\blender\`
  - `unit_kit_v2.py`: kit de personagem por RECEITA (`t.legs(); t.torso(...); t.head(face=...)`),
    esqueleto de 20 ossos com peças rígidas (peso 1), todos os ossos apontando +Y, rolagem 0,
    soquetes de arma; receitas em `unit_v2_valmora*.py`.
  - `generate_all.py`: padrão "cada peça nova é uma FUNÇÃO própria + uma linha no registro
    `BUILDERS`", nunca editar o corpo de função compartilhada.
  - `boss_rework_v2.py`, `final_boss_model.py`: criaturas grandes com nós separados animáveis.
- Convenções: frente em +Z, chão em y = 0, braço direito em +X, escala real em metros.
- Ao trocar um modelo: mantenha nomes de nó, pivôs, escala, origem e orientação que o código
  espera. Nunca apague o gerador antigo antes do novo estar validado.

## 3. Orçamentos e desempenho (Godot)

| Peça | Triângulos |
|---|---|
| Personagem que aparece em grupo | ~2.000 a 2.500 |
| Personagem principal / NPC de destaque | até ~8.000 |
| Criatura/chefe grande | ~10.000 a 15.000 |

- **Malha com esqueleto não é instanciada pelo Godot**: cada material vira uma chamada de desenho
  por personagem. **No máximo 2 materiais por personagem, texturas num atlas** (lição paga: 15
  materiais = 6.922 draw calls com 150 unidades; com atlas, 607).
- Reduza onde a câmera não vê e funda materiais. Cenário repetido: MultiMesh.
- Regerar `.glb` às vezes não reimporta: apague o `.glb.import` e o cache em `.godot/imported/`.
- Confirme que um `.glb` é referenciado por alguma cena antes de gastar tempo no gerador dele.

## 4. Ciclo obrigatório de aceitação

1. Gere o modelo.
2. **Capture em janela, na câmera do jogo** (`get_viewport().get_texture().get_image().save_png(...)`),
   sempre com `--audio-driver Dummy` (teste não faz som) e `timeout` externo.
3. **Ponha lado a lado com uma referência** e OLHE a imagem.
4. Se não estiver no nível, ajuste e repita.
5. `--import` sem `SCRIPT ERROR`.
6. Mande a captura final ao usuário (ele acompanha pelo celular) com resumo curto e honesto,
   incluindo os pontos fracos que você vê.
