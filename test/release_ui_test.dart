// 업무 #53 QA 반영: 출시 빌드 디버그 UI 숨김 + 영어 기본/한국어 지원.
// 업무 #56: 네이티브 언어 리소스(Android localeConfig, iOS ATT 문구) 검사 추가.
// index.html의 한글 누락 검사는 i18n_strict_test.dart(괄호 짝 맞춤 방식)가 맡는다.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:bounce_tower/main.dart';
import 'package:bounce_tower/notifications.dart';

final _hangul = RegExp('[가-힣]');

void main() {
  group('gameUrl (튜닝 패널 노출 스위치)', () {
    test('debug 빌드에서만 ?dev=1이 붙는다', () {
      expect(gameUrl(debug: true), 'http://localhost:8080/index.html?dev=1');
    });
    test('profile·release 빌드는 dev 플래그 없이 연다', () {
      expect(gameUrl(debug: false), 'http://localhost:8080/index.html');
      expect(gameUrl(debug: false), isNot(contains('dev=')));
    });
  });

  group('WebView 터치 (#56 드래그 불능 회귀 방지)', () {
    // flutter_inappwebview_android는 disableVertical/HorizontalScroll이 둘 다
    // true이면 ACTION_MOVE를 소비해 웹에 pointermove가 가지 않는다 → 타워 회전 불가.
    test('스크롤 차단 옵션을 켜지 않는다 (드래그가 웹 게임에 전달돼야 함)', () {
      final s = gameWebViewSettings();
      expect(s.disableVerticalScroll, isNot(true));
      expect(s.disableHorizontalScroll, isNot(true));
    });
    test('페이지 스크롤은 웹(CSS)에서 막는다', () {
      final html = File('assets/www/index.html').readAsStringSync();
      expect(html, contains('#app { position: fixed; inset: 0; touch-action: none; }'));
      expect(html, contains('overflow: hidden'));
    });
  });

  group('알림 언어', () {
    test('한국어 로케일만 한국어', () {
      expect(NotificationService.isKorean(const Locale('ko', 'KR')), isTrue);
      expect(NotificationService.isKorean(const Locale('en', 'US')), isFalse);
      expect(NotificationService.isKorean(const Locale('ja')), isFalse);
    });
  });

  group('assets/www/index.html', () {
    final html = File('assets/www/index.html').readAsStringSync();

    test('튜닝 패널은 DEV_TOOLS일 때만 보인다', () {
      expect(html, contains("get('dev') === '1'"));
      expect(html, contains("classList.toggle('hide', !DEV_TOOLS || name !== null)"));
      expect(html, contains('<div id="panel" class="hide">'));
    });

    test('기본 언어는 영어이고 한국어 로케일에서만 교체한다', () {
      expect(html, contains('<html lang="en">'));
      expect(html, contains(">▶ PLAY</button>"));
      expect(html, contains("startsWith('ko') ? 'ko' : 'en'"));
      expect(html, contains('applyStaticI18n();'));
    });

    test('랭킹 목업의 내 이름도 언어별로 나온다 (#56)', () {
      expect(html, isNot(contains("nm: 'YOU'")));
      expect(html, isNot(contains("(p.nm || 'YOU')")));
      expect(html, contains("L('YOU', '나')"));
    });

    test('데일리 알림 숫자는 배지로 표시된다 ("Daily1"처럼 붙지 않게, #56)', () {
      expect(html, contains('<span id="dailyBadge" class="badge"></span>'));
      expect(html, contains('#home .tab .badge {'));
    });

    test('상점 소모품 설명은 어두운 카드 위에서 읽히는 색을 쓴다 (#56)', () {
      expect(html, contains('.skin .pct { color: #b8b8d0;'));
    });
  });

  group('네이티브 언어 리소스 (#56)', () {
    test('Android: 앱별 언어 설정에 en·ko를 등록한다', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:localeConfig="@xml/locales_config"'));
      final cfg = File('android/app/src/main/res/xml/locales_config.xml')
          .readAsStringSync();
      expect(cfg, contains('<locale android:name="en"/>'));
      expect(cfg, contains('<locale android:name="ko"/>'));
    });

    test('Android: 출시 패키지는 com.bounce.tower', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.bounce.tower"'));
    });

    test('iOS: ATT 문구 기본은 영어, 한국어는 ko.lproj', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final att = RegExp(
              r'<key>NSUserTrackingUsageDescription</key>\s*<string>([^<]*)</string>')
          .firstMatch(plist)!
          .group(1)!;
      expect(_hangul.hasMatch(att), isFalse, reason: att);
      final en = File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync();
      final ko = File('ios/Runner/ko.lproj/InfoPlist.strings').readAsStringSync();
      expect(en, contains('"NSUserTrackingUsageDescription" = "'));
      expect(ko, contains('"NSUserTrackingUsageDescription" = "'));
      expect(_hangul.hasMatch(ko), isTrue);
      // Xcode 프로젝트에 등록돼 있어야 앱 번들에 들어간다
      final pbx =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, contains('path = en.lproj/InfoPlist.strings;'));
      expect(pbx, contains('path = ko.lproj/InfoPlist.strings;'));
      expect(pbx, contains('/* InfoPlist.strings in Resources */,'));
      expect(RegExp(r'knownRegions = \([^)]*\bko,').hasMatch(pbx), isTrue);
    });
  });
}
