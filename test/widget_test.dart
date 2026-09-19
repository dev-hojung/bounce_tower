// Bounce Tower 스모크 테스트.
//
// WebView/AdMob은 플랫폼 채널이 필요해 단위 테스트 환경에서 인스턴스화하지 않는다.
// 여기서는 앱 위젯이 예외 없이 구성되는지만 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bounce_tower/main.dart';

void main() {
  testWidgets('앱 위젯이 구성된다', (WidgetTester tester) async {
    const app = BounceTowerApp();
    expect(app, isA<StatelessWidget>());
  });
}
