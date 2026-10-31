'use strict';
// Robô de teste: faz o papel do professor e de colegas de equipe por WebSocket, para que um
// cliente Godot real (capturando tela) veja uma sala viva com quadro preenchido.
// Uso: node tools/dev/drive.js <caseId> <arquivoCodigo>   (servidor já rodando em :8080)
const fs = require('fs');
const WebSocket = require(require.resolve('ws', { paths: [require('path').join(__dirname, '../../server')] }));

const caseId = process.argv[2] || 'rumor_1017';
const codeFile = process.argv[3] || 'code.txt';
const URL = process.env.RUMOR_WS || 'ws://127.0.0.1:8080/ws';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function client() {
  const ws = new WebSocket(URL);
  const c = { ws, state: null, joined: null, code: null };
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    if (m.t === 'state') c.state = m;
    if (m.t === 'joined') c.joined = m;
    if (m.t === 'hosted') c.code = m.code;
  });
  c.send = (o) => ws.send(JSON.stringify(o));
  c.open = () => new Promise((r) => ws.on('open', r));
  return c;
}

(async () => {
  const cases = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../server/cases', caseId + '.json'), 'utf8'));
  const host = client(); await host.open();
  host.send({ t: 'host_create' });
  while (!host.code) await sleep(50);
  host.send({ t: 'host_settings', caseId, teamCount: 2 });
  fs.writeFileSync(codeFile, host.code);
  console.log('CODE', host.code);
  const mates = [];
  for (const n of ['Coruja', 'Lince']) {
    const m = client(); await m.open();
    m.send({ t: 'join', code: host.code, name: n });
    mates.push(m);
  }
  const other = client(); await other.open();
  other.send({ t: 'join', code: host.code, name: 'Raposa' });
  await sleep(500);
  for (const m of mates) m.send({ t: 'pick_team', team: 't1' });
  other.send({ t: 'pick_team', team: 't2' });
  // espera o aluno Godot entrar (ele cai na equipe menor; força t1)
  const waitUntil = Date.now() + 40000;
  while (Date.now() < waitUntil) {
    const total = host.state ? host.state.teams.reduce((a, t) => a + t.players.length, 0) : 0;
    if (total >= 4) break;
    await sleep(200);
  }
  const godotP = host.state.teams.flatMap((t) => t.players).find((p) => !['Coruja', 'Lince', 'Raposa'].includes(p.name));
  if (godotP) host.send({ t: 'host_move', pid: godotP.id, team: 't1' });
  await sleep(1500);
  host.send({ t: 'host_start' });
  console.log('START');
  while (!mates[0].state || mates[0].state.phase !== 'playing') await sleep(200);
  // colega monta parte do quadro: pessoas, um fato, fios e uma prova
  const people = cases.cards.filter((c) => c.kind === 'pessoa').slice(0, 4);
  const fact = cases.cards.find((c) => c.kind === 'fato');
  const pos = [[0.25, 0.3], [0.7, 0.28], [0.3, 0.7], [0.72, 0.72], [0.5, 0.5]];
  [...people, fact].forEach((c, i) => mates[0].send({ t: 'board', op: { k: 'pin', ref: 'p:' + c.id, x: pos[i][0], y: pos[i][1] } }));
  await sleep(400);
  const e = cases.solution.edges;
  for (const edge of e.slice(0, 3)) {
    for (const id of [edge.from, edge.to]) mates[0].send({ t: 'board', op: { k: 'pin', ref: 'p:' + id, x: 0.2 + Math.random() * 0.6, y: 0.2 + Math.random() * 0.6 } });
  }
  await sleep(400);
  for (const edge of e.slice(0, 3)) mates[0].send({ t: 'board', op: { k: 'link', a: edge.from, b: edge.to, type: edge.type } });
  await sleep(600);
  const st = mates[0].state;
  const mine = st.mine || [];
  if (mine[0]) mates[0].send({ t: 'board', op: { k: 'pin', ref: 'c:' + mine[0], x: 0.5, y: 0.15 } });
  const l = st.board.links[0];
  const proof = e[0].evidence.find((x) => st.clues.some((c) => c.id === x)) || (st.clues[0] && st.clues[0].id);
  if (l && proof) mates[0].send({ t: 'board', op: { k: 'attach', id: l.id, clue: proof } });
  console.log('BOARD READY');
  const hold = Number(process.env.HOLD_MS || 60000);
  await sleep(hold);
  process.exit(0);
})();
