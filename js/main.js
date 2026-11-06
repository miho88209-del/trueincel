import * as THREE from 'three';

const I18N = window.I18N, Sound = window.Sound;
const qs = new URLSearchParams(location.search);
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const rand = (a, b) => a + Math.random() * (b - a);
const SPEED = clamp(parseFloat(qs.get('speed')) || 1, 0.1, 60); // test hook: ?speed=10
const NIGHT_LEN = 540;
const MAX_WOOD = 4;

// ---------- settings ----------
const SET = { sens: 1, invert: false, vol: 0.8 };
try { Object.assign(SET, JSON.parse(localStorage.getItem('lastcan.settings') || '{}')); } catch (e) { /* ignore */ }
const saveSet = () => { try { localStorage.setItem('lastcan.settings', JSON.stringify(SET)); } catch (e) { /* ignore */ } };
Sound.setVolume(SET.vol);

// ---------- noise ----------
function hash(x, z) { const h = Math.sin(x * 127.1 + z * 311.7) * 43758.5453; return h - Math.floor(h); }
function vnoise(x, z) {
  const xi = Math.floor(x), zi = Math.floor(z), xf = x - xi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = zf * zf * (3 - 2 * zf);
  const a = hash(xi, zi), b = hash(xi + 1, zi), c = hash(xi, zi + 1), d = hash(xi + 1, zi + 1);
  return (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v) * 2 - 1;
}
function fbm(x, z, oct = 4) { let s = 0, a = 0.5, f = 1; for (let i = 0; i < oct; i++) { s += a * vnoise(x * f, z * f); f *= 2.03; a *= 0.5; } return s; }
function seeded(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

// ---------- canyon layout ----------
const BOWL = { cx: 0, cz: -8, rx: 48, rz: 70 };
const MESA = { cx: 0, cz: -8, rx: 28, rz: 22 }; // Coffin Rock, split by the slot canyon
const CAMP = { x: 5, z: 40 };
const HORSE_HOME = { x: -2.5, z: 43.5 };
const WAGON = { x: 10, z: -56 };
const OVERHANG = { x: -41, z: 16 };
const washX = z => 3 * Math.sin(z * 0.07) + 1.5 * Math.sin(z * 0.19 + 1);
function sdE(x, z, e) { const dx = (x - e.cx) / e.rx, dz = (z - e.cz) / e.rz; return (Math.sqrt(dx * dx + dz * dz) - 1) * Math.min(e.rx, e.rz); }
function cliff(d) { const s = clamp(d / 5, 0, 1); return 1 - Math.pow(1 - s, 2.5); }
function terrace(w) { const st = 3; const k = Math.floor(w / st), f = w / st - k; return 0.25 * w + 0.75 * (k + smooth(0.4, 1, f)) * st; }
function terrainInfo(x, z) {
  const n1 = fbm(x * 0.045 + 11, z * 0.045 - 3, 3);
  let floor = fbm(x * 0.06, z * 0.06, 3) * 0.7 + vnoise(x * 0.3, z * 0.3) * 0.08;
  const dOut = sdE(x, z, BOWL) + n1 * 7;
  const dMesa = -(sdE(x, z, MESA) + fbm(x * 0.07 + 5, z * 0.07 + 9, 3) * 4.5);
  let wall = 0;
  if (dOut > 0) wall = cliff(dOut) * (24 + n1 * 8 + Math.max(0, dOut - 6) * 0.4);
  if (dMesa > 0) wall = Math.max(wall, cliff(dMesa) * (17 + n1 * 5));
  const dA = Math.hypot(x - OVERHANG.x, z - OVERHANG.z);
  if (dA < 8) wall *= smooth(5.5, 8, dA);
  let wash = 0;
  if (z > -70 && z < 32) {
    const wd = Math.abs(x - washX(z));
    const along = smooth(-68, -58, z) * (1 - smooth(22, 30, z));
    wash = (1 - smooth(2.4, 5, wd)) * along;
    wall *= 1 - (1 - smooth(3.4, 6.5, wd)) * smooth(-72, -62, z) * (1 - smooth(24, 32, z));
  }
  floor -= wash * 1.4;
  return { h: floor + terrace(wall), wall, wash };
}
const groundH = (x, z) => terrainInfo(x, z).h;
const walkable = (x, z) => terrainInfo(x, z).wall < 0.9;

// ---------- renderer ----------
let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
} catch (e) {
  document.querySelector('#loading .tag').textContent = I18N.t('webgl_error');
  throw e;
}
const LOW = qs.get('quality') === 'low';
renderer.setPixelRatio(LOW ? 0.6 : Math.min(window.devicePixelRatio || 1, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
document.getElementById('view').appendChild(renderer.domElement);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 1500);
scene.fog = new THREE.Fog(0xc07050, 60, 520);
addEventListener('resize', () => { renderer.setSize(innerWidth, innerHeight); camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); });

const mat = (color, o = {}) => new THREE.MeshStandardMaterial(Object.assign({ color, roughness: 0.9, metalness: 0 }, o));
function mesh(geo, m, x = 0, y = 0, z = 0, parent) {
  const me = new THREE.Mesh(geo, m); me.position.set(x, y, z); me.castShadow = true; me.receiveShadow = true;
  (parent || scene).add(me); return me;
}
function texFromCanvas(w, h, draw) { const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t; }
const softTex = texFromCanvas(64, 64, (g, w) => { const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.4, 'rgba(255,255,255,0.5)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, w, w); });
const flameTex = texFromCanvas(64, 128, (g) => {
  const gr = g.createRadialGradient(32, 96, 2, 32, 80, 60);
  gr.addColorStop(0, 'rgba(255,250,210,1)'); gr.addColorStop(0.25, 'rgba(255,190,80,0.95)'); gr.addColorStop(0.6, 'rgba(255,90,20,0.5)'); gr.addColorStop(1, 'rgba(120,20,0,0)');
  g.fillStyle = gr; g.beginPath(); g.moveTo(32, 2); g.bezierCurveTo(58, 50, 62, 90, 32, 126); g.bezierCurveTo(2, 90, 6, 50, 32, 2); g.fill();
});

// ---------- terrain ----------
const colliders = []; // {x, z, r}
let terrainMat;
{
  const TS = 230, SEG = 200;
  const g = new THREE.PlaneGeometry(TS, TS, SEG, SEG); g.rotateX(-Math.PI / 2);
  const pos = g.attributes.position, n = pos.count;
  const info = new Array(n);
  for (let i = 0; i < n; i++) { const x = pos.getX(i), z = pos.getZ(i); const t = terrainInfo(x, z); info[i] = t; pos.setY(i, t.h); }
  g.computeVertexNormals();
  const nor = g.attributes.normal, col = new Float32Array(n * 3);
  const strata = ['#8e3b25', '#b5532f', '#c9774a', '#9e4229', '#d8a070', '#7a3020', '#b8603a', '#a34a2c'].map(c => new THREE.Color(c));
  const floorA = new THREE.Color('#8a4c32'), floorB = new THREE.Color('#b0724a'), washC = new THREE.Color('#a8917a'), top = new THREE.Color('#8c5a3c');
  const c = new THREE.Color();
  for (let i = 0; i < n; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i), t = info[i], ny = nor.getY(i);
    if (t.wall < 1.2) {
      c.copy(floorA).lerp(floorB, 0.5 + 0.5 * fbm(x * 0.08, z * 0.08, 3));
      c.lerp(washC, clamp(t.wash * 1.1, 0, 1));
    } else {
      const band = Math.floor((y + fbm(x * 0.05, z * 0.05, 2) * 2.5) / 1.7);
      c.copy(strata[((band % strata.length) + strata.length) % strata.length]);
      if (ny > 0.85 && t.wall > 4) c.lerp(top, 0.6);
    }
    const shade = 0.72 + 0.28 * clamp(ny, 0, 1) + vnoise(x * 0.9, z * 0.9) * 0.05;
    col[i * 3] = c.r * shade; col[i * 3 + 1] = c.g * shade; col[i * 3 + 2] = c.b * shade;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  terrainMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, metalness: 0 });
  const tm = new THREE.Mesh(g, terrainMat); tm.receiveShadow = true; tm.castShadow = true; scene.add(tm);
  // a big skirt so the horizon never shows a hole
  const skirt = new THREE.Mesh(new THREE.CircleGeometry(1200, 32).rotateX(-Math.PI / 2), mat(0x7a3a26));
  skirt.position.y = 20; scene.add(skirt);
}

// rock helper: noise-displaced icosahedron, flat shaded
const rockMats = ['#8a3e28', '#9c4a2e', '#7a3826', '#a85a3a'].map(c => mat(c, { flatShading: true, roughness: 0.95 }));
function rockGeo(seed, detail = 1) {
  const g = new THREE.IcosahedronGeometry(1, detail), p = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const k = 1 + 0.3 * fbm(v.x * 1.4 + seed, v.z * 1.4 + v.y * 1.1 + seed * 0.7, 3);
    v.multiplyScalar(k); if (v.y < -0.3) v.y = -0.3 + (v.y + 0.3) * 0.3;
    p.setXYZ(i, v.x, v.y, v.z);
  }
  g.computeVertexNormals(); return g;
}
function addRock(x, z, s, sy = 0.7, rot = 0, collide = true) {
  const r = mesh(rockGeo(x * 0.37 + z * 0.11), rockMats[Math.abs(Math.floor(x * 7 + z * 3)) % 4], x, groundH(x, z) + s * 0.15, z);
  r.scale.set(s, s * sy, s * (0.8 + hash(x, z) * 0.4)); r.rotation.y = rot;
  if (collide && s > 0.7) colliders.push({ x, z, r: s * 0.85 });
  return r;
}

// distant mesas for the horizon silhouette
{
  const r = seeded(4);
  for (let i = 0; i < 18; i++) {
    const a = i / 18 * Math.PI * 2 + r() * 0.2, d = 240 + r() * 200, rad = 25 + r() * 55, h = 40 + r() * 80;
    const g = new THREE.CylinderGeometry(rad * (0.75 + r() * 0.2), rad, h, 9, 3);
    const p = g.attributes.position;
    for (let k = 0; k < p.count; k++) { const s = 1 + (vnoise(p.getX(k) * 0.1 + i * 7, p.getY(k) * 0.08) * 0.18); p.setX(k, p.getX(k) * s); p.setZ(k, p.getZ(k) * s); }
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, mat(['#8a4030', '#9a5038', '#7a3828'][i % 3], { flatShading: true })); m.position.set(Math.cos(a) * d, h / 2 + 10, Math.sin(a) * d); scene.add(m);
  }
}

