# 광고 브리지 규격 (JS ↔ Flutter) — 업무 #18

웹 게임(`assets/www/index.html`)과 Flutter(`lib/main.dart`, `lib/ads.dart`, `lib/ad_policy.dart`)
사이의 **광고 관련** 메시지만 정리한다. 랭킹·계정·세이브 브리지는 `README.md` 표 참고.

## 1. PRD 3.3 규격과의 관계 (기존 브리지 우선)

PRD 3.3은 `runId`가 붙은 새 메시지(`game_over`, `continue_granted`, `restart` …)를 제안했지만,
이미 출시 준비가 된 **Promise 기반 브리지**가 있어서 새 규격을 따로 만들지 않고 기존 규격에 맞췄다.
새 메시지를 추가하면 같은 동작을 두 경로가 처리하게 되어 중복 보상 위험이 오히려 커진다.

| PRD 개념 | 현재 구현 |
|---|---|
| `runId`별 이어하기 최대 1회 | 웹 `reviveUsed`(판마다 `startGame`에서 초기화) + 콜백 안에서 한 번 더 확인 |
| `continue_granted` (보상 확정) | `callHandler('showRewarded')` Promise가 `true`로 resolve. `onUserEarnedReward`를 받은 경우에만 `true` |
| 중복 보상 차단(양쪽) | 웹: `adInFlight`이면 재호출 무시 · Flutter: `_rewardedInFlight`이면 `false` 반환, 결과는 `Completer`로 1회만 전달 |
| `pause` / `resume` | Flutter → 웹 `window.btAdPause()` / `window.btAdResume()` (광고 표시 직전 / 닫힌 직후) |
| `restart` / `go_home` | 웹 `retryBtn` / `homeBtn` → `showInterstitialThen(cb)` → 광고가 닫힌 뒤 `cb` |
| 게임 오버 오버레이 | 기존 웹 `#over` 화면 유지(Flutter 오버레이로 옮기지 않음) |

## 2. 메시지

| 방향 | 이름 | 인자 → 반환 | 의미 |
|---|---|---|---|
| JS→Flutter | `isRewardedReady` | → `bool` | 게임 오버 때 호출. `false`면 광고 버튼(부활·코인 2배)을 **숨긴다** |
| JS→Flutter | `showRewarded` | `placement`(`revive`\|`coin_double`) → `true`\|`false`\|`'noad'` | `true`=끝까지 시청(보상) · `false`=중도 종료/중복 호출(보상 없음) · `'noad'`=광고 없음/표시 실패(**보상 없음**, 버튼 숨김) |
| JS→Flutter | `showInterstitial` | → `null`(광고가 닫힌 뒤 resolve) | 웹이 판수 조건(첫 N판·M판마다·이어하기 한 판 제외)을 통과했을 때만 호출. Flutter `AdPolicy`가 첫 세션·180초 쿨다운·미로드를 최종 판단 |
| JS→Flutter | `privacyOptionsRequired` | → `bool` | UMP 동의 대상 지역이면 계정 모달에 "광고 개인정보 설정" 노출 |
| JS→Flutter | `showPrivacyOptions` | → `null` | UMP 동의 다시 설정 폼 |
| JS→Flutter | `logEvent` | `name, params` | `continue_offered` / `continue_used` / `continue_declined` 등 |
| Flutter→JS | `window.btAdPause()` | — | 오디오 suspend, 플레이 중이면 `paused` |
| Flutter→JS | `window.btAdResume()` | — | 오디오 resume, 광고 때문에 멈춘 경우만 `playing` 복귀 |

> 변경 전에는 `'noad'`(광고 없음·표시 실패)도 보상을 지급했다. 이제는 지급하지 않는다(PRD F-B1).

## 3. 시퀀스

```
[플레이] --사망--> gameOver()
   ├─ isRewardedReady() → true면 [광고 보고 부활]·[코인 2배] 표시 (+continue_offered)
   │                      false면 버튼 숨김
   ├─ [광고 보고 부활] → showRewarded('revive')
   │     btAdPause → 광고 → 닫힘 → AdPolicy.recordFullscreenClosed → btAdResume
   │     ├─ true   → reviveUsed=true, 이어서 플레이 (+continue_used)
   │     ├─ false  → 토스트 "끝까지 봐야…", 버튼 유지
   │     └─ 'noad' → 토스트 "광고를 불러오지 못했어요", 버튼 숨김
   ├─ [다시 하기] → (continue_declined) commitRun → showInterstitialThen(startGame)
   └─ [홈]       → (continue_declined) commitRun → showInterstitialThen(home)

showInterstitialThen:
  웹 shouldShowInterstitial() (첫 N판 아님 · M판 경과 · reviveUsed 아님)
     └─ 통과 → showInterstitial → AdPolicy.checkInterstitial
           ├─ first_session / cooldown / not_loaded → ad_skipped 기록, 즉시 resolve
           └─ 통과 → btAdPause → 광고 → 닫힘 → btAdResume → resolve → 다음 화면
```

## 4. 광고 정책 게이트 (`lib/ad_policy.dart`)

- 세션: 콜드 스타트, 또는 백그라운드 30분 이상 후 복귀. 첫 세션에는 전면 광고 없음.
- 전면 쿨다운: 전면 **또는 보상형** 광고가 닫힌 시각부터 180초. Remote Config `interstitial_gap_sec`은 180~600 범위로 클램프되고, `AdPolicy`도 180초 미만을 한 번 더 무시한다.
- 미로드: 기다리지 않고 건너뛴다.
- 시계 역행: 쿨다운 중으로 보고 기준 시각을 현재로 재설정한다.
- 저장 키: `ad_session_count`, `ad_last_background_at`, `ad_last_fullscreen_closed_at`.
- 계측: `ad_request`, `ad_loaded`, `ad_load_failed`, `ad_impression`, `ad_show_failed`, `ad_skipped(reason)` → Firebase Analytics(`AnalyticsService`).
