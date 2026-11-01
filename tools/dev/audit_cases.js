'use strict';
// Auditoria de TODOS os casos: (1) checagem estática dos roteiros (árvores, flags, itens, elenco),
// (2) partida simulada dentro do servidor real com 3 jogadores (explora tudo, esgota conversas,
// monta o quadro certo, apresenta), também pela "rota ruim", e (3) ações simultâneas da equipe.
// Uso: node tools/dev/audit_cases.js [id_do_caso]
const fs = require('fs');
const path = require('path');
const { Room } = require('../../server/src/room');

const CASES_DIR = path.join(__dirname, '../../server/cases');
const only = process.argv[2];
const cases = new Map();
for (const f of fs.readdirSync(CASES_DIR).filter((x) => x.endsWith('.json'))) {
  const c = JSON.parse(fs.readFileSync(path.join(CASES_DIR, f), 'utf8'));
  cases.set(c.id, c);
}

const ANCHORS = {
  corredor: ['quadro_avisos', 'mural', 'celular', 'armario_aberto', 'lixeira'],
  biblioteca: ['caderno_entrada', 'pasta_gremio', 'computador', 'estante', 'mesa_estudo'],
  teatro: ['caixa_props', 'quadro_teatro', 'trono', 'arara_figurino', 'cortina'],
  sala_aula: ['lousa', 'mesa_professor', 'carteira_fundo', 'mochila', 'janela'],
  cantina: ['balcao', 'cardapio', 'bandeja', 'geladeira', 'mural_cantina'],
  patio: ['banco_patio', 'arvore', 'bicicletario', 'lixeira_patio', 'poste'],
  sala_professores: ['escaninho', 'cafeteira', 'mural_recados', 'computador_prof', 'armario_prof'],
  quadra: ['arquibancada', 'placar', 'bolsa_esportiva', 'vestiario_porta', 'rede'],
  sala_diretor: ['mesa_diretor', 'gaveta', 'quadro_fotos', 'telefone', 'cofre'],
  deposito: ['caixa_achados', 'prateleira', 'vassoura', 'caixa_fusiveis', 'porta_fundos'],
  laboratorio: ['bancada', 'microscopio', 'armario_vidros', 'quadro_tabela', 'pia'],
  sala_musica: ['piano', 'bateria', 'estante_partituras', 'armario_instrumentos', 'quadro_horarios'],
};

