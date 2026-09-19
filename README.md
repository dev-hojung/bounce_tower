# Bounce Tower (Flutter WebView + AdMob)

Helix Jump 스타일 캐주얼 게임. **Three.js 웹 프로토타입을 Flutter WebView로 래핑**하고
**네이티브 AdMob**으로 수익화한 모바일 앱(iOS/Android).

> Unity 정식 이식을 시도했으나 웹 프로토타입의 블룸/오로라 비주얼 퀄리티 재현이
> 비효율적이라, 완성된 웹 게임을 그대로 살리는 WebView 방식으로 전환했다.

## 구조

```
lib/
  main.dart              # 앱 진입점. 로컬 HTTP 서버 기동 + 풀스크린 InAppWebView + 브리지 등록
  ads.dart               # AdManager: 전면/보상형 광고 로드·노출·빈도제한
  ranking.dart           # RankingService: 익명 인증 + 계정 연결(Google/Apple) + 전체/시즌 랭킹 + 클라우드 세이브
  remote_config.dart     # RemoteConfigService: 밸런스·광고빈도·시즌 원격 조정
  notifications.dart     # NotificationService: 출석·복귀·주간마감 로컬 알림
  firebase_options.dart  # flutterfire configure 산출물
assets/www/
  index.html  # 게임 본체. CDN→로컬 vendor 경로로 교체됨(오프라인 동작)
  vendor/*.js # three.js r128 + 포스트프로세싱(블룸) 의존성 로컬 번들
```

> ⚠️ **게임 본체의 원본은 `assets/www/index.html`이다.**
> `/Users/khj/develop/bounce-tower-prototype/index.html`은 2026-06-25에서 멈춰 있어
> 닉네임·클라우드 세이브·시즌이 **들어 있지 않다**. 거기서 복사해 오면 그 기능들이
> 사라지므로, 게임 수정은 `assets/www/index.html`에서 직접 한다.
> 프로토타입은 참고용 과거 기록.

## 동작 방식

1. `InAppLocalhostServer(documentRoot: 'assets/www')`가 게임을 `http://localhost:8080`로 서빙
   (상대경로 `vendor/*.js`가 그대로 로드되도록).
2. 풀스크린 `InAppWebView`가 `index.html`을 로드.
3. `assets/www/index.html` 하단 **브리지 스크립트**가 `window.flutter_inappwebview` 존재 시
   네이티브 광고로 동작 전환(없으면 기존 웹 목업 그대로 → 브라우저 테스트 가능).

## JS ↔ Dart 브리지

브리지가 없으면(브라우저) 게임은 목업 광고·목업 랭킹·기본 밸런스로 그대로 동작한다.

| JS 호출 | Dart 핸들러 | 용도 |
|---|---|---|
| `showRewarded()` → `Promise` | `AdManager.showRewarded()` | 부활 / 코인 2배 (보상형). `true`=보상완료, `'noad'`=광고없음(지급), `false`=중도종료 |
| `showInterstitial()` | `AdManager.maybeShowInterstitial()` | 게임오버 후 다시하기/홈 전환 시 전면광고. 기본 45초 빈도제한(Remote Config로 조정) |
| `setAdFree()` | `AdManager.adFree = true` | **dormant** — 광고 전용 모델이라 호출되지 않음 |
| `submitScore(best, name, seasonBest)` | `RankingService.submitScore` | 전체 랭킹 + 현재 시즌 랭킹에 최고점 제출 |
| `getLeaderboard(myBest)` | `RankingService.getLeaderboard` | 전체 상위 100 + 내 순위 (미설정 시 `null` → 목업) |
| `getSeasonLeaderboard(mySeasonBest)` | `RankingService.getSeasonLeaderboard` | 시즌 상위 100 + 내 순위 + `{seasonId, seasonIndex, endsAt}` |
| `getAccountState()` | `RankingService.accountState` | `{enabled, uid, linked, isAnonymous, providers[], appleAvailable}` — 시작 시 폴링 + 배지·계정 모달 |
| `linkAccount(provider)` → `Promise` | `RankingService.linkAccount` | `'google'`\|`'apple'` 계정 연결. `{ok, switched, providers, error}`. `switched`면 웹이 `cloudResync()`로 재병합 |
| `signOut()` → `Promise` | `RankingService.signOut` | 로그아웃 → 새 익명. 로컬 세이브 유지 |
| `deleteAccount()` → `Promise` | `RankingService.deleteAccount` | 계정 삭제(스토어 정책). 재인증 → (Apple) revoke → 문서 삭제 → `user.delete()` |
| `cloudLoad()` / `cloudSave(save)` | `RankingService.loadCloud/saveCloud` | `users/{uid}.save`에 웹 SAVE 통째 백업·복원 |
| `getRemoteConfig()` | `RemoteConfigService.toJson()` | 밸런스·시즌 설정. `ready=true`가 될 때까지 웹이 폴링 |

