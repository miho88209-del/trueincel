'use strict';
(() => {
// ---------- constants ----------
const W = 1280, H = 720;
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
const lightC = document.createElement('canvas'); lightC.width = W; lightC.height = H;
const lctx = lightC.getContext('2d');
const qs = new URLSearchParams(location.search);
const SPEED = Math.max(0.1, Math.min(60, parseFloat(qs.get('speed')) || 1)); // test hook: ?speed=10

const NIGHT_LEN = 540;          // seconds of real time from sunset (7 PM) to sunrise (6 AM)
const WORLD_W = 3400;
const BASE_Y = 590;
const CAMP_X = 1100;
const HORSE_X = 900;
const WASH_L = 1880, WASH_R = 2170;
const WAGON_X = 2900;
const LEFT_WALL = 200, RIGHT_WALL = 3200;
const MAX_WOOD = 4;

// ---------- utils ----------
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const rand = (a, b) => a + Math.random() * (b - a);
const pick = arr => arr[(Math.random() * arr.length) | 0];
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function hex(h) { const n = parseInt(h.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; }
function mix(c1, c2, t) { return [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)]; }
function rgb(c, a = 1) { return `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`; }
function groundY(x) {
  if (x > WASH_L && x < WASH_R) { const u = (x - WASH_L) / (WASH_R - WASH_L); return BASE_Y + 48 * Math.sin(u * Math.PI) ** 0.8; }
  return BASE_Y;
}
const inWash = x => x > WASH_L + 25 && x < WASH_R - 25;

// ---------- palettes ----------
const SKY = [
  [0,   '#3a3f7a', '#e0705a', '#ffc27a'],
  [90,  '#262a5c', '#b8485a', '#f08a4a'],
  [170, '#171c38', '#4a3450', '#7a4040'],
  [240, '#0d1224', '#1a2036', '#262a3c'],
  [470, '#0d1224', '#1a2036', '#262a3c'],
  [505, '#202a52', '#6a5478', '#c08070'],
  [540, '#5a7ab8', '#f0a080', '#ffd890'],
].map(k => [k[0], hex(k[1]), hex(k[2]), hex(k[3])]);
function skyAt(t) {
  for (let i = 0; i < SKY.length - 1; i++) {
    const a = SKY[i], b = SKY[i + 1];
    if (t <= b[0]) { const u = smooth(a[0], b[0], t); return [mix(a[1], b[1], u), mix(a[2], b[2], u), mix(a[3], b[3], u)]; }
  }
  const l = SKY[SKY.length - 1]; return [l[1], l[2], l[3]];
}

// ---------- landscape (seeded, static) ----------
function makeLayer(seed, par, opts) {
  const r = mulberry32(seed), step = 4;
  const len = W + WORLD_W * par + 200;
  const n = Math.ceil(len / step) + 2;
  const h = new Float32Array(n);
  for (let i = 0; i < n; i++) h[i] = opts.base + Math.sin(i * 0.013 + seed) * 8 + Math.sin(i * 0.051) * 4;
  const addFeature = (cx, topW, height, cliff, talus) => {
    for (let i = 0; i < n; i++) {
      const d = Math.abs(i * step - cx);
      let v;
      if (d < topW / 2) v = height;
      else if (d < topW / 2 + cliff) v = height - (d - topW / 2) / cliff * height * 0.45;
      else v = height * 0.55 * Math.exp(-(d - topW / 2 - cliff) / talus);
      if (v > h[i]) h[i] = v;
    }
  };
  let x = -50;
  while (x < len) {
    const kind = r();
    if (kind < 0.62) { const tw = rand2(r, 90, 320); addFeature(x + tw / 2, tw, rand2(r, opts.min, opts.max), rand2(r, 8, 22), rand2(r, 30, 70)); x += tw + rand2(r, 40, 200); }
    else if (kind < 0.8) { addFeature(x + 10, rand2(r, 10, 26), rand2(r, opts.max * 0.7, opts.max * 1.1), 6, 25); x += rand2(r, 60, 160); }
    else x += rand2(r, 80, 220);
  }
  (opts.extra || []).forEach(f => addFeature(f[0], f[1], f[2], f[3], f[4]));
  for (let i = 0; i < n; i++) h[i] += (r() - 0.5) * 2.2;
  const strata = [];
  for (let k = 0; k < 9; k++) strata.push([rand2(r, 0.05, 0.95), rand2(r, 2, 7), r() < 0.5]);
  return { h, step, par, len, strata, ...opts };
}
function rand2(r, a, b) { return a + r() * (b - a); }

const LAYERS = [
  makeLayer(11, 0.1, { base: 30, min: 70, max: 150, y: 470, dusk: hex('#c97a68'), night: hex('#2a2a48'), rim: hex('#ffb070') }),
  makeLayer(23, 0.28, { base: 20, min: 110, max: 250, y: 520, dusk: hex('#a84a38'), night: hex('#1d1a34'), rim: hex('#ff9a50'),
    extra: [[560, 150, 300, 10, 40]] }),
  makeLayer(37, 0.55, { base: 10, min: 60, max: 190, y: 575, dusk: hex('#7c2e22'), night: hex('#140f22'), rim: hex('#ff8040') }),
];
// Coffin Rock: the canyon's signature butte, plus a natural arch on the mid layer.
const LANDMARKS = { coffinX: 560, archX: 1150 };

// static scatter
const SCATTER = (() => {
  const r = mulberry32(99);
  const grass = [], rocks = [], saguaros = [], fg = [];
  for (let x = LEFT_WALL - 40; x < RIGHT_WALL + 40; x += 9 + r() * 14) grass.push({ x, h: 8 + r() * 18, ph: r() * 6.28, n: 3 + (r() * 3 | 0), c: r() });
  for (let x = LEFT_WALL; x < RIGHT_WALL; x += 40 + r() * 120) rocks.push({ x, w: 6 + r() * 16, h: 4 + r() * 9 });
  for (let x = 150; x < WORLD_W * 0.85; x += 260 + r() * 420) saguaros.push({ x, h: 50 + r() * 50, arms: r() });
  for (let x = 0; x < WORLD_W * 1.2; x += 220 + r() * 300) fg.push({ x, w: 60 + r() * 120, h: 20 + r() * 40 });
  return { grass, rocks, saguaros, fg };
})();

// ---------- state ----------
let G = null;
let mode = 'title'; // title | play | paused | won | lost
const keys = {}; const pressed = {};

function newGame() {
  G = {
    t: 0, camX: CAMP_X - W / 2, wind: 0.3, storm: 0, dark: 0, night: 0, flash: 0, gust: 0, bolt: null,
    p: { x: CAMP_X + 70, face: 1, walk: 0, moving: false, running: false, crouch: false,
      wood: 0, weeds: 0, can: { heat: 0, half: false }, cup: true, hat: true, blanket: false, matches: 2, jerky: 0, pears: 0, letters: true,
      warmth: 100, belly: 70, say: null, sayT: 0, gassy: 0, tootT: 0, petCD: 0, bellyWarned: false },
    fire: { x: CAMP_X, fuel: 45, lit: true, can: null, flare: 0, ember: 0 },
    horse: { x: HORSE_X, state: 'idle', t: 0, face: 1, gassy: 0, tootT: 0, rear: 0, awayT: 0, walk: 0, bubble: null },
    rac: { x: -999, state: 'hidden', t: 0, face: 1, cd: 0, side: 1, loot: null },
    cupObj: null, hatObj: null, groundCan: null,
    woods: [
      { x: 250, n: 2, kind: 'pile' }, { x: 420, n: 3, kind: 'pile' }, { x: 690, n: 2, kind: 'pile' }, { x: 1460, n: 4, kind: 'tree' },
      { x: 1700, n: 2, kind: 'pile' }, { x: 2360, n: 3, kind: 'pile' }, { x: 2620, n: 2, kind: 'pile' },
    ],
    cacti: [{ x: 300, n: 2 }, { x: 1580, n: 2 }, { x: 2500, n: 1 }],
    wagon: { x: WAGON_X, searched: false, boards: 4 },
    weedsOut: [], toasts: [], parts: [], rain: [], later: [],
    timers: { lightning: 150, gust: 215, flood: 240, weed: 6, music: 0, crackle: 0 },
    flood: { state: 'none', t: 0, level: 0 },
    gustS: { state: 'none', t: 0 },
    stats: { logs: 0, matches: 0, swept: 0, hats: 0, cups: 0, pets: 0, toots: 0, beans: 'never opened (coward)' },
    tut: { moved: false, gathered: false, fed: false, beans: false },
    beats: {}, musicStep: 0, lose: null,
  };
  toast('Sundown in Coffin Rock Canyon. One can of beans. One horse. One very long night.', '#ffd9a0', 7);
}

// ---------- messaging ----------
function toast(text, color = '#f3e2c2', dur = 5) {
  if (!G) return;
  G.toasts.push({ text, color, t: 0, dur });
  if (G.toasts.length > 4) G.toasts.shift();
}
function say(text, dur = 2.8) { G.p.say = text; G.p.sayT = dur; }
function later(dt, fn) { G.later.push({ at: G.t + dt, fn }); }
function beat(name) { if (G.beats[name]) return false; G.beats[name] = true; return true; }

// ---------- particles ----------
function addPart(o) { if (G.parts.length < 500) G.parts.push(o); }
function puff(x, y, color, n = 10, spread = 40) {
  for (let i = 0; i < n; i++) addPart({ x, y, vx: rand(-spread, spread), vy: rand(-spread, 5), life: rand(0.6, 1.4), t: 0, r: rand(5, 12), color, kind: 'puff' });
}
function sparks(x, y, n = 12) {
  for (let i = 0; i < n; i++) addPart({ x, y, vx: rand(-80, 80) + G.wind * 40, vy: rand(-220, -60), life: rand(0.6, 1.6), t: 0, r: rand(1, 2.5), kind: 'spark' });
}

// ---------- beans ----------
function canState(c) { return c.heat < 40 ? 'cold' : c.heat < 100 ? 'warm' : c.heat < 190 ? 'HOT' : 'burnt'; }
function eatCan(c, where) {
  const st = canState(c);
  let food = { cold: 30, warm: 45, HOT: 70, burnt: 40 }[st]; let warm = { cold: 0, warm: 8, HOT: 25, burnt: 10 }[st];
  if (c.half) { food *= 0.5; warm *= 0.5; }
  const p = G.p;
  p.belly = clamp(p.belly + food, 0, 100); p.warmth = clamp(p.warmth + warm, 0, 100);
  p.gassy = 150; p.tootT = rand(10, 16);
  Sound.eat();
  const lines = {
    cold: ['Cold beans. Straight from the can. Like an animal.', 'Tastes like tin and regret.'],
    warm: ['Lukewarm. Like a handshake from a banker.', 'Not hot. Not bad. Not good.'],
    HOT: ['Hot beans! The finest meal in the territory.', 'Lord, that\'s the stuff.'],
    burnt: ['Charcoal with a hint of bean.', 'Crunchy. Beans shouldn\'t be crunchy.'],
  }[st];
  say(pick(lines), 3.5);
  G.stats.beans = (c.half ? 'half-eaten (raccoon-seasoned), ' : '') + 'eaten ' + (st === 'HOT' ? 'piping HOT' : st) + ' by you' + (where === 'pack' ? ', straight from the can' : '');
  toast(`Ate the beans (${st}${c.half ? ', half' : ''}). Belly +${Math.round(food)}. Your insides are now a weather system.`, '#ffd27a');
}

// ---------- actions ----------
function getActions() {
  const p = G.p, f = G.fire, acts = [];
  const add = (key, label, x, fn, dist) => acts.push({ key, label, fn, d: dist !== undefined ? dist : Math.abs(p.x - x) });
  const df = Math.abs(p.x - f.x);
  const hasFuel = p.wood > 0 || p.weeds > 0;
  if (df < 85) {
    if (!f.lit) {
      if (p.matches > 0 && (hasFuel || f.fuel > 5)) add('E', `Strike a match (${p.matches} left) — crouch [S] in rain`, f.x, relight);
      else if (p.matches > 0) add('E', 'Need wood before you strike a match', f.x, null);
      else add('E', 'No matches... the wagon east might have some', f.x, null);
    } else if (hasFuel && f.fuel < 96) add('E', p.wood > 0 ? 'Feed the fire (log)' : 'Feed the fire (tumbleweed)', f.x, feedFire);
    else if (!hasFuel && p.letters && f.fuel < 30) add('E', "Burn Mabel's love letters", f.x, burnLetters);
    if (p.can && !f.can) add('B', 'Heat your last can of beans', f.x, placeBeans);
    if (f.can) add('F', `Eat the beans (${canState(f.can)})`, f.x, () => { const c = f.can; f.can = null; eatCan(c, 'fire'); });
  }
  for (const w of G.woods) {
    if (w.n > 0 && Math.abs(p.x - w.x) < 60) {
      if (p.wood < MAX_WOOD) add('E', w.kind === 'tree' ? `Snap off a branch (${w.n} left)` : `Gather deadwood (${w.n} left)`, w.x, () => { w.n--; p.wood++; G.tut.gathered = true; Sound.wood(); puff(w.x, groundY(w.x) - 10, [120, 90, 60], 5, 30); if (p.wood === MAX_WOOD) say('Arms full. Back to the fire.'); });
      else add('E', 'Arms full (4/4) — feed the fire first', w.x, null);
    }
  }
  for (const c of G.cacti) {
    if (c.n > 0 && Math.abs(p.x - c.x) < 55) add('E', 'Pick a prickly pear (ow)', c.x, () => { c.n--; p.pears++; p.warmth = Math.max(1, p.warmth - 2); Sound.ouch(); say(pick(['Ow. Worth it.', 'Ow! Delicious? Ow.', 'Nature\'s pin cushion.'])); });
  }
  const wg = G.wagon;
  if (Math.abs(p.x - wg.x) < 100) {
    if (!wg.searched) add('E', 'Search the abandoned wagon', wg.x, () => {
      wg.searched = true; p.blanket = true; p.matches += 3; p.jerky += 1; Sound.pickup();
      toast('Found: a moth-eaten blanket (less cold), 3 matches, and jerky of uncertain species.', '#ffd27a', 6);
      say('Sorry, Doc. You won\'t be needin\' these.');
    });
    else if (wg.boards > 0 && p.wood < MAX_WOOD) add('E', `Pry off wagon boards (${wg.boards} left)`, wg.x, () => { wg.boards--; p.wood++; Sound.wood(); puff(wg.x, BASE_Y - 30, [130, 100, 70], 6, 40); });
  }
  const h = G.horse;
  if (Math.abs(p.x - h.x) < 75 && p.petCD <= 0) add('E', 'Pet Biscuit', h.x, () => {
    p.petCD = 6; G.stats.pets++; p.warmth = clamp(p.warmth + 4, 0, 100); Sound.snort();
    say(pick(['Good boy, Biscuit.', 'You\'re warmer than my prospects.', 'Who\'s a noble steed? Not you. But still.', 'Don\'t look at me like that.']));
  });
  if (G.cupObj && G.cupObj.landed && Math.abs(p.x - G.cupObj.x) < 50 && G.rac.state !== 'play') add('E', 'Pick up your tin cup', G.cupObj.x, () => { G.cupObj = null; p.cup = true; Sound.clink(); });
  if (G.hatObj && G.hatObj.landed && Math.abs(p.x - G.hatObj.x) < 50) add('E', 'Grab your hat', G.hatObj.x, () => { G.hatObj = null; p.hat = true; Sound.hat(); say('Hat\'s back. Dignity... partially restored.'); });
  if (G.groundCan && Math.abs(p.x - G.groundCan.x) < 50) add('E', 'Pick up the beans', G.groundCan.x, () => { p.can = G.groundCan.can; G.groundCan = null; Sound.pickup(); });
  for (const tw of G.weedsOut) if (!tw.dead && Math.abs(p.x - tw.x) < 60) add('E', 'Grab the tumbleweed (kindling)', tw.x, () => { tw.dead = true; p.weeds++; Sound.pickup(); say(pick(['Gotcha, you drifter.', 'Free firewood, delivered by the wind.'])); });
  if (p.cup) add('C', 'Throw tin cup', p.x, throwCup, 999);
  if (!f.can || df >= 85) {
    if (p.can && p.belly < 60) add('F', `Eat beans from the can (${canState(p.can)})`, p.x, () => { const c = p.can; p.can = null; eatCan(c, 'pack'); }, 998);
    else if (p.jerky > 0) add('F', 'Chew mystery jerky', p.x, () => { p.jerky--; p.belly = clamp(p.belly + 30, 0, 100); Sound.eat(); say(pick(['Tastes like... saddle?', 'Best not to ask what it was.'])); }, 998);
    else if (p.pears > 0) add('F', 'Eat a prickly pear', p.x, () => { p.pears--; p.belly = clamp(p.belly + 14, 0, 100); Sound.eat(); say('Sweet. Spiny. Mostly spiny.'); }, 998);
  }
  return acts;
}

function feedFire() {
  const p = G.p, f = G.fire;
  if (p.wood > 0) { p.wood--; f.fuel = Math.min(100, f.fuel + 25); G.stats.logs++; }
  else { p.weeds--; f.fuel = Math.min(100, f.fuel + 14); }
  G.tut.fed = true; f.flare = 1; Sound.feed(); sparks(f.x, groundY(f.x) - 20, 18);
}
function burnLetters() {
  const p = G.p, f = G.fire; p.letters = false; f.fuel = Math.min(100, f.fuel + 18); f.flare = 1; Sound.feed(); sparks(f.x, BASE_Y - 20, 25);
  say('Goodbye, Mabel. You burned bright. So do your letters.', 4);
}
function relight() {
  const p = G.p, f = G.fire;
  p.matches--; G.stats.matches++; Sound.match();
  const failChance = p.crouch ? 0 : G.storm * 0.65;
  if (Math.random() < failChance) {
    Sound.fizzle(); puff(f.x, BASE_Y - 30, [150, 150, 160], 6, 20);
    toast(`Fssst. The rain ate your match. Crouch [S] to shield the next one. (${p.matches} left)`, '#ff9a6a');
    return;
  }
  if (f.fuel < 5) { if (p.wood > 0) { p.wood--; f.fuel = 25; G.stats.logs++; } else { p.weeds--; f.fuel = 14; } }
  f.lit = true; f.flare = 1; sparks(f.x, BASE_Y - 20, 20); Sound.feed();
  say(pick(['Let there be fire.', 'Still got it.', 'Burn, baby. Burn.']));
}
function placeBeans() {
  const p = G.p; G.fire.can = p.can; p.can = null; G.tut.beans = true; Sound.clink();
  say('Supper\'s on. Don\'t wander off.', 3);
  if (beat('beansHint')) toast('Beans heat on the fire. Hot beans fill you and warm you. But they smell. Mighty good.', '#ffd27a', 6);
}
function throwCup() {
  const p = G.p; p.cup = false; G.stats.cups++;
  G.cupObj = { x: p.x + p.face * 14, y: groundY(p.x) - 50, vx: p.face * 330 + (p.running ? p.face * 100 : 0), vy: -260, rot: 0, landed: false };
  Sound.hat();
  say(pick(['Fetch!', 'Go get it, varmint!', 'Shiny thing! Look!']), 2);
}

// ---------- update ----------
function update(dt) {
  G.t += dt;
  const t = G.t, p = G.p, f = G.fire;
  // environment
  G.storm = smooth(115, 200, t) * (1 - smooth(470, 525, t));
  G.night = smooth(70, 230, t) * (1 - smooth(485, 540, t));
  G.dark = 0.08 + 0.74 * G.night;
  G.wind = 0.2 + G.storm * 0.9 + G.gust * 1.6 + Math.sin(t * 0.7) * 0.15 * (0.4 + G.storm);
  G.flash = Math.max(0, G.flash - dt * 3.2);
  G.gust = Math.max(0, G.gust - dt * 0.6);
  if (G.bolt) { G.bolt.t -= dt; if (G.bolt.t <= 0) G.bolt = null; }
  for (let i = G.later.length - 1; i >= 0; i--) if (G.t >= G.later[i].at) { const l = G.later[i]; G.later.splice(i, 1); l.fn(); }

  // story beats
  if (t > 3 && beat('tut1')) toast('Walk with A/D or the arrow keys. Hold Shift to hurry.', '#ffd27a', 6);
  if (t > 110 && beat('storm')) { toast('Thunderheads over the west rim. Storm\'s comin\'. Gather what you can.', '#ffb070', 6); later(1, () => Sound.thunder(0.35)); }
  if (t > 175 && beat('rain')) toast('First drops. Head back to camp, or risk one more run to that wagon?', '#ffb070', 7);
  if (t > 235 && beat('dark')) toast('Full dark. Keep that fire alive till sunrise.', '#ffd9a0', 6);
  if ((t > 40 && beat('howl1')) || (t > 492 && beat('howl2'))) Sound.howl();
  if (t > 470 && beat('dawn')) toast('The storm\'s breakin\'. Is that... the sun? Hang on, cowboy!', '#ffd890', 6);

  // player
  const L = keys.ArrowLeft || keys.KeyA, R = keys.ArrowRight || keys.KeyD;
  p.crouch = !!(keys.ArrowDown || keys.KeyS);
  p.running = !!(keys.ShiftLeft || keys.ShiftRight);
  let dir = (R ? 1 : 0) - (L ? 1 : 0);
  if (p.crouch) dir = 0;
  let spd = p.running ? 225 : 140;
  if (inWash(p.x) && G.flood.level > 0.05) spd *= 0.6;
  if (p.warmth < 20) spd *= 0.8;
  p.moving = dir !== 0;
  if (dir) { p.face = dir; p.x += dir * spd * dt; p.walk += dt * spd * 0.07; G.tut.moved = true; }
  p.x = clamp(p.x, LEFT_WALL + 20, RIGHT_WALL - 20);
  if (p.sayT > 0) p.sayT -= dt;
  p.petCD -= dt;
  G.camX = lerp(G.camX, clamp(p.x - W / 2 + p.face * 80, 0, WORLD_W - W), clamp(dt * 3, 0, 1));

  // tutorial follow-ups
  if (G.tut.moved && t > 9 && beat('tut2')) toast('Gather deadwood with E. The fire is hungry, and so are you.', '#ffd27a', 6);
  if (G.tut.gathered && beat('tut3')) toast('Carry it back to camp and press E at the fire to feed it.', '#ffd27a', 6);
  if (G.tut.fed && beat('tut4')) toast('Press B at the fire to heat your last can of beans. Hot beans = full belly + warm bones.', '#ffd27a', 7);
  if (t > 60 && beat('tut5')) toast('The old wagon is way east, past the dry wash. Folks leave things in wagons.', '#ffd27a', 6);

  // fire
  if (f.lit) {
    f.fuel -= (0.45 + G.storm * 0.55 + G.gust * 2.5) * dt;
    if (f.fuel <= 0) { f.fuel = 0; f.lit = false; f.ember = 1; toast(`The fire's out! Press E at the fire to strike a match (${p.matches} left).`, '#ff7a5a', 6); Sound.fizzle(); puff(f.x, BASE_Y - 20, [90, 90, 100], 14, 30); }
    else if (f.fuel < 20 && beat('lowfire' + Math.floor(t / 40))) toast('The fire\'s burnin\' low. Feed it with E.', '#ffb070');
  }
  f.ember = Math.max(0, f.ember - dt * 0.05);
  f.flare = Math.max(0, f.flare - dt * 1.5);
  if (f.can) {
    if (f.lit) f.can.heat += (1.5 + f.fuel / 25) * dt;
    if (f.can.heat > 190 && beat('burnt')) toast('Your beans are burnin\'! Eat them [F] before they\'re charcoal.', '#ff9a6a');
    else if (f.can.heat > 100 && beat('hot')) { toast('The beans are bubblin\' HOT. Press F at the fire to eat!', '#ffd27a'); Sound.pluck(440, 0.15); }
  }
  if (p.can) p.can.heat = Math.max(0, p.can.heat - dt * 0.6);

  // warmth & belly
  const d = Math.abs(p.x - f.x);
  const heat = f.lit ? clamp(f.fuel / 45, 0.2, 1.25) : f.ember * 0.2;
  const near = clamp(1 - d / 200, 0, 1);
  let gain = near * heat * 6.5 + f.flare * near * 3;
  if (Math.abs(p.x - G.horse.x) < 70 && G.night > 0.3) gain += 0.7;
  let cold = 0.15 + G.night * 0.95 + G.storm * 0.7;
  if (!p.hat) cold *= 1.35;
  if (p.blanket) cold *= 0.6;
  if (p.belly <= 0) cold *= 1.6;
  if (inWash(p.x) && G.flood.level > 0.3) cold *= 1.6;
  if (p.crouch) cold *= 0.9;
  p.warmth = clamp(p.warmth + (gain - cold) * dt, 0, 100);
  p.belly = clamp(p.belly - (p.running ? 0.34 : 0.17) * dt, 0, 100);
  if (p.belly <= 0 && !p.bellyWarned) { p.bellyWarned = true; toast('Your stomach is growlin\' louder than the thunder. Starvin\' makes the cold bite harder. Eat something [F]!', '#ff9a6a', 6); }
  if (p.belly > 5) p.bellyWarned = false;
  if (p.warmth < 25 && beat('coldwarn' + Math.floor(t / 30))) toast('You\'re freezin\'! Get close to the fire.', '#9ad0ff');

  // gas (beans have consequences)
  if (p.gassy > 0) {
    p.gassy -= dt; p.tootT -= dt;
    if (p.tootT <= 0) { p.tootT = rand(12, 20); playerToot(); }
  }

  updHorse(dt); updRac(dt); updEvents(dt); updObjects(dt); updParticles(dt);

  // music: campfire guitar that you hear better when close to the fire
  G.timers.music -= dt;
  if (G.timers.music <= 0) { G.timers.music = 0.36; playMusicStep(clamp(1 - d / 500, 0, 1) * (f.lit ? 1 : 0.3)); }
  G.timers.crackle -= dt;
  if (G.timers.crackle <= 0) { G.timers.crackle = rand(0.04, 0.25); if (f.lit) Sound.crackle(0.03 + 0.12 * clamp(1 - d / 600, 0, 1) * f.fuel / 60); }
  Sound.setAmbience(0.25 + G.wind * 0.6, 300 + G.wind * 500 + Math.sin(t * 1.3) * 120, G.storm, f.lit ? clamp(1 - d / 700, 0, 1) * (0.3 + f.fuel / 100) : 0);

  // end conditions
  if (p.warmth <= 0) return endGame(false);
  if (G.t >= NIGHT_LEN) return endGame(true);
}

const CHORDS = [[110, 164.8, 220, 261.6, 329.6], [98, 146.8, 196, 246.9, 293.7], [87.3, 130.8, 174.6, 220, 261.6], [82.4, 123.5, 164.8, 207.7, 246.9]];
const PATTERN = [0, 2, 3, 4, 3, 2, 1, 3];
function playMusicStep(vol) {
  const s = G ? G.musicStep++ : 0;
  if (vol < 0.03) return;
  const chord = CHORDS[Math.floor(s / 8) % 4];
  if (s % 8 === 7 && Math.random() < 0.5) return;
  Sound.pluck(chord[PATTERN[s % 8]], 0.07 * vol);
}

function playerToot() {
  const p = G.p; G.stats.toots++;
  Sound.toot(false); puff(p.x - p.face * 10, groundY(p.x) - 25, [140, 160, 90], 8, 25);
  const r = G.rac, h = G.horse;
  if (['lurk', 'sneak', 'grab', 'play', 'lured'].includes(r.state) && Math.abs(r.x - p.x) < 300) { scareRac('The raccoon gags and flees. Bean power!'); }
  if (Math.abs(h.x - p.x) < 120) { say('Pardon me, Biscuit.'); later(0.8, () => { Sound.snort(); }); }
  else if (Math.abs(p.x - G.fire.x) < 90 && G.fire.lit) { G.fire.fuel = Math.min(100, G.fire.fuel + 5); G.fire.flare = 1; sparks(G.fire.x, BASE_Y - 20, 12); say('Fwoomp. There go my eyebrows.'); }
  else say(pick(['Pardon me.', 'Beans.', 'That was the wind. Honest.', 'Excuse me, canyon.']));
}

function updHorse(dt) {
  const h = G.horse, f = G.fire, p = G.p; h.t += dt;
  const away = Math.abs(p.x - f.x) > 240;
  if (h.rear > 0) h.rear -= dt;
  if (h.gassy > 0) {
    h.gassy -= dt; h.tootT -= dt;
    if (h.tootT <= 0) {
      h.tootT = rand(9, 14); Sound.toot(true); puff(h.x - h.face * 45, groundY(h.x) - 45, [140, 160, 90], 12, 30);
      if (Math.abs(h.x - f.x) < 260 && f.lit) {
        f.fuel = Math.min(100, f.fuel + 10); f.flare = 1; sparks(f.x, BASE_Y - 20, 25);
        toast(beat('horsefan') ? 'Biscuit\'s bean-powered breeze fans the flames! (+fire)' : 'Pfffrrrt. Biscuit stokes the fire again.', '#c8e08a');
      }
      if (['lurk', 'sneak', 'grab', 'play'].includes(G.rac.state) && Math.abs(G.rac.x - h.x) < 400) scareRac('Biscuit\'s toot sends the raccoon running.');
    }
  }
  const moveTo = (tx, s) => { const dd = tx - h.x; if (Math.abs(dd) < 3) return true; h.face = Math.sign(dd); h.x += Math.sign(dd) * Math.min(Math.abs(dd), s * dt); h.walk += dt * 6; return false; };
  switch (h.state) {
    case 'idle':
      if (Math.abs(h.x - HORSE_X) > 3) moveTo(HORSE_X, 40); else h.face = 1;
      if (f.can && away) { h.awayT += dt; if (h.awayT > 3) { h.state = 'eyeing'; h.t = 0; Sound.snort(); toast('Biscuit is eyein\' your beans... (get back to camp!)', '#ffb070'); } }
      else h.awayT = 0;
      break;
    case 'eyeing':
      h.face = 1;
      if (!f.can) h.state = 'idle';
      else if (!away) { h.state = 'idle'; h.awayT = 0; say('Don\'t even think about it, Biscuit.'); }
      else if (h.t > 4) { h.state = 'walk'; h.t = 0; }
      break;
    case 'walk':
      if (!f.can) { h.state = 'back'; break; }
      if (!away) { h.state = 'back'; toast('Biscuit pretends he was just stretchin\'.', '#c8e08a'); break; }
      if (moveTo(f.x - 55, 45)) { h.state = 'eat'; h.t = 0; Sound.snort(); }
      break;
    case 'eat':
      if (!f.can || !away) { h.state = 'back'; if (f.can) toast('Biscuit freezes mid-chew. You saw nothin\'.', '#c8e08a'); break; }
      if (h.t > 3) {
        f.can = null; G.stats.beans = 'eaten by Biscuit the horse'; h.gassy = 120; h.tootT = 5; h.state = 'back';
        toast('Biscuit ate your beans. Biscuit regrets nothing.', '#ff9a6a', 6); Sound.neigh();
      }
      break;
    case 'back':
      if (moveTo(HORSE_X, 50)) { h.state = 'idle'; h.awayT = 0; }
      break;
  }
}

function scareRac(msg) {
  const r = G.rac;
  if (r.state === 'play' && G.cupObj) G.cupObj.x = r.x; // drops your cup where it was playing
  r.state = 'flee'; r.t = 0; Sound.chitter();
  if (msg) toast(msg, '#c8e08a');
}
function updRac(dt) {
  const r = G.rac, p = G.p, f = G.fire; r.t += dt; r.cd -= dt;
  const dP = Math.abs(p.x - r.x);
  const run = (tx, s) => { const dd = tx - r.x; if (Math.abs(dd) < 4) return true; r.face = Math.sign(dd); r.x += Math.sign(dd) * Math.min(Math.abs(dd), s * dt); return false; };
  const scareable = ['lurk', 'sneak', 'grab', 'play', 'lured'];
  if (scareable.includes(r.state) && dP < 75) { scareRac(r.state === 'play' ? 'The raccoon drops your cup and bolts.' : 'You shoo the raccoon. It hisses something rude.'); if (beat('shoo')) say('Git! Go on, git!'); return; }
  switch (r.state) {
    case 'hidden':
      if (f.can && f.can.heat > 12 && r.cd <= 0) {
        r.side = p.x > f.x ? -1 : 1; r.x = f.x + r.side * 330; r.state = 'lurk'; r.t = 0; r.face = -r.side;
        Sound.rustle();
        toast('Somethin\'s rustlin\' in the sage... it smells your beans.', '#c8e08a');
        if (beat('cuptip')) later(2.5, () => toast('Shoo it off by walkin\' at it, or throw your tin cup [C] to lure it away.', '#ffd27a', 7));
      }
      break;
    case 'lurk': if (!f.can) { r.state = 'leave'; break; } if (r.t > 3.5) { r.state = 'sneak'; r.t = 0; } break;
    case 'sneak':
      if (!f.can) { r.state = 'leave'; break; }
      if (run(f.x + r.side * 22, 42)) { r.state = 'grab'; r.t = 0; Sound.chitter(); }
      break;
    case 'grab':
      if (!f.can) { r.state = 'leave'; break; }
      if (r.t > 2.4) { r.loot = f.can; f.can = null; r.state = 'carry'; r.t = 0; Sound.chitter(); toast('The raccoon grabbed your beans! Run it down [Shift]!', '#ff9a6a'); }
      break;
    case 'carry':
      if (dP < 42) {
        r.loot.half = true; p.can = r.loot; r.loot = null; r.state = 'flee'; r.t = 0; Sound.chitter();
        toast('You wrestle the can back. It\'s half-eaten. Raccoon spit counts as seasoning.', '#ffd27a', 6);
        break;
      }
      if (run(f.x + r.side * 760, 115)) { G.stats.beans = 'stolen by a raccoon'; r.loot = null; r.state = 'gone'; toast('The raccoon disappears with your last can of beans. Somewhere, it is living your best life.', '#ff9a6a', 7); }
      break;
    case 'flee':
      if (run(r.x + (r.x < p.x ? -1 : 1) * 200, 175) || Math.abs(r.x - f.x) > 650 || r.x < LEFT_WALL || r.x > RIGHT_WALL) { r.state = 'hidden'; r.cd = 12; r.x = -999; }
      break;
    case 'lured':
      if (!G.cupObj || !G.cupObj.landed) { if (!G.cupObj) r.state = 'leave'; break; }
      if (run(G.cupObj.x, 95)) { r.state = 'play'; r.t = 0; if (beat('cupplay')) toast('The raccoon is admirin\' its reflection in your cup.', '#c8e08a'); else Sound.chitter(); }
      break;
    case 'play':
      if (G.cupObj) G.cupObj.x = r.x + r.face * 10;
      if (r.t > 14) { r.t = 0; r.side = r.x < f.x ? -1 : 1; r.state = f.can ? 'sneak' : 'leave'; }
      break;
    case 'leave':
      if (run(f.x + (r.x < f.x ? -1 : 1) * 700, 90)) { r.state = 'hidden'; r.cd = 10; r.x = -999; }
      break;
    case 'gone': break;
  }
}

function updEvents(dt) {
  const p = G.p, f = G.fire, T = G.timers;
  // lightning
  if (G.storm > 0.35 && G.t > T.lightning) {
    T.lightning = G.t + rand(5, 14) / Math.max(G.storm, 0.4);
    G.flash = 1; G.bolt = { x: rand(150, W - 150), t: 0.22, seed: Math.random() * 1000 };
    later(rand(0.3, 1.6), () => Sound.thunder(rand(0.6, 1)));
    const h = G.horse;
    if (h.state === 'idle' && Math.random() < 0.5) { h.rear = 1.2; Sound.neigh(); }
  }
  // wind gust: crouch to keep your hat
  const gs = G.gustS;
  gs.t += dt;
  if (gs.state === 'none' && G.storm > 0.45 && G.t > T.gust) { gs.state = 'warn'; gs.t = 0; Sound.whoosh(); toast('Big gust comin\'! Crouch [S] to hold onto your hat!', '#9ad0ff', 4); }
  else if (gs.state === 'warn' && gs.t > 2.3) {
    gs.state = 'blow'; gs.t = 0; G.gust = 1;
    if (p.hat && !p.crouch) {
      p.hat = false; G.stats.hats++; Sound.hat();
      G.hatObj = { x: p.x, y: groundY(p.x) - 64, vx: rand(260, 380), vy: -240, rot: 0, landed: false };
      toast('Your hat is ridin\' off without you! (no hat = colder) Grab it with E.', '#9ad0ff', 5);
      say('MY HAT!', 2);
    } else if (p.hat) say(pick(['Not today, wind.', 'Hat stays. I stay.']));
    if (f.lit) sparks(f.x, BASE_Y - 20, 30);
    spawnWeed(true);
  } else if (gs.state === 'blow' && gs.t > 1.8) { gs.state = 'none'; T.gust = G.t + rand(35, 55); }
  // flash flood in the wash
  const fl = G.flood; fl.t += dt;
  const puddle = G.storm * 0.18;
  if (fl.state === 'none') {
    fl.level = lerp(fl.level, puddle, dt);
    if (G.storm > 0.55 && G.t > T.flood) { fl.state = 'warn'; fl.t = 0; Sound.rumble(); toast('A low roar up the wash... FLASH FLOOD comin\'! Get out of the dry wash!', '#ff7a5a', 5); }
  } else if (fl.state === 'warn') { fl.level = lerp(fl.level, puddle, dt); if (fl.t > 4.5) { fl.state = 'flood'; fl.t = 0; Sound.splash(); } }
  else if (fl.state === 'flood') {
    fl.level = fl.t < 1.2 ? lerp(puddle, 1, fl.t / 1.2) : fl.t < 7 ? 1 : lerp(1, puddle, (fl.t - 7) / 2.5);
    if (fl.t > 9.5) { fl.state = 'none'; T.flood = G.t + rand(45, 70); }
  }
  if (fl.level > 0.55 && inWash(p.x)) {
    const lost = p.wood + p.weeds;
    p.x = p.x < (WASH_L + WASH_R) / 2 ? WASH_L - 30 : WASH_R + 30;
    p.wood = 0; p.weeds = 0; p.warmth = Math.max(0, p.warmth - 22); G.stats.swept++; Sound.splash();
    toast('The wash baptized you. You\'re clean for the first time since spring.' + (lost ? ` (Lost ${lost} firewood.)` : ''), '#9ad0ff', 6);
    say('BLBLBL—', 1.5);
  }
  // tumbleweeds
  if (G.t > T.weed && G.t < 470) { T.weed = G.t + rand(16, 30); spawnWeed(false); }
}
function spawnWeed(fast) {
  if (G.weedsOut.filter(w => !w.dead).length > 2) return;
  G.weedsOut.push({ x: G.camX - 60, y: BASE_Y - 14, vy: 0, rot: 0, r: rand(12, 17), dead: false, fast });
}

function updObjects(dt) {
  // cup
  const c = G.cupObj;
  if (c && !c.landed) {
    c.vy += 700 * dt; c.x += c.vx * dt; c.y += c.vy * dt; c.rot += dt * 14;
    if (c.x < LEFT_WALL + 10) { c.x = LEFT_WALL + 10; c.vx = Math.abs(c.vx) * 0.4; }
    if (c.x > RIGHT_WALL - 10) { c.x = RIGHT_WALL - 10; c.vx = -Math.abs(c.vx) * 0.4; }
    if (c.y >= groundY(c.x) - 5) {
      c.y = groundY(c.x) - 5; c.landed = true; Sound.clink();
      const r = G.rac;
      if (['lurk', 'sneak', 'grab', 'carry'].includes(r.state) && Math.abs(r.x - c.x) < 800) {
        if (r.state === 'carry') { G.groundCan = { x: r.x, can: r.loot }; r.loot = null; toast('The raccoon drops your beans for the shiny cup. Priorities.', '#c8e08a', 6); }
        r.state = 'lured'; r.t = 0; Sound.chitter();
      }
    }
  }
  // hat
  const h = G.hatObj;
  if (h && !h.landed) {
    h.vy += 400 * dt; h.vx *= (1 - dt * 0.6); h.x += h.vx * dt; h.y += h.vy * dt; h.rot += dt * 8;
    if (h.x > RIGHT_WALL - 20) { h.x = RIGHT_WALL - 20; h.vx = -20; }
    if (h.y >= groundY(h.x) - 4) { h.y = groundY(h.x) - 4; h.landed = true; }
  }
  if (h && h.landed && inWash(h.x) && G.flood.level > 0.55) { G.hatObj = null; toast('Your hat floats away down the wash. Godspeed, hat.', '#9ad0ff'); }
  if (G.cupObj && G.cupObj.landed && inWash(G.cupObj.x) && G.flood.level > 0.55 && G.rac.state !== 'play') { G.cupObj = null; toast('The flood carries off your tin cup.', '#9ad0ff'); }
  if (G.groundCan && inWash(G.groundCan.x) && G.flood.level > 0.55) { G.groundCan = null; G.stats.beans = 'washed away in a flash flood'; toast('The flood takes your beans. Of course it does.', '#ff9a6a'); }
  // tumbleweeds roll with the wind
  for (const w of G.weedsOut) {
    if (w.dead) continue;
    const v = 60 + G.wind * 110 + (w.fast ? 120 : 0);
    w.x += v * dt; w.rot += v * dt / w.r;
    w.vy += 500 * dt; w.y += w.vy * dt;
    const gy = groundY(w.x) - w.r;
    if (w.y > gy) { w.y = gy; w.vy = -rand(80, 220) * (0.5 + G.wind * 0.4); }
    if (w.x > RIGHT_WALL - 30 || w.x > G.camX + W + 200) w.dead = true;
    if (inWash(w.x) && G.flood.level > 0.55) w.dead = true;
  }
  G.weedsOut = G.weedsOut.filter(w => !w.dead);
  // toasts
  for (const tt of G.toasts) tt.t += dt;
  G.toasts = G.toasts.filter(tt => tt.t < tt.dur);
}

function updParticles(dt) {
  for (const q of G.parts) {
    q.t += dt; q.x += q.vx * dt; q.y += q.vy * dt;
    if (q.kind === 'spark') { q.vy += 40 * dt; q.vx += G.wind * 30 * dt; }
    else if (q.kind === 'smoke') { q.vx += G.wind * 25 * dt; q.r += dt * 6; }
    else if (q.kind === 'splash') q.vy += 600 * dt;
    else { q.vx *= 0.97; q.vy *= 0.97; }
  }
  G.parts = G.parts.filter(q => q.t < q.life);
  // ambient fire particles
  const f = G.fire;
  if (f.lit && Math.random() < dt * (6 + f.fuel / 10)) addPart({ x: f.x + rand(-10, 10), y: BASE_Y - 20, vx: rand(-15, 15), vy: rand(-90, -40), life: rand(0.6, 1.8), t: 0, r: rand(1, 2.2), kind: 'spark' });
  if ((f.lit || f.ember > 0.1) && Math.random() < dt * 5) addPart({ x: f.x + rand(-6, 6), y: BASE_Y - 40 - f.fuel * 0.3, vx: rand(-5, 5), vy: rand(-35, -20), life: rand(2, 4), t: 0, r: rand(6, 10), kind: 'smoke' });
  if (f.can && f.can.heat > 100 && Math.random() < dt * 4) addPart({ x: f.x + 26, y: BASE_Y - 26, vx: rand(-5, 5), vy: -25, life: 1.4, t: 0, r: 4, kind: f.can.heat > 190 ? 'smoke' : 'steam' });
  // rain
  const want = Math.floor(G.storm * 520);
  while (G.rain.length < want) G.rain.push({ x: rand(-100, W + 100), y: rand(-H, 0), v: rand(700, 950), l: rand(10, 22) });
  if (G.rain.length > want) G.rain.length = want;
  const slant = G.wind * 140;
  for (const d of G.rain) {
    d.y += d.v * dt; d.x += slant * dt;
    const gy = groundY(d.x + G.camX);
    if (d.y > gy) {
      if (Math.random() < 0.25) addPart({ x: d.x + G.camX, y: gy, vx: rand(-30, 30), vy: rand(-80, -30), life: 0.25, t: 0, r: 1, kind: 'splash' });
      d.y = rand(-60, -10); d.x = rand(-150, W + 50);
    }
  }
}

function endGame(won) {
  mode = won ? 'won' : 'lost';
  const p = G.p, s = G.stats;
  Sound.sting(won);
  Sound.setAmbience(0.2, 400, won ? 0 : G.storm, 0);
  document.getElementById('endEyebrow').textContent = won ? '6:00 AM · Sunrise over Coffin Rock' : `Died at ${clockStr()} · Coffin Rock Canyon`;
  document.getElementById('endTitle').textContent = won ? 'You Survived' : 'Froze Stiff';
  let text;
  if (won) {
    text = s.beans.includes('Biscuit') ? 'The sun rises. Biscuit, full of your beans, has never looked more at peace.'
      : s.beans.includes('raccoon') ? 'The sun rises. Somewhere, a raccoon is telling its friends about you.'
      : s.beans.includes('by you') ? 'The sun rises on a cowboy with a full belly and a terrible secret (the beans).'
      : 'The sun rises. You are cold, damp, and alive. Mostly alive.';
  } else {
    text = !p.hat ? 'They found you hatless, stiff as a fence post. The hat was fine.'
      : !G.fire.lit ? 'The fire went out, and so did you. Biscuit stood watch till morning.'
      : p.belly <= 0 ? 'An empty belly and a cold night. Should\'ve eaten those beans.'
      : 'Stiff as a fence post. The canyon keeps its secrets, and now it keeps you.';
  }
  document.getElementById('endText').textContent = text;
  const li = (k, v) => `<li>${k}: <b>${v}</b></li>`;
  document.getElementById('endStats').innerHTML =
    li('Your last can of beans', s.beans) + li('Logs burned', s.logs) + li('Matches struck', s.matches) +
    li('Hats lost to the wind', s.hats) + li('Flash-flood baptisms', s.swept) + li('Tin cups thrown', s.cups) +
    li('Toots', s.toots) + li('Horse pets', s.pets);
  document.getElementById('end').classList.remove('hidden');
}

function clockStr() {
  const mins = Math.floor((G ? G.t : 0) / NIGHT_LEN * 11 * 60);
  let hh = 19 + Math.floor(mins / 60); const mm = mins % 60;
  hh = hh % 24; const ap = hh >= 12 ? 'PM' : 'AM'; let h12 = hh % 12; if (h12 === 0) h12 = 12;
  return `${h12}:${String(mm).padStart(2, '0')} ${ap}`;
}

// ---------- rendering ----------
function render() {
  const t = G.t;
  const [top, mid, bot] = skyAt(t);
  // sky
  const sg = ctx.createLinearGradient(0, 0, 0, BASE_Y);
  sg.addColorStop(0, rgb(top)); sg.addColorStop(0.6, rgb(mid)); sg.addColorStop(1, rgb(bot));
  ctx.fillStyle = sg; ctx.fillRect(0, 0, W, H);
  // sun (west, setting) and dawn glow (east)
  const sunY = lerp(250, 560, smooth(0, 150, t));
  if (sunY < 560) {
    const sx = 330 - G.camX * 0.04;
    const gl = ctx.createRadialGradient(sx, sunY, 10, sx, sunY, 260);
    gl.addColorStop(0, 'rgba(255,220,150,0.7)'); gl.addColorStop(0.2, 'rgba(255,160,80,0.3)'); gl.addColorStop(1, 'rgba(255,120,60,0)');
    ctx.fillStyle = gl; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = '#fff0c8'; ctx.beginPath(); ctx.arc(sx, sunY, 34, 0, 7); ctx.fill();
  }
  const dawn = smooth(490, 540, t);
  if (dawn > 0) {
    const gl = ctx.createRadialGradient(W * 0.85, BASE_Y, 20, W * 0.85, BASE_Y, 700);
    gl.addColorStop(0, `rgba(255,210,140,${0.7 * dawn})`); gl.addColorStop(1, 'rgba(255,150,100,0)');
    ctx.fillStyle = gl; ctx.fillRect(0, 0, W, H);
    const ry = lerp(600, 380, smooth(515, 570, t));
    ctx.fillStyle = `rgba(255,236,190,${dawn})`; ctx.beginPath(); ctx.arc(W * 0.85, ry, 40, 0, 7); ctx.fill();
  }
  drawClouds(t);
  // landscape layers
  const litAmt = 1 - smooth(60, 200, t) + dawn * 0.8;
  LAYERS.forEach((L, i) => {
    drawLayer(L, litAmt, i);
    // haze between layers
    const hz = ctx.createLinearGradient(0, L.y - 200, 0, L.y + 20);
    hz.addColorStop(0, rgb(bot, 0)); hz.addColorStop(1, rgb(bot, 0.28 - i * 0.06));
    ctx.fillStyle = hz; ctx.fillRect(0, L.y - 200, W, 260);
    if (i === 1) drawArch(litAmt);
  });
  drawSaguaros();
  drawCanyonWalls(litAmt);
  drawGround();
  drawWorldObjects();
  drawParticles(false);
  drawLighting();
  // things that glow / must stay readable after the darkness pass
  drawFireFlames();
  drawParticles(true);
  drawRain();
  drawRacEyes();
  if (G.bolt) drawBolt();
  if (G.flash > 0) { ctx.fillStyle = `rgba(220,230,255,${G.flash * 0.35})`; ctx.fillRect(0, 0, W, H); }
  drawForeground();
  drawVignette();
}

function drawClouds(t) {
  const cover = 0.15 + G.storm * 0.85;
  const r = mulberry32(5);
  const dusk = 1 - smooth(60, 200, t);
  const base = mix(hex('#2a2636'), hex('#c87870'), dusk);
  const lit = G.flash;
  for (let i = 0; i < 16; i++) {
    const cx = ((r() * 2400 - G.camX * 0.05 + t * (6 + G.wind * 14) * (0.6 + r())) % 2400 + 2400) % 2400 - 500;
    const cy = 40 + r() * 220;
    const s = 60 + r() * 120;
    const a = clamp(cover * 1.4 - i * 0.05, 0, 0.9) * (0.55 + 0.45 * G.storm);
    if (a <= 0) continue;
    const col = mix(base, hex('#c8d0ff'), lit * 0.5);
    ctx.fillStyle = rgb(col, a);
    ctx.beginPath();
    for (let k = 0; k < 5; k++) { const ox = (k - 2) * s * 0.55; const oy = Math.sin(k * 1.7 + i) * s * 0.18; ctx.moveTo(cx + ox + s * 0.5, cy + oy); ctx.arc(cx + ox, cy + oy, s * (0.45 + 0.1 * Math.sin(k + i)), 0, 7); }
    ctx.fill();
    if (dusk > 0.1) { ctx.fillStyle = `rgba(255,150,110,${dusk * 0.25 * a})`; ctx.fillRect(cx - s * 1.3, cy + s * 0.25, s * 2.6, 3); }
  }
}

function drawLayer(L, litAmt, idx) {
  const off = G.camX * L.par;
  const col = mix(L.night, L.dusk, clamp(litAmt, 0, 1));
  const i0 = Math.max(0, Math.floor(off / L.step) - 1), i1 = Math.min(L.h.length - 1, Math.ceil((off + W) / L.step) + 1);
  ctx.beginPath(); ctx.moveTo(-10, H);
  for (let i = i0; i <= i1; i++) ctx.lineTo(i * L.step - off, L.y - L.h[i]);
  ctx.lineTo(W + 10, H); ctx.closePath();
  const g = ctx.createLinearGradient(0, L.y - 260, 0, L.y);
  g.addColorStop(0, rgb(mix(col, [255, 190, 130], 0.12 * litAmt))); g.addColorStop(1, rgb(mix(col, [20, 10, 20], 0.35)));
  ctx.fillStyle = g; ctx.fill();
  // strata bands (clipped)
  ctx.save(); ctx.clip();
  for (const s of L.strata) {
    const y = L.y - 250 * s[0];
    ctx.fillStyle = s[2] ? `rgba(255,200,150,${0.06 * litAmt + 0.02})` : 'rgba(30,10,20,0.12)';
    ctx.fillRect(0, y, W, s[1]);
  }
  // shadowed east faces: darken right half of each feature by sampling slope
  ctx.fillStyle = `rgba(20,5,15,${0.18 + 0.1 * (1 - litAmt)})`;
  for (let i = i0; i < i1; i++) {
    if (L.h[i + 1] < L.h[i] - 1.2) { const x = i * L.step - off; ctx.fillRect(x, L.y - L.h[i], L.step + 0.5, L.h[i] + 10); }
  }
  ctx.restore();
  // rim light on top edges (setting sun)
  if (litAmt > 0.05) {
    ctx.strokeStyle = rgb(L.rim, 0.5 * litAmt); ctx.lineWidth = 2; ctx.beginPath();
    for (let i = i0; i <= i1; i++) { const x = i * L.step - off; if (i === i0) ctx.moveTo(x, L.y - L.h[i]); else ctx.lineTo(x, L.y - L.h[i]); }
    ctx.stroke();
  }
  // Coffin Rock silhouette label-free landmark: a lid notch on the big mid-layer butte
  if (idx === 1) {
    const x = LANDMARKS.coffinX - off;
    if (x > -200 && x < W + 200) {
      ctx.fillStyle = rgb(mix(col, [20, 10, 20], 0.15));
      ctx.beginPath(); ctx.moveTo(x - 55, L.y - 300); ctx.lineTo(x - 40, L.y - 345); ctx.lineTo(x + 40, L.y - 345); ctx.lineTo(x + 55, L.y - 300); ctx.closePath(); ctx.fill();
      if (litAmt > 0.05) { ctx.strokeStyle = rgb(L.rim, 0.5 * litAmt); ctx.beginPath(); ctx.moveTo(x - 55, L.y - 300); ctx.lineTo(x - 40, L.y - 345); ctx.lineTo(x + 40, L.y - 345); ctx.stroke(); }
    }
  }
}

function drawArch(litAmt) {
  const L = LAYERS[1];
  const x = LANDMARKS.archX - G.camX * 0.4, y = 545;
  if (x < -300 || x > W + 300) return;
  const col = mix(hex('#170f26'), hex('#93402f'), clamp(litAmt, 0, 1));
  ctx.fillStyle = rgb(col);
  ctx.beginPath();
  ctx.moveTo(x - 150, y); ctx.lineTo(x - 140, y - 150); ctx.quadraticCurveTo(x - 120, y - 205, x - 30, y - 210);
  ctx.quadraticCurveTo(x + 90, y - 214, x + 130, y - 160); ctx.lineTo(x + 150, y);
  ctx.lineTo(x + 85, y); ctx.lineTo(x + 80, y - 95); ctx.quadraticCurveTo(x + 5, y - 170, x - 75, y - 100); ctx.lineTo(x - 85, y);
  ctx.closePath(); ctx.fill();
  if (litAmt > 0.05) { ctx.strokeStyle = rgb(L.rim, 0.55 * litAmt); ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(x - 140, y - 150); ctx.quadraticCurveTo(x - 120, y - 205, x - 30, y - 210); ctx.quadraticCurveTo(x + 90, y - 214, x + 130, y - 160); ctx.stroke(); }
}

function drawSaguaros() {
  const par = 0.8;
  ctx.fillStyle = '#2a1a1a'; ctx.strokeStyle = '#2a1a1a'; ctx.lineCap = 'round';
  for (const s of SCATTER.saguaros) {
    const x = s.x - G.camX * par; if (x < -60 || x > W + 60) continue;
    const y = BASE_Y - 8;
    ctx.lineWidth = 9; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y - s.h); ctx.stroke();
    ctx.lineWidth = 6; ctx.beginPath();
    ctx.moveTo(x, y - s.h * 0.45); ctx.lineTo(x - 14, y - s.h * 0.45); ctx.lineTo(x - 14, y - s.h * 0.75);
    if (s.arms > 0.4) { ctx.moveTo(x, y - s.h * 0.6); ctx.lineTo(x + 13, y - s.h * 0.6); ctx.lineTo(x + 13, y - s.h * 0.85); }
    ctx.stroke();
  }
}

function drawCanyonWalls(litAmt) {
  const col = mix(hex('#1a0f1c'), hex('#8a3424'), clamp(litAmt * 0.9, 0, 1));
  const drawWall = (edge, dir) => {
    const x0 = edge - G.camX;
    if ((dir < 0 && x0 < -40) || (dir > 0 && x0 > W + 40)) return;
    ctx.fillStyle = rgb(col);
    ctx.beginPath();
    const far = dir < 0 ? -400 : W + 400;
    ctx.moveTo(far, H); ctx.lineTo(x0, H);
    const r = mulberry32(dir < 0 ? 3 : 4);
    for (let y = BASE_Y; y > -20; y -= 30) ctx.lineTo(x0 + dir * (r() * 30 + (BASE_Y - y) * 0.15), y);
    ctx.lineTo(far, -20); ctx.closePath(); ctx.fill();
    ctx.save(); ctx.clip();
    for (let k = 0; k < 14; k++) { ctx.fillStyle = k % 2 ? 'rgba(255,190,140,0.07)' : 'rgba(20,5,10,0.15)'; ctx.fillRect(-400, 40 + k * 40 + (k * 13) % 17, W + 800, 6 + (k * 7) % 9); }
    ctx.restore();
  };
  drawWall(LEFT_WALL, -1); drawWall(RIGHT_WALL, 1);
}

function drawGround() {
  const cx = G.camX;
  ctx.beginPath(); ctx.moveTo(-10, H);
  for (let sx = -10; sx <= W + 10; sx += 6) ctx.lineTo(sx, groundY(sx + cx));
  ctx.lineTo(W + 10, H); ctx.closePath();
  const g = ctx.createLinearGradient(0, BASE_Y - 10, 0, H);
  const wet = G.storm * 0.4;
  g.addColorStop(0, rgb(mix(hex('#a2543a'), hex('#5a3a3a'), wet))); g.addColorStop(0.3, rgb(mix(hex('#7a3826'), hex('#3a2630'), wet))); g.addColorStop(1, '#2a1416');
  ctx.fillStyle = g; ctx.fill();
  // wash water
  const lv = G.flood.level;
  if (lv > 0.02) {
    const sx0 = WASH_L - cx, sx1 = WASH_R - cx;
    if (sx1 > -10 && sx0 < W + 10) {
      const top = BASE_Y + 48 - lv * 62;
      ctx.save();
      ctx.beginPath(); ctx.moveTo(sx0, BASE_Y - 20);
      for (let x = WASH_L; x <= WASH_R; x += 6) ctx.lineTo(x - cx, groundY(x));
      ctx.lineTo(sx1, BASE_Y - 20); ctx.closePath(); ctx.clip();
      ctx.fillStyle = lv > 0.5 ? 'rgba(120,80,60,0.92)' : 'rgba(80,90,110,0.7)';
      ctx.beginPath(); ctx.moveTo(sx0, H);
      for (let x = sx0; x <= sx1; x += 6) ctx.lineTo(x, top + Math.sin(x * 0.08 + G.t * (lv > 0.5 ? 9 : 2)) * (lv > 0.5 ? 4 : 1));
      ctx.lineTo(sx1, H); ctx.closePath(); ctx.fill();
      if (lv > 0.5) { ctx.strokeStyle = 'rgba(230,220,200,0.6)'; ctx.lineWidth = 2; for (let k = 0; k < 8; k++) { const fx = sx0 + ((k * 47 + G.t * 160) % (sx1 - sx0)); ctx.beginPath(); ctx.moveTo(fx, top + 2); ctx.lineTo(fx + 14, top); ctx.stroke(); } }
      ctx.restore();
    }
  }
  // rocks
  ctx.fillStyle = '#5a2a20';
  for (const r of SCATTER.rocks) { const x = r.x - cx; if (x < -30 || x > W + 30) continue; const y = groundY(r.x); ctx.beginPath(); ctx.ellipse(x, y, r.w, r.h, 0, Math.PI, 0); ctx.fill(); }
  // grass bending in the wind
  ctx.lineWidth = 1.5; ctx.lineCap = 'round';
  for (const gr of SCATTER.grass) {
    const x = gr.x - cx; if (x < -30 || x > W + 30) continue;
    const y = groundY(gr.x) + 1;
    const bend = (G.wind * 0.8 + Math.sin(G.t * (2 + G.wind * 2) + gr.ph) * (0.15 + G.wind * 0.35)) * gr.h;
    ctx.strokeStyle = gr.c < 0.5 ? '#c99a52' : '#a87a3a';
    ctx.beginPath();
    for (let k = 0; k < gr.n; k++) { const ox = (k - gr.n / 2) * 2.5; ctx.moveTo(x + ox, y); ctx.quadraticCurveTo(x + ox + bend * 0.3, y - gr.h * 0.6, x + ox + bend * 0.8 + k, y - gr.h + Math.abs(bend) * 0.3); }
    ctx.stroke();
  }
}

function sx(x) { return x - G.camX; }
function visible(x, m = 150) { const s = x - G.camX; return s > -m && s < W + m; }

function drawWorldObjects() {
  const p = G.p;
  // deadwood
  for (const w of G.woods) {
    if (!visible(w.x)) continue;
    const x = sx(w.x), y = groundY(w.x);
    if (w.kind === 'tree') {
      ctx.strokeStyle = '#3a2418'; ctx.lineCap = 'round'; ctx.lineWidth = 12;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.quadraticCurveTo(x - 8, y - 60, x + 6, y - 120); ctx.stroke();
      const br = [[-1, 60, 40], [1, 80, 45], [-1, 100, 35], [1, 112, 30]];
      ctx.lineWidth = 5;
      for (let i = 0; i < w.n; i++) { const b = br[i]; ctx.beginPath(); ctx.moveTo(x + 2, y - b[1]); ctx.quadraticCurveTo(x + b[0] * b[2] * 0.6, y - b[1] - 10, x + b[0] * b[2], y - b[1] - 28); ctx.stroke(); }
      ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(x + 6, y - 120); ctx.lineTo(x + 18, y - 136); ctx.stroke();
    } else {
      ctx.strokeStyle = '#6a4428'; ctx.lineWidth = 6; ctx.lineCap = 'round';
      for (let i = 0; i < w.n; i++) { ctx.beginPath(); ctx.moveTo(x - 22 + i * 6, y - 3 - i * 4); ctx.lineTo(x + 20 - i * 3, y - 8 - (i % 2) * 6); ctx.stroke(); }
      if (w.n === 0) { ctx.fillStyle = '#4a2a1a'; ctx.fillRect(x - 10, y - 2, 20, 2); }
    }
  }
  // cacti
  for (const c of G.cacti) {
    if (!visible(c.x)) continue;
    const x = sx(c.x), y = groundY(c.x);
    ctx.fillStyle = '#4a6a3a';
    [[0, -14, 11, 15], [-12, -30, 9, 12], [10, -32, 9, 12], [0, -44, 8, 10]].forEach(pd => { ctx.beginPath(); ctx.ellipse(x + pd[0], y + pd[1], pd[2], pd[3], pd[0] * 0.03, 0, 7); ctx.fill(); });
    ctx.fillStyle = '#d0507a';
    for (let i = 0; i < c.n; i++) { ctx.beginPath(); ctx.arc(x - 12 + i * 20, y - 44 + i * 2, 4, 0, 7); ctx.fill(); }
  }
  drawWagon();
  // hitching post + rope
  { const x = sx(HORSE_X - 40), y = BASE_Y; ctx.fillStyle = '#3a2418'; ctx.fillRect(x - 4, y - 50, 8, 50); ctx.fillRect(x - 14, y - 50, 28, 6);
    ctx.strokeStyle = '#8a7050'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x, y - 46); const hx = sx(G.horse.x) + G.horse.face * 40; ctx.quadraticCurveTo((x + hx) / 2, y - 20, hx, y - 62); ctx.stroke(); }
  // camp: bedroll + stones + logs
  { const f = G.fire, x = sx(f.x), y = BASE_Y;
    ctx.fillStyle = '#6a2a24'; ctx.beginPath(); ctx.ellipse(x + 95, y - 6, 34, 8, 0, 0, 7); ctx.fill();
    ctx.fillStyle = '#8a3a2e'; ctx.beginPath(); ctx.ellipse(x + 124, y - 10, 11, 11, 0, 0, 7); ctx.fill();
    ctx.fillStyle = '#2a1a14'; ctx.lineWidth = 6; ctx.strokeStyle = '#3a2216';
    ctx.beginPath(); ctx.moveTo(x - 22, y - 2); ctx.lineTo(x + 18, y - 12); ctx.moveTo(x + 22, y - 2); ctx.lineTo(x - 16, y - 12); ctx.stroke();
    ctx.fillStyle = '#5a5050';
    for (let i = 0; i < 7; i++) { ctx.beginPath(); ctx.ellipse(x - 30 + i * 10, y - 2, 7, 5, 0, 0, 7); ctx.fill(); }
    if (f.can) drawCan(x + 26, y - 14, f.can);
  }
  if (G.groundCan) drawCan(sx(G.groundCan.x), groundY(G.groundCan.x) - 2, G.groundCan.can);
  drawHorse();
  drawRaccoon();
  for (const w of G.weedsOut) drawWeed(w);
  if (G.cupObj) drawCup(sx(G.cupObj.x), G.cupObj.y, G.cupObj.landed ? 0 : G.cupObj.rot);
  if (G.hatObj) { ctx.save(); ctx.translate(sx(G.hatObj.x), G.hatObj.y); ctx.rotate(G.hatObj.landed ? 0 : Math.sin(G.hatObj.rot) * 0.8); drawHat(0, 0); ctx.restore(); }
  drawCowboy();
}