// ------------------------------------------------------------------ 1. estática
function staticAudit(c) {
  const errs = [];
  const warn = [];
  const clueIds = new Set(c.clues.map((x) => x.id));
  const itemIds = new Set((c.items || []).map((x) => x.id));
  const people = c.cards.filter((x) => x.kind === 'pessoa');
  const cardIds = new Set(c.cards.map((x) => x.id));
  const flagsSet = new Set();
  for (const p of people) for (const n of Object.values(p.talk?.tree?.nodes || {})) for (const f of n.sets || []) flagsSet.add(f);
  for (const h of c.hotspots || []) {
    if (!(c.locations || []).includes(h.scene)) errs.push(`hotspot ${h.id}: cena ${h.scene} fora de locations`);
    if (!(ANCHORS[h.scene] || []).includes(h.object)) errs.push(`hotspot ${h.id}: âncora ${h.object} não existe em ${h.scene}`);
    if (h.clue && !clueIds.has(h.clue)) errs.push(`hotspot ${h.id}: pista ${h.clue} não existe`);
    if (h.item && !itemIds.has(h.item)) errs.push(`hotspot ${h.id}: item ${h.item} não existe`);
    if (h.item) flagsSet.add('hs:' + h.id);
  }
  for (const sp of c.scene_people || []) {
    for (const f of [...(sp.if || []), ...(sp.ifnot || [])]) if (!flagsSet.has(f)) errs.push(`scene_people ${sp.id}: flag ${f} nunca é criada`);
  }
  for (const p of people) {
    const tree = p.talk?.tree;
    if (!tree) { warn.push(`${p.id}: sem árvore de conversa`); continue; }
    const nodes = tree.nodes || {};
    const starts = [tree.start, ...(tree.entries || []).map((e) => e.node)].filter(Boolean);
    for (const s of starts) if (!nodes[s]) errs.push(`${p.id}: entrada aponta para nó inexistente ${s}`);
    for (const e of tree.entries || []) for (const f of [...(e.if || []), ...(e.ifnot || [])]) if (!flagsSet.has(f)) errs.push(`${p.id}: entrada usa flag ${f} nunca criada`);
    const reach = new Set();
    const stack = [...starts];
    while (stack.length) {
      const id = stack.pop();
      if (reach.has(id) || !nodes[id]) continue;
      reach.add(id);
      for (const ch of nodes[id].choices || []) stack.push(ch.next);
    }
    for (const [nid, n] of Object.entries(nodes)) {
      if (!reach.has(nid)) warn.push(`${p.id}: nó ${nid} nunca é alcançado`);
      const cast = [p.id, ...(n.cast || tree.cast || [])];
      for (const l of n.lines || []) {
        if (l.who && !cast.includes(l.who)) errs.push(`${p.id}.${nid}: fala de ${l.who}, que não está no elenco`);
        for (const m of String(l.text || '').matchAll(/\{por:([^}]+)\}/g)) if (!flagsSet.has(m[1])) errs.push(`${p.id}.${nid}: {por:${m[1]}} usa flag nunca criada`);
        if (String(l.text || '').includes('—')) errs.push(`${p.id}.${nid}: travessão na fala`);
      }
      for (const cid of n.cast || []) if (!cardIds.has(cid)) errs.push(`${p.id}.${nid}: elenco com ${cid} inexistente`);
      if (n.unlock && !clueIds.has(n.unlock)) errs.push(`${p.id}.${nid}: unlock ${n.unlock} inexistente`);
      if (n.give_item && !itemIds.has(n.give_item)) errs.push(`${p.id}.${nid}: give_item ${n.give_item} inexistente`);
      if (n.take_item && !itemIds.has(n.take_item)) errs.push(`${p.id}.${nid}: take_item ${n.take_item} inexistente`);
      for (const ch of n.choices || []) {
        // escolha sem "next" encerra a conversa (despedida): é válido
        if (ch.next !== undefined && ch.next !== '' && !nodes[ch.next]) errs.push(`${p.id}.${nid}: escolha "${ch.text}" vai para nó inexistente ${ch.next}`);
        const req = Array.isArray(ch.requires) ? ch.requires : (ch.requires ? [ch.requires] : []);
        for (const r of req) if (!clueIds.has(r) && !itemIds.has(r)) errs.push(`${p.id}.${nid}: escolha exige ${r}, que não existe`);
        for (const f of [...(ch.if || []), ...(ch.ifnot || [])]) if (!flagsSet.has(f)) errs.push(`${p.id}.${nid}: escolha usa flag ${f} nunca criada`);
        // entregar item só se a escolha exige o item (senão o diálogo "pega" algo que a equipe não tem)
        const tgt = nodes[ch.next];
        if (tgt && tgt.take_item && !req.includes(tgt.take_item)) warn.push(`${p.id}.${nid}: escolha leva a take_item ${tgt.take_item} sem exigir o item`);
      }
      const hasChoices = (n.choices || []).length > 0;
      if (!hasChoices && !n.end) warn.push(`${p.id}.${nid}: nó sem escolhas e sem end (a conversa termina aí)`);
    }
  }
  return { errs, warn };
}

// ------------------------------------------------------------------ 2. partida simulada
function fakeSock(name) { return { name, readyState: 1, inbox: [], send() {} }; }

function makeRoom(c) {
  const m = new Map([[c.id, c]]);
  const sent = [];
  const room = new Room('9999', m, (sock, obj) => { if (sock && sock.inbox) sock.inbox.push(obj); sent.push(obj); });
  room.settings.caseId = c.id;
  room.settings.teamCount = 1;
  room.settings.penaltySec = 0;
  room.makeTeams();
  const socks = ['Corvo', 'Lince', 'Coruja'].map((n) => { const s = fakeSock(n); room.join(s, n); return s; });
  for (const s of socks) room.playerCmd(s, { t: 'pick_team', team: 't1' });
  room.startRound();
  room.beginPlaying();
  return { room, socks, team: room.teams[0] };
}

function teamKnows(room, team) {
  const ids = room.visibleClues(team, null);
  for (const pid of team.players) { const p = room.players.get(pid); if (p) for (const x of p.clues) ids.add(x); }
  return ids;
}

