// 업무 #54: 영어 로케일에서 한글이 새지 않는지 더 엄격하게 검사한다.
// release_ui_test.dart의 스캔은 `L(`이 있는 줄을 통째로 건너뛰므로, 한 줄에
// L()과 한국어 단독 문구가 같이 있으면 놓친다. 여기서는 파일 전체를 훑어
// ① 주석 ② data-ko/data-ko-ph 속성 ③ L(en, ko)의 두 번째 인자(괄호 짝 맞춤)를
// 공백으로 지운 뒤 남은 한글을 찾는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _hangul = RegExp(r'[가-힣ㄱ-ㆎ]');

bool _isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

/// [src]에서 영어 로케일에 보이지 않는 부분을 공백으로 바꾼다(줄 번호 유지).
String blankNonEnglish(String src) {
  final out = src.split('');
  void blank(int from, int to) {
    for (var k = from; k < to && k < out.length; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  // ① HTML 주석, data-ko 속성 (문자열 상태와 무관하게 HTML 영역에만 나온다)
  for (final m in RegExp(r'<!--[\s\S]*?-->').allMatches(src)) {
    blank(m.start, m.end);
  }
  for (final m in RegExp(r'data-ko(-ph)?="[^"]*"').allMatches(src)) {
    blank(m.start, m.end);
  }
  // CSS 주석
  for (final st in RegExp(r'<style>[\s\S]*?</style>').allMatches(src)) {
    for (final m in RegExp(r'/\*[\s\S]*?\*/').allMatches(st[0]!)) {
      blank(st.start + m.start, st.start + m.end);
    }
  }

  // ② <script> 안: JS 주석과 L()의 두 번째 인자
  for (final sm in RegExp(r'<script>([\s\S]*?)</script>').allMatches(src)) {
    final start = sm.start + '<script>'.length;
    final end = sm.end - '</script>'.length;
    var i = start;
    // 문자열/주석을 건너뛰며 위치 i 에서 끝나는 인덱스를 돌려준다.
    int skipString(int p) {
      final q = src[p];
      p++;
      while (p < end) {
        final c = src[p];
        if (c == '\\') {
          p += 2;
          continue;
        }
        if (c == q) return p + 1;
        p++;
      }
      return p;
    }

    while (i < end) {
      final c = src[i];
      if (c == '/' && i + 1 < end && src[i + 1] == '/') {
        final nl = src.indexOf('\n', i);
        final e = nl < 0 || nl > end ? end : nl;
        blank(i, e);
        i = e;
        continue;
      }
      if (c == '/' && i + 1 < end && src[i + 1] == '*') {
        final e0 = src.indexOf('*/', i + 2);
        final e = e0 < 0 ? end : e0 + 2;
        blank(i, e);
        i = e;
        continue;
      }
      if (c == "'" || c == '"' || c == '`') {
        i = skipString(i);
        continue;
      }
      if (c == 'L' &&
          i + 1 < end &&
          src[i + 1] == '(' &&
          (i == 0 || !_isIdent(src[i - 1]))) {
        // 괄호 짝을 맞춰 최상위 콤마(두 번째 인자 시작)와 닫는 괄호를 찾는다.
        var p = i + 2, depth = 0, comma = -1;
        while (p < end) {
          final d = src[p];
          if (d == "'" || d == '"' || d == '`') {
            p = skipString(p);
            continue;
          }
          if (d == '(' || d == '[' || d == '{') depth++;
          if (d == ')' || d == ']' || d == '}') {
            if (depth == 0) break;
            depth--;
          }
          if (d == ',' && depth == 0 && comma < 0) comma = p;
          p++;
        }
        if (comma >= 0) blank(comma + 1, p);
        i += 2; // 첫 번째 인자 안의 중첩 L()도 계속 검사
        continue;
      }
      i++;
    }
  }
  return out.join();
}

/// 한국어 전용으로 의도된 줄(사람이 확인한 목록).
/// (#56) MLABELS도 L()로 바꿔 예외에서 뺐다. 남은 예외는 닉네임 검증용 데이터뿐.
bool _koOnlyByDesign(String line) =>
    line.contains('가-힣') || // 닉네임 허용 문자 정규식
    line.contains("'시발'"); // 닉네임 금칙어

void main() {
  test('blankNonEnglish: L()의 한국어 인자만 지운다', () {
    final s = blankNonEnglish(
        "<script>toast(L(a + ' ok', a + ' 확인')); x = '한글';</script>");
    expect(s.contains('확인'), isFalse);
    expect(s.contains('한글'), isTrue);
  });

  test('blankNonEnglish: 같은 줄에서 L() 뒤에 붙은 한국어도 잡는다 (#56)', () {
    final s = blankNonEnglish(
        "<script>toast(L('Hi', '안녕') + ' 획득'); y = L('a' + n, n + '개');</script>");
    expect(s.contains('안녕'), isFalse);
    expect(s.contains('개'), isFalse);
    expect(s.contains('획득'), isTrue);
  });

  test('언어 적용은 vendor 스크립트보다 먼저 실행된다(로딩 중 영어 깜빡임 방지)', () {
    final src = File('assets/www/index.html').readAsStringSync();
    final apply = src.indexOf('applyStaticI18n();');
    final vendor = src.indexOf('<script src="vendor/three.min.js">');
    expect(apply, greaterThan(0));
    expect(vendor, greaterThan(0));
    expect(apply, lessThan(vendor));
    expect(src, contains('html[lang="ko"] body { word-break: keep-all;'));
  });

  test('index.html: L()/data-ko/주석 밖에 한글 문구가 없다', () {
    final src = File('assets/www/index.html').readAsStringSync();
    final lines = blankNonEnglish(src).split('\n');
    final orig = src.split('\n');
    final offenders = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!_hangul.hasMatch(lines[i])) continue;
      if (_koOnlyByDesign(orig[i])) continue;
      offenders.add('${i + 1}: ${orig[i].trim()}');
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