function drawCan(x, y, c) {
  const st = canState(c);
  ctx.fillStyle = st === 'burnt' ? '#3a3a3a' : '#a8a8b0'; ctx.fillRect(x - 6, y - 14, 12, 14);
  ctx.fillStyle = st === 'burnt' ? '#2a1a1a' : '#b8322a'; ctx.fillRect(x - 6, y - 10, 12, 6);
  ctx.fillStyle = '#d8d8e0'; ctx.fillRect(x - 6, y - 15, 12, 2);
}
function drawCup(x, y, rot) { ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.fillStyle = '#b0b8c0'; ctx.fillRect(-5, -9, 10, 9); ctx.strokeStyle = '#b0b8c0'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(6, -5, 3, -1.5, 1.5); ctx.stroke(); ctx.restore(); }
function drawHat(x, y) {
  ctx.fillStyle = '#5a3a22'; ctx.beginPath(); ctx.ellipse(x, y, 17, 4, 0, 0, 7); ctx.fill();
  ctx.beginPath(); ctx.moveTo(x - 9, y - 1); ctx.quadraticCurveTo(x - 10, y - 13, x - 4, y - 12); ctx.lineTo(x, y - 9); ctx.lineTo(x + 4, y - 12); ctx.quadraticCurveTo(x + 10, y - 13, x + 9, y - 1); ctx.fill();
  ctx.fillStyle = '#2a1a10'; ctx.fillRect(x - 9, y - 4, 18, 2);
}
function drawWeed(w) {
  if (!visible(w.x)) return;
  ctx.save(); ctx.translate(sx(w.x), w.y); ctx.rotate(w.rot);
  ctx.strokeStyle = '#b08a50'; ctx.lineWidth = 1.2;
  ctx.beginPath(); for (let k = 0; k < 9; k++) { const a = k * 0.7; ctx.moveTo(Math.cos(a) * w.r, Math.sin(a) * w.r); ctx.quadraticCurveTo(0, 0, Math.cos(a + 2.4) * w.r, Math.sin(a + 2.4) * w.r); } ctx.stroke();
  ctx.beginPath(); ctx.arc(0, 0, w.r, 0, 7); ctx.stroke();
  ctx.restore();
}

