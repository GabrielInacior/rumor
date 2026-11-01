# Formato de um caso (JSON)

Cada caso é um arquivo `server/cases/<id>.json`, escrito à mão. O servidor carrega todos ao iniciar.
O cliente NUNCA recebe `solution` nem `reveal` antes do fim da rodada (o servidor remove).

## Ideia de jogo que o formato serve

- Cada equipe tem um **quadro de detetive compartilhado** (cortiça). Qualquer membro fixa cartas
  (pessoas, lugares, fatos, pistas) e liga duas cartas com uma **linha** de um tipo (`link_types`).
- Uma pista pode ser **presa numa linha** como prova (`evidence`).
- A teoria entregue é o quadro **mais o culpado apontado** (`solution.culprit`).
- A equipe anda por 3 a 4 **cenas** (`locations`), toca objetos (`hotspots`) e **interroga** pessoas
  (`talk.tree`). Pistas também chegam com o tempo (`t+`).
- Itens (`items`) ficam na **mochila da equipe** e servem para trocas com personagens.
- O estado das conversas é **compartilhado pela equipe** via flags: se um colega ofendeu alguém,
  a pessoa trata o próximo colega diferente.

## Campos

```jsonc
{
  "id": "rumor_1017",                 // = nome do arquivo (casos solo: solo_*.json)
  "mode": "multi",                    // "solo" (um aluno sozinho, sem professor) | "multi" (equipes)
  "title": "O Rumor das 10h17",
  "tagline": "Ninguém cancelou nada. Mas a escola inteira já chorou.",   // 1 linha, tom noir divertido
  "difficulty": 1,                    // 1 fácil, 2 médio, 3 difícil
  "duration_sec": 600,
  // Cenas do caso (ver "Solo x multi"). A primeira é onde o caso começa.
  // corredor | biblioteca | teatro | sala_aula | cantina | patio | sala_professores | quadra
  // sala_diretor | deposito | laboratorio | sala_musica
  "locations": ["corredor", "sala_aula", "sala_musica"],
  "scene": "corredor",                // legado: sempre igual a locations[0]
  // pessoas presentes fisicamente nas cenas (1 a 3 por cena). Cada uma precisa de talk.tree.
  "scene_people": [{"id": "caio", "scene": "corredor"}, {"id": "duda", "scene": "sala_musica"}],
  "briefing": "Máx. 45 palavras, com gancho forte. Voz de narrador noir.",
  "goal": "1 frase, fica fixa na tela.",

  "link_types": [                     // 2 tipos (máx. 3), rótulos curtíssimos
    {"id": "contou", "label": "contou para", "directed": true},
    {"id": "postou", "label": "postou", "directed": true}
  ],

  "cards": [                          // tudo que pode ir pro quadro, menos pistas
    {"id": "caio", "kind": "pessoa", "name": "Caio", "gender": "m", "role": "presidente do grêmio",
     "look": {"skin": "#8d5524", "hair": "raspado", "hair_color": "#1a1a1a", "top": "#2e7d32", "accessory": "bone"},
     // gender: "f" | "m" (escolhe o modelo 3D; adultos seguem a mesma regra)
     // hair para "f" (sempre comprido): longo | rabo | coque | trancas | ondulado | cacheado_longo
     // hair para "m": curto | raspado | franja | cacheado
     // accessory: nenhum | oculos | bone | fones | brinco | cachecol
     "talk": {
       "greet": [{"text": "Eu? Tô só passando. Juro.", "expr": "nervoso", "anim": "negando"}],  // 1 a 2 falas, sem revelar nada
       "mood": "desconfiado",                                                                      // expressão padrão
       "tree": { ... }                                                                             // ver "Interrogatório"
     }},
    {"id": "biblioteca", "kind": "lugar", "name": "Biblioteca"},
    // lugar cujo id não é um id de cena: "scene" = cena mais parecida (usada na "foto" da carta)
    {"id": "sala_prova", "kind": "lugar", "name": "Sala da recuperação", "scene": "sala_aula"},
    // fato: "icon" obrigatório (modelo 3D low-poly da "foto" no quadro)
    {"id": "boato", "kind": "fato", "name": "Boato: \"a viagem foi cancelada\"", "icon": "mensagem"}
  ],
  // icon: celular | mensagem | onibus | trofeu | livro | carta | chocolate | carregador | baqueta | fita |
  //       computador | pizza | chave | mochila | coroa | camera | papel | microfone | bola | prancheta |
  //       caixa | cartaz | wifi | relogio | sacola

  "items": [                          // objetos de troca, vão para a mochila da equipe. "icon" obrigatório.
    {"id": "carregador", "name": "Carregador de celular", "desc": "Vale ouro numa escola com celular em 2%.", "icon": "carregador"}
  ],

  "clues": [
    {
      "id": "c_bilhete",
      "kind": "bilhete",              // mensagem | depoimento | registro | objeto | post | bilhete
      "title": "Bilhete da Lúcia",    // até 4 palavras
      "time": "09h55",                // opcional
      "who": "lucia",                 // opcional, id de pessoa (autor / quem fala)
      "text": "Máx. 35 palavras. Uma informação clara por pista.",
      "release": "hotspot",           // start | "t+180" | hotspot | interrogatorio
      "deal": "team"                  // team = todos veem | split = vai pra UM aluno
    }
  ],
  // Campos extras por tipo de pista:
  //  mensagem: "app": "chat", "chat": {"group": "nome", "lines": [{"who": "id ou nome solto", "text": "...", "time": "10h17"}]}
  //            o "text" vira resumo de 1 linha
  //  post:     "post": {"user": "@arroba", "who": "id", "caption": "...", "likes": 87, "image": "o que a foto mostra",
  //                     "comments": [{"user": "@x", "text": "..."}]}
  //  depoimento: "dialogue" opcional: [{"text","expr","anim"}] (2 a 4 falas)
  //  release "interrogatorio": a pista só existe quando um nó de talk.tree com "unlock" é alcançado.

  // 1 a 2 hotspots por cena. Cada hotspot dá UMA pista ("clue") OU UM item ("item").
  "hotspots": [
    {"id": "hs_quadro", "scene": "corredor", "object": "quadro_avisos", "label": "Quadro de avisos", "clue": "c_bilhete"},
    {"id": "hs_mochila", "scene": "sala_aula", "object": "mochila", "label": "Mochila perdida", "item": "carregador"}
  ],

  "solution": {
    "culprit": "duda",                              // id da pessoa culpada (responsável principal)
    "culprit_question": "Quem mudou a história?",   // mostrada na hora de apontar; vale como categoria a mais
    "culprit_evidence": ["c_celular", "c_dm_duda"], // pistas que sustentam o culpado (para validação e revelação)
    "categories": [{"id": "cadeia", "label": "Por onde o recado passou"}],   // máx. 3
    "edges": [                                      // 3 a 4 linhas exigidas
      {"from": "caio", "to": "duda", "type": "contou", "category": "cadeia",
       "evidence": ["c_celular", "c_print_gremio"]}  // qualquer UMA delas presa vale
    ],
    "traps": [                                      // 1 a 2 hipóteses erradas plausíveis
      {"from": "rafa", "to": "boato", "type": "postou", "category": "post"}
    ]
  },

  // Guia do professor (o cliente do aluno não recebe). Linguagem simples.
  "teacher_guide": {
    "summary": "A verdade em 3 a 4 frases.",
    "twist": "Onde o plot twist foi plantado: quais pistas o jogador viu e leu errado, e o segundo giro.",
    "solution_steps": ["5 a 8 passos do caminho ótimo, citando pista, lugar e pessoa"],
    "pacing": [{"when": "0 a 5 min", "aha": "o que costuma acontecer", "if_stuck": "pergunta para destravar"}],  // 3 a 6
    "clue_map": [{"clue": "c_id", "where": "como se obtém (cena+objeto, quem dá, t+, troca)", "proves": "o que prova"}],  // TODAS as pistas
    "red_herrings": ["pista falsa e por que é falsa"],
    "faq": [{"q": "dúvida comum", "a": "como ajudar sem entregar"}],  // 4 a 6
    "talking_points": ["pergunta para a revelação (raciocínio, fontes, boatos)"]  // exatamente 3
  },

  // 4 a 6 dicas DESTE caso, da mais sutil para a mais forte, sem entregar o culpado de cara.
  // multi: o professor manda. solo: o jogador pede (uma por vez, na ordem).
  "hints": ["Alguém leu só o começo de uma mensagem. Quem estava com pressa?", "..."],

  "reveal": {
    "timeline": [{"time": "09h55", "text": "..."}],
    "explanation": "2 a 4 frases com a verdade e o 'aha'.",
    "refuted": ["Por que cada suspeito errado não foi."]
  }
}
```

