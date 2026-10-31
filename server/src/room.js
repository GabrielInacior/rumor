'use strict';
// Uma sala de aula: professor (host), equipes, alunos, quadro compartilhado por equipe.
// O servidor é a autoridade: guarda a solução, distribui pistas e valida teorias.
const crypto = require('crypto');
const { validateBoard } = require('./validate');

const TEAM_PRESETS = [
  { id: 't1', name: 'Lanterna', color: '#ffc83d' },
  { id: 't2', name: 'Neblina', color: '#6fd3ff' },
  { id: 't3', name: 'Néon', color: '#ff6fae' },
  { id: 't4', name: 'Fumaça', color: '#b9a3ff' },
  { id: 't5', name: 'Faísca', color: '#ff9a4d' },
  { id: 't6', name: 'Luar', color: '#8ef0b5' },
];
const BRIEFING_SEC = 12;
const MAX_CARDS = 70;
const MAX_LINKS = 70;

const token = () => crypto.randomBytes(9).toString('base64url');

class Room {
  constructor(code, cases, send) {
    this.code = code;
    this.cases = cases;          // Map id -> caso completo
    this.send = send;            // (sock, obj) => void
    this.hostSecret = token();
    this.hostSock = null;
    this.phase = 'lobby';        // lobby | briefing | playing | reveal
    this.settings = { caseId: [...cases.keys()][0], teamCount: 3, penaltySec: 45, durationSec: null };
    this.players = new Map();    // pid -> {id,name,teamId,secret,sock,clues:Set}
    this.teams = [];
    this.makeTeams();
    this.touched = Date.now();
    this.phaseEndsAt = 0;
    this.startedAt = 0;
    this.released = new Set();
    this.solvedOrder = [];
  }

  get caseData() { return this.cases.get(this.settings.caseId); }

  makeTeams() {
    const old = this.teams;
    this.teams = TEAM_PRESETS.slice(0, this.settings.teamCount).map((p) => {
      const prev = old.find((t) => t.id === p.id);
      return {
        ...p,
        board: { cards: [], links: [], seq: 0 },
        found: new Set(),
        lockUntil: 0,
        lastResult: null,
        bestScore: 0,
        submissions: 0,
        solvedAt: 0,
        players: prev ? prev.players : [],
      };
    });
    // quem estava numa equipe que deixou de existir volta para "sem equipe"
    for (const pl of this.players.values()) {
      if (!this.teams.find((t) => t.id === pl.teamId)) pl.teamId = null;
    }
    this.syncTeamRosters();
  }

  syncTeamRosters() {
    for (const t of this.teams) {
      t.players = [...this.players.values()].filter((p) => p.teamId === t.id).map((p) => p.id);
    }
  }

  // ------------------------------------------------------------- conexões
  attachHost(sock) { this.hostSock = sock; sock.room = this; sock.role = 'host'; this.touch(); }

  join(sock, rawName) {
    if (this.players.size >= 60) return { error: 'Sala cheia.' };
    let name = String(rawName || 'Agente').slice(0, 24).trim() || 'Agente';
    const taken = new Set([...this.players.values()].map((p) => p.name));
    if (taken.has(name)) {
      let n = 2;
      while (taken.has(`${name} ${n}`)) n++;
      name = `${name} ${n}`;
    }
    const p = { id: token(), name, teamId: null, secret: token(), sock, clues: new Set() };
    this.players.set(p.id, p);
    // entra automaticamente na equipe menor (o aluno pode trocar no lobby)
    this.autoTeam(p);
    sock.room = this; sock.role = 'player'; sock.pid = p.id;
    this.emitEvent({ k: 'join', name: p.name });
    this.touch();
    return { player: p };
  }

  resume(sock, pid, secret) {
    const p = this.players.get(pid);
    if (!p || p.secret !== secret) return false;
    p.sock = sock; sock.room = this; sock.role = 'player'; sock.pid = pid;
    this.touch();
    return true;
  }

  autoTeam(p) {
    const t = [...this.teams].sort((a, b) => a.players.length - b.players.length)[0];
    p.teamId = t.id;
    this.syncTeamRosters();
  }