function drawWagon() {
  const wg = G.wagon; if (!visible(wg.x, 200)) return;
  const x = sx(wg.x), y = BASE_Y;
  ctx.save(); ctx.translate(x, y); ctx.rotate(wg.boards < 2 ? 0.1 : 0.05);
  // wheels
  const wheel = (wx, r) => { ctx.strokeStyle = '#3a2416'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(wx, -r, r, 0, 7); ctx.stroke(); ctx.lineWidth = 2; for (let k = 0; k < 8; k++) { const a = k * Math.PI / 4; ctx.beginPath(); ctx.moveTo(wx, -r); ctx.lineTo(wx + Math.cos(a) * r, -r + Math.sin(a) * r); ctx.stroke(); } };
  wheel(-60, 26);
  // bed
  ctx.fillStyle = '#5a3a24'; ctx.fillRect(-90, -62, 170, 26);
  ctx.fillStyle = '#4a2c1a'; for (let i = 0; i < wg.boards; i++) ctx.fillRect(-88 + i * 42, -60, 38, 4);
  // canvas cover (torn)
  ctx.fillStyle = '#d8c8a8'; ctx.strokeStyle = '#8a7a60'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(-85, -62); ctx.bezierCurveTo(-85, -140, 70, -140, 70, -62);
  ctx.lineTo(50, -62); ctx.lineTo(40, -90); ctx.lineTo(25, -70); ctx.lineTo(10, -100); ctx.lineTo(-5, -62); ctx.closePath(); ctx.fill(); ctx.stroke();
  for (let k = 0; k < 3; k++) { ctx.beginPath(); ctx.moveTo(-70 + k * 60, -62); ctx.quadraticCurveTo(-70 + k * 60, -130, -60 + k * 60, -125); ctx.stroke(); }
  ctx.fillStyle = '#7a2a1a'; ctx.font = 'bold 10px Georgia'; ctx.textAlign = 'center';
  ctx.fillText("DR. GRIMSBY'S", -40, -100); ctx.fillText('MIRACLE TONIC', -40, -88);
  wheel(55, 24);
  ctx.restore();
  if (wg.searched === false) { ctx.fillStyle = 'rgba(255,220,140,0.25)'; ctx.beginPath(); ctx.arc(x - 30, y - 70, 6 + Math.sin(G.t * 4) * 2, 0, 7); ctx.fill(); }
}

