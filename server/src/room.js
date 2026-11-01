'use strict';
// sem limite prático de provas por fio (a carta da prova sempre pode voltar ao quadro)
const MAX_PROOFS = 50;
// ligações gerais, disponíveis em todos os casos, para o aluno montar o panorama completo
// (quem estava com quem, quem mentiu, quem é inocente...). Não contam na correção oficial,
// a não ser que o caso use o mesmo id na solução.
const GENERIC_LINKS = [
  { id: 'g_estava_com', label: 'estava com', directed: false, pairs: ['pessoa>pessoa'] },
  { id: 'g_viu', label: 'viu', directed: true, pairs: ['pessoa>pessoa', 'pessoa>fato'] },
  { id: 'g_mentiu', label: 'mentiu para', directed: true, pairs: ['pessoa>pessoa'] },
  { id: 'g_mentiu_sobre', label: 'mentiu sobre', directed: true, pairs: ['pessoa>fato'] },
  { id: 'g_acobertou', label: 'acobertou', directed: true, pairs: ['pessoa>pessoa'] },
  { id: 'g_alibi', label: 'é o álibi de', directed: true, pairs: ['pessoa>pessoa'] },
  { id: 'g_brigou', label: 'brigou com', directed: false, pairs: ['pessoa>pessoa'] },
  { id: 'g_amigo', label: 'é amigo(a) de', directed: false, pairs: ['pessoa>pessoa'] },
  { id: 'g_sabia', label: 'sabia de', directed: true, pairs: ['pessoa>fato'] },
  { id: 'g_motivo', label: 'tinha motivo para', directed: true, pairs: ['pessoa>fato'] },
  { id: 'g_nao_fez', label: 'não fez', directed: true, pairs: ['pessoa>fato'] },
  { id: 'g_esteve', label: 'esteve em', directed: true, pairs: ['pessoa>lugar'] },
  { id: 'g_aconteceu', label: 'aconteceu em', directed: true, pairs: ['fato>lugar'] },
];
const CARD_TAGS = ['inocente', 'suspeito', 'mentiu', 'alibi'];

/** Tipos de ligação do caso + gerais (sem repetir um rótulo que o caso já tem). */
function allLinkTypes(c) {
  const own = c.link_types || [];
  const labels = new Set(own.map((t) => String(t.label).toLowerCase()));
  // pares de cartas que as ligações do próprio caso já cobrem (pela solução)
  const kindOf = Object.fromEntries((c.cards || []).map((x) => [x.id, x.kind]));
  const ownPairs = new Set();
  for (const e of [...((c.solution || {}).edges || []), ...((c.solution || {}).traps || [])]) {
    if (own.some((t) => t.id === e.type)) ownPairs.add(`${kindOf[e.from]}>${kindOf[e.to]}`);
  }
  // "esteve em" e "aconteceu em" repetiriam o "estava em" do caso: some quando o caso já liga esse par
  const SAME = { g_esteve: 'pessoa>lugar', g_aconteceu: 'fato>lugar' };
  return [...own, ...GENERIC_LINKS.filter((g) => !labels.has(g.label) && !own.some((t) => t.id === g.id)
    && !(SAME[g.id] && ownPairs.has(SAME[g.id])))];
}
// provas de um fio (compatível com quadros antigos que tinham só "evidence")
function proofsOf(l) { return Array.isArray(l.proofs) ? [...l.proofs] : (l.evidence ? [l.evidence] : []); }
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
const BRIEFING_SEC = 30;   // tempo para ler a abertura com calma
const TIME_BONUS = 1.5;    // por padrão, 50% a mais que o tempo escrito no caso
const MAX_CARDS = 70;
const MAX_LINKS = 70;
const LINK_COLORS = ['vermelho', 'amarelo', 'azul', 'verde', 'rosa'];

const token = () => crypto.randomBytes(9).toString('base64url');

class Room {
  constructor(code, cases, send) {
    this.code = code;
    this.cases = cases;          // Map id -> caso completo
    this.send = send;            // (sock, obj) => void
    this.hostSecret = token();
    this.hostSock = null;
    this.phase = 'lobby';        // lobby | briefing | playing | reveal
    const firstMulti = [...cases.values()].find((c) => (c.mode || 'multi') !== 'solo');
    this.settings = { caseId: firstMulti ? firstMulti.id : [...cases.keys()][0], teamCount: 3, penaltySec: 45, durationSec: null, extraMin: 0 };
    this.players = new Map();    // pid -> {id,name,teamId,secret,sock,clues:Set}
    this.teams = [];
    this.makeTeams();
    this.touched = Date.now();
    this.phaseEndsAt = 0;
    this.startedAt = 0;
    this.released = new Set();
    this.solvedOrder = [];
    this.feed = [];   // registro de ações para o professor acompanhar a turma
  }

