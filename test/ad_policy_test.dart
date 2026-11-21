// 광고 정책 게이트 단위 테스트 (업무 #18 QA 요청 2번).
// Strike Log test/ad_policy_test.dart 와 같은 케이스를 유지한다.

import 'package:bounce_tower/ad_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late SharedPreferences prefs;
  late AdPolicy policy;

  Future<AdPolicy> make({Map<String, Object> init = const {}}) async {
    SharedPreferences.setMockInitialValues(init);
    prefs = await SharedPreferences.getInstance();
    return AdPolicy(prefs, clock: () => now);
  }

  setUp(() async {
    now = DateTime(2026, 11, 21, 12);
    policy = await make();
  });

  test('첫 세션에는 전면 광고를 띄우지 않는다', () async {
    await policy.onColdStart();
    expect(policy.sessionCount, 1);
    expect(await policy.checkInterstitial(loaded: true),
        AdSkipReason.firstSession);
  });

  test('두 번째 콜드 스타트부터 표시 가능', () async {
    await policy.onColdStart();
    await policy.onColdStart();
    expect(await policy.checkInterstitial(loaded: true), isNull);
  });

  test('백그라운드 30분 이상 후 복귀는 새 세션, 29분은 같은 세션', () async {
    await policy.onColdStart();
    await policy.onBackground();
    now = now.add(const Duration(minutes: 29));
    await policy.onForeground();
    expect(policy.sessionCount, 1);

    await policy.onBackground();
    now = now.add(const Duration(minutes: 30));
    await policy.onForeground();
    expect(policy.sessionCount, 2);
  });

  test('광고 닫힘 후 179초는 쿨다운, 180초는 표시 가능', () async {
    await policy.onColdStart();
    await policy.onColdStart();
    await policy.recordFullscreenClosed();

    now = now.add(const Duration(seconds: 179));
    expect(await policy.checkInterstitial(loaded: true), AdSkipReason.cooldown);

    now = now.add(const Duration(seconds: 1));
    expect(await policy.checkInterstitial(loaded: true), isNull);
  });

  test('광고가 로드되지 않았으면 기다리지 않고 not_loaded로 건너뛴다', () async {
    await policy.onColdStart();
    await policy.onColdStart();
    expect(await policy.checkInterstitial(loaded: false),
        AdSkipReason.notLoaded);
    expect(AdSkipReason.notLoaded.code, 'not_loaded');
  });

  test('기기 시계가 과거로 돌아가면 쿨다운 중으로 보고 기준 시각을 재설정', () async {
    await policy.onColdStart();
    await policy.onColdStart();
    await policy.recordFullscreenClosed();

    now = now.subtract(const Duration(hours: 1));
    expect(await policy.checkInterstitial(loaded: true), AdSkipReason.cooldown);
    // 재설정된 시각 기준으로 180초 뒤에는 다시 가능
    now = now.add(const Duration(seconds: 180));
    expect(await policy.checkInterstitial(loaded: true), isNull);
  });

  test('원격 설정으로 180초 미만 쿨다운을 넣어도 180초가 유지된다', () async {
    policy.cooldown = const Duration(seconds: 60);
    expect(policy.cooldown, AdPolicy.minCooldown);
    policy.cooldown = const Duration(seconds: 300);
    expect(policy.cooldown, const Duration(seconds: 300));
  });

  test('세션 수는 재시작 후에도 유지된다(저장소 기반)', () async {
    await policy.onColdStart();
    final again = AdPolicy(prefs, clock: () => now);
    await again.onColdStart();
    expect(again.sessionCount, 2);
    expect(prefs.getInt(AdPolicy.kSessionCount), 2);
  });

  test('디버그 옵션: 10초 쿨다운·세션 강제 (테스트는 debug 모드)', () async {
    await policy.onColdStart();
    policy.debugSessionOverride = 3;
    policy.debugUseShortCooldown = true;
    await policy.recordFullscreenClosed();
    now = now.add(const Duration(seconds: 10));
    expect(await policy.checkInterstitial(loaded: true), isNull);
  });

  test('AdEventLog는 최근 50건만 최신순으로 보관한다', () {
    final log = AdEventLog();
    final sent = <String>[];
    log.sink = (name, _) => sent.add(name);
    for (var i = 0; i < 60; i++) {
      log.log('ad_request', {'format': 'interstitial', 'n': i});
    }
    expect(log.events.length, 50);
    expect(log.events.first.params['n'], 59);
    expect(sent.length, 60);
  });
}