function drawHorse() {
  const h = G.horse; if (!visible(h.x, 200)) return;
  const x = sx(h.x), y = BASE_Y;
  const moving = ['walk', 'back'].includes(h.state) || (h.state === 'idle' && Math.abs(h.x - HORSE_X) > 3);
  ctx.save(); ctx.translate(x, y); ctx.scale(h.face, 1);
  if (h.rear > 0) { ctx.translate(-30, 0); ctx.rotate(-Math.sin(clamp(h.rear, 0, 1.2) / 1.2 * Math.PI) * 0.35); ctx.translate(30, 0); }
  const body = '#8a5530', dark = '#4a2a18';
  // legs
  ctx.strokeStyle = '#6a3e22'; ctx.lineWidth = 6; ctx.lineCap = 'round';
  const legs = [-30, -22, 24, 32];
  legs.forEach((lx, i) => { const sw = moving ? Math.sin(h.walk + i * 1.6) * 7 : 0; ctx.beginPath(); ctx.moveTo(lx, -42); ctx.lineTo(lx + sw * 0.5, -20); ctx.lineTo(lx + sw, 0); ctx.stroke(); });
  ctx.fillStyle = '#2a1a10'; legs.forEach(lx => ctx.fillRect(lx - 4, -4, 8, 4));
  // body
  ctx.fillStyle = body; ctx.beginPath(); ctx.ellipse(0, -52, 42, 17, 0, 0, 7); ctx.fill();
  // saddle blanket
  ctx.fillStyle = '#2a4a6a'; ctx.fillRect(-14, -68, 24, 18); ctx.fillStyle = '#c8a050'; ctx.fillRect(-14, -58, 24, 2);
  // tail
  ctx.strokeStyle = dark; ctx.lineWidth = 6; ctx.beginPath(); ctx.moveTo(-40, -58);
  const sw = Math.sin(G.t * 3) * 6 + G.wind * 10;
  ctx.quadraticCurveTo(-55 - sw * 0.5, -45, -50 - sw, -22); ctx.stroke();
  // neck + head (grazing when idle)
  const graze = (h.state === 'idle' && !moving && Math.sin(G.t * 0.4) > 0.2) || h.state === 'eat';
  const hx = graze ? 58 : 56, hy = graze ? -22 : -86;
  ctx.fillStyle = body; ctx.beginPath(); ctx.moveTo(28, -62); ctx.lineTo(hx - 6, hy - 6); ctx.lineTo(hx + 4, hy + 8); ctx.lineTo(38, -40); ctx.closePath(); ctx.fill();
  ctx.save(); ctx.translate(hx, hy); ctx.rotate(graze ? 1.2 : 0.5 + (h.state === 'eyeing' ? -0.3 : 0));
  ctx.fillStyle = body; ctx.beginPath(); ctx.ellipse(8, 0, 17, 8, 0, 0, 7); ctx.fill();
  ctx.fillStyle = '#e8dcc8'; ctx.fillRect(4, -3, 18, 3);
  ctx.fillStyle = '#1a0f08'; ctx.beginPath(); ctx.arc(2, -3, 1.8, 0, 7); ctx.fill();
  ctx.fillStyle = body; ctx.beginPath(); ctx.moveTo(-6, -6); ctx.lineTo(-4, -16); ctx.lineTo(0, -6); ctx.fill();
  ctx.restore();
  ctx.strokeStyle = dark; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(26, -68); ctx.lineTo(hx - 6, hy - 8); ctx.stroke();
  ctx.restore();
  if (h.state === 'eyeing' || h.state === 'walk' || h.state === 'eat') bubbleAt(x, y - 120, h.state === 'eat' ? '*munch*' : '?', '#ffb070');
  if (h.gassy > 0 && Math.sin(G.t * 2) > 0.95) bubbleAt(x, y - 120, '...', '#c8e08a');
}

