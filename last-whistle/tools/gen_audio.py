#!/usr/bin/env python3
"""Procedural audio generator for "The Last Whistle".

Everything is synthesized with numpy/scipy (no samples). Fixed per-file seeds
(crc32 of the file name) make output reproducible. Loops are built from
spectrally-shaped noise (exactly periodic) and wrapped events, so they are
seamless by construction.

Usage:  python3 tools/gen_audio.py [--only name1,name2] [--no-verify]
Requires: numpy, scipy, ffmpeg (libvorbis) on PATH.
"""
import os, sys, zlib, subprocess, tempfile, json, time
import numpy as np
from scipy import signal
from scipy.io import wavfile
from multiprocessing import Pool

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "audio"))
TAU = 2 * np.pi


# ----------------------------------------------------------------- helpers
def N(d): return int(round(d * SR))
def tt(d): return np.arange(N(d)) / SR
def midi(m): return 440.0 * 2 ** ((np.asarray(m, float) - 69) / 12)
def cents(c): return 2 ** (c / 1200.0)


def sp_noise(n, rng, lo=None, hi=None, slope=0.0, order=2):
    """Unit-RMS noise shaped in the frequency domain (exactly periodic over n)."""
    f = np.fft.rfftfreq(n, 1 / SR); f[0] = f[1]
    spec = rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))
    a = f ** (-slope / 2.0)
    if hi: a = a / np.sqrt(1 + (f / hi) ** (2 * order))
    if lo: a = a / np.sqrt(1 + (lo / f) ** (2 * order))
    spec = spec * a; spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def nz(n, rng, lo=None, hi=None, slope=0.0, order=2):
    return sp_noise(max(n, 16), rng, lo, hi, slope, order)[:n]


def sos(kind, f, order=2): return signal.butter(order, f, btype=kind, fs=SR, output="sos")
def lp(x, f, o=2): return signal.sosfilt(sos("lowpass", min(f, 20000), o), x, axis=0)
def hp(x, f, o=2): return signal.sosfilt(sos("highpass", f, o), x, axis=0)
def bp(x, lo, hi, o=2): return signal.sosfilt(sos("bandpass", [lo, min(hi, 20000)], o), x, axis=0)


def loopf(fn, x):
    """Apply an LTI filter to a periodic signal without edge artefacts."""
    n = len(x)
    return fn(np.concatenate([x, x, x]))[n:2 * n]


def norm01(m):
    return (m - m.min()) / (m.max() - m.min() + 1e-12)


def dec(n, tau, atk=0.002):
    t = np.arange(n) / SR
    return (1 - np.exp(-t / atk)) * np.exp(-t / tau)


def smooth(t, pts, vals):
    return np.interp(t, pts, vals)


def put(buf, sig, t0, gain=1.0, pan=None, wrap=False):
    sig = np.asarray(sig, float) * gain
    if buf.ndim == 2 and sig.ndim == 1:
        a = (0.5 if pan is None else pan) * np.pi / 2
        sig = np.stack([sig * np.cos(a), sig * np.sin(a)], 1)
    L = len(buf); i = int(round(t0 * SR))
    if wrap:
        i %= L; pos = 0; m = len(sig)
        while pos < m:
            k = min(m - pos, L - i)
            buf[i:i + k] += sig[pos:pos + k]
            pos += k; i = (i + k) % L
    else:
        if i < 0: sig = sig[-i:]; i = 0
        k = min(len(sig), L - i)
        if k > 0: buf[i:i + k] += sig[:k]


def fit(x, n):
    x = np.asarray(x, float)
    if len(x) >= n: return x[:n]
    pad = np.zeros((n - len(x),) + x.shape[1:])
    return np.concatenate([x, pad])