// ---------- sky ----------
const skyU = {
  uTop: { value: new THREE.Color() }, uMid: { value: new THREE.Color() }, uHor: { value: new THREE.Color() },
  uSunDir: { value: new THREE.Vector3(-1, 0.2, 0.2).normalize() }, uSunCol: { value: new THREE.Color(1, 0.6, 0.3) }, uSunVis: { value: 1 },
  uStorm: { value: 0 }, uTime: { value: 0 }, uFlash: { value: 0 }, uCloudDark: { value: new THREE.Color() }, uCloudLit: { value: new THREE.Color() },
};
const sky = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), new THREE.ShaderMaterial({
  uniforms: skyU, side: THREE.BackSide, depthWrite: false, fog: false,
  vertexShader: `varying vec3 vDir; void main(){ vDir = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position,1.0); gl_Position = p.xyww; }`,
  fragmentShader: `
    uniform vec3 uTop, uMid, uHor, uSunDir, uSunCol, uCloudDark, uCloudLit; uniform float uStorm, uTime, uFlash, uSunVis;
    varying vec3 vDir;
    float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
    float noise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
      return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y); }
    float fbm(vec2 p){ float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++){ s += a*noise(p); p = p*2.03 + 17.0; a *= 0.5; } return s; }
    void main(){
      vec3 d = normalize(vDir); float h = d.y;
      vec3 col = mix(uMid, uTop, smoothstep(0.0, 0.55, h));
      col = mix(uHor, col, smoothstep(-0.02, 0.2, h));
      float sd = max(dot(d, uSunDir), 0.0);
      col += uSunCol * (pow(sd, 6.0) * 0.45 + pow(sd, 600.0) * 8.0 * uSunVis);
      if (h > -0.05) {
        vec2 uv = d.xz / (h + 0.16) * 0.9 + vec2(uTime * 0.012, uTime * 0.005);
        float n = fbm(uv);
        float cover = mix(0.6, 0.3, uStorm);
        float c = smoothstep(cover, cover + 0.22, n) * smoothstep(-0.05, 0.1, h);
        vec3 cc = mix(uCloudDark, uCloudLit, clamp(pow(sd, 2.0) * 0.9 + (1.0 - n) * 0.3, 0.0, 1.0));
        cc = mix(cc, vec3(0.75, 0.8, 1.0), uFlash * 0.8);
        col = mix(col, cc, c * mix(0.8, 0.98, uStorm));
      }
      gl_FragColor = vec4(col, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
}));
sky.renderOrder = -1; sky.frustumCulled = false; scene.add(sky);
const SKY = [
  [0, '#3a4a8a', '#e0806a', '#ffc080'], [90, '#283060', '#b85a5a', '#f09050'], [170, '#161c38', '#3e3450', '#5a3a40'],
  [240, '#0b0f1e', '#151a2c', '#1c2030'], [470, '#0b0f1e', '#151a2c', '#1c2030'], [505, '#202a52', '#6a5478', '#c08070'], [545, '#5a80c0', '#f0a888', '#ffd890'],
].map(k => [k[0], new THREE.Color(k[1]), new THREE.Color(k[2]), new THREE.Color(k[3])]);
function skyAt(t, out) {
  for (let i = 0; i < SKY.length - 1; i++) {
    const a = SKY[i], b = SKY[i + 1];
    if (t <= b[0]) { const u = smooth(a[0], b[0], t); for (let k = 0; k < 3; k++) out[k].copy(a[k + 1]).lerp(b[k + 1], u); return; }
  }
  const l = SKY[SKY.length - 1]; for (let k = 0; k < 3; k++) out[k].copy(l[k + 1]);
}

// ---------- lights ----------
const hemi = new THREE.HemisphereLight(0xffc8a0, 0x5a3020, 1.0); scene.add(hemi);
const sun = new THREE.DirectionalLight(0xffa060, 2.5); sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048); Object.assign(sun.shadow.camera, { left: -45, right: 45, top: 45, bottom: -45, near: 1, far: 300 });
sun.shadow.bias = -0.0005; sun.shadow.normalBias = 0.04; scene.add(sun); scene.add(sun.target);
const moon = new THREE.DirectionalLight(0x8090c0, 0.0); moon.position.set(30, 100, 20); scene.add(moon);
const fireLight = new THREE.PointLight(0xff8a3a, 10, 40, 1.5); fireLight.castShadow = true;
fireLight.shadow.mapSize.set(512, 512); fireLight.shadow.camera.near = 0.3; fireLight.shadow.camera.far = 40; fireLight.shadow.bias = -0.002;
fireLight.position.set(CAMP.x, groundH(CAMP.x, CAMP.z) + 1.2, CAMP.z); scene.add(fireLight);
// Weak GPUs: drop the expensive shadows and resolution (automatic after a slow start, or ?quality=low).
let lowApplied = false;
function applyLowQuality() {
  if (lowApplied) return; lowApplied = true;
  fireLight.castShadow = false; sun.shadow.mapSize.set(1024, 1024); if (sun.shadow.map) { sun.shadow.map.dispose(); sun.shadow.map = null; }
  renderer.setPixelRatio(Math.min(renderer.getPixelRatio(), LOW ? 0.6 : 0.8));
}
if (LOW) applyLowQuality();

// ---------- vegetation ----------
const grassU = { uTime: { value: 0 }, uWind: { value: 0.3 } };
{
  const blade = new THREE.BufferGeometry();
  const v = [], r = seeded(77);
  for (let b = 0; b < 7; b++) {
    const a = r() * Math.PI * 2, d = r() * 0.12, h = 0.35 + r() * 0.45, w = 0.03, lean = 0.15 + r() * 0.2;
    const cx = Math.cos(a) * d, cz = Math.sin(a) * d, tx = Math.cos(a) * lean, tz = Math.sin(a) * lean, px = -Math.sin(a) * w, pz = Math.cos(a) * w;
    v.push(cx - px, 0, cz - pz, cx + px, 0, cz + pz, cx + tx, h, cz + tz);
  }
  blade.setAttribute('position', new THREE.Float32BufferAttribute(v, 3)); blade.computeVertexNormals();
  const gm = mat(0xc89a58, { side: THREE.DoubleSide, roughness: 1 });
  gm.onBeforeCompile = sh => {
    sh.uniforms.uTime = grassU.uTime; sh.uniforms.uWind = grassU.uWind;
    sh.vertexShader = 'uniform float uTime; uniform float uWind;\n' + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      vec4 gw = instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0);
      float sway = sin(uTime * (1.5 + uWind * 2.0) + gw.x * 0.35 + gw.z * 0.25) * (0.15 + uWind * 0.35) + uWind * 0.5;
      transformed.x += sway * position.y * 0.6; transformed.z += sway * position.y * 0.25;`);
  };
  const N = 4200, inst = new THREE.InstancedMesh(blade, gm, N), m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), s3 = new THREE.Vector3(), p3 = new THREE.Vector3();
  let k = 0, tries = 0;
  while (k < N && tries < N * 6) {
    tries++;
    const x = rand(-48, 48), z = rand(-78, 62); const t = terrainInfo(x, z);
    if (t.wall > 0.15 || t.wash > 0.3 || Math.hypot(x - CAMP.x, z - CAMP.z) < 3.5) continue;
    if (fbm(x * 0.07 + 40, z * 0.07, 2) < -0.15) continue; // patchy
    q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.random() * 6.28); const s = 0.7 + Math.random() * 0.9;
    m4.compose(p3.set(x, t.h - 0.02, z), q, s3.set(s, s, s)); inst.setMatrixAt(k++, m4);
  }
  inst.count = k; inst.receiveShadow = true; scene.add(inst);
}
// sagebrush (raccoon hiding spots near camp + scatter)
const sageSpots = [];
const sageMat = mat(0x6a7a5a, { flatShading: true });
function addSage(x, z, s) {
  const g = new THREE.Group(); g.position.set(x, groundH(x, z), z); scene.add(g);
  for (let i = 0; i < 4; i++) { const b = mesh(rockGeo(x + i * 3.1, 1), sageMat, rand(-0.4, 0.4) * s, 0.35 * s, rand(-0.4, 0.4) * s, g); b.scale.set(0.55 * s, 0.45 * s, 0.55 * s); }
  return g;
}
for (let i = 0; i < 7; i++) { const a = i / 7 * Math.PI * 2 + 0.3, d = 12 + (i % 3) * 1.5; const x = CAMP.x + Math.cos(a) * d, z = CAMP.z + Math.sin(a) * d; if (walkable(x, z)) sageSpots.push({ x, z, g: addSage(x, z, 1.1) }); }
{ const r = seeded(9); for (let i = 0; i < 40; i++) { const x = -45 + r() * 90, z = -76 + r() * 136; const t = terrainInfo(x, z); if (t.wall < 0.2 && t.wash < 0.2) addSage(x, z, 0.6 + r() * 0.7); } }

// boulders and fallen slabs
{
  const r = seeded(21); let placed = 0;
  for (let i = 0; i < 400 && placed < 55; i++) {
    const x = -46 + r() * 92, z = -76 + r() * 136; const t = terrainInfo(x, z);
    if (t.wall > 0.5 || t.wash > 0.4) continue;
    const near = [CAMP, WAGON, OVERHANG].some(p => Math.hypot(x - p.x, z - p.z) < 9);
    if (near) continue;
    const edge = terrainInfo(x + 4, z).wall + terrainInfo(x - 4, z).wall + terrainInfo(x, z + 4).wall + terrainInfo(x, z - 4).wall;
    if (edge < 1 && r() < 0.6) continue; // cluster rocks at the base of cliffs
    addRock(x, z, 0.5 + r() * 2.2, 0.5 + r() * 0.5, r() * 6); placed++;
  }
}

// ---------- props ----------
const M = {
  wood: mat(0x5e3e26), woodDark: mat(0x3a2416), woodPale: mat(0x8a6a4a), canvas: mat(0xd8c8a8, { side: THREE.DoubleSide }), iron: mat(0x3a3a3e, { metalness: 0.6, roughness: 0.5 }),
  tin: mat(0xb0b8c0, { metalness: 0.8, roughness: 0.35 }), label: mat(0xb8322a), stone: mat(0x5a5050, { flatShading: true }), cactus: mat(0x4a6a3a, { flatShading: true }),
  fruit: mat(0xd0507a), red: mat(0x8a2a22), blanket: mat(0x8a2a22), ash: mat(0x1a1210, { roughness: 1 }),
};
function logMesh(len, r, m, parent) { return mesh(new THREE.CylinderGeometry(r, r * 1.1, len, 7), m || M.wood, 0, 0, 0, parent); }

// camp
const camp = new THREE.Group(); camp.position.set(CAMP.x, groundH(CAMP.x, CAMP.z), CAMP.z); scene.add(camp);
for (let i = 0; i < 10; i++) { const a = i / 10 * Math.PI * 2; const s = mesh(rockGeo(i * 1.7, 0), M.stone, Math.cos(a) * 0.75, 0.08, Math.sin(a) * 0.75, camp); s.scale.set(0.22, 0.16, 0.2); }
mesh(new THREE.CircleGeometry(0.7, 16).rotateX(-Math.PI / 2), M.ash, 0, 0.02, 0, camp);
for (let i = 0; i < 4; i++) { const l = logMesh(1.0, 0.07, M.woodDark, camp); l.rotation.z = Math.PI / 2 - 0.35; l.rotation.y = i * Math.PI / 4 * 2 + 0.3; l.position.y = 0.18; }
{ const roll = mesh(new THREE.CylinderGeometry(0.3, 0.3, 1.9, 12), M.blanket, 2.8, 0.25, 1.4, camp); roll.rotation.z = Math.PI / 2; roll.rotation.y = 0.4;
  const saddle = mesh(new THREE.SphereGeometry(0.35, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), mat(0x6a3a1e), -1.8, 0.05, 2.0, camp); saddle.scale.set(1.2, 0.8, 0.8);
  const cof = mesh(new THREE.CylinderGeometry(0.09, 0.11, 0.25, 10), M.iron, 0.9, 0.12, -0.6, camp); cof.rotation.z = 0.2; }
// grate over the fire for the bean can
{ const gr = mesh(new THREE.BoxGeometry(0.9, 0.03, 0.5), M.iron, 0.25, 0.42, 0, camp); gr.castShadow = false;
  for (const sx of [-0.18, 0.68]) mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.42, 5), M.iron, sx, 0.21, 0, camp); }
// canvas tarp (rigged later)
const tarp = new THREE.Group(); tarp.visible = false; camp.add(tarp);
{ for (const [x, z] of [[-1.6, -1.6], [1.6, -1.6]]) { const p = logMesh(2.6, 0.04, M.woodPale, tarp); p.position.set(x, 1.3, z); }
  for (const [x, z] of [[-1.6, 1.8], [1.6, 1.8]]) { const p = logMesh(1.6, 0.04, M.woodPale, tarp); p.position.set(x, 0.8, z); }
  const cl = mesh(new THREE.PlaneGeometry(3.6, 3.8, 6, 6), M.canvas, 0, 2.05, 0.1, tarp); cl.rotation.x = -Math.PI / 2 + 0.28;
  const cp = cl.geometry.attributes.position; for (let i = 0; i < cp.count; i++) cp.setZ(i, cp.getZ(i) - Math.abs(Math.sin(cp.getX(i) * 0.9)) * 0.12); cl.geometry.computeVertexNormals(); }
// bean can (shared mesh)
function makeCan() { const g = new THREE.Group(); mesh(new THREE.CylinderGeometry(0.09, 0.09, 0.2, 14), M.tin, 0, 0.1, 0, g); const lb = mesh(new THREE.CylinderGeometry(0.092, 0.092, 0.1, 14), M.label.clone(), 0, 0.1, 0, g); g.userData.label = lb; return g; }
const fireCan = makeCan(); fireCan.position.set(0.3, 0.44, 0); fireCan.visible = false; camp.add(fireCan);
// hitching post
{ const hp = new THREE.Group(); hp.position.set(HORSE_HOME.x - 1.6, groundH(HORSE_HOME.x - 1.6, HORSE_HOME.z), HORSE_HOME.z); scene.add(hp);
  for (const z of [-1, 1]) { const p = logMesh(1.3, 0.07, M.woodDark, hp); p.position.set(0, 0.65, z); }
  const bar = logMesh(2.3, 0.06, M.woodDark, hp); bar.rotation.x = Math.PI / 2; bar.position.y = 1.15; colliders.push({ x: HORSE_HOME.x - 1.6, z: HORSE_HOME.z, r: 0.6 }); }

// fire visuals
const flameGroup = new THREE.Group(); camp.add(flameGroup);
const flames = [];
for (let i = 0; i < 7; i++) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: flameTex, color: 0xffffff, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false }));
  s.userData = { ox: rand(-0.22, 0.22), oz: rand(-0.22, 0.22), ph: rand(0, 6), sc: i < 3 ? 1 : 0.6 }; flameGroup.add(s); flames.push(s);
}
const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: softTex, color: 0xff7a2a, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: 0.35, fog: false }));
glow.scale.set(5, 5, 1); glow.position.y = 0.8; camp.add(glow);

// particles: embers + smoke + steam
function makePoints(n, color, size, additive) {
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
  const m = new THREE.PointsMaterial({ color, size, map: softTex, transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending, opacity: additive ? 1 : 0.35 });
  const p = new THREE.Points(g, m); p.frustumCulled = false; scene.add(p);
  return { p, n, data: Array.from({ length: n }, () => ({ x: 0, y: -999, z: 0, vx: 0, vy: 0, vz: 0, life: 0 })) };
}
const embers = makePoints(140, 0xffa040, 0.12, true);
const smoke = makePoints(70, 0x555058, 1.6, false);
const puffs = makePoints(80, 0xb0b8a0, 1.0, false);
function emit(sys, x, y, z, vx, vy, vz, life) { const d = sys.data.find(q => q.life <= 0); if (!d) return; Object.assign(d, { x, y, z, vx, vy, vz, life }); }
function puff(x, y, z, n = 10, sp = 1.2) { for (let i = 0; i < n; i++) emit(puffs, x, y, z, rand(-sp, sp), rand(0, sp), rand(-sp, sp), rand(0.6, 1.4)); }
function sparks(n = 20) { for (let i = 0; i < n; i++) emit(embers, CAMP.x + rand(-0.3, 0.3), camp.position.y + 0.5, CAMP.z + rand(-0.3, 0.3), rand(-1.5, 1.5), rand(2, 5), rand(-1.5, 1.5), rand(0.8, 2)); }

// rain
const RAIN_N = 3200, RAIN_BOX = 34;
const rainGeo = new THREE.BufferGeometry();
rainGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(RAIN_N * 6), 3));
rainGeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(RAIN_N * 6), 3));
const rain = new THREE.LineSegments(rainGeo, new THREE.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.55, depthWrite: false }));
rain.frustumCulled = false; scene.add(rain);
const drops = Array.from({ length: RAIN_N }, () => ({ x: rand(-RAIN_BOX, RAIN_BOX), y: rand(0, 30), z: rand(-RAIN_BOX, RAIN_BOX), v: rand(16, 22) }));

// lightning bolt
const boltGeo = new THREE.BufferGeometry(); boltGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(30 * 3), 3));
const bolt = new THREE.Line(boltGeo, new THREE.LineBasicMaterial({ color: 0xe8ecff, fog: false, transparent: true })); bolt.visible = false; bolt.frustumCulled = false; scene.add(bolt);

