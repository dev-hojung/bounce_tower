import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob 전면/보상형 광고 관리.
///
/// ⚠️ 현재는 Google 공식 **테스트 광고 ID**를 사용한다. 실제 출시 전
/// [_AdUnits]의 ID를 본인의 AdMob 계정 광고단위로 교체하고, AndroidManifest /
/// Info.plist의 App ID도 함께 교체할 것. (테스트 ID 외 실광고를 개발 중 클릭하면
/// 계정 정지 위험)
class AdManager {
  AdManager();

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  bool _interstitialLoading = false;
  bool _rewardedLoading = false;

  /// 광고 제거(IAP) 구매 시 true. 전면 광고를 건너뛴다.
  bool adFree = false;

  /// 전면 광고 빈도 제한(연속 노출 방지). 마지막 노출 시각.
  DateTime? _lastInterstitial;

  /// 전면 광고 최소 간격. Remote Config(`interstitial_gap_sec`)가 덮어쓴다.
  Duration interstitialMinGap = const Duration(seconds: 45);

  void preloadAll() {
    _loadInterstitial();
    _loadRewarded();
  }

  // ───────────────────────── 전면(Interstitial) ─────────────────────────

  void _loadInterstitial() {
    if (_interstitial != null || _interstitialLoading) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
          // fullScreenContentCallback은 노출 시점(maybeShowInterstitial)에
          // 붙인다 — 닫힘을 Future로 알려야 하기 때문.
        },
        onAdFailedToLoad: (err) {
          _interstitialLoading = false;
          _interstitial = null;
        },
      ),
    );
  }

  /// 빈도 제한·adFree를 고려해 전면 광고를 노출(가능할 때만).
  ///
  /// 반환 Future는 **광고가 닫힌 뒤** 완료된다. 노출하지 않은 경우(adFree,
  /// 빈도제한, 미준비)에는 즉시 완료. 웹은 이걸 기다렸다가 다음 판을 시작해야
  /// 광고가 이미 진행 중인 게임을 덮지 않는다.
  ///
  /// 판수 기반 빈도 제어(첫 N판 무광고, M판마다 1회)는 세이브 데이터를 쥔
  /// **웹이 판단**하고, 여기 시간 간격은 그 위에 얹는 백스톱이다.
  Future<void> maybeShowInterstitial() {
    if (adFree) return Future.value();
    final now = DateTime.now();
    if (_lastInterstitial != null &&
        now.difference(_lastInterstitial!) < interstitialMinGap) {
      return Future.value();
    }
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return Future.value();
    }
    _lastInterstitial = now;
    _interstitial = null; // 아래 콜백에서 재로드

    final completer = Completer<void>();
    void finish(InterstitialAd a) {
      a.dispose();
      _loadInterstitial(); // 다음 노출 대비 재로드
      if (!completer.isCompleted) completer.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (a, err) => finish(a),
    );
    ad.show();
    return completer.future;
  }

  // ───────────────────────── 보상형(Rewarded) ─────────────────────────

  void _loadRewarded() {
    if (_rewarded != null || _rewardedLoading) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: _AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (err) {
          _rewardedLoading = false;
          _rewarded = null;
        },
      ),
    );
  }

  /// 보상형 광고를 노출하고 결과를 반환한다.
  /// - `true`   : 보상 획득 완료
  /// - `false`  : 사용자가 중도 종료(보상 없음)
  /// - `'noad'` : 광고 미준비 → 게임 흐름을 막지 않도록 호출측에서 지급 처리
  Future<dynamic> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return 'noad';
    }
    _rewarded = null;

    final completer = Completer<dynamic>();
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded(); // 다음 보상형 대비 재로드
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loadRewarded();
        // 표시 실패: 게임 흐름 막지 않도록 지급
        if (!completer.isCompleted) completer.complete('noad');
      },
    );

    ad.show(onUserEarnedReward: (ad, reward) {
      earned = true;
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

/// 광고 단위 ID. 현재는 Google 공식 테스트 ID.
class _AdUnits {
  static String get interstitial => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  static String get rewarded => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';
}