> **수익 모델: 광고 전용.** 유료 상품(IAP)은 제공하지 않는다. `setAdFree` 브리지와
> `AdManager.adFree`는 현재 호출되지 않는 dormant 코드(향후 광고제거 IAP 도입 대비 잔존).

게임 코드의 `showAd(cb)`(부활/코인2배 공통)와 `retryBtn`/`homeBtn` 클릭에 훅이 걸려 있다.

## ⚠️ 출시 전 필수 교체 (현재 Google 테스트 ID)

실제 AdMob 계정 ID로 바꾸지 않으면 수익이 발생하지 않으며, 개발 중 실광고 클릭은
계정 정지 위험이 있다.

- `lib/ads.dart` → `_AdUnits.interstitial`, `_AdUnits.rewarded` (Android/iOS 각각)
- `android/app/src/main/AndroidManifest.xml` → `com.google.android.gms.ads.APPLICATION_ID`
- `ios/Runner/Info.plist` → `GADApplicationIdentifier`

## 빌드 / 실행

```bash
flutter pub get
flutter run -d <device>          # 시뮬레이터/실기기
flutter build apk --release      # Android
flutter build ipa                # iOS (서명 설정 필요)

# 계정 연결 웹 플로우 회귀 테스트 (목 브리지 + 헤드리스 Chrome, Flutter 불필요)
cd tool/webtest && npm i && node run.mjs
```

## 남은 작업 (출시까지)

- [ ] 실제 AdMob 광고단위 ID 교체
- [x] iOS `SKAdNetworkItems` 항목 추가 (광고 어트리뷰션) — AdMob 50개
- [x] Firebase Analytics + Crashlytics
- [ ] 스토어 등록(스크린샷, 설명, 심사)
- [x] 소셜 로그인 코드 + 콘솔 provider·debug SHA·config 재생성·URL scheme·규칙 배포 (2026-09-17)
- [ ] upload/Play App Signing SHA-1 등록 + Apple Developer capability + 실기기 e2e. `FIREBASE_SETUP.md` 2-B
- [ ] 릴리스 키스토어 생성 → `android/key.properties`(예시 파일 참고). 없으면 debug 서명으로 폴백된다

> 수익은 **광고 전용**(전면·보상형). 유료 상품 없음. 자세한 잔여 작업은 `출시_체크리스트.md`.
> 완료: 앱 아이콘·스플래시·앱 이름, ATT 동의, 개인정보처리방침 URL, Firebase 랭킹·클라우드
> 세이브, 닉네임 UI, 로컬 알림 3종, 2주 시즌 랭킹 + 시즌 한정 스킨, Remote Config,
> 계정 연결(Google/Apple) 코드(설정 전에는 "로그인 설정이 아직 준비되지 않았어요"로 안전 실패).

## Remote Config로 조정 가능한 값

콘솔에 파라미터를 안 만들어도 `lib/remote_config.dart`의 기본값으로 동작한다.
원격 값은 안전 범위로 클램프되므로 콘솔 오입력이 게임을 망가뜨리지 않는다.

| 키 | 기본 | 범위 | 효과 |
|---|---|---|---|
| `first_runs_no_ads` | 3 | 0~50 | **첫 N판은 전면광고 없음**(첫인상 보호) |
| `interstitial_every_runs` | 3 | 1~20 | 그 이후 M판마다 전면광고 1회 |
| `interstitial_gap_sec` | 45 | 15~600 | 전면광고 최소 간격(초) — 판수 정책 위의 백스톱 |
| `danger_max` | 0.42 | 0~0.8 | 최대 위험 발판 비율 |
| `rage_combo` | 5 | 2~30 | RAGE(무적) 발동 콤보 |
| `coin_mult` | 1.0 | 0.5~10 | 코인 획득 배율(이벤트용) |
| `season_enabled` | true | — | 시즌 탭·한정 스킨 노출 |
| `season_goal` | 60 | 10~100000 | 시즌 한정 스킨 해금 점수 |

## 시즌 (2주)

`2026-01-05 00:00 UTC`를 기준점으로 14일마다 시즌이 바뀐다. 시즌 점수는
`seasons/{seasonId}/scores/{uid}`에 따로 쌓이고, 전체 랭킹(`scores/{uid}`)은
명예의 전당으로 남는다. 시즌 최고점이 `season_goal` 이상이면 그 시즌 한정 스킨이
해금되며(3종 로테이션), 시즌이 지나면 획득 경로가 사라진다.

> ⚠️ 시즌 번호는 `lib/ranking.dart`와 `assets/www/index.html`이 **각자 독립 계산**한다
> (브라우저 목업에서도 시즌이 돌아야 하므로). 기준점·주기를 바꿀 때는 **양쪽을 함께**
> 고칠 것 — 한쪽만 바꾸면 웹이 보는 시즌과 기록되는 시즌이 어긋난다.
