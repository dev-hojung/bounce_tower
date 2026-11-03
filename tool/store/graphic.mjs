// 스토어 그래픽 이미지(1024x500) 생성 — Play 스토어 등록정보 필수 자산.
//   cd tool/store && node graphic.mjs
import { chromium } from 'playwright-core';
import fs from 'fs'; import path from 'path';
const here = path.dirname(new URL(import.meta.url).pathname);
const out = path.resolve(here, '../../store');
const icon = fs.readFileSync(path.resolve(here, '../../assets/icon/icon.png')).toString('base64');

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { width:1024px; height:500px; overflow:hidden;
         font-family:-apple-system,system-ui,"Apple SD Gothic Neo",sans-serif; }
  .bg { position:absolute; inset:0;
        background:
          radial-gradient(900px 420px at 78% 18%, rgba(124,92,255,.55), transparent 62%),
          radial-gradient(700px 380px at 22% 88%, rgba(255,92,141,.42), transparent 60%),
          linear-gradient(160deg, #2a1748 0%, #1a0f33 48%, #0f0a1e 100%); }
  .stars { position:absolute; inset:0; }
  .s { position:absolute; background:#fff; border-radius:50%; }
  .wrap { position:absolute; inset:0; display:flex; align-items:center; gap:52px; padding:0 66px; }
  .art { position:relative; width:290px; height:290px; flex:none; }
  .glow { position:absolute; inset:-38px; border-radius:50%;
          background:radial-gradient(circle, rgba(124,92,255,.62), transparent 68%); filter:blur(14px); }
  .art img { position:relative; width:290px; height:290px; border-radius:64px;
             box-shadow:0 26px 70px rgba(0,0,0,.6); }
  h1 { font-size:88px; line-height:.95; font-weight:900; letter-spacing:-2px; color:#fff;
       text-shadow:0 6px 34px rgba(124,92,255,.75); }
  h1 em { display:block; font-style:normal;
          background:linear-gradient(95deg,#ff5c8d,#ffb86b 55%,#7cf0ff);
          -webkit-background-clip:text; background-clip:text; color:transparent; }
  p { margin-top:20px; font-size:29px; font-weight:700; color:#d6d2ee; letter-spacing:-.4px; }
  .tags { margin-top:26px; display:flex; gap:11px; }
  .tag { font-size:19px; font-weight:800; color:#fff; padding:10px 20px; border-radius:999px;
         background:rgba(255,255,255,.12); border:1px solid rgba(255,255,255,.22); }
</style></head><body>
  <div class="bg"></div>
  <div class="stars" id="st"></div>
  <div class="wrap">
    <div class="art"><div class="glow"></div><img src="data:image/png;base64,${icon}"></div>
    <div>
      <h1>BOUNCE<em>TOWER</em></h1>
      <p>드래그로 타워를 돌려 끝없이 내려가세요</p>
      <div class="tags"><span class="tag">원터치</span><span class="tag">오프라인 플레이</span><span class="tag">2주 시즌 랭킹</span></div>
    </div>
  </div>
  <script>
    const st = document.getElementById('st');
    for (let i = 0; i < 90; i++) {
      const d = document.createElement('div'); d.className = 's';
      const r = Math.random() * 2.1 + 0.7;
      d.style.cssText = 'width:'+r+'px;height:'+r+'px;left:'+(Math.random()*1024)+'px;top:'+(Math.random()*500)+'px;opacity:'+(Math.random()*.7+.25);
      st.appendChild(d);
    }
  </script>
</body></html>`;

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 1024, height: 500 }, deviceScaleFactor: 1 });
await page.setContent(html, { waitUntil: 'load' });
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, 'feature-graphic-1024x500.png') });
await browser.close();
console.log('saved', path.join(out, 'feature-graphic-1024x500.png'));
