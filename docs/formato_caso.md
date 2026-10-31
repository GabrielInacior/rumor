# Formato de um caso (JSON)

Cada caso é um arquivo `server/cases/<id>.json`, escrito à mão. O servidor carrega todos ao iniciar.
O cliente NUNCA recebe `solution` nem `reveal` antes do fim da rodada (o servidor remove).

## Ideia de jogo que o formato serve

- Cada equipe tem um **quadro de detetive compartilhado** (cortiça). Qualquer membro fixa cartas
  (pessoas, lugares, fatos, pistas) e liga duas cartas com uma **linha** de um tipo (`link_types`).
- Uma pista pode ser **presa numa linha** como prova (`evidence`).
- A teoria entregue é o próprio quadro. O servidor confere as linhas exigidas em `solution.edges`.
- Cada aluno recebe pistas **só dele** (distribuição `split`), então a equipe precisa conversar.
  Ele decide fixar no quadro (aí a equipe inteira vê).
- Algumas pistas aparecem tocando objetos da **cena 3D** (`hotspots`), outras chegam com o tempo.

## Campos

```jsonc
{
  "id": "rumor_1017",                 // = nome do arquivo
  "title": "O Rumor das 10h17",
  "tagline": "Uma mensagem inocente. Uma escola em pânico.",   // 1 linha, tom noir divertido
  "difficulty": 1,                    // 1 fácil, 2 médio, 3 difícil
  "duration_sec": 600,
  // 3 cenas do caso. A primeira é onde o caso começa. Ids possíveis:
  // corredor | biblioteca | teatro | sala_aula | cantina | patio | sala_professores | quadra
  "locations": ["corredor", "sala_aula", "patio"],
  "scene": "corredor",                // legado: sempre igual a locations[0]
  // pessoas que aparecem fisicamente nas cenas: 1 a 2 por location (máx. 3). Cada uma tem talk.tree.
  "scene_people": [{"id": "caio", "scene": "corredor"}, {"id": "duda", "scene": "patio"}],
  "briefing": "Texto curto (máx. 45 palavras) lido na abertura. Voz de narrador noir.",
  "goal": "Descubra quem contou para quem e onde a história mudou.",   // 1 frase, fica fixa na tela

  "link_types": [                     // SÓ os tipos que este caso usa (2, máx. 3)
    {"id": "contou", "label": "contou para", "directed": true},
    {"id": "criou",  "label": "criou a versão", "directed": true}
  ],

  "cards": [                          // tudo que pode ir pro quadro, menos pistas
    {"id": "lucia", "kind": "pessoa", "name": "Profa. Lúcia", "role": "organiza a viagem",
     "look": {"skin": "#c98d6b", "hair": "coque", "hair_color": "#3a2a20", "top": "#7a5a9e", "accessory": "oculos"},
     // talk: falas ao tocar na pessoa na cena 3D antes do depoimento (1 a 2, sem revelar nada)
     // e a expressão padrão do rosto (mesmos valores de expr do dialogue)
     "talk": {"greet": [{"text": "Eu? Tô só passando. Juro.", "expr": "nervoso", "anim": "negando"}], "mood": "neutro",
       // tree: interrogatório (só para quem está em scene_people). Ver seção "Interrogatório".
       "tree": {"start": "n1", "nodes": {
         "n1": {"lines": [{"text": "Se for sobre a viagem, já falei mil vezes.", "expr": "desconfiado", "anim": "dando_de_ombros"}],
                "choices": [
                  {"text": "Mostrar o bilhete da Lúcia", "kind": "boa", "next": "conta",
                   "requires": "c_bilhete", "unlock": "c_dep_caio"},
                  {"text": "O que você sabe da viagem?", "kind": "neutra", "next": "n2"},
                  {"text": "Foi você que inventou isso!", "kind": "ruim", "next": "bravo"}]},
         "n2": {"lines": [...], "choices": [{"text": "Valeu, depois eu volto.", "kind": "neutra", "end": true}]},
         "conta": {"lines": [...], "choices": [{"text": "Valeu, Caio.", "kind": "neutra", "end": true}]},
         "bravo": {"lines": [{"text": "Sem prova? Tchau.", "expr": "bravo", "anim": "negando"}],
                   "choices": [], "end": true, "lock": 20}}}}},
    {"id": "biblioteca", "kind": "lugar", "name": "Biblioteca"},
    {"id": "versao_cancelada", "kind": "fato", "name": "\"A viagem foi cancelada\""}
  ],

  "clues": [
    {
      "id": "c_msg_1017",
      "kind": "mensagem",             // mensagem | depoimento | registro | objeto | post | bilhete
      "title": "Grupo do grêmio, 10h17",
      "time": "10h17",                // opcional, mostrado na carta
      "from": "caio",                 // opcional, id de carta pessoa (autor)
      "text": "Texto curto (máx. 35 palavras). Mensagens podem usar \\n entre falas.",
      "release": "start",             // start | "t+240" (segundos desde o início) | "hotspot" | "interrogatorio"
                                      // interrogatorio = liberada por uma escolha com "unlock" numa talk.tree
      "deal": "split"                 // split = vai pra UM aluno da equipe | team = todos veem
    }
  ],

  // Campos opcionais por tipo de pista (a UI simula redes sociais):
  //  "who": "id_pessoa"   autor/quem fala (depoimento, bilhete, registro). Substitui "from".
  //  kind "mensagem" -> "app": "chat" e
  //    "chat": {"group": "nome do grupo ou da pessoa",
  //             "lines": [{"who": "id_pessoa ou nome solto", "text": "...", "time": "10h17"}]}
  //    O "text" da pista vira um resumo de 1 linha, usado em listas.
  //  kind "post" ->
  //    "post": {"user": "@arroba", "who": "id_pessoa (opcional)", "caption": "...", "likes": 87,
  //             "image": "descrição curta do que a foto mostra",
  //             "comments": [{"user": "@x", "text": "..."}]}
  //    O "text" da pista também vira resumo de 1 linha.
  //  "title" curto (até 4 palavras). "time" opcional.
  //  kind "depoimento" -> "dialogue": [{"text": "...", "expr": "...", "anim": "..."}]
  //    2 a 4 falas (até 22 palavras cada) para a conversa 3D, com o MESMO conteúdo do "text".
  //    O "text" continua como resumo.
  //    expr: neutro | feliz | surpreso | bravo | desconfiado | triste | nervoso
  //    anim: falando | pensando | nervoso | negando | apontando | dando_de_ombros | rindo

  // objetos tocáveis nas cenas que liberam pista para a equipe. 1 a 2 por location (3 a 5 no caso).
  // "scene" = uma das locations. "object" = uma âncora daquela cena:
  //  corredor: quadro_avisos, mural, celular, armario_aberto, lixeira
  //  biblioteca: caderno_entrada, pasta_gremio, computador, estante, mesa_estudo
  //  teatro: caixa_props, quadro_teatro, trono, arara_figurino, cortina
  //  sala_aula: lousa, mesa_professor, carteira_fundo, mochila, janela
  //  cantina: balcao, cardapio, bandeja, geladeira, mural_cantina
  //  patio: banco_patio, arvore, bicicletario, lixeira_patio, poste
  //  sala_professores: escaninho, cafeteira, mural_recados, computador_prof, armario_prof
  //  quadra: arquibancada, placar, bolsa_esportiva, vestiario_porta, rede
  "hotspots": [
    {"id": "hs_quadro", "scene": "corredor", "object": "quadro_avisos", "label": "Quadro de avisos", "clue": "c_bilhete"}
  ],

  "solution": {
    "categories": [                   // perguntas do caso, cada uma vira um selo de feedback
      {"id": "origem", "label": "De onde veio a informação"},
      {"id": "cadeia", "label": "Como ela se espalhou"},
      {"id": "distorcao", "label": "Onde a história mudou"}
    ],
    "edges": [                        // linhas EXIGIDAS (3 a 4 por caso, máx. 3 categorias)
      {"from": "lucia", "to": "caio", "type": "contou", "category": "origem",
       "evidence": ["c_dep_caio", "c_bilhete_lucia"]}   // [] = não exige prova presa
    ],
    "traps": [                        // linhas de hipóteses erradas plausíveis
      {"from": "rafa", "to": "versao_cancelada", "type": "criou", "category": "distorcao"}
    ]
  },

  "reveal": {
    "timeline": [{"time": "09h50", "text": "A Profa. Lúcia avisa o Caio no corredor."}],
    "explanation": "2 a 4 frases explicando a verdade e por que a pista X muda tudo.",
    "refuted": ["Rafa não começou nada: o meme dele é das 10h40, depois da mensagem da Bia."]
  }
}
```

