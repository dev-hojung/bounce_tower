// 업무 #81: 스플래시 재디자인 · 무적 테스트 버튼 제거 · 실기기 드래그 방어 회귀 테스트.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:bounce_tower/main.dart';

/// PNG IHDR에서 (가로, 세로)를 읽는다.
(int, int) _pngSize(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  final html = File('assets/www/index.html').readAsStringSync();

  group('무적 테스트 제거 (#81)', () {
    test('RAGE test 버튼·핸들러가 없다', () {
      expect(html, isNot(contains('rageTest')));
      expect(html, isNot(contains('RAGE test')));
    });

    test('RAGE를 켜는 곳은 콤보 발동 한 곳뿐이다', () {
      final calls = RegExp(r'setRage\(true\)').allMatches(html).length;
      expect(calls, 1);
      expect(html,
          contains('if (combo >= RAGE_COMBO) { rageLeft = RAGE_RINGS; combo = 0; setRage(true); }'));
    });

    test('정식 RAGE·피격/부활 무적과 Remote Config 연결은 그대로다', () {
      expect(html, contains('RAGE_COMBO = RC.rageCombo;'));
      expect(html, contains('HIT_INVULN = 1.0'));
      expect(RegExp(r'hitInvuln = 2\.0').allMatches(html).length, 2);
      expect(html, contains("stat: 'rages'"));
    });

    test('rageLeft를 직접 채우는 곳은 콤보 발동뿐이다', () {
      expect(RegExp(r'rageLeft = RAGE_RINGS').allMatches(html).length, 1);
    });
  });

  group('드래그 입력 방어 (#81 실기기)', () {
    test('pointercancel·blur에서 드래그를 끝낸다', () {
      expect(html, contains("window.addEventListener('pointercancel', onUp);"));
      expect(html, contains("window.addEventListener('blur', () => onUp());"));
    });

    test('캔버스에 touch-action:none을 직접 건다', () {
      expect(html, contains("renderer.domElement.style.touchAction = 'none';"));
    });

    test('첫 손가락만 따라간다 (멀티터치 역회전 방지)', () {
      expect(html, contains('id !== dragId'));
      expect(html, contains('e.pointerId !== dragId'));
    });
  });

  group('스플래시·배경색 일관성 (#81)', () {
    const hex = '#1A0E33';

    test('Flutter 상수가 브랜드 배경색이다', () {
      expect(kBrandBg, const Color(0xFF1A0E33));
    });

    test('웹 body·Android colors·pubspec이 같은 색을 쓴다', () {
      expect(html, contains('background: $hex;'));
      expect(html, isNot(contains('#0a0a14;')));
      final colors =
          File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      expect(colors, contains('<color name="brand_bg">$hex</color>'));
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(RegExp('color: "$hex"').allMatches(pub).length, 2);
      expect(RegExp('color_dark: "$hex"').allMatches(pub).length, 2);
    });

    test('NormalTheme 창 배경이 흰색(colorBackground)이 아니라 브랜드 색이다', () {
      for (final d in ['values', 'values-v31', 'values-night', 'values-night-v31']) {
        final s =
            File('android/app/src/main/res/$d/styles.xml').readAsStringSync();
        expect(s, contains('<item name="android:windowBackground">@color/brand_bg</item>'),
            reason: d);
        expect(s, isNot(contains('?android:colorBackground')), reason: d);
      }
      for (final d in ['values-v31', 'values-night-v31']) {
        final s =
            File('android/app/src/main/res/$d/styles.xml').readAsStringSync();
        expect(s, contains('windowSplashScreenBackground">$hex<'), reason: d);
      }
    });

    test('Android 12 이미지는 1152px(마스크 없는 288dp 규격), 일반은 1024px', () {
      expect(_pngSize('assets/icon/splash_android12.png'), (1152, 1152));
      expect(_pngSize('assets/icon/splash.png'), (1024, 1024));
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('image: assets/icon/splash_android12.png'));
      // icon_background_color를 넣으면 240dp 규격으로 축소된다
      expect(pub, isNot(contains('icon_background_color:')));
    });
  });
}