  drop(sock) {
    if (sock.role === 'host' && this.hostSock === sock) this.hostSock = null;
    if (sock.role === 'player') {
      const p = this.players.get(sock.pid);
      if (p && p.sock === sock) p.sock = null;
    }
    this.broadcast();
  }

  touch() { this.touched = Date.now(); }

  // ------------------------------------------------------------- professor
  hostCmd(msg) {
    const t = msg.t;
    if (t === 'host_settings' && this.phase === 'lobby') {
      if (msg.caseId && this.cases.has(msg.caseId)) this.settings.caseId = msg.caseId;
      if (msg.teamCount) {
        this.settings.teamCount = Math.max(2, Math.min(6, msg.teamCount | 0));
        this.makeTeams();
        for (const p of this.players.values()) if (!p.teamId) this.autoTeam(p);
      }
      if (msg.penaltySec != null) this.settings.penaltySec = Math.max(0, Math.min(180, msg.penaltySec | 0));
    } else if (t === 'host_kick') {
      const p = this.players.get(msg.pid);
      if (p) { this.players.delete(p.id); this.syncTeamRosters(); if (p.sock) this.send(p.sock, { t: 'kicked' }); }
    } else if (t === 'host_move' && this.phase === 'lobby') {
      const p = this.players.get(msg.pid);
      if (p && this.teams.find((x) => x.id === msg.team)) { p.teamId = msg.team; this.syncTeamRosters(); }
    } else if (t === 'host_shuffle' && this.phase === 'lobby') {
      const list = [...this.players.values()].sort(() => Math.random() - 0.5);
      list.forEach((p, i) => { p.teamId = this.teams[i % this.teams.length].id; });
      this.syncTeamRosters();
    } else if (t === 'host_start' && this.phase === 'lobby') {
      this.startRound();
    } else if (t === 'host_release' && this.phase === 'playing') {
      this.releaseNextTimed();
    } else if (t === 'host_add_time' && this.phase === 'playing') {
      this.phaseEndsAt += 60_000;
    } else if (t === 'host_end' && (this.phase === 'playing' || this.phase === 'briefing')) {
      this.toReveal();
    } else if (t === 'host_lobby') {
      this.phase = 'lobby';
      this.makeTeams();
      for (const p of this.players.values()) { p.clues = new Set(); if (!p.teamId) this.autoTeam(p); }
    }
    this.broadcast();
  }

  startRound() {
    const c = this.caseData;
    this.settings.durationSec = c.duration_sec || 900;
    this.makeTeams();
    for (const p of this.players.values()) { p.clues = new Set(); if (!p.teamId) this.autoTeam(p); }
    this.released = new Set();
    this.solvedOrder = [];
    this.phase = 'briefing';
    this.phaseEndsAt = Date.now() + BRIEFING_SEC * 1000;
    for (const p of this.players.values()) if (p.sock) this.send(p.sock, { t: 'case', case: publicCase(c) });
    if (this.hostSock) this.send(this.hostSock, { t: 'case', case: publicCase(c) });
  }

  beginPlaying() {
    this.phase = 'playing';
    this.startedAt = Date.now();
    this.phaseEndsAt = this.startedAt + this.settings.durationSec * 1000;
    for (const clue of this.caseData.clues) {
      if (clue.release === 'start') this.releaseClue(clue, true);
    }
    this.emitEvent({ k: 'go' });
  }

  timedClues() {
    return this.caseData.clues
      .filter((c) => typeof c.release === 'string' && c.release.startsWith('t+'))
      .map((c) => ({ clue: c, at: parseInt(c.release.slice(2), 10) || 0 }))
      .sort((a, b) => a.at - b.at);
  }

  releaseNextTimed() {
    const next = this.timedClues().find((x) => !this.released.has(x.clue.id));
    if (next) this.releaseClue(next.clue, false);
  }

