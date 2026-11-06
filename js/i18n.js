'use strict';
// Tiny i18n runtime. Messages are stored as {k, p, i} so they re-render in the current language.
(function () {
  const KEY = 'lastcan.lang';
  const L = window.LANGS;
  const I = { lang: 'en', listeners: [] };
  try { const s = localStorage.getItem(KEY); if (s && L[s]) I.lang = s; } catch (e) { /* storage blocked */ }
  document.documentElement.lang = I.lang;

  I.raw = k => { const t = L[I.lang] || L.en; return (k in t) ? t[k] : L.en[k]; };
  I.count = k => { const s = I.raw(k); return Array.isArray(s) ? s.length : 1; };
  const resolve = p => {
    if (!p) return p;
    const o = {};
    for (const n in p) o[n] = (p[n] && typeof p[n] === 'object' && p[n].k) ? I.tr(p[n]) : p[n];
    return o;
  };
  I.t = (k, p, idx) => {
    let s = I.raw(k);
    if (s === undefined) return k;
    if (Array.isArray(s)) s = s[(idx || 0) % s.length];
    p = resolve(p);
    if (p) s = s.replace(/\{(\w+)\}/g, (m, n) => (n in p) ? p[n] : m);
    return s;
  };
  I.tr = m => (typeof m === 'string' ? I.t(m) : I.t(m.k, m.p, m.i));
  I.msg = (k, p) => ({ k, p, i: Math.floor(Math.random() * 1000) });
  I.apply = () => {
    document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = I.t(el.dataset.i18n); });
    document.querySelectorAll('.langbtn').forEach(b => b.classList.toggle('active', b.dataset.lang === I.lang));
    document.title = I.t('title_name');
  };
  I.set = lang => {
    if (!L[lang]) return;
    I.lang = lang;
    try { localStorage.setItem(KEY, lang); } catch (e) { /* storage blocked */ }
    document.documentElement.lang = lang;
    I.apply();
    I.listeners.forEach(f => f(lang));
  };
  window.I18N = I;
  document.addEventListener('DOMContentLoaded', I.apply);
  document.addEventListener('click', e => {
    const b = e.target.closest && e.target.closest('.langbtn');
    if (b) { e.stopPropagation(); I.set(b.dataset.lang); }
  }, true);
})();
