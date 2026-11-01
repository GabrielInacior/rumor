'use strict';
const { checkName } = require('./namefilter');
// Servidor do RUMOR: entrega o jogo exportado (pasta public/) e roda as salas por WebSocket em /ws.
// Um único processo, sem banco: a sala vive na memória enquanto a aula acontece.
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { WebSocketServer } = require('ws');
const { Room } = require('./room');

const PORT = Number(process.env.PORT) || 8080;
const PUBLIC = process.env.RUMOR_PUBLIC || path.join(__dirname, '..', 'public');
const CASES_DIR = process.env.RUMOR_CASES || path.join(__dirname, '..', 'cases');

function loadCases() {
  const map = new Map();
  if (!fs.existsSync(CASES_DIR)) return map;
  for (const f of fs.readdirSync(CASES_DIR).filter((x) => x.endsWith('.json')).sort()) {
    try {
      const c = JSON.parse(fs.readFileSync(path.join(CASES_DIR, f), 'utf8'));
      map.set(c.id, c);
    } catch (e) {
      console.error(`[casos] ${f} inválido: ${e.message}`);
    }
  }
  return map;
}

const cases = loadCases();
const rooms = new Map();

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json',
  '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json', '.css': 'text/css',
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, rooms: rooms.size, cases: [...cases.keys()] }));
    return;
  }
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/') rel = '/index.html';
  const file = path.normalize(path.join(PUBLIC, rel));
  if (!file.startsWith(path.normalize(PUBLIC))) { res.writeHead(403); res.end(); return; }
  fs.stat(file, (err, st) => {
    const ext = path.extname(file).toLowerCase();
    // na hospedagem só vão os .gz (repositório menor); entrega o comprimido mesmo sem o original
    if ((err || !st.isFile()) && fs.existsSync(file + '.gz')) {
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream', 'Content-Encoding': 'gzip', 'Cache-Control': 'public, max-age=300' });
      fs.createReadStream(file + '.gz').pipe(res);
      return;
    }
    if (err || !st.isFile()) { res.writeHead(404); res.end('não encontrado'); return; }
    const headers = {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      // HTML sempre fresco (pega build novo); o resto pode ficar em cache curto
      'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=300',
    };
    // wasm/pck/js comprimidos: o Wi-Fi da escola agradece (o motor tem ~35 MB)
    const gz = file + '.gz';
    if (/\bgzip\b/.test(req.headers['accept-encoding'] || '') && ['.wasm', '.pck', '.js'].includes(ext) && fs.existsSync(gz)) {
      headers['Content-Encoding'] = 'gzip';
      res.writeHead(200, headers);
      fs.createReadStream(gz).pipe(res);
      return;
    }
    res.writeHead(200, headers);
    fs.createReadStream(file).pipe(res);
  });
});

const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 64 * 1024 });

function send(sock, obj) {
  if (sock && sock.readyState === 1) sock.send(JSON.stringify(obj));
}

function newCode() {
  for (let i = 0; i < 1000; i++) {
    const c = String(Math.floor(1000 + Math.random() * 9000));
    if (!rooms.has(c)) return c;
  }
  throw new Error('sem códigos livres');
}

wss.on('connection', (sock) => {
  sock.isAlive = true;
  sock.on('pong', () => { sock.isAlive = true; });
  sock.on('message', (data) => {
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    if (!msg || typeof msg.t !== 'string') return;
    try {
      handle(sock, msg);
    } catch (e) {
      console.error('[ws] erro tratando', msg.t, e);
    }
  });
  sock.on('close', () => { if (sock.room) sock.room.drop(sock); });
});

const modeOf = (c) => c.mode || 'multi';

