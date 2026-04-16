import 'package:flutter/services.dart';

import '../models/task_models.dart';

class AlarmReminder {
  const AlarmReminder({
    required this.id,
    required this.taskId,
    required this.title,
    required this.body,
    required this.whenEpochMillis,
    required this.ringtoneSource,
    required this.ringtoneLabel,
    required this.ringtoneValue,
  });

  final String id;
  final String taskId;
  final String title;
  final String body;
  final int whenEpochMillis;
  final RingtoneSource ringtoneSource;
  final String ringtoneLabel;
  final String? ringtoneValue;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'title': title,
      'body': body,
      'whenEpochMillis': whenEpochMillis,
      'ringtoneSource': ringtoneSource.name,
      'ringtoneLabel': ringtoneLabel,
      'ringtoneValue': ringtoneValue,
    };
  }
}

class SystemRingtoneSelection {
  const SystemRingtoneSelection({required this.label, required this.uri});

  final String label;
  final String uri;
}

class AlarmBridge {
  static const MethodChannel _channel = MethodChannel('scriptapp/alarm');

  Future<void> replaceAlarms(List<AlarmReminder> reminders) async {
    await _channel.invokeMethod('replaceAlarms', {
      'reminders': reminders.map((it) => it.toJson()).toList(),
    });
  }

  Future<String?> consumeLaunchTaskId() async {
    final result = await _channel.invokeMethod<String>('consumeLaunchTaskId');
    return result;
  }

  Future<SystemRingtoneSelection?> pickSystemRingtone() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickSystemRingtone',
    );
    if (result == null) {
      return null;
    }
    final uri = result['uri'] as String?;
    final label = result['label'] as String?;
    if (uri == null || label == null) {
      return null;
    }
    return SystemRingtoneSelection(label: label, uri: uri);
  }

  Future<void> openExactAlarmSettings() async {
    await _channel.invokeMethod('openExactAlarmSettings');
  }

  Future<void> openNotificationSettings() async {
    await _channel.invokeMethod('openNotificationSettings');
  }

  Future<void> openFullScreenIntentSettings() async {
    await _channel.invokeMethod('openFullScreenIntentSettings');
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  Future<void> openOverlaySettings() async {
    await _channel.invokeMethod('openOverlaySettings');
  }

  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  Future<void> scheduleSelfTest(AlarmReminder reminder) async {
    await _channel.invokeMethod('scheduleSelfTest', {
      'reminder': reminder.toJson(),
    });
  }
}