### Âncoras de hotspot por cena

| cena | objetos |
|---|---|
| corredor | quadro_avisos, mural, celular, armario_aberto, lixeira |
| biblioteca | caderno_entrada, pasta_gremio, computador, estante, mesa_estudo |
| teatro | caixa_props, quadro_teatro, trono, arara_figurino, cortina |
| sala_aula | lousa, mesa_professor, carteira_fundo, mochila, janela |
| cantina | balcao, cardapio, bandeja, geladeira, mural_cantina |
| patio | banco_patio, arvore, bicicletario, lixeira_patio, poste |
| sala_professores | escaninho, cafeteira, mural_recados, computador_prof, armario_prof |
| quadra | arquibancada, placar, bolsa_esportiva, vestiario_porta, rede |
| sala_diretor | mesa_diretor, gaveta, quadro_fotos, telefone, cofre |
| deposito | caixa_achados, prateleira, vassoura, caixa_fusiveis, porta_fundos |
| laboratorio | bancada, microscopio, armario_vidros, quadro_tabela, pia |
| sala_musica | piano, bateria, estante_partituras, armario_instrumentos, quadro_horarios |

## Interrogatório (talk.tree v2, estado da equipe)

```jsonc
"tree": {
  "entries": [                                        // a primeira que casa vence
    {"if": ["caio_bravo"], "ifnot": ["caio_carregado"], "node": "fechado"},
    {"if": ["caio_contou"], "node": "reencontro"},
    {"node": "inicio"}                                // a última, sem condição, é o padrão
  ],
  "nodes": {
    "inicio": {
      "lines": [{"text": "Fala rápido, meu celular tá com 2%.", "expr": "desconfiado", "anim": "dando_de_ombros"}],
      "choices": [
        {"text": "Mostrar o bilhete da Profa. Lúcia", "kind": "boa", "next": "conta", "requires": ["c_bilhete"]},
        {"text": "Toma, carrega seu celular aqui", "kind": "boa", "next": "carrega", "requires": ["carregador"]},
        {"text": "Foi você que inventou isso, né?", "kind": "ruim", "next": "bravo"},
        {"text": "Valeu, depois eu volto.", "kind": "neutra", "end": true}
      ]},
    "carrega": {"lines": [...], "sets": ["caio_carregado"], "unlock": "c_print_gremio", "take_item": "carregador",
                "choices": [{"text": "Valeu, Caio.", "kind": "neutra", "end": true}]},
    "bravo":   {"lines": [{"text": "Sem prova? Tchau.", "expr": "bravo", "anim": "negando"}],
                "sets": ["caio_bravo"], "end": true, "lock": 20, "choices": []},
    "fechado": {"lines": [{"text": "{por:caio_bravo} já veio me chamar de mentiroso.", "expr": "bravo", "anim": "negando"}],
                "choices": [...]}
  }
}
```

