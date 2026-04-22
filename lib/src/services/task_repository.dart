import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_models.dart';

class TaskRepository {
  static const String _storageKey = 'daily_task_state_v1';
  static const String _gestureConfigsKey = 'gesture_configs_v1';
  static const String _unlockGestureConfigKey = 'unlock_gesture_config_v1';
  static const String _lastGestureConfigIdKey = 'last_gesture_config_id_v1';
  static const String _dailyMottosKey = 'daily_mottos_v1';
  static const String _dailyMottoEntriesKey = 'daily_motto_entries_v1';
  static const String _dailyMottoSourceUrlKey = 'daily_motto_source_url_v1';
  static const String _dailyMottoLastFetchDateKey =
      'daily_motto_last_fetch_date_v1';
  static const String _pinnedDailyMottoKey = 'pinned_daily_motto_v1';
  static const String _pinnedDailyMottoIdKey = 'pinned_daily_motto_id_v1';
  static const String _showDailyMottoMetaOnHomeKey =
      'show_daily_motto_meta_on_home_v1';
  static const String _dailyMottoImageUrlKey = 'daily_motto_image_url_v1';
  static const String _dailyMottoImagePathKey = 'daily_motto_image_path_v1';
  static const String _dailyMottoImageFetchDateKey =
      'daily_motto_image_fetch_date_v1';

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

  Future<String?> loadLastGestureConfigId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_lastGestureConfigIdKey);
  }

  Future<void> saveLastGestureConfigId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastGestureConfigIdKey, id);
  }

  Future<List<String>> loadDailyMottos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getStringList(_dailyMottosKey);
    return raw?.where((item) => item.trim().isNotEmpty).toList() ?? [];
  }

  Future<void> saveDailyMottos(List<String> mottos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _dailyMottosKey,
      mottos
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }

  Future<List<DailyMottoEntry>> loadDailyMottoEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_dailyMottoEntriesKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<Object?>;
        return decoded
            .whereType<Map<String, Object?>>()
            .map(DailyMottoEntry.fromJson)
            .where((item) => item.content.trim().isNotEmpty)
            .toList();
      } catch (_) {}
    }
    final legacy = prefs.getStringList(_dailyMottosKey) ?? const [];
    return legacy
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map(DailyMottoEntry.fromLegacy)
        .toList();
  }

  Future<void> saveDailyMottoEntries(List<DailyMottoEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = entries
        .map(
          (item) => item.copyWith(
            content: item.content.trim(),
            author: item.author?.trim(),
            poemTitle: item.poemTitle?.trim(),
          ),
        )
        .where((item) => item.content.isNotEmpty)
        .toList();
    await prefs.setString(
      _dailyMottoEntriesKey,
      jsonEncode(cleaned.map((item) => item.toJson()).toList()),
    );
    await prefs.setStringList(
      _dailyMottosKey,
      cleaned.map((item) => item.content).toList(),
    );
  }

  Future<String?> loadPinnedDailyMotto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final value = prefs.getString(_pinnedDailyMottoKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> savePinnedDailyMotto(String? motto) async {
    final prefs = await SharedPreferences.getInstance();
    final value = motto?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_pinnedDailyMottoKey);
      return;
    }
    await prefs.setString(_pinnedDailyMottoKey, value);
  }

  Future<String?> loadPinnedDailyMottoId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final value = prefs.getString(_pinnedDailyMottoIdKey)?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    final legacy = prefs.getString(_pinnedDailyMottoKey)?.trim();
    if (legacy == null || legacy.isEmpty) {
      return null;
    }
    final entries = await loadDailyMottoEntries();
    return entries
        .where((item) => item.content.trim() == legacy)
        .firstOrNull
        ?.id;
  }

  Future<void> savePinnedDailyMottoId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    final value = id?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_pinnedDailyMottoIdKey);
      return;
    }
    await prefs.setString(_pinnedDailyMottoIdKey, value);
  }

  Future<bool> loadShowDailyMottoMetaOnHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_showDailyMottoMetaOnHomeKey) ?? true;
  }

  Future<void> saveShowDailyMottoMetaOnHome(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showDailyMottoMetaOnHomeKey, value);
  }

  Future<String?> loadDailyMottoSourceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_dailyMottoSourceUrlKey);
  }

  Future<void> saveDailyMottoSourceUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_dailyMottoSourceUrlKey);
      return;
    }
    await prefs.setString(_dailyMottoSourceUrlKey, value);
  }

  Future<String?> loadDailyMottoLastFetchDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_dailyMottoLastFetchDateKey);
  }

  Future<void> saveDailyMottoLastFetchDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyMottoLastFetchDateKey, dateKey);
  }

  Future<String?> loadDailyMottoImageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final value = prefs.getString(_dailyMottoImageUrlKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveDailyMottoImageUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_dailyMottoImageUrlKey);
      return;
    }
    await prefs.setString(_dailyMottoImageUrlKey, value);
  }

  Future<String?> loadDailyMottoImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final value = prefs.getString(_dailyMottoImagePathKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveDailyMottoImagePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final value = path?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_dailyMottoImagePathKey);
      return;
    }
    await prefs.setString(_dailyMottoImagePathKey, value);
  }

  Future<String?> loadDailyMottoImageFetchDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_dailyMottoImageFetchDateKey);
  }

  Future<void> saveDailyMottoImageFetchDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyMottoImageFetchDateKey, dateKey);
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
    await prefs.reload();
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
