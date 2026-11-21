import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_policy.dart';

/// AdMob 전면/보상형 광고 관리.
///
/// ⚠️ 현재는 Google 공식 **테스트 광고 ID**를 사용한다. 실제 출시 전
/// [_AdUnits]의 release ID를 AdMob 계정 광고단위로 채우고(대표 승인 A2),
/// AndroidManifest / Info.plist의 App ID도 함께 교체할 것.
/// debug/profile 빌드는 release ID와 상관없이 **항상 테스트 ID**를 쓴다.
///
/// 정책(업무 #18): 전면 광고는 [AdPolicy] 게이트(첫 세션 금지, 180초 쿨다운,
/// 미로드 시 대기 없이 건너뜀)를 통과해야 한다. 보상형 광고는 사용자가 버튼을
/// 눌렀을 때만 호출되며, 광고를 끝까지 봤을 때만 보상한다. 브리지 규격은
/// `docs/bridge.md` 참고.
class AdManager {
  AdManager({AdEventLog? log}) : log = log ?? AdEventLog();

  final AdEventLog log;

  /// 앱 시작 시 SharedPreferences가 준비되면 주입한다. 없으면 전면 광고를
  /// 띄우지 않는다(정책을 확인할 수 없으므로 안전한 쪽).
  AdPolicy? policy;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  bool _interstitialLoading = false;
  bool _rewardedLoading = false;

  /// 보상형 광고가 화면에 떠 있는 동안 true. 연타·중복 호출로 보상이
  /// 두 번 처리되는 것을 막는다.
  bool _rewardedInFlight = false;

  /// UMP 동의 결과 광고 요청이 가능할 때만 true.
  bool canRequestAds = false;

  /// 광고 제거(IAP) 구매 시 true. 전면 광고를 건너뛴다. (dormant)
  bool adFree = false;

  /// 광고가 화면을 덮기 직전/닫힌 직후 호출 — 웹 게임 루프·사운드 정지/재개용.
  VoidCallback? onFullscreenShow;
  VoidCallback? onFullscreenHide;

  void preloadAll() {
    if (!canRequestAds) return;
    _loadInterstitial();
    _loadRewarded();
  }

