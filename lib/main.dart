import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads.dart';
import 'analytics.dart';
import 'firebase_options.dart';
import 'notifications.dart';
import 'ranking.dart';
import 'remote_config.dart';

/// 로컬 자산(assets/www)을 서빙할 내장 HTTP 서버. 상대경로(vendor/*.js)가
/// 그대로 동작하도록 localhost로 서빙한다.
final InAppLocalhostServer _localhostServer =
    InAppLocalhostServer(documentRoot: 'assets/www', port: 8080);

/// 지표·크래시 수집. main()에서 Firebase 초기화 직후 켜고, 이후 브리지가 쓴다.
final AnalyticsService _analytics = AnalyticsService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 세로 고정 + 풀스크린(상태바/내비바 숨김) — 게임 몰입감
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await MobileAds.instance.initialize();

  // Firebase는 **여기서 한 번만** 초기화한다(RankingService는 이걸 재사용).
  // 크래시 핸들러를 runApp 이전에 걸어야 초기 프레임 예외까지 잡힌다.
  // 미설정·오프라인이면 그대로 목업 모드로 계속 간다.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await _analytics.init();
  } catch (e) {
    debugPrint('Firebase 초기화 실패(목업 모드로 계속): $e');
  }

  // 포트가 이미 점유된 경우(이전 인스턴스 잔존 등) 예외로 앱이 아예 못 뜨는 걸 막는다.
  // 서버가 이미 떠 있으면 WebView 로드는 그대로 성공하므로 계속 진행한다.
  try {
    await _localhostServer.start();
  } catch (e) {
    debugPrint('로컬 서버 시작 실패(이미 실행 중일 수 있음): $e');
  }

  runApp(const BounceTowerApp());
}

class BounceTowerApp extends StatelessWidget {
  const BounceTowerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Bounce Tower',
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final AdManager _ads = AdManager();
  final RankingService _ranking = RankingService();
  final RemoteConfigService _config = RemoteConfigService();

  @override
  void initState() {
    super.initState();
    // ATT(iOS): 앱이 활성화된 뒤 추적 동의를 요청하고, 그 다음 광고를 프리로드.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTrackingThenAds());
  }

