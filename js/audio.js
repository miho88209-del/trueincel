'use strict';
// Procedural WebAudio: no audio files needed.
const Sound = (() => {
  let ac = null, master, noiseBuf, brownBuf;
  let windGain, windFilter, rainGain, fireGain, musicGain;
  let muted = false;

  function init() {
    if (ac) { if (ac.state === 'suspended') ac.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try { ac = new AC(); } catch (e) { ac = null; return; }
    master = ac.createGain(); master.gain.value = 0.7; master.connect(ac.destination);
    const sr = ac.sampleRate;
    noiseBuf = ac.createBuffer(1, sr * 2, sr);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    brownBuf = ac.createBuffer(1, sr * 3, sr);
    const b = brownBuf.getChannelData(0); let last = 0;
    for (let i = 0; i < b.length; i++) { last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02; b[i] = last * 3.5; }

    const wind = ac.createBufferSource(); wind.buffer = noiseBuf; wind.loop = true;
    windFilter = ac.createBiquadFilter(); windFilter.type = 'bandpass'; windFilter.frequency.value = 400; windFilter.Q.value = 1.2;
    windGain = ac.createGain(); windGain.gain.value = 0;
    wind.connect(windFilter); windFilter.connect(windGain); windGain.connect(master); wind.start();

    const rain = ac.createBufferSource(); rain.buffer = noiseBuf; rain.loop = true; rain.playbackRate.value = 0.9;
    const rh = ac.createBiquadFilter(); rh.type = 'highpass'; rh.frequency.value = 900;
    const rl = ac.createBiquadFilter(); rl.type = 'lowpass'; rl.frequency.value = 7000;
    rainGain = ac.createGain(); rainGain.gain.value = 0;
    rain.connect(rh); rh.connect(rl); rl.connect(rainGain); rainGain.connect(master); rain.start();

    const fire = ac.createBufferSource(); fire.buffer = brownBuf; fire.loop = true;
    const fl = ac.createBiquadFilter(); fl.type = 'lowpass'; fl.frequency.value = 500;
    fireGain = ac.createGain(); fireGain.gain.value = 0;
    fire.connect(fl); fl.connect(fireGain); fireGain.connect(master); fire.start();

    musicGain = ac.createGain(); musicGain.gain.value = 0.5; musicGain.connect(master);
  }

  const ok = () => ac && !muted;

  function setAmbience(wind, windFreq, rain, fire) {
    if (!ac) return;
    const t = ac.currentTime;
    windGain.gain.setTargetAtTime(muted ? 0 : wind * 0.35, t, 0.3);
    windFilter.frequency.setTargetAtTime(windFreq, t, 0.4);
    rainGain.gain.setTargetAtTime(muted ? 0 : rain * 0.16, t, 0.5);
    fireGain.gain.setTargetAtTime(muted ? 0 : fire * 0.5, t, 0.2);
  }

  function noise({ dur = 0.2, freq = 1000, type = 'bandpass', q = 1, vol = 0.3, attack = 0.005, buf, rate = 1, freqEnd }) {
    if (!ok()) return;
    const t = ac.currentTime;
    const s = ac.createBufferSource(); s.buffer = buf || noiseBuf; s.playbackRate.value = rate;
    const f = ac.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
    if (freqEnd) f.frequency.exponentialRampToValueAtTime(freqEnd, t + dur);
    const g = ac.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(master);
    s.start(t, Math.random() * 1.5); s.stop(t + dur + 0.05);
  }

  function tone({ type = 'sine', f0 = 440, f1, dur = 0.2, vol = 0.2, attack = 0.01, delay = 0, dest, vib = 0, vibRate = 8, lp }) {
    if (!ok()) return;
    const t = ac.currentTime + delay;
    const o = ac.createOscillator(); o.type = type; o.frequency.setValueAtTime(f0, t);
    if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ac.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    let node = o;
    if (vib) {
      const l = ac.createOscillator(); l.frequency.value = vibRate;
      const lg = ac.createGain(); lg.gain.value = vib; l.connect(lg); lg.connect(o.frequency);
      l.start(t); l.stop(t + dur + 0.05);
    }
    if (lp) { const f = ac.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = lp; o.connect(f); node = f; }
    node.connect(g); g.connect(dest || master);
    o.start(t); o.stop(t + dur + 0.05);
  }

  return {
    init,
    get ready() { return !!ac; },
    toggleMute() { muted = !muted; if (ac) master.gain.setTargetAtTime(muted ? 0 : 0.7, ac.currentTime, 0.05); return muted; },
    setAmbience,
    crackle(vol = 0.12) { noise({ dur: 0.04 + Math.random() * 0.05, freq: 1500 + Math.random() * 3000, q: 2, vol }); },
    thunder(vol = 0.9) {
      noise({ dur: 3.5, freq: 160, type: 'lowpass', q: 0.5, vol, attack: 0.08, buf: brownBuf, rate: 0.6 });
      noise({ dur: 0.6, freq: 900, type: 'lowpass', q: 0.4, vol: vol * 0.5, attack: 0.01 });
    },
    rumble() { noise({ dur: 4.5, freq: 90, type: 'lowpass', q: 0.7, vol: 0.9, attack: 1.5, buf: brownBuf, rate: 0.5 }); },
    whoosh() { noise({ dur: 2.6, freq: 300, freqEnd: 1400, q: 1.5, vol: 0.4, attack: 1.4 }); },
    splash() { noise({ dur: 1.2, freq: 1200, type: 'lowpass', q: 0.5, vol: 0.6, attack: 0.02 }); },
    rustle() { for (let i = 0; i < 6; i++) setTimeout(() => noise({ dur: 0.12, freq: 3000, q: 0.8, vol: 0.12 }), i * 90 + Math.random() * 50); },
    pickup() { tone({ type: 'triangle', f0: 520, f1: 780, dur: 0.12, vol: 0.12 }); },
    wood() { noise({ dur: 0.15, freq: 700, q: 3, vol: 0.3 }); tone({ type: 'triangle', f0: 180, f1: 120, dur: 0.12, vol: 0.12 }); },
    feed() { noise({ dur: 0.5, freq: 2500, q: 0.7, vol: 0.2, attack: 0.02 }); for (let i = 0; i < 5; i++) setTimeout(() => this.crackle(0.2), i * 60); },
    match() { noise({ dur: 0.35, freq: 4000, q: 0.8, vol: 0.3, attack: 0.01 }); },
    fizzle() { noise({ dur: 0.6, freq: 6000, freqEnd: 2000, q: 0.5, vol: 0.2, attack: 0.01 }); },
    clink() { tone({ f0: 2300, dur: 0.35, vol: 0.12 }); tone({ f0: 3450, dur: 0.25, vol: 0.06 }); },
    eat() { for (let i = 0; i < 4; i++) noise({ dur: 0.08, freq: 800 + i * 200, q: 1, vol: 0.15 }); tone({ type: 'triangle', f0: 400, f1: 600, dur: 0.15, vol: 0.08, delay: 0.3 }); },
    ouch() { tone({ type: 'square', f0: 500, f1: 300, dur: 0.15, vol: 0.06, lp: 1500 }); },
    neigh() { tone({ type: 'sawtooth', f0: 520, f1: 760, dur: 0.35, vol: 0.12, vib: 40, vibRate: 22, lp: 2200 }); tone({ type: 'sawtooth', f0: 760, f1: 380, dur: 0.7, vol: 0.12, vib: 60, vibRate: 25, delay: 0.3, lp: 2000 }); },
    snort() { noise({ dur: 0.3, freq: 600, q: 0.6, vol: 0.25, attack: 0.02 }); },
    chitter() { for (let i = 0; i < 7; i++) tone({ type: 'square', f0: 1700 + Math.random() * 900, dur: 0.05, vol: 0.05, delay: i * 0.07, lp: 4000 }); },
    toot(low = false) {
      tone({ type: 'sawtooth', f0: low ? 70 : 110, f1: low ? 55 : 80, dur: low ? 0.9 : 0.6, vol: 0.25, vib: low ? 18 : 25, vibRate: low ? 13 : 18, lp: 500 });
    },
    hat() { noise({ dur: 0.5, freq: 900, q: 1, vol: 0.2, attack: 0.03 }); },
    pluck(f, vol = 0.12) {
      if (!ok()) return;
      tone({ type: 'triangle', f0: f, dur: 1.6, vol, attack: 0.004, dest: musicGain, lp: 1800 });
      tone({ type: 'sine', f0: f * 2, dur: 0.5, vol: vol * 0.3, attack: 0.004, dest: musicGain });
    },
    musicLevel(v) { if (ac) musicGain.gain.setTargetAtTime(v, ac.currentTime, 0.4); },
    sting(win) {
      const notes = win ? [220, 277, 330, 440, 554, 660] : [220, 208, 196, 147];
      notes.forEach((f, i) => setTimeout(() => this.pluck(f, 0.25), i * (win ? 140 : 380)));
    },
  };
})();
