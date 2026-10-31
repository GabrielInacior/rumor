# RUMOR · Nada começa como parece

Jogo web multiplayer de detetive para a sala de aula. Equipes de alunos investigam o mesmo mistério
leve, cada um no próprio celular: exploram cenas 3D da escola, interrogam personagens (escolhendo o
que perguntar e qual pista mostrar) e montam juntos um **quadro de detetive** com fios e provas.
A teoria entregue é o próprio quadro; o servidor confere. O professor projeta a sala e o placar.

Casos escritos à mão (sem IA gerando história): `server/cases/*.json`, formato em `docs/formato_caso.md`.

## Jogar agora (hospedado)

**https://rumor.inaciodev.online** (Render, plano gratuito; cada push na branch `main` publica sozinho).
O plano gratuito dorme depois de 15 min sem uso: abra o link uns 2 minutos antes da aula para acordar.
Para publicar uma versão nova do jogo: `bash tools/build_web.sh`, commit e push.

## Usar numa aula sem internet (rede da escola)

1. No computador do professor (precisa de Node.js 18+):
   ```bash
   cd server
   npm install
   npm start
   ```
   O terminal mostra o endereço da rede, por exemplo `http://192.168.0.12:8080`.
2. Abra esse endereço no computador ligado ao projetor e toque em **Sou professor: criar uma sala**.
3. Os alunos (mesma rede Wi-Fi) abrem o endereço no celular, tocam em **Entrar na sala**, digitam o
   código de 4 dígitos do telão e escolhem um codinome.
4. Escolha o caso e o número de equipes, sorteie ou deixe os alunos escolherem, e toque em
   **Começar o caso**. Durante a rodada você pode liberar a próxima pista, dar mais um minuto, ver o
   quadro de qualquer equipe ao vivo e encerrar. A revelação mostra placar, verdade e quadro oficial.

Celular que apaga a tela volta para a mesma equipe sozinho ao reabrir a página.

## Desenvolvimento

- `game/`: cliente Godot 4.7 (renderizador Compatibility, exporta para web).
- `server/`: Node + ws. `npm test` roda a rodada completa por WebSocket.
- `bash tools/build_web.sh`: exporta o jogo para `server/public/` e comprime.
- `tools/blender/`: personagens, retratos e cenas de arte (Blender headless).
- `tools/audio/gen_sfx.py`: efeitos sonoros sintetizados.
- `tools/dev/drive.js`: robô que faz papel de professor e colegas para testar telas.
- Trilha: `game/assets/audio/musica/`.