function drawRaccoon() {
  const r = G.rac; if (['hidden', 'gone'].includes(r.state) || !visible(r.x)) return;
  const x = sx(r.x), y = groundY(r.x);
  if (r.state === 'lurk') { // hidden in sage brush, only eyes (drawn later) + shaking bush
    ctx.fillStyle = '#5a6a4a'; const sh = Math.sin(G.t * 30) * 2;
    ctx.beginPath(); ctx.ellipse(x + sh, y - 14, 26, 16, 0, 0, 7); ctx.ellipse(x - 14 + sh, y - 10, 16, 11, 0, 0, 7); ctx.fill();
    return;
  }
  ctx.save(); ctx.translate(x, y); ctx.scale(r.face, 1);
  const bob = Math.abs(Math.sin(G.t * 14)) * 2;
  // tail rings
  for (let k = 0; k < 5; k++) { ctx.fillStyle = k % 2 ? '#3a3634' : '#8a8580'; ctx.beginPath(); ctx.arc(-16 - k * 5, -12 - k * 2.5, 4.5, 0, 7); ctx.fill(); }
  ctx.fillStyle = '#7a7570'; ctx.beginPath(); ctx.ellipse(0, -11 - bob, 15, 9, 0, 0, 7); ctx.fill();
  ctx.fillStyle = '#5a5552'; ctx.fillRect(-10, -5, 4, 5); ctx.fillRect(6, -5, 4, 5);
  ctx.fillStyle = '#8a8580'; ctx.beginPath(); ctx.arc(15, -16 - bob, 7, 0, 7); ctx.fill();
  ctx.fillStyle = '#1a1818'; ctx.fillRect(10, -19 - bob, 12, 4);
  ctx.fillStyle = '#8a8580'; ctx.beginPath(); ctx.moveTo(10, -21 - bob); ctx.lineTo(12, -27 - bob); ctx.lineTo(15, -22 - bob); ctx.fill();
  ctx.fillStyle = '#2a2020'; ctx.beginPath(); ctx.arc(22, -15 - bob, 1.6, 0, 7); ctx.fill();
  if (r.state === 'carry' && r.loot) drawCan(22, -4, r.loot);
  ctx.restore();
  if (r.state === 'grab') bubbleAt(x, y - 45, '!!', '#ff7a5a');
  if (r.state === 'play') bubbleAt(x, y - 45, '<3', '#ffb0c0');
}
function drawRacEyes() {
  const r = G.rac; if (['hidden', 'gone'].includes(r.state) || !visible(r.x) || G.dark < 0.3) return;
  const x = sx(r.x), y = groundY(r.x);
  const ex = r.state === 'lurk' ? x - 2 : x + r.face * 17, ey = r.state === 'lurk' ? y - 18 : y - 18;
  ctx.fillStyle = `rgba(255,240,150,${0.5 + 0.4 * Math.sin(G.t * 3)})`;
  ctx.beginPath(); ctx.arc(ex - 3, ey, 1.8, 0, 7); ctx.arc(ex + 3, ey, 1.8, 0, 7); ctx.fill();
}

