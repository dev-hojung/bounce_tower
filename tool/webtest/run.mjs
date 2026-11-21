// 계정 연결(Google/Apple) 웹 플로우 회귀 테스트 — Flutter 브리지를 목업으로 갈아 끼워 헤드리스 Chrome에서 돌린다.
// 연결 기능은 ACCT_LINK_ENABLED 스위치로 꺼져 있다. 연결 플로우는 스위치를 켠 사본(/on/)으로, 출시 상태(꺼짐)는 원본 그대로 검증한다.
//   cd tool/webtest && npm i && node run.mjs
// assets/www/index.html 원본은 건드리지 않고, <head>에 mock_bridge.html을 주입한 사본을 임시 폴더에서 서빙한다.
import { chromium } from 'playwright-core';
import http from 'http'; import fs from 'fs'; import path from 'path'; import os from 'os';
const here = path.dirname(new URL(import.meta.url).pathname);
const www = path.resolve(here, '../../assets/www');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bt-webtest-'));
const html = fs.readFileSync(path.join(www, 'index.html'), 'utf8');
const FLAG_OFF = 'const ACCT_LINK_ENABLED = false;';
if (!html.includes(FLAG_OFF)) throw new Error('ACCT_LINK_ENABLED 스위치가 꺼져 있지 않다 — 테스트 전제 확인');
const mocked = html.replace('<head>', '<head>' + fs.readFileSync(path.join(here, 'mock_bridge.html'), 'utf8'));
for (const [dir, body] of [['', mocked], ['on', mocked.replace(FLAG_OFF, 'const ACCT_LINK_ENABLED = true;')], ['orig', html]]) {
  if (dir) fs.mkdirSync(path.join(root, dir));
  fs.writeFileSync(path.join(root, dir, 'index.html'), body);
  fs.symlinkSync(path.join(www, 'vendor'), path.join(root, dir, 'vendor'));
}
const mime = { '.html': 'text/html', '.js': 'application/javascript' };
const server = http.createServer((req, res) => {
  const f = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(f, (e, b) => { if (e) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'application/octet-stream' }); res.end(b); });
}).listen(8090);
const fails = []; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) fails.push(m); };
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors = []; page.on('pageerror', e => errors.push(e.message)); page.on('console', m => { if (m.type() === 'error' && !(m.location().url || '').endsWith('/favicon.ico')) errors.push(m.text() + ' @ ' + m.location().url); });
page.on('response', r => { if (r.status() === 404) console.log('404:', r.url()); });
await page.goto('http://localhost:8090/on/index.html'); await page.waitForTimeout(1800);
ok(errors.length === 0, 'no JS errors on load: ' + JSON.stringify(errors));
// 첫 실행 닉네임 모달(정상 동작)은 건너뛰기로 닫는다
if (await page.isVisible('#nickmodal')) { await page.click('#nickSkip'); await page.waitForTimeout(150); }

// ── 시작 동기화: getAccountState → cloudLoad → 배지 ☁️
let calls = await page.evaluate(() => window.__calls.map(c => c[0]));
ok(calls.includes('getAccountState') && calls.includes('cloudLoad'), 'startup sync called getAccountState+cloudLoad');
ok((await page.textContent('#homeNick')).startsWith('☁️'), 'home chip shows ☁️ (cloud on, not linked)');
ok(!calls.includes('submitScore'), 'no submitScore at startup when best=0 (no 0-point row)');

// ── 진입점: 홈 칩 → 닉 모달 → "계정 연결" 링크 → 계정 모달
await page.click('#homeNick'); await page.waitForTimeout(150);
ok(await page.isVisible('#nickAcctRow'), 'nick modal shows account link row (native)');
await page.click('#nickAcct'); await page.waitForTimeout(300);
ok(await page.isVisible('#acctmodal'), 'account modal opened'); ok(!(await page.isVisible('#nickmodal')), 'nick modal closed');
ok((await page.textContent('#acctStatus')).includes('이 기기에만'), 'status text: device-only');
ok(await page.isVisible('#acctApple'), 'Apple button visible (appleAvailable)');
ok(!(await page.isVisible('#acctLinks')), 'signout/delete hidden while anonymous');