  Future<void> _initTrackingThenAds() async {
    try {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        // 시스템 권한창이 앱 표시 직후 바로 뜨지 않도록 약간 지연
        await Future.delayed(const Duration(milliseconds: 600));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (_) {
      // Android 등 ATT 미지원 플랫폼은 무시
    }
    _ads.preloadAll();

    // 리텐션 로컬 알림 (출석/복귀)
    try {
      await NotificationService.init();
      await NotificationService.scheduleReminders();
    } catch (_) {/* 알림 실패는 게임 동작에 영향 없음 */}

    // 계정(익명) + 랭킹 (Firebase 미설정이면 자동 비활성 → 목업 랭킹 유지)
    try {
      await _ranking.init();
    } catch (_) {}

    // Remote Config — Firebase 초기화(ranking.init) 이후에만 유효.
    // 실패해도 기본값이 남으므로 게임 동작에는 영향 없음.
    try {
      await _config.init();
      _ads.interstitialMinGap = _config.interstitialGap;
    } catch (_) {}
  }

  /// JS에서 넘어온 인자 중 [i]번째를 int로. 없거나 숫자가 아니면 0.
  static int _argInt(List<dynamic> args, int i) {
    if (i >= args.length) return 0;
    final v = args[i];
    return v is num ? v.toInt() : 0;
  }

  @override
  void dispose() {
    _ads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 게임 배경(보라 그라데이션)과 톤을 맞춰 로딩 깜빡임 최소화
    return Scaffold(
      backgroundColor: const Color(0xFF241638),
      body: SafeArea(
        top: false,
        bottom: false,
        child: InAppWebView(
          initialUrlRequest:
              URLRequest(url: WebUri('http://localhost:8080/index.html')),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            disableContextMenu: true,
            supportZoom: false,
            disableVerticalScroll: true,
            disableHorizontalScroll: true,
            // Android localhost(http) 허용
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          onWebViewCreated: (controller) {
            // ── JS → Dart 브리지 핸들러 등록 (index.html 브리지 스크립트와 짝) ──

            // 보상형 광고: true(보상완료) | 'noad'(광고없음→지급) | false(중도종료)
            controller.addJavaScriptHandler(
              handlerName: 'showRewarded',
              callback: (args) => _ads.showRewarded(),
            );

            // 전면 광고: 게임 종료 후 다시하기/홈 전환 시.
            // **광고가 닫힌 뒤에** Promise가 resolve된다 — 웹은 이걸 기다렸다가
            // 다음 판을 시작한다(광고가 진행 중인 판을 덮는 문제 방지).
            controller.addJavaScriptHandler(
              handlerName: 'showInterstitial',
              callback: (args) => _ads.maybeShowInterstitial(),
            );

            // 광고 제거(IAP) 상태 반영
            controller.addJavaScriptHandler(
              handlerName: 'setAdFree',
              callback: (args) {
                _ads.adFree = true;
                return null;
              },
            );

            // 랭킹: 최고 점수 제출
            // callHandler('submitScore', best, name, seasonBest)
            controller.addJavaScriptHandler(
              handlerName: 'submitScore',
              callback: (args) {
                final name = args.length > 1 ? '${args[1]}' : 'Player';
                _ranking.submitScore(_argInt(args, 0), name,
                    seasonBest: _argInt(args, 2));
                return null;
              },
            );

            // 랭킹: 상위 100 + 내 순위 — callHandler('getLeaderboard', myBest)
            // Firebase 미설정이면 null 반환 → 웹은 목업 랭킹 사용
            controller.addJavaScriptHandler(
              handlerName: 'getLeaderboard',
              callback: (args) => _ranking.getLeaderboard(_argInt(args, 0)),
            );

            // 시즌 랭킹 — callHandler('getSeasonLeaderboard', mySeasonBest)
            // 전체 랭킹 형태 + { seasonId, seasonIndex, endsAt }
            controller.addJavaScriptHandler(
              handlerName: 'getSeasonLeaderboard',
              callback: (args) =>
                  _ranking.getSeasonLeaderboard(_argInt(args, 0)),
            );

            // 알림 권한 — callHandler('requestNotificationPermission')
            // 웹이 첫 보상(출석/미션) 수령 직후에 부른다. 앱 시작 시 ATT와
            // 겹쳐 뜨지 않게 하려는 것 → B4.
            controller.addJavaScriptHandler(
              handlerName: 'requestNotificationPermission',
              callback: (args) => NotificationService.requestPermission(),
            );

            // 지표 — callHandler('logEvent', 'game_over', { score: 12, ... })
            // 이름·파라미터 검증은 AnalyticsService가 담당(잘못된 건 조용히 무시).
            controller.addJavaScriptHandler(
              handlerName: 'logEvent',
              callback: (args) {
                if (args.isEmpty) return null;
                final params = (args.length > 1 && args[1] is Map)
                    ? Map<String, dynamic>.from(args[1] as Map)
                    : <String, dynamic>{};
                _analytics.logEvent('${args[0]}', params);
                return null;
              },
            );

            // Remote Config 밸런스 값 — callHandler('getRemoteConfig')
            // 미설정/오프라인이어도 기본값이 담겨 항상 유효한 맵을 반환한다.
            controller.addJavaScriptHandler(
              handlerName: 'getRemoteConfig',
              callback: (args) => _config.toJson(),
            );

            // 계정 상태 — callHandler('getAccountState')
            // { enabled, uid, linked, isAnonymous, providers[], appleAvailable }
            // 웹이 시작 시 폴링(익명 로그인 완료 대기)하고, 배지·계정 모달·권유 트리거에 쓴다.
            controller.addJavaScriptHandler(
              handlerName: 'getAccountState',
              callback: (args) => _ranking.accountState(),
            );

            // 계정 연결 — callHandler('linkAccount', 'google' | 'apple')
            // → { ok, switched, providers, error }. switched=true면 이미 연결된 다른 계정으로
            // 전환된 것이라 웹이 cloudResync()로 재병합한다. 설계: 닉네임계정설계 Phase 2.
            controller.addJavaScriptHandler(
              handlerName: 'linkAccount',
              callback: (args) =>
                  _ranking.linkAccount(args.isNotEmpty ? '${args[0]}' : ''),
            );

            // 로그아웃 → 새 익명 계정. 로컬 세이브는 웹이 그대로 유지한다.
            controller.addJavaScriptHandler(
              handlerName: 'signOut',
              callback: (args) => _ranking.signOut(),
            );

            // 계정 삭제(App Store 5.1.1(v) / Play 정책) — 재인증 → 문서 삭제 → user.delete().
            controller.addJavaScriptHandler(
              handlerName: 'deleteAccount',
              callback: (args) => _ranking.deleteAccount(),
            );

            // 클라우드 세이브 로드 — callHandler('cloudLoad') → users/{uid}.save | null
            controller.addJavaScriptHandler(
              handlerName: 'cloudLoad',
              callback: (args) async => await _ranking.loadCloud(),
            );

            // 클라우드 세이브 저장 — callHandler('cloudSave', saveObject)
            controller.addJavaScriptHandler(
              handlerName: 'cloudSave',
              callback: (args) {
                final m = (args.isNotEmpty && args[0] is Map)
                    ? Map<String, dynamic>.from(args[0] as Map)
                    : <String, dynamic>{};
                if (m.isNotEmpty) _ranking.saveCloud(m);
                return null;
              },
            );
          },
          onLoadStop: (controller, url) async {
            // WebView에서 env(safe-area-inset-*)가 0으로 나오는 환경 대비:
            // Flutter MediaQuery의 실제 안전영역(노치/다이나믹 아일랜드)을 CSS 변수로 주입.
            if (!mounted) return;
            final p = MediaQuery.of(context).padding;
            await controller.evaluateJavascript(source:
                "var d=document.documentElement.style;"
                "d.setProperty('--safe-top','${p.top}px');"
                "d.setProperty('--safe-bottom','${p.bottom}px');"
                "d.setProperty('--safe-left','${p.left}px');"
                "d.setProperty('--safe-right','${p.right}px');");
          },
        ),
      ),
    );
  }
}