function drawCowboy() {
  const p = G.p, x = sx(p.x), y = groundY(p.x);
  const jitter = p.warmth < 30 ? (Math.random() - 0.5) * (30 - p.warmth) * 0.08 : 0;
  ctx.save(); ctx.translate(x + jitter, y); ctx.scale(p.face, 1);
  const c = p.crouch ? 0.72 : 1;
  const w = p.moving ? Math.sin(p.walk) : 0;
  ctx.lineCap = 'round';
  // wood bundle on back
  if (p.wood + p.weeds > 0) { ctx.strokeStyle = '#6a4428'; ctx.lineWidth = 5; for (let i = 0; i < p.wood; i++) { ctx.beginPath(); ctx.moveTo(-18, -34 * c - i * 5); ctx.lineTo(-4, -48 * c - i * 5); ctx.stroke(); } }
  // legs
  ctx.strokeStyle = '#3a2a22'; ctx.lineWidth = 6;
  if (p.crouch) { ctx.beginPath(); ctx.moveTo(-3, -22); ctx.lineTo(8, -12); ctx.lineTo(2, 0); ctx.moveTo(3, -22); ctx.lineTo(-8, -10); ctx.lineTo(-6, 0); ctx.stroke(); }
  else { ctx.beginPath(); ctx.moveTo(-3, -30); ctx.lineTo(-3 + w * 9, 0); ctx.moveTo(3, -30); ctx.lineTo(3 - w * 9, 0); ctx.stroke(); }
  ctx.fillStyle = '#1a100a'; ctx.fillRect(-3 + (p.crouch ? 0 : w * 9) - 3, -4, 9, 4); ctx.fillRect(3 - (p.crouch ? 8 : w * 9) - 3, -4, 9, 4);
  // duster coat
  const top = -56 * c;
  ctx.fillStyle = '#7a5434'; ctx.beginPath(); ctx.moveTo(-9, top); ctx.lineTo(9, top); ctx.lineTo(13 + w * 2, -20 * c); ctx.lineTo(-14 - w * 2 - G.wind * 3, -18 * c); ctx.closePath(); ctx.fill();
  if (p.blanket) { ctx.fillStyle = '#8a2a22'; ctx.beginPath(); ctx.moveTo(-11, top - 1); ctx.lineTo(11, top - 1); ctx.lineTo(12, top + 18); ctx.lineTo(-13 - G.wind * 4, top + 22); ctx.closePath(); ctx.fill(); ctx.fillStyle = '#d8b060'; ctx.fillRect(-12, top + 6, 24, 2); ctx.fillRect(-12, top + 12, 24, 2); }
  // arm
  ctx.strokeStyle = '#6a4a2e'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(4, top + 4);
  if (p.crouch && p.hat) ctx.lineTo(6, top - 14); else ctx.lineTo(8 - w * 6, top + 26);
  ctx.stroke();
  // bandana + head
  ctx.fillStyle = '#a3262a'; ctx.beginPath(); ctx.moveTo(-6, top); ctx.lineTo(7, top); ctx.lineTo(2, top + 6); ctx.fill();
  ctx.fillStyle = '#c98d5e'; ctx.beginPath(); ctx.arc(1, top - 8, 7.5, 0, 7); ctx.fill();
  ctx.fillStyle = '#3a2418'; ctx.fillRect(-4, top - 4, 9, 3); // stubble
  ctx.fillStyle = '#1a0f08'; ctx.fillRect(4, top - 10, 2, 2);
  ctx.fillStyle = '#c98d5e'; ctx.fillRect(7, top - 8, 2, 3);
  if (p.hat) drawHat(1, top - 13);
  else { ctx.fillStyle = '#2a1a10'; ctx.beginPath(); ctx.arc(1, top - 12, 7, Math.PI, 0); ctx.fill(); }
  ctx.restore();
}

