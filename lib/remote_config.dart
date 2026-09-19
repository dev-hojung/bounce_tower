import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Firebase Remote Config — 앱 업데이트 없이 밸런스·광고 빈도·이벤트를 조정한다.
///
/// Firebase 미설정/오프라인/콘솔 미등록 어느 경우에도 [_defaults]가 그대로 쓰이므로
/// 게임 동작은 항상 보장된다. 원격 값은 [_clamp]로 안전 범위를 강제해서, 콘솔에
/// 잘못된 값을 넣어도 게임이 망가지지 않게 한다.
class RemoteConfigService {
  /// 원격 미설정 시 사용할 기본값. 값의 **런타임 타입이 파싱 기준**이므로
  /// (int/double/bool) 타입을 바꿀 때는 [_coerce]도 함께 확인할 것.
  static const Map<String, dynamic> _defaults = {
    'interstitial_gap_sec': 45, // 전면광고 최소 간격(초) — 판수 정책 위의 백스톱
    'interstitial_every_runs': 3, // 전면광고를 M판마다 1회
    'first_runs_no_ads': 3, // 첫 N판은 전면광고 없음(첫인상 보호)
    'danger_max': 0.42, // 최대 위험 발판 비율 — 웹 P.dangerMax
    'rage_combo': 5, // RAGE(무적) 발동 콤보 수
    'coin_mult': 1.0, // 코인 획득 배율(이벤트용)
    'season_enabled': true, // 시즌 랭킹 탭 노출
    'season_goal': 60, // 시즌 한정 스킨 해금 점수
  };

  /// 각 키의 허용 범위 (min, max). bool·미등재 키는 클램프하지 않는다.
  static const Map<String, List<num>> _bounds = {
    'interstitial_gap_sec': [15, 600],
    'interstitial_every_runs': [1, 20],
    'first_runs_no_ads': [0, 50],
    'danger_max': [0.0, 0.8],
    'rage_combo': [2, 30],
    'coin_mult': [0.5, 10.0],
    'season_goal': [10, 100000],
  };

  final Map<String, dynamic> _values = Map<String, dynamic>.from(_defaults);

  /// 원격 값 적용에 성공했는지(디버깅·로깅용).
  bool activated = false;

  /// **[Firebase.initializeApp] 이후**에 호출할 것 — `RankingService.init()` 다음.
  Future<void> init() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await rc.setDefaults(_defaults);
      await rc.fetchAndActivate();
      for (final key in _defaults.keys) {
        _values[key] = _clamp(key, _coerce(_defaults[key], rc.getValue(key)));
      }
      activated = true;
    } catch (_) {
      // 미설정·오프라인·권한오류 → 기본값 유지(게임 정상 동작)
    }
  }

  /// 기본값의 타입에 맞춰 원격 값을 읽는다.
  static dynamic _coerce(dynamic def, RemoteConfigValue v) {
    if (def is bool) return v.asBool();
    if (def is int) return v.asInt();
    if (def is double) return v.asDouble();
    return v.asString();
  }

  /// 콘솔 오입력 방어. 범위 밖이면 잘라내고, 타입이 어긋나면 기본값으로 되돌린다.
  static dynamic _clamp(String key, dynamic value) {
    final b = _bounds[key];
    if (b == null || value is! num) return value;
    final clamped = value.clamp(b[0], b[1]);
    return _defaults[key] is int ? clamped.round() : clamped.toDouble();
  }

  int _int(String k) => (_values[k] as num).round();
  double _double(String k) => (_values[k] as num).toDouble();

  /// 전면광고 최소 간격 — [AdManager.interstitialMinGap]에 주입한다.
  Duration get interstitialGap => Duration(seconds: _int('interstitial_gap_sec'));

  bool get seasonEnabled => _values['season_enabled'] == true;

  /// 웹(JS)으로 넘길 게임 밸런스 값. `getRemoteConfig` 브리지의 반환 형태이며,
  /// 키 이름은 `index.html`의 `applyRemoteConfig()`와 짝이다.
  ///
  /// `ready`는 원격 값 적용 완료 신호 — 웹은 이게 true가 될 때까지 폴링한다
  /// (init()이 Firebase 초기화 뒤에 끝나므로 웹이 먼저 물어볼 수 있다).
  Map<String, dynamic> toJson() => {
        'ready': activated,
        'dangerMax': _double('danger_max'),
        'rageCombo': _int('rage_combo'),
        'coinMult': _double('coin_mult'),
        'seasonEnabled': seasonEnabled,
        'seasonGoal': _int('season_goal'),
        'interstitialEveryRuns': _int('interstitial_every_runs'),
        'firstRunsNoAds': _int('first_runs_no_ads'),
      };
}
