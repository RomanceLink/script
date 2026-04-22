import 'dart:convert';
import 'dart:io';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_models.dart';
import 'alarm_bridge.dart';
import 'task_repository.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AlarmBridge _alarmBridge = AlarmBridge();
  final TaskRepository _repository = TaskRepository();

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
    final reminders = <AlarmReminder>[];
    final gestureConfigs = await _repository.loadGestureConfigs();

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
            reminders.add(
              AlarmReminder(
                id: 'alarm_${id++}',
                taskId: definition.id,
                title: definition.title,
                body: '时窗开始，可进入应用并手动记次。',
                whenEpochMillis: start.millisecondsSinceEpoch,
                ringtoneSource: definition.ringtoneSource,
                ringtoneLabel: definition.ringtoneLabel,
                ringtoneValue: definition.ringtoneValue,
                targetAppPackage: state.selectedAppPackage,
                targetAppLabel: state.selectedAppLabel,
                gestureConfigName: _gestureConfigName(
                  definition,
                  gestureConfigs,
                ),
                gestureActionsJson: _gestureActionsJson(
                  definition,
                  gestureConfigs,
                ),
                gestureLoopCount: _gestureLoopCount(definition, gestureConfigs),
                gestureLoopIntervalMillis: _gestureLoopIntervalMillis(
                  definition,
                  gestureConfigs,
                ),
                preGestureConfigName: _preGestureConfigName(
                  definition,
                  gestureConfigs,
                ),
                preGestureActionsJson: _preGestureActionsJson(
                  definition,
                  gestureConfigs,
                ),
                preGestureLoopCount: _preGestureLoopCount(
                  definition,
                  gestureConfigs,
                ),
                preGestureLoopIntervalMillis: _preGestureLoopIntervalMillis(
                  definition,
                  gestureConfigs,
                ),
                autoOpenDelaySeconds: definition.autoOpenDelaySeconds,
                autoCompleteDelaySeconds: definition.autoCompleteDelayDuration.inSeconds,
              ),
            );
          }
          break;
        case AssistantTaskKind.adCooldown:
          if (state.intervalCompleted(definition.id) < definition.targetCount) {
            final next =
                state.intervalNextAt(definition.id) ??
                _timeForToday(
                  now,
                  definition.startHour,
                  definition.startMinute,
                );
            if (next.isAfter(now)) {
              reminders.add(
                AlarmReminder(
                  id: 'alarm_${id++}',
                  taskId: definition.id,
                  title: definition.title,
                  body: '间隔结束，可开始下一次。',
                  whenEpochMillis: next.millisecondsSinceEpoch,
                  ringtoneSource: definition.ringtoneSource,
                  ringtoneLabel: definition.ringtoneLabel,
                  ringtoneValue: definition.ringtoneValue,
                  targetAppPackage: state.selectedAppPackage,
                  targetAppLabel: state.selectedAppLabel,
                  gestureConfigName: _gestureConfigName(
                    definition,
                    gestureConfigs,
                  ),
                  gestureActionsJson: _gestureActionsJson(
                    definition,
                    gestureConfigs,
                  ),
                  gestureLoopCount: _gestureLoopCount(
                    definition,
                    gestureConfigs,
                  ),
                  gestureLoopIntervalMillis: _gestureLoopIntervalMillis(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureConfigName: _preGestureConfigName(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureActionsJson: _preGestureActionsJson(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureLoopCount: _preGestureLoopCount(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureLoopIntervalMillis: _preGestureLoopIntervalMillis(
                    definition,
                    gestureConfigs,
                  ),
                  autoOpenDelaySeconds: definition.autoOpenDelaySeconds,
                  autoCompleteDelaySeconds: definition.autoCompleteDelayDuration.inSeconds,
                ),
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
              reminders.add(
                AlarmReminder(
                  id: 'alarm_${id++}',
                  taskId: definition.id,
                  title: definition.title,
                  body: '到点了，点通知后去完成。',
                  whenEpochMillis: due.millisecondsSinceEpoch,
                  ringtoneSource: definition.ringtoneSource,
                  ringtoneLabel: definition.ringtoneLabel,
                  ringtoneValue: definition.ringtoneValue,
                  targetAppPackage: state.selectedAppPackage,
                  targetAppLabel: state.selectedAppLabel,
                  gestureConfigName: _gestureConfigName(
                    definition,
                    gestureConfigs,
                  ),
                  gestureActionsJson: _gestureActionsJson(
                    definition,
                    gestureConfigs,
                  ),
                  gestureLoopCount: _gestureLoopCount(
                    definition,
                    gestureConfigs,
                  ),
                  gestureLoopIntervalMillis: _gestureLoopIntervalMillis(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureConfigName: _preGestureConfigName(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureActionsJson: _preGestureActionsJson(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureLoopCount: _preGestureLoopCount(
                    definition,
                    gestureConfigs,
                  ),
                  preGestureLoopIntervalMillis: _preGestureLoopIntervalMillis(
                    definition,
                    gestureConfigs,
                  ),
                  autoOpenDelaySeconds: definition.autoOpenDelaySeconds,
                  autoCompleteDelaySeconds: definition.autoCompleteDelayDuration.inSeconds,
                ),
              );
            }
          }
          break;
      }
    }

    if (Platform.isAndroid) {
      await _alarmBridge.replaceAlarms(reminders);
    }
  }

  GestureConfig? _gestureConfigFor(
    String? configId,
    List<GestureConfig> configs,
  ) {
    if (configId == null || configId.isEmpty) return null;
    return configs.where((config) => config.id == configId).firstOrNull;
  }

  String? _gestureConfigName(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    return _gestureConfigFor(definition.gestureConfigId, configs)?.name;
  }

  String? _gestureActionsJson(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    final config = _gestureConfigFor(definition.gestureConfigId, configs);
    if (config == null) return null;
    return jsonEncode(config.actions.map((action) => action.toJson()).toList());
  }

  int? _gestureLoopCount(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    return _gestureConfigFor(definition.gestureConfigId, configs)?.loopCount;
  }

  int? _gestureLoopIntervalMillis(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    return _gestureConfigFor(
      definition.gestureConfigId,
      configs,
    )?.loopIntervalMillis;
  }

  String? _preGestureConfigName(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    return _gestureConfigFor(definition.preGestureConfigId, configs)?.name;
  }

  String? _preGestureActionsJson(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    final config = _gestureConfigFor(definition.preGestureConfigId, configs);
    if (config == null) return null;
    return jsonEncode(config.actions.map((action) => action.toJson()).toList());
  }

  int? _preGestureLoopCount(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    return _gestureConfigFor(definition.preGestureConfigId, configs)?.loopCount;
  }

  int? _preGestureLoopIntervalMillis(
    AssistantTaskDefinition definition,
    List<GestureConfig> configs,
  ) {
    return _gestureConfigFor(
      definition.preGestureConfigId,
      configs,
    )?.loopIntervalMillis;
  }

  Future<void> _showSummary(DailyTaskState state) async {
    final body = state.taskDefinitions
        .where((task) => state.isHomeVisible(task.id))
        .take(3)
        .map((task) {
          switch (task.kind) {
            case AssistantTaskKind.adCooldown:
              return '${task.title} ${state.intervalCompleted(task.id)}/${task.targetCount}';
            case AssistantTaskKind.feedWindow:
            case AssistantTaskKind.fixedPoint:
              return '${task.title} ${state.isCompleted(task.id) ? '完成' : '未完'}';
          }
        })
        .join(' · ');
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

  DateTime _timeForToday(DateTime now, int hour, int minute) {
    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}