// ── Apple: not-configured 에러 표시
await page.click('#acctApple'); await page.waitForTimeout(400);
ok((await page.textContent('#acctErr')).includes('준비되지'), 'not-configured error shown: ' + await page.textContent('#acctErr'));

// ── Google: 이미 연결된 계정(B)으로 전환 → cloudResync → 병합
await page.evaluate(() => { window.__calls.length = 0; });
await page.click('#acctGoogle'); await page.waitForTimeout(900);
calls = await page.evaluate(() => window.__calls);
const names = calls.map(c => c[0]);
const la = calls.find(c => c[0] === 'linkAccount'); ok(la && la[1] === 'google', 'linkAccount(google) called');
ok(names.indexOf('cloudLoad') > names.indexOf('linkAccount'), 'cloudLoad re-run after link (cloudResync)');
const save = await page.evaluate(() => SAVE);
ok(save.coins === 500 && save.best === 77 && save.nickname === 'CloudNick' && save.ownedSkins.includes('gold') && save.items.revive === 2, 'merged cloud B into local (coins/best/nick/skins/items)');
ok(save.season.best === 0, 'past-season best NOT merged (season id differs)');
const sub = calls.find(c => c[0] === 'submitScore');
ok(sub && sub[1] === 77 && sub[2] === 'CloudNick', 'submitScore re-fired with merged best/nick: ' + JSON.stringify(sub));
ok((await page.textContent('#toast')).includes('합쳐졌어요'), 'toast: merged with other device');
ok((await page.textContent('#homeNick')).startsWith('🔗'), 'home chip shows 🔗 after link');
ok((await page.textContent('#acctGoogle')).includes('연결됨'), 'Google button shows linked');
ok(await page.isVisible('#acctLinks'), 'signout/delete visible when linked');
const linkEv = calls.find(c => c[0] === 'logEvent' && c[1] === 'account_link');
ok(linkEv && linkEv[2].result === 'switched', 'analytics account_link result=switched');
await page.waitForTimeout(2800);
ok((await page.evaluate(() => window.__calls.filter(c => c[0] === 'cloudSave').length)) >= 1, 'debounced cloudSave pushed merged save');

// ── 랭킹 화면 진입점
await page.click('#acctClose'); await page.waitForTimeout(100);
await page.evaluate(() => { rankRows([], '', false); });
ok((await page.textContent('#rankAcct')).includes('연결됨'), 'rank tierBox shows 🔗 계정 연결됨');

// ── 계정 삭제 2단계
await page.evaluate(() => openAcctModal()); await page.waitForTimeout(200);
ok(!(await page.isVisible('#acctConfirm')), 'delete confirm hidden initially');
await page.click('#acctDelete'); await page.waitForTimeout(100);
ok(await page.isVisible('#acctConfirm'), 'delete confirm shown after 1st tap');
await page.evaluate(() => { window.__calls.length = 0; });
await page.click('#acctDeleteGo'); await page.waitForTimeout(700);
calls = await page.evaluate(() => window.__calls.map(c => c[0]));
ok(calls.includes('deleteAccount'), 'deleteAccount called on 2nd tap');
ok((await page.textContent('#toast')).includes('삭제했어요'), 'toast: deleted');
ok((await page.textContent('#homeNick')).startsWith('☁️'), 'chip back to ☁️ after delete (new anonymous)');
const saveAfter = await page.evaluate(() => SAVE);
ok(saveAfter.coins === 500, 'local progress retained after delete');
await page.click('#acctClose');