  // Pista "split" vai para UM aluno por equipe, em rodízio estável. Todas as equipes recebem
  // as mesmas pistas nos mesmos momentos (competição justa).
  releaseClue(clue, silent) {
    if (this.released.has(clue.id)) return;
    this.released.add(clue.id);
    const splitIndex = this.caseData.clues.filter((c) => c.deal === 'split' && this.released.has(c.id)).length - 1;
    for (const team of this.teams) {
      if (clue.deal === 'split' && team.players.length > 0) {
        const pid = team.players[splitIndex % team.players.length];
        const p = this.players.get(pid);
        if (p) p.clues.add(clue.id);
      } else {
        team.found.add(clue.id);
      }
    }
    if (!silent) this.emitEvent({ k: 'clue_new', clue: clue.id, title: clue.title });
  }

  toReveal() {
    this.phase = 'reveal';
    // equipes sem entrega ainda são avaliadas pelo quadro atual, para o placar final
    for (const team of this.teams) {
      if (!team.solvedAt) {
        const r = validateBoard(this.caseData, team.board);
        team.bestScore = Math.max(team.bestScore, r.score);
        team.finalResult = r;
      }
    }
    if (this.hostSock) this.send(this.hostSock, { t: 'reveal', reveal: this.revealData() });
    for (const p of this.players.values()) if (p.sock) this.send(p.sock, { t: 'reveal', reveal: this.revealData() });
    this.emitEvent({ k: 'reveal' });
  }

  revealData() {
    const c = this.caseData;
    return {
      reveal: c.reveal,
      edges: c.solution.edges,
      categories: c.solution.categories,
      ranking: this.ranking(),
    };
  }

  ranking() {
    const solved = this.teams.filter((t) => t.solvedAt).sort((a, b) => a.solvedAt - b.solvedAt);
    const rest = this.teams.filter((t) => !t.solvedAt).sort((a, b) => b.bestScore - a.bestScore);
    return [...solved, ...rest].map((t, i) => ({
      place: i + 1, id: t.id, name: t.name, color: t.color, solved: !!t.solvedAt,
      timeSec: t.solvedAt ? Math.round((t.solvedAt - this.startedAt) / 1000) : null,
      score: t.bestScore, submissions: t.submissions,
    }));
  }

  // ------------------------------------------------------------- tempo
  tick(now) {
    if (this.phase === 'briefing' && now >= this.phaseEndsAt) { this.beginPlaying(); this.broadcast(); return; }
    if (this.phase !== 'playing') return;
    const elapsed = (now - this.startedAt) / 1000;
    let changed = false;
    for (const x of this.timedClues()) {
      if (!this.released.has(x.clue.id) && elapsed >= x.at) { this.releaseClue(x.clue, false); changed = true; }
    }
    if (now >= this.phaseEndsAt) { this.toReveal(); changed = true; }
    if (changed) this.broadcast();
  }

  // ------------------------------------------------------------- aluno
  playerCmd(sock, msg) {
    const p = this.players.get(sock.pid);
    if (!p) return;
    this.touch();
    if (msg.t === 'pick_team' && this.phase === 'lobby') {
      if (this.teams.find((t) => t.id === msg.team)) { p.teamId = msg.team; this.syncTeamRosters(); }
      this.broadcast();
      return;
    }
    const team = this.teams.find((t) => t.id === p.teamId);
    if (!team || this.phase !== 'playing') return;

    if (msg.t === 'hotspot') {
      const hs = (this.caseData.hotspots || []).find((h) => h.id === msg.id);
      if (hs && !team.found.has(hs.clue)) {
        team.found.add(hs.clue);
        this.emitEvent({ k: 'hotspot', team: team.id, by: p.name, id: hs.id, label: hs.label }, team.id);
        this.broadcastTeam(team);
      }
      return;
    }
    if (msg.t === 'interrogate') {
      // a fala de um nó do interrogatório libera uma pista para a equipe inteira
      const card = this.caseData.cards.find((c) => c.id === msg.person);
      const node = card && card.talk && card.talk.tree && card.talk.tree.nodes ? card.talk.tree.nodes[msg.node] : null;
      if (node && node.unlock && !team.found.has(node.unlock)) {
        team.found.add(node.unlock);
        this.released.add(node.unlock);
        const clue = this.caseData.clues.find((c) => c.id === node.unlock);
        this.emitEvent({ k: 'interrogated', team: team.id, by: p.name, person: card.name, clue: node.unlock, title: clue ? clue.title : '' }, team.id);
        this.broadcastTeam(team);
      }
      return;
    }
    if (msg.t === 'board') {
      const ok = this.applyBoardOp(team, p, msg.op || {});
      if (ok) this.broadcastTeam(team, msg.op && msg.op.k === 'move' ? sock : null);
      return;
    }
    if (msg.t === 'submit') {
      const now = Date.now();
      if (team.solvedAt || now < team.lockUntil) return;
      const r = validateBoard(this.caseData, team.board);
      team.submissions += 1;
      team.lastResult = { ...r, by: p.name, at: now };
      team.bestScore = Math.max(team.bestScore, r.score);
      if (r.correct) {
        team.solvedAt = now;
        this.solvedOrder.push(team.id);
        this.emitEvent({ k: 'solved', team: team.id, name: team.name, place: this.solvedOrder.length });
        if (this.teams.every((t) => t.solvedAt || t.players.length === 0)) this.toReveal();
      } else {
        team.lockUntil = now + this.settings.penaltySec * 1000;
        this.emitEvent({ k: 'wrong', team: team.id }, team.id);
      }
      this.broadcast();
    }
  }