**Nó:** `lines` (1 a 3 falas, até 22 palavras cada; `expr`: neutro | feliz | surpreso | bravo | desconfiado | triste | nervoso;
`anim`: falando | pensando | nervoso | negando | apontando | dando_de_ombros | rindo). Ao chegar no nó, a equipe ganha:
`sets` (flags), `unlock` (pista com release interrogatorio), `give_item` (item na mochila). `take_item` tira o item da mochila
(o nó só é alcançável se a equipe tem o item). `end: true` + `lock: N` encerra e bloqueia a conversa com essa pessoa por N segundos.

**Escolha:** `text` (até 9 palavras, fala do detetive), `kind` (boa | neutra | ruim), `next` OU `end: true`.
Condições: `requires` (ids de pista ou item que a equipe tem), `if` / `ifnot` (flags). Escolha que não passa nas
condições fica escondida.

**`{por:flag}`** nas falas é trocado pelo codinome do colega que ganhou aquela flag. Só use num nó que seta a flag
ou que é aberto por uma entry com essa flag em `if`.

**Regras de roteiro:**
- 3 a 6 nós por pessoa. Entradas diferentes para a 1ª conversa, o reencontro e depois de flags importantes.
- Todo nó não final tem uma saída livre (escolha sem `requires`/`if`, que não seja ruim).
- Escolha `ruim` leva a um nó final com `sets` (ex.: `bia_ofendida`), `lock` e expressão brava ou nervosa.
  A flag fecha a rota fácil: a pessoa passa a dar menos, ou só fala depois de uma troca ou de uma prova melhor.
