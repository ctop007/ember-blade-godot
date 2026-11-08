// E2E acceptance (DESIGN §10): real CDP multi-touch, full run, per-skill screenshots, layout, perf.
// Usage: npm run serve (other terminal)  then  node tools/e2e.mjs [--only=full|small|perf] [--headed]
import { chromium } from 'playwright';
import fs from 'node:fs';

const URL = 'http://localhost:8941/index.html?debug';
const OUT = 'tools/shots';
const args = process.argv.slice(2);
const only = (args.find(a => a.startsWith('--only=')) || '').slice(7);
const headed = args.includes('--headed');
fs.mkdirSync(OUT, { recursive: true });
const report = { errors: [], runs: {} };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const log = (...a) => console.log('[e2e]', ...a);

async function open(vw, vh, tag) {
  const browser = await chromium.launch({ headless: !headed, channel: 'chrome',
    args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
  const ctx = await browser.newContext({ viewport: { width: vw, height: vh }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  page.on('console', m => {
    const t = m.text();
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(t)) report.errors.push(`[${tag}] ${t}`);
  });
  page.on('pageerror', e => report.errors.push(`[${tag}] pageerror ${e.message}`));
  const cdp = await ctx.newCDPSession(page);
  const t0 = Date.now();
  await page.goto(URL);
  const T = new Touch(page, cdp);
  await T.waitFor(s => s && s.screen === 'home' && s.startBtn, 60000, 'home');
  const loadMs = Date.now() - t0;
  return { browser, page, cdp, T, loadMs };
}

class Touch {
  constructor(page, cdp) { this.page = page; this.cdp = cdp; this.pts = new Map(); this.nextId = 1; }
  async st() { return this.page.evaluate(() => window.__jr && window.__jr.state); }
  async css(x, y) { return this.page.evaluate(([x, y]) => window.__AI_BRIDGE__.toCss(x, y), [x, y]); }
  // CDP semantics (as in Puppeteer): each event lists only the finger(s) that changed.
  pt(id) { const p = this.pts.get(id); return [{ x: p[0], y: p[1], id, radiusX: 8, radiusY: 8, force: 1 }]; }
  async down(x, y) { // logical coords
    const [cx, cy] = await this.css(x, y);
    let id = 0; while (this.pts.has(id)) id++;
    this.pts.set(id, [cx, cy]);
    await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: this.pt(id) });
    return id;
  }
  async move(id, x, y) {
    const [cx, cy] = await this.css(x, y);
    this.pts.set(id, [cx, cy]);
    await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: this.pt(id) });
  }
  async up(id) {
    if (!this.pts.has(id)) return;
    const pts = this.pt(id); this.pts.delete(id);
    await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: pts });
  }
  async tap(x, y, hold = 70) { const id = await this.down(x, y); await sleep(hold); await this.up(id); }
  async btn(name, hold = 70) { const s = await this.st(); const b = s.layout[name]; await this.tap(b[0], b[1], hold); }
  async waitFor(pred, ms, what) {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      const s = await this.st().catch(() => null);
      if (pred(s)) return s;
      await sleep(100);
    }
    throw new Error('timeout waiting for ' + what);
  }
}
// --- joystick held by one finger for the whole run; steer by moving it
class Stick {
  constructor(T) { this.T = T; this.id = null; this.c = null; }
  async hold(s) {
    const j = s.layout.joy; this.c = [j[0], j[1]]; this.r = j[2];
    this.id = await this.T.down(this.c[0], this.c[1]);
  }
  async dir(dx, dy) {
    const l = Math.hypot(dx, dy) || 1;
    const k = l < 1 ? 0 : 1;
    await this.T.move(this.id, this.c[0] + dx / l * this.r * 0.9 * k, this.c[1] + dy / l * this.r * 0.9 * k);
  }
  async release() { if (this.id !== null) await this.T.up(this.id); this.id = null; }
}

function nearest(g) {
  let best = null, bd = 1e9;
  for (const e of g.enemies) { const d = Math.hypot(e.x - g.px, (e.y - g.py) * 2); if (d < bd) { bd = d; best = e; } }
  return [best, bd];
}
const shot = (page, name) => page.screenshot({ path: `${OUT}/${name}.png` });

async function steerToward(stick, g, e, keep = 90) {
  const dx = e.x - g.px, dy = (e.y - g.py);
  if (Math.abs(dx) < keep && Math.abs(dy) < 24) { await stick.dir(Math.sign(dx) * 0.001, 0); return true; }
  const tx = Math.abs(dx) < keep ? 0 : dx - Math.sign(dx) * keep * 0.8;
  await stick.dir(tx, dy * 2);
  return false;
}

