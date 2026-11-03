# hosting — 공개 웹 페이지 (Firebase Hosting)

스토어 제출에 필요한 공개 URL과 웹 데모를 **Firebase Hosting**(`https://bounce-tower.web.app`)으로 서빙한다.
2026-11 이전에는 별도 저장소(`bounce-tower-web`)를 Railway로 배포했으나, 앱 저장소 하나로 관리하려고 이쪽으로 합쳤다.

| URL | 원본 | 용도 |
|---|---|---|
| `/` | `assets/www/index.html` | 웹 데모(브라우저 목업 모드 — 광고·랭킹은 목업) |
| `/privacy` | `hosting/privacy.html` | 개인정보처리방침 (Play·App Store 제출용) |
| `/delete-account` | `hosting/delete-account.html` | 계정 삭제 요청 (Play 데이터 보안 제출용) |

## 배포

```bash
firebase deploy --only hosting
```

`firebase.json`의 predeploy가 `tool/build_hosting.sh`를 먼저 실행해 `assets/www` + `hosting/*.html`을
`build/hosting/`으로 합친 뒤 올린다. **게임 원본은 `assets/www` 하나뿐**이라 앱과 웹 데모가 어긋나지 않는다
(Railway 시절엔 6월 사본이 그대로 남아 웹 데모가 구버전이었다).

## 주의

- `/privacy`, `/delete-account` URL은 Play Console에 등록돼 있다. 경로를 바꾸면 콘솔도 함께 고칠 것.
- 개인정보 처리 항목(수집 데이터·외부 서비스)이 바뀌면 `privacy.html`과 Play 데이터 보안 양식을 함께 갱신.
