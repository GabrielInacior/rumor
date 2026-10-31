---
name: game-arte-2d-ia
description: OBRIGATÓRIA antes de gerar ou editar arte 2D deste jogo (ícones, retratos, ilustrações, molduras de UI, fundos, arte de loja), inclusive pela OpenAI. Pipeline de geração por IA, pós-processo de pixel art real, custos, lições pagas no FortressChaos e o que nunca fazer.
---

# Arte 2D por IA: padrão obrigatório

Herdado do FortressChaos (`C:\Project\game`), onde uma migração inteira de arte 2D foi feita por
vários agentes. Tudo aqui foi testado de verdade. Se delegar, cole o essencial no briefing.

## 1. Pixel art de verdade (se o estilo do jogo for pixel art)

No FortressChaos o pixel art era obrigatório. **Confirme com o usuário o estilo deste jogo** antes
do primeiro lote. Sendo pixel art, toda arte gerada passa por pós-processo:
- reduzir para uma **grade real** com fator inteiro, por **amostragem de ponto / moda** (nunca média:
  média borra a aresta dura e o dither), e reampliar com **vizinho mais próximo**;
- **paleta limitada** (ícone ~9 a 12 cores; retrato poucas mil no máximo);
- **contorno escuro** igual ao dos vizinhos; contorno seletivo só nas bordas da silhueta;
- **fundo transparente limpo**: gerar sobre **magenta chapado** e recortar
  (`background: "transparent"` da API não é confiável).
- No Godot, `TEXTURE_FILTER_NEAREST` em todo `TextureRect`/material que mostra pixel art.

Teste de "pixel art falso": pixel art real tem erro ~0 ao reduzir pela grade certa, poucas cores e
quase nenhuma transição suave entre vizinhos.

## 2. Pipeline e ferramentas (`tools/ai_art/`)

- `gen_image.ps1 -PromptFile p.txt -Out C:\abs\saida.png -KeyFile C:/Users/gabri/.openai_key [-Quality low] [-Size 1024x1024]`
  (gpt-image-1, repete em 429/5xx). **Chave nunca impressa nem commitada.** Use **caminho
  absoluto** no `-Out` (relativo já fez perder imagem paga).
- `sprite_icon.ps1 -In bruto.png -Out icone.png -Size 32`: chave do magenta, caixa justa, re-grid por
  moda, alfa binário.
- `palette_limit.py entrada.png saida.png 10`: reduz paleta (MAXCOVERAGE preserva acento pequeno).
- `imgtool.ps1`: utilidades de imagem em PowerShell/C# inline.
- Mais 100 scripts de pós-processo específicos (molduras 9-patch, parallax, banners Steam,
  cápsulas) para consulta em `C:\Project\game\tools\ai_art\`.

Custos (2026, confira): `low` ~US$0,01, `medium` ~0,034, `high` ~0,133 por 1024². Limite ~5
imagens/min por organização (compartilhado entre agentes): sequencial com espera no 429.
**Uma chamada de teste primeiro** (a conta pode estar sem crédito; se faltar, pare e avise).
Piloto pequeno antes de lote; ledger de custo; brutos em `tools/ai_art/raw_<tema>/` (com
`.gdignore`) e prompts em `tools/ai_art/prompts_<tema>/` para recompor sem pagar de novo.
Resultado vai para pasta de revisão; trocar em `assets/` é decisão do usuário.

## 3. Lições de prompt

- O bloco "pixel art, not a smooth painting" sozinho não basta. Funciona: prefixo técnico agressivo
  (`PIXEL ART SPRITE, drawn on a 200x200 pixel canvas, nearest-neighbour, NO anti-aliasing, NO smooth
  gradients, aliased stair-stepped outlines`) + bloco de estilo no FIM. ~30% ainda vem liso: reroll
  ou pós-processo, não reescrever o prompt 10 vezes.
- **Peça pequena (16-32 px)**: peça já na resolução final ("a sprite of exactly 32x32 pixels, each
  logical pixel a flat solid square block"); reduzir ilustração grande vira mingau.
- **Peça grande (fundo, banner, logo)**: grade FINA ("fine-grained detailed pixel art, high pixel
  density, NOT chunky blocks"; referências que funcionam: Owlboy, Dead Cells, Blasphemous).
- **Parallax**: mesma fonte de luz e gradiente atmosférico descritos em cada camada; preencher massa
  sólida sob a silhueta (interpolação por coluna, senão vira "cerca").
- **Moldura 9-patch**: pedir borda só nos ~10% externos e centro chapado; detectar a borda por código
  e normalizar entre variantes. No Godot, margem 9-patch vira piso de tamanho mínimo: não aumente.
- **Ícone falha por contraste**: puxe o objeto pro claro em painel escuro e varie a cor dominante entre
  ícones vizinhos.
- **Ilustração de carta/emblema**: UM sujeito em close a 60-70% do quadro, fundo vinheta simples com
  uma cor dominante + acento, legível em meio segundo. Nada de cena lotada.
- Vários agentes no mesmo lote: mesmo prompt-base copiado literalmente e mesma imagem de referência
  lida com Read, senão o estilo muda de agente pra agente.
- Logo: sempre o arquivo original; **nunca letras geradas pela IA**.
- Ícone que substitui um procedural: mantenha o procedural como fallback se o PNG faltar.

## 4. Coerência e entrega

Compare **lado a lado, no tamanho real em que aparece no jogo**, antes de aceitar. Texto ao jogador
em qualquer arte: sem travessão "—" e sem termo de dev. Folha de contato no tamanho real, olhada
por você, enviada ao usuário com custo e pontos fracos.
