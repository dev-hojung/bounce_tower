import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics + Crashlytics.
///
/// Firebase 초기화 이후에 [init]을 호출한다. 실패하면 [enabled]=false로 남고
/// 모든 기록이 조용히 무시된다 — 지표 수집 실패가 게임 동작을 막지 않도록.
class AnalyticsService {
  bool enabled = false;
  FirebaseAnalytics? _analytics;

  /// 크래시 핸들러는 **runApp 이전에** 걸어야 초기 프레임 예외도 잡힌다.
  Future<void> init() async {
    try {
      _analytics = FirebaseAnalytics.instance;

      // Flutter 프레임워크 내부 에러
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      // 프레임워크 밖(비동기·isolate) 에러
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      enabled = true;
    } catch (_) {
      enabled = false;
    }
  }

  /// 웹(JS)에서 넘어온 이벤트를 기록한다.
  ///
  /// Firebase의 이름 규칙(영문으로 시작, 영숫자·`_`, 40자 이내)을 어기면
  /// SDK가 예외를 던지므로 여기서 걸러낸다. 파라미터 값은 String/num만
  /// 허용되므로 bool은 0/1로, 그 외는 문자열로 변환한다.
  Future<void> logEvent(String name, Map<String, dynamic> raw) async {
    final a = _analytics;
    if (!enabled || a == null || !_validName(name)) return;

    final params = <String, Object>{};
    raw.forEach((k, v) {
      if (v == null || !_validName(k)) return;
      if (v is num) {
        params[k] = v;
      } else if (v is bool) {
        params[k] = v ? 1 : 0;
      } else {
        // 문자열 파라미터는 100자 제한
        final s = v.toString();
        params[k] = s.length > 100 ? s.substring(0, 100) : s;
      }
    });

    try {
      await a.logEvent(
          name: name, parameters: params.isEmpty ? null : params);
    } catch (_) {
      // 기록 실패는 무시 — 게임 흐름에 영향 없음
    }
  }

  static final RegExp _nameRe = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$');
  static bool _validName(String s) => _nameRe.hasMatch(s);
}