- NUNCA bloquear o progresso: toda linha exigida e o culpado precisam de pelo menos uma prova que não dependa
  de interrogatório (start, t+ ou hotspot), e continuam alcançáveis mesmo com todas as flags ruins setadas.
- Pelo menos uma tarefa de troca por caso: a pessoa pede algo, o item está em outra cena, entregar (`take_item`)
  libera info extra ou um atalho.

## Regras de validação (servidor)

- Uma linha exigida conta se o quadro tem linha `from → to` do mesmo `type`
  (tipo não direcionado aceita os dois sentidos).
- Se `evidence` não está vazio, a linha precisa ter presa UMA das pistas da lista;
  senão o feedback da categoria é "a ligação existe, mas falta a prova".
- Uma armadilha presente marca a categoria como "tem uma ligação errada aqui".
- O culpado apontado vale como categoria extra (`culprit_question`).
- Linhas a mais que não são armadilha são ignoradas.
- Teoria correta = todas as linhas exigidas com prova, nenhuma armadilha e o culpado certo.
- Teoria errada: equipe bloqueada por `penalty_sec` (padrão 45 s) para entregar de novo.
- Fim do tempo sem acerto: vence a equipe com mais pontos de dedução na última entrega.
  Pontos = 100 por linha exigida certa com prova, 50 sem prova, −60 por armadilha, +150 pelo culpado certo.

## Solo x multi

| | solo | multi |
|---|---|---|
| locations | 2 a 5 | 5 a 7 |
| pessoas | 3 a 6 | 8 a 10 |
| pistas | 5 a 20 | 18 a 28 |
| `deal: "split"` | proibido (tudo `team`) | obrigatório (pelo menos 2, só em start ou t+) |
| linhas exigidas | 2 a 5 | 5 a 7 |
| trocas (`take_item`) | pelo menos 1 | pelo menos 2, cada item usado por uma pessoa só |
| duration_sec | 600 a 1500 | 1500 a 2400 (o servidor ainda soma 50%) |

Comum aos dois: 2 a 3 link_types, até 3 categorias, 1 a 3 armadilhas, pelo menos 1 pista `t+150..300`,
1 a 2 hotspots por cena, 1 a 3 pessoas por cena.

`unlock` pode apontar para uma pista `t+` (vira **atalho**: a equipe ganha antes do tempo). Nunca para
start ou hotspot.

## Validador

`python tools/validar_casos.py` valida todos os casos (ou os arquivos passados). Além dos ids, âncoras,
tamanhos e regras por modo, ele roda a alcançabilidade duas vezes: do zero, e com **todas as flags ruins
ligadas** (a equipe fez todas as escolhas ruins). Toda linha exigida e o culpado precisam continuar
com prova alcançável no pior caminho.

## Regras de escrita

- Mistério de verdade: transgressão real (furto, fraude, chantagem, vazamento, sabotagem, perfil falso, armação),
  culpado com intenção e motivo forte. Nada de violência gráfica, sexo, drogas ou morte.
- Um plot twist forte e justo por caso, plantado em pistas que o jogador já viu, e de preferência um segundo giro
  (cúmplice, vítima que mentiu, motivo escondido). A pista t+ costuma ser a isca ou a confirmação do twist.
- Público com pouca experiência em jogos: nada complexo, mas o culpado não pode ser óbvio.
  2 suspeitos plausíveis + o verdadeiro, uma pista falsa justa, uma reviravolta que se encaixa, um "aha" deduzível.
- Uma informação clara por pista (limites de quantidade na tabela "Solo x multi"). Pelo menos 1 pista `t+` (150 a 300) que vira o jogo.
- Cada linha exigida aceita 2 ou mais pistas como prova, uma delas team ou hotspot.
- Tudo deduzível só com as pistas, sem conhecimento externo. Nada pesado; tom leve.
- Personagens fictícios. Sem travessão nos textos ao jogador. Português do Brasil.
