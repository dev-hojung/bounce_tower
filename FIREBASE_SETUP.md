# Firebase 계정·랭킹 설정 런북

목표: 익명 로그인 + Firestore로 **크로스플랫폼 랭킹**(+ 추후 클라우드 세이브).
코드는 이미 들어가 있고, **Firebase 미설정 상태에서는 게임이 목업 랭킹으로 그대로 동작**한다.
아래 단계를 마치면 실제 랭킹이 활성화된다.

## 1. Firebase 프로젝트 생성 (브라우저, 본인 계정)
1. https://console.firebase.google.com → "프로젝트 추가" → 이름 예: `bounce-tower`
2. Google 애널리틱스는 켜도/꺼도 무방(나중에 연결 가능)

## 2. FlutterFire CLI 설치 + 구성 (터미널)
로그인이 필요한 인터랙티브 단계라 직접 실행해 주세요. 세션 프롬프트에서 `!` 접두로 실행 가능:

```bash
! dart pub global activate flutterfire_cli
! cd /Users/khj/develop/bounce_tower && flutterfire configure
```
- 프롬프트에서 위에서 만든 프로젝트 선택
- 플랫폼은 **iOS, Android** 선택
- 끝나면 `lib/firebase_options.dart` + iOS `GoogleService-Info.plist` + Android `google-services.json`이 생성/배치됨

> 이 단계를 마치면 알려주세요. 제가 초기화 코드를 `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`로 전환하고 빌드 검증까지 마무리합니다.

## 3. Authentication 활성화 (콘솔) — ✅ 완료 2026-09-17
- Firebase 콘솔 → Authentication → 시작하기 → **익명(Anonymous)** 로그인 사용 설정
- ⚠️ **이 단계가 2026-09-17까지 빠져 있었다.** 코드는 진작 들어가 있었지만 `CONFIGURATION_NOT_FOUND`로
  익명 로그인이 계속 실패해 랭킹·클라우드 세이브·시즌이 전부 목업으로만 돌았다(Firestore 문서 0개).
  증상이 "조용한 폴백"이라 눈치채기 어렵다. 확인법: Authentication → Users에 계정이 쌓이는지,
  Firestore에 `scores`/`users` 문서가 생기는지.

## 4. Firestore 생성 + 규칙 배포 (콘솔 또는 CLI)
- 콘솔 → Firestore Database → 데이터베이스 만들기 → 프로덕션 모드
- 규칙은 이 저장소의 `firestore.rules`를 사용:
  - 콘솔 → Firestore → 규칙 탭에 붙여넣기, 또는
  - `! npm i -g firebase-tools && firebase login && firebase deploy --only firestore:rules`
- ✅ 2026-09-17 배포 완료(시즌 규칙 + 본인 `delete`). 라이브 프로브로 검증한 동작:
  허용 = 본인 점수·시즌·세이브 쓰기, 본인 문서 3종 삭제, 비로그인 랭킹 읽기 /
  차단 = 점수 하향, 타인 문서 읽기·쓰기·삭제, 형식 밖 seasonId 컬렉션 생성

## 5. Remote Config 파라미터 등록 (콘솔, 선택)
앱 업데이트 없이 밸런스·광고빈도·시즌을 조정한다. **등록하지 않아도 코드 기본값으로
정상 동작**하므로 급하지 않다. 콘솔 → Remote Config → 매개변수 추가:

| 키 | 타입 | 기본 | 허용 범위(코드가 강제) |
|---|---|---|---|
| `first_runs_no_ads` | Number | 3 | 0~50 |
| `interstitial_every_runs` | Number | 3 | 1~20 |
| `interstitial_gap_sec` | Number | 45 | 15~600 |
| `danger_max` | Number | 0.42 | 0~0.8 |
| `rage_combo` | Number | 5 | 2~30 |
| `coin_mult` | Number | 1.0 | 0.5~10 |
| `season_enabled` | Boolean | true | — |
| `season_goal` | Number | 60 | 10~100000 |

- 범위 밖 값을 넣으면 `RemoteConfigService._clamp`가 잘라내므로 게임이 망가지지 않는다.
- 앱은 시작 시 1회 fetch하며 최소 fetch 간격은 1시간(`minimumFetchInterval`).
  즉시 확인하려면 앱을 재설치하거나 콘솔에서 값을 바꾸고 1시간 뒤 확인.