// Separate per-mechanic checks, each with a screenshot and an assertion on core state.
async function mechanics(T, page, tag) {
  const res = {};
  let s = await T.st();
  const stick = new Stick(T);
  await stick.hold(s);
  // joystick move (multitouch: finger stays down for the following taps)
  const x0 = s.game.px;
  await stick.dir(1, 0); await sleep(600);
  s = await T.st(); res.joystick = s.game.px - x0 > 60;
  await page.evaluate(() => { window.__AI_BRIDGE__.god(true); window.__AI_BRIDGE__.spawn('imp', 4); });
  await sleep(300);
  s = await T.st();
  for (let i = 0; i < 40; i++) { s = await T.st(); const [e] = nearest(s.game); if (!e || await steerToward(stick, s.game, e)) break; await sleep(80); }
  // 3-hit combo while the stick finger is still down
  let comboSeen = 0;
  for (let i = 0; i < 3; i++) { await T.btn('attack', 60); await sleep(170); s = await T.st(); comboSeen = Math.max(comboSeen, s.game.combo); if (i === 2) await shot(page, `${tag}-combo3`); }
  res.combo3 = comboSeen >= 2;
  await sleep(500);
  // charged thrust: hold attack >= 0.35s
  const L = s.layout.attack; const hid = await T.down(L[0], L[1]); await sleep(520);
  await shot(page, `${tag}-charge`); const tx0 = (await T.st()).game.px; await T.up(hid); await sleep(90);
  await shot(page, `${tag}-thrust`); await sleep(250);
  s = await T.st(); res.thrust = Math.abs(s.game.px - tx0) > 120;
  await sleep(500);
  // dodge
  await T.waitFor(x => ['idle', 'run'].includes(x.game.pstate), 3000, 'idle before dodge');
  const dx0 = (await T.st()).game.px; await T.btn('dodge'); await sleep(110); await shot(page, `${tag}-dodge`); await sleep(300);
  s = await T.st(); res.dodge = Math.abs(s.game.px - dx0) > 80;
  await sleep(500);
  // jump + air attack slam
  await T.btn('jump'); await sleep(180); s = await T.st(); res.jump = s.game.pstate === 'jump';
  await T.btn('attack'); const seen = [];
  for (let i = 0; i < 8; i++) { await sleep(40); seen.push((await T.st()).game.pstate); }
  res.slam = seen.includes('slam') || seen.includes('slam_end'); res.slamStates = [...new Set(seen)].join('>');
  await sleep(260); await shot(page, `${tag}-slam`); await sleep(400);
  // walk toward mid-arena so the camera frames skills fully
  await stick.dir(1, 0); await sleep(1100); await stick.dir(0, 0);
  // skills via real button taps (mp / cd checked)
  for (const [btn, name, at] of [['skill1', 'crescent', 380], ['skill2', 'skyfall', 560], ['skill3', 'meteorSpear', 260]]) {
    await T.waitFor(x => x.game.mp >= 30 && !(x.game.cds[name] > 0), 15000, name + ' ready');
    await page.evaluate(() => window.__AI_BRIDGE__.spawn('imp', 3));
    s = await T.st(); const mp0 = s.game.mp;
    await T.btn(btn); await sleep(at); await shot(page, `${tag}-${name}`);
    s = await T.st(); res[name] = s.game.mp < mp0 || s.game.cds[name] > 0;
    await sleep(900);
  }
  // ultimate: fill rage by fighting, else wait
  res.rageNatural = false;
  for (let i = 0; i < 400; i++) {
    s = await T.st(); if (s.game.rage >= 100) { res.rageNatural = true; break; }
    const [e] = nearest(s.game);
    if (!e) await page.evaluate(() => window.__AI_BRIDGE__.spawn('imp', 4));
    else if (await steerToward(stick, s.game, e)) await T.btn('attack', 50);
    await sleep(70);
  }
  await stick.dir(0, 0);
  await page.evaluate(() => window.__AI_BRIDGE__.spawn('imp', 5)); await sleep(300);
  await T.btn('ult'); await sleep(450); await shot(page, `${tag}-ult-cutin`);
  await sleep(900); await shot(page, `${tag}-ult-meteors`);
  s = await T.st(); res.ult = s.game.rage < 50;
  await sleep(1500);
  await stick.release();
  await page.evaluate(() => window.__AI_BRIDGE__.god(false));
  return res;
}
// Full run from home tap → waves → drafts → boss → result, steering only with touch.
async function fullRun(T, page, tag, budgetMs = 420000) {
  const r = { drafts: 0, draftBlocked: [], bossCard: false, godUsed: false, result: null, fpsMin: 999, fpsSum: 0, fpsN: 0, particlesMax: 0 };
  let s = await T.st();
  await shot(page, `${tag}-home`);
  await T.tap(s.startBtn[0], s.startBtn[1]);
  s = await T.waitFor(x => x && x.screen === 'battle' && x.layout, 10000, 'battle');
  await sleep(400);
  await shot(page, `${tag}-battle-start`);
  const stick = new Stick(T); await stick.hold(s);
  const t0 = Date.now(); let lastWave = 0; let atkT = 0;
  while (Date.now() - t0 < budgetMs) {
    s = await T.st();
    if (!s) { await sleep(100); continue; }
    if (s.screen === 'result') break;
    const g = s.game;
    if (g) {
      if (s.fps > 1) { r.fpsMin = Math.min(r.fpsMin, s.fps); r.fpsSum += s.fps; r.fpsN++; }
      r.particlesMax = Math.max(r.particlesMax, s.particles);
      if (g.wave !== lastWave) { lastWave = g.wave; log(tag, 'wave', g.wave, 'hp', g.hp); await shot(page, `${tag}-wave${g.wave}`); }
      if (!r.godUsed && g.hp < g.maxHp * 0.2 && g.result === '') { r.godUsed = true; log(tag, 'low hp → god'); await page.evaluate(() => window.__AI_BRIDGE__.god(true)); }
    }
    if (s.cards) {
      // draft: tap during the animation must be ignored
      if (!s.cardsReady) {
        const c = s.cards[0]; await T.tap(c[0], c[1]); await sleep(250);
        const s2 = await T.st(); r.draftBlocked.push(!!s2.cards);
        if (r.drafts === 0) await shot(page, `${tag}-draft-anim`);
        await T.waitFor(x => !x.cards || x.cardsReady, 8000, 'cards ready');
      }
      s = await T.st();
      if (s.cards) {
        await shot(page, `${tag}-draft${r.drafts + 1}`);
        const c = s.cards[r.drafts % 3]; await T.tap(c[0], c[1]); r.drafts++;
        await T.waitFor(x => !x.cards, 3000, 'draft closed'); await sleep(200);
        // controls drop all fingers while the modal is up; lift and re-press the stick like a player would
        await stick.release(); await stick.hold(await T.st());
      }
      continue;
    }
    if (!g) { await sleep(100); continue; }
    if (g.phase === 'boss_intro' && !r.bossCard) { r.bossCard = true; await sleep(350); await shot(page, `${tag}-boss-card`); continue; }
    const [e, d] = nearest(g);
    if (g.phase === 'advance' || !e) { await stick.dir(1, (580 - g.py) / 200); await sleep(80); continue; }
    const close = await steerToward(stick, g, e);
    // dodge telegraphs from boss/brute when close
    const danger = g.enemies.find(x => ['windup', 'charging', 'leap'].includes(x.state) && Math.abs(x.x - g.px) < 200);
    if (danger && !(g.cds.dodge > 0)) { await T.btn('dodge', 40); }
    else if (g.rage >= 100 && g.enemies.length >= 3) { await T.btn('ult'); await sleep(200); }
    else if (close) {
      if (g.mp >= 30 && !(g.cds.skyfall > 0) && g.enemies.length >= 3) await T.btn('skill2');
      else if (g.mp >= 20 && !(g.cds.crescent > 0) && g.enemies.filter(x => Math.abs(x.x - g.px) < 150).length >= 2) await T.btn('skill1');
      else if (g.mp >= 25 && !(g.cds.meteorSpear > 0)) await T.btn('skill3');
      else if (Date.now() - atkT > 160) { atkT = Date.now(); await T.btn('attack', 50); }
    }
    await sleep(60);
  }
  await stick.release();
  s = await T.waitFor(x => x && x.screen === 'result' && x.againBtn, 15000, 'result').catch(() => null);
  r.result = s ? s.game.result : 'timeout';
  r.time = s && s.game ? s.game.result && s.game : null;
  if (s) {
    r.stats = { kills: s.game.kills, maxCombo: s.game.maxCombo, dmg: Math.round(s.game.totalDamage), hp: s.game.hp };
    await sleep(800); await shot(page, `${tag}-result`);
    const sa = await T.st();   // re-read: panel scales in, coords captured mid-tween are stale
    await T.tap(sa.againBtn[0], sa.againBtn[1]);
    const s3 = await T.waitFor(x => x && x.screen === 'battle' && x.game && x.game.wave === 1 && x.game.hp === x.game.maxHp, 8000, 'replay').catch(() => null);
    r.replay = !!s3;
  }
  r.fpsAvg = r.fpsN ? +(r.fpsSum / r.fpsN).toFixed(1) : 0;
  r.wallSec = Math.round((Date.now() - t0) / 1000);
  delete r.fpsSum; delete r.fpsN; delete r.time;
  return r;
}

