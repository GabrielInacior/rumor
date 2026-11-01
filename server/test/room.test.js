'use strict';
// Testa a sala ponta a ponta por WebSocket: professor cria, alunos entram, pistas são distribuídas,
// quadro é editado, teoria errada bloqueia, teoria certa vence. Usa um caso mínimo próprio.
const { test } = require('node:test');
const assert = require('node:assert');
const path = require('path');
const fs = require('fs');
const os = require('os');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rumor-cases-'));
fs.writeFileSync(path.join(dir, 'mini.json'), JSON.stringify({
  id: 'mini', title: 'Mini', tagline: 't', difficulty: 1, duration_sec: 60, scene: 'corredor',
  briefing: 'b', goal: 'g',
  link_types: [{ id: 'contou', label: 'contou para', directed: true }, { id: 'criou', label: 'criou', directed: true }],
  cards: [
    { id: 'ana', kind: 'pessoa', name: 'Ana' }, { id: 'bia', kind: 'pessoa', name: 'Bia' },
    { id: 'rafa', kind: 'pessoa', name: 'Rafa' }, { id: 'versao', kind: 'fato', name: 'Versão' },
  ],
  clues: [
    { id: 'c1', kind: 'mensagem', title: 'c1', text: 'x', release: 'start', deal: 'split' },
    { id: 'c2', kind: 'mensagem', title: 'c2', text: 'x', release: 'start', deal: 'split' },
    { id: 'c3', kind: 'registro', title: 'c3', text: 'x', release: 'start', deal: 'team' },
    { id: 'c4', kind: 'objeto', title: 'c4', text: 'x', release: 'hotspot', deal: 'team' },
    { id: 'c5', kind: 'depoimento', title: 'c5', text: 'x', release: 't+1', deal: 'team' },
  ],
  hotspots: [{ id: 'h1', object: 'mural', label: 'Mural', clue: 'c4' }],
  solution: {
    categories: [{ id: 'origem', label: 'Origem' }, { id: 'dist', label: 'Distorção' }],
    edges: [
      { from: 'ana', to: 'bia', type: 'contou', category: 'origem', evidence: ['c1'] },
      { from: 'bia', to: 'versao', type: 'criou', category: 'dist', evidence: ['c4'] },
    ],
    traps: [{ from: 'rafa', to: 'versao', type: 'criou', category: 'dist' }],
  },
  reveal: { timeline: [], explanation: 'e', refuted: [] },
}));
process.env.RUMOR_CASES = dir;
process.env.PORT = '0';
const WebSocket = require('ws');
const { server } = require('../src/server');

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
    wait: (pred, ms = 3000) => {
      const hit = inbox.slice().reverse().find(pred);
      if (hit) return Promise.resolve(hit);
      return new Promise((res, rej) => {
        waiters.push({ pred, res });
        setTimeout(() => rej(new Error('timeout')), ms);
      });
    },
    next: (pred, ms = 3000) => new Promise((res, rej) => {
      waiters.push({ pred, res });
      setTimeout(() => rej(new Error('timeout')), ms);
    }),
  };
}

