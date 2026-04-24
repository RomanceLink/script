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
      final gesturePlan = _gestureExecutionPlan(
        definition.gestureConfigId,
        gestureConfigs,
      );
      final preGesturePlan = _gestureExecutionPlan(
        definition.preGestureConfigId,
        gestureConfigs,
        allowInfinite: false,
      );
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
                gestureConfigName: gesturePlan?.name,
                gestureBeforeLoopActionsJson: _actionsJsonOrNull(
                  gesturePlan?.beforeLoopActions,
                ),
                gestureActionsJson: _actionsJsonOrNull(
                  gesturePlan?.loopActions,
                ),
                gestureLoopCount: gesturePlan?.loopCount,
                gestureLoopIntervalMillis: gesturePlan?.loopIntervalMillis,
                gestureInfiniteLoop: gesturePlan?.infiniteLoop,
                preGestureConfigName: preGesturePlan?.name,
                preGestureActionsJson: _actionsJsonOrNull(
                  preGesturePlan == null
                      ? null
                      : [
                          ...preGesturePlan.beforeLoopActions,
                          ...preGesturePlan.loopActions,
                        ],
                ),
                preGestureLoopCount: preGesturePlan == null ? null : 1,
                preGestureLoopIntervalMillis: preGesturePlan == null ? null : 0,
                autoOpenDelaySeconds: definition.autoOpenDelaySeconds,
                autoCompleteDelaySeconds:
                    definition.autoCompleteDelayDuration.inSeconds,
              ),
            );
          }
          break;
        case AssistantTaskKind.adCooldown:
          if (definition.infiniteLoop ||
              state.intervalCompleted(definition.id) < definition.targetCount) {
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
                  gestureConfigName: gesturePlan?.name,
                  gestureBeforeLoopActionsJson: _actionsJsonOrNull(
                    gesturePlan?.beforeLoopActions,
                  ),
                  gestureActionsJson: _actionsJsonOrNull(
                    gesturePlan?.loopActions,
                  ),
                  gestureLoopCount: gesturePlan?.loopCount,
                  gestureLoopIntervalMillis: gesturePlan?.loopIntervalMillis,
                  gestureInfiniteLoop: gesturePlan?.infiniteLoop,
                  preGestureConfigName: preGesturePlan?.name,
                  preGestureActionsJson: _actionsJsonOrNull(
                    preGesturePlan == null
                        ? null
                        : [
                            ...preGesturePlan.beforeLoopActions,
                            ...preGesturePlan.loopActions,
                          ],
                  ),
                  preGestureLoopCount: preGesturePlan == null ? null : 1,
                  preGestureLoopIntervalMillis: preGesturePlan == null
                      ? null
                      : 0,
                  autoOpenDelaySeconds: definition.autoOpenDelaySeconds,
                  autoCompleteDelaySeconds:
                      definition.autoCompleteDelayDuration.inSeconds,
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
                  gestureConfigName: gesturePlan?.name,
                  gestureBeforeLoopActionsJson: _actionsJsonOrNull(
                    gesturePlan?.beforeLoopActions,
                  ),
                  gestureActionsJson: _actionsJsonOrNull(
                    gesturePlan?.loopActions,
                  ),
                  gestureLoopCount: gesturePlan?.loopCount,
                  gestureLoopIntervalMillis: gesturePlan?.loopIntervalMillis,
                  gestureInfiniteLoop: gesturePlan?.infiniteLoop,
                  preGestureConfigName: preGesturePlan?.name,
                  preGestureActionsJson: _actionsJsonOrNull(
                    preGesturePlan == null
                        ? null
                        : [
                            ...preGesturePlan.beforeLoopActions,
                            ...preGesturePlan.loopActions,
                          ],
                  ),
                  preGestureLoopCount: preGesturePlan == null ? null : 1,
                  preGestureLoopIntervalMillis: preGesturePlan == null
                      ? null
                      : 0,
                  autoOpenDelaySeconds: definition.autoOpenDelaySeconds,
                  autoCompleteDelaySeconds:
                      definition.autoCompleteDelayDuration.inSeconds,
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

  ({
    String name,
    List<Map<String, Object?>> beforeLoopActions,
    List<Map<String, Object?>> loopActions,
    int loopCount,
    int loopIntervalMillis,
    bool infiniteLoop,
  })?
  _gestureExecutionPlan(
    String? configId,
    List<GestureConfig> configs, {
    bool allowInfinite = true,
  }) {
    final config = _gestureConfigFor(configId, configs);
    return _resolveGestureExecutionPlan(
      config,
      configs,
      allowInfinite: allowInfinite,
    );
  }

  ({
    String name,
    List<Map<String, Object?>> beforeLoopActions,
    List<Map<String, Object?>> loopActions,
    int loopCount,
    int loopIntervalMillis,
    bool infiniteLoop,
  })?
  _resolveGestureExecutionPlan(
    GestureConfig? config,
    List<GestureConfig> configs, {
    bool allowInfinite = true,
    Set<String>? visited,
  }) {
    if (config == null) {
      return null;
    }
    final nextVisited = {...?visited};
    if (!nextVisited.add(config.id)) {
      return (
        name: config.name,
        beforeLoopActions: _expandFiniteConfigActions(config),
        loopActions: const [],
        loopCount: 1,
        loopIntervalMillis: 0,
        infiniteLoop: false,
      );
    }
    if (config.infiniteLoop && allowInfinite) {
      return (
        name: config.name,
        beforeLoopActions: const [],
        loopActions: config.actions.map((action) => action.toJson()).toList(),
        loopCount: config.loopCount,
        loopIntervalMillis: config.loopIntervalMillis,
        infiniteLoop: true,
      );
    }
    final currentActions = _expandFiniteConfigActions(config);
    final child = configs
        .where((item) => item.id == config.followUpConfigId)
        .firstOrNull;
    final childPlan = _resolveGestureExecutionPlan(
      child,
      configs,
      allowInfinite: allowInfinite,
      visited: nextVisited,
    );
    if (childPlan == null) {
      return (
        name: config.name,
        beforeLoopActions: currentActions,
        loopActions: const [],
        loopCount: 1,
        loopIntervalMillis: 0,
        infiniteLoop: false,
      );
    }
    return (
      name: '${config.name} -> ${childPlan.name}',
      beforeLoopActions: [...currentActions, ...childPlan.beforeLoopActions],
      loopActions: childPlan.loopActions,
      loopCount: childPlan.loopCount,
      loopIntervalMillis: childPlan.loopIntervalMillis,
      infiniteLoop: childPlan.infiniteLoop,
    );
  }

  List<Map<String, Object?>> _expandFiniteConfigActions(GestureConfig config) {
    final out = <Map<String, Object?>>[];
    final loops = config.loopCount.clamp(1, 9999);
    for (var i = 0; i < loops; i++) {
      out.addAll(config.actions.map((action) => action.toJson()));
      if (i < loops - 1 && config.loopIntervalMillis > 0) {
        out.add(
          WaitAction.fixedMilliseconds(
            milliseconds: config.loopIntervalMillis,
          ).toJson(),
        );
      }
    }
    return out;
  }

  String? _actionsJsonOrNull(List<Map<String, Object?>>? actions) {
    if (actions == null || actions.isEmpty) {
      return null;
    }
    return jsonEncode(actions);
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
