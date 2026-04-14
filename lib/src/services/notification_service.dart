import 'dart:io';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/task_models.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int summaryNotificationId = 10;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);

    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();
      final canExact = await androidPlugin?.canScheduleExactNotifications();
      if (canExact == false) {
        await androidPlugin?.requestExactAlarmsPermission();
      }
    }
  }

  Future<void> scheduleForState(
    DailyTaskState state,
    List<AssistantTaskDefinition> definitions,
  ) async {
    await _plugin.cancelAll();
    await _showSummary(state);

    final now = DateTime.now();
    var id = 100;

    for (final definition in definitions) {
      if (!state.isEnabled(definition.id)) {
        continue;
      }
      switch (definition.kind) {
        case AssistantTaskKind.feedWindow:
          if (state.isCompleted(definition.id)) {
            break;
          }
          final start = _timeForToday(
            now,
            definition.startHour,
            definition.startMinute,
          );
          if (start.isAfter(now)) {
            await _scheduleReminder(
              id: id++,
              when: start,
              title: definition.title,
              body: '时窗开始，可进入应用并手动记次。',
            );
          }
          break;
        case AssistantTaskKind.adCooldown:
          if (state.adCompleted < definition.targetCount) {
            final next =
                state.adNextAvailableAt ??
                _timeForToday(
                  now,
                  definition.startHour,
                  definition.startMinute,
                );
            if (next.isAfter(now)) {
              await _scheduleReminder(
                id: id++,
                when: next,
                title: definition.title,
                body: '广告倒计时结束，可开始下一次。',
              );
            }
          }
          break;
        case AssistantTaskKind.fixedPoint:
          if (!state.isCompleted(definition.id)) {
            final due = _timeForToday(
              now,
              definition.startHour,
              definition.startMinute,
            );
            if (due.isAfter(now)) {
              await _scheduleReminder(
                id: id++,
                when: due,
                title: definition.title,
                body: '到点了，点通知后去完成。',
              );
            }
          }
          break;
      }
    }
  }

  Future<void> _showSummary(DailyTaskState state) async {
    final morning = state.isCompleted('feed_am') ? '完成' : '未完';
    final evening = state.isCompleted('feed_pm') ? '完成' : '未完';
    final body = '广告 ${state.adCompleted}/20 · 上午 $morning · 下午 $evening';
    await _plugin.show(
      id: summaryNotificationId,
      title: '今日任务看板',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_summary',
          'Task Summary',
          channelDescription: 'Persistent daily task summary',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }

  Future<void> _scheduleReminder({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_alarm',
          'Task Alarm',
          channelDescription: 'Task alarms and lock-screen reminders',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  DateTime _timeForToday(DateTime now, int hour, int minute) {
    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}
