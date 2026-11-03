// 스토어 등록용 스크린샷 생성 — 실제 게임(assets/www)을 폰 해상도 헤드리스 크롬으로 띄워 캡처한다.
//   cd tool/store && npm i && node shots.mjs
// 결과: store/screenshots/*.png (1080x1920, Play/App Store 제출 규격)
import { chromium } from 'playwright-core';
import http from 'http'; import fs from 'fs'; import path from 'path';
const here = path.dirname(new URL(import.meta.url).pathname);
const www = path.resolve(here, '../../assets/www');
const out = path.resolve(here, '../../store/screenshots');
fs.mkdirSync(out, { recursive: true });
const mime = { '.html': 'text/html', '.js': 'application/javascript' };
const server = http.createServer((req, res) => {
  const f = path.join(www, decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(f, (e, b) => { if (e) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'application/octet-stream' }); res.end(b); });
}).listen(8091);

const browser = await chromium.launch({ channel: 'chrome', headless: true,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--hide-scrollbars'] });
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
page.on('pageerror', e => console.log('JS ERROR:', e.message));

// 진행도가 있는 상태로 보이도록 세이브를 미리 심는다(실제 플레이로 도달 가능한 값).
await page.addInitScript(() => {
  localStorage.setItem('bt_save_v2', JSON.stringify({
    coins: 1240, best: 1240,
    ownedSkins: ['classic','aqua','lime','gold','violet'], equipped: 'gold',
    ownedTrails: ['basic','stardust','flame'], equippedTrail: 'stardust',
    ownedThemes: ['aurora','sunset','deepsea'], equippedTheme: 'aurora',
    items: { revive: 2, booster: 1, shield: 1 }, boosterRuns: 0,
    nickname: 'BounceKing', nickSet: true, linkPrompted: true, notifAsked: true,
    stats: { games: 143, bestDepth: 96, bestCombo: 18, rages: 27, coinsTotal: 9800 },
    daily: { last: '', streak: 4 },
    season: { id: 'S19', best: 540 },
  }));
});
await page.goto('http://localhost:8091/index.html');
await page.waitForTimeout(2500);
await page.evaluate(() => {   // 개발용 튜닝 패널 숨김
  const p = document.getElementById('panel'); if (p) p.style.display = 'none';
});

const shot = async (name) => { await page.screenshot({ path: path.join(out, name + '.png') }); console.log('saved', name); };

// 1) 홈
await page.evaluate(() => { showScreen('home'); refreshMeta(); });
await page.waitForTimeout(700); await shot('01-home');

// 2) 플레이 중 — 게임은 타워를 돌려야 진행되므로 자동 조작을 붙인다
//    (다음 링의 빈틈으로 타워를 맞추는 캡처용 봇. 게임 코드는 건드리지 않는다)
await page.evaluate(() => {
  const h = document.getElementById('hint'); if (h) h.style.display = 'none';  // 조작 안내 문구 숨김
  RAGE_COMBO = 999;                       // 플레이 컷에서는 무적 연출을 끈다(3번 컷에서 따로 보여줌)
  window.__auto = 'gap';
  const loop = () => {
    if (!window.__auto) return;
    if (typeof state !== 'undefined' && state === 'playing') {
      const r = nextRing();
      if (r) {
        const idx = r.slots.map((v, i) => v === window.__auto ? i : -1).filter(i => i >= 0);
        if (idx.length) tower.rotation.y = (idx[0] + 0.5) * SLOT_ANG;
      }
    }
    requestAnimationFrame(loop);
  };
  loop();
  startGame();
});
await page.waitForTimeout(8000);

// 공이 화면 중앙부에 보이는 프레임에서 찍는다(공이 잘려 안 보이는 컷 방지)
const ballY = () => page.evaluate(() => {
  const v = ball.position.clone().project(camera);
  return { y: (1 - v.y) / 2, depth: runDepth, score: score };
});
let best = null;
for (let i = 0; i < 40; i++) {
  const p0 = await ballY();
  if (p0.y > 0.25 && p0.y < 0.45 && (!best || Math.abs(p0.y - 0.35) < best.d)) {
    await shot('02-play'); best = { d: Math.abs(p0.y - 0.35), ...p0 };
    if (best.d < 0.05) break;
  }
  await page.waitForTimeout(120);
}
console.log('play 컷:', best || '조건 미달 — 마지막 프레임 사용');
if (!best) await shot('02-play');

// 3) 무적(RAGE) — 콤보가 쌓이면 링을 부수며 관통한다
await page.evaluate(() => { rageLeft = RAGE_RINGS; setRage(true); updateHUD(); });
await page.waitForTimeout(500);
for (let i = 0; i < 25; i++) {
  const p0 = await ballY();
  if (p0.y > 0.25 && p0.y < 0.45) break;
  await page.waitForTimeout(120);
}
await shot('03-rage');
await page.evaluate(() => { window.__auto = null; });

// 4) 랭킹 — 탭 활성 표시까지 맞춘다
await page.evaluate(async () => {
  state = 'home'; setRage(false);
  rankMode = 'all';
  document.querySelectorAll('#rankTabs .shoptab').forEach(t => t.classList.toggle('active', t.dataset.rank === 'all'));
  await renderRank(); showScreen('rank');
});
await page.waitForTimeout(900); await shot('04-rank');

// 5) 상점(공 스킨)
await page.evaluate(() => { shopCat = 'skin'; refreshMeta(); renderShop(); showScreen('shop'); });
await page.waitForTimeout(700); await shot('05-shop');

// 6) 출석·미션
await page.evaluate(() => { renderDaily(); showScreen('daily'); });
await page.waitForTimeout(700); await shot('06-daily');

await browser.close(); server.close();
console.log('완료:', out);