def make_ir(rt60, seed, damp=5000, pre=0.0):
    rng = np.random.default_rng(seed)
    L = N(rt60); t = np.arange(L) / SR
    ir = rng.standard_normal(L) * np.exp(-6.908 * t / rt60)
    ir = lp(ir, damp, 1)
    ir = np.concatenate([np.zeros(N(pre)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, rt60, wet=0.3, seed=1, damp=5000, pre=0.0, tail=None, dry=1.0):
    """Linear convolution reverb; output is longer than input by `tail`."""
    x = np.asarray(x, float)
    nt = N(rt60 * 0.7 if tail is None else tail)
    xp = np.concatenate([x, np.zeros((nt,) + x.shape[1:])])
    chans = [xp] if xp.ndim == 1 else [xp[:, 0], xp[:, 1]]
    outs = []
    for c, ch in enumerate(chans):
        ir = make_ir(rt60, seed + c * 17, damp, pre)
        w = signal.fftconvolve(ch, ir)[:len(ch)]
        outs.append(dry * ch + wet * w)
    return outs[0] if xp.ndim == 1 else np.stack(outs, 1)


def creverb(x, rt60, seed=1, damp=4000):
    """Circular reverb: returns the wet signal only (keeps loops seamless)."""
    n = len(x)
    chans = [x] if x.ndim == 1 else [x[:, 0], x[:, 1]]
    outs = []
    for c, ch in enumerate(chans):
        ir = make_ir(min(rt60, (n - 1) / SR), seed + c * 17, damp)
        irp = np.zeros(n); irp[:len(ir)] = ir
        outs.append(np.fft.irfft(np.fft.rfft(ch) * np.fft.rfft(irp), n))
    return outs[0] if x.ndim == 1 else np.stack(outs, 1)


def finish(x, dur=None, peak=-1.5, fi=0.003, fo=0.03):
    x = np.asarray(x, float)
    if dur: x = fit(x, N(dur))
    x = x - x.mean(axis=0)
    n = len(x)
    a = min(N(fi), n // 2); b = min(N(fo), n // 2)
    if a > 0:
        w = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
        x[:a] *= w if x.ndim == 1 else w[:, None]
    if b > 0:
        w = np.cos(np.linspace(0, np.pi / 2, b)) ** 2
        x[-b:] *= w if x.ndim == 1 else w[:, None]
    return x * (10 ** (peak / 20) / (np.abs(x).max() + 1e-12))


# ------------------------------------------------------------ sound atoms
def ping(freqs, amps, taus, dur, atk=0.0004):
    t = tt(dur); x = np.zeros(len(t))
    for f, a, tau in zip(freqs, amps, taus):
        x += a * np.sin(TAU * f * t) * np.exp(-t / tau)
    return x * (1 - np.exp(-t / atk))


def thump(f0, f1, dur, tau, k=0.03):
    t = tt(dur)
    f = f1 + (f0 - f1) * np.exp(-t / k)
    return np.sin(TAU * np.cumsum(f) / SR) * dec(len(t), tau, 0.001)


def nburst(rng, dur, lo, hi, tau, atk=0.001, order=2):
    n = N(dur)
    return nz(n, rng, lo, hi, order=order) * dec(n, tau, atk)


def crinkle(rng, dur, density, lo, hi, grain=0.002, wrap=False):
    """Grainy noise: noise gated by random decaying grains."""
    n = N(dur)
    base = nz(n, rng, lo, hi, order=2)
    gate = (rng.random(n) < density / SR) * (rng.random(n) ** 2 + 0.1)
    a = np.exp(-1 / (grain * SR))
    if wrap:
        g = signal.lfilter([1], [1, -a], np.concatenate([gate, gate]))[n:]
    else:
        g = signal.lfilter([1], [1, -a], gate)
    g = g / (np.sqrt(np.mean(g ** 2)) + 1e-12)
    return base * g


def clatter(rng, dur, hits, flo, fhi, tau_lo=0.006, tau_hi=0.03, bias=1.8, dens_amp=1.0):
    buf = np.zeros(N(dur))
    for _ in range(hits):
        t0 = (rng.random() ** bias) * dur * 0.95
        f = np.exp(rng.uniform(np.log(flo), np.log(fhi)))
        tau = rng.uniform(tau_lo, tau_hi)
        a = rng.uniform(0.2, 1.0) * (1 - 0.6 * t0 / dur) * dens_amp
        s = ping([f, f * 1.9], [1, 0.4], [tau, tau * 0.6], 0.12)
        s += 0.7 * nburst(rng, 0.12, f * 0.6, min(f * 2.5, 19000), tau * 0.5)
        put(buf, s, t0, a)
    return buf


def whoosh(rng, dur, bands):
    n = N(dur); t = np.arange(n) / SR; x = np.zeros(n)
    for lo, hi, tp, w, a in bands:
        x += a * nz(n, rng, lo, hi) * np.exp(-0.5 * ((t - tp) / w) ** 2)
    return x


def creak(rng, dur, f0, f1, fmid=None, res=(400, 1200), noise=0.15, jit=0.25):
    n = N(dur); t = np.arange(n) / SR; u = t / dur
    f = np.interp(u, [0, 0.5, 1], [f0, fmid or (f0 + f1) / 2, f1])
    f = f * (1 + jit * 0.2 * nz(n, rng, 3, 25))
    ph = np.cumsum(f) / SR
    saw = (ph % 1.0) * 2 - 1
    x = saw + noise * nz(n, rng, 200, 4000)
    y = bp(x, *res, 2) + 0.6 * bp(x, res[0] * 1.8, res[1] * 1.8, 2)
    env = np.sin(np.pi * u) ** 0.8 * (0.55 + 0.45 * norm01(nz(n, rng, 2, 12)))
    y = y * env
    return y / (np.std(y) + 1e-12)


def chuff_sig(rng, g=1.0, dur=0.35):
    n = N(dur)
    a = nz(n, rng, 180, 1800) * dec(n, 0.075, 0.006)
    b = nz(n, rng, 2500, 9000) * dec(n, 0.12, 0.012) * 0.25
    c = thump(70, 38, dur, 0.07, 0.03) * 0.8
    return (a + b + c) * g


def saw_ph(ph, nh=8):
    x = np.zeros(len(ph))
    for k in range(1, nh + 1):
        x += np.sin(TAU * k * ph) / k
    return x * 0.6


def ar_env(n, atk, rel):
    t = np.arange(n) / SR
    up = np.clip(t / atk, 0, 1); dn = np.clip((n / SR - t) / rel, 0, 1)
    return np.sin(up * np.pi / 2) ** 2 * np.sin(dn * np.pi / 2) ** 2


def pad_voice(freqs, dur, rng, det=7, nh=6, cut=1200, atk=2.5, rel=3.0, stereo=True):
    n = N(dur); t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for f in freqs:
        for d, wl in ((-det, 1.0), (det, 0.45), (0.0, 0.0)):
            ph = f * cents(d) * t + rng.random()
            s = saw_ph(ph, nh) if d != 0 else np.sin(TAU * ph) * 0.8
            if d == 0:
                out[:, 0] += s * 0.4; out[:, 1] += s * 0.4
            else:
                out[:, 0] += s * wl; out[:, 1] += s * (1.45 - wl)
    out = lp(out, cut, 2)
    out *= ar_env(n, atk, rel)[:, None]
    return out / len(freqs)


def mbox(f, dur=3.5):
    r = [1, 2.0, 3.01, 4.2, 5.8]; a = [1, .35, .15, .1, .05]; tau = [2.2, 1.1, .6, .35, .2]
    k = (440 / f) ** 0.3
    t = tt(dur); x = np.zeros(len(t))
    for ri, ai, ti in zip(r, a, tau):
        if f * ri < 15000:
            x += ai * np.sin(TAU * f * ri * t) * np.exp(-t / (ti * k))
    return x * (1 - np.exp(-t / 0.001)) * 0.5


def felt(f, dur=4.5):
    t = tt(dur); x = np.zeros(len(t))
    for k in range(1, 8):
        x += np.sin(TAU * f * k * (1 + 0.0002 * k * k) * t) / k ** 1.3 * np.exp(-t / (3.5 / k ** 0.5))
    x = x * (1 - np.exp(-t / 0.012))
    return lp(x, 1800, 2) * 0.6


def bell_tone(f, dur=6.0, bright=1.0):
    r = [1, 2.0, 2.4, 3.0, 4.07, 5.95]; a = [1, .5, .3, .25, .15, .08]; tau = [4, 2.5, 2, 1.6, 1, .6]
    t = tt(dur); x = np.zeros(len(t))
    for ri, ai, ti in zip(r, a, tau):
        if f * ri < 15000:
            x += ai * (bright if ri > 1 else 1) * np.sin(TAU * f * ri * t) * np.exp(-t / ti)
    return x * (1 - np.exp(-t / 0.004)) * 0.4


def sweep_lp(x, e, cuts):
    ys = [loopf(lambda z, c=c: lp(z, c, 2), x) for c in cuts]
    pos = e * (len(cuts) - 1); out = 0
    for i, y in enumerate(ys):
        w = np.clip(1 - np.abs(pos - i), 0, 1)
        out = out + (w[:, None] if y.ndim == 2 else w) * y
    return out


# ================================================================== LOOPS
def g_amb_wind(rng):
    n = N(30)
    gust = norm01(sp_noise(n, rng, 0.04, 0.35))
    gust2 = norm01(sp_noise(n, rng, 0.05, 0.3))
    x = sp_noise(n, rng, 120, 900) * (0.25 + 0.75 * gust ** 1.5) * 0.7
    x += sp_noise(n, rng, 40, 220) * (0.4 + 0.4 * gust) * 0.6
    x += sp_noise(n, rng, 900, 2200, order=3) * gust2 ** 3 * 0.12
    return finish(x, peak=-3, fi=0, fo=0)


def g_amb_forest(rng):
    d = 40; n = N(d)
    bed = sp_noise(n, rng, 100, 500, slope=1) * (0.35 + 0.35 * norm01(sp_noise(n, rng, 0.05, 0.4))) * 0.5
    sw = norm01(sp_noise(n, rng, 0.1, 1.2)) ** 3
    leaf = sp_noise(n, rng, 2500, 7000) * sw * 0.22
    leaf += crinkle(rng, d, 50, 3000, 8000, wrap=True) * 0.05
    x = bed + leaf
    for pos in np.linspace(2, 38, 6) + rng.uniform(-2, 2, 6):
        c = creak(rng, rng.uniform(1.2, 2.2), rng.uniform(50, 90), rng.uniform(60, 110), res=(300, 900))
        c = lp(c, 1500, 2)
        c = reverb(c, 1.8, 0.7, int(pos * 10), 1500, dry=0.5)
        put(x, c, pos, 0.07, wrap=True)
    return finish(x, peak=-3, fi=0, fo=0)


def g_amb_rain(rng):
    d = 30; n = N(d)
    mod = 0.85 + 0.15 * norm01(sp_noise(n, rng, 0.05, 0.5))
    x = sp_noise(n, rng, 1500, 9000, slope=0.3) * 0.45 * mod
    x += sp_noise(n, rng, 300, 1200, slope=0.5) * 0.5 * mod
    x += crinkle(rng, d, 90, 2500, 7500, wrap=True) * 0.25
    for _ in range(int(d * 6)):
        f = rng.uniform(1000, 3200)
        put(x, ping([f, f * 2.3], [1, .3], [0.012, 0.006], 0.06), rng.uniform(0, d),
            0.25 * rng.random() ** 2.0 + 0.04, wrap=True)
    x = loopf(lambda z: lp(z, 8000, 2), x)
    return finish(x, peak=-3, fi=0, fo=0)


def g_train_rumble(rng):
    d = 10; n = N(d); t = np.arange(n) / SR
    x = sp_noise(n, rng, 20, 110, slope=2, order=3) * 1.0
    x += sp_noise(n, rng, 90, 500, slope=1) * 0.35 * (0.8 + 0.2 * norm01(sp_noise(n, rng, 0.3, 2)))
    for f, a, m in ((36, 0.22, 0.8), (52.3, 0.12, 1.3)):
        f = round(f * d) / d
        x += a * np.sin(TAU * f * t) * (0.7 + 0.3 * np.sin(TAU * round(m * d) / d * t))
    unit = np.zeros(N(0.5))
    put(unit, nburst(rng, 0.12, 40, 130, 0.05, 0.004) * 1.0, 0.0, 0.9)
    put(unit, nburst(rng, 0.12, 40, 130, 0.05, 0.004), 0.095, 0.6)
    put(unit, nburst(rng, 0.05, 1200, 3500, 0.012), 0.0, 0.08)
    put(unit, nburst(rng, 0.05, 1200, 3500, 0.012), 0.095, 0.06)
    for i in range(20):
        put(x, unit, i * 0.5, 0.45 * rng.uniform(0.7, 1.1), wrap=True)
    return finish(x, peak=-3, fi=0, fo=0)


def g_steam_hiss(rng):
    n = N(6)
    x = sp_noise(n, rng, 2500, 11000) * (0.75 + 0.25 * norm01(sp_noise(n, rng, 0.4, 3)))
    x += sp_noise(n, rng, 500, 2500) * 0.25 * (0.7 + 0.3 * norm01(sp_noise(n, rng, 0.3, 2)))
    return finish(x, peak=-4, fi=0, fo=0)


def g_furnace_fire(rng):
    d = 10; n = N(d)
    x = sp_noise(n, rng, 30, 500, slope=1) * (0.6 + 0.4 * norm01(sp_noise(n, rng, 0.2, 1.5)))
    x += sp_noise(n, rng, 300, 2500, slope=1) * 0.3 * (0.5 + 0.5 * norm01(sp_noise(n, rng, 0.3, 2)))
    for _ in range(130):
        f = rng.uniform(1500, 5000)
        a = min(0.05 + rng.exponential(0.15), 0.9)
        s = ping([f], [1], [0.004], 0.03) + nburst(rng, 0.03, 800, 6000, 0.004)
        put(x, s, rng.uniform(0, d), a, wrap=True)
    for _ in range(9):
        put(x, thump(120, 60, 0.15, 0.04) + nburst(rng, 0.15, 150, 900, 0.03),
            rng.uniform(0, d), rng.uniform(0.3, 0.6), wrap=True)
    return finish(x, peak=-3, fi=0, fo=0)


# ------------------------------------------------------------------ MUSIC
def g_music_menu(rng):
    T = 80.0; n = N(T); beat = T / 96
    chords = {
        "Am": [45, 52, 57, 60, 64], "F": [41, 48, 57, 60, 65], "Dm": [38, 50, 57, 62, 65],
        "E": [40, 52, 56, 59, 64], "C": [48, 52, 55, 60, 64], "Em": [40, 52, 55, 59, 64]}
    prog = ["Am", "F", "Dm", "E", "Am", "F", "C", "Em", "Am", "F", "Dm", "E"]
    cl = 8 * beat
    pad = np.zeros((n, 2)); notes = np.zeros((n, 2))
    minor_pcs = {9, 11, 0, 2, 4, 5, 7}
    prev = 76
    for i, name in enumerate(prog):
        ch = chords[name]; t0 = i * cl
        pad += 0  # placeholder to keep structure explicit
        put(pad, pad_voice(midi(ch), cl + 3.0, rng, det=6, nh=5, cut=900, atk=2.5, rel=3.0),
            t0 - 1.2, 0.5, wrap=True)
        put(notes, felt(midi(ch[0])), t0, 0.5, pan=0.45, wrap=True)
        put(notes, felt(midi(ch[0]) * 1.5), t0 + 0.02, 0.2, pan=0.55, wrap=True)
        pcs = minor_pcs | {m % 12 for m in ch}
        pool = [m for m in range(69, 87) if m % 12 in pcs]
        tones = {m % 12 for m in ch}
        for s in range(16):
            p = 0.9 if s == 0 else (0.33 if s % 4 == 0 else 0.2)
            if rng.random() > p: continue
            w = np.array([(3.0 if m % 12 in tones else 1.0) * np.exp(-abs(m - prev) / 3.0) for m in pool])
            m = int(rng.choice(pool, p=w / w.sum())); prev = m
            put(notes, mbox(midi(m)), t0 + s * beat / 2, rng.uniform(0.5, 0.85),
                pan=rng.uniform(0.3, 0.7), wrap=True)
    wet = creverb(notes + 0.3 * pad, 3.5, seed=11, damp=5000)
    x = pad * 0.55 + notes + 0.6 * wet
    return finish(x, peak=-2.5, fi=0, fo=0)


def g_music_travel(rng):
    T = 90.0; n = N(T); t = np.arange(n) / SR
    x = np.zeros((n, 2))
    f1 = round(36.71 * T) / T; f2 = round(73.42 * T) / T
    lfo = 0.5 + 0.5 * np.sin(TAU * 6 / T * t)
    sub = 0.5 * np.sin(TAU * f1 * t) + 0.25 * loopf(lambda z: lp(z, 220, 2), saw_ph(f2 * t, 6)) * (0.5 + 0.5 * lfo)
    sub = sub * (0.7 + 0.3 * lfo)
    x += sub[:, None] * 0.9
    chords = [[38, 50, 57, 60, 64], [34, 46, 53, 57, 64], [43, 55, 58, 62, 69],
              [45, 52, 57, 58, 64], [38, 50, 57, 62, 65], [40, 52, 55, 58, 62]]
    cl = T / 6
    for i, ch in enumerate(chords):
        put(x, pad_voice(midi(ch), cl + 11, rng, det=9, nh=5, cut=700, atk=5.5, rel=6.0),
            i * cl - 3, 0.55, wrap=True)
    air = sp_noise(n, rng, 300, 1200, slope=1) * norm01(sp_noise(n, rng, 0.05, 0.3)) ** 2 * 0.05
    x += air[:, None]
    notes = np.zeros((n, 2))
    pent = [62, 65, 67, 69, 72]
    for _ in range(14):
        m = int(rng.choice(pent)) + 12 * int(rng.integers(0, 2))
        put(notes, lp(bell_tone(midi(m), 7.0, 0.5), 3000, 2), rng.uniform(0, T), rng.uniform(.08, .2),
            pan=rng.uniform(.2, .8), wrap=True)
    x += notes + 1.2 * creverb(notes, 4.5, seed=21, damp=3000)
    return finish(x, peak=-2.5, fi=0, fo=0)


def g_music_stop(rng):
    T = 60.0; n = N(T); t = np.arange(n) / SR
    x = np.zeros((n, 2))
    sn = lambda f: round(f * T) / T
    pulse = (0.5 + 0.5 * np.sin(TAU * 12 / T * t - 1.2)) ** 2
    sub = (np.sin(TAU * sn(41.2) * t) + 0.8 * np.sin(TAU * sn(43.65) * t)) * (0.25 + 0.75 * pulse)
    x += sub[:, None] * 0.5
    put(x, pad_voice(midi([40, 46, 52, 58]), T + 8, rng, det=4, nh=4, cut=380, atk=14, rel=14),
        -4, 0.18, wrap=True)
    hi = np.zeros((n, 2)); sh = np.zeros((n, 2))
    for _ in range(5):
        f = rng.uniform(1500, 3400); d = rng.uniform(3.5, 8); L = rng.uniform(9, 14)
        tl = tt(L)
        s = (np.sin(TAU * f * tl) + np.sin(TAU * (f + d) * tl)) * np.sin(np.pi * tl / L) ** 2
        put(hi, s, rng.uniform(0, T), 0.025, pan=rng.uniform(.1, .9), wrap=True)
    for _ in range(6):
        b = rng.uniform(900, 1800); r = [1, 1.47, 2.09, 2.76, 3.9]
        tl = tt(5.0); s = np.zeros(len(tl))
        for k, ri in enumerate(r):
            s += np.sin(TAU * b * ri * tl + k) * np.exp(-tl / rng.uniform(1.0, 2.2)) / (1 + k * .5)
        s *= (1 - np.exp(-tl / 0.05))
        put(sh, s, rng.uniform(0, T), 0.05, pan=rng.uniform(.15, .85), wrap=True)
    br = sp_noise(n, rng, 2000, 6000) * norm01(sp_noise(n, rng, 0.05, 0.3)) ** 3 * 0.012
    x += hi + sh + br[:, None] + 1.5 * creverb(hi + sh, 5.0, seed=31, damp=4000)
    return finish(x, peak=-2.5, fi=0, fo=0)


def g_music_danger(rng):
    T = 40.0; n = N(T); t = np.arange(n) / SR
    snap = lambda f: np.round(f * T) / T
    e = np.where(t < 34, 0.15 + 0.85 * (t / 34) ** 1.5,
                 0.15 + 0.85 * (0.5 + 0.5 * np.cos(np.pi * (t - 34) / 6)))
    cl = np.zeros((n, 2))
    for m in [38, 50, 51, 57, 58, 62, 66, 68]:
        for v in range(2):
            f = snap(midi(m) * cents(rng.uniform(-18, 18)))
            vf = rng.integers(3, 8) * 0.5; vf = round(vf * T) / T
            ph = f * t + (f * 0.004 / (TAU * vf)) * np.sin(TAU * vf * t + rng.random() * 6)
            s = saw_ph(ph, 7)
            swell = 0.6 + 0.4 * np.sin(TAU * int(rng.integers(2, 6)) * t / T + rng.random() * 6.28)
            a = rng.random()
            cl[:, 0] += s * swell * a; cl[:, 1] += s * swell * (1 - a)
    cl = sweep_lp(cl, e, [500, 1200, 2800]) * (0.25 + 0.75 * e)[:, None] * 0.12
    x = cl.copy()
    x += (0.5 * np.sin(TAU * snap(36.71) * t) * (0.5 + 0.5 * e))[:, None] * 0.6
    tr = 0.5 + 0.5 * np.sin(TAU * 280 / T * t)
    x += (np.sin(TAU * snap(2093) * t) * e ** 2 * tr * 0.025)[:, None]
    hb = np.zeros((n, 2)); tc = 0.5
    while tc < T - 0.6:
        iv = np.interp(tc, [0, 34], [1.5, 0.8]) * rng.uniform(0.88, 1.12)
        beat = thump(62, 38, 0.35, 0.12, 0.03) + 0.65 * np.pad(thump(70, 45, 0.3, 0.1, 0.03), (N(0.26), 0))[:N(0.35)]
        put(hb, lp(beat, 160, 2), tc, 0.9 + 0.3 * e[min(n - 1, N(tc))], wrap=True)
        tc += iv
    x += hb * 0.9
    x += 0.35 * creverb(x, 2.5, seed=41, damp=3500)
    return finish(x, peak=-2.5, fi=0, fo=0)


def g_music_ending(rng):
    T = 60.0; n = N(T + 8)
    chords = [[38, 50, 57, 62, 66], [40, 52, 57, 61, 64], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62],
              [38, 50, 57, 62, 66], [40, 52, 57, 61, 64], [43, 50, 55, 59, 62], [38, 50, 57, 62, 66, 69]]
    cl = 7.5
    pad = np.zeros((n, 2)); notes = np.zeros((n, 2))
    pool_all = [74, 76, 78, 81, 83, 86]
    for i, ch in enumerate(chords):
        t0 = i * cl
        put(pad, pad_voice(midi(ch), cl + 4.5, rng, det=5, nh=5, cut=1800, atk=2.5, rel=3.5), t0 - 1, 0.5)
        put(notes, felt(midi(ch[0])), t0, 0.55, pan=0.45)
        tones = {m % 12 for m in ch}
        pool = [m for m in pool_all if m % 12 in tones] or pool_all
        nn = 4 if i < 7 else 3
        for k in range(nn):
            tn = t0 + 0.6 + k * 1.55 + rng.uniform(-0.1, 0.1)
            if i == 0 and tn < 3: continue
            m = int(rng.choice(pool))
            put(notes, bell_tone(midi(m), 7.0, 1.0), tn, rng.uniform(.35, .6), pan=rng.uniform(.3, .7))
    x = pad * 0.6 + notes
    x = x + 0.5 * reverb(x * 0.6, 3.5, 1.0, 51, 5000, tail=0.5, dry=0.0)[:n]
    x = fit(x, N(T))
    fo = N(9); w = np.cos(np.linspace(0, np.pi / 2, fo)) ** 2
    x[-fo:] *= w[:, None]
    return finish(x, peak=-2.5, fi=1.5, fo=0.05)


# --------------------------------------------------------------- ONE-SHOTS
def g_chuff(rng):
    return finish(chuff_sig(rng), 0.35, peak=-2, fo=0.05)


def whistle_core(rng, dur, fs=(440.0, 523.25, 659.25)):
    n = N(dur); t = np.arange(n) / SR; out = np.zeros(n)
    for k, f0 in enumerate(fs):
        det = 1 + rng.uniform(-.004, .004)
        glide = 1 - 0.025 * np.exp(-t / 0.07)
        sag = 1 - 0.012 * np.clip((t - dur * 0.55) / (dur * 0.45), 0, 1) ** 2
        vib = 1 + 0.003 * np.sin(TAU * (4.8 + 0.4 * k) * t + k) * np.clip(t / 0.5, 0, 1)
        ph = TAU * np.cumsum(f0 * det * glide * sag * vib) / SR
        s = np.sin(ph) + .28 * np.sin(2 * ph) + .12 * np.sin(3 * ph) + .05 * np.sin(4 * ph)
        s = s * (1 + 0.05 * nz(n, rng, 5, 30)) + 0.12 * nz(n, rng, f0 * .8, f0 * 3)
        out += s * (1 - 0.12 * k)
    tr = dur * 0.68
    env = (1 - np.exp(-t / 0.07)) * (0.8 + 0.3 * np.exp(-t / 0.3))
    rel = np.where(t > tr, np.cos(np.clip((t - tr) / (dur - tr), 0, 1) * np.pi / 2) ** 2, 1.0)
    return out * env * rel


def g_whistle(rng):
    x = reverb(whistle_core(rng, 2.0), 0.9, 0.18, 61, 5000, tail=0.4)
    return finish(x, 2.4, peak=-1.5, fi=0.01, fo=0.05)


def g_whistle_distant(rng):
    w = whistle_core(rng, 2.4)
    w = hp(lp(w, 1600, 2), 150, 1)
    x = reverb(w, 3.2, 1.2, 62, 2500, pre=0.1, tail=2.6, dry=0.6)
    return finish(x, 5.0, peak=-8, fi=0.15, fo=0.4)


def g_rail_clack(rng):
    buf = np.zeros(N(0.5))
    for t0, a in ((0.0, 1.0), (0.11, 0.7)):
        s = nburst(rng, 0.12, 800, 4000, 0.01) * 0.7
        s += ping([1100, 1700, 2900], [.5, .4, .25], [.03, .025, .02], 0.12)
        s += thump(130, 80, 0.12, 0.04) * 0.8
        put(buf, s, t0, a)
    put(buf, nburst(rng, 0.3, 60, 400, 0.12, 0.02), 0.03, 0.15)
    return finish(buf, 0.5, peak=-2, fo=0.08)


def g_brake(rng):
    d = 2.0; n = N(d); t = np.arange(n) / SR
    f = (1750 - 350 * np.clip(t / 1.3, 0, 1)) * (1 + 0.01 * nz(n, rng, 10, 60))
    ph = TAU * np.cumsum(f) / SR
    sq = np.sin(ph) + .5 * np.sin(1.507 * ph + 1) + .3 * np.sin(2.01 * ph)
    sq *= 0.6 + 0.4 * norm01(nz(n, rng, 6, 40))
    env = np.interp(t, [0, 0.12, 0.9, 1.4], [0, 1, 0.8, 0])
    x = sq * env * 0.5 + nz(n, rng, 1200, 4000) * 0.12 * env + nz(n, rng, 200, 900) * 0.15 * env
    h = nz(n, rng, 2500, 12000) * np.where(t > 0.25, np.exp(-(t - 0.25) / 0.6), 0) * (1 - np.exp(-(t - .25).clip(0) / .05))
    return finish(x + h * 0.5, d, peak=-2, fi=0.02, fo=0.2)


def g_lever(rng):
    buf = np.zeros(N(0.4))
    for t0, a in ((0.0, .3), (0.07, .35), (0.13, .4)):
        put(buf, nburst(rng, 0.03, 1000, 4500, 0.004) + ping([2400], [.3], [.01], 0.03), t0, a)
    s = thump(120, 55, 0.25, 0.06) + ping([600, 1370, 2200], [.5, .4, .25], [.08, .06, .04], 0.25)
    s += nburst(rng, 0.25, 400, 3000, 0.012)
    put(buf, s, 0.22, 1.0)
    return finish(buf, 0.4, peak=-2, fo=0.06)


def g_furnace_door(rng):
    buf = np.zeros(N(0.8))
    put(buf, creak(rng, 0.55, 90, 140, res=(500, 1400), noise=0.2) * np.hanning(N(0.55)) ** 0.3, 0.0, 0.5)
    s = ping([220, 590, 1130, 1810], [.7, .6, .4, .3], [.15, .12, .1, .06], 0.4)
    s += thump(110, 55, 0.4, 0.06) * 0.8 + nburst(rng, 0.4, 800, 5000, 0.006) * 0.6
    put(buf, s, 0.55, 1.0)
    return finish(buf, 0.8, peak=-2, fo=0.1)


def g_shovel(rng):
    buf = np.zeros(N(1.0)); t = tt(1.0)
    n1 = N(0.55); tp = np.arange(n1) / SR
    sc = crinkle(rng, 0.55, 700, 1500, 5000, grain=0.003) * np.interp(tp, [0, .1, .4, .55], [0, 1, .8, 0])
    sc += 0.4 * nz(n1, rng, 300, 1200) * np.interp(tp, [0, .1, .4, .55], [0, 1, .8, 0])
    put(buf, sc, 0.0, 0.7)
    put(buf, whoosh(rng, 0.25, [(200, 900, 0.1, 0.05, 1.0), (800, 2500, 0.12, 0.04, .5)]), 0.5, 0.35)
    put(buf, clatter(rng, 0.35, 22, 800, 4500, dens_amp=0.9), 0.68, 0.7)
    put(buf, thump(110, 60, 0.15, 0.05), 0.7, 0.4)
    return finish(buf, 1.0, peak=-2, fo=0.12)


def g_coal_pickup(rng):
    buf = np.zeros(N(0.6))
    put(buf, nz(N(0.3), rng, 300, 2000) * np.hanning(N(0.3)) ** 2, 0.0, 0.35)
    put(buf, clatter(rng, 0.4, 24, 700, 4000, bias=1.2), 0.1, 0.7)
    put(buf, thump(100, 50, 0.2, 0.06), 0.3, 0.5)
    return finish(buf, 0.6, peak=-2, fo=0.1)


def g_axe_swing(rng):
    x = whoosh(rng, 0.35, [(300, 900, .08, .045, .9), (800, 2500, .15, .05, 1.0), (2000, 5000, .2, .05, .5)])
    return finish(x, 0.35, peak=-3, fi=0.01, fo=0.08)


def g_axe_chop(rng):
    buf = np.zeros(N(0.5))
    s = thump(160, 70, 0.4, 0.07, 0.025) * 1.0
    s += ping([300, 520, 810], [.5, .35, .25], [.06, .05, .04], 0.4)
    s += nburst(rng, 0.4, 500, 3000, 0.015) * 0.9
    put(buf, s, 0.0, 1.0)
    for _ in range(5):
        put(buf, ping([rng.uniform(3000, 8000)], [1], [.003], 0.02), rng.uniform(0.01, 0.07), rng.uniform(.15, .35))
    put(buf, ping([2200], [.2], [.12], 0.3), 0.02, 0.4)
    return finish(buf, 0.5, peak=-2, fo=0.08)


def g_tree_crack(rng):
    d = 2.8; buf = np.zeros(N(d))
    for _ in range(26):
        tc = (rng.random() ** 0.6) * 1.35
        put(buf, ping([rng.uniform(1000, 5000)], [1], [.005], 0.03) + nburst(rng, 0.03, 800, 5000, 0.006),
            tc, 0.08 + 0.3 * tc / 1.35 * rng.random())
    put(buf, creak(rng, 1.4, 60, 110, res=(250, 900)) * np.hanning(N(1.4)) ** 2, 0.0, 0.5)
    big = nburst(rng, 0.5, 300, 6000, 0.05, 0.001) * 1.0 + ping([400, 900, 1700], [.5, .4, .3], [.12, .08, .05], 0.5)
    put(buf, big, 1.4, 1.0)
    sw = nz(N(0.9), rng, 600, 3500) * np.sin(np.linspace(0, np.pi, N(0.9))) ** 2
    put(buf, sw, 1.5, 0.35)
    put(buf, thump(80, 32, 0.8, 0.25, 0.06) * 1.2 + nburst(rng, 0.8, 40, 250, 0.2, 0.004) * 0.6, 2.0, 1.0)
    put(buf, clatter(rng, 0.7, 20, 800, 3500, bias=1.0, dens_amp=0.5), 2.05, 0.5)
    return finish(buf, d, peak=-1.5, fo=0.25)


def g_step(rng, kind, i):
    n = N(0.25); t = np.arange(n) / SR
    if kind == "grass":
        lo = rng.uniform(1000, 1500); hi = rng.uniform(4000, 5500)
        x = nz(n, rng, lo, hi) * dec(n, rng.uniform(.05, .08), 0.018)
        x += 0.6 * thump(rng.uniform(90, 110), 55, 0.25, 0.05, 0.02)
        x += crinkle(rng, 0.25, 250, 3000, 8000) * dec(n, 0.1, 0.01) * 0.25
    elif kind == "wood":
        f = rng.uniform(130, 175)
        x = ping([f, f * 1.9, f * 2.9], [1, .5, .3], [.07, .05, .035], 0.25)
        x += nburst(rng, 0.25, 800, 2500, 0.012) * 0.45 + thump(90, 55, 0.25, 0.05) * 0.5
    elif kind == "metal":
        j = rng.uniform(0.9, 1.15)
        x = nburst(rng, 0.25, 2000, 6000, 0.006) * 0.5
        x += ping([450 * j, 980 * j, 1630 * j, 2400 * j], [.6, .5, .35, .25], [.09, .07, .05, .035], 0.25)
        x += thump(110, 65, 0.25, 0.05) * 0.7
    else:
        x = crinkle(rng, 0.25, 1500, 1500, 6000, grain=0.0015) * dec(n, 0.09, 0.006)
        x += 0.5 * thump(95, 55, 0.25, 0.05) + nburst(rng, 0.25, 300, 1500, 0.03) * 0.3
    return finish(x, 0.25, peak=-3, fi=0.002, fo=0.04)


def g_ladder(rng):
    x = ping([320, 700, 1450, 2350], [.5, .7, .5, .3], [.1, .1, .08, .05], 0.3)
    x += nburst(rng, 0.3, 1500, 6000, 0.006) * 0.6 + nburst(rng, 0.3, 400, 2000, 0.03) * 0.2
    return finish(x, 0.3, peak=-2.5, fo=0.06)


def g_land(rng):
    x = thump(100, 45, 0.3, 0.08, 0.04) + nburst(rng, 0.3, 80, 900, 0.05) * 0.6
    x += clatter(rng, 0.3, 8, 1000, 4000, dens_amp=0.3)
    return finish(x, 0.3, peak=-2.5, fo=0.06)


def g_branch(rng, i):
    n = N(0.4); buf = np.zeros(n)
    if i == 3:
        put(buf, creak(rng, 0.14, 300, 500, res=(900, 2200), noise=0.3) * np.hanning(N(0.14)) * 0.5, 0.0)
        t0 = 0.14
    else:
        t0 = 0.02
    s = nburst(rng, 0.1, 1500, 6000, 0.006) + 0.6 * nburst(rng, 0.1, 400, 1500, 0.02)
    s += ping([rng.uniform(1800, 2600)], [.4], [.015], 0.1)
    put(buf, s, t0, 1.0)
    if i == 2:
        put(buf, nburst(rng, 0.08, 1500, 5500, 0.005) + 0.5 * nburst(rng, 0.08, 400, 1500, 0.015), t0 + 0.09, 0.45)
    buf = lp(buf, 5000, 1)
    x = reverb(buf, 0.7, 0.4, 70 + i, 3500, tail=0.2)
    return finish(x, 0.4, peak=-3, fo=0.08)


def g_far_steps(rng):
    d = 3.5; buf = np.zeros(N(d))
    for tc in (0.15, 0.95, 1.8, 2.55, 3.1):
        s = thump(75, 40, 0.4, 0.09, 0.03) + 0.6 * lp(nburst(rng, 0.4, 300, 1500, 0.09, 0.015), 1500, 2)
        s += 0.3 * crinkle(rng, 0.4, 500, 400, 2500) * dec(N(0.4), 0.1, 0.01)
        put(buf, s, tc + rng.uniform(-.05, .05), rng.uniform(.8, 1.1))
    x = reverb(lp(buf, 2500, 2), 1.5, 0.5, 72, 2500, tail=0.4)
    return finish(x, d, peak=-5, fi=0.01, fo=0.3)


VOW = {"a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (270, 2290, 3010),
       "o": (570, 840, 2410), "u": (300, 870, 2240), "x": (500, 1500, 2500)}


def g_whisper(rng, i):
    d = 2.5; buf = np.zeros(N(d + 0.4)); t = 0.15
    vks = list(VOW)
    while t < 2.1:
        word_a = rng.uniform(.5, 1.0)
        for s in range(int(rng.integers(2, 5))):
            L = rng.uniform(.11, .22); n = N(L)
            v1, v2 = rng.choice(vks, 2)
            src = nz(n, rng, 200, 9000)
            y = np.zeros(n); w = np.linspace(0, 1, n)
            for (f1, g) in zip(VOW[v1], (1, .6, .3)):
                y += (1 - w) * g * bp(src, f1 * .88, f1 * 1.12, 2)
            for (f2, g) in zip(VOW[v2], (1, .6, .3)):
                y += w * g * bp(src, f2 * .88, f2 * 1.12, 2)
            y *= np.sin(np.pi * np.arange(n) / n) ** 2
            if rng.random() < .6:
                c = nz(N(.04), rng, 3500, 8000) * np.hanning(N(.04))
                y[:len(c)] += c * 0.8 * np.std(y) / (np.std(c) + 1e-9)
            put(buf, y / (np.std(y) + 1e-9), t, word_a * rng.uniform(.6, 1))
            t += L + 0.02
        t += rng.uniform(.12, .3)
    x = reverb(lp(buf, 8000, 2), 1.4, 0.35, 80 + i, 3500, pre=0.02, tail=0.3)
    return finish(x, d, peak=-6, fi=0.05, fo=0.2)


def g_heartbeat(rng):
    buf = np.zeros(N(1.0))
    put(buf, thump(60, 38, 0.4, 0.1, 0.03), 0.0, 1.0)
    put(buf, thump(70, 45, 0.35, 0.09, 0.03), 0.28, 0.7)
    put(buf, nburst(rng, 0.1, 60, 250, 0.03), 0.0, 0.3)
    x = lp(buf, 220, 2)
    x = reverb(x, 0.3, 0.2, 90, 600, tail=0.1)
    return finish(x, 1.0, peak=-2, fo=0.08)


def g_breath(rng):
    d = 3.0; n = N(d); t = np.arange(n) / SR
    def phase(t0, t1, up):
        e = np.zeros(n); m = (t >= t0) & (t < t1); u = (t[m] - t0) / (t1 - t0)
        e[m] = (u ** 1.5 * (1 - u) ** 0.6) * 3 if up else (u ** 0.5 * (1 - u) ** 1.4) * 3
        return e
    env = phase(0.0, 1.25, True) + 0.9 * phase(1.4, 2.95, False)
    env *= 1 - 0.45 * np.exp(-0.5 * ((t - 0.75) / 0.05) ** 2)  # hitch in the inhale
    trem = 1 - 0.35 * (0.5 + 0.5 * np.sin(TAU * 9 * t + 2 * nz(n, rng, 1, 6) * 0.3))
    src = nz(n, rng, 300, 7000)
    x = (bp(src, 500, 2500) * 0.8 + bp(src, 800, 1200) * 0.5 + bp(src, 1700, 2100) * 0.3) * env * trem
    x += 0.4 * nz(n, rng, 80, 400) * env
    return finish(x, d, peak=-3, fi=0.05, fo=0.1)


def g_wake_muffled(rng):
    d = 7.0; n = N(d); t = np.arange(n) / SR
    rum = sp_noise(n, rng, 20, 120, slope=2, order=3) * 1.0
    hb = np.zeros(n)
    for tc in np.arange(0.4, d - 0.5, 1.05):
        put(hb, lp(thump(60, 38, 0.4, 0.1, 0.03), 120, 2), tc, 0.6)
    water = sp_noise(n, rng, 60, 3000, slope=1.5)
    e = np.clip(t / d, 0, 1)
    wat = np.where(True, 1, 1) * (loopf(lambda z: lp(z, 300, 2), water) * (1 - e) + loopf(lambda z: lp(z, 1500, 2), water) * e)
    ring = (np.sin(TAU * 4200 * t) + 0.35 * np.sin(TAU * 5650 * t + 1)) * 0.08 * np.exp(-t / 2.5)
    ring *= 1 + 0.15 * np.sin(TAU * 0.7 * t)
    ch = np.zeros(n)
    for tc in np.arange(1.0, d - 0.6, 0.95):
        put(ch, lp(chuff_sig(rng), 320, 2), tc, 0.45 * np.interp(tc, [0, d], [0.6, 1.0]))
    x = rum * 0.5 + hb + wat * 0.35 + ring + ch
    x *= np.interp(t, [0, 0.4, d - 1.2, d], [0, 1, 1, 0.0])
    return finish(x, d, peak=-2, fi=0.3, fo=1.0)


def g_sting(rng):
    d = 3.0; n = N(d); t = np.arange(n) / SR
    env = np.interp(t, [0, 1.2, 3.0], [0, 1, 0]) ** 1.3
    low = sum(np.sin(TAU * f * t + k) * a for k, (f, a) in enumerate(((55, 1), (82.4, .5), (77.8, .5))))
    low = lp(low + 0.4 * saw_ph(55 * t, 6), 300, 2) * env
    henv = np.interp(t, [0, 0.7, 1.4, 3.0], [0, 0.4, 1, 0]) ** 2
    hi = sum(np.sin(TAU * f * t) for f in (1396.9, 1480.0, 1568.0 * 1.01, 2349.3, 2489.0))
    hi = hi * henv * 0.07 * (1 + 0.2 * np.sin(TAU * 5.5 * t))
    sc = nz(n, rng, 2500, 7000) * henv * 0.03
    x = reverb(low * 1.2 + hi + sc, 2.0, 0.5, 91, 3500, tail=0.0)
    return finish(x, d, peak=-3, fi=0.1, fo=0.4)


def g_hit(rng):
    d = 0.8; buf = np.zeros(N(d))
    s = lp(nburst(rng, 0.6, 100, 2500, 0.03, 0.0008), 1500, 2) * 1.0
    th = thump(95, 38, 0.6, 0.14, 0.04)
    put(buf, s + 1.2 * th, 0.0, 1.0)
    x = np.tanh(buf * 3.0) * 0.8
    x[N(0.08):] = buf[N(0.08):]
    t = tt(d)
    x += np.sin(TAU * 3200 * t) * 0.04 * np.exp(-t / 0.2) + 0.06 * whoosh(rng, d, [(150, 700, 0.1, 0.06, 1.0)])
    return finish(x, d, peak=-2, fo=0.15)


def g_paper(rng):
    d = 0.5; n = N(d); t = np.arange(n) / SR
    env = np.interp(t, [0, .05, .2, .35, .5], [0, 1, .6, .9, 0])
    x = crinkle(rng, d, 160, 2000, 8000) * env
    x += 0.5 * crinkle(rng, d, 60, 800, 3000, grain=0.004) * env
    return finish(x, d, peak=-4, fi=0.01, fo=0.1)


def g_pickup(rng):
    buf = np.zeros(N(0.4))
    put(buf, crinkle(rng, 0.2, 200, 1000, 5000) * np.hanning(N(0.2)), 0.0, 0.8)
    put(buf, ping([1800, 2900, 4300], [.5, .4, .2], [.08, .05, .03], 0.25), 0.1, 0.35)
    put(buf, thump(130, 80, 0.1, 0.03), 0.08, 0.2)
    return finish(buf, 0.4, peak=-3, fo=0.08)


def g_heal(rng):
    buf = np.zeros(N(1.0)); n = N(0.55)
    put(buf, crinkle(rng, 0.55, 180, 1500, 6000) * np.sin(np.linspace(0, np.pi, n)) ** 1.5, 0.0, 0.6)
    tl = tt(0.6)
    tone = sum(np.sin(TAU * f * tl) + 0.2 * np.sin(TAU * 2 * f * tl) for f in (523.25, 659.25, 783.99))
    tone *= np.sin(np.pi * tl / 0.6) ** 2 * 0.12
    put(buf, tone, 0.25, 1.0)
    x = reverb(buf, 0.8, 0.25, 95, 4000, tail=0.0)
    return finish(x, 0.8, peak=-3, fo=0.2)


def g_creak(rng, i):
    if i == 1:
        x = creak(rng, 1.5, 55, 70, fmid=100, res=(350, 1100), noise=0.2)
    else:
        x = creak(rng, 1.5, 140, 120, fmid=210, res=(700, 2200), noise=0.12)
        x += 0.15 * ping([880, 1330], [1, .5], [.3, .2], 1.5)
    return finish(x, 1.5, peak=-3, fi=0.05, fo=0.2)


def g_bell(rng):
    d = 4.5; t = tt(d); fp = 330.0
    rat = [0.5, 1, 1.183, 1.506, 2, 2.514, 2.662, 3.011, 4.166]
    amp = [.6, 1, .7, .5, .5, .3, .25, .2, .12]
    x = np.zeros(len(t))
    for r, a in zip(rat, amp):
        tau = 1.9 / (r ** 0.55 if r > .5 else 0.9)
        x += a * np.exp(-t / tau) * (np.sin(TAU * fp * r * t) + 0.5 * np.sin(TAU * (fp * r + 0.8) * t + 1))
    x *= (1 - np.exp(-t / 0.002))
    x += 0.5 * nburst(rng, d, 2000, 5000, 0.01) + 0.3 * nburst(rng, d, 400, 1500, 0.04)
    x = reverb(x, 1.5, 0.25, 100, 5000, tail=0.0)
    return finish(x, d, peak=-2, fo=0.5)


def g_ui_hover(rng):
    d = 0.25; n = N(d); t = np.arange(n) / SR
    x = whoosh(rng, d, [(1500, 6000, 0.12, 0.05, 1.0)]) + 0.5 * crinkle(rng, d, 120, 2500, 7000) * np.exp(-0.5 * ((t - .12) / .05) ** 2)
    return finish(x, d, peak=-8, fi=0.03, fo=0.08)


def g_ui_click(rng):
    d = 0.3; n = N(d)
    x = lp(thump(180, 90, d, 0.02, 0.01), 400, 2) * 0.8
    x += nburst(rng, d, 1500, 6000, 0.012, 0.001) * 0.6
    x += crinkle(rng, d, 400, 2500, 7500) * dec(n, 0.07, 0.003) * 0.5
    return finish(x, d, peak=-4, fi=0.002, fo=0.08)


def g_crash(rng):
    d = 2.2; buf = np.zeros(N(d))
    put(buf, nz(N(1.0), rng, 60, 6000) * dec(N(1.0), 0.12, 0.001), 0.0, 1.0)
    put(buf, thump(70, 28, 1.5, 0.4, 0.08), 0.0, 1.4)
    for _ in range(14):
        f0 = rng.uniform(150, 600)
        fr = [f0 * r for r in (1, rng.uniform(1.4, 1.7), rng.uniform(2.1, 2.9), rng.uniform(3.4, 4.6))]
        put(buf, ping(fr, [.6, .5, .4, .3], [rng.uniform(.3, 1.2), .5, .3, .2], 1.4),
            rng.uniform(0, 0.9) ** 1.3, rng.uniform(.2, .45))
    put(buf, clatter(rng, 1.4, 60, 600, 5000, tau_hi=0.06, dens_amp=0.7), 0.15, 0.6)
    put(buf, creak(rng, 1.0, 400, 200, fmid=300, res=(800, 2500), noise=0.3) * np.hanning(N(1.0)), 0.35, 0.3)
    x = np.tanh(buf * 1.2)
    x = reverb(x, 1.5, 0.3, 110, 4000, tail=0.0)
    return finish(x, d, peak=-1.5, fo=0.35)


def g_engine_start(rng):
    d = 2.5; n = N(d); t = np.arange(n) / SR; buf = np.zeros(n)
    jet = nz(n, rng, 1500, 9000) * np.exp(-t / 0.7) * (1 - np.exp(-t / 0.03))
    body = nz(n, rng, 200, 1200) * np.exp(-t / 0.5) * (1 - np.exp(-t / 0.02))
    buf += jet * 0.6 + body * 0.8
    put(buf, ping([180, 430, 910, 1700], [.7, .6, .4, .3], [.2, .15, .1, .06], 0.5) + thump(100, 50, 0.5, .08) + nburst(rng, 0.5, 800, 6000, 0.01), 0.0, 0.9)
    put(buf, ping([260, 700, 1300], [.6, .4, .3], [.12, .08, .05], 0.3) + thump(90, 50, 0.3, .06), 0.35, 0.5)
    for tc, g in ((1.0, .55), (1.5, .7), (1.95, .85), (2.3, .95)):
        put(buf, chuff_sig(rng, g), tc, 1.0)
    return finish(buf, d, peak=-1.5, fo=0.25)


# ----------------------------------------------------------------- registry
def _rep(fn, *a): return lambda rng: fn(rng, *a)

TASKS = []  # (filename, fn, expected_duration_s, is_loop)

def add(name, fn, dur, loop=False): TASKS.append((name, fn, dur, loop))

add("amb_wind.ogg", g_amb_wind, 30, True)
add("amb_forest.ogg", g_amb_forest, 40, True)
add("amb_rain.ogg", g_amb_rain, 30, True)
add("train_rumble.ogg", g_train_rumble, 10, True)
add("steam_hiss.ogg", g_steam_hiss, 6, True)
add("furnace_fire.ogg", g_furnace_fire, 10, True)
add("music_menu.ogg", g_music_menu, 80, True)
add("music_travel.ogg", g_music_travel, 90, True)
add("music_stop.ogg", g_music_stop, 60, True)
add("music_danger.ogg", g_music_danger, 40, True)
add("music_ending.ogg", g_music_ending, 60, False)
for nm, fn, d in (("chuff", g_chuff, .35), ("whistle", g_whistle, 2.4), ("whistle_distant", g_whistle_distant, 5.0),
                  ("rail_clack", g_rail_clack, .5), ("brake", g_brake, 2.0), ("lever", g_lever, .4),
                  ("furnace_door", g_furnace_door, .8), ("shovel", g_shovel, 1.0), ("coal_pickup", g_coal_pickup, .6),
                  ("axe_swing", g_axe_swing, .35), ("axe_chop", g_axe_chop, .5), ("tree_crack", g_tree_crack, 2.8)):
    add(nm + ".wav", fn, d)
for kind, cnt in (("grass", 4), ("wood", 4), ("metal", 3), ("gravel", 3)):
    for i in range(1, cnt + 1):
        add(f"step_{kind}_{i}.wav", _rep(g_step, kind, i), .25)
add("ladder.wav", g_ladder, .3)
add("land.wav", g_land, .3)
for i in (1, 2, 3): add(f"branch_snap_{i}.wav", _rep(g_branch, i), .4)
add("far_steps.wav", g_far_steps, 3.5)
for i in (1, 2, 3): add(f"whisper_{i}.wav", _rep(g_whisper, i), 2.5)
for nm, fn, d in (("heartbeat", g_heartbeat, 1.0), ("breath", g_breath, 3.0), ("wake_muffled", g_wake_muffled, 7.0),
                  ("sting", g_sting, 3.0), ("hit", g_hit, .8), ("paper", g_paper, .5), ("pickup", g_pickup, .4),
                  ("heal", g_heal, .8)):
    add(nm + ".wav", fn, d)
for i in (1, 2): add(f"creak_{i}.wav", _rep(g_creak, i), 1.5)
for nm, fn, d in (("bell", g_bell, 4.5), ("ui_hover", g_ui_hover, .25), ("ui_click", g_ui_click, .3),
                  ("crash", g_crash, 2.2), ("engine_start", g_engine_start, 2.5)):
    add(nm + ".wav", fn, d)


def run_task(idx):
    name, fn, dur, loop = TASKS[idx]
    t0 = time.time()
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    x = fn(rng)
    assert np.isfinite(x).all(), name
    path = os.path.join(OUT, name)
    if name.endswith(".wav"):
        wavfile.write(path, SR, np.round(np.clip(x, -1, 1) * 32767).astype(np.int16))
    else:
        with tempfile.TemporaryDirectory() as td:
            tmp = os.path.join(td, "x.wav")
            wavfile.write(tmp, SR, x.astype(np.float32))
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis",
                            "-q:a", "4", path], check=True)
    return name, time.time() - t0


