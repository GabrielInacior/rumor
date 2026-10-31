# Projeto novo (pasta `detetive`)

Jogo novo do mesmo autor do FortressChaos (`C:\Project\game`). A ideia ainda está sendo definida.
Tudo que foi aprendido lá em arte, Blender e Godot foi trazido para cá:

- `.claude/skills/game-modelagem-3d` (invocar antes de criar ou refazer modelo 3D)
- `.claude/skills/game-arte-2d-ia` (invocar antes de qualquer arte 2D, inclusive pela OpenAI)
- `.claude/skills/game-godot-workflow` (invocar antes de código/cena/validação em Godot)
- `tools/blender/` (kit de primitivas e texturas pixel art, render de ícones)
- `tools/ai_art/` (geração gpt-image-1 e pós-processo de pixel art)
- `docs/referencias_visuais_fortresschaos/` (régua de acabamento aprovada no outro jogo)

Ao delegar a um agente, cole o essencial da skill no briefing.

## Regras de base
- Nenhum asset pronto de terceiro; gerado por código ou por IA é permitido.
- Teste nunca faz som (`--audio-driver Dummy`). Nunca `git commit` sem pedido.
- Texto ao jogador sem travessão "—" e sem termo de dev.
- Confirmar UX ambígua antes de implementar. Economia de tokens: uma frente por vez.
