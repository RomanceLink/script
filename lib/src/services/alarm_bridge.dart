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
    this.ringtoneLabel = '默认铃声',
    this.ringtoneValue,
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

class AlarmBridge {
  static const _channel = MethodChannel('scriptapp/alarm');

  Future<void> replaceAlarms(List<AlarmReminder> reminders) async {
    await _channel.invokeMethod('replaceAlarms', {
      'reminders': reminders.map((r) => r.toJson()).toList(),
    });
  }

  Future<String?> consumeLaunchTaskId() async {
    final value = await _channel.invokeMethod<String>('consumeLaunchTaskId');
    return value;
  }

  Future<({String uri, String label})?> pickSystemRingtone() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'pickSystemRingtone',
    );
    if (result == null) return null;
    return (uri: result['uri']!, label: result['label']!);
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

  Future<Map<String, Object?>?> enterPickerMode(String type) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'enterPickerMode',
      {'type': type},
    );
    return result;
  }

  Future<String?> consumeOverlayCommand() async {
    final value = await _channel.invokeMethod<String>('consumeOverlayCommand');
    return value;
  }

  Future<bool> showAutomationMenu({
    required List<Map<String, Object?>> configs,
  }) async {
    final result = await _channel.invokeMethod<bool>('showAutomationMenu', {
      'configs': configs,
    });
    return result ?? false;
  }

  Future<bool> syncAutomationConfigs({
    required List<Map<String, Object?>> configs,
  }) async {
    final result = await _channel.invokeMethod<bool>('syncAutomationConfigs', {
      'configs': configs,
    });
    return result ?? false;
  }

  Future<void> runGestureConfig({
    required String name,
    required List<Map<String, Object?>> actions,
  }) async {
    await _channel.invokeMethod('performAutoSwipe', {
      'min':
          0, // In scripted mode, we might not use random intervals at the top level
      'max': 0,
      'actions': actions,
      'name': name,
    });
  }

  Future<void> performAutoSwipe({
    required int min,
    required int max,
    required List<Map<String, Object?>> actions,
  }) async {
    await _channel.invokeMethod('performAutoSwipe', {
      'min': min,
      'max': max,
      'actions': actions,
    });
  }
}