// wood sources
const woodSources = [];
function addWoodPile(x, z, n, kind) {
  const g = new THREE.Group(); g.position.set(x, groundH(x, z), z); scene.add(g);
  const logs = [];
  for (let i = 0; i < n; i++) {
    const l = logMesh(rand(0.9, 1.3), rand(0.06, 0.09), kind === 'drift' ? M.woodPale : M.wood, g);
    l.rotation.z = Math.PI / 2; l.rotation.y = rand(-0.6, 0.6) + i; l.position.set(rand(-0.3, 0.3), 0.08 + (i % 3) * 0.1, rand(-0.3, 0.3)); logs.push(l);
  }
  const w = { x, z, n, kind, logs, g }; woodSources.push(w); return w;
}
function addDeadTree(x, z, n) {
  const g = new THREE.Group(); g.position.set(x, groundH(x, z), z); scene.add(g);
  const tr = mesh(new THREE.CylinderGeometry(0.12, 0.28, 4.2, 7), M.woodDark, 0, 2.1, 0, g); tr.rotation.z = 0.08;
  const logs = [];
  for (let i = 0; i < n; i++) { const b = new THREE.Group(); b.position.y = 1.6 + i * 0.7; b.rotation.y = i * 2.1; g.add(b);
    const br = mesh(new THREE.CylinderGeometry(0.04, 0.08, 1.7, 5), M.woodDark, 0.7, 0.4, 0, b); br.rotation.z = -1.0; logs.push(b); }
  colliders.push({ x, z, r: 0.45 });
  const w = { x, z, n, kind: 'tree', logs, g }; woodSources.push(w); return w;
}
addWoodPile(14, 47, 2, 'pile'); addWoodPile(-7, 31, 2, 'pile'); addWoodPile(17, 30, 2, 'pile');
addDeadTree(36, 2, 3); addDeadTree(33, -32, 3); addWoodPile(30, 20, 2, 'pile'); addWoodPile(-31, -32, 2, 'pile'); addWoodPile(-34, 34, 2, 'pile');
addWoodPile(OVERHANG.x - 2.2, OVERHANG.z - 1.2, 3, 'dry'); addWoodPile(OVERHANG.x - 1.2, OVERHANG.z + 2.2, 3, 'dry');
for (const z of [6, -18, -42]) addWoodPile(washX(z) + 0.8, z, 2, 'drift');

// overhang roof slab + cow skull
{
  const slab = mesh(rockGeo(5.5, 2), rockMats[1], OVERHANG.x - 2.5, groundH(OVERHANG.x, OVERHANG.z) + 4.4, OVERHANG.z);
  slab.scale.set(5.5, 1.3, 6.5);
  const back = mesh(rockGeo(8.1, 1), rockMats[2], OVERHANG.x - 6.5, groundH(OVERHANG.x, OVERHANG.z) + 2, OVERHANG.z); back.scale.set(2.5, 4, 6);
  colliders.push({ x: OVERHANG.x - 6.5, z: OVERHANG.z, r: 2.4 });
  const sk = mesh(new THREE.SphereGeometry(0.18, 8, 6), mat(0xe8e0d0), OVERHANG.x + 1, groundH(OVERHANG.x + 1, OVERHANG.z + 3) + 0.12, OVERHANG.z + 3); sk.scale.set(1, 0.7, 1.5);
}

// cacti
const cacti = [];
function addPear(x, z, n) {
  const g = new THREE.Group(); g.position.set(x, groundH(x, z), z); scene.add(g);
  [[0, 0.3, 0, 0.3], [-0.3, 0.65, 0.05, 0.24], [0.3, 0.7, -0.05, 0.24], [0.05, 1.0, 0, 0.2]].forEach(([px, py, pz, s]) => { const p = mesh(new THREE.SphereGeometry(1, 8, 6), M.cactus, px, py, pz, g); p.scale.set(s, s * 1.25, s * 0.3); p.rotation.z = px; });
  const fruits = []; for (let i = 0; i < n; i++) fruits.push(mesh(new THREE.SphereGeometry(0.08, 8, 6), M.fruit, -0.35 + i * 0.6, 0.95 + i * 0.05, 0.06, g));
  colliders.push({ x, z, r: 0.5 });
  const c = { x, z, n, fruits }; cacti.push(c); return c;
}
function addSaguaro(x, z, h) {
  const g = new THREE.Group(); g.position.set(x, groundH(x, z), z); scene.add(g);
  mesh(new THREE.CapsuleGeometry(0.28, h, 4, 10), M.cactus, 0, h / 2 + 0.2, 0, g);
  const arm = (side, y, l) => { const a = mesh(new THREE.CapsuleGeometry(0.18, 0.5, 4, 8), M.cactus, side * 0.5, y, 0, g); a.rotation.z = side * Math.PI / 2;
    mesh(new THREE.CapsuleGeometry(0.17, l, 4, 8), M.cactus, side * 0.78, y + l / 2, 0, g); };
  arm(-1, h * 0.45, h * 0.3); if (h > 3.5) arm(1, h * 0.6, h * 0.25);
  colliders.push({ x, z, r: 0.5 });
}
addPear(39, -14, 2); addPear(26, 12, 2); addPear(-36, -10, 2);
addSaguaro(22, 52, 4.2); addSaguaro(-20, 42, 3.4); addSaguaro(40, 26, 4.5); addSaguaro(-30, -48, 4); addSaguaro(28, -52, 3.6); addSaguaro(-38, 6, 3.2);

// abandoned wagon
const wagon = { x: WAGON.x, z: WAGON.z, searched: false, boards: 4, boardMeshes: [], cover: null };
{
  const g = new THREE.Group(); g.position.set(WAGON.x, groundH(WAGON.x, WAGON.z), WAGON.z); g.rotation.y = 0.55; scene.add(g);
  const body = new THREE.Group(); body.rotation.z = 0.09; body.rotation.x = -0.04; g.add(body);
  mesh(new THREE.BoxGeometry(1.7, 0.12, 3.6), M.wood, 0, 0.95, 0, body);
  for (const s of [-1, 1]) for (let i = 0; i < 2; i++) { const b = mesh(new THREE.BoxGeometry(0.06, 0.22, 3.6), i ? M.wood : M.woodDark, s * 0.84, 1.13 + i * 0.22, 0, body); wagon.boardMeshes.push(b); }
  mesh(new THREE.BoxGeometry(1.7, 0.45, 0.06), M.woodDark, 0, 1.2, -1.8, body);
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 0.38), new THREE.MeshStandardMaterial({ map: texFromCanvas(512, 76, (c, w, h) => {
    c.fillStyle = '#4a2c1a'; c.fillRect(0, 0, w, h); c.fillStyle = '#e8d2a0'; c.font = 'bold 38px Georgia, serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText("DR. GRIMSBY'S TONIC", w / 2, h / 2 + 2);
    c.strokeStyle = '#e8d2a0'; c.lineWidth = 3; c.strokeRect(6, 6, w - 12, h - 12); }), roughness: 0.9 }));
  sign.position.set(0.89, 1.25, 0); sign.rotation.y = Math.PI / 2; body.add(sign);
  const cover = new THREE.Group(); body.add(cover); wagon.cover = cover;
  const cv = mesh(new THREE.CylinderGeometry(0.95, 0.95, 3.0, 16, 4, true, -Math.PI / 2, Math.PI), M.canvas, 0, 1.25, 0.1, cover); cv.rotation.x = Math.PI / 2; cv.rotation.y = Math.PI / 2;
  const cp = cv.geometry.attributes.position; for (let i = 0; i < cp.count; i++) { const y = cp.getY(i); if (y > 1.2 && cp.getX(i) > 0.2) cp.setX(i, cp.getX(i) * 0.8); } cv.geometry.computeVertexNormals();
  for (const z of [-1.3, 0, 1.3]) { const hp = mesh(new THREE.TorusGeometry(0.95, 0.03, 5, 16, Math.PI), M.woodPale, 0, 1.25, z, body); }
  const wheel = (x, y, z, flat) => { const w = new THREE.Group(); w.position.set(x, y, z); body.add(w);
    mesh(new THREE.TorusGeometry(0.55, 0.05, 6, 20), M.woodDark, 0, 0, 0, w);
    for (let k = 0; k < 6; k++) { const s = mesh(new THREE.CylinderGeometry(0.025, 0.025, 1.1, 4), M.woodDark, 0, 0, 0, w); s.rotation.z = k * Math.PI / 6; }
    w.rotation.y = Math.PI / 2; if (flat) { w.rotation.set(Math.PI / 2, 0, 0.3); } return w; };
  wheel(0.95, 0.55, 1.2); wheel(-0.95, 0.55, 1.2); wheel(-0.95, 0.5, -1.2); wheel(2.0, 0.07, -1.6, true);
  mesh(new THREE.BoxGeometry(0.4, 0.4, 0.4), M.woodDark, 0.85, 0.3, -1.2, body);
  const tongue = mesh(new THREE.BoxGeometry(0.1, 0.1, 2.4), M.woodDark, 0, 0.35, 2.9, g); tongue.rotation.x = 0.25;
  mesh(new THREE.BoxGeometry(0.6, 0.5, 0.6), M.woodPale, -1.8, 0.25, 0.8, g).rotation.y = 0.4;
  const barrel = mesh(new THREE.CylinderGeometry(0.32, 0.32, 0.8, 12), M.wood, -2.1, 0.32, -0.7, g); barrel.rotation.x = Math.PI / 2; barrel.rotation.z = 0.5;
  const c = Math.cos(0.55), s = Math.sin(0.55);
  for (const d of [-1.3, 0, 1.3]) colliders.push({ x: WAGON.x + s * d, z: WAGON.z + c * d, r: 1.15 });
  colliders.push({ x: WAGON.x + c * -1.8 + s * 0.8, z: WAGON.z - s * -1.8 + c * 0.8, r: 0.45 });
  const lantern = new THREE.PointLight(0xffc070, 0, 8, 2); lantern.position.set(0, 1.6, 0); g.add(lantern); wagon.glint = lantern;
}

// ---------- characters ----------
function makeCowboy() {
  const g = new THREE.Group(); scene.add(g);
  const body = new THREE.Group(); g.add(body);
  const coat = mat(0x6e4a2e), pants = mat(0x3a3a48), skin = mat(0xc98d5e), boot = mat(0x2a1a10), band = mat(0xa3262a);
  const limb = (x, y, r, l, m) => { const p = new THREE.Group(); p.position.set(x, y, 0); body.add(p); mesh(new THREE.CapsuleGeometry(r, l, 4, 8), m, 0, -l / 2 - r, 0, p); return p; };
  const legL = limb(-0.12, 0.95, 0.085, 0.72, pants), legR = limb(0.12, 0.95, 0.085, 0.72, pants);
  for (const lg of [legL, legR]) mesh(new THREE.BoxGeometry(0.15, 0.12, 0.28), boot, 0, -0.9, 0.05, lg);
  mesh(new THREE.CapsuleGeometry(0.21, 0.42, 4, 10), coat, 0, 1.35, 0, body);
  const skirt = mesh(new THREE.CylinderGeometry(0.24, 0.34, 0.6, 10, 1, true), mat(0x6e4a2e, { side: THREE.DoubleSide }), 0, 0.93, 0, body);
  const armL = limb(-0.3, 1.55, 0.065, 0.5, coat), armR = limb(0.3, 1.55, 0.065, 0.5, coat);
  mesh(new THREE.ConeGeometry(0.17, 0.16, 8), band, 0, 1.66, 0.02, body).rotation.x = Math.PI;
  const head = mesh(new THREE.SphereGeometry(0.15, 12, 10), skin, 0, 1.84, 0, body);
  mesh(new THREE.BoxGeometry(0.04, 0.05, 0.06), skin, 0, 1.83, 0.16, body);
  mesh(new THREE.BoxGeometry(0.2, 0.06, 0.1), mat(0x3a2418), 0, 1.75, 0.1, body);
  const hat = new THREE.Group(); hat.position.set(0, 1.95, 0); body.add(hat);
  const hatM = mat(0x4a3020);
  mesh(new THREE.CylinderGeometry(0.36, 0.36, 0.025, 18), hatM, 0, 0, 0, hat);
  mesh(new THREE.CylinderGeometry(0.15, 0.18, 0.2, 12), hatM, 0, 0.1, 0, hat);
  mesh(new THREE.CylinderGeometry(0.182, 0.182, 0.04, 12), mat(0x1a100a), 0, 0.03, 0, hat);
  const blanket = mesh(new THREE.CylinderGeometry(0.25, 0.32, 0.5, 10, 1, true), mat(0x8a2a22, { side: THREE.DoubleSide }), 0, 1.45, -0.02, body); blanket.visible = false;
  return { g, body, legL, legR, armL, armR, hat, blanket, skirt, head };
}
function makeHatMesh() { const hat = new THREE.Group(); const hatM = mat(0x4a3020); mesh(new THREE.CylinderGeometry(0.36, 0.36, 0.025, 18), hatM, 0, 0, 0, hat); mesh(new THREE.CylinderGeometry(0.15, 0.18, 0.2, 12), hatM, 0, 0.1, 0, hat); scene.add(hat); return hat; }
function makeHorse() {
  const g = new THREE.Group(); scene.add(g);
  const rig = new THREE.Group(); g.add(rig);
  const coat = mat(0x7a4a2a), dark = mat(0x2e1a10);
  const bodyM = mesh(new THREE.CapsuleGeometry(0.42, 1.3, 6, 12), coat, 0, 1.42, 0, rig); bodyM.rotation.x = Math.PI / 2;
  mesh(new THREE.BoxGeometry(0.9, 0.08, 0.8), mat(0x2a4a6a), 0, 1.84, -0.05, rig);
  const legs = [];
  for (const [x, z] of [[-0.24, 0.62], [0.24, 0.62], [-0.24, -0.62], [0.24, -0.62]]) { const p = new THREE.Group(); p.position.set(x, 1.25, z); rig.add(p); mesh(new THREE.CylinderGeometry(0.08, 0.06, 1.2, 6), coat, 0, -0.6, 0, p); mesh(new THREE.CylinderGeometry(0.075, 0.08, 0.1, 6), dark, 0, -1.2, 0, p); legs.push(p); }
  const neck = new THREE.Group(); neck.position.set(0, 1.65, 0.85); rig.add(neck);
  const nk = mesh(new THREE.CapsuleGeometry(0.2, 0.7, 4, 8), coat, 0, 0.35, 0.15, neck); nk.rotation.x = 0.5;
  mesh(new THREE.BoxGeometry(0.06, 0.55, 0.3), dark, 0, 0.45, 0.0, neck).rotation.x = 0.5;
  const head = new THREE.Group(); head.position.set(0, 0.8, 0.45); neck.add(head);
  const hm = mesh(new THREE.BoxGeometry(0.26, 0.26, 0.62), coat, 0, 0, 0.2, head); hm.rotation.x = 0.35;
  mesh(new THREE.BoxGeometry(0.1, 0.03, 0.3), mat(0xe8dcc8), 0, 0.1, 0.3, head).rotation.x = 0.35;
  for (const s of [-1, 1]) { mesh(new THREE.ConeGeometry(0.05, 0.18, 5), coat, s * 0.09, 0.2, -0.05, head); mesh(new THREE.SphereGeometry(0.03, 6, 4), dark, s * 0.13, 0.06, 0.1, head); }
  const tail = new THREE.Group(); tail.position.set(0, 1.55, -1.0); rig.add(tail);
  mesh(new THREE.CylinderGeometry(0.03, 0.1, 0.9, 6), dark, 0, -0.45, -0.1, tail).rotation.x = 0.25;
  return { g, rig, legs, neck, head, tail };
}
function makeRaccoon() {
  const g = new THREE.Group(); scene.add(g);
  const fur = mat(0x7a7570), dark = mat(0x2a2624);
  const b = mesh(new THREE.SphereGeometry(1, 10, 8), fur, 0, 0.26, 0, g); b.scale.set(0.22, 0.18, 0.32);
  const head = mesh(new THREE.SphereGeometry(0.13, 10, 8), fur, 0, 0.36, 0.33, g);
  mesh(new THREE.BoxGeometry(0.24, 0.06, 0.08), dark, 0, 0.38, 0.41, g);
  mesh(new THREE.ConeGeometry(0.05, 0.09, 6), fur, -0.08, 0.5, 0.31, g); mesh(new THREE.ConeGeometry(0.05, 0.09, 6), fur, 0.08, 0.5, 0.31, g);
  mesh(new THREE.ConeGeometry(0.05, 0.12, 6), fur, 0, 0.33, 0.48, g).rotation.x = Math.PI / 2;
  for (let k = 0; k < 5; k++) mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.09, 8), k % 2 ? dark : fur, 0, 0.3 + k * 0.04, -0.35 - k * 0.08, g).rotation.x = 1.0;
  const eyeM = new THREE.MeshBasicMaterial({ color: 0xfff09a });
  for (const s of [-1, 1]) mesh(new THREE.SphereGeometry(0.022, 6, 4), eyeM, s * 0.055, 0.39, 0.45, g).castShadow = false;
  const cup = new THREE.Group(); g.add(cup);
  const can = makeCan(); can.position.set(0, 0.2, 0.55); can.visible = false; g.add(can);
  g.visible = false; return { g, can, eyeM };
}
function makeCup() { const g = new THREE.Group(); mesh(new THREE.CylinderGeometry(0.07, 0.06, 0.13, 12, 1, true), M.tin, 0, 0.065, 0, g); mesh(new THREE.TorusGeometry(0.04, 0.012, 5, 10), M.tin, 0.08, 0.07, 0, g); g.visible = false; scene.add(g); return g; }

