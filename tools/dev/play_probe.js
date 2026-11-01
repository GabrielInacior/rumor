'use strict';
// Sonda de gameplay pela rede (servidor real + WebSocket), para cada caso:
// multi: 2 equipes de 3, nome proibido e repetido, chamada de prontos com queda, volta pelo nome,
// rajada simultânea no quadro, votação (não, queda no meio, sim), uma equipe acerta e a outra erra,
// revelação: quem acertou recebe a solução, quem errou NÃO recebe.
// solo: errar (sem resposta) e acertar (com resposta).
// Uso: node tools/dev/play_probe.js [id_do_caso]
const WebSocket = require('../../server/node_modules/ws');
const srv = require('../../server/src/server');

const only = process.argv[2];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function client(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const inbox = [];
  const waiters = [];
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    inbox.push(m);
    for (const w of [...waiters]) if (w.pred(m)) { waiters.splice(waiters.indexOf(w), 1); w.res(m); }
  });
  return {
    ws, inbox,
    open: () => new Promise((r) => ws.on('open', r)),
    send: (o) => ws.send(JSON.stringify(o)),
    last: (pred) => inbox.slice().reverse().find(pred),
    wait: (pred, ms = 4000) => {
      const hit = inbox.slice().reverse().find(pred);
      if (hit) return Promise.resolve(hit);
      return new Promise((res, rej) => { waiters.push({ pred, res }); setTimeout(() => rej(new Error('timeout')), ms); });
    },
    close: () => new Promise((r) => { ws.on('close', r); ws.close(); }),
  };
}

// dá à equipe as pistas de prova (que o caso se resolve de verdade é coberto por audit_cases.js)
function giveProofs(room, team) {
  for (const e of room.caseData.solution.edges) for (const ev of e.evidence || []) team.found.add(ev);
}

async function buildBoard(socks, room, team) {
  const sol = room.caseData.solution;
  const ids = new Set();
  for (const e of sol.edges) { ids.add(e.from); ids.add(e.to); }
  // rajada: todos fixam e ligam as mesmas coisas ao mesmo tempo
  for (const id of ids) for (const s of socks) s.send({ t: 'board', op: { k: 'pin', ref: 'p:' + id, x: Math.random(), y: Math.random() } });
  for (const e of sol.edges) for (const s of socks) s.send({ t: 'board', op: { k: 'link', a: e.from, b: e.to, type: e.type } });
  await sleep(250);
  for (const e of sol.edges) {
    const l = team.board.links.find((x) => x.a === e.from && x.b === e.to && x.type === e.type);
    if (l && (e.evidence || []).length) {
      socks[0].send({ t: 'board', op: { k: 'pin', ref: 'c:' + e.evidence[0], x: 0.5, y: 0.9 } });
      for (const s of socks) s.send({ t: 'board', op: { k: 'attach', id: l.id, clue: e.evidence[0] } });
    }
  }
  await sleep(250);
}