## Interrogatório (talk.tree)

- Árvore de 2 a 3 níveis. Cada nó tem `lines` (falas com expr/anim, até 22 palavras) e `choices` (2 a 3).
- Escolha: `text` (fala do detetive, até 9 palavras), `kind` (`boa` | `neutra` | `ruim`), e então
  `next` (id do próximo nó) OU `end: true` (encerra a conversa sem punição).
  - `requires`: id de pista. A escolha só aparece se a equipe já tem essa pista (ex.: "Mostrar o print").
  - `unlock`: id de pista com `release: "interrogatorio"`. Ao escolher, a pista vai para a equipe inteira
    e a fala do nó de destino conta o conteúdo dela.
- Escolha `ruim` (acusar sem prova, ser grosso) leva a um nó final: `"choices": [], "end": true, "lock": 20`.
  A pessoa se fecha (expr bravo ou nervoso) e fica `lock` segundos sem conversa. Depois a conversa recomeça
  do `start`, então a escolha boa continua disponível. Nenhum caminho trava a equipe para sempre.
- Laço típico: achar pista na cena → mostrar para a pessoa (`requires`) → ela conta (`unlock`) → nova pista.
- Toda pista com `release: "interrogatorio"` precisa de pelo menos um `unlock` alcançável, e toda linha
  exigida precisa de pelo menos uma prova que não dependa de interrogatório (start team, t+ ou hotspot).

