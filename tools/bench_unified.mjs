// Unified cross-engine perf benchmark (Godot / Cocos use the same script & scenario).
// Scenario: 844x390, 20 enemies alive, hero attacks continuously (real touch held), god on.
// Measured per frame INSIDE the app's own requestAnimationFrame callback:
//   busy = ms the main thread spends inside the rAF callback (scripts + render submit issued there)
//   gap  = ms between consecutive rAF timestamps (actual frame interval)
// Rates: CPU throttling 1x/4x/6x (CDP Emulation.setCPUThrottlingRate), 10 s each, p50/p95.
// Usage:
//   node tools/bench_unified.mjs --url=http://127.0.0.1:8941/index.html --rig=sprite --out=tools/shots/bench-sprite.json
//   node tools/bench_unified.mjs --url=http://127.0.0.1:8941/index.html --rig=hero   --out=tools/shots/bench-hero.json
//   (Cocos: swap --url/--rig and keep the same bridge surface: start/god/clearEnemies/spawn/full/layout.)
import { chromium } from 'playwright';
import fs from 'node:fs';

const arg = (k, d) => { const a = process.argv.find(x => x.startsWith(`--${k}=`)); return a === undefined ? d : a.slice(k.length + 3); };
const URL_BASE = arg('url', 'http://127.0.0.1:8941/index.html');
const RIG = arg('rig', 'sprite');
const SECONDS = +arg('seconds', 10);
const RATES = arg('rates', '1,4,6').split(',').map(Number);
const OUT = arg('out', 'tools/shots/bench-unified.json');
const DIAG = process.argv.includes('--diag');
const sleep = ms => new Promise(r => setTimeout(r, ms));

function stats(a) {
  if (!a.length) return { n: 0 };
  const s = [...a].sort((x, y) => x - y);
  const q = k => +s[Math.min(s.length - 1, Math.floor(s.length * k))].toFixed(2);
  return { n: a.length, p50: q(0.5), p95: q(0.95), avg: +(a.reduce((x, y) => x + y, 0) / a.length).toFixed(2) };
}

const browser = await chromium.launch({ headless: true, channel: 'chrome',
  args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
const page = await ctx.newPage();
const errors = [];
page.on('console', m => { if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(m.text()); });
page.on('pageerror', e => errors.push(String(e.message)));
await page.addInitScript(() => {
  const raf = window.requestAnimationFrame.bind(window);
  const b = window.__bench = { busy: [], gap: [], on: false };
  let last = 0;
  window.requestAnimationFrame = cb => raf(ts => {
    const t0 = performance.now();
    try { cb(ts); } finally {
      const t1 = performance.now();
      if (b.on) {
        b.busy.push(t1 - t0);
        if (last > 0) b.gap.push(ts - last);
      }
      last = ts;
    }
  });
});
const cdp = await ctx.newCDPSession(page);
const t0 = Date.now();
await page.goto(`${URL_BASE}?debug=1&rig=${RIG}`);
await page.waitForFunction(() => window.__AI_BRIDGE__ && window.__AI_BRIDGE__.full() && window.__AI_BRIDGE__.full().screen === 'home', null, { timeout: 40000 });
const loadMs = Date.now() - t0;
await page.evaluate(() => window.__AI_BRIDGE__.start());
await page.waitForFunction(() => { const f = window.__AI_BRIDGE__.full(); return f && f.screen === 'battle' && f.layout && f.layout.attack; }, null, { timeout: 20000 });
await page.evaluate(() => window.__AI_BRIDGE__.god(true));

// Keep exactly ~20 enemies alive for the whole run (identical for every engine/rate).
await page.evaluate(() => {
  window.__keep = setInterval(() => {
    const f = window.__AI_BRIDGE__.full();
    const n = f && f.game && f.game.enemies ? f.game.enemies.length : 0;
    if (n < 20) window.__AI_BRIDGE__.spawn('imp', Math.min(4, 20 - n));
  }, 800);
});
const reset = () => page.evaluate(() => {
  const b = window.__AI_BRIDGE__;
  b.clearEnemies(); b.spawn('imp', 14); b.spawn('lantern', 4); b.spawn('brute', 2);
});

// Real touch held on the attack button: auto-combo for the whole run.
const full = await page.evaluate(() => window.__AI_BRIDGE__.full());
const [ax, ay] = await page.evaluate(([x, y]) => window.__AI_BRIDGE__.toCss(x, y), [full.layout.attack[0], full.layout.attack[1]]);
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: Math.round(ax), y: Math.round(ay), id: 1, radiusX: 6, radiusY: 6 }] });

const out = { engine: arg('engine', 'godot'), rig: RIG, url: URL_BASE, viewport: [844, 390], loadMs, rates: {} };
for (const rate of RATES) {
  await cdp.send('Emulation.setCPUThrottlingRate', { rate });
  await reset();
  await sleep(1500);
  const alive0 = await page.evaluate(() => window.__AI_BRIDGE__.full().game.enemies.length);
  await page.evaluate(() => { const b = window.__bench; b.busy.length = 0; b.gap.length = 0; b.on = true; });
  await sleep(SECONDS * 1000);
  const d = await page.evaluate(() => { const b = window.__bench; b.on = false; return { busy: b.busy.slice(), gap: b.gap.slice() }; });
  const alive1 = await page.evaluate(() => window.__AI_BRIDGE__.full().game.enemies.length);
  const busy = stats(d.busy), gap = stats(d.gap);
  out.rates[`${rate}x`] = { busy, gap, fpsP50: gap.p50 ? +(1000 / gap.p50).toFixed(1) : null,
    fpsP95: gap.p95 ? +(1000 / gap.p95).toFixed(1) : null, alive: Math.round((alive0 + alive1) / 2) };
  console.log(`[bench] ${RIG} ${rate}x busy p50=${busy.p50} p95=${busy.p95} | gap p50=${gap.p50} p95=${gap.p95} fps(${out.rates[`${rate}x`].fpsP50}) alive=${out.rates[`${rate}x`].alive} n=${busy.n}`);
  if (DIAG) {
    const samples = [];
    for (let i = 0; i < 12; i++) {
      samples.push(await page.evaluate(() => { const f = window.__AI_BRIDGE__.full(); return { sim: f.rigSimUs, draw: f.rigDrawUs, parts: f.rigParts, eval: f.rigEvalUs, world: f.rigWorldUs, spring: f.rigSpringUs }; }));
      await sleep(200);
    }
    const mean = k => Math.round(samples.reduce((s, x) => s + (x[k] || 0), 0) / samples.length);
    out.diag = { simUs: mean('sim'), drawUs: mean('draw'), parts: mean('parts'), evalUs: mean('eval'), worldUs: mean('world'), springUs: mean('spring') };
    console.log('[bench] diag', JSON.stringify(out.diag));
  }
}
await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
await page.evaluate(() => { clearInterval(window.__keep); window.__AI_BRIDGE__.clearEnemies(); });
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [{ x: Math.round(ax), y: Math.round(ay), id: 1 }] });
out.errors = errors;
fs.mkdirSync(OUT.split('/').slice(0, -1).join('/') || '.', { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
await browser.close();
console.log('[bench] errors', errors.length, errors.slice(0, 3));
