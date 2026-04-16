import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_models.dart';

class TaskRepository {
  static const String _storageKey = 'daily_task_state_v1';

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