## Regras de validação (servidor)

- Uma linha exigida conta se o quadro tem linha `from → to` do mesmo `type`
  (tipo não direcionado aceita os dois sentidos).
- Se `evidence` não está vazio, a linha precisa ter presa UMA das pistas da lista;
  senão o feedback da categoria é "a ligação existe, mas falta a prova".
- Uma armadilha presente marca a categoria como "tem uma ligação errada aqui".
- Linhas a mais que não são armadilha são ignoradas.
- Teoria correta = todas as linhas exigidas com prova e nenhuma armadilha.
- Teoria errada: equipe bloqueada por `penalty_sec` (padrão 45 s) para entregar de novo.
- Fim do tempo sem acerto: vence a equipe com mais pontos de dedução na última entrega.
  Pontos = 100 por linha exigida certa com prova, 50 sem prova, −60 por armadilha.

## Regras de escrita

- Público com pouca experiência em jogos: casos simples. 3 a 4 linhas exigidas (máx. 3 categorias),
  2 tipos de linha (máx. 3), 4 a 5 pessoas, até 2 lugares e 2 fatos, 7 a 9 pistas com UMA informação cada,
  1 ou 2 armadilhas. Briefing até 45 palavras, pista até 35.
- Cada linha exigida aceita 2 pistas como prova sempre que possível, uma delas `team` ou hotspot,
  para nenhuma equipe travar se um aluno faltar.
- Pistas curtas, legíveis no celular. Pelo menos 2 hipóteses plausíveis no começo.
- Pelo menos uma pista que chega depois (`t+...`) e muda a leitura.
- Tudo deduzível só com as pistas, sem conhecimento externo. Nada pesado; tom leve.
- Personagens fictícios. Sem travessão "—" nos textos ao jogador. Português do Brasil.