function checkLayout(s) {
  const L = s.layout, [vw, vh] = s.view, bad = [];
  const ids = Object.keys(L);
  for (const id of ids) {
    const [x, y, r] = L[id];
    if (id !== 'joy' && (x - r < 0 || y - r < 0 || x + r > vw || y + r > vh)) bad.push(`${id} out of view`);
  }
  for (let i = 0; i < ids.length; i++) for (let j = i + 1; j < ids.length; j++) {
    const a = L[ids[i]], b = L[ids[j]];
    if (Math.hypot(a[0] - b[0], a[1] - b[1]) < a[2] + b[2] - 2) bad.push(`${ids[i]}×${ids[j]} overlap`);
  }
  return bad;
}

async function perf(tag) {
  const { browser, page, cdp, T, loadMs } = await open(844, 390, tag);
  const out = { loadMs };
  await page.evaluate(() => window.__AI_BRIDGE__.start()); await T.waitFor(x => x && x.game, 5000, 'battle');
  await page.evaluate(() => { const b = window.__AI_BRIDGE__; b.god(true); b.spawn('imp', 14); b.spawn('lantern', 4); b.spawn('brute', 2); });
  await sleep(1500);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await sleep(1500);
  const base = (await T.st()).fps;
  const fps = [];
  await page.evaluate(() => window.__AI_BRIDGE__.cast('ult'));
  const alive = [];
  for (let i = 0; i < 40; i++) {
    const s = await T.st(); fps.push(s.fps); alive.push(s.game.enemies.length);
    if (s.game.enemies.length < 18) await page.evaluate(() => window.__AI_BRIDGE__.spawn('imp', 6));
    if (i === 12) await shot(page, `${tag}-ult20`); await sleep(100);
  }
  const n = Math.round(alive.reduce((a, b) => a + b, 0) / alive.length);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
  Object.assign(out, { fpsBefore4x: +base.toFixed(1), ultFpsMin4x: +Math.min(...fps).toFixed(1), ultFpsAvg4x: +(fps.reduce((a, b) => a + b, 0) / fps.length).toFixed(1), enemiesAliveAvg: n });
  out.heapMB = await page.evaluate(() => performance.memory ? +(performance.memory.usedJSHeapSize / 1048576).toFixed(1) : null);
  await browser.close();
  return out;
}

