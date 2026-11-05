// Room-code WebSocket relay as a SQLite-backed Durable Object (Cloudflare Free plan).
// Protocol mirrors /workspace/droid-siege/relay/relay.js exactly.
// Hibernation-safe: per-socket meta lives in serializeAttachment; rooms are rebuilt from
// getWebSockets() on every wake so binary game packets still route after idle.
const MAX_PER_ROOM = 4;
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function sendJson(ws, obj) {
  try { ws.send(JSON.stringify(obj)); } catch (_) {}
}
function frame(num, payload) {
  const b = new Uint8Array(4 + payload.byteLength);
  new DataView(b.buffer).setInt32(0, num, true);
  b.set(payload instanceof Uint8Array ? payload : new Uint8Array(payload), 4);
  return b;
}
function asU8(message) {
  if (typeof message === 'string') return null;
  if (message instanceof Uint8Array) return message;
  if (message instanceof ArrayBuffer) return new Uint8Array(message);
  return new Uint8Array(message); // ArrayBufferView
}

export class RelayHub {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.rooms = new Map(); // rebuilt from attachments whenever needed
  }

  _rebuild() {
    this.rooms = new Map();
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() || {};
      if (!meta.code) continue;
      let room = this.rooms.get(meta.code);
      if (!room) {
        room = { code: meta.code, host: null, peers: new Map() };
        this.rooms.set(meta.code, room);
      }
      if (meta.id === 1) room.host = ws;
      else room.peers.set(meta.id, ws);
    }
  }

  async fetch(request) {
    this._rebuild();
    const url = new URL(request.url);
    if (url.pathname === '/health' || request.headers.get('Upgrade') !== 'websocket') {
      return new Response(`Droid Siege relay OK. rooms=${this.rooms.size}\n`, {
        status: 200,
        headers: { 'content-type': 'text/plain', 'access-control-allow-origin': '*' },
      });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ code: null, id: 0 });
    return new Response(null, { status: 101, webSocket: client });
  }

  newCode() {
    this._rebuild();
    for (let tries = 0; tries < 1000; tries++) {
      let c = '';
      for (let i = 0; i < 5; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
      if (!this.rooms.has(c)) return c;
    }
    throw new Error('no codes left');
  }
  newId(room) {
    let id;
    do { id = 2 + Math.floor(Math.random() * 2000000000); } while (room.peers.has(id));
    return id;
  }

  webSocketMessage(ws, message) {
    this._rebuild();
    const meta = ws.deserializeAttachment() || { code: null, id: 0 };
    if (typeof message === 'string') {
      let m;
      try { m = JSON.parse(message); } catch { return; }
      if (m.op === 'host' && !meta.code) {
        const code = this.newCode();
        const room = { code, host: ws, peers: new Map() };
        this.rooms.set(code, room);
        ws.serializeAttachment({ code, id: 1 });
        sendJson(ws, { op: 'hosted', code, id: 1 });
      } else if (m.op === 'join' && !meta.code) {
        const code = String(m.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
        const room = this.rooms.get(code);
        if (!room || !room.host) return sendJson(ws, { op: 'error', msg: `No room with code ${code}. Check the code with your host.` });
        if (room.peers.size + 1 >= MAX_PER_ROOM) return sendJson(ws, { op: 'error', msg: 'That squad is full (4 troopers max).' });
        const id = this.newId(room);
        room.peers.set(id, ws);
        ws.serializeAttachment({ code, id });
        sendJson(ws, { op: 'joined', code, id });
        sendJson(room.host, { op: 'peer_connected', id });
      } else if (m.op === 'kick' && meta.id === 1 && meta.code) {
        const room = this.rooms.get(meta.code);
        const p = room && room.peers.get(m.id);
        if (p) try { p.close(4000, 'kicked'); } catch (_) {}
      } else if (m.op === 'ping') {
        sendJson(ws, { op: 'pong' });
      }
      return;
    }
    const data = asU8(message);
    if (!meta.code || !data || data.length < 4) return;
    const room = this.rooms.get(meta.code);
    if (!room || !room.host) return;
    const target = new DataView(data.buffer, data.byteOffset, data.byteLength).getInt32(0, true);
    const payload = data.subarray(4);
    if (meta.id !== 1) {
      try { room.host.send(frame(meta.id, payload)); } catch (_) {}
      return;
    }
    const out = frame(1, payload);
    if (target > 0) {
      const p = room.peers.get(target);
      if (p) try { p.send(out); } catch (_) {}
    } else {
      for (const [id, p] of room.peers) {
        if (target < 0 && id === -target) continue;
        try { p.send(out); } catch (_) {}
      }
    }
  }

  webSocketClose(ws, _code, _reason, _wasClean) {
    this._onDrop(ws);
  }
  webSocketError(ws, _error) {
    this._onDrop(ws);
  }
  _onDrop(ws) {
    this._rebuild();
    const meta = ws.deserializeAttachment() || {};
    if (!meta.code) return;
    const room = this.rooms.get(meta.code);
    if (!room) return;
    if (meta.id === 1) {
      for (const p of room.peers.values()) {
        sendJson(p, { op: 'error', msg: 'The host left the game.' });
        try { p.close(); } catch (_) {}
      }
      this.rooms.delete(meta.code);
    } else {
      room.peers.delete(meta.id);
      if (room.host) sendJson(room.host, { op: 'peer_disconnected', id: meta.id });
    }
  }
}