function drawParticles(glow) {
  for (const q of G.parts) {
    const a = 1 - q.t / q.life, x = sx(q.x);
    if (x < -40 || x > W + 40) continue;
    if (glow) {
      if (q.kind !== 'spark') continue;
      ctx.fillStyle = `rgba(255,${150 + 80 * a | 0},60,${a})`; ctx.fillRect(x, q.y, q.r, q.r);
    } else {
      if (q.kind === 'spark') continue;
      if (q.kind === 'splash') { ctx.fillStyle = `rgba(190,200,230,${a * 0.6})`; ctx.fillRect(x, q.y, 1.5, 1.5); continue; }
      const col = q.kind === 'smoke' ? [70, 65, 70] : q.kind === 'steam' ? [230, 230, 230] : q.color;
      ctx.fillStyle = rgb(col, a * (q.kind === 'smoke' ? 0.35 : 0.5));
      ctx.beginPath(); ctx.arc(x, q.y, q.r, 0, 7); ctx.fill();
    }
  }
}

function fireLight() {
  const f = G.fire;
  const fl = Math.sin(G.t * 13) * 6 + Math.sin(G.t * 7.3) * 9 + Math.random() * 6;
  if (f.lit) return 150 + f.fuel * 2.6 + f.flare * 80 + fl;
  return 30 + f.ember * 50;
}
function drawLighting() {
  const dark = clamp(G.dark * (1 - G.flash * 0.7), 0, 1);
  if (dark <= 0.01) return;
  lctx.globalCompositeOperation = 'source-over';
  lctx.clearRect(0, 0, W, H);
  lctx.fillStyle = `rgba(6,8,24,${dark})`;
  lctx.fillRect(0, 0, W, H);
  lctx.globalCompositeOperation = 'destination-out';
  const f = G.fire, fx = sx(f.x), fy = BASE_Y - 25, R = fireLight();
  const g = lctx.createRadialGradient(fx, fy, 10, fx, fy, R);
  g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(0.5, 'rgba(0,0,0,0.75)'); g.addColorStop(1, 'rgba(0,0,0,0)');
  lctx.fillStyle = g; lctx.fillRect(fx - R, fy - R, R * 2, R * 2);
  // faint personal visibility so you can always see yourself
  const px = sx(G.p.x), py = BASE_Y - 30;
  const g2 = lctx.createRadialGradient(px, py, 5, px, py, 150);
  g2.addColorStop(0, 'rgba(0,0,0,0.55)'); g2.addColorStop(1, 'rgba(0,0,0,0)');
  lctx.fillStyle = g2; lctx.fillRect(px - 150, py - 150, 300, 300);
  ctx.drawImage(lightC, 0, 0);
  // warm additive glow
  if (f.lit || f.ember > 0.05) {
    ctx.globalCompositeOperation = 'lighter';
    const gg = ctx.createRadialGradient(fx, fy, 5, fx, fy, R * 0.9);
    const a = f.lit ? 0.22 + f.flare * 0.15 : f.ember * 0.1;
    gg.addColorStop(0, `rgba(255,140,50,${a})`); gg.addColorStop(1, 'rgba(255,100,30,0)');
    ctx.fillStyle = gg; ctx.fillRect(fx - R, fy - R, R * 2, R * 2);
    ctx.globalCompositeOperation = 'source-over';
  }
}

function drawFireFlames() {
  const f = G.fire, x = sx(f.x), y = BASE_Y - 8;
  if (x < -100 || x > W + 100) return;
  if (!f.lit) {
    if (f.ember > 0.02) { ctx.fillStyle = `rgba(255,90,30,${f.ember * 0.8})`; for (let i = 0; i < 6; i++) ctx.fillRect(x - 14 + i * 5, y - 4 + Math.sin(i + G.t * 3), 3, 2); }
    return;
  }
  const hgt = 18 + f.fuel * 0.55 + f.flare * 30;
  ctx.globalCompositeOperation = 'lighter';
  const tongues = 5;
  for (let layer = 0; layer < 2; layer++) {
    for (let i = 0; i < tongues; i++) {
      const ox = (i - (tongues - 1) / 2) * 7 * (layer ? 0.6 : 1);
      const hh = hgt * (layer ? 0.6 : 1) * (0.6 + 0.4 * Math.sin(G.t * (9 + i) + i * 2) ** 2) * (i === 2 ? 1.2 : 0.85);
      const lean = G.wind * 10 + Math.sin(G.t * 11 + i) * 4;
      ctx.fillStyle = layer ? 'rgba(255,230,140,0.85)' : 'rgba(255,110,30,0.75)';
      ctx.beginPath(); ctx.moveTo(x + ox - 8, y);
      ctx.quadraticCurveTo(x + ox - 9 + lean * 0.3, y - hh * 0.5, x + ox + lean, y - hh);
      ctx.quadraticCurveTo(x + ox + 9 + lean * 0.3, y - hh * 0.5, x + ox + 8, y);
      ctx.closePath(); ctx.fill();
    }
  }
  ctx.globalCompositeOperation = 'source-over';
}