(async () => {
  try {
    if (!only || only === 'full') {
      const { browser, page, T, loadMs } = await open(844, 390, 'p844');
      log('home loaded in', loadMs, 'ms');
      const s = await T.st();
      const full = await fullRun(T, page, 'p844');
      full.loadMs = loadMs;
      log('full run', JSON.stringify(full));
      const st = await T.st();
      full.layoutIssues = checkLayout(st);
      full.mechanics = await mechanics(T, page, 'p844');
      log('mechanics', JSON.stringify(full.mechanics));
      report.runs.p844 = full;
      await browser.close();
    }
    if (!only || only === 'small') {
      const { browser, page, T, loadMs } = await open(667, 375, 'p667');
      const full = await fullRun(T, page, 'p667');
      full.loadMs = loadMs;
      full.layoutIssues = checkLayout(await T.st());
      log('p667 run', JSON.stringify(full));
      report.runs.p667 = full;
      await browser.close();
    }
    if (!only || only === 'perf') { report.perf = await perf('perf'); log('perf', JSON.stringify(report.perf)); }
  } catch (e) { report.fatal = String(e.stack || e); console.error(e); }
  fs.writeFileSync(`${OUT}/report.json`, JSON.stringify(report, null, 2));
  log('errors', report.errors.length, report.errors.slice(0, 10));
  log('DONE');
  process.exit(0);
})();
