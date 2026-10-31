---
name: game-godot-workflow
description: Use antes de mexer em código, cenas, UI ou validação deste jogo em Godot. Como validar sem abrir o editor, captura de tela, regras de economia de tokens, orquestração de agentes e as armadilhas de Godot já pagas no FortressChaos.
---

# Fluxo de trabalho em Godot (herdado do FortressChaos)

## 1. Validar sem abrir o editor

Godot 4.7.1 console:
`C:/Users/gabri/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.1-stable_win64_console.exe`
(também `godot` no PATH; confira se o caminho mudou).

- Compilação: `godot --headless --audio-driver Dummy --path . --import` (sem `SCRIPT ERROR`).
- Runtime: `godot --headless --audio-driver Dummy --path . --quit-after 400 res://<cena principal>.tscn`.
- **Headless não desenha UI nem 3D.** Visual se confere em janela
  (`--audio-driver Dummy --resolution 1920x1080 cena.tscn`), salvando
  `get_viewport().get_texture().get_image().save_png(...)`, e OLHANDO o PNG.
- **Teste nunca toca som**: `--audio-driver Dummy` em TODA execução, inclusive em janela.
- `timeout` externo em sonda em janela; `APPDATA` desviado para o scratchpad em sonda que grava
  save/settings (nunca `--user-data-dir`), senão mexe no save real do usuário.
- Um `--import` por vez; concorrente derruba sondas com "Busy": re-rode antes de chamar de bug.

## 2. Convenções

- Dado balanceável como `@export` na cena, nunca hardcoded no comportamento.
- Comentários em português do Brasil explicando o porquê.
- GDScript: `:=` inferindo de chamada que retorna `Variant` é erro; declare o tipo.
- **Nunca `git commit` sem pedido explícito.**
- Arquivo grande compartilhado: só `Edit` incremental, releia antes, nunca `awk`/`sed`/`Write` inteiro
  (um `awk` em loop já corrompeu um arquivo de 12 mil linhas).
- Texto ao jogador: linguagem de jogo, sem termo de dev, sem travessão "—", em todos os idiomas.
- Interação/UX nova ambígua: confirme o comportamento com o usuário antes de implementar.
- Economia (plano Pro): uma frente por vez, subagente só para trabalho grande, sem bots nem baterias
  longas de testes; o usuário faz os playtests. Poucas capturas, todas olhadas.

## 3. Orquestração (quando valer a pena delegar)

- Investigue você mesmo antes do briefing; o prompt leva fatos verificados, fronteira de arquivos e o
  essencial das skills de arte coladas.
- "Fundação primeiro, depois fanout": uma peça completa e aprovada, depois o resto repetindo a técnica.
- Valide pessoalmente depois de cada entrega; não confie só no relatório do agente.
- Crash por limite de sessão: retome com SendMessage; se não houver transcript, novo agente que
  audita o disco antes de refazer.

## 4. Armadilhas de Godot já pagas

- `TextureRect` com `expand_mode` padrão usa o tamanho da textura como mínimo:
  use `EXPAND_IGNORE_SIZE` (repetiu 4 vezes).
- `StyleBoxTexture` margem 9-patch vira tamanho mínimo do controle: não suba a margem ao aumentar a
  resolução da textura.
- `set_anchors_preset()` em Control oculto/fora da árvore não calcula: use
  `set_anchors_and_offsets_preset()` ou configure antes de esconder.
- Separador/scrollbar do tema nasce com espessura zero sem margem de conteúdo no StyleBox.
- `call_deferred` com referência de nó quebra se o nó for liberado: guarde `get_instance_id()`.
- `as Tipo` sobre nó liberado é erro, não `null`: `is_instance_valid` antes do `as`.
- `_ready()` roda filho antes do pai; `_enter_tree()` pai antes do filho (troca de modelo antes de
  um animador capturar ossos vai em `_enter_tree()`).
- NavMesh: colisão descreve superfície, não área; meça antes de assumir que o carve funciona.
- `flat` é palavra reservada em GDShader.
- Regerar `.glb` pode não reimportar: apague `.import` e `.godot/imported/` correspondente.
- Pixel art: `TEXTURE_FILTER_NEAREST`.
- Python 3 do sistema pode cair no stub da Microsoft Store; PowerShell + C# inline resolve
  manipulação de imagem (confira `python --version` antes).

Referência completa do outro projeto: `C:\Project\game\.claude\skills\fortaleza-context\SKILL.md`
(seções 3, 6 e 7) e `C:\Project\game\docs\` (ex.: `ui_design_system.md`, `audio_qualidade.md`,
`acessibilidade.md`, `release_steam.md`, Android em `.claude\skills\fortaleza-android`).