function exploreAll(c, room, socks, team, preferBad) {
  // hotspots
  for (const h of c.hotspots || []) room.playerCmd(socks[0], { t: 'hotspot', id: h.id });
  // pistas por tempo: avança o relógio
  room.startedAt = Date.now() - 10 * 3600 * 1000;
  room.tick(Date.now());
  // conversas: ponto fixo, percorrendo nós alcançáveis com as escolhas permitidas
  const people = c.cards.filter((x) => x.talk?.tree);
  const visitedEdges = new Set();
  for (let round = 0; round < 12; round++) {
    let changed = false;
    for (const p of people) {
      const tree = p.talk.tree;
      const nodes = tree.nodes || {};
      const ok = (d) => {
        for (const f of d.if || []) if (!team.flags[f]) return false;
        for (const f of d.ifnot || []) if (team.flags[f]) return false;
        const req = Array.isArray(d.requires) ? d.requires : (d.requires ? [d.requires] : []);
        const known = teamKnows(room, team);
        for (const r of req) if (!known.has(r) && !team.items.has(r)) return false;
        return true;
      };
      let start = tree.start;
      for (const e of tree.entries || []) if (ok(e)) { start = e.node; break; }
      const stack = [start];
      const seen = new Set();
      while (stack.length) {
        const nid = stack.pop();
        if (!nid || seen.has(nid) || !nodes[nid]) continue;
        seen.add(nid);
        const before = JSON.stringify([Object.keys(team.flags).length, team.items.size, teamKnows(room, team).size]);
        room.playerCmd(socks[round % 3], { t: 'talk_node', person: p.id, node: nid });
        if (JSON.stringify([Object.keys(team.flags).length, team.items.size, teamKnows(room, team).size]) !== before) changed = true;
        const chs = (nodes[nid].choices || []).filter(ok);
        const order = preferBad ? [...chs].sort((x, y) => (y.kind === 'ruim') - (x.kind === 'ruim')) : chs;
        for (const ch of order) {
          const k = p.id + nid + ch.next;
          if (!visitedEdges.has(k) || true) { visitedEdges.add(k); stack.push(ch.next); }
          if (preferBad && ch.kind === 'ruim') break; // na rota ruim, a primeira escolha é a ruim
        }
      }
    }
    if (!changed) break;
  }
}

function solveBoard(c, room, socks, team) {
  const sol = c.solution;
  const known = teamKnows(room, team);
  const problems = [];
  const ids = new Set();
  for (const e of sol.edges) { ids.add(e.from); ids.add(e.to); }
  let i = 0;
  for (const id of ids) room.playerCmd(socks[i++ % 3], { t: 'board', op: { k: 'pin', ref: 'p:' + id, x: 0.3, y: 0.3 } });
  for (const e of sol.edges) {
    room.playerCmd(socks[i++ % 3], { t: 'board', op: { k: 'link', a: e.from, b: e.to, type: e.type } });
    const l = team.board.links.find((x) => x.a === e.from && x.b === e.to && x.type === e.type);
    if (!l) { problems.push(`não conseguiu criar o fio ${e.from}->${e.to}`); continue; }
    const proof = (e.evidence || []).find((x) => known.has(x));
    if ((e.evidence || []).length && !proof) { problems.push(`nenhuma prova de ${e.from}->${e.to} foi obtida (${e.evidence.join(', ')})`); continue; }
    if (proof) {
      // a prova precisa estar visível para quem prende: o dono da pista split fixa antes
      room.playerCmd(socks[0], { t: 'board', op: { k: 'pin', ref: 'c:' + proof, x: 0.5, y: 0.9 } });
      for (const s of socks) room.playerCmd(s, { t: 'board', op: { k: 'attach', id: l.id, clue: proof } });
      if (team.board.links.find((x) => x.id === l.id).evidence !== proof) problems.push(`não conseguiu prender a prova ${proof}`);
    }
  }
  room.playerCmd(socks[1], { t: 'submit', culprit: sol.culprit });
  const r = team.lastResult;
  if (!r || !r.correct) problems.push('teoria certa NÃO foi aceita: ' + JSON.stringify(r && r.categories));
  return problems;
}