  /// UMP 동의(EEA·영국). 동의 절차가 끝난 뒤에만 광고를 요청한다.
  /// 실패해도 앱은 계속 동작하며, SDK가 광고 요청 가능 여부를 알려준다.
  Future<void> gatherConsent() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? e) {
          if (!done.isCompleted) done.complete();
        });
      },
      (FormError e) {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    try {
      canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      canRequestAds = false;
    }
  }

  /// 설정 화면의 "광고 동의 다시 설정" 노출 여부.
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? e) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    canRequestAds = await ConsentInformation.instance.canRequestAds();
    preloadAll();
  }

  // ───────────────────────── 전면(Interstitial) ─────────────────────────

  void _loadInterstitial() {
    if (!canRequestAds) return;
    if (_interstitial != null || _interstitialLoading) return;
    _interstitialLoading = true;
    final started = DateTime.now();
    log.log('ad_request', {'format': 'interstitial', 'placement': 'game_over'});
    InterstitialAd.load(
      adUnitId: _AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
          log.log('ad_loaded', {
            'format': 'interstitial',
            'placement': 'game_over',
            'latency_ms': DateTime.now().difference(started).inMilliseconds,
          });
        },
        onAdFailedToLoad: (err) {
          _interstitialLoading = false;
          _interstitial = null;
          log.log('ad_load_failed', {
            'format': 'interstitial',
            'placement': 'game_over',
            'error_code': err.code,
            'error_domain': err.domain,
          });
        },
      ),
    );
  }

  /// 정책 게이트를 통과하면 전면 광고를 노출한다.
  ///
  /// 반환 Future는 **광고가 닫힌 뒤** 완료된다. 노출하지 않은 경우에는 즉시 완료.
  /// 웹은 이걸 기다렸다가 다음 판을 시작해야 광고가 진행 중인 게임을 덮지 않는다.
  /// 판수 기반 빈도(첫 N판 무광고, M판마다 1회)는 웹이 먼저 판단하고, 여기서는
  /// 세션·시간 규칙을 최종적으로 건다.
  Future<void> maybeShowInterstitial({String placement = 'game_over'}) async {
    if (adFree) return;
    final p = policy;
    final ad = _interstitial;
    final reason = p == null
        ? AdSkipReason.firstSession
        : await p.checkInterstitial(loaded: ad != null);
    if (reason != null || ad == null) {
      log.log('ad_skipped', {
        'format': 'interstitial',
        'placement': placement,
        'reason': (reason ?? AdSkipReason.notLoaded).code,
      });
      if (ad == null) _loadInterstitial();
      return;
    }
    _interstitial = null; // 아래 콜백에서 재로드

    final completer = Completer<void>();
    void finish(InterstitialAd a) {
      a.dispose();
      onFullscreenHide?.call();
      _loadInterstitial(); // 다음 노출 대비 재로드
      if (!completer.isCompleted) completer.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdImpression: (_) => log.log(
          'ad_impression', {'format': 'interstitial', 'placement': placement}),
      onAdDismissedFullScreenContent: (a) {
        p!.recordFullscreenClosed();
        finish(a);
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        log.log('ad_show_failed', {
          'format': 'interstitial',
          'placement': placement,
          'error_code': err.code,
        });
        finish(a);
      },
    );
    onFullscreenShow?.call();
    ad.show();
    return completer.future;
  }

  // ───────────────────────── 보상형(Rewarded) ─────────────────────────

  void _loadRewarded() {
    if (!canRequestAds) return;
    if (_rewarded != null || _rewardedLoading) return;
    _rewardedLoading = true;
    final started = DateTime.now();
    log.log('ad_request', {'format': 'rewarded', 'placement': 'game_over'});
    RewardedAd.load(
      adUnitId: _AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewarded = ad;
          log.log('ad_loaded', {
            'format': 'rewarded',
            'placement': 'game_over',
            'latency_ms': DateTime.now().difference(started).inMilliseconds,
          });
        },
        onAdFailedToLoad: (err) {
          _rewardedLoading = false;
          _rewarded = null;
          log.log('ad_load_failed', {
            'format': 'rewarded',
            'placement': 'game_over',
            'error_code': err.code,
            'error_domain': err.domain,
          });
        },
      ),
    );
  }

  /// 보상형 버튼을 보여줘도 되는지(광고가 로드돼 있는지). 웹이 게임 오버 때 묻는다.
  /// 로드돼 있지 않으면 재로드를 걸고 false.
  bool isRewardedReady() {
    if (_rewarded == null) _loadRewarded();
    return _rewarded != null && !_rewardedInFlight;
  }

  /// 보상형 광고를 노출하고 결과를 반환한다.
  /// - `true`   : 끝까지 시청해 보상 확정(`onUserEarnedReward`)
  /// - `false`  : 중도 종료 또는 이미 다른 보상형 광고가 진행 중 → 보상 없음
  /// - `'noad'` : 광고 미준비/표시 실패 → **보상 없음**(무료 지급하지 않는다)
  Future<dynamic> showRewarded({String placement = 'revive'}) async {
    if (_rewardedInFlight) return false;
    final ad = _rewarded;
    if (ad == null) {
      log.log('ad_skipped',
          {'format': 'rewarded', 'placement': placement, 'reason': 'not_loaded'});
      _loadRewarded();
      return 'noad';
    }
    _rewarded = null;
    _rewardedInFlight = true;

    final completer = Completer<dynamic>();
    bool earned = false;

    void finish(RewardedAd a, dynamic result) {
      a.dispose();
      _rewardedInFlight = false;
      onFullscreenHide?.call();
      _loadRewarded(); // 다음 보상형 대비 재로드
      if (!completer.isCompleted) completer.complete(result);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdImpression: (_) => log.log(
          'ad_impression', {'format': 'rewarded', 'placement': placement}),
      onAdDismissedFullScreenContent: (a) {
        // 보상형도 전면 쿨다운에 포함(PRD F-B2).
        policy?.recordFullscreenClosed();
        finish(a, earned);
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        log.log('ad_show_failed', {
          'format': 'rewarded',
          'placement': placement,
          'error_code': err.code,
        });
        finish(a, 'noad');
      },
    );

    onFullscreenShow?.call();
    ad.show(onUserEarnedReward: (ad, reward) {
      earned = true; // 여러 번 와도 결과는 한 번만 전달된다(completer)
    });

    return completer.future;
  }

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _interstitial = null;
    _rewarded = null;
  }
}

/// 광고 단위 ID. debug/profile 빌드는 항상 Google 공식 테스트 ID.
/// release 값은 대표 승인(A2) 전까지 테스트 ID 그대로 둔다.
class _AdUnits {
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  // TODO(A2, 대표 승인 후): 실제 광고 단위 ID로 교체.
  static const _releaseInterstitialAndroid = _testInterstitialAndroid;
  static const _releaseInterstitialIos = _testInterstitialIos;
  static const _releaseRewardedAndroid = _testRewardedAndroid;
  static const _releaseRewardedIos = _testRewardedIos;

  static String get interstitial => !kReleaseMode
      ? (Platform.isAndroid ? _testInterstitialAndroid : _testInterstitialIos)
      : (Platform.isAndroid
          ? _releaseInterstitialAndroid
          : _releaseInterstitialIos);

  static String get rewarded => !kReleaseMode
      ? (Platform.isAndroid ? _testRewardedAndroid : _testRewardedIos)
      : (Platform.isAndroid ? _releaseRewardedAndroid : _releaseRewardedIos);
}