test('rodada completa', async () => {
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;
  const host = client(port); await host.open();
  host.send({ t: 'host_create' });
  const hosted = await host.wait((m) => m.t === 'hosted');
  host.send({ t: 'host_settings', teamCount: 2, penaltySec: 1 });

  const a = client(port); await a.open();
  const b = client(port); await b.open();
  const c = client(port); await c.open();
  a.send({ t: 'join', code: hosted.code, name: 'Corvo' });
  b.send({ t: 'join', code: hosted.code, name: 'Corvo' });
  c.send({ t: 'join', code: hosted.code, name: 'Gato' });
  const ja = await a.wait((m) => m.t === 'joined');
  const jb = await b.wait((m) => m.t === 'joined');
  await c.wait((m) => m.t === 'joined');
  assert.strictEqual(jb.name, 'Corvo 2', 'nome repetido ganha número');
  a.send({ t: 'pick_team', team: 't1' });
  b.send({ t: 'pick_team', team: 't1' });
  c.send({ t: 'pick_team', team: 't2' });
  await a.next((m) => m.t === 'state' && m.teams[0].players.length === 2);

  host.send({ t: 'host_start' });
  const pc = await a.wait((m) => m.t === 'case');
  assert.ok(!pc.case.solution && !pc.case.clues, 'solução e pistas não vão no caso público');
  // pula o briefing
  const room = require('../src/server').rooms.get(hosted.code);
  // abertura: só conta quando todos dão PRONTO
  const w = await a.wait((m) => m.t === 'state' && m.phase === 'briefing' && m.readyList);
  assert.strictEqual(w.countdown, false);
  for (const x of [a, b, c]) x.send({ t: 'ready' });
  await host.wait((m) => m.t === 'state' && m.countdown === true);
  room.phaseEndsAt = 1;
  const sa = await a.next((m) => m.t === 'state' && m.phase === 'playing');
  const sb = await b.wait((m) => m.t === 'state' && m.phase === 'playing');
  // split: cada aluno da equipe 1 tem uma pista diferente; c3 (team) todos
  assert.deepStrictEqual(sa.mine.length + sb.mine.length, 2);
  assert.notDeepStrictEqual(sa.mine, sb.mine);
  assert.ok(sa.clues.some((x) => x.id === 'c3'));
  assert.ok(!sa.clues.some((x) => sb.mine.includes(x.id)), 'pista do colega não aparece');

  // quem tem c1 fixa no quadro: colega passa a ver
  const holder = sa.mine.includes('c1') ? a : b;
  const other = holder === a ? b : a;
  holder.send({ t: 'board', op: { k: 'pin', ref: 'c:c1', x: 0.2, y: 0.2 } });
  const so = await other.next((m) => m.t === 'state' && m.board.cards.length === 1);
  assert.ok(so.clues.some((x) => x.id === 'c1'));

  // monta teoria com armadilha -> errado e bloqueio
  for (const id of ['ana', 'bia', 'rafa', 'versao']) a.send({ t: 'board', op: { k: 'pin', ref: 'p:' + id, x: 0.5, y: 0.5 } });
  a.send({ t: 'board', op: { k: 'link', a: 'ana', b: 'bia', type: 'contou' } });
  a.send({ t: 'board', op: { k: 'link', a: 'rafa', b: 'versao', type: 'criou' } });
  await a.next((m) => m.t === 'state' && m.board.links.length === 2);
  // entrega: com dois online, vira votação; um "não" cancela
  a.send({ t: 'propose_finish' });
  const vb = await b.next((m) => m.t === 'state' && m.vote);
  assert.strictEqual(vb.vote.mine, false);
  assert.strictEqual(vb.vote.need, 2);
  b.send({ t: 'vote_finish', yes: false });
  const vc = await a.next((m) => m.t === 'state' && m.vote === null);
  assert.strictEqual(vc.finished, false);
  // a regra de correção continua a mesma (armadilha = errado, sem prova = falta prova)
  const { validateBoard } = require('../src/validate');
  const room2 = require('../src/server').rooms.get(hosted.code);
  const wr = validateBoard(room2.caseData, room2.teams[0].board, null);
  assert.strictEqual(wr.correct, false);
  assert.strictEqual(wr.categories.find((x) => x.id === 'dist').status, 'errado');
  assert.strictEqual(wr.categories.find((x) => x.id === 'origem').status, 'falta_prova');

  // conserta: prova, remove armadilha, acha hotspot, liga bia->versao com prova
  const st = await a.wait((m) => m.t === 'state' && m.board.links.length === 2);
  const l1 = st.board.links.find((l) => l.a === 'ana');
  const trap = st.board.links.find((l) => l.a === 'rafa');
  a.send({ t: 'board', op: { k: 'unlink', id: trap.id } });
  a.send({ t: 'board', op: { k: 'attach', id: l1.id, clue: 'c1' } });
  a.send({ t: 'hotspot', id: 'h1' });
  a.send({ t: 'board', op: { k: 'link', a: 'bia', b: 'versao', type: 'criou' } });
  const s2 = await a.next((m) => m.t === 'state' && m.board.links.some((l) => l.a === 'bia'));
  const l2 = s2.board.links.find((l) => l.a === 'bia');
  a.send({ t: 'board', op: { k: 'attach', id: l2.id, clue: 'c4' } });
  await a.next((m) => m.t === 'state' && m.board.links.some((l) => l.evidence === 'c4'));
  a.send({ t: 'propose_finish' });
  await b.next((m) => m.t === 'state' && m.vote);
  b.send({ t: 'vote_finish', yes: true });
  const ok = await a.next((m) => m.t === 'state' && m.finished);
  assert.strictEqual(ok.lastResult.correct, true);
  assert.strictEqual(ok.objectives.secDone, ok.objectives.secTotal);
  const rel = await a.wait((m) => m.t === 'state' && m.released.includes('c5'), 2000);
  assert.ok(rel.clues.some((x) => x.id === 'c5'), 'pista com tempo liberada');

  host.send({ t: 'host_end' });
  const rv = await host.wait((m) => m.t === 'reveal');
  assert.strictEqual(rv.reveal.ranking[0].id, 't1');
  assert.strictEqual(rv.reveal.ranking[0].solved, true);

  for (const x of [host, a, b, c]) x.ws.close();
  await new Promise((r) => server.close(r));
  process.exit(0);
});