  // registra uma ação (só o professor recebe). who = codinome; team = id da equipe
  log(teamId, who, text, kind = 'acao') {
    this.feed.push({ at: Date.now(), team: teamId || null, who: who || null, text, kind });
    if (this.feed.length > 300) this.feed.splice(0, this.feed.length - 300);
    if (who) {
      const p = [...this.players.values()].find((x) => x.name === who);
      if (p) { p.lastAction = Date.now(); p.actions = (p.actions || 0) + 1; }
    }
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
        flags: {},          // flag -> codinome de quem conseguiu (reações compartilhadas pela equipe)
        items: new Set(),   // mochila da equipe (objetos de troca)
        lockUntil: 0,
        lastResult: null,
        bestScore: 0,
        submissions: 0,
        solvedAt: 0,
        finishedAt: 0,      // a equipe entregou o caso (resultado fica guardado, quadro trava)
        finalResult: null,
        vote: null,         // votação de entrega em andamento
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
    let name = String(rawName || 'Agente').slice(0, 24).trim() || 'Agente';
    // voltou depois de cair (outro celular, sessão apagada): o mesmo codinome de alguém que está
    // desconectado retoma aquele jogador, com a mesma equipe e as mesmas pistas
    const back = [...this.players.values()].find((x) => x.name === name && !x.sock);
    if (back) {
      back.sock = sock; back.secret = token(); back.lastAction = Date.now();
      sock.room = this; sock.role = 'player'; sock.pid = back.id;
      this.log(back.teamId, back.name, `${back.name} voltou para a sala`, 'sala');
      this.touch();
      return { player: back, rejoined: true };
    }
    // mesmo nome de alguém conectado: pede a inicial do sobrenome (duas Anas na turma)
    if ([...this.players.values()].some((x) => x.sock && x.name.toLowerCase() === name.toLowerCase())) {
      return { error: `Já tem alguém chamado ${name} na sala. Acrescente a inicial do sobrenome (ex.: ${name} S.).` };
    }
    if (this.players.size >= 60) return { error: 'Sala cheia.' };
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
    this.log(p.teamId, p.name, `${p.name} entrou na sala`, 'sala');
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
    this.checkReady(); // quem caiu não segura a turma na abertura
    // quem caiu também não segura a votação de entrega: se todos os conectados já votaram sim, entrega
    for (const t of this.teams) {
      if (t.vote && this.phase === 'playing') {
        const on = this.onlineOf(t);
        if (on.length > 0 && on.every((pid) => t.vote.yes.includes(pid))) this.finishTeam(t, t.vote.culprit, t.vote.by);
      }
    }
    this.broadcast();
  }

  touch() { this.touched = Date.now(); }

