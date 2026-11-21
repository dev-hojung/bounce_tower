import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광고 정책 게이트 (업무 #18 PRD 1장 공통 규격).
///
/// ⚠️ 이 파일은 Strike Log(`lib/core/services/ad_policy.dart`)와 **같은 내용**을
/// 유지한다. 규칙을 바꾸면 두 앱을 함께 고칠 것.
///
/// 규칙
/// - 세션: 콜드 스타트 1회 또는 백그라운드 30분 이상 후 복귀 = 새 세션.
/// - 첫 세션(`sessionCount <= 1`)에는 전면 광고 없음.
/// - 전면/보상형 광고가 **닫힌 시각**부터 최소 180초 동안 전면 광고 없음.
///   원격 설정으로 더 길게는 바꿀 수 있지만 180초 미만은 무시한다.
/// - 미리 로드된 광고가 없으면 기다리지 않고 건너뛴다.
/// - 기기 시계가 과거로 돌아가면 쿨다운이 안 지난 것으로 보고 기준 시각을 지금으로 맞춘다.
class AdPolicy {
  AdPolicy(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  static const Duration minCooldown = Duration(seconds: 180);
  static const Duration sessionTimeout = Duration(minutes: 30);

  /// QA용 단축 쿨다운(디버그 빌드에서만 적용).
  static const Duration debugShortCooldown = Duration(seconds: 10);

  static const String kSessionCount = 'ad_session_count';
  static const String kLastBackgroundAt = 'ad_last_background_at';
  static const String kLastFullscreenClosedAt = 'ad_last_fullscreen_closed_at';

  Duration _cooldown = minCooldown;

  /// 디버그 전용 옵션. release 빌드에서는 값을 넣어도 무시된다.
  bool debugUseShortCooldown = false;
  int? debugSessionOverride;

  static bool get _debugAllowed => !kReleaseMode;

  /// 원격 설정 등으로 쿨다운을 바꾼다. 180초 미만은 180초로 올린다.
  set cooldown(Duration d) => _cooldown = d < minCooldown ? minCooldown : d;

  Duration get cooldown {
    if (_debugAllowed && debugUseShortCooldown) return debugShortCooldown;
    return _cooldown;
  }

  int get sessionCount {
    if (_debugAllowed && debugSessionOverride != null) {
      return debugSessionOverride!;
    }
    return _prefs.getInt(kSessionCount) ?? 0;
  }

  bool get isFirstSession => sessionCount <= 1;

  DateTime? _readTime(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _writeTime(String key, DateTime t) =>
      _prefs.setInt(key, t.millisecondsSinceEpoch);

  /// 앱 콜드 스타트 시 1회 호출.
  Future<void> onColdStart() async {
    await _prefs.setInt(kSessionCount, (_prefs.getInt(kSessionCount) ?? 0) + 1);
    await _prefs.remove(kLastBackgroundAt);
  }

  /// 앱이 백그라운드로 갈 때 호출.
  Future<void> onBackground() => _writeTime(kLastBackgroundAt, _clock());

  /// 앱이 포그라운드로 돌아올 때 호출. 30분 이상 떠나 있었으면 새 세션.
  Future<void> onForeground() async {
    final bg = _readTime(kLastBackgroundAt);
    await _prefs.remove(kLastBackgroundAt);
    if (bg == null) return;
    final away = _clock().difference(bg);
    if (away >= sessionTimeout) {
      await _prefs.setInt(
          kSessionCount, (_prefs.getInt(kSessionCount) ?? 0) + 1);
    }
  }

  /// 남은 쿨다운. 0이면 표시 가능. 시계 역행 시 기준 시각을 지금으로 다시 맞춘다.
  Future<Duration> remainingCooldown() async {
    final last = _readTime(kLastFullscreenClosedAt);
    if (last == null) return Duration.zero;
    final now = _clock();
    if (now.isBefore(last)) {
      await _writeTime(kLastFullscreenClosedAt, now);
      return cooldown;
    }
    final passed = now.difference(last);
    return passed >= cooldown ? Duration.zero : cooldown - passed;
  }

  /// 전면 광고를 띄워도 되는지 판단한다. `null`이면 표시 가능, 아니면 건너뛴 이유.
  Future<AdSkipReason?> checkInterstitial({required bool loaded}) async {
    if (isFirstSession) return AdSkipReason.firstSession;
    if (await remainingCooldown() > Duration.zero) return AdSkipReason.cooldown;
    if (!loaded) return AdSkipReason.notLoaded;
    return null;
  }

  /// 전면 또는 보상형 광고가 닫혔을 때 호출(쿨다운 기준 시각).
  Future<void> recordFullscreenClosed() =>
      _writeTime(kLastFullscreenClosedAt, _clock());

  /// 디버그: 쿨다운 기록 초기화.
  Future<void> debugResetCooldown() async {
    if (!_debugAllowed) return;
    await _prefs.remove(kLastFullscreenClosedAt);
  }
}

enum AdSkipReason {
  firstSession('first_session'),
  cooldown('cooldown'),
  notLoaded('not_loaded');

  const AdSkipReason(this.code);
  final String code;
}

/// 광고 이벤트 한 건 (개인정보 없음: 형식·지점·오류 코드만).
class AdEvent {
  AdEvent(this.name, this.params, this.at);
  final String name;
  final Map<String, Object> params;
  final DateTime at;

  @override
  String toString() => '$name $params';
}

/// 광고 계측(PRD F-S1/F-B4). 최근 50건을 메모리에 남기고, [sink]가 있으면
/// Analytics 등으로도 보낸다. 이벤트 이름은 PRD 규격을 따른다.
class AdEventLog {
  AdEventLog({this.capacity = 50});

  final int capacity;
  final List<AdEvent> _events = [];

  /// 외부 전송(예: Firebase Analytics). 실패해도 앱 흐름에 영향이 없어야 한다.
  void Function(String name, Map<String, Object> params)? sink;

  /// 최신순.
  List<AdEvent> get events => List.unmodifiable(_events.reversed);

  void log(String name, Map<String, Object> params) {
    _events.add(AdEvent(name, params, DateTime.now()));
    if (_events.length > capacity) _events.removeAt(0);
    try {
      sink?.call(name, params);
    } catch (_) {}
  }

  void clear() => _events.clear();
}