# ------------------------------------------------------------------ verify
def read_any(path):
    p = json.loads(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "stream=channels,sample_rate:format=duration",
         "-of", "json", path]))
    ch = int(p["streams"][0]["channels"]); dur = float(p["format"]["duration"])
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-"])
    x = np.frombuffer(raw, np.float32).reshape(-1, ch).astype(float)
    return x, dur, ch


def verify():
    print(f"{'file':26s}{'dur(s)':>8s}{'exp':>7s}{'peak dB':>9s}{'rms dB':>8s}{'dc':>9s}{'loopΔ':>7s}  status")
    bad = 0; total = 0
    for name, _, exp, loop in TASKS:
        path = os.path.join(OUT, name); status = "ok"
        if not os.path.exists(path):
            print(f"{name:26s} MISSING"); bad += 1; continue
        total += os.path.getsize(path)
        x, dur, ch = read_any(path)
        pk = np.abs(x).max(); rms = np.sqrt(np.mean(x ** 2)); dc = abs(x.mean(axis=0)).max()
        pdb = 20 * np.log10(pk + 1e-12); rdb = 20 * np.log10(rms + 1e-12)
        ratio = 0.0
        if loop:
            d = np.sqrt(np.mean(np.diff(x, axis=0) ** 2)) + 1e-12
            ratio = np.abs(x[0] - x[-1]).max() / d
            if ratio > 10: status = "LOOP JUMP"
        if abs(dur - exp) > max(0.08, exp * 0.03) and not name.endswith(".ogg"): status = "DURATION"
        if name.endswith(".ogg") and abs(dur - exp) > 0.15: status = "DURATION"
        if pk > 0.99: status = "PEAK"
        if rdb < -60: status = "SILENT"
        if dc > 0.01: status = "DC"
        if status != "ok": bad += 1
        print(f"{name:26s}{dur:8.2f}{exp:7.2f}{pdb:9.1f}{rdb:8.1f}{dc:9.5f}{ratio:7.2f}  {status}")
    print(f"\n{len(TASKS)} files, total size {total/1e6:.2f} MB, problems: {bad}")
    return bad


def main():
    os.makedirs(OUT, exist_ok=True)
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    idxs = [i for i, t in enumerate(TASKS) if only is None or t[0] in only or t[0].split(".")[0] in only]
    # heaviest (music) first for better load balancing
    idxs.sort(key=lambda i: -TASKS[i][2])
    t0 = time.time()
    with Pool(2) as p:
        for name, dt in p.imap_unordered(run_task, idxs):
            print(f"  {name:26s}{dt:6.1f}s", flush=True)
    print(f"generated {len(idxs)} files in {time.time()-t0:.1f}s -> {OUT}")
    if "--no-verify" not in sys.argv and only is None:
        sys.exit(1 if verify() else 0)


if __name__ == "__main__":
    main()