- 코드: `lib/remote_config.dart`, 브리지 `getRemoteConfig`, 웹 `applyRemoteConfig()`

## ⚠️ Firebase 패키지는 "같은 세대"끼리만 묶인다 (가장 많이 깨진 지점)

각 Firebase 플러그인은 특정 `firebase_core` 세대와 **네이티브 코드가 짝지어져** 있다.
그런데 Dart 제약(`^`)은 세대가 어긋난 조합도 허용하기 때문에 **`pub get`도
`flutter analyze`도 통과하고, 빌드 단계에서만 터진다.** 실제로 겪은 것:

| 어긋난 조합 | 증상 |
|---|---|
| core 4.14.0 + auth 6.5.x | Android: `cannot find symbol: customAuthDomain` |
| remote_config 6.5.6 + Flutter 3.41 | iOS: `Redundant conformance of 'FlutterError' to protocol 'Error'` |

원인은 pub의 **최소 변경 원칙**이다. `flutter pub add firebase_analytics`를 하면
analytics만 최신으로 올라가고 기존 auth/firestore/remote_config는 옛 세대에 남는다.

**규칙: Firebase 패키지는 하나만 올리지 말고 세트로 움직인다.**

```bash
# 현재 각 플러그인이 요구하는 core 세대 확인
! grep -A1 "^  firebase_core:" ~/.pub-cache/hosted/pub.dev/<플러그인>-<버전>/pubspec.yaml
```

`pubspec.yaml`의 Firebase 블록에 주석으로 같은 내용을 적어 뒀다.

## ⚠️ Firebase 패키지를 추가할 때마다 iOS 파드가 깨진다 (자주 겪음)

`flutter pub add firebase_*` 는 **Firebase 스택 전체를 함께 올린다**(예: analytics를
추가했더니 `firebase_auth` 6.5.4→6.5.7, `Firebase/Auth` 12.17.0→12.18.0). 그러면
`ios/Podfile.lock`이 고정한 옛 버전과 충돌해 빌드가 이렇게 실패한다:

```
[!] CocoaPods could not find compatible versions for pod "Firebase/Auth":
  In snapshot (Podfile.lock): Firebase/Auth (= 12.17.0)
  In Podfile: firebase_auth ... was resolved to 6.5.7, which depends on Firebase/Auth (= 12.18.0)
```

**`pod install --repo-update`만으로는 안 풀린다** — 스펙 저장소는 갱신되지만
락파일 스냅샷이 여전히 옛 버전을 강제하기 때문. 다음 순서로 처리한다:

```bash
! cd /Users/khj/develop/bounce_tower/ios
! pod repo update          # 스펙 캐시 갱신 (최초 1회 또는 새 버전이 안 잡힐 때)
! rm -f Podfile.lock && pod install   # 락파일 재생성
```

Android는 이 문제가 없다(Gradle이 매번 재해결). Phase 2에서 `google_sign_in`을
추가할 때도 똑같이 겪을 것(Apple 로그인은 firebase_auth 내장이라 패키지 추가 없음, 2-B 참고).

## 데이터 모델
```
scores/{uid}                      : { name: string(<=16), best: int, updatedAt }  // 전체 랭킹
seasons/{seasonId}/scores/{uid}   : { name, best, updatedAt }                     // 시즌 랭킹(2주)
users/{uid}                       : { save: {...웹 SAVE 통째...}, updatedAt }     // 클라우드 세이브
```
랭킹 조회: `orderBy(best desc).limit(100)`, 내 순위는 `best > myBest` 카운트(전체·시즌 동일).
`seasonId`는 `S0`,`S1`,… 형식이며 시즌이 바뀌면 하위 문서가 새로 생성된다(자연 리셋).

> ⚠️ **시즌 규칙이 추가되어 `firestore.rules` 재배포가 필요하다.** 4번 단계를 다시 수행할 것.
> Phase 2(2-B)에서 본인 문서 `delete` 허용이 추가되면 다시 한 번 재배포한다.

## 동작 방식 (코드)
- `lib/ranking.dart` `RankingService`: 앱 시작 시 `init()`(익명 로그인) → 실패하면 비활성(목업 유지)
- 게임(JS) → 브리지 `submitScore(best, name, seasonBest)` → 전체·시즌 문서 동시 기록
- 랭킹 화면 진입 → `getLeaderboard(myBest)` / `getSeasonLeaderboard(mySeasonBest)`
  → 상위 100 + 내 순위 반환 → 웹 UI 렌더(없으면 기존 목업)

