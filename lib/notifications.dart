import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 로컬 알림(서버 없이 기기에서 예약). 리텐션용 — 출석/복귀 유도.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// 플러그인·타임존 준비. **권한은 요청하지 않는다.**
  ///
  /// 앱 시작 직후에 ATT와 알림 권한 팝업이 연달아 뜨면 양쪽 승인률이 모두
  /// 떨어진다. 권한은 사용자가 "받을 게 있다"고 인지한 시점(첫 보상 수령
  /// 직후)에 [requestPermission]으로 따로 요청한다.
  ///
  /// 예약(zonedSchedule) 자체는 권한과 무관하게 성공하며, 권한이 없으면
  /// 표시만 되지 않는다. 그래서 시작 시 예약은 그대로 해둔다.
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {/* 실패 시 UTC 유지 */}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios));

    _ready = true;
  }

  /// 알림 권한 요청 (iOS / Android 13+). 첫 보상 수령 직후에 호출한다.
  /// 반환값은 허용 여부(플랫폼이 답을 안 주면 false).
  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final ios = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      final android = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return ios ?? android ?? false;
    } catch (_) {
      return false;
    }
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bt_reminders',
      '리마인더',
      channelDescription: '출석·복귀 알림',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// 앱 실행 때마다 호출: 기존 예약을 갱신(복귀 타이머 리셋).
  static Future<void> scheduleReminders() async {
    if (!_ready) return;
    await _plugin.cancelAll();

    // 매일 저녁 7시 출석 리마인더 (반복)
    await _plugin.zonedSchedule(
      id: 1,
      title: '오늘의 출석 보상이 도착했어요 🎁',
      body: '연속 출석 보너스를 받아가세요!',
      scheduledDate: _nextInstanceOfHour(19),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 2일 미접속 시 복귀 유도 (앱 켤 때마다 리셋됨)
    await _plugin.zonedSchedule(
      id: 2,
      title: '타워가 당신을 기다려요 🗼',
      body: 'BEST 점수를 갱신해볼까요?',
      scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(days: 2)),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );

    // 주간 미션 마감 임박 — 일요일 저녁 8시 (주간 리셋은 웹의 weekStr() 기준)
    await _plugin.zonedSchedule(
      id: 3,
      title: '주간 미션 마감 임박! ⏰',
      body: '이번 주 보상을 놓치기 전에 받아가세요.',
      scheduledDate: _nextWeekdayHour(DateTime.sunday, 20),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static tz.TZDateTime _nextInstanceOfHour(int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// 다음 [weekday](DateTime.monday~sunday) [hour]시. 오늘이 해당 요일이고
  /// 아직 시각 전이면 오늘로 잡힌다.
  static tz.TZDateTime _nextWeekdayHour(int weekday, int hour) {
    var d = _nextInstanceOfHour(hour);
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