  visibleClues(team, p) {
    const ids = new Set(team.found);
    if (p) for (const c of p.clues) ids.add(c);
    for (const card of team.board.cards) if (card.ref.startsWith('c:')) ids.add(card.ref.slice(2));
    for (const l of team.board.links) if (l.evidence) ids.add(l.evidence);
    return ids;
  }

  applyBoardOp(team, p, op) {
    const b = team.board;
    const c = this.caseData;
    const refOk = (ref) => {
      if (typeof ref !== 'string') return false;
      if (ref.startsWith('p:')) return c.cards.some((x) => x.id === ref.slice(2));
      if (ref.startsWith('c:')) return this.visibleClues(team, p).has(ref.slice(2));
      return false;
    };
    const clamp = (v) => Math.max(0, Math.min(1, Number(v) || 0));
    switch (op.k) {
      case 'pin': {
        if (!refOk(op.ref) || b.cards.length >= MAX_CARDS) return false;
        if (b.cards.some((x) => x.ref === op.ref)) return false;
        b.cards.push({ ref: op.ref, x: clamp(op.x), y: clamp(op.y), by: p.name });
        return true;
      }
      case 'move': {
        const card = b.cards.find((x) => x.ref === op.ref);
        if (!card) return false;
        card.x = clamp(op.x); card.y = clamp(op.y);
        return true;
      }
      case 'unpin': {
        const i = b.cards.findIndex((x) => x.ref === op.ref);
        if (i < 0) return false;
        b.cards.splice(i, 1);
        b.links = b.links.filter((l) => l.a !== op.ref.slice(2) || !op.ref.startsWith('p:'))
          .filter((l) => l.b !== op.ref.slice(2) || !op.ref.startsWith('p:'));
        if (op.ref.startsWith('c:')) {
          const cid = op.ref.slice(2);
          for (const l of b.links) if (l.evidence === cid) l.evidence = null;
        }
        return true;
      }
      case 'link': {
        const a = String(op.a || ''); const bb = String(op.b || '');
        if (a === bb || b.links.length >= MAX_LINKS) return false;
        if (!b.cards.some((x) => x.ref === 'p:' + a) || !b.cards.some((x) => x.ref === 'p:' + bb)) return false;
        if (!c.link_types.some((t) => t.id === op.type)) return false;
        if (b.links.some((l) => l.a === a && l.b === bb && l.type === op.type)) return false;
        b.seq += 1;
        b.links.push({ id: 'l' + b.seq, a, b: bb, type: op.type, evidence: null, by: p.name });
        return true;
      }
      case 'retype': {
        const l = b.links.find((x) => x.id === op.id);
        if (!l || !c.link_types.some((t) => t.id === op.type)) return false;
        l.type = op.type;
        return true;
      }
      case 'flip': {
        const l = b.links.find((x) => x.id === op.id);
        if (!l) return false;
        [l.a, l.b] = [l.b, l.a];
        return true;
      }
      case 'unlink': {
        const n = b.links.length;
        b.links = b.links.filter((x) => x.id !== op.id);
        return b.links.length !== n;
      }
      case 'attach': {
        const l = b.links.find((x) => x.id === op.id);
        if (!l) return false;
        if (op.clue == null) { l.evidence = null; return true; }
        if (!this.visibleClues(team, p).has(op.clue)) return false;
        l.evidence = op.clue;
        return true;
      }
      default:
        return false;
    }
  }