function handle(sock, msg) {
  if (msg.t === 'ping') { send(sock, { t: 'pong', now: Date.now() }); return; }
  if (msg.t === 'list_cases') {
    // lista pública (sem solução) para a tela de escolha do modo solo
    send(sock, { t: 'cases', cases: [...cases.values()].map((c) => ({
      id: c.id, title: c.title, tagline: c.tagline, difficulty: c.difficulty, duration_sec: c.duration_sec, mode: modeOf(c),
      // capa do arquivo: um OBJETO do caso (nunca uma pessoa, para não dar pista)
      cover_icon: c.cover_icon || '',
      place: ((c.cards || []).find((x) => x.kind === 'lugar') || {}).name || '',
      people: (c.cards || []).filter((x) => x.kind === 'pessoa').length,
    })) });
    return;
  }
  if (msg.t === 'solo_start') {
    // modo solo: uma sala particular, sem professor, com uma equipe de um aluno só, que começa na hora
    const c = cases.get(String(msg.caseId));
    if (!c) { send(sock, { t: 'error', msg: 'Caso não encontrado.' }); return; }
    const room = new Room(newCode(), cases, send);
    room.solo = true;
    room.settings.caseId = c.id;
    room.settings.teamCount = 1;
    room.settings.penaltySec = 20;
    room.makeTeams();
    rooms.set(room.code, room);
    const r = room.join(sock, msg.name || 'Detetive');
    send(sock, { t: 'joined', code: room.code, pid: r.player.id, secret: r.player.secret, name: r.player.name, solo: true });
    room.startRound();
    room.broadcast();
    return;
  }
  if (msg.t === 'host_create') {
    if (cases.size === 0) { send(sock, { t: 'error', msg: 'Nenhum caso instalado no servidor.' }); return; }
    const room = new Room(newCode(), cases, send);
    rooms.set(room.code, room);
    room.attachHost(sock);
    send(sock, { t: 'hosted', code: room.code, hostSecret: room.hostSecret });
    room.sendGuide();
    room.broadcast();
    return;
  }
  if (msg.t === 'host_resume') {
    const room = rooms.get(String(msg.code));
    if (!room || room.hostSecret !== msg.hostSecret) { send(sock, { t: 'resume_failed' }); return; }
    room.attachHost(sock);
    send(sock, { t: 'hosted', code: room.code, hostSecret: room.hostSecret });
    room.sendGuide();
    if (room.phase !== 'lobby') send(sock, { t: 'case', case: require('./room').publicCase(room.caseData) });
    if (room.phase === 'reveal') send(sock, { t: 'reveal', reveal: room.revealData() });
    room.broadcast();
    return;
  }
  if (msg.t === 'join') {
    const room = rooms.get(String(msg.code));
    if (!room) { send(sock, { t: 'error', msg: 'Sala não encontrada. Confira o código.' }); return; }
    // nome digitado pelo aluno: filtro de palavrão e termo sexual (o servidor tem a palavra final)
    const chk = checkName(msg.name);
    if (!chk.ok) { send(sock, { t: 'error', msg: chk.msg, field: 'name' }); return; }
    const r = room.join(sock, chk.name);
    if (r.error) { send(sock, { t: 'error', msg: r.error, field: 'name' }); return; }
    send(sock, { t: 'joined', code: room.code, pid: r.player.id, secret: r.player.secret, name: r.player.name, rejoined: !!r.rejoined });
    if (room.phase !== 'lobby') send(sock, { t: 'case', case: require('./room').publicCase(room.caseData) });
    room.broadcast();
    return;
  }
  if (msg.t === 'resume') {
    const room = rooms.get(String(msg.code));
    if (!room || !room.resume(sock, msg.pid, msg.secret)) { send(sock, { t: 'resume_failed' }); return; }
    const p = room.players.get(msg.pid);
    send(sock, { t: 'joined', code: room.code, pid: p.id, secret: p.secret, name: p.name });
    if (room.phase !== 'lobby') send(sock, { t: 'case', case: require('./room').publicCase(room.caseData) });
    if (room.phase === 'reveal') send(sock, { t: 'reveal', reveal: room.revealFor(p) });
    room.broadcast();
    return;
  }
  const room = sock.room;
  if (!room) return;
  if (msg.t.startsWith('host_')) {
    if (sock.role === 'host') room.hostCmd(msg);
    return;
  }
  // aluno saiu pelo botão: fica marcado como fora (pode voltar pelo mesmo nome) e não segura
  // a chamada de prontos nem a votação da equipe
  if (msg.t === 'leave' && sock.role === 'player') {
    room.drop(sock);
    sock.room = null; sock.role = null; sock.pid = null;
    return;
  }
  if (sock.role === 'player') room.playerCmd(sock, msg);
}

// relógio das salas + limpeza de conexões mortas (celular que apagou a tela) e salas velhas
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    room.tick(now);
    if (now - room.touched > 4 * 3600 * 1000) rooms.delete(code);
  }
}, 500);
setInterval(() => {
  for (const s of wss.clients) {
    if (!s.isAlive) { s.terminate(); continue; }
    s.isAlive = false;
    s.ping();
  }
}, 15000);

function lanAddresses() {
  return Object.values(os.networkInterfaces()).flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
}

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`RUMOR no ar. Casos: ${[...cases.keys()].join(', ') || '(nenhum)'}`);
    console.log(`  Neste computador: http://localhost:${PORT}`);
    for (const ip of lanAddresses()) console.log(`  Na rede da escola: http://${ip}:${PORT}`);
  });
}

module.exports = { server, rooms, cases };
