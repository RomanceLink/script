import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_models.dart';

class TaskRepository {
  static const String _storageKey = 'daily_task_state_v1';
  static const String _gestureConfigsKey = 'gesture_configs_v1';
  static const String _unlockGestureConfigKey = 'unlock_gesture_config_v1';

  Future<List<GestureConfig>> loadGestureConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_gestureConfigsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return decoded
          .whereType<Map<String, Object?>>()
          .map(GestureConfig.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGestureConfigs(List<GestureConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _gestureConfigsKey,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  Future<GestureConfig?> loadUnlockGestureConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_unlockGestureConfigKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return GestureConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUnlockGestureConfig(GestureConfig? config) async {
    final prefs = await SharedPreferences.getInstance();
    if (config == null) {
      await prefs.remove(_unlockGestureConfigKey);
      return;
    }
    await prefs.setString(_unlockGestureConfigKey, jsonEncode(config.toJson()));
  }

  Future<DailyTaskState> loadOrCreateToday(
    List<AssistantTaskDefinition> definitions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final fresh = DailyTaskState.freshFor(DateTime.now(), definitions);

    if (raw == null) {
      await save(fresh);
      return fresh;
    }

    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final state = DailyTaskState.fromJson(
      decoded,
      fallbackDefinitions: definitions,
    );

    if (state.dateKey != fresh.dateKey) {
      final reset = DailyTaskState.freshFor(
        DateTime.now(),
        state.taskDefinitions,
        templateGroups: state.templateGroups,
        selectedAppPackage: state.selectedAppPackage,
        selectedAppLabel: state.selectedAppLabel,
        homeVisibleTaskIds: state.homeVisibleTaskIds,
        enabledTaskIds: state.enabledTaskIds,
      );
      await save(reset);
      return reset;
    }

    if (state.taskDefinitions.isEmpty) {
      await save(fresh);
      return fresh;
    }

    return state;
  }

  Future<void> save(DailyTaskState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(state.toJson()));
  }
}