// ── 권유 트리거: 큐 → 홈 복귀 시 1회만
await page.evaluate(() => { SAVE.linkPrompted = false; SAVE.stats.games = 5; queueLinkPrompt('shop'); showScreen('home'); });
await page.waitForTimeout(800);
ok(await page.isVisible('#acctmodal'), 'link prompt opened on home after queue');
ok((await page.textContent('#acctStatus')).includes('소중한 기록'), 'prompt hint shown');
ok(await page.evaluate(() => SAVE.linkPrompted === true), 'linkPrompted flag set');
await page.click('#acctClose');
await page.evaluate(() => { queueLinkPrompt('best'); showScreen('home'); }); await page.waitForTimeout(800);
ok(!(await page.isVisible('#acctmodal')), 'prompt NOT shown a second time');
ok(errors.length === 0, 'no JS errors during flow: ' + JSON.stringify(errors));

// ── 출시 상태(스위치 꺼짐): 연결 버튼·권유 숨김, 계정 관리에서 익명 계정 삭제만 가능
const page3 = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors3 = []; page3.on('pageerror', e => errors3.push(e.message));
await page3.goto('http://localhost:8090/index.html'); await page3.waitForTimeout(1800);
if (await page3.isVisible('#nickmodal')) { await page3.click('#nickSkip'); await page3.waitForTimeout(150); }
await page3.click('#homeNick'); await page3.waitForTimeout(150);
ok((await page3.textContent('#nickAcct')).includes('계정 관리'), 'off: nick modal entry reads 계정 관리');
await page3.click('#nickAcct'); await page3.waitForTimeout(300);
ok(await page3.isVisible('#acctmodal'), 'off: account modal opens');
ok(!(await page3.isVisible('#acctGoogle')) && !(await page3.isVisible('#acctApple')), 'off: Google/Apple buttons hidden');
ok((await page3.textContent('#acctStatus')).includes('익명 계정'), 'off: status text explains anonymous account');
ok(await page3.isVisible('#acctDelete') && !(await page3.isVisible('#acctSignOut')), 'off: delete visible, signout hidden (anonymous)');
await page3.click('#acctDelete'); await page3.waitForTimeout(100);
await page3.evaluate(() => { window.__calls.length = 0; });
await page3.click('#acctDeleteGo'); await page3.waitForTimeout(700);
ok((await page3.evaluate(() => window.__calls.map(c => c[0]))).includes('deleteAccount'), 'off: anonymous delete calls deleteAccount');
ok((await page3.textContent('#toast')).includes('삭제했어요'), 'off: toast deleted');
await page3.click('#acctClose');
await page3.evaluate(() => { rankRows([], '', false); });
ok((await page3.textContent('#rankAcct')).includes('계정 관리'), 'off: rank entry reads 계정 관리');
await page3.evaluate(() => { SAVE.linkPrompted = false; SAVE.stats.games = 5; queueLinkPrompt('shop'); showScreen('home'); });
await page3.waitForTimeout(800);
ok(!(await page3.isVisible('#acctmodal')), 'off: link prompt never opens');
ok(await page3.evaluate(() => SAVE.linkPrompted === false), 'off: linkPrompted untouched (prompt saved for later)');
ok(errors3.length === 0, 'off: no JS errors: ' + JSON.stringify(errors3));

// ── 브라우저 모드(브리지 없음): 원본 파일로 무해성 확인
const page2 = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors2 = []; page2.on('pageerror', e => errors2.push(e.message));
await page2.goto('http://localhost:8090/orig/index.html'); await page2.waitForTimeout(1200);
ok(errors2.length === 0, 'browser mode: no JS errors: ' + JSON.stringify(errors2));
ok((await page2.textContent('#homeNick')).startsWith('👤'), 'browser mode: chip 👤');
await page2.click('#nickSkip').catch(() => {});
await page2.evaluate(() => openNickModal(false)); await page2.waitForTimeout(100);
ok(!(await page2.isVisible('#nickAcctRow')), 'browser mode: account link hidden');
await page2.evaluate(() => { queueLinkPrompt('shop'); showScreen('home'); }); await page2.waitForTimeout(700);
ok(!(await page2.isVisible('#acctmodal')), 'browser mode: prompt never opens');

await browser.close(); server.close(); fs.rmSync(root, { recursive: true, force: true });
console.log(fails.length ? `\n${fails.length} FAILED` : '\nALL PASSED');
process.exit(fails.length ? 1 : 0);
