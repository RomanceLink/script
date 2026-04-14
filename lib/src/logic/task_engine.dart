import '../models/task_models.dart';

class TaskEngine {
  static bool isTaskEnabled(DailyTaskState state, String taskId) {
    return state.isEnabled(taskId);
  }

  static bool isFeedWindowActive(
    DateTime now,
    AssistantTaskDefinition definition,
  ) {
    final start = _timeForToday(
      now,
      definition.startHour,
      definition.startMinute,
    );
    final end = _timeForToday(now, definition.endHour!, definition.endMinute!);
    return !now.isBefore(start) && now.isBefore(end);
  }

  static bool canCompleteAd(DateTime now, DailyTaskState state) {
    final next = state.adNextAvailableAt;
    return next == null || !now.isBefore(next);
  }

  static bool isTaskDone(DailyTaskState state, String taskId) {
    return state.isCompleted(taskId);
  }

  static bool isFixedTaskDue(DateTime now, AssistantTaskDefinition definition) {
    final due = _timeForToday(
      now,
      definition.startHour,
      definition.startMinute,
    );
    return !now.isBefore(due);
  }

  static String adCountdownLabel(DateTime now, DailyTaskState state) {
    if (!state.isEnabled('ads')) {
      return '今日已关闭此任务。';
    }
    if (state.adCompleted >= 20) {
      return '今日广告已满 20 次。';
    }
    final next = state.adNextAvailableAt;
    if (next == null || !now.isBefore(next)) {
      return '现在可做下一次广告。';
    }
    final remaining = next.difference(now);
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '距下次广告 ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static ReminderPreview? nextReminder(
    DateTime now,
    DailyTaskState state,
    List<AssistantTaskDefinition> definitions,
  ) {
    final candidates = <ReminderPreview>[];

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
          if (now.isBefore(start)) {
            candidates.add(
              ReminderPreview(label: definition.title, when: start),
            );
          }
          break;
        case AssistantTaskKind.adCooldown:
          if (state.adCompleted < definition.targetCount) {
            final when =
                state.adNextAvailableAt ??
                _timeForToday(
                  now,
                  definition.startHour,
                  definition.startMinute,
                );
            if (when.isAfter(now)) {
              candidates.add(
                ReminderPreview(label: definition.title, when: when),
              );
            }
          }
          break;
        case AssistantTaskKind.fixedPoint:
          if (!state.isCompleted(definition.id)) {
            final when = _timeForToday(
              now,
              definition.startHour,
              definition.startMinute,
            );
            if (when.isAfter(now)) {
              candidates.add(
                ReminderPreview(label: definition.title, when: when),
              );
            }
          }
          break;
      }
    }

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => a.when.compareTo(b.when));
    return candidates.first;
  }

  static DateTime _timeForToday(DateTime now, int hour, int minute) {
    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}