function drawRain() {
  if (!G.rain.length) return;
  const f = G.fire, fx = sx(f.x), fy = BASE_Y - 40, R = f.lit ? fireLight() * 0.9 : 0;
  const slant = G.wind * 140 / 900;
  const buckets = [[], [], [], []];
  for (const d of G.rain) {
    const dx = d.x - fx, dy = d.y - fy; const dist = Math.sqrt(dx * dx + dy * dy);
    const lit = R > 0 ? clamp(1 - dist / R, 0, 1) : 0;
    buckets[lit > 0.6 ? 3 : lit > 0.3 ? 2 : lit > 0.05 ? 1 : 0].push(d);
  }
  const styles = [`rgba(170,190,230,${0.22 + G.flash * 0.5})`, 'rgba(255,170,100,0.35)', 'rgba(255,190,120,0.55)', 'rgba(255,215,160,0.8)'];
  ctx.lineWidth = 1.2;
  buckets.forEach((b, i) => {
    if (!b.length) return;
    ctx.strokeStyle = styles[i]; ctx.beginPath();
    for (const d of b) { ctx.moveTo(d.x, d.y); ctx.lineTo(d.x - slant * d.l, d.y - d.l); }
    ctx.stroke();
  });
}

function drawBolt() {
  const b = G.bolt, r = mulberry32(b.seed | 0);
  ctx.strokeStyle = `rgba(230,235,255,${clamp(b.t / 0.22, 0, 1)})`; ctx.lineWidth = 3; ctx.shadowColor = '#aab8ff'; ctx.shadowBlur = 20;
  ctx.beginPath(); let x = b.x, y = 0; ctx.moveTo(x, y);
  while (y < 420) { x += (r() - 0.5) * 60; y += 20 + r() * 30; ctx.lineTo(x, y); }
  ctx.stroke(); ctx.shadowBlur = 0;
}

function drawForeground() {
  ctx.fillStyle = '#120a0c';
  for (const f of SCATTER.fg) {
    const x = f.x - G.camX * 1.25; if (x < -200 || x > W + 200) continue;
    ctx.beginPath(); ctx.ellipse(x, H + 10, f.w, f.h, 0, Math.PI, 0); ctx.fill();
  }
}

function drawVignette() {
  const p = G.p;
  const v = ctx.createRadialGradient(W / 2, H / 2, H * 0.4, W / 2, H / 2, H * 0.95);
  v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,0.55)');
  ctx.fillStyle = v; ctx.fillRect(0, 0, W, H);
  if (p.warmth < 40) {
    const a = (40 - p.warmth) / 40;
    const fr = ctx.createRadialGradient(W / 2, H / 2, H * 0.3, W / 2, H / 2, H * 0.85);
    fr.addColorStop(0, 'rgba(150,200,255,0)'); fr.addColorStop(1, `rgba(170,215,255,${0.55 * a})`);
    ctx.fillStyle = fr; ctx.fillRect(0, 0, W, H);
  }
}

function bubbleAt(x, y, text, color = '#f3e2c2') {
  ctx.font = 'bold 15px Georgia'; ctx.textAlign = 'center';
  const w = ctx.measureText(text).width + 16;
  ctx.fillStyle = 'rgba(20,12,10,0.8)'; roundRect(x - w / 2, y - 18, w, 24, 6); ctx.fill();
  ctx.fillStyle = color; ctx.fillText(text, x, y);
}
function roundRect(x, y, w, h, r) { ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }

// ---------- HUD ----------
function drawHUD(acts) {
  const p = G.p, f = G.fire;
  // panel
  ctx.fillStyle = 'rgba(28,14,10,0.72)'; roundRect(16, 16, 300, 178, 8); ctx.fill();
  ctx.strokeStyle = 'rgba(184,135,63,0.8)'; ctx.lineWidth = 1.5; ctx.stroke();
  ctx.textAlign = 'left'; ctx.fillStyle = '#ffd9a0'; ctx.font = 'bold 26px Georgia'; ctx.fillText(clockStr(), 30, 48);
  const phase = G.t < 110 ? 'Sundown' : G.t < 200 ? 'Storm rollin\' in' : G.t < 470 ? 'Stormy night' : 'Almost dawn';
  ctx.font = 'italic 14px Georgia'; ctx.fillStyle = '#e0a85a'; ctx.fillText(phase + ' · sunrise at 6:00 AM', 30, 70);
  const bar = (label, v, y, c1, c2) => {
    ctx.fillStyle = '#e9cfa5'; ctx.font = 'bold 12px Georgia'; ctx.fillText(label, 30, y + 10);
    ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(100, y, 190, 12);
    ctx.fillStyle = v < 25 && Math.sin(G.t * 8) > 0 ? '#ff5a4a' : c1; ctx.fillRect(100, y, 190 * v / 100, 12);
    ctx.fillStyle = c2; ctx.fillRect(100, y, 190 * v / 100, 3);
  };
  bar('WARMTH', p.warmth, 82, '#e8783a', '#ffc080');
  bar('BELLY', p.belly, 102, '#c8a050', '#f0d090');
  bar('FIRE', f.lit ? f.fuel : 0, 122, f.lit ? '#ffb030' : '#555', '#fff0a0');
  const inv = [`Wood ${p.wood}/${MAX_WOOD}`, p.weeds ? `Tumbleweed ${p.weeds}` : null, `Matches ${p.matches}`,
    p.can ? `Beans (${canState(p.can)})` : null, p.cup ? 'Tin cup' : null, p.hat ? null : 'NO HAT', p.blanket ? 'Blanket' : null,
    p.jerky ? `Jerky ${p.jerky}` : null, p.pears ? `Pears ${p.pears}` : null].filter(Boolean);
  ctx.font = '12px Georgia'; ctx.fillStyle = '#f3e2c2';
  ctx.fillText(inv.slice(0, 4).join('  ·  '), 30, 160);
  ctx.fillText(inv.slice(4).join('  ·  '), 30, 180);
  // toasts
  ctx.textAlign = 'center';
  G.toasts.forEach((tt, i) => {
    const a = clamp(Math.min(tt.t * 4, (tt.dur - tt.t) * 2), 0, 1);
    ctx.font = 'italic 18px Georgia';
    const w = ctx.measureText(tt.text).width + 30, y = 40 + i * 34;
    ctx.fillStyle = `rgba(20,10,8,${0.7 * a})`; roundRect(W / 2 + 80 - w / 2, y - 20, w, 28, 6); ctx.fill();
    ctx.globalAlpha = a; ctx.fillStyle = tt.color; ctx.fillText(tt.text, W / 2 + 80, y); ctx.globalAlpha = 1;
  });
  // speech
  if (p.say && p.sayT > 0) bubbleAt(sx(p.x), groundY(p.x) - 90, p.say);
  // context prompts above the player
  const shown = {}; const lines = [];
  acts.sort((a, b) => a.d - b.d).forEach(a => { if (shown[a.key]) return; shown[a.key] = true; if (a.key === 'C' && G.rac.state === 'hidden') return; lines.push(a); });
  let py = groundY(p.x) - (p.say && p.sayT > 0 ? 122 : 92);
  ctx.font = 'bold 14px Georgia';
  lines.slice(0, 4).forEach(a => {
    const txt = `[${a.key}] ${a.label}`; const w = ctx.measureText(txt).width + 16;
    ctx.fillStyle = a.fn ? 'rgba(40,20,10,0.85)' : 'rgba(40,30,30,0.7)'; roundRect(sx(p.x) - w / 2, py - 17, w, 23, 5); ctx.fill();
    ctx.fillStyle = a.fn ? '#ffd27a' : '#a89880'; ctx.fillText(txt, sx(p.x), py);
    py -= 27;
  });
  // off-screen arrow to camp
  const fxs = sx(f.x);
  if (fxs < 0 || fxs > W) {
    const left = fxs < 0; ctx.fillStyle = f.lit ? '#ffb030' : '#888';
    ctx.font = 'bold 16px Georgia'; ctx.textAlign = left ? 'left' : 'right';
    ctx.fillText(left ? '◀ camp' : 'camp ▶', left ? 16 : W - 16, BASE_Y - 140);
  }
  // off-screen markers for things you probably want back
  ctx.font = 'bold 14px Georgia';
  [[G.hatObj && G.hatObj.landed ? G.hatObj.x : null, 'hat'], [G.cupObj && G.cupObj.landed ? G.cupObj.x : null, 'cup'], [G.groundCan ? G.groundCan.x : null, 'beans']].forEach(([x, name], i) => {
    if (x === null) return; const s2 = sx(x); if (s2 >= 0 && s2 <= W) return;
    const left = s2 < 0; ctx.textAlign = left ? 'left' : 'right'; ctx.fillStyle = '#9ad0ff';
    ctx.fillText(left ? '◀ your ' + name : 'your ' + name + ' ▶', left ? 16 : W - 16, BASE_Y - 112 + i * 22);
  });
  // footer controls
  ctx.textAlign = 'left'; ctx.font = '12px Georgia'; ctx.fillStyle = 'rgba(243,226,194,0.6)';
  ctx.fillText('A/D move · Shift hurry · E use · B heat beans · F eat · C throw cup · S crouch · P pause · M mute · R restart', 16, H - 12);
}

// ---------- main loop ----------
let last = performance.now();
let titleT = 25;
function frame(now) {
  const rawDt = Math.min(0.05, (now - last) / 1000); last = now;
  if (mode === 'play') {
    const steps = Math.ceil(SPEED);
    for (let i = 0; i < steps && mode === 'play'; i++) update(rawDt * SPEED / steps);
    const acts = getActions();
    for (const k of ['E', 'B', 'F', 'C']) {
      if (pressed['Key' + k]) { const a = acts.filter(x => x.key === k && x.fn).sort((x, y) => x.d - y.d)[0]; if (a) a.fn(); }
    }
    if (mode === 'play') { render(); drawHUD(getActions()); }
  } else if (mode === 'title') {
    titleT += rawDt;
    G.t = 20 + Math.sin(titleT * 0.05) * 15; G.camX = 600 + Math.sin(titleT * 0.08) * 300;
    G.storm = 0; G.dark = 0.08; G.wind = 0.3 + Math.sin(titleT) * 0.1;
    updObjects(rawDt); updParticles(rawDt);
    render();
  } else if (mode === 'paused' || mode === 'won' || mode === 'lost') {
    if (mode === 'won' && G.t < 575) { G.t += rawDt * 4; G.storm = 0; G.night = 0; G.dark = 0.08; G.rain.length = 0; }
    render();
  }
  for (const k in pressed) delete pressed[k];
  requestAnimationFrame(frame);
}

function startGame() {
  Sound.init();
  newGame(); mode = 'play';
  document.getElementById('title').classList.add('hidden');
  document.getElementById('end').classList.add('hidden');
  document.getElementById('pause').classList.add('hidden');
  canvas.focus();
}

window.addEventListener('keydown', e => {
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space'].includes(e.code)) e.preventDefault();
  if (!keys[e.code]) pressed[e.code] = true;
  keys[e.code] = true;
  if (mode === 'title' && (e.code === 'Enter' || e.code === 'Space')) startGame();
  else if ((mode === 'won' || mode === 'lost') && (e.code === 'Enter' || e.code === 'KeyR' || e.code === 'Space')) startGame();
  else if (mode === 'play' && e.code === 'KeyR') startGame();
  else if (mode === 'play' && (e.code === 'KeyP' || e.code === 'Escape')) { mode = 'paused'; document.getElementById('pause').classList.remove('hidden'); Sound.setAmbience(0, 400, 0, 0); }
  else if (mode === 'paused' && (e.code === 'KeyP' || e.code === 'Escape')) { mode = 'play'; document.getElementById('pause').classList.add('hidden'); last = performance.now(); }
  else if (mode === 'paused' && e.code === 'KeyR') startGame();
  if (e.code === 'KeyM') Sound.toggleMute();
});
window.addEventListener('keyup', e => { keys[e.code] = false; });
window.addEventListener('blur', () => { for (const k in keys) keys[k] = false; if (mode === 'play') { mode = 'paused'; document.getElementById('pause').classList.remove('hidden'); } });
document.getElementById('startBtn').addEventListener('click', startGame);
document.getElementById('againBtn').addEventListener('click', startGame);

// test hook for automated checks (harmless in normal play)
window.__beans = { get G() { return G; }, get mode() { return mode; }, start: startGame };

newGame(); G.toasts = [];
requestAnimationFrame(frame);
})();