  // ------------------------------------------------------------- professor
  hostCmd(msg) {
    const t = msg.t;
    if (t === 'host_guide') { this.sendGuide(); return; }
    if (t === 'host_settings' && this.phase === 'lobby') {
      if (msg.caseId && this.cases.has(msg.caseId) && (this.cases.get(msg.caseId).mode || 'multi') !== 'solo') this.settings.caseId = msg.caseId;
      if (msg.teamCount) {
        this.settings.teamCount = Math.max(2, Math.min(6, msg.teamCount | 0));
        this.makeTeams();
        for (const p of this.players.values()) if (!p.teamId) this.autoTeam(p);
      }
      if (msg.penaltySec != null) this.settings.penaltySec = Math.max(0, Math.min(180, msg.penaltySec | 0));
      if (msg.caseId) { this.settings.extraMin = 0; this.sendGuide(); }
      if (msg.extraMin != null) this.settings.extraMin = Math.max(-10, Math.min(30, msg.extraMin | 0));
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
    } else if (t === 'host_hint' && typeof msg.text === 'string' && msg.text.trim()) {
      const text = msg.text.trim().slice(0, 160);
      const target = this.teams.find((x) => x.id === msg.team);
      this.emitEvent({ k: 'hint', text, team: target ? target.id : null }, target ? target.id : undefined);
      this.log(target ? target.id : null, null, `Professor mandou dica${target ? ' para ' + target.name : ' para todos'}: "${text}"`, 'dica');
    } else if (t === 'host_start' && this.phase === 'lobby') {
      this.startRound();
    } else if (t === 'host_force_start' && this.phase === 'briefing') {
      this.startCountdown();
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

  // guia completo do caso: SÓ para o professor (solução, pistas, onde estão, dúvidas comuns)
  sendGuide() {
    if (!this.hostSock) return;
    const c = this.caseData;
    if (!c) return;
    this.send(this.hostSock, { t: 'guide', guide: {
      id: c.id, title: c.title, teacher_guide: c.teacher_guide || null, solution: c.solution, reveal: c.reveal,
      clues: c.clues, hotspots: c.hotspots || [], items: c.items || [], cards: c.cards, link_types: c.link_types,
      locations: c.locations || [], hints: c.hints || [],
    } });
  }

  startRound() {
    const c = this.caseData;
    this.feed = [];
    for (const p of this.players.values()) { p.lastAction = Date.now(); p.actions = 0; }
    this.settings.durationSec = this.durationFor(c);
    this.makeTeams();
    for (const p of this.players.values()) { p.clues = new Set(); if (!p.teamId) this.autoTeam(p); }
    this.released = new Set();
    this.solvedOrder = [];
    this.phase = 'briefing';
    // a contagem só começa quando todos os alunos conectados derem PRONTO (ou o professor forçar)
    this.phaseEndsAt = 0;
    for (const p of this.players.values()) p.ready = false;
    for (const p of this.players.values()) if (p.sock) this.send(p.sock, { t: 'case', case: publicCase(c) });
    if (this.hostSock) this.send(this.hostSock, { t: 'case', case: publicCase(c) });
  }

  // duração padrão generosa (alunos pouco gamers) arredondada em minutos, mais o ajuste do professor
  durationFor(c) {
    const base = Math.round(((c.duration_sec || 900) * TIME_BONUS) / 60);
    return Math.max(5, base + (this.settings.extraMin || 0)) * 60;
  }

  /** Todos os conectados prontos? Começa a contagem curta (5 s; 3 s no solo). */
  checkReady() {
    if (this.phase !== 'briefing' || this.phaseEndsAt) return;
    const online = [...this.players.values()].filter((p) => p.sock && p.teamId);
    if (online.length > 0 && online.every((p) => p.ready)) this.startCountdown();
  }

  startCountdown() {
    if (this.phase !== 'briefing' || this.phaseEndsAt) return;
    this.phaseEndsAt = Date.now() + (this.solo ? 3 : 5) * 1000;
    this.log(null, null, 'Todos prontos: o caso vai começar', 'sistema');
  }

  beginPlaying() {
    this.phase = 'playing';
    this.startedAt = Date.now();
    // sem tempo limite: o relógio só conta quanto tempo passou (desempate pelo tempo de entrega)
    this.phaseEndsAt = 0;
    for (const clue of this.caseData.clues) {
      if (clue.release === 'start') this.releaseClue(clue, true);
    }
    this.emitEvent({ k: 'go' });
  }

  timedClues() {
    return this.caseData.clues
      .filter((c) => typeof c.release === 'string' && c.release.startsWith('t+'))
      // no solo a pista do tempo é ajuda para quem empacou: nunca antes de 40% do tempo do caso
      .map((c) => {
        const at = parseInt(c.release.slice(2), 10) || 0;
        return { clue: c, at: this.solo ? Math.max(at, Math.round((this.settings.durationSec || 600) * 0.4)) : at };
      })
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
    if (!silent) {
      this.emitEvent({ k: 'clue_new', clue: clue.id, title: clue.title, timed: true });
      this.log(null, null, `Nova pista liberada para todas as equipes: ${clue.title}`, 'sistema');
    }
  }

  toReveal() {
    this.phase = 'reveal';
    // equipes sem entrega ainda são avaliadas pelo quadro atual, para o placar final
    for (const team of this.teams) {
      team.vote = null;
      if (!team.finishedAt) {
        const r = validateBoard(this.caseData, team.board, team.lastCulprit);
        team.bestScore = Math.max(team.bestScore, r.score);
        team.finalResult = r;
      }
    }
    if (this.hostSock) this.send(this.hostSock, { t: 'reveal', reveal: this.revealData() });
    for (const p of this.players.values()) if (p.sock) this.send(p.sock, { t: 'reveal', reveal: this.revealFor(p) });
    this.emitEvent({ k: 'reveal' });
  }

  /**
   * Revelação para um aluno: quem errou o culpado NÃO recebe a resposta (nem o culpado, nem a
   * explicação, nem o quadro oficial). Só o placar e os próprios objetivos.
   */
  revealFor(p) {
    const team = this.teams.find((t) => t.id === p.teamId);
    const r = team ? (team.finalResult || validateBoard(this.caseData, team.board, team.lastCulprit)) : null;
    const o = r ? this.objectives(r) : { primary: false, secDone: 0, secTotal: 0 };
    const mine = r ? { culpritOk: o.primary, objDone: o.secDone, objTotal: o.secTotal, categories: r.categories, finished: !!(team && team.finishedAt) } : null;
    if (o.primary) return { ...this.revealData(), mine };
    return { hidden: true, ranking: this.ranking(), mine, categories: this.caseData.solution.categories.map((c) => ({ id: c.id, label: c.label })) };
  }

  revealData() {
    const c = this.caseData;
    return {
      reveal: c.reveal,
      culprit: c.solution.culprit || null,
      edges: c.solution.edges,
      panorama: c.solution.panorama || [],
      categories: c.solution.categories,
      ranking: this.ranking(),
    };
  }

  ranking() {
    const rows = this.teams.filter((t) => t.players.length > 0 || t.finishedAt).map((t) => {
      const r = t.finalResult || validateBoard(this.caseData, t.board, t.lastCulprit);
      const o = this.objectives(r);
      return { t, r, o, time: t.finishedAt ? t.finishedAt - this.startedAt : Infinity };
    });
    rows.sort((a, b) => (b.o.primary - a.o.primary) || (b.o.secDone - a.o.secDone) || (a.time - b.time) || (b.r.score - a.r.score));
    return rows.map((x, i) => ({
      place: i + 1, id: x.t.id, name: x.t.name, color: x.t.color, solved: !!x.r.correct,
      finished: !!x.t.finishedAt, culpritOk: x.o.primary, objDone: x.o.secDone, objTotal: x.o.secTotal,
      timeSec: x.t.finishedAt ? Math.round(x.time / 1000) : null,
      score: x.r.score, submissions: x.t.submissions,
    }));
  }

  // ------------------------------------------------------------- tempo
  tick(now) {
    if (this.phase === 'briefing' && this.phaseEndsAt && now >= this.phaseEndsAt) { this.beginPlaying(); this.broadcast(); return; }
    if (this.phase !== 'playing') return;
    const elapsed = (now - this.startedAt) / 1000;
    let changed = false;
    for (const x of this.timedClues()) {
      if (!this.released.has(x.clue.id) && elapsed >= x.at) { this.releaseClue(x.clue, false); changed = true; }
    }
    for (const t of this.teams) if (t.vote && now - t.vote.at > 90000) { t.vote = null; changed = true; }
    if (this.phaseEndsAt && now >= this.phaseEndsAt) { this.toReveal(); changed = true; }
    if (changed) this.broadcast();
  }

  // ------------------------------------------------------------- aluno
  playerCmd(sock, msg) {
    const p = this.players.get(sock.pid);
    if (!p) return;
    this.touch();
    if (msg.t === 'pick_team' && this.phase === 'lobby') {
      const nt = this.teams.find((t) => t.id === msg.team);
      if (nt) {
        p.teamId = msg.team; this.syncTeamRosters();
        this.log(p.teamId, p.name, `${p.name} entrou na equipe ${nt.name}`, 'sala');
      }
      this.broadcast();
      return;
    }
    if (msg.t === 'ready' && this.phase === 'briefing') {
      p.ready = msg.ready !== false;
      this.checkReady();
      this.broadcast();
      return;
    }
    const team = this.teams.find((t) => t.id === p.teamId);
    if (!team || this.phase !== 'playing') return;

    if (msg.t === 'hotspot') {
      const hs = (this.caseData.hotspots || []).find((h) => h.id === msg.id);
      if (hs && hs.item && !team.flags['hs:' + hs.id]) {
        team.flags['hs:' + hs.id] = p.name;
        team.items.add(hs.item);
        const it = (this.caseData.items || []).find((x) => x.id === hs.item);
        this.emitEvent({ k: 'item', team: team.id, by: p.name, id: hs.id, label: it ? it.name : hs.label }, team.id);
        this.log(team.id, p.name, `${p.name} pegou ${it ? it.name : 'um objeto'} (${hs.label})`, 'cena');
        this.broadcastTeam(team);
        return;
      }
      if (hs && hs.clue && !team.found.has(hs.clue)) {
        team.found.add(hs.clue);
        this.emitEvent({ k: 'hotspot', team: team.id, by: p.name, id: hs.id, label: hs.label }, team.id);
        this.log(team.id, p.name, `${p.name} achou uma pista: ${hs.label}`, 'cena');
        this.broadcastTeam(team);
      }
      return;
    }
    if (msg.t === 'talk_node') {
      // a equipe chegou num nó da conversa: aplica flags, itens e pista (estado compartilhado)
      const card = this.caseData.cards.find((c) => c.id === msg.person);
      const node = card && card.talk && card.talk.tree && card.talk.tree.nodes ? card.talk.tree.nodes[msg.node] : null;
      if (!node) return;
      let changed = false;
      p.lastAction = Date.now();
      if (!team.flags['talk:' + card.id + ':' + p.name]) {
        team.flags['talk:' + card.id + ':' + p.name] = p.name;
        this.log(team.id, p.name, `${p.name} começou a interrogar ${card.name}`, 'conversa');
      }
      for (const f of node.sets || []) {
        if (!team.flags[f]) { team.flags[f] = p.name; changed = true; }
      }
      if (node.take_item && team.items.has(node.take_item)) { team.items.delete(node.take_item); changed = true; }
      if (node.give_item && !team.items.has(node.give_item)) { team.items.add(node.give_item); changed = true; }
      if (node.unlock && !team.found.has(node.unlock)) {
        team.found.add(node.unlock);
        this.released.add(node.unlock);
        const clue = this.caseData.clues.find((c) => c.id === node.unlock);
        this.emitEvent({ k: 'interrogated', team: team.id, by: p.name, person: card.name, clue: node.unlock, title: clue ? clue.title : '' }, team.id);
        this.log(team.id, p.name, `${p.name} fez ${card.name} contar: ${clue ? clue.title : 'uma pista'}`, 'conversa');
        changed = true;
      }
      if (node.take_item) this.log(team.id, p.name, `${p.name} trocou um objeto com ${card.name}`, 'conversa');
      if ((node.lock || 0) > 0) this.log(team.id, p.name, `${card.name} se fechou com ${p.name} (escolha ruim)`, 'alerta');
      if (changed) this.broadcastTeam(team);
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
      if (team.finishedAt) return;
      const ok = this.applyBoardOp(team, p, msg.op || {});
      if (ok) this.logBoard(team, p, msg.op || {});
      if (ok) this.broadcastTeam(team, msg.op && msg.op.k === 'move' ? sock : null);
      return;
    }
    // ENTREGAR O CASO: quem propõe já vota sim; com mais gente online, a equipe vota.
    if ((msg.t === 'propose_finish' || msg.t === 'submit') && this.phase === 'playing') {
      if (team.finishedAt) return;
      if (team.vote) { this.castVote(team, p, true); return; }
      const culprit = msg.culprit ? String(msg.culprit) : null;
      const online = this.onlineOf(team);
      if (this.solo || online.length <= 1) { this.finishTeam(team, culprit, p.name); return; }
      team.vote = { culprit, by: p.name, byId: p.id, yes: [p.id], no: [], at: Date.now() };
      const cn = (this.caseData.cards.find((c) => c.id === culprit) || {}).name;
      this.log(team.id, p.name, `${p.name} propôs entregar o caso${cn ? ' acusando ' + cn : ''}`, 'teoria');
      this.emitEvent({ k: 'vote_start', team: team.id, by: p.name }, team.id);
      this.broadcast();
      return;
    }
    if (msg.t === 'vote_finish' && team.vote) {
      this.castVote(team, p, !!msg.yes);
      return;
    }
  }

  onlineOf(team) {
    return team.players.filter((pid) => { const pl = this.players.get(pid); return pl && pl.sock; });
  }

  castVote(team, p, yes) {
    const v = team.vote;
    if (!v) return;
    if (!yes) {
      team.vote = null;
      this.log(team.id, p.name, `${p.name} quer continuar investigando (entrega cancelada)`, 'teoria');
      this.emitEvent({ k: 'vote_no', team: team.id, by: p.name }, team.id);
      this.broadcast();
      return;
    }
    if (!v.yes.includes(p.id)) v.yes.push(p.id);
    const online = this.onlineOf(team);
    if (online.every((pid) => v.yes.includes(pid))) this.finishTeam(team, v.culprit, v.by);
    else this.broadcast();
  }

  /** Objetivos: principal = culpado; secundários = cada parte da história provada no quadro. */
  objectives(r) {
    const cul = r.categories.find((c) => c.id === 'culpado');
    const sec = r.categories.filter((c) => c.id !== 'culpado');
    return {
      primary: cul ? cul.status === 'ok' : r.correct,
      secDone: sec.filter((c) => c.status === 'ok').length,
      secTotal: sec.length,
    };
  }

  finishTeam(team, culprit, by) {
    if (team.finishedAt) return;
    const now = Date.now();
    team.vote = null;
    team.lastCulprit = culprit;
    const r = validateBoard(this.caseData, team.board, culprit);
    team.finishedAt = now;
    team.finalResult = r;
    team.lastResult = { ...r, by, at: now };
    team.bestScore = r.score;
    team.submissions = 1;
    if (r.correct) { team.solvedAt = now; this.solvedOrder.push(team.id); }
    const o = this.objectives(r);
    this.log(team.id, by, `${team.name} entregou o caso: culpado ${o.primary ? 'CERTO' : 'errado'}, ${o.secDone} de ${o.secTotal} partes provadas`, o.primary ? 'acerto' : 'teoria');
    this.emitEvent({ k: 'finished', team: team.id, name: team.name }, null);
    if (this.teams.every((t) => t.finishedAt || t.players.length === 0)) this.toReveal();
    this.broadcast();
  }

  /** Devolve a carta de uma prova ao quadro, perto do fio (se ela ainda não estiver lá). */
  returnToBoard(b, l, clueId, p, i) {
    if (!clueId || b.cards.some((x) => x.ref === 'c:' + clueId)) return;
    const clamp = (v) => Math.max(0.02, Math.min(0.98, v));
    const ca = b.cards.find((x) => x.ref === 'p:' + l.a) || { x: 0.5, y: 0.5 };
    const cb = b.cards.find((x) => x.ref === 'p:' + l.b) || { x: 0.5, y: 0.5 };
    b.cards.push({ ref: 'c:' + clueId, x: clamp((ca.x + cb.x) / 2 + 0.1 + i * 0.06), y: clamp((ca.y + cb.y) / 2 + 0.18), by: p.name });
  }

  logBoard(team, p, op) {
    const nm = (id) => { const c = this.caseData.cards.find((x) => x.id === id); return c ? c.name : id; };
    const refName = (ref) => {
      const r = String(ref || '');
      if (r.startsWith('c:')) { const c = this.caseData.clues.find((x) => x.id === r.slice(2)); return c ? c.title : 'pista'; }
      return nm(r.slice(2));
    };
    const lt = (id) => (this.caseData.link_types.find((t) => t.id === id) || {}).label || id;
    if (op.k === 'pin') this.log(team.id, p.name, `${p.name} fixou ${refName(op.ref)} no quadro`, 'quadro');
    else if (op.k === 'unpin') this.log(team.id, p.name, `${p.name} tirou ${refName(op.ref)} do quadro`, 'quadro');
    else if (op.k === 'link') this.log(team.id, p.name, `${p.name} ligou ${nm(op.a)} ${lt(op.type)} ${nm(op.b)}`, 'quadro');
    else if (op.k === 'unlink') this.log(team.id, p.name, `${p.name} cortou um fio`, 'quadro');
    else if (op.k === 'attach' && op.clue) this.log(team.id, p.name, `${p.name} prendeu uma prova num fio`, 'quadro');
    else if (op.k === 'detach') this.log(team.id, p.name, `${p.name} tirou uma prova de um fio (voltou para o quadro)`, 'quadro');
    else if (op.k === 'tag') this.log(team.id, p.name, op.tag ? `${p.name} marcou ${refName(op.ref)} como ${({ inocente: 'INOCENTE', suspeito: 'SUSPEITO', mentiu: 'MENTIU', alibi: 'TEM ÁLIBI' })[op.tag]}` : `${p.name} tirou a marca de ${refName(op.ref)}`, 'quadro');
    else if (op.k === 'move') p.lastAction = Date.now();
  }

  visibleClues(team, p) {
    const ids = new Set(team.found);
    if (p) for (const c of p.clues) ids.add(c);
    for (const card of team.board.cards) if (card.ref.startsWith('c:')) ids.add(card.ref.slice(2));
    for (const l of team.board.links) for (const x of proofsOf(l)) ids.add(x);
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
        // fios que saem junto com a carta devolvem as provas deles ao quadro (nada some)
        const gone = op.ref.startsWith('p:') ? b.links.filter((l) => l.a === op.ref.slice(2) || l.b === op.ref.slice(2)) : [];
        for (const gl of gone) proofsOf(gl).forEach((x, k) => this.returnToBoard(b, gl, x, p, k));
        b.links = b.links.filter((l) => !gone.includes(l));
        if (op.ref.startsWith('c:')) {
          const cid = op.ref.slice(2);
          for (const l of b.links) { l.proofs = proofsOf(l).filter((x) => x !== cid); l.evidence = l.proofs[0] || null; }
        }
        return true;
      }
      case 'link': {
        const a = String(op.a || ''); const bb = String(op.b || '');
        if (a === bb || b.links.length >= MAX_LINKS) return false;
        if (!b.cards.some((x) => x.ref === 'p:' + a) || !b.cards.some((x) => x.ref === 'p:' + bb)) return false;
        if (!allLinkTypes(c).some((t) => t.id === op.type)) return false;
        if (b.links.some((l) => l.a === a && l.b === bb && l.type === op.type)) return false;
        b.seq += 1;
        const color = LINK_COLORS.includes(op.color) ? op.color : 'vermelho';
        b.links.push({ id: 'l' + b.seq, a, b: bb, type: op.type, evidence: null, proofs: [], color, by: p.name });
        return true;
      }
      case 'recolor': {
        const l = b.links.find((x) => x.id === op.id);
        if (!l || !LINK_COLORS.includes(op.color)) return false;
        l.color = op.color;
        return true;
      }
      case 'retype': {
        const l = b.links.find((x) => x.id === op.id);
        if (!l || !allLinkTypes(c).some((t) => t.id === op.type)) return false;
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
        // um fio guarda até 3 provas (a rede de provas); a 4ª entra no lugar da mais antiga
        const l = b.links.find((x) => x.id === op.id);
        if (!l) return false;
        if (op.clue == null) {
          proofsOf(l).forEach((x, i) => this.returnToBoard(b, l, x, p, i));
          l.proofs = []; l.evidence = null; return true;
        }
        if (!this.visibleClues(team, p).has(op.clue)) return false;
        const list = proofsOf(l);
        if (list.includes(op.clue)) return false;
        list.push(op.clue);
        // passou de 3: a prova mais antiga sai do fio e VOLTA para o quadro (perto do fio)
        while (list.length > MAX_PROOFS) this.returnToBoard(b, l, list.shift(), p, 0);
        l.proofs = list;
        l.evidence = list[0];
        // a carta da pista sai do quadro e vai para o fio (não fica cópia solta)
        b.cards = b.cards.filter((c) => c.ref !== 'c:' + op.clue);
        return true;
      }
      case 'detach': {
        // tirar a prova do fio: a carta VOLTA para o quadro (perto do fio), nunca some
        const l = b.links.find((x) => x.id === op.id);
        if (!l) return false;
        const list = proofsOf(l);
        const n = list.length;
        l.proofs = list.filter((x) => x !== op.clue);
        l.evidence = l.proofs[0] || null;
        if (l.proofs.length !== n) this.returnToBoard(b, l, op.clue, p, 0);
        return l.proofs.length !== n;
      }
      case 'tag': {
        // etiqueta na carta da pessoa (INOCENTE, SUSPEITO, MENTIU, TEM ÁLIBI) ou null para tirar
        const card = b.cards.find((x) => x.ref === op.ref);
        if (!card) return false;
        if (op.tag != null && !CARD_TAGS.includes(op.tag)) return false;
        card.tag = op.tag || null;
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
      finished: !!t.finishedAt, voting: !!t.vote,
      submissions: t.submissions, score: t.bestScore,
      progress: t.lastResult ? t.lastResult.categories : null,
      cards: t.board.cards.length, links: t.board.links.length,
    }));
  }

  common() {
    return {
      code: this.code, phase: this.phase, now: Date.now(), endsAt: this.phaseEndsAt, solo: !!this.solo,
      startedAt: this.startedAt, settings: this.settings, teams: this.teamsSummary(),
      readyList: this.phase === 'briefing' ? [...this.players.values()].filter((p) => p.teamId).map((p) => ({
        id: p.id, name: p.name, team: p.teamId, ready: !!p.ready, online: !!p.sock,
      })) : null,
      countdown: this.phase === 'briefing' && !!this.phaseEndsAt,
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
      s.hotspots = (this.caseData.hotspots || []).filter((h) => (h.clue && team.found.has(h.clue)) || team.flags['hs:' + h.id]).map((h) => h.id);
      s.flags = team.flags;
      s.items = [...team.items];
      s.lockUntil = team.lockUntil;
      s.lastResult = team.lastResult;
      s.solved = !!team.solvedAt;
      s.finished = !!team.finishedAt;
      if (team.finishedAt) s.objectives = this.objectives(team.finalResult);
      const online = this.onlineOf(team);
      s.vote = team.vote ? {
        culprit: team.vote.culprit, by: team.vote.by, mine: team.vote.yes.includes(p.id),
        yes: team.vote.yes.length, need: online.length,
      } : null;
      s.teamsFinished = this.teams.filter((t) => t.finishedAt).length;
      s.teamsPlaying = this.teams.filter((t) => t.players.length > 0).length;
    }
    return s;
  }

  hostState() {
    const s = { t: 'state', ...this.common(), host: true };
    s.feed = this.feed.slice(-120);
    if (this.phase !== 'lobby') {
      const total = this.caseData.clues.length;
      const now = Date.now();
      s.insight = Object.fromEntries(this.teams.map((t) => {
        const r = validateBoard(this.caseData, t.board, t.lastCulprit);
        const cats = r.categories.filter((c) => c.id !== 'culpado');
        const edgesOk = cats.reduce((a, c) => a + c.found, 0);
        const edgesTotal = cats.reduce((a, c) => a + c.total, 0);
        const clues = this.visibleClues(t, null);
        for (const pid of t.players) { const pl = this.players.get(pid); if (pl) for (const c of pl.clues) clues.add(c); }
        return [t.id, {
          edgesOk, edgesTotal, cluesFound: clues.size, cluesTotal: total, items: t.items.size,
          // objetivos ao vivo (só o professor vê): partes da história já provadas no quadro
          cats: cats.map((c) => ({ label: c.label, status: c.status })),
          finished: !!t.finishedAt, voting: !!t.vote,
          culpritOk: t.finishedAt ? this.objectives(t.finalResult).primary : null,
          lockLeft: Math.max(0, Math.round((t.lockUntil - now) / 1000)),
          members: t.players.map((pid) => {
            const pl = this.players.get(pid);
            return { name: pl.name, online: !!pl.sock, idleSec: Math.round((now - (pl.lastAction || now)) / 1000), actions: pl.actions || 0 };
          }),
        }];
      }));
    }
    s.cases = [...this.cases.values()].filter((c) => (c.mode || 'multi') !== 'solo').map((c) => ({
      id: c.id, title: c.title, tagline: c.tagline, difficulty: c.difficulty, duration_sec: this.durationFor(c),
      cover_icon: c.cover_icon || '',
      people: (c.cards || []).filter((x) => x.kind === 'pessoa').length,
      places: (c.locations || []).length,
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
  const { solution, reveal, clues, hotspots, teacher_guide, ...rest } = c;
  // para cada tipo de ligação, só QUE tipos de carta ela liga (pessoa→lugar...), sem revelar quais cartas
  const kindOf = Object.fromEntries(c.cards.map((x) => [x.id, x.kind]));
  const pairs = {};
  for (const e of [...(solution.edges || []), ...(solution.traps || [])]) {
    const k = `${kindOf[e.from]}>${kindOf[e.to]}`;
    (pairs[e.type] = pairs[e.type] || new Set()).add(k);
  }
  const link_types = allLinkTypes(c).map((lt) => ({ ...lt, generic: lt.id.startsWith('g_'),
    pairs: lt.pairs ? lt.pairs : (pairs[lt.id] ? [...pairs[lt.id]] : []) }));
  return {
    ...rest,
    link_types,
    clue_count: clues.length,
    hotspots: (hotspots || []).map((h) => ({ id: h.id, object: h.object, label: h.label })),
    categories: solution.categories.map((x) => ({ id: x.id, label: x.label })),
    has_culprit: !!solution.culprit,
    culprit_question: solution.culprit_question || 'Quem é o responsável?',
  };
}

module.exports = { Room, publicCase, TEAM_PRESETS, allLinkTypes, GENERIC_LINKS };
