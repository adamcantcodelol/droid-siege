// Droid Siege room-code relay. Tiny WebSocket server: the host creates a room and gets a
// short code; joiners type the code. Game packets are forwarded between the host (peer 1)
// and the joiners. No game logic runs here; the host stays authoritative.
//
// Frames:  text = JSON control messages, binary = [int32 LE target/from][payload]
//   client -> relay control: {op:"host"} | {op:"join", code} | {op:"kick", id}
//   relay -> client control: {op:"hosted", code, id:1} | {op:"joined", code, id}
//                            {op:"peer_connected", id} | {op:"peer_disconnected", id}
//                            {op:"error", msg}
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.PORT || '9080', 10);
const MAX_PER_ROOM = parseInt(process.env.MAX_PER_ROOM || '4', 10);
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I confusion
const rooms = new Map(); // code -> {host: ws, peers: Map<id, ws>}

function newCode() {
  for (let tries = 0; tries < 1000; tries++) {
    let c = '';
    for (let i = 0; i < 5; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
  throw new Error('no codes left');
}
function newId(room) {
  let id;
  do { id = 2 + Math.floor(Math.random() * 2000000000); } while (room.peers.has(id));
  return id;
}
function sendJson(ws, obj) { if (ws.readyState === 1) ws.send(JSON.stringify(obj)); }
function frame(num, payload) {
  const b = Buffer.allocUnsafe(4 + payload.length);
  b.writeInt32LE(num, 0);
  payload.copy(b, 4);
  return b;
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'content-type': 'text/plain', 'access-control-allow-origin': '*' });
  res.end(`Droid Siege relay OK. rooms=${rooms.size}\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 1 << 20 });

wss.on('connection', (ws) => {
  ws.room = null; ws.id = 0; ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', (data, isBinary) => {
    if (!isBinary) {
      let m; try { m = JSON.parse(data.toString()); } catch { return; }
      if (m.op === 'host' && !ws.room) {
        const code = newCode();
        const room = { code, host: ws, peers: new Map() };
        rooms.set(code, room);
        ws.room = room; ws.id = 1;
        sendJson(ws, { op: 'hosted', code, id: 1 });
        console.log(`room ${code} created (${rooms.size} rooms)`);
      } else if (m.op === 'join' && !ws.room) {
        const code = String(m.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
        const room = rooms.get(code);
        if (!room) return sendJson(ws, { op: 'error', msg: `No room with code ${code}. Check the code with your host.` });
        if (room.peers.size + 1 >= MAX_PER_ROOM) return sendJson(ws, { op: 'error', msg: 'That squad is full (4 troopers max).' });
        const id = newId(room);
        room.peers.set(id, ws);
        ws.room = room; ws.id = id;
        sendJson(ws, { op: 'joined', code, id });
        sendJson(room.host, { op: 'peer_connected', id });
      } else if (m.op === 'kick' && ws.room && ws.id === 1) {
        const p = ws.room.peers.get(m.id);
        if (p) p.close(4000, 'kicked');
      }
      return;
    }
    const room = ws.room;
    if (!room || data.length < 4) return;
    const target = data.readInt32LE(0);
    const payload = data.subarray(4);
    if (ws.id !== 1) {
      // joiners only talk to the host (Godot's server relay forwards client<->client RPCs)
      if (room.host.readyState === 1) room.host.send(frame(ws.id, payload));
      return;
    }
    const out = frame(1, payload);
    if (target > 0) {
      const p = room.peers.get(target);
      if (p && p.readyState === 1) p.send(out);
    } else {
      for (const [id, p] of room.peers) {
        if (target < 0 && id === -target) continue;
        if (p.readyState === 1) p.send(out);
      }
    }
  });
  ws.on('close', () => {
    const room = ws.room;
    if (!room) return;
    if (ws.id === 1) {
      for (const p of room.peers.values()) { sendJson(p, { op: 'error', msg: 'The host left the game.' }); p.close(); }
      rooms.delete(room.code);
      console.log(`room ${room.code} closed (${rooms.size} rooms)`);
    } else {
      room.peers.delete(ws.id);
      sendJson(room.host, { op: 'peer_disconnected', id: ws.id });
    }
  });
});

// keep connections alive through proxies / detect dead sockets
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false; ws.ping();
  }
}, 25000);

server.listen(PORT, () => console.log(`Droid Siege relay listening on :${PORT}`));