const cowboy = makeCowboy(), horseM = makeHorse(), racM = makeRaccoon(), cupMesh = makeCup(), hatMesh = makeHatMesh(), groundCanMesh = makeCan();
hatMesh.visible = false; groundCanMesh.visible = false; scene.add(groundCanMesh);

// flood water in the wash
const washWater = (() => {
  const L = 100, g = new THREE.PlaneGeometry(9, L, 1, 80); g.rotateX(-Math.PI / 2);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) { const z = p.getZ(i) - 22; p.setX(i, p.getX(i) + washX(z)); p.setZ(i, z); }
  const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color: 0x7a5a40, roughness: 0.15, metalness: 0.1, transparent: true, opacity: 0.85 }));
  m.receiveShadow = true; scene.add(m); return m;
})();

// ---------- game state ----------
let G = null;
let mode = 'loading';
const keys = {}, pressed = {};
const cam = { yaw: Math.PI, pitch: 0.28, dist: 6.5, curDist: 6.5 };

function newGame() {
  const sp = { x: CAMP.x + 1.5, z: CAMP.z + 3.5 };
  G = {
    t: 0, storm: 0, night: 0, wind: 0.3, flash: 0, gust: 0,
    p: { x: sp.x, z: sp.z, vx: 0, vz: 0, face: Math.PI, walk: 0, moving: false, running: false, crouch: false,
      wood: 0, wetWood: 0, can: { heat: 0, half: false }, cup: true, hat: true, blanket: false, canvas: false, matches: 2, peaches: 0, pears: 0, letters: true,
      warmth: 100, belly: 70, wet: 0, say: null, sayT: 0, gassy: 0, tootT: 0, petCD: 0, stepT: 0, sheltered: false },
    fire: { fuel: 45, lit: true, can: null, flare: 0, ember: 0, tarp: false },
    horse: { x: HORSE_HOME.x, z: HORSE_HOME.z, face: 0, state: 'idle', t: 0, awayT: 0, gassy: 0, tootT: 0, rear: 0, walk: 0 },
    rac: { x: 0, z: 0, face: 0, state: 'hidden', t: 0, cd: 0, spot: null, loot: null },
    cupObj: null, hatObj: null, groundCan: null,
    toasts: [], later: [],
    timers: { lightning: 150, gust: 215, flood: 240, music: 0, crackle: 0 },
    flood: { state: 'none', t: 0, level: 0 }, gustS: { state: 'none', t: 0 },
    stats: { logs: 0, matches: 0, swept: 0, hats: 0, cups: 0, pets: 0, toots: 0, beans: { k: 'beans_never' } },
    tut: { moved: false, gathered: false, fed: false }, beats: {}, musicStep: 0,
  };
  for (const w of woodSources) { w.n = w.logs.length; w.logs.forEach(l => l.visible = true); }
  for (const c of cacti) { c.n = c.fruits.length; c.fruits.forEach(f => f.visible = true); }
  wagon.searched = false; wagon.boards = 4; wagon.boardMeshes.forEach(b => b.visible = true); wagon.cover.visible = true;
  tarp.visible = false; cowboy.blanket.visible = false; cowboy.hat.visible = true;
  cam.yaw = Math.PI * 0.95; cam.pitch = 0.3;
  toast('t_intro', null, '#ffd9a0', 7);
}

// ---------- messaging ----------
function toast(k, p, color = '#f3e2c2', dur = 5.5) {
  G.toasts.push({ m: I18N.msg(k, p), color, t: 0, dur });
  if (G.toasts.length > 4) G.toasts.shift();
}
function say(k, p, dur = 3) { G.p.say = I18N.msg(k, p); G.p.sayT = dur; }
function later(dt, fn) { G.later.push({ at: G.t + dt, fn }); }
function beat(n) { if (G.beats[n]) return false; G.beats[n] = true; return true; }
const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
const pr = () => G.p;

// ---------- beans ----------
function canState(c) { return c.heat < 40 ? 'can_cold' : c.heat < 100 ? 'can_warm' : c.heat < 190 ? 'can_hot' : 'can_burnt'; }
function eatCan(c) {
  const st = canState(c), p = G.p;
  let food = { can_cold: 30, can_warm: 45, can_hot: 70, can_burnt: 40 }[st], warm = { can_cold: 0, can_warm: 8, can_hot: 25, can_burnt: 10 }[st];
  if (c.half) { food *= 0.5; warm *= 0.5; }
  p.belly = clamp(p.belly + food, 0, 100); p.warmth = clamp(p.warmth + warm, 0, 100);
  p.gassy = 150; p.tootT = rand(10, 16); Sound.eat();
  say({ can_cold: 's_cold', can_warm: 's_warm', can_hot: 's_hot', can_burnt: 's_burnt' }[st], null, 3.5);
  G.stats.beans = { k: c.half ? 'beans_half' : 'beans_you', p: { state: { k: st } } };
  toast('t_ate', { state: { k: st }, n: Math.round(food) }, '#ffd27a');
}

// ---------- interactions ----------
function getActions() {
  const p = G.p, f = G.fire, acts = [];
  const add = (key, k, params, x, z, fn, prio = 0) => acts.push({ key, m: { k, p: params }, fn, d: x === null ? prio : Math.hypot(p.x - x, p.z - z) });
  const df = dist(p, CAMP);
  const hasFuel = p.wood + p.wetWood > 0;
  if (df < 2.8) {
    if (!f.lit) {
      if (p.matches > 0 && (hasFuel || f.fuel > 5)) add('E', 'p_strike', { n: p.matches }, CAMP.x, CAMP.z, relight);
      else if (p.matches > 0) add('E', 'p_need_wood', null, CAMP.x, CAMP.z, null);
      else add('E', 'p_no_matches', null, CAMP.x, CAMP.z, null);
    } else if (hasFuel && f.fuel < 96) add('E', p.wood > 0 ? 'p_feed_log' : 'p_feed_wet', null, CAMP.x, CAMP.z, feedFire);
    else if (p.canvas && !f.tarp) add('E', 'p_rig_canvas', null, CAMP.x, CAMP.z, rigCanvas);
    else if (!hasFuel && p.letters && f.fuel < 30) add('E', 'p_letters', null, CAMP.x, CAMP.z, burnLetters);
    if (p.canvas && !f.tarp && hasFuel) add('E', 'p_rig_canvas', null, CAMP.x, CAMP.z + 0.5, rigCanvas);
    if (p.can && !f.can) add('F', 'p_heat_beans', null, CAMP.x, CAMP.z, placeBeans);
    if (f.can) add('F', 'p_eat_fire_beans', { state: { k: canState(f.can) } }, CAMP.x, CAMP.z, () => { const c = f.can; f.can = null; eatCan(c); });
  }
  for (const w of woodSources) {
    if (w.n > 0 && Math.hypot(p.x - w.x, p.z - w.z) < (w.kind === 'tree' ? 2.2 : 1.9)) {
      const k = { tree: 'p_branch', dry: 'p_gather_dry', drift: 'p_driftwood', pile: 'p_gather' }[w.kind];
      if (p.wood + p.wetWood < MAX_WOOD) add('E', k, { n: w.n }, w.x, w.z, () => gatherWood(w));
      else add('E', 'p_arms_full', { max: MAX_WOOD }, w.x, w.z, null);
    }
  }
  for (const c of cacti) if (c.n > 0 && Math.hypot(p.x - c.x, p.z - c.z) < 1.9) add('E', 'p_pear', null, c.x, c.z, () => {
    c.n--; c.fruits[c.n].visible = false; p.pears++; p.warmth = Math.max(1, p.warmth - 2); Sound.ouch(); say('s_ow');
  });
  if (dist(p, WAGON) < 3.4) {
    if (!wagon.searched) add('E', 'p_search_wagon', null, WAGON.x, WAGON.z, searchWagon);
    else if (wagon.boards > 0 && p.wood + p.wetWood < MAX_WOOD) add('E', 'p_boards', { n: wagon.boards }, WAGON.x, WAGON.z, () => {
      wagon.boards--; wagon.boardMeshes[wagon.boards].visible = false; p.wood++; Sound.wood(); puff(WAGON.x, groundH(WAGON.x, WAGON.z) + 1, WAGON.z, 6);
    });
  }
  const h = G.horse;
  if (dist(p, h) < 2.6 && p.petCD <= 0) add('E', 'p_pet', null, h.x, h.z, () => { p.petCD = 6; G.stats.pets++; p.warmth = clamp(p.warmth + 4, 0, 100); Sound.snort(); say('s_pet'); });
  if (G.cupObj && G.cupObj.landed && dist(p, G.cupObj) < 1.8 && G.rac.state !== 'play') add('E', 'p_cup', null, G.cupObj.x, G.cupObj.z, () => { G.cupObj = null; p.cup = true; Sound.clink(); });
  if (G.hatObj && G.hatObj.landed && dist(p, G.hatObj) < 1.8) add('E', 'p_hat', null, G.hatObj.x, G.hatObj.z, () => { G.hatObj = null; p.hat = true; Sound.hat(); say('s_hat_back'); });
  if (G.groundCan && dist(p, G.groundCan) < 1.8) add('E', 'p_pick_beans', null, G.groundCan.x, G.groundCan.z, () => { p.can = G.groundCan.can; G.groundCan = null; Sound.pickup(); });
  if (p.cup) add('Q', 'p_throw_cup', null, null, null, throwCup, 99);
  if (!f.can || df >= 2.8) {
    if (p.can && p.belly < 60) add('F', 'p_eat_pack_beans', { state: { k: canState(p.can) } }, null, null, () => { const c = p.can; p.can = null; eatCan(c); }, 98);
    else if (p.peaches > 0) add('F', 'p_eat_peaches', null, null, null, () => { p.peaches--; p.belly = clamp(p.belly + 35, 0, 100); Sound.eat(); say('s_peaches'); }, 98);
    else if (p.pears > 0) add('F', 'p_eat_pear', null, null, null, () => { p.pears--; p.belly = clamp(p.belly + 14, 0, 100); Sound.eat(); say('s_pear'); }, 98);
  }
  return acts;
}
function gatherWood(w) {
  const p = G.p; w.n--; w.logs[w.n].visible = false;
  const wet = (w.kind === 'drift' && G.storm > 0.2) || (w.kind !== 'dry' && G.storm > 0.5);
  if (wet) { p.wetWood++; if (beat('wetwood')) toast('t_wet_wood', null, '#9ad0ff', 7); } else p.wood++;
  G.tut.gathered = true; Sound.wood(); puff(w.x, groundH(w.x, w.z) + 0.3, w.z, 5, 0.6);
  if (p.wood + p.wetWood === MAX_WOOD) say('s_arms_full');
}
function feedFire() {
  const p = G.p, f = G.fire;
  if (p.wood > 0) { p.wood--; f.fuel = Math.min(100, f.fuel + 25); Sound.feed(); sparks(22); }
  else { p.wetWood--; f.fuel = Math.min(100, f.fuel + 12); Sound.hiss(); for (let i = 0; i < 12; i++) emit(smoke, CAMP.x, camp.position.y + 0.6, CAMP.z, rand(-0.4, 0.4), rand(1, 2), rand(-0.4, 0.4), rand(2, 4)); say('s_wet_wood'); }
  G.stats.logs++; G.tut.fed = true; f.flare = 1;
}
function rigCanvas() { G.p.canvas = false; G.fire.tarp = true; tarp.visible = true; Sound.hat(); toast('t_canvas_rigged', null, '#ffd27a'); }
function burnLetters() { const p = G.p, f = G.fire; p.letters = false; f.fuel = Math.min(100, f.fuel + 18); f.flare = 1; Sound.feed(); sparks(30); say('s_letters', null, 4); }
function relight() {
  const p = G.p, f = G.fire; p.matches--; G.stats.matches++; Sound.match();
  const fail = (p.crouch || f.tarp) ? 0 : G.storm * 0.65;
  if (Math.random() < fail) { Sound.fizzle(); puff(CAMP.x, camp.position.y + 0.5, CAMP.z, 6, 0.5); toast('t_match_fizzle', { n: p.matches }, '#ff9a6a'); return; }
  if (f.fuel < 5) { if (p.wood > 0) { p.wood--; f.fuel = 25; } else { p.wetWood--; f.fuel = 12; } G.stats.logs++; }
  f.lit = true; f.flare = 1; sparks(20); Sound.feed(); say('s_relight');
}
function placeBeans() { const p = G.p; G.fire.can = p.can; p.can = null; Sound.clink(); say('s_supper'); if (beat('beansHint')) toast('t_beans_on', null, '#ffd27a', 6); }
function searchWagon() {
  const p = G.p; wagon.searched = true; wagon.cover.visible = false; wagon.glint.intensity = 0;
  p.canvas = true; p.matches += 3; p.peaches += 1; p.blanket = true; cowboy.blanket.visible = true; Sound.pickup();
  toast('t_wagon_loot', null, '#ffd27a', 7); say('s_wagon');
}
const _fwd = new THREE.Vector3();
function throwCup() {
  const p = G.p; p.cup = false; G.stats.cups++;
  camera.getWorldDirection(_fwd); _fwd.y = 0; _fwd.normalize();
  G.cupObj = { x: p.x + _fwd.x * 0.5, y: groundH(p.x, p.z) + 1.6, z: p.z + _fwd.z * 0.5, vx: _fwd.x * 11, vy: 5, vz: _fwd.z * 11, landed: false, rot: 0 };
  Sound.hat(); say('s_throw', null, 2);
}