// ------------------------------------------------------------------ 3. ações simultâneas
function concurrency(c) {
  const out = [];
  const { room, socks, team } = makeRoom(c);
  const ppl = c.cards.filter((x) => x.kind === 'pessoa').map((x) => x.id);
  // dois fixam a mesma carta ao mesmo tempo: só uma carta
  for (const s of socks) room.playerCmd(s, { t: 'board', op: { k: 'pin', ref: 'p:' + ppl[0], x: 0.2, y: 0.2 } });
  if (team.board.cards.filter((x) => x.ref === 'p:' + ppl[0]).length !== 1) out.push('carta duplicada ao fixar ao mesmo tempo');
  room.playerCmd(socks[0], { t: 'board', op: { k: 'pin', ref: 'p:' + ppl[1], x: 0.6, y: 0.2 } });
  const lt = c.link_types[0].id;
  for (const s of socks) room.playerCmd(s, { t: 'board', op: { k: 'link', a: ppl[0], b: ppl[1], type: lt } });
  if (team.board.links.length !== 1) out.push(`fio duplicado ao ligar ao mesmo tempo (${team.board.links.length})`);
  // um tira a carta enquanto outro prende prova no fio dela: sem fio órfão
  const lid = team.board.links[0] && team.board.links[0].id;
  room.playerCmd(socks[0], { t: 'board', op: { k: 'unpin', ref: 'p:' + ppl[0] } });
  room.playerCmd(socks[1], { t: 'board', op: { k: 'attach', id: lid, clue: c.clues[0].id } });
  if (team.board.links.some((l) => l.a === ppl[0] || l.b === ppl[0])) out.push('fio ficou órfão depois de tirar a carta');
  // movimentar carta inexistente / fio inexistente não quebra
  room.playerCmd(socks[2], { t: 'board', op: { k: 'move', ref: 'p:nao_existe', x: 0.1, y: 0.1 } });
  room.playerCmd(socks[2], { t: 'board', op: { k: 'retype', id: 'l999', type: lt } });
  // apresentar duas vezes no mesmo instante: conta 1 (com bloqueio)
  room.settings.penaltySec = 30;
  room.playerCmd(socks[0], { t: 'submit', culprit: ppl[0] });
  room.playerCmd(socks[1], { t: 'submit', culprit: ppl[0] });
  if (team.submissions !== 1) out.push(`duas teorias contadas no mesmo instante (${team.submissions})`);
  // mesma prova em dois fios: fica só no último
  room.playerCmd(socks[0], { t: 'board', op: { k: 'pin', ref: 'p:' + ppl[0], x: 0.2, y: 0.2 } });
  room.playerCmd(socks[0], { t: 'board', op: { k: 'pin', ref: 'p:' + ppl[2], x: 0.2, y: 0.7 } });
  room.playerCmd(socks[0], { t: 'board', op: { k: 'link', a: ppl[0], b: ppl[1], type: lt } });
  room.playerCmd(socks[0], { t: 'board', op: { k: 'link', a: ppl[0], b: ppl[2], type: lt } });
  const team_clue = [...teamKnows(room, team)][0];
  if (team_clue && team.board.links.length >= 2) {
    room.playerCmd(socks[0], { t: 'board', op: { k: 'attach', id: team.board.links[0].id, clue: team_clue } });
    room.playerCmd(socks[1], { t: 'board', op: { k: 'attach', id: team.board.links[1].id, clue: team_clue } });
    // a mesma pista pode provar dois fios (há casos que precisam disso): os dois devem ficar com ela
    if (team.board.links.filter((l) => l.evidence === team_clue).length !== 2) out.push('mesma prova não ficou nos dois fios');
  }
  // conversa: dois alunos no mesmo nó com unlock ao mesmo tempo: a pista entra uma vez só
  const p = c.cards.find((x) => x.talk?.tree && Object.values(x.talk.tree.nodes || {}).some((n) => n.unlock));
  if (p) {
    const [nid] = Object.entries(p.talk.tree.nodes).find(([, n]) => n.unlock);
    const before = team.found.size;
    for (const s of socks) room.playerCmd(s, { t: 'talk_node', person: p.id, node: nid });
    if (team.found.size - before > 1) out.push('pista de conversa liberada mais de uma vez');
    const feedCount = room.feed.filter((f) => f.kind === 'conversa' && f.text.includes('contar')).length;
    if (feedCount > 1) out.push('registro do professor duplicou a confissão');
  }
  return out;
}

// ------------------------------------------------------------------ execução
let totalErr = 0;
for (const c of cases.values()) {
  if (only && c.id !== only) continue;
  const st = staticAudit(c);
  const good = makeRoom(c);
  exploreAll(c, good.room, good.socks, good.team, false);
  const solveProblems = solveBoard(c, good.room, good.socks, good.team);
  const bad = makeRoom(c);
  exploreAll(c, bad.room, bad.socks, bad.team, true);
  const badProblems = solveBoard(c, bad.room, bad.socks, bad.team).map((x) => 'rota ruim: ' + x);
  const conc = concurrency(c);
  const errs = [...st.errs, ...solveProblems, ...badProblems, ...conc];
  totalErr += errs.length;
  console.log(`\n=== ${c.id} (${c.mode}, nível ${c.difficulty}) : ${errs.length ? errs.length + ' PROBLEMA(S)' : 'OK'}`);
  for (const e of errs) console.log('  ERRO  ' + e);
  for (const w of st.warn.slice(0, 12)) console.log('  aviso ' + w);
  if (st.warn.length > 12) console.log(`  ... +${st.warn.length - 12} avisos`);
}
console.log(`\nTotal de problemas: ${totalErr}`);
process.exit(totalErr ? 1 : 0);
