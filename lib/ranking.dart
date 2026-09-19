import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';

/// 계정(익명 → Google/Apple 연결) + 크로스플랫폼 랭킹 + 클라우드 세이브.
/// Firebase 초기화/인증 실패 시 자동 비활성(enabled=false) → 호출측은 목업 랭킹으로 폴백한다.
class RankingService {
  bool enabled = false;

  /// 현재 uid. 계정 연결·전환·삭제로 바뀔 수 있으므로 **캐시하지 않고** 매번 조회한다.
  String? get uid {
    if (!enabled) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── 시즌 ─────────────────────────
  // 2주 단위 시즌. 시즌 랭킹은 `seasons/{seasonId}/scores/{uid}`에 따로 쌓는다
  // (전체 랭킹 `scores/{uid}`는 그대로 유지 = 명예의 전당).
  //
  // ⚠️ 웹(`assets/www/index.html`의 SEASON_EPOCH_MS / SEASON_DAYS)이 **같은 식으로
  // 독립 계산**한다. 브라우저 목업에서도 시즌이 돌아야 하기 때문. 둘 중 하나만
  // 바꾸면 시즌 번호가 어긋나므로 반드시 함께 수정할 것.

  /// 시즌 기준점 — 2026-01-05(월) 00:00 UTC.
  static final DateTime seasonEpoch = DateTime.utc(2026, 1, 5);
  static const int seasonDays = 14;

  /// 현재 시즌 번호(0부터). 기준점 이전이면 0.
  static int get seasonIndex {
    final ms = DateTime.now().toUtc().difference(seasonEpoch).inMilliseconds;
    if (ms <= 0) return 0;
    return ms ~/ (seasonDays * Duration.millisecondsPerDay);
  }

  static String get seasonId => 'S$seasonIndex';

  /// 현재 시즌 종료 시각(UTC).
  static DateTime get seasonEnd =>
      seasonEpoch.add(Duration(days: seasonDays * (seasonIndex + 1)));

  Future<void> init() async {
    try {
      // main()에서 이미 초기화했으면 재사용한다 — 중복 호출은 duplicate-app 예외.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
      await _ensureSignedIn();
      enabled = FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      enabled = false; // 미설정/오류 → 목업 유지
    }
  }

  /// 로그인된 사용자가 **없을 때만** 익명 로그인한다.
  ///
  /// ⚠️ `signInAnonymously()`는 다른 사용자가 로그인돼 있으면 **그 사용자를 로그아웃**
  /// 시킨다(Firebase SDK 문서). 매 실행 무조건 부르면 Google/Apple 연결이 앱 재시작마다
  /// 풀리고 새 익명 uid가 발급된다. 반드시 currentUser를 먼저 본다.
  Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;
    await auth.signInAnonymously();
  }

