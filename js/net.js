// Multiplayer link to server.py (WebSocket at /ws). Served by a plain static server, the game simply stays solo.
const handlers = {};
const rosterListeners = [];
let ws = null, playing = false, everOnline = false;

export const Net = {
  id: null, hostId: null, roster: [], online: false, name: '',
  on(type, fn) { handlers[type] = fn; },
  onRoster(fn) { rosterListeners.push(fn); },
  send(m) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(m)); },
  setPlaying(b) { playing = b; Net.send({ t: 'state', playing: b }); },
  setName(n) { Net.name = n; Net.send({ t: 'name', name: n }); },
  others() { return Net.roster.filter(p => p.id !== Net.id); },
  othersPlaying() { return Net.others().some(p => p.playing); },
  // a guest mirrors the host's world instead of simulating it
  isGuest() { return Net.online && Net.hostId != null && Net.hostId !== Net.id; },
  connect,
};

function connect() {
  if (!/^https?:$/.test(location.protocol)) return;
  if (!everOnline) { // only server.py has /ws; asking first avoids a console error on plain static servers
    fetch(location.pathname, { method: 'HEAD', cache: 'no-store' })
      .then(r => { if (r.headers.get('X-Beans-Multiplayer')) open(); }).catch(() => {});
    return;
  }
  open();
}
function open() {
  try { ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'); } catch (e) { return; }
  ws.onmessage = e => {
    let m; try { m = JSON.parse(e.data); } catch (err) { return; }
    if (m.t === 'hello') { Net.id = m.id; Net.online = everOnline = true; Net.send({ t: 'join', name: Net.name, playing }); return; }
    if (m.t === 'roster') { Net.roster = m.players; Net.hostId = m.host; rosterListeners.forEach(f => f()); return; }
    const h = handlers[m.t]; if (h) h(m);
  };
  ws.onclose = () => {
    const was = Net.online;
    Object.assign(Net, { online: false, id: null, hostId: null, roster: [] });
    if (was) rosterListeners.forEach(f => f());
    if (everOnline) setTimeout(connect, 3000); // server restarted: try again
  };
}