// ---------- update ----------
function update(dt) {
  G.t += dt;
  const t = G.t, p = G.p, f = G.fire;
  G.storm = smooth(115, 200, t) * (1 - smooth(470, 525, t));
  G.night = smooth(70, 230, t) * (1 - smooth(485, 540, t));
  G.wind = 0.2 + G.storm * 0.9 + G.gust * 1.6 + Math.sin(t * 0.7) * 0.15 * (0.4 + G.storm);
  G.flash = Math.max(0, G.flash - dt * 3.2); G.gust = Math.max(0, G.gust - dt * 0.6);
  for (let i = G.later.length - 1; i >= 0; i--) if (G.t >= G.later[i].at) { const l = G.later[i]; G.later.splice(i, 1); l.fn(); }

  // story & tutorial beats
  if (t > 3 && beat('tut1')) toast('t_move', null, '#ffd27a', 7);
  if (G.tut.moved && t > 10 && beat('tut2')) toast('t_gather', null, '#ffd27a', 6);
  if (G.tut.gathered && beat('tut3')) toast('t_carry', null, '#ffd27a', 6);
  if (G.tut.fed && beat('tut4')) toast('t_beans', null, '#ffd27a', 7);
  if (t > 55 && beat('tut5')) toast('t_wagon', null, '#ffd27a', 8);
  if ((t > 40 && beat('howl1')) || (t > 492 && beat('howl2'))) Sound.howl();
  if (t > 110 && beat('storm')) { toast('t_storm', null, '#ffb070', 6); later(1, () => Sound.thunder(0.35)); }
  if (t > 172 && beat('rain')) toast('t_rain', null, '#9ad0ff', 8);
  if (t > 235 && beat('dark')) toast('t_dark', null, '#ffd9a0', 6);
  if (t > 470 && beat('dawn')) toast('t_dawn', null, '#ffd890', 6);

  if (window.__beansBot) window.__beansBot(dt);
  movePlayer(dt);

  // fire
  if (f.lit) {
    f.fuel -= (0.45 + G.storm * 0.55 * (f.tarp ? 0.35 : 1) + G.gust * 2.0) * dt;
    if (f.fuel <= 0) { f.fuel = 0; f.lit = false; f.ember = 1; toast('t_fire_out', { n: p.matches }, '#ff7a5a', 6); Sound.fizzle(); for (let i = 0; i < 15; i++) emit(smoke, CAMP.x, camp.position.y + 0.4, CAMP.z, rand(-0.3, 0.3), rand(1, 2), rand(-0.3, 0.3), rand(2, 4)); }
    else if (f.fuel < 20 && beat('lowfire' + Math.floor(t / 40))) toast('t_fire_low', null, '#ffb070');
  }
  f.ember = Math.max(0, f.ember - dt * 0.05); f.flare = Math.max(0, f.flare - dt * 1.5);
  if (f.can) {
    if (f.lit) f.can.heat += (1.5 + f.fuel / 25) * dt;
    if (f.can.heat > 190 && beat('burnt')) toast('t_beans_burning', null, '#ff9a6a');
    else if (f.can.heat > 100 && beat('hot')) { toast('t_beans_hot', null, '#ffd27a'); Sound.pluck(440, 0.15); }
  }
  if (p.can) p.can.heat = Math.max(0, p.can.heat - dt * 0.6);

  // shelter, wetness, warmth, belly
  const d = dist(p, CAMP);
  const info = terrainInfo(p.x, p.z);
  const underTarp = f.tarp && d < 2.6;
  const underRock = Math.hypot(p.x - (OVERHANG.x - 1.8), p.z - OVERHANG.z) < 4.6;
  p.sheltered = underTarp || underRock;
  if (underRock && G.storm > 0.3 && beat('shelter')) say('s_shelter');
  const heat = f.lit ? clamp(f.fuel / 45, 0.25, 1.25) : f.ember * 0.2;
  const near = clamp(1 - d / 8, 0, 1);
  let wetGain = p.sheltered ? 0 : G.storm * 1.1;
  const wading = info.wash > 0.5 && G.flood.level > 0.12;
  if (wading) wetGain += 6;
  p.wet = clamp(p.wet + (wetGain - near * heat * 4.5 - (p.sheltered ? 0.4 : 0)) * dt, 0, 100);
  if (p.wet > 70 && beat('soaked')) toast('t_soaked', null, '#9ad0ff', 6);
  let gain = near * heat * 6.5 + f.flare * near * 3;
  if (dist(p, G.horse) < 2.5 && G.night > 0.3) gain += 0.7;
  let cold = (0.15 + G.night * 0.95 + G.storm * 0.5) * (1 + p.wet / 70);
  if (!p.hat) cold *= 1.35;
  if (p.blanket) cold *= 0.7;
  if (p.belly <= 0) cold *= 1.6;
  if (p.crouch) cold *= 0.9;
  if (p.sheltered) cold *= 0.8;
  p.warmth = clamp(p.warmth + (gain - cold) * dt, 0, 100);
  p.belly = clamp(p.belly - (p.running && p.moving ? 0.32 : 0.16) * dt, 0, 100);
  if (p.belly <= 0 && beat('starve' + Math.floor(t / 60))) toast('t_starving', null, '#ff9a6a', 6);
  if (p.warmth < 25 && beat('cold' + Math.floor(t / 30))) toast('t_freezing', null, '#9ad0ff');
  if (p.gassy > 0) { p.gassy -= dt; p.tootT -= dt; if (p.tootT <= 0) { p.tootT = rand(12, 20); playerToot(); } }
  if (p.sayT > 0) p.sayT -= dt;
  p.petCD -= dt;

  updHorse(dt); updRac(dt); updEvents(dt); updObjects(dt);

  // audio
  G.timers.music -= dt;
  if (G.timers.music <= 0) { G.timers.music = 0.36; playMusicStep(clamp(1 - d / 22, 0, 1) * (f.lit ? 1 : 0.3)); }
  G.timers.crackle -= dt;
  if (G.timers.crackle <= 0) { G.timers.crackle = rand(0.04, 0.25); if (f.lit) Sound.crackle(0.03 + 0.12 * clamp(1 - d / 25, 0, 1) * f.fuel / 60); }
  Sound.setAmbience(0.25 + G.wind * 0.6, 300 + G.wind * 500 + Math.sin(t * 1.3) * 120, G.storm * (p.sheltered ? 0.6 : 1), f.lit ? clamp(1 - d / 30, 0, 1) * (0.3 + f.fuel / 100) : 0);

  if (p.warmth <= 0) return endGame(false);
  if (G.t >= NIGHT_LEN) return endGame(true);
}

const CHORDS = [[110, 164.8, 220, 261.6, 329.6], [98, 146.8, 196, 246.9, 293.7], [87.3, 130.8, 174.6, 220, 261.6], [82.4, 123.5, 164.8, 207.7, 246.9]];
const PATTERN = [0, 2, 3, 4, 3, 2, 1, 3];
function playMusicStep(vol) {
  const s = G.musicStep++; if (vol < 0.03) return;
  if (s % 8 === 7 && Math.random() < 0.5) return;
  Sound.pluck(CHORDS[Math.floor(s / 8) % 4][PATTERN[s % 8]], 0.07 * vol);
}

function movePlayer(dt) {
  const p = G.p;
  let ix = 0, iz = 0;
  if (keys.KeyW || keys.ArrowUp) iz += 1; if (keys.KeyS || keys.ArrowDown) iz -= 1;
  if (keys.KeyD) ix += 1; if (keys.KeyA) ix -= 1;
  if (keys.ArrowLeft) cam.yaw += 2.2 * dt / SPEED; if (keys.ArrowRight) cam.yaw -= 2.2 * dt / SPEED;
  p.crouch = !!(keys.KeyC || keys.ControlLeft);
  p.running = !!(keys.ShiftLeft || keys.ShiftRight) && !p.crouch;
  const len = Math.hypot(ix, iz);
  // camera-relative: forward is where the camera looks
  const fx = -Math.sin(cam.yaw), fz = -Math.cos(cam.yaw), rx = -fz, rz = fx;
  let tx = 0, tz = 0;
  if (len > 0) { tx = (fx * iz + rx * ix) / len; tz = (fz * iz + rz * ix) / len; }
  let spd = p.crouch ? 1.6 : p.running ? 7.2 : 4.4;
  const info = terrainInfo(p.x, p.z);
  if (info.wash > 0.5 && G.flood.level > 0.12) spd *= 0.65;
  if (p.warmth < 20) spd *= 0.8;
  if (p.wood + p.wetWood >= MAX_WOOD) spd *= 0.9;
  const k = clamp(dt * 14, 0, 1);
  p.vx = lerp(p.vx, tx * spd, k); p.vz = lerp(p.vz, tz * spd, k);
  const sp = Math.hypot(p.vx, p.vz);
  p.moving = sp > 0.3;
  if (p.moving) {
    if (len > 0) G.tut.moved = true;
    let nx = p.x + p.vx * dt, nz = p.z + p.vz * dt;
    if (!walkable(nx, nz)) { if (walkable(nx, p.z)) nz = p.z; else if (walkable(p.x, nz)) nx = p.x; else { nx = p.x; nz = p.z; } }
    for (const c of colliders) {
      const dx = nx - c.x, dz = nz - c.z, dd = Math.hypot(dx, dz), m = c.r + 0.35;
      if (dd < m && dd > 1e-4) { nx = c.x + dx / dd * m; nz = c.z + dz / dd * m; }
    }
    for (const o of [G.horse]) { const dx = nx - o.x, dz = nz - o.z, dd = Math.hypot(dx, dz); if (dd < 1.1 && dd > 1e-4) { nx = o.x + dx / dd * 1.1; nz = o.z + dz / dd * 1.1; } }
    { const dx = nx - CAMP.x, dz = nz - CAMP.z, dd = Math.hypot(dx, dz); if (dd < 1.0 && dd > 1e-4) { nx = CAMP.x + dx / dd; nz = CAMP.z + dz / dd; } }
    if (walkable(nx, nz)) { p.x = nx; p.z = nz; }
    p.walk += dt * sp * 2.2;
    const want = Math.atan2(p.vx, p.vz);
    let da = want - p.face; while (da > Math.PI) da -= Math.PI * 2; while (da < -Math.PI) da += Math.PI * 2;
    p.face += da * clamp(dt * 12, 0, 1);
    p.stepT -= dt * sp; if (p.stepT <= 0) { p.stepT = 1.5; Sound.step(G.storm > 0.4 || info.wash > 0.5); }
  }
}

function playerToot() {
  const p = G.p; G.stats.toots++; Sound.toot(false); puff(p.x, groundH(p.x, p.z) + 0.8, p.z, 8, 0.6);
  const r = G.rac;
  if (['lurk', 'sneak', 'grab', 'play', 'lured'].includes(r.state) && dist(r, p) < 12) scareRac('t_raccoon_gag');
  if (dist(G.horse, p) < 4) { say('s_pardon_horse'); later(0.8, () => Sound.snort()); }
  else if (dist(p, CAMP) < 3 && G.fire.lit) { G.fire.fuel = Math.min(100, G.fire.fuel + 5); G.fire.flare = 1; sparks(12); say('s_eyebrows'); }
  else say('s_toot');
}