  /// 최고 점수 제출(본인 문서). best는 단조 증가만 의미 있음(규칙이 강제).
  /// [seasonBest]가 0보다 크면 현재 시즌 문서에도 함께 기록한다.
  Future<void> submitScore(int best, String name, {int seasonBest = 0}) async {
    final id = uid;
    if (id == null) return;
    final clean = name.length > 16 ? name.substring(0, 16) : name;
    final fs = FirebaseFirestore.instance;
    try {
      await fs.collection('scores').doc(id).set({
        'name': clean,
        'best': best,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    if (seasonBest <= 0) return;
    try {
      await _seasonScores().doc(id).set({
        'name': clean,
        'best': seasonBest,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  CollectionReference<Map<String, dynamic>> _seasonScores() =>
      FirebaseFirestore.instance
          .collection('seasons')
          .doc(seasonId)
          .collection('scores');

  /// 전체(명예의 전당) 랭킹 — 상위 100 + 내 순위.
  Future<Map<String, dynamic>?> getLeaderboard(int myBest) =>
      _leaderboard(FirebaseFirestore.instance.collection('scores'), myBest);

  /// 현재 시즌 랭킹. 시즌 메타(번호·종료시각)를 함께 실어 보낸다.
  Future<Map<String, dynamic>?> getSeasonLeaderboard(int mySeasonBest) async {
    final board = await _leaderboard(_seasonScores(), mySeasonBest);
    if (board == null) return null;
    return {
      ...board,
      'seasonId': seasonId,
      'seasonIndex': seasonIndex,
      'endsAt': seasonEnd.millisecondsSinceEpoch,
    };
  }

  /// 상위 100 + 내 순위. 반환값은 JS로 그대로 직렬화되어 랭킹 UI가 렌더한다.
  Future<Map<String, dynamic>?> _leaderboard(
      Query<Map<String, dynamic>> col, int myBest) async {
    if (!enabled) return null;
    final id = uid;
    try {
      final snap =
          await col.orderBy('best', descending: true).limit(100).get();
      final top = snap.docs
          .map((d) => {
                'name': (d.data()['name'] ?? '???').toString(),
                'best': (d.data()['best'] ?? 0),
                'me': d.id == id,
              })
          .toList();
      int myRank = 0;
      try {
        final agg = await col.where('best', isGreaterThan: myBest).count().get();
        myRank = (agg.count ?? 0) + 1;
      } catch (_) {}
      return {'top': top, 'myRank': myRank, 'myBest': myBest};
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── 클라우드 세이브 ─────────────────────────
  // 웹의 SAVE 객체(localStorage) 전체를 users/{uid}.save 에 백업.
  // 같은 계정으로 다시 로그인하면 복원된다. 재설치·기기 이전 후 같은 uid를 잇는 것은
  // 아래 "계정 연결"(Google/Apple)이 담당한다.

  /// users/{uid}.save 로드(없으면 null). 병합은 웹(JS)이 담당.
  Future<Map<String, dynamic>?> loadCloud() async {
    final id = uid;
    if (id == null) return null;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(id).get();
      final data = doc.data();
      final save = data?['save'];
      if (save is Map) return Map<String, dynamic>.from(save);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 웹 SAVE 객체를 통째로 백업(병합 저장).
  Future<void> saveCloud(Map<String, dynamic> save) async {
    final id = uid;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).set({
        'save': save,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ───────────────────────── 계정 연결 (Phase 2) ─────────────────────────
  // 익명 계정을 Google/Apple에 link해 같은 uid를 다른 기기·재설치 후에도 잇는다.
  // 설계: 바운스타워_닉네임계정설계.md Phase 2 / 프로비저닝: FIREBASE_SETUP.md 2-B
  //
  //  · Google: google_sign_in 7.x (initialize → authenticate → idToken) → linkWithCredential
  //  · Apple : firebase_auth 내장 AppleAuthProvider → linkWithProvider (iOS 네이티브, nonce 자동)
  //  · 이미 다른 uid(B)에 연결된 자격증명이면(credential-already-in-use):
  //      현재 익명 uid의 문서를 먼저 지우고 → B로 signIn 전환. 유령 랭킹 행 방지.
  //      현재 사용자가 익명이 아니면(이미 연결된 실계정) 전환하지 않고 에러로 알린다.

  static const String _googleId = 'google.com';
  static const String _appleId = 'apple.com';
  bool _googleReady = false;

  /// 연결된 소셜 provider 목록(`google.com`, `apple.com`).
  List<String> get providers {
    if (!enabled) return const [];
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const [];
      return user.providerData
          .map((p) => p.providerId)
          .where((p) => p == _googleId || p == _appleId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool get linked => providers.isNotEmpty;

  /// 브리지 `getAccountState` 응답. 웹이 배지·계정 모달·권유 트리거에 쓴다.
  Map<String, dynamic> accountState() {
    bool anonymous = true;
    try {
      anonymous = FirebaseAuth.instance.currentUser?.isAnonymous ?? true;
    } catch (_) {}
    return {
      'enabled': enabled,
      'uid': uid,
      'linked': linked,
      'isAnonymous': anonymous,
      'providers': providers,
      // Android Apple 로그인(웹 플로우)은 Services ID 등록이 필요해 2차로 미룸.
      'appleAvailable': Platform.isIOS,
    };
  }

  /// 계정 연결. [provider]는 `'google'` | `'apple'`.
  ///
  /// 반환 `{ok, switched, providers, error}`:
  ///  - ok=true, switched=false : 현재 uid에 연결됨(기록 그대로 승계)
  ///  - ok=true, switched=true  : 자격증명이 이미 다른 uid에 연결돼 있어 그 계정으로 전환됨.
  ///                              현재(익명) uid의 문서는 지웠다. 웹은 `cloudResync()`로 재병합.
  ///  - ok=false, error=코드    : cancelled | not-configured | already-linked |
  ///                              in-use-other-account | disabled | 기타 FirebaseAuth 코드
  Future<Map<String, dynamic>> linkAccount(String provider) async {
    if (!enabled) return _fail('disabled');
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) return _fail('no-user');
    final isApple = provider == 'apple';
    if (!isApple && provider != 'google') return _fail('bad-provider');
    if (providers.contains(isApple ? _appleId : _googleId)) {
      return _fail('already-linked');
    }

    AuthCredential? cred;
    try {
      if (isApple) {
        await user.linkWithProvider(AppleAuthProvider());
      } else {
        cred = await _googleCredential();
        await user.linkWithCredential(cred);
      }
      return _ok();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        // 이미 연결된 실계정 위에서 또 다른 실계정으로 갈아타는 건 막는다 —
        // 현재 계정의 기록을 지우게 되므로. 로그아웃 후 그 계정으로 로그인하도록 안내.
        if (!user.isAnonymous) return _fail('in-use-other-account');
        return _switchTo(e.credential ?? cred, isApple);
      }
      if (e.code == 'provider-already-linked') return _fail('already-linked');
      return _fail(_mapAuthCode(e.code));
    } on GoogleSignInException catch (e) {
      return _fail(_mapGoogleCode(e.code));
    } on PlatformException catch (_) {
      return _fail('not-configured');
    } on StateError catch (_) {
      return _fail('not-configured');
    } catch (_) {
      return _fail('unknown');
    }
  }

  /// already-in-use 폴백: 현재(익명) uid 문서 정리 → 기존 계정으로 전환.
  Future<Map<String, dynamic>> _switchTo(
      AuthCredential? cred, bool isApple) async {
    final auth = FirebaseAuth.instance;
    final oldUid = auth.currentUser?.uid;
    // 1) 아직 옛 uid로 로그인돼 있는 지금 지워야 규칙(본인 delete)을 통과한다.
    //    실패해도 계속 간다 — 로컬(진실원본)이 살아 있어 다음 푸시가 복구한다.
    if (oldUid != null) {
      try {
        await _deleteUserDocs(oldUid);
      } catch (_) {}
    }
    // 2) 전환. 실패하면 옛 사용자로 그대로 남는다(signIn 실패는 로그아웃시키지 않음).
    try {
      if (cred != null) {
        await auth.signInWithCredential(cred);
      } else if (isApple) {
        await auth.signInWithProvider(AppleAuthProvider());
      } else {
        await auth.signInWithCredential(await _googleCredential());
      }
      return _ok(switched: true);
    } on FirebaseAuthException catch (e) {
      await _recover();
      return _fail(_mapAuthCode(e.code));
    } on GoogleSignInException catch (e) {
      await _recover();
      return _fail(_mapGoogleCode(e.code));
    } catch (_) {
      await _recover();
      return _fail('unknown');
    }
  }

  /// 로그아웃 → 새 익명 계정. 잘못된 계정에 연결했을 때의 탈출로.
  /// 이전 계정의 문서는 지우지 않는다(그 계정 소유자의 기록).
  Future<Map<String, dynamic>> signOut() async {
    if (!enabled) return _fail('disabled');
    try {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
      await FirebaseAuth.instance.signOut();
      await _ensureSignedIn();
      return _ok();
    } on FirebaseAuthException catch (e) {
      await _recover();
      return _fail(_mapAuthCode(e.code));
    } catch (_) {
      await _recover();
      return _fail('unknown');
    }
  }

  /// 계정 삭제(App Store 5.1.1(v) / Play 정책).
  /// 재인증 → (Apple) 토큰 revoke → 본인 Firestore 문서 삭제 → user.delete() → 새 익명.
  /// 로컬 SAVE는 웹이 그대로 들고 있으므로 이 기기의 진행도는 남는다.
  Future<Map<String, dynamic>> deleteAccount() async {
    if (!enabled) return _fail('disabled');
    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;
    if (user == null) return _fail('no-user');
    final id = user.uid;
    try {
      final ps = providers;
      // 1) 재인증 — delete()는 최근 로그인을 요구할 수 있다(requires-recent-login).
      //    Apple은 여기서 받은 authorizationCode로 토큰을 revoke한다(Apple 정책).
      //    revoke는 현재 사용자의 ID 토큰이 필요하므로 delete() **전에** 한다.
      if (ps.contains(_appleId)) {
        final uc = await user.reauthenticateWithProvider(AppleAuthProvider());
        final code = uc.additionalUserInfo?.authorizationCode;
        if (code != null && code.isNotEmpty) {
          try {
            await auth.revokeTokenWithAuthorizationCode(code);
          } catch (_) {}
        }
      } else if (ps.contains(_googleId)) {
        await user.reauthenticateWithCredential(await _googleCredential());
      }
      user = auth.currentUser ?? user;
      // 2) 본인 문서 삭제(users / scores / 모든 시즌)
      await _deleteUserDocs(id);
      // 3) 계정 삭제. 익명 계정은 재인증이 불가하므로 실패해도 넘어간다
      //    (문서는 이미 지웠고, 아래에서 새 익명으로 갈아탄다).
      try {
        await user.delete();
      } on FirebaseAuthException {
        if (!user.isAnonymous) rethrow;
        await auth.signOut();
      }
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    } on FirebaseAuthException catch (e) {
      return _fail(_mapAuthCode(e.code));
    } on GoogleSignInException catch (e) {
      return _fail(_mapGoogleCode(e.code));
    } on PlatformException catch (_) {
      return _fail('not-configured');
    } catch (_) {
      return _fail('unknown');
    }
    // 4) 새 익명 로그인(실패해도 삭제는 끝났다)
    await _recover();
    return _ok();
  }

  /// Google 로그인 → Firebase 자격증명. idToken만 필요(accessToken 불필요).
  /// Android는 google-services.json의 web client(client_type 3), iOS는 plist의 CLIENT_ID를
  /// 플러그인이 읽는다 — 둘 다 `flutterfire configure` 재실행으로 채워진다(2-B).
  Future<AuthCredential> _googleCredential() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize();
      _googleReady = true;
    }
    final account = await g.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('google idToken missing');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// users/{uid}, scores/{uid}, seasons/S0..S{현재}/scores/{uid} 일괄 삭제.
  /// 시즌은 2주 단위(연 26개)라 배치 한도(500) 안에서 수십 년 여유가 있다.
  Future<void> _deleteUserDocs(String id) async {
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();
    batch.delete(fs.collection('users').doc(id));
    batch.delete(fs.collection('scores').doc(id));
    for (var i = 0; i <= seasonIndex; i++) {
      batch.delete(
          fs.collection('seasons').doc('S$i').collection('scores').doc(id));
    }
    await batch.commit();
  }

  /// 인증 상태가 비었으면 익명으로 되살린다. 어떤 실패 뒤에도 랭킹이 죽지 않게.
  Future<void> _recover() async {
    try {
      await _ensureSignedIn();
    } catch (_) {}
  }

  Map<String, dynamic> _ok({bool switched = false}) =>
      {'ok': true, 'switched': switched, 'providers': providers};

  Map<String, dynamic> _fail(String code) =>
      {'ok': false, 'switched': false, 'providers': providers, 'error': code};

  static String _mapAuthCode(String code) {
    final c = code.toLowerCase();
    if (c.contains('cancel')) return 'cancelled'; // canceled / web-context-canceled 등
    if (c == 'network-request-failed') return 'network';
    if (c == 'operation-not-allowed' || c == 'invalid-credential') {
      return 'not-configured'; // 콘솔에서 provider 미활성 / OAuth client 불일치
    }
    return code;
  }

  static String _mapGoogleCode(GoogleSignInExceptionCode code) {
    switch (code) {
      case GoogleSignInExceptionCode.canceled:
        return 'cancelled';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'not-configured';
      default:
        return 'google-${code.name}';
    }
  }
}
