// 업무 #53 QA 반영: 출시 빌드 디버그 UI 숨김 + 영어 기본/한국어 지원.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:bounce_tower/main.dart';
import 'package:bounce_tower/notifications.dart';

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

    test('스크립트 문자열에 한국어 단독 문구가 남지 않았다', () {
      // 한국어가 들어간 코드 줄은 주석, L(en, ko) 분기, data-ko 속성,
      // 한국어 전용 테이블(MLABELS ko), 닉네임 금칙어·정규식만 허용한다.
      final hangul = RegExp(r'[가-힣]');
      final offenders = <String>[];
      final lines = html.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i];
        if (!hangul.hasMatch(raw)) continue;
        // 줄 끝 주석 제거(문자열 안의 // 는 이 파일에서 한국어와 함께 쓰이지 않는다)
        final code = raw.split(RegExp(r'\s//\s|^\s*//|<!--|/\*')).first;
        if (!hangul.hasMatch(code)) continue;
        if (code.contains('data-ko')) continue;
        if (code.contains('L(')) continue;
        if (code.trim().startsWith('*')) continue;
        // 여러 줄로 나뉜 L(...) 의 한국어 인자 줄
        if (i > 0 && lines[i - 1].contains('L(')) continue;
        if (code.contains("combo: '한 판 콤보'")) continue; // MLABELS ko
        if (code.contains("'시발'") || code.contains('가-힣')) continue; // 금칙어·정규식
        offenders.add('${i + 1}: ${raw.trim()}');
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