function updHorse(dt) {
  const h = G.horse, f = G.fire, p = G.p; h.t += dt;
  const away = dist(p, CAMP) > 14;
  if (h.rear > 0) h.rear -= dt;
  if (h.gassy > 0) {
    h.gassy -= dt; h.tootT -= dt;
    if (h.tootT <= 0) {
      h.tootT = rand(9, 14); Sound.toot(true); puff(h.x - Math.sin(h.face) * 1.2, groundH(h.x, h.z) + 1.3, h.z - Math.cos(h.face) * 1.2, 12, 0.8);
      if (dist(h, CAMP) < 10 && f.lit) { f.fuel = Math.min(100, f.fuel + 10); f.flare = 1; sparks(25); toast(beat('horsefan') ? 't_horse_fan' : 't_horse_fan2', null, '#c8e08a'); }
      if (['lurk', 'sneak', 'grab', 'play'].includes(G.rac.state) && dist(G.rac, h) < 16) scareRac('t_horse_scare');
    }
  }
  const moveTo = (tx, tz, s) => { const dx = tx - h.x, dz = tz - h.z, dd = Math.hypot(dx, dz); if (dd < 0.15) return true; h.face = Math.atan2(dx, dz); const st = Math.min(dd, s * dt); h.x += dx / dd * st; h.z += dz / dd * st; h.walk += dt * 6; return false; };
  const eatSpot = { x: CAMP.x - 1.9, z: CAMP.z + 0.6 };
  switch (h.state) {
    case 'idle':
      if (dist(h, HORSE_HOME) > 0.2) moveTo(HORSE_HOME.x, HORSE_HOME.z, 1.4); else h.face = lerp(h.face, 1.9, dt);
      if (f.can && away) { h.awayT += dt; if (h.awayT > 3) { h.state = 'eyeing'; h.t = 0; Sound.snort(); toast('t_horse_eye', null, '#ffb070'); } } else h.awayT = 0;
      break;
    case 'eyeing':
      h.face = Math.atan2(CAMP.x - h.x, CAMP.z - h.z);
      if (!f.can) h.state = 'idle';
      else if (!away) { h.state = 'idle'; h.awayT = 0; say('s_dont'); }
      else if (h.t > 4) { h.state = 'walk'; h.t = 0; }
      break;
    case 'walk':
      if (!f.can) { h.state = 'back'; break; }
      if (!away) { h.state = 'back'; toast('t_horse_stretch', null, '#c8e08a'); break; }
      if (moveTo(eatSpot.x, eatSpot.z, 1.6)) { h.state = 'eat'; h.t = 0; Sound.snort(); }
      break;
    case 'eat':
      h.face = Math.atan2(CAMP.x - h.x, CAMP.z - h.z);
      if (!f.can || !away) { h.state = 'back'; if (f.can) toast('t_horse_freeze', null, '#c8e08a'); break; }
      if (h.t > 3) { f.can = null; G.stats.beans = { k: 'beans_horse' }; h.gassy = 120; h.tootT = 5; h.state = 'back'; toast('t_horse_ate', null, '#ff9a6a', 6); Sound.neigh(); }
      break;
    case 'back': if (moveTo(HORSE_HOME.x, HORSE_HOME.z, 1.8)) { h.state = 'idle'; h.awayT = 0; } break;
  }
}

function scareRac(k) {
  const r = G.rac;
  if (r.state === 'play' && G.cupObj) { G.cupObj.x = r.x; G.cupObj.z = r.z; }
  r.state = 'flee'; r.t = 0; Sound.chitter();
  if (k) toast(k, null, '#c8e08a');
}
function updRac(dt) {
  const r = G.rac, p = G.p, f = G.fire; r.t += dt; r.cd -= dt;
  const dP = dist(p, r);
  const run = (tx, tz, s) => { const dx = tx - r.x, dz = tz - r.z, dd = Math.hypot(dx, dz); if (dd < 0.15) return true; r.face = Math.atan2(dx, dz); const st = Math.min(dd, s * dt); r.x += dx / dd * st; r.z += dz / dd * st; return false; };
  if (['lurk', 'sneak', 'grab', 'play', 'lured'].includes(r.state) && dP < 2.8) { scareRac(r.state === 'play' ? 't_raccoon_cupdrop' : 't_raccoon_shoo'); if (beat('shoo')) say('s_shoo'); return; }
  const awayFrom = (dx, dz) => { const L = Math.hypot(dx, dz) || 1; return { x: r.x + dx / L * 40, z: r.z + dz / L * 40 }; };
  switch (r.state) {
    case 'hidden':
      if (f.can && f.can.heat > 12 && r.cd <= 0) {
        // the bush farthest from the player
        const spot = sageSpots.slice().sort((a, b) => dist(b, p) - dist(a, p))[0];
        r.spot = spot; r.x = spot.x; r.z = spot.z; r.state = 'lurk'; r.t = 0; r.face = Math.atan2(CAMP.x - r.x, CAMP.z - r.z);
        Sound.rustle(); toast('t_raccoon', null, '#c8e08a');
        if (beat('cuptip')) later(2.5, () => toast('t_raccoon_tip', null, '#ffd27a', 7));
      }
      break;
    case 'lurk': if (!f.can) { r.state = 'leave'; break; } if (r.t > 4) { r.state = 'sneak'; r.t = 0; } break;
    case 'sneak': if (!f.can) { r.state = 'leave'; break; } if (run(CAMP.x + 0.9, CAMP.z + 0.3, 1.5)) { r.state = 'grab'; r.t = 0; Sound.chitter(); } break;
    case 'grab':
      if (!f.can) { r.state = 'leave'; break; }
      if (r.t > 2.5) { r.loot = f.can; f.can = null; r.state = 'carry'; r.t = 0; Sound.chitter(); toast('t_raccoon_grab', null, '#ff9a6a'); r.dest = awayFrom(r.x - p.x, r.z - p.z); }
      break;
    case 'carry': {
      if (dP < 1.6) { r.loot.half = true; p.can = r.loot; r.loot = null; r.state = 'flee'; r.t = 0; Sound.chitter(); toast('t_raccoon_catch', null, '#ffd27a', 6); break; }
      if (!walkable(r.x + Math.sin(r.face) * 1.5, r.z + Math.cos(r.face) * 1.5)) r.dest = awayFrom(CAMP.x - r.x + rand(-5, 5), CAMP.z - r.z + rand(-5, 5));
      if (run(r.dest.x, r.dest.z, 4.6) || dist(r, CAMP) > 45) { G.stats.beans = { k: 'beans_raccoon' }; r.loot = null; r.state = 'gone'; toast('t_raccoon_gone', null, '#ff9a6a', 7); }
      break;
    }
    case 'flee': {
      const dx = r.x - p.x, dz = r.z - p.z, L = Math.hypot(dx, dz) || 1;
      run(r.x + dx / L * 5, r.z + dz / L * 5, 6.5);
      if (r.t > 3.5 || !walkable(r.x, r.z)) { r.state = 'hidden'; r.cd = 12; }
      break;
    }
    case 'lured':
      if (!G.cupObj) { r.state = 'leave'; break; }
      if (!G.cupObj.landed) break;
      if (run(G.cupObj.x, G.cupObj.z, 3.6)) { r.state = 'play'; r.t = 0; if (beat('cupplay')) toast('t_raccoon_cup', null, '#c8e08a'); else Sound.chitter(); }
      break;
    case 'play':
      if (G.cupObj) { G.cupObj.x = r.x + Math.sin(r.face) * 0.4; G.cupObj.z = r.z + Math.cos(r.face) * 0.4; }
      r.face += dt * 1.5;
      if (r.t > 14) { r.t = 0; r.state = f.can ? 'sneak' : 'leave'; }
      break;
    case 'leave': { const spot = r.spot || sageSpots[0]; if (run(spot.x, spot.z, 3) || r.t > 10) { r.state = 'hidden'; r.cd = 10; } break; }
    case 'gone': break;
  }
}

function updEvents(dt) {
  const p = G.p, f = G.fire, T = G.timers;
  if (G.storm > 0.35 && G.t > T.lightning) {
    T.lightning = G.t + rand(5, 14) / Math.max(G.storm, 0.4);
    G.flash = 1; makeBolt();
    later(rand(0.3, 1.6), () => Sound.thunder(rand(0.6, 1)));
    if (G.horse.state === 'idle' && Math.random() < 0.5) { G.horse.rear = 1.2; Sound.neigh(); }
  }
  const gs = G.gustS; gs.t += dt;
  if (gs.state === 'none' && G.storm > 0.45 && G.t > T.gust) { gs.state = 'warn'; gs.t = 0; Sound.whoosh(); toast('t_gust', null, '#9ad0ff', 4); }
  else if (gs.state === 'warn' && gs.t > 2.6) {
    gs.state = 'blow'; gs.t = 0; G.gust = 1;
    if (p.hat && !p.crouch && !p.sheltered) {
      p.hat = false; G.stats.hats++; Sound.hat();
      G.hatObj = { x: p.x, y: groundH(p.x, p.z) + 2, z: p.z, vx: rand(5, 7), vy: 4, vz: rand(-2, 2), landed: false, rot: 0 };
      toast('t_hat_gone', null, '#9ad0ff', 6); say('s_myhat', null, 2);
    } else if (p.hat) say('s_kepthat');
    if (f.lit) sparks(30);
  } else if (gs.state === 'blow' && gs.t > 1.8) { gs.state = 'none'; T.gust = G.t + rand(35, 55); }
  const fl = G.flood; fl.t += dt;
  const puddle = G.storm * 0.25;
  if (fl.state === 'none') { fl.level = lerp(fl.level, puddle, dt); if (G.storm > 0.55 && G.t > T.flood) { fl.state = 'warn'; fl.t = 0; Sound.rumble(); toast('t_flood_warn', null, '#ff7a5a', 5); } }
  else if (fl.state === 'warn') { fl.level = lerp(fl.level, puddle, dt); if (fl.t > 4.5) { fl.state = 'flood'; fl.t = 0; Sound.splash(); } }
  else if (fl.state === 'flood') {
    fl.level = fl.t < 1.2 ? lerp(puddle, 1, fl.t / 1.2) : fl.t < 7 ? 1 : lerp(1, puddle, (fl.t - 7) / 2.5);
    if (fl.t > 9.5) { fl.state = 'none'; T.flood = G.t + rand(45, 70); }
  }
  if (fl.level > 0.55 && terrainInfo(p.x, p.z).wash > 0.3) {
    const lost = p.wood + p.wetWood;
    // shove the player out of the channel toward the nearest bank
    const side = p.x < washX(p.z) ? -1 : 1;
    for (let k = 0; k < 40; k++) { p.x += side * 0.25; if (terrainInfo(p.x, p.z).wash < 0.2) break; }
    if (!walkable(p.x, p.z)) { p.z = clamp(p.z + 8, -60, 30); p.x = washX(p.z) + side * 6; }
    p.wood = 0; p.wetWood = 0; p.wet = 100; p.warmth = Math.max(0, p.warmth - 22); G.stats.swept++; Sound.splash();
    toast('t_flood_hit', null, '#9ad0ff', 6); if (lost) toast('t_flood_lost', { n: lost }, '#9ad0ff', 6);
    say('s_flood', null, 1.5);
  }
}

function makeBolt() {
  const a = rand(0, Math.PI * 2), d = rand(120, 260), x0 = camera.position.x + Math.cos(a) * d, z0 = camera.position.z + Math.sin(a) * d;
  const p = boltGeo.attributes.position; let x = x0, y = 160, z = z0;
  for (let i = 0; i < 30; i++) { p.setXYZ(i, x, y, z); x += rand(-6, 6); z += rand(-6, 6); y -= 140 / 29; }
  p.needsUpdate = true; bolt.visible = true; bolt.userData.t = 0.25;
}

function updObjects(dt) {
  const c = G.cupObj;
  if (c && !c.landed) {
    c.vy -= 18 * dt; c.x += c.vx * dt; c.y += c.vy * dt; c.z += c.vz * dt; c.rot += dt * 14;
    if (!walkable(c.x, c.z)) { c.vx *= -0.3; c.vz *= -0.3; c.x += c.vx * dt * 2; c.z += c.vz * dt * 2; }
    const gy = groundH(c.x, c.z);
    if (c.y <= gy + 0.05) {
      c.y = gy; c.landed = true; Sound.clink();
      const r = G.rac;
      if (['lurk', 'sneak', 'grab', 'carry'].includes(r.state) && dist(r, c) < 35) {
        if (r.state === 'carry') { G.groundCan = { x: r.x, z: r.z, can: r.loot }; r.loot = null; toast('t_raccoon_drop', null, '#c8e08a', 6); }
        r.state = 'lured'; r.t = 0; Sound.chitter();
      }
    }
  }
  const h = G.hatObj;
  if (h && !h.landed) {
    h.vy -= 9 * dt; h.vx *= 1 - dt * 0.5; h.vz *= 1 - dt * 0.5; h.x += h.vx * dt; h.y += h.vy * dt; h.z += h.vz * dt; h.rot += dt * 8;
    if (!walkable(h.x, h.z)) { h.x -= h.vx * dt * 3; h.vx = -h.vx * 0.3; }
    const gy = groundH(h.x, h.z); if (h.y <= gy + 0.03) { h.y = gy + 0.03; h.landed = true; }
  }
  const flooded = o => o && terrainInfo(o.x, o.z).wash > 0.3 && G.flood.level > 0.55;
  if (h && h.landed && flooded(h)) { G.hatObj = null; toast('t_hat_float', null, '#9ad0ff'); }
  if (c && c.landed && flooded(c) && G.rac.state !== 'play') { G.cupObj = null; toast('t_cup_float', null, '#9ad0ff'); }
  if (flooded(G.groundCan)) { G.groundCan = null; G.stats.beans = { k: 'beans_flood' }; toast('t_beans_float', null, '#ff9a6a'); }
  for (const tt of G.toasts) tt.t += dt;
  G.toasts = G.toasts.filter(tt => tt.t < tt.dur);
}

// ---------- end ----------
function clockStr() {
  const mins = Math.floor(clamp(G.t, 0, NIGHT_LEN) / NIGHT_LEN * 11 * 60);
  const hh = (19 + Math.floor(mins / 60)) % 24, mm = mins % 60;
  if (I18N.lang === 'en') { let h12 = hh % 12; if (h12 === 0) h12 = 12; return `${h12}:${String(mm).padStart(2, '0')} ${hh >= 12 ? 'PM' : 'AM'}`; }
  return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
}
let endInfo = null;
function endGame(won) {
  mode = won ? 'won' : 'lost';
  const p = G.p, s = G.stats;
  Sound.sting(won); Sound.setAmbience(0.2, 400, won ? 0 : G.storm, 0);
  let textK;
  if (won) textK = s.beans.k === 'beans_horse' ? 'win_horse' : s.beans.k === 'beans_raccoon' ? 'win_raccoon' : (s.beans.k === 'beans_you' || s.beans.k === 'beans_half') ? 'win_you' : 'win_plain';
  else textK = !p.hat ? 'lose_hat' : !G.fire.lit ? 'lose_fire' : p.belly <= 0 ? 'lose_belly' : p.wet > 60 ? 'lose_wet' : 'lose_plain';
  endInfo = { won, textK, time: clockStr() };
  renderEnd();
  document.getElementById('end').classList.remove('hidden');
  document.getElementById('hud').classList.add('hidden');
  if (document.pointerLockElement) document.exitPointerLock();
}
function renderEnd() {
  if (!endInfo) return;
  const s = G.stats, T = I18N.t;
  document.getElementById('endEyebrow').textContent = endInfo.won ? T('end_win_eyebrow') : T('end_lose_eyebrow', { time: endInfo.time });
  document.getElementById('endTitle').textContent = T(endInfo.won ? 'end_win_title' : 'end_lose_title');
  document.getElementById('endText').textContent = T(endInfo.textK);
  const ul = document.getElementById('endStats'); ul.textContent = '';
  [['st_beans', I18N.tr(s.beans)], ['st_logs', s.logs], ['st_matches', s.matches], ['st_hats', s.hats], ['st_swept', s.swept], ['st_cups', s.cups], ['st_toots', s.toots], ['st_pets', s.pets]].forEach(([k, v]) => {
    const li = document.createElement('li'); li.append(T(k) + ': '); const b = document.createElement('b'); b.textContent = v; li.append(b); ul.append(li);
  });
}

