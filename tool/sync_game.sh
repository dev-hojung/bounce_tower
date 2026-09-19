#!/usr/bin/env bash
# 웹 프로토타입(index.html)을 Flutter 앱 assets/www로 동기화한다.
#   1) 원본 복사
#   2) CDN three.js 스크립트 9개 → 로컬 vendor/ 경로로 치환(오프라인 동작)
#   3) 끝에 Flutter↔JS 광고 브리지 스크립트 주입
# 사용: bash tool/sync_game.sh
set -euo pipefail

SRC="/Users/khj/develop/bounce-tower-prototype/index.html"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$APP_DIR/assets/www"
DST="$WWW/index.html"

mkdir -p "$WWW/vendor"
cp "$SRC" "$DST"

# 2) CDN → vendor 경로 치환
perl -0pi -e 's{https://cdnjs\.cloudflare\.com/ajax/libs/three\.js/r128/three\.min\.js}{vendor/three.min.js}g' "$DST"
perl -0pi -e 's{https://unpkg\.com/three\@0\.128\.0/examples/js/(?:shaders|postprocessing)/([A-Za-z]+\.js)}{vendor/$1}g' "$DST"

# 3) 브리지 스크립트 주입(이미 있으면 건너뜀)
if ! grep -q "BT_NATIVE" "$DST"; then
  perl -0pi -e 's{</body>}{<!-- ===== Flutter <-> JS ad bridge (native AdMob) ===== -->\n<script>\n(function () {\n  var hasBridge = !!(window.flutter_inappwebview && window.flutter_inappwebview.callHandler);\n  window.BT_NATIVE = hasBridge;\n  if (!hasBridge) return;\n  window.showAd = function (cb) {\n    window.flutter_inappwebview.callHandler("showRewarded").then(function (res) {\n      if (res === true || res === "noad") { cb && cb(); }\n    }).catch(function () { cb && cb(); });\n  };\n  function interstitial() { try { window.flutter_inappwebview.callHandler("showInterstitial"); } catch (e) {} }\n  var rb = document.getElementById("retryBtn");\n  var hb = document.getElementById("homeBtn");\n  if (rb) rb.addEventListener("click", interstitial);\n  if (hb) hb.addEventListener("click", interstitial);\n  var af = document.getElementById("iapAdfree");\n  if (af) af.addEventListener("click", function () { try { window.flutter_inappwebview.callHandler("setAdFree", true); } catch (e) {} });\n})();\n</script>\n</body>}g' "$DST"
fi

echo "동기화 완료:"
echo "  - CDN 스크립트 남음? $(grep -c 'unpkg.com\|cdnjs' "$DST") (0이어야 정상)"
echo "  - vendor 참조: $(grep -c 'vendor/' "$DST")"
echo "  - 브리지 주입: $(grep -c 'BT_NATIVE' "$DST")"