## 비용
익명 인증·Firestore 읽기/쓰기 모두 무료 티어(일 5만 읽기/2만 쓰기)로 캐주얼 게임 초기엔 충분.
랭킹 조회를 화면 진입 시에만 호출하고 캐시하면 읽기량을 더 줄일 수 있다.

---

# Phase 2 — 계정·클라우드 세이브

설계 문서: `바운스타워_닉네임계정설계.md`

## 2-A. 클라우드 세이브 (구현 완료 — 추가 설정 불필요)

웹의 `SAVE`(localStorage) 전체를 `users/{uid}.save`에 백업한다. 이미 설정된 익명
인증 + Firestore 위에서 **바로 동작**한다(추가 콘솔 작업 없음).

- 동작: 앱 시작 → 웹이 `getAccountState` 폴링(익명 로그인 완료 대기, 최대 ~5초) →
  `cloudLoad`로 클라우드 세이브를 받아 **병합** → 이후 변경은 `cloudSave`로 디바운스(2.5초) 백업
- 병합 정책(웹 `mergeCloud`): 코인/best/통계=최댓값, 보유 스킨·트레일·테마=합집합,
  아이템 수=최댓값, 업적=합집합(true 우선), 닉네임=클라우드가 사용자지정(`nickSet`)이면 우선.
  **시즌 최고점은 시즌 ID가 같을 때만** 병합(지난 시즌 값 유입 차단).
  daily/missions/weekly/장착=시간·세션 의존이라 로컬 유지.
- 푸시 가드: 첫 pull+merge 완료(`_cloudReady`) 전에는 백업을 막아 빈 로컬이 클라우드를 덮지 않게 함.
- 코드: `lib/ranking.dart`(`loadCloud`/`saveCloud`/`uid`), `lib/main.dart`(브리지 `cloudLoad`/`cloudSave`/`getAccountState`), `assets/www/index.html`(`cloudSyncOnStart`/`mergeCloud`/`cloudPushDebounced`)
- 데이터: `users/{uid}: { save: {...웹 SAVE...}, updatedAt }`. `firestore.rules`의 `users/{uid}` 본인 R/W 규칙으로 이미 보호됨(규칙 변경 불필요).

> ⚠️ 한계: 익명 uid는 **재설치/기기교체 시 새로 발급**되므로, 클라우드 세이브만으로는
> 재설치 후 복원이 안 된다. 재설치·기기이전 복원은 아래 2-B(소셜 로그인 연결) 필요.

## 2-B. 소셜 로그인 연결 (Google/Apple) — **코드 완료(2026-09-02)**, 프로비저닝 필요

> 2026-09-02 설계 검토 반영. 설계 본문(방식·already-in-use·계정 삭제·UX)은
> `바운스타워_닉네임계정설계.md` Phase 2. 여기는 **콘솔·플랫폼 설정과 코드 착수 순서**만 다룬다.

목표: 익명 계정을 Google/Apple에 **연결(linkWithCredential)**해 재설치·기기이전 후에도
같은 uid로 랭킹·클라우드 세이브를 복원. **양 플랫폼 모두 Google + Apple** 제공
(Android Apple은 웹 플로우, 2차). 코드 작성 전에 아래 **인터랙티브 설정이 선행**돼야 한다.

### 선행 설정 — 🟡 2026-09-17 대부분 완료

| 항목 | 상태 |
|---|---|
| Google·Apple provider ON | ✅ (Apple의 Services ID는 비움 — iOS 네이티브엔 불필요) |
| 익명 자동 삭제 OFF | ✅ 기본값 유지 확인 |
| debug SHA-1/SHA-256 등록 | ✅ Firebase Management API로 등록 |
| upload 키스토어 SHA-1 | ⬜ 키 생성 후 |
| Play App Signing SHA-1 | ⬜ Play Console 등록 후 |
| `flutterfire configure` 재실행 | ✅ `oauth_client` web/android + iOS `CLIENT_ID` 생성됨 |
| iOS URL scheme(`REVERSED_CLIENT_ID`) | ✅ `Info.plist` 등록 |
| Apple Developer App ID capability | ⬜ |

아래는 원래 절차(남은 항목 참고용).