// ---------- visual sync ----------
const skyCols = [new THREE.Color(), new THREE.Color(), new THREE.Color()];
const tmpC = new THREE.Color(), tmpV = new THREE.Vector3();
function syncVisuals(dt, time) {
  const t = G.t, p = G.p, f = G.fire;
  // sky + sun
  skyAt(t, skyCols);
  skyU.uTop.value.copy(skyCols[0]); skyU.uMid.value.copy(skyCols[1]); skyU.uHor.value.copy(skyCols[2]);
  skyU.uStorm.value = G.storm; skyU.uTime.value = time; skyU.uFlash.value = G.flash;
  const dusk = 1 - smooth(60, 200, t), dawn = smooth(490, 545, t);
  let sunDir;
  if (t < 300) { const el = lerp(0.3, -0.1, smooth(0, 170, t)); sunDir = tmpV.set(-0.55 * Math.cos(el), Math.sin(el), -0.83 * Math.cos(el)).normalize(); }
  else { const el = lerp(-0.1, 0.16, smooth(495, 580, t)); sunDir = tmpV.set(Math.cos(el), Math.sin(el), -0.3).normalize(); }
  skyU.uSunDir.value.copy(sunDir);
  skyU.uSunVis.value = clamp((sunDir.y + 0.03) * 12, 0, 1) * (1 - G.storm);
  skyU.uSunCol.value.setRGB(1.0, 0.55 + dawn * 0.2, 0.25 + dawn * 0.2).multiplyScalar(Math.max(dusk, dawn) * 0.9 + 0.05);
  skyU.uCloudDark.value.copy(skyCols[1]).lerp(tmpC.set(0x101018), 0.55 + G.storm * 0.3);
  skyU.uCloudLit.value.set(dusk > dawn ? 0xff9a6a : 0xffc8a0).multiplyScalar(Math.max(dusk, dawn) * 0.9 + 0.08);
  sky.position.copy(camera.position);
  // sun light
  const sunUp = clamp(sunDir.y * 8 + 0.2, 0, 1);
  sun.intensity = 2.8 * sunUp * Math.max(dusk, dawn) * (1 - G.storm * 0.8);
  sun.color.set(0xff9a50).lerp(tmpC.set(0xffd8a8), dawn * 0.5);
  sun.position.set(p.x + sunDir.x * 120, groundH(p.x, p.z) + Math.max(sunDir.y, 0.08) * 120, p.z + sunDir.z * 120);
  sun.target.position.set(p.x, groundH(p.x, p.z), p.z);
  moon.intensity = 0.35 * G.night * (1 - G.storm * 0.4) + G.flash * 3;
  hemi.intensity = 0.25 + 0.95 * Math.max(dusk, dawn) + G.flash * 2.5;
  hemi.color.copy(skyCols[1]).lerp(tmpC.set(0x8090c0), 0.3); hemi.groundColor.set(0x5a3020).lerp(tmpC.set(0x141018), 1 - Math.max(dusk, dawn));
  renderer.toneMappingExposure = 1.15 + G.night * 0.3;
  // fog: haze at dusk, rain wall at night
  scene.fog.color.copy(skyCols[2]).lerp(tmpC.set(0x0c0e16), G.storm * 0.4);
  scene.fog.near = lerp(60, 8, G.storm); scene.fog.far = lerp(520, 130, G.storm);
  terrainMat.roughness = 0.95 - G.storm * 0.45;
  // fire
  const fl = Math.sin(time * 13) * 0.08 + Math.sin(time * 7.3) * 0.12 + Math.random() * 0.08;
  const fuelK = f.lit ? 0.4 + f.fuel / 70 : f.ember * 0.25;
  fireLight.intensity = (f.lit ? 5 + f.fuel * 0.11 + f.flare * 6 : f.ember * 1.5) * (1 + fl);
  fireLight.distance = f.lit ? 26 + f.fuel * 0.15 : 6;
  flameGroup.visible = f.lit;
  flames.forEach((s, i) => {
    const u = s.userData, ph = time * (7 + i) + u.ph, hgt = (0.7 + 0.35 * Math.sin(ph) ** 2) * u.sc * fuelK * (1 + f.flare * 0.5);
    s.scale.set(0.55 * u.sc * (0.8 + fuelK * 0.4), 1.2 * hgt + 0.1, 1);
    s.position.set(u.ox + G.wind * 0.08 * Math.sin(ph * 0.7), 0.25 + s.scale.y * 0.45, u.oz);
  });
  glow.material.opacity = f.lit ? 0.25 + fuelK * 0.12 + f.flare * 0.15 : f.ember * 0.15;
  fireCan.visible = !!f.can;
  if (f.can) fireCan.userData.label.material.color.set(canState(f.can) === 'can_burnt' ? 0x2a1a1a : 0xb8322a);
  if (f.lit && Math.random() < dt * (8 + f.fuel / 8)) emit(embers, CAMP.x + rand(-0.2, 0.2), camp.position.y + 0.5, CAMP.z + rand(-0.2, 0.2), rand(-0.3, 0.3), rand(1.5, 3.5), rand(-0.3, 0.3), rand(0.8, 2));
  if ((f.lit || f.ember > 0.1) && Math.random() < dt * 4) emit(smoke, CAMP.x, camp.position.y + 1.2, CAMP.z, rand(-0.1, 0.1), rand(0.8, 1.4), rand(-0.1, 0.1), rand(2.5, 4.5));
  if (f.can && f.can.heat > 100 && Math.random() < dt * 4) emit(puffs, CAMP.x + 0.3, camp.position.y + 0.7, CAMP.z, 0, 0.6, 0, 1.2);
  for (const sys of [embers, smoke, puffs]) {
    const arr = sys.p.geometry.attributes.position;
    sys.data.forEach((q, i) => {
      if (q.life > 0) { q.life -= dt; q.x += (q.vx + G.wind * (sys === embers ? 1.2 : 0.8)) * dt; q.y += q.vy * dt; q.z += q.vz * dt; if (sys === embers) q.vy -= 0.5 * dt; }
      arr.setXYZ(i, q.x, q.life > 0 ? q.y : -999, q.z);
    });
    arr.needsUpdate = true;
  }
  // rain lit by the campfire
  const rp = rainGeo.attributes.position, rc = rainGeo.attributes.color, nDrops = Math.floor(RAIN_N * G.storm);
  const fy = camp.position.y + 1, slant = 0.06 + G.wind * 0.12, R = f.lit ? 9 + f.fuel * 0.08 : 0;
  const cx = camera.position.x, cz = camera.position.z, by = groundH(p.x, p.z);
  for (let i = 0; i < RAIN_N; i++) {
    const d = drops[i];
    if (i >= nDrops) { rp.setXYZ(i * 2, 0, -999, 0); rp.setXYZ(i * 2 + 1, 0, -999, 0); continue; }
    d.y -= d.v * dt; d.x += G.wind * 4 * dt;
    if (d.y < -2) { d.y = rand(16, 26); d.x = rand(-RAIN_BOX, RAIN_BOX); d.z = rand(-RAIN_BOX, RAIN_BOX); }
    let wx = cx + ((d.x % RAIN_BOX) + RAIN_BOX) % RAIN_BOX * 2 - RAIN_BOX, wz = cz + d.z, wy = by + d.y;
    rp.setXYZ(i * 2, wx, wy, wz); rp.setXYZ(i * 2 + 1, wx - slant * 0.8, wy + 0.55, wz);
    const ld = R > 0 ? clamp(1 - Math.hypot(wx - CAMP.x, wy - fy, wz - CAMP.z) / R, 0, 1) : 0;
    const base = 0.32 + G.flash * 0.6;
    const r = base + ld * 1.2, g = base + 0.03 + ld * 0.65, b = base + 0.12 + ld * 0.2;
    rc.setXYZ(i * 2, r, g, b); rc.setXYZ(i * 2 + 1, r * 0.5, g * 0.5, b * 0.5);
  }
  rp.needsUpdate = true; rc.needsUpdate = true;
  rain.visible = nDrops > 0;
  if (bolt.visible) { bolt.userData.t -= dt; bolt.material.opacity = clamp(bolt.userData.t / 0.25, 0, 1); if (bolt.userData.t <= 0) bolt.visible = false; }
  // water
  washWater.position.y = -1.35 + G.flood.level * 1.5 + Math.sin(time * 2) * 0.02 * G.flood.level;
  washWater.visible = G.flood.level > 0.03;
  washWater.material.color.set(G.flood.level > 0.5 ? 0x7a5a40 : 0x4a5058);
  grassU.uTime.value = time; grassU.uWind.value = G.wind;
  // cowboy
  const cb = cowboy; cb.g.position.set(p.x, groundH(p.x, p.z), p.z); cb.g.rotation.y = p.face;
  const sw = p.moving ? Math.sin(p.walk) * (p.running ? 0.8 : 0.55) : 0;
  cb.legL.rotation.x = sw; cb.legR.rotation.x = -sw; cb.armL.rotation.x = -sw * 0.8; cb.armR.rotation.x = sw * 0.8;
  cb.body.position.y = p.crouch ? -0.45 : (p.moving ? Math.abs(Math.cos(p.walk)) * 0.04 : 0);
  cb.body.rotation.x = p.crouch ? 0.25 : (p.running ? 0.12 : 0);
  if (p.crouch && p.hat) { cb.armR.rotation.x = -2.6; }
  const shiver = p.warmth < 30 ? (Math.random() - 0.5) * (30 - p.warmth) * 0.002 : 0; cb.body.position.x = shiver;
  cb.hat.visible = p.hat; cb.blanket.visible = p.blanket;
  cb.skirt.rotation.z = Math.sin(time * 3) * 0.03 * G.wind;
  // horse
  const h = G.horse; horseM.g.position.set(h.x, groundH(h.x, h.z), h.z);
  horseM.g.rotation.y = h.face;
  const hm = ['walk', 'back'].includes(h.state) || (h.state === 'idle' && dist(h, HORSE_HOME) > 0.2);
  horseM.legs.forEach((l, i) => { l.rotation.x = hm ? Math.sin(h.walk + i * 1.6) * 0.4 : 0; });
  const graze = (h.state === 'idle' && !hm && Math.sin(time * 0.4) > 0.3) || h.state === 'eat';
  horseM.neck.rotation.x = lerp(horseM.neck.rotation.x, graze ? 1.1 : h.state === 'eyeing' ? -0.15 : 0, dt * 3);
  horseM.tail.rotation.z = Math.sin(time * 2.5) * 0.25 + G.wind * 0.3;
  horseM.rig.rotation.x = h.rear > 0 ? -Math.sin(clamp(h.rear, 0, 1.2) / 1.2 * Math.PI) * 0.45 : 0;
  // raccoon
  const r = G.rac; racM.g.visible = !['hidden', 'gone'].includes(r.state) && r.state !== 'lurk';
  racM.g.position.set(r.x, groundH(r.x, r.z) + (racM.g.visible ? Math.abs(Math.sin(time * 14)) * 0.03 : 0), r.z); racM.g.rotation.y = r.face;
  racM.can.visible = r.state === 'carry' && !!r.loot;
  for (const s of sageSpots) { const shake = r.state === 'lurk' && r.spot === s; s.g.rotation.z = shake ? Math.sin(time * 30) * 0.06 : 0; s.g.position.x = s.x + (shake ? Math.sin(time * 25) * 0.04 : 0); }
  // thrown / dropped things
  const c = G.cupObj; cupMesh.visible = !!c || (r.state === 'play');
  if (c) { cupMesh.position.set(c.x, c.landed ? groundH(c.x, c.z) : c.y, c.z); cupMesh.rotation.set(c.landed ? 0 : c.rot, 0, c.landed && r.state !== 'play' ? 1.4 : 0); }
  const ho = G.hatObj; hatMesh.visible = !!ho;
  if (ho) { hatMesh.position.set(ho.x, ho.landed ? groundH(ho.x, ho.z) + 0.03 : ho.y, ho.z); hatMesh.rotation.set(ho.landed ? 0 : Math.sin(ho.rot) * 0.8, ho.rot, 0); }
  groundCanMesh.visible = !!G.groundCan;
  if (G.groundCan) { groundCanMesh.position.set(G.groundCan.x, groundH(G.groundCan.x, G.groundCan.z), G.groundCan.z); groundCanMesh.rotation.z = 1.4; }
  if (!wagon.searched) wagon.glint.intensity = (0.6 + 0.4 * Math.sin(time * 3)) * 2 * G.night;
}

function updateCamera(dt) {
  const p = G.p;
  const tx = p.x, tz = p.z, ty = groundH(p.x, p.z) + (p.crouch ? 1.15 : 1.7);
  const cp = Math.cos(cam.pitch);
  const dx = Math.sin(cam.yaw) * cp, dy = Math.sin(cam.pitch), dz = Math.cos(cam.yaw) * cp;
  // pull in when the canyon wall is between camera and cowboy
  let want = cam.dist;
  for (let i = 1; i <= 14; i++) {
    const s = cam.dist * i / 14, x = tx + dx * s, y = ty + dy * s, z = tz + dz * s;
    if (groundH(x, z) + 0.35 > y) { want = Math.max(1.2, s - 0.6); break; }
  }
  cam.curDist = want < cam.curDist ? want : lerp(cam.curDist, want, clamp(dt * 3, 0, 1));
  camera.position.set(tx + dx * cam.curDist, ty + dy * cam.curDist, tz + dz * cam.curDist);
  const gy = groundH(camera.position.x, camera.position.z) + 0.3; if (camera.position.y < gy) camera.position.y = gy;
  camera.lookAt(tx, ty, tz);
  if (G.flash > 0.5) camera.position.x += (Math.random() - 0.5) * 0.03;
}

