#!/usr/bin/env bash
# Firebase Hosting 배포용 산출물 생성: assets/www(게임) + hosting/*.html(정책 페이지) → build/hosting
# firebase.json의 hosting.predeploy에서 자동 실행된다. 수동 실행: bash tool/build_hosting.sh
set -euo pipefail
ROOT="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT="$ROOT/build/hosting"
rm -rf "$OUT"
mkdir -p "$OUT"
# 점 파일·폴더(.omc 등 로컬 도구 상태)는 공개하지 않는다
rsync -a --exclude ".*" "$ROOT/assets/www/" "$OUT/"
cp "$ROOT"/hosting/*.html "$OUT/"
echo "build/hosting 준비 완료: $(find "$OUT" -type f | wc -l | tr -d ' ')개 파일"