1. **Firebase 콘솔 → Authentication → Sign-in method**: Google, Apple provider 사용 설정
2. **Authentication → Settings → User actions**: "익명 사용자 자동 삭제(30일)"가 **꺼져 있는지 확인**.
   켜져 있으면 30일 미접속 익명 계정이 지워져 다음 실행에 uid가 바뀐다(미연결 유저 랭킹·세이브 유실).
   Phase 2와 무관하게 **현 구조에도 이미 영향**을 주는 설정이다.
3. **Android SHA-1/SHA-256 — 3종 모두** 등록: 프로젝트 설정 → 내 앱(Android) → 지문 추가
   ```bash
   # ① debug 지문
   ! keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
   # ② upload 키스토어 지문 (실제 서명 키스토어 경로/alias로)
   ! keytool -list -v -alias <alias> -keystore <upload.jks>
   ```
   ③ **Play App Signing 인증서**: Play Console → 설정 → 앱 서명 → "앱 서명 키 인증서"의 SHA-1.
   ⚠️ ③이 빠지면 내부테스트까지는 되고 **프로덕션에서만 Google 로그인이 실패**한다(가장 흔한 함정).
4. **config 재생성** — OAuth client가 채워진다. 현재 `google-services.json`은 `oauth_client: []`이고
   `GoogleService-Info.plist`에는 `CLIENT_ID`/`REVERSED_CLIENT_ID`가 없다:
   ```bash
   ! flutterfire configure
   ```
   확인: `google-services.json`의 `oauth_client`에 `client_type: 3`(web) 항목이 있어야
   `google_sign_in`이 Android에서 idToken을 받는다. plist에 `REVERSED_CLIENT_ID`가 생겼는지도 확인.
5. **iOS Sign in with Apple**
   - Apple Developer → Identifiers → App ID `com.bouncetower.bounceTower`에 Sign in with Apple 켜기
   - Xcode `Runner` 타겟 → Signing & Capabilities → **+ Sign in with Apple**
     (`ios/Runner/Runner.entitlements`가 생성된다 — 현재 entitlements 파일 없음)
   - `Info.plist`에 Google용 `CFBundleURLTypes` → `CFBundleURLSchemes`에 plist의 `REVERSED_CLIENT_ID` 등록
6. **(2차, Android Apple 로그인)** Apple Developer에 Services ID 생성 + Sign in with Apple Key(.p8) 발급 →
   Firebase 콘솔 Apple provider에 Services ID·Team ID·Key ID·Key 입력 →
   Services ID의 Return URL에 `https://bounce-tower.firebaseapp.com/__/auth/handler` 등록.
7. **스토어 정책** (코드 아님, 제출 전 확인)
   - App Store 4.8: iOS에서 Google 로그인을 제공하면 Apple 로그인 필수 → 둘 다 넣으므로 충족
   - App Store 5.1.1(v) / Play 정책: 계정 생성 지원 시 **인앱 계정 삭제 필수**. Apple은 토큰 revoke까지 요구
   - 개인정보처리방침에 "로그인 식별자(Google/Apple 사용자 ID)" 추가, App Privacy / Data Safety에 User ID 신고

### 코드 현황 — ✅ 완료 (2026-09-02)

아래 항목은 전부 코드에 들어갔다. **선행 설정이 끝나기 전**에는 연결 버튼을 눌러도
"로그인 설정이 아직 준비되지 않았어요"만 뜨고(`not-configured`) 나머지 게임·랭킹·세이브는 영향 없다.

- ✅ `pubspec.yaml` `google_sign_in ^7.2.0` (Firebase 세대 변동 없음 — core 4.14.0 / auth 6.6.1 유지)
- ✅ `ios/Podfile.lock` 재생성 — GoogleSignIn 9.2.0이 `GTMSessionFetcher/Core ~> 3.3`을 요구해 5.3.1과 충돌했고,
  락파일을 지우고 재해결하니 3.5.0으로 정리됐다(FirebaseAuth 12.18.0은 `>= 3.4 < 6.0`이라 호환). 위 파드 절차 그대로.