// ---------- HUD ----------
const $ = id => document.getElementById(id);
const hud = { toasts: $('toasts'), prompts: $('prompts'), say: $('say'), markers: $('markers'), inv: $('inv'), status: $('status'), clock: $('clock'), phase: $('phase'), frost: $('frost'), look: $('lookhint') };
const bars = { warmth: $('b_warmth'), belly: $('b_belly'), dry: $('b_dry'), fire: $('b_fire') };
const markerEls = {};
const _proj = new THREE.Vector3();
function screenPos(x, y, z) {
  _proj.set(x, y, z).project(camera);
  const behind = _proj.z > 1;
  return { x: (_proj.x * 0.5 + 0.5) * innerWidth, y: (-_proj.y * 0.5 + 0.5) * innerHeight, behind };
}
function setBar(el, v) { el.style.width = clamp(v, 0, 100) + '%'; el.classList.toggle('low', v < 25); }
let hudSlow = 0;
function drawHUD(dt, acts) {
  const p = G.p, f = G.fire, T = I18N.t;
  setBar(bars.warmth, p.warmth); setBar(bars.belly, p.belly); setBar(bars.dry, 100 - p.wet); setBar(bars.fire, f.lit ? f.fuel : 0);
  hud.frost.style.opacity = p.warmth < 40 ? (40 - p.warmth) / 40 : 0;
  hudSlow -= dt;
  if (hudSlow <= 0) {
    hudSlow = 0.15;
    hud.clock.textContent = clockStr();
    hud.phase.textContent = T(G.t < 110 ? 'phase_sundown' : G.t < 200 ? 'phase_storm' : G.t < 470 ? 'phase_night' : 'phase_dawn') + ' · ' + T('sunrise_at');
    const inv = [T('inv_wood', { n: p.wood + p.wetWood, max: MAX_WOOD }) + (p.wetWood ? ' ' + T('inv_wet', { n: p.wetWood }) : ''), T('inv_matches', { n: p.matches })];
    if (p.can) inv.push(T('inv_beans', { state: T(canState(p.can)) }));
    if (p.cup) inv.push(T('inv_cup')); if (!p.hat) inv.push(T('inv_nohat')); if (p.canvas) inv.push(T('inv_canvas')); if (p.blanket) inv.push(T('inv_blanket'));
    if (p.peaches) inv.push(T('inv_peaches', { n: p.peaches })); if (p.pears) inv.push(T('inv_pears', { n: p.pears }));
    hud.inv.textContent = inv.join(' · ');
    const st = []; if (p.sheltered) st.push(T('status_sheltered')); if (p.wet > 70) st.push(T('status_soaked')); if (dist(p, CAMP) < 6 && f.lit) st.push(T('status_by_fire'));
    hud.status.textContent = st.join(' · ');
  }
  // toasts
  const want = G.toasts.length;
  while (hud.toasts.children.length < want) { const d = document.createElement('div'); d.className = 'toast'; hud.toasts.append(d); }
  while (hud.toasts.children.length > want) hud.toasts.lastChild.remove();
  G.toasts.forEach((tt, i) => { const el = hud.toasts.children[i]; el.textContent = I18N.tr(tt.m); el.style.color = tt.color; el.style.opacity = clamp(Math.min(tt.t * 4, (tt.dur - tt.t) * 2), 0, 1); });
  // prompts
  const shown = {}, lines = [];
  acts.slice().sort((a, b) => a.d - b.d).forEach(a => { if (shown[a.key]) return; shown[a.key] = true; if (a.key === 'Q' && G.rac.state === 'hidden') return; lines.push(a); });
  while (hud.prompts.children.length < lines.length) { const d = document.createElement('div'); d.className = 'prompt'; d.append(document.createElement('kbd'), document.createElement('span')); hud.prompts.append(d); }
  while (hud.prompts.children.length > lines.length) hud.prompts.lastChild.remove();
  lines.forEach((a, i) => { const el = hud.prompts.children[i]; el.firstChild.textContent = a.key; el.lastChild.textContent = I18N.tr(a.m); el.classList.toggle('off', !a.fn); });
  // speech bubble
  if (p.say && p.sayT > 0) {
    const s = screenPos(p.x, groundH(p.x, p.z) + 2.5, p.z);
    hud.say.classList.toggle('hidden', s.behind); hud.say.textContent = I18N.tr(p.say); hud.say.style.left = s.x + 'px'; hud.say.style.top = s.y + 'px';
  } else hud.say.classList.add('hidden');
  // world markers
  const mk = [];
  if (dist(p, CAMP) > 12) mk.push(['camp', 'marker_camp', CAMP.x, CAMP.z, 2.5, f.lit ? '#ffb030' : '#aaa']);
  if (!wagon.searched && dist(p, WAGON) > 10 && G.t > 50) mk.push(['wagon', 'marker_wagon', WAGON.x, WAGON.z, 3, '#ffd9a0']);
  if (G.t > 170 && dist(p, OVERHANG) > 10) mk.push(['overhang', 'marker_overhang', OVERHANG.x - 1.8, OVERHANG.z, 4, '#9ad0ff']);
  if (G.hatObj && G.hatObj.landed) mk.push(['hat', 'marker_hat', G.hatObj.x, G.hatObj.z, 0.8, '#9ad0ff']);
  if (G.cupObj && G.cupObj.landed && dist(p, G.cupObj) > 3) mk.push(['cup', 'marker_cup', G.cupObj.x, G.cupObj.z, 0.6, '#c8e08a']);
  if (G.groundCan) mk.push(['beans', 'marker_beans', G.groundCan.x, G.groundCan.z, 0.6, '#ffd27a']);
  const used = new Set(); let offL = 0, offR = 0;
  for (const [id, k, x, z, hgt, color] of mk) {
    used.add(id);
    let el = markerEls[id]; if (!el) { el = markerEls[id] = document.createElement('div'); el.className = 'marker'; hud.markers.append(el); }
    const s = screenPos(x, groundH(x, z) + hgt, z);
    let sx = s.x, sy = s.y; const off = s.behind || sx < 0 || sx > innerWidth || sy < 0 || sy > innerHeight;
    let arrow = '';
    if (off) {
      const fx = -Math.sin(cam.yaw), fz = -Math.cos(cam.yaw), rx = -fz, rz = fx;
      const vx = x - p.x, vz = z - p.z, side = vx * rx + vz * rz;
      sx = side > 0 ? innerWidth - 110 : 110; sy = innerHeight * 0.4 + (side > 0 ? offR++ : offL++) * 26; arrow = side > 0 ? ' ▶' : '◀ ';
    }
    el.style.left = sx + 'px'; el.style.top = sy + 'px'; el.style.color = color; el.style.display = '';
    const label = T(k) + ' · ' + T('meters', { n: Math.round(Math.hypot(x - p.x, z - p.z)) });
    el.textContent = off ? (arrow === '◀ ' ? arrow + label : label + arrow) : '▼ ' + label;
  }
  for (const id in markerEls) if (!used.has(id)) markerEls[id].style.display = 'none';
  hud.look.style.display = (document.pointerLockElement || lookUsed) ? 'none' : '';
}

// ---------- input ----------
let lookUsed = false, dragging = false;
const canvas = renderer.domElement;
function look(dx, dy) { cam.yaw -= dx * 0.0032 * SET.sens; cam.pitch = clamp(cam.pitch + dy * 0.0028 * SET.sens * (SET.invert ? -1 : 1), -0.35, 1.2); if (Math.abs(dx) + Math.abs(dy) > 2) lookUsed = true; }
canvas.addEventListener('click', () => { if (mode === 'play' && !document.pointerLockElement && canvas.requestPointerLock) { try { const r = canvas.requestPointerLock(); if (r && r.catch) r.catch(() => {}); } catch (e) { /* drag fallback */ } } });
canvas.addEventListener('mousedown', () => { dragging = true; });
addEventListener('mouseup', () => { dragging = false; });
addEventListener('mousemove', e => { if (mode !== 'play') return; if (document.pointerLockElement === canvas || dragging) look(e.movementX, e.movementY); });
canvas.addEventListener('wheel', e => { cam.dist = clamp(cam.dist + Math.sign(e.deltaY) * 0.6, 2.5, 11); }, { passive: true });
let hadLock = false;
document.addEventListener('pointerlockchange', () => {
  if (document.pointerLockElement === canvas) hadLock = true;
  else if (hadLock && mode === 'play') { hadLock = false; pause(); }
});
function pause() { if (mode !== 'play') return; mode = 'paused'; hadLock = false; if (document.pointerLockElement) document.exitPointerLock(); $('pause').classList.remove('hidden'); Sound.setAmbience(0, 400, 0, 0); syncSettingsUI(); }
function resume() { if (mode !== 'paused') return; mode = 'play'; $('pause').classList.add('hidden'); last = performance.now(); canvas.click(); }
addEventListener('keydown', e => {
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space'].includes(e.code)) e.preventDefault();
  if (!keys[e.code]) pressed[e.code] = true;
  keys[e.code] = true;
  if (mode === 'title' && (e.code === 'Enter' || e.code === 'Space')) startGame();
  else if ((mode === 'won' || mode === 'lost') && (e.code === 'Enter' || e.code === 'KeyR')) startGame();
  else if (mode === 'play' && (e.code === 'KeyP' || e.code === 'Escape')) pause();
  else if (mode === 'paused' && (e.code === 'KeyP' || e.code === 'Escape')) resume();
  else if (mode === 'paused' && e.code === 'KeyR') startGame();
  if (e.code === 'KeyM') Sound.toggleMute();
});
addEventListener('keyup', e => { keys[e.code] = false; });
addEventListener('blur', () => { for (const k in keys) keys[k] = false; pause(); });
$('startBtn').addEventListener('click', startGame);
$('againBtn').addEventListener('click', startGame);
$('resumeBtn').addEventListener('click', resume);
$('restartBtn').addEventListener('click', startGame);
function syncSettingsUI() { $('sens').value = SET.sens; $('vol').value = SET.vol; $('invertBtn').textContent = I18N.t(SET.invert ? 'on' : 'off'); }
$('sens').addEventListener('input', e => { SET.sens = parseFloat(e.target.value); saveSet(); });
$('vol').addEventListener('input', e => { SET.vol = parseFloat(e.target.value); Sound.setVolume(SET.vol); saveSet(); });
$('invertBtn').addEventListener('click', () => { SET.invert = !SET.invert; saveSet(); syncSettingsUI(); });
I18N.listeners.push(() => { renderEnd(); syncSettingsUI(); });

function startGame() {
  Sound.init(); Sound.setVolume(SET.vol); cam.dist = 6.5; perf.frames = 0; perf.time = 0;
  newGame(); mode = 'play'; endInfo = null;
  ['title', 'end', 'pause'].forEach(id => $(id).classList.add('hidden'));
  $('hud').classList.remove('hidden');
  if (!document.pointerLockElement) canvas.click();
}

// ---------- main loop ----------
let last = performance.now(), clockT = 0, titleT = 0;
const perf = { frames: 0, time: 0 };
function frame(now) {
  requestAnimationFrame(frame);
  const rawDt = Math.min(0.25, (now - last) / 1000); last = now;
  const vdt = Math.min(rawDt, 0.05);
  clockT += vdt;
  if (mode === 'play') {
    if (!lowApplied && perf.time < 6) { perf.frames++; perf.time += rawDt; if (perf.time >= 4 && perf.frames / perf.time < 24) applyLowQuality(); }
    const simDt = rawDt * SPEED, steps = Math.max(1, Math.ceil(simDt / 0.05));
    for (let i = 0; i < steps && mode === 'play'; i++) update(simDt / steps);
    if (mode === 'play') {
      const acts = getActions();
      for (const k of ['E', 'F', 'Q']) if (pressed['Key' + k]) { const a = acts.filter(x => x.key === k && x.fn).sort((x, y) => x.d - y.d)[0]; if (a) a.fn(); }
      updateCamera(vdt); syncVisuals(vdt, clockT); drawHUD(vdt, getActions());
    }
  } else if (mode === 'title') {
    titleT += vdt;
    G.t = 25 + Math.sin(titleT * 0.05) * 10;
    cam.yaw = 0.35 + Math.sin(titleT * 0.05) * 0.5; cam.pitch = 0.04; cam.dist = 8;
    G.p.x = CAMP.x - 2; G.p.z = CAMP.z + 1.5; G.p.face = 2.2;
    updateCamera(vdt); syncVisuals(vdt, clockT);
  } else if (mode === 'won') {
    if (G.t < 590) { G.t += vdt * 4; G.storm = 0; G.night = Math.max(0, G.night - vdt); G.flood.level *= 0.98; }
    updateCamera(vdt); syncVisuals(vdt, clockT);
  } else if (mode === 'lost' || mode === 'paused') {
    if (mode === 'lost') cam.yaw += vdt * 0.05;
    updateCamera(vdt); syncVisuals(vdt * (mode === 'paused' ? 0 : 1), clockT);
  }
  for (const k in pressed) delete pressed[k];
  renderer.render(scene, camera);
}

// test hook for automated checks (harmless in normal play)
window.__beans = { get G() { return G; }, get mode() { return mode; }, start: startGame, cam, keys, actions: () => getActions().map(a => ({ key: a.key, k: a.m.k, ok: !!a.fn, d: a.d })), act: k => { const a = getActions().filter(x => x.key === k && x.fn).sort((x, y) => x.d - y.d)[0]; if (a) { a.fn(); return a.m.k; } return null; }, setLang: l => I18N.set(l), terrainInfo, CAMP, WAGON, OVERHANG, washX };

newGame(); G.toasts = [];
mode = 'title'; $('loading').classList.add('hidden');
I18N.apply(); syncSettingsUI();
requestAnimationFrame(frame);