async function multi(port, c) {
  const errs = [];
  const host = client(port); await host.open();
  host.send({ t: 'host_create' });
  const hosted = await host.wait((m) => m.t === 'hosted');
  host.send({ t: 'host_settings', caseId: c.id, teamCount: 2 });
  const room = srv.rooms.get(hosted.code);
  const bad = client(port); await bad.open();
  bad.send({ t: 'join', code: hosted.code, name: 'P1nt0' });
  const be = await bad.wait((m) => m.t === 'error');
  if (be.field !== 'name') errs.push('nome proibido não foi barrado');
  const names = ['Ana Clara', 'Bruno', 'Carolina', 'Davi', 'Eduarda', 'Felipe'];
  const P = [];
  for (const n of names) {
    const s = client(port); await s.open();
    s.send({ t: 'join', code: hosted.code, name: n });
    await s.wait((m) => m.t === 'joined');
    P.push(s);
  }
  bad.send({ t: 'join', code: hosted.code, name: 'ana clara' });
  await sleep(120);
  if (!bad.last((m) => m.t === 'error' && /Já tem alguém/.test(m.msg))) errs.push('nome repetido não foi recusado');
  P.forEach((s, i) => s.send({ t: 'pick_team', team: i < 3 ? 't1' : 't2' }));
  await sleep(150);
  host.send({ t: 'host_start' });
  await P[0].wait((m) => m.t === 'state' && m.phase === 'briefing');
  for (const s of P.slice(0, 5)) s.send({ t: 'ready' });
  await sleep(150);
  if (room.phaseEndsAt) errs.push('contagem começou sem todos prontos');
  await P[5].close();
  await sleep(150);
  if (!room.phaseEndsAt) errs.push('quem caiu segurou a contagem');
  room.phaseEndsAt = 1;
  await P[0].wait((m) => m.t === 'state' && m.phase === 'playing');
  const back = client(port); await back.open();
  back.send({ t: 'join', code: hosted.code, name: 'Felipe' });
  const jb = await back.wait((m) => m.t === 'joined');
  if (!jb.rejoined) errs.push('voltar pelo nome não retomou o jogador');
  P[5] = back;
  const st = await back.wait((m) => m.t === 'state' && m.me);
  if (st.me.team !== 't2') errs.push('voltou em outra equipe');
  const [A] = room.teams;
  giveProofs(room, A);
  await buildBoard(P.slice(0, 3), room, A);
  if (A.board.cards.length !== new Set(A.board.cards.map((x) => x.ref)).size) errs.push('rajada duplicou cartas');
  if (A.board.links.length !== new Set(A.board.links.map((x) => x.a + '|' + x.b + '|' + x.type)).size) errs.push('rajada duplicou fios');
  P[0].send({ t: 'propose_finish', culprit: c.solution.culprit });
  await sleep(100);
  P[1].send({ t: 'vote_finish', yes: false });
  await sleep(100);
  if (A.vote || A.finishedAt) errs.push('voto não, não cancelou');
  P[0].send({ t: 'propose_finish', culprit: c.solution.culprit });
  await sleep(60);
  P[1].send({ t: 'vote_finish', yes: true });
  await sleep(100);
  await P[2].close();
  await sleep(150);
  if (!A.finishedAt) errs.push('queda de quem faltava votar não completou a entrega');
  if (A.finalResult && !A.finalResult.correct) errs.push('quadro certo não deu caso resolvido: ' + JSON.stringify(A.finalResult.categories));
  P[0].send({ t: 'board', op: { k: 'unpin', ref: 'p:' + c.solution.culprit } });
  await sleep(80);
  if (!A.board.cards.some((x) => x.ref === 'p:' + c.solution.culprit)) errs.push('quadro mudou depois de entregue');
  const wrong = c.cards.find((x) => x.kind === 'pessoa' && x.id !== c.solution.culprit).id;
  P[3].send({ t: 'propose_finish', culprit: wrong });
  await sleep(60);
  P[4].send({ t: 'vote_finish', yes: true });
  P[5].send({ t: 'vote_finish', yes: true });
  const ra = await P[0].wait((m) => m.t === 'reveal');
  const rb = await P[3].wait((m) => m.t === 'reveal');
  if (!ra.reveal.culprit || ra.reveal.hidden) errs.push('quem acertou não recebeu a solução');
  if (rb.reveal.culprit || rb.reveal.reveal || rb.reveal.edges || !rb.reveal.hidden) errs.push('quem ERROU recebeu a solução');
  if (ra.reveal.ranking[0].id !== 't1') errs.push('placar: quem acertou não ficou em 1º');
  const hr = await host.wait((m) => m.t === 'reveal');
  if (!hr.reveal.culprit) errs.push('professor sem a solução na revelação');
  for (const s of [host, bad, ...P]) { try { s.ws.close(); } catch (e) { /* já fechado */ } }
  return errs;
}

async function solo(port, c) {
  const errs = [];
  for (const right of [false, true]) {
    const s = client(port); await s.open();
    s.send({ t: 'solo_start', caseId: c.id, name: 'Detetive' });
    const j = await s.wait((m) => m.t === 'joined');
    const room = srv.rooms.get(j.code);
    s.send({ t: 'ready' });
    await sleep(80);
    if (!room.phaseEndsAt) errs.push('solo: pronto não começou a contagem');
    room.phaseEndsAt = 1;
    await s.wait((m) => m.t === 'state' && m.phase === 'playing');
    const team = room.teams[0];
    giveProofs(room, team);
    await buildBoard([s], room, team);
    const wrong = c.cards.find((x) => x.kind === 'pessoa' && x.id !== c.solution.culprit).id;
    s.send({ t: 'propose_finish', culprit: right ? c.solution.culprit : wrong });
    const r = await s.wait((m) => m.t === 'reveal');
    if (right && (!r.reveal.culprit || !r.reveal.ranking[0].solved)) errs.push('solo: acerto sem solução ou sem resolvido');
    if (!right && (r.reveal.culprit || !r.reveal.hidden)) errs.push('solo: erro recebeu a solução');
    s.ws.close();
  }
  return errs;
}

(async () => {
  await new Promise((r) => srv.server.listen(0, r));
  const port = srv.server.address().port;
  let total = 0;
  for (const c of srv.cases.values()) {
    if (only && c.id !== only) continue;
    let errs;
    try { errs = (c.mode || 'multi') === 'solo' ? await solo(port, c) : await multi(port, c); } catch (e) { errs = ['travou: ' + e.message]; }
    total += errs.length;
    console.log(`${errs.length ? 'FALHA' : 'ok   '}  ${c.id}${errs.length ? '\n   - ' + errs.join('\n   - ') : ''}`);
  }
  console.log('Total de problemas: ' + total);
  process.exit(total ? 1 : 0);
})();