- ✅ `ios/Runner/Runner.entitlements`(Sign in with Apple) 생성 + `project.pbxproj` 3개 구성에 `CODE_SIGN_ENTITLEMENTS`
- ✅ `lib/ranking.dart`: `init()` currentUser 우선 · uid 동적 조회 · `linkAccount` / `signOut` / `deleteAccount` · already-in-use 고아 삭제 후 전환
- ✅ `lib/main.dart` 브리지 4종, `firestore.rules` 본인 `delete` 3곳(**재배포는 아직**)
- ✅ 웹: 계정 모달(`#acctmodal`), `cloudResync()`, 홈 칩 👤/☁️/🔗, 랭킹·닉 모달 진입점, 권유 1회(`SAVE.linkPrompted`), 삭제 2단계
- ✅ 검증: `flutter analyze` 0건, Android debug APK 빌드 성공, 목 브리지 브라우저 테스트(연결→전환 병합→삭제→권유) 통과
- ✅ `Info.plist` `CFBundleURLTypes` = `REVERSED_CLIENT_ID` (2026-09-17, 설정 재생성 후 등록)
- ✅ 순수 코드 작업 **전부 완료**. 남은 건 키스토어·Play·Apple Developer 등 계정 쪽뿐

### 구현 메모 (설계 대비 확정 사항)

**패키지**
- `pubspec.yaml`: **`google_sign_in`(7.x)만 추가.** `sign_in_with_apple`은 넣지 않는다 —
  firebase_auth 내장 `AppleAuthProvider` + `linkWithProvider`가 iOS에서 네이티브로 처리한다(nonce 자동).
- 7.x API: `GoogleSignIn.instance.initialize()` → `authenticate()` → `authentication.idToken`
  → `GoogleAuthProvider.credential(idToken: ...)`. 6.x의 `signIn()`은 없다. accessToken 불필요.
- ⚠️ 추가 직후 iOS `Podfile.lock` 충돌은 위 "Firebase 패키지를 추가할 때마다 iOS 파드가 깨진다" 절차로.

**`lib/ranking.dart` — 연결 기능보다 먼저 고칠 것**
- `init()`: `FirebaseAuth.instance.currentUser`가 있으면 재사용, **없을 때만** `signInAnonymously()`.
  현재처럼 매 실행 익명 로그인을 부르면 연결된 사용자가 **로그아웃되고 새 익명 uid가 발급**된다
  (Firebase SDK 문서 명시). 이 한 줄이 빠지면 연결이 앱 재시작마다 풀린다.
- `_uid` 캐시 제거 → `currentUser?.uid` 동적 조회(연결·전환 뒤 옛 uid로 쓰는 것 방지)

**연결 / 전환 / 삭제**
- `linkGoogle()` / `linkApple()`: `currentUser.linkWithCredential` / `linkWithProvider(AppleAuthProvider())`.
  비익명 사용자에게도 허용(한 계정에 두 provider).
- `credential-already-in-use`: **현재 uid 문서 삭제 → `signInWithCredential` 전환** 순서. 상세는 설계 문서 2-1.
- `deleteAccount()`: 재인증 → (Apple) `revokeTokenWithAuthorizationCode` →
  `users`/`scores`/`seasons/S0..S현재` 삭제 → `user.delete()`
- `signOut()`: 로그아웃 → 새 익명. 이전 계정 문서는 두고 감.

**`firestore.rules`** — 본인 문서 `delete` 허용 3곳(`scores`, `seasons/*/scores`, `users`) + **재배포**(4장).

**브리지(`lib/main.dart`)**: `linkAccount(provider)` → `{ok, switched, providers, error}`,
`signOut()`, `deleteAccount()`, `getAccountState()` 확장 `{…, isAnonymous, providers}`.

**웹(`assets/www/index.html`)**: 계정 모달, `cloudResync()`(연결·전환·삭제 뒤
`cloudLoad`→`mergeCloud`→`save`→`submitScoreNative`→`refreshMeta`), 홈 칩 ☁️ → 연결됨 배지,
권유 트리거 1회, 삭제 2단계 확인.

**e2e(실기기, 선행 설정 후)**: 재설치 복원 / 두 기기 충돌 병합 / **앱 재시작 후 연결 유지** / 삭제 후 재연결 /
Play 내부테스트 트랙에서 Google 로그인(App Signing SHA 검증).

### 선행 설정 후 확인 순서
1. 4장 규칙 재배포(`delete` 규칙) → 2. 4단계 `flutterfire configure` → 3. `Info.plist` URL scheme →
4. iOS `rm Podfile.lock && pod install`(plist 변경 후 필요 시) → 5. 실기기에서 홈 칩 → 닉 모달 → "계정 연결"로 e2e.