  // ------------------------------------------------------------- envio de estado
  emitEvent(evt, teamId) {
    const msg = { t: 'evt', evt };
    if (this.hostSock) this.send(this.hostSock, msg);
    for (const p of this.players.values()) {
      if (!p.sock) continue;
      if (teamId && p.teamId !== teamId) continue;
      this.send(p.sock, msg);
    }
  }

  teamsSummary() {
    return this.teams.map((t) => ({
      id: t.id, name: t.name, color: t.color,
      players: t.players.map((id) => {
        const p = this.players.get(id);
        return { id, name: p.name, online: !!p.sock };
      }),
      solved: !!t.solvedAt, place: t.solvedAt ? this.solvedOrder.indexOf(t.id) + 1 : 0,
      submissions: t.submissions, score: t.bestScore,
      progress: t.lastResult ? t.lastResult.categories : null,
      cards: t.board.cards.length, links: t.board.links.length,
    }));
  }

  common() {
    return {
      code: this.code, phase: this.phase, now: Date.now(), endsAt: this.phaseEndsAt,
      startedAt: this.startedAt, settings: this.settings, teams: this.teamsSummary(),
      released: [...this.released],
    };
  }

  stateFor(p) {
    const team = this.teams.find((t) => t.id === p.teamId);
    const s = { t: 'state', ...this.common(), me: { id: p.id, name: p.name, team: p.teamId } };
    if (team && this.phase !== 'lobby') {
      const vis = this.visibleClues(team, p);
      // só o texto das pistas que este aluno pode ver (o resto nem trafega pela rede)
      s.clues = this.caseData.clues.filter((c) => vis.has(c.id));
      s.mine = [...p.clues];
      s.board = { cards: team.board.cards, links: team.board.links };
      s.hotspots = (this.caseData.hotspots || []).filter((h) => team.found.has(h.clue)).map((h) => h.id);
      s.lockUntil = team.lockUntil;
      s.lastResult = team.lastResult;
      s.solved = !!team.solvedAt;
    }
    return s;
  }

  hostState() {
    const s = { t: 'state', ...this.common(), host: true };
    s.cases = [...this.cases.values()].map((c) => ({
      id: c.id, title: c.title, tagline: c.tagline, difficulty: c.difficulty, duration_sec: c.duration_sec,
    }));
    if (this.phase !== 'lobby') {
      s.clues = this.caseData.clues;
      s.boards = Object.fromEntries(this.teams.map((t) => [t.id, { cards: t.board.cards, links: t.board.links }]));
    }
    return s;
  }

  broadcastTeam(team, except) {
    for (const id of team.players) {
      const p = this.players.get(id);
      if (p && p.sock && p.sock !== except) this.send(p.sock, this.stateFor(p));
    }
    if (this.hostSock) this.send(this.hostSock, this.hostState());
  }

  broadcast() {
    if (this.hostSock) this.send(this.hostSock, this.hostState());
    for (const p of this.players.values()) if (p.sock) this.send(p.sock, this.stateFor(p));
  }
}

// O que o aluno pode saber do caso: tudo menos a solução e a revelação.
function publicCase(c) {
  const { solution, reveal, clues, hotspots, ...rest } = c;
  return {
    ...rest,
    clue_count: clues.length,
    hotspots: (hotspots || []).map((h) => ({ id: h.id, object: h.object, label: h.label })),
    categories: solution.categories.map((x) => ({ id: x.id, label: x.label })),
  };
}

module.exports = { Room, publicCase, TEAM_PRESETS };
