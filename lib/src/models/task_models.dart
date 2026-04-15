enum AssistantTaskKind { feedWindow, adCooldown, fixedPoint }

enum RingtoneSource { systemDefault, systemAlarm, filePath }

class AssistantTaskDefinition {
  const AssistantTaskDefinition({
    required this.id,
    required this.kind,
    required this.title,
    required this.startHour,
    required this.startMinute,
    this.endHour,
    this.endMinute,
    this.targetCount = 0,
    this.cooldownMinutes = 0,
    this.ringtoneLabel = '默认铃声',
    this.ringtoneSource = RingtoneSource.systemDefault,
    this.ringtoneValue,
    this.showQuickLaunch = false,
  });

  final String id;
  final AssistantTaskKind kind;
  final String title;
  final int startHour;
  final int startMinute;
  final int? endHour;
  final int? endMinute;
  final int targetCount;
  final int cooldownMinutes;
  final String ringtoneLabel;
  final RingtoneSource ringtoneSource;
  final String? ringtoneValue;
  final bool showQuickLaunch;

  String get timeLabel {
    if (endHour != null && endMinute != null) {
      return '${_two(startHour)}:${_two(startMinute)}-${_two(endHour!)}:${_two(endMinute!)}';
    }
    return '${_two(startHour)}:${_two(startMinute)}';
  }

  AssistantTaskDefinition copyWith({
    String? id,
    AssistantTaskKind? kind,
    String? title,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    int? targetCount,
    int? cooldownMinutes,
    String? ringtoneLabel,
    RingtoneSource? ringtoneSource,
    String? ringtoneValue,
    bool? showQuickLaunch,
    bool clearEnd = false,
  }) {
    return AssistantTaskDefinition(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: clearEnd ? null : (endHour ?? this.endHour),
      endMinute: clearEnd ? null : (endMinute ?? this.endMinute),
      targetCount: targetCount ?? this.targetCount,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      ringtoneLabel: ringtoneLabel ?? this.ringtoneLabel,
      ringtoneSource: ringtoneSource ?? this.ringtoneSource,
      ringtoneValue: ringtoneValue ?? this.ringtoneValue,
      showQuickLaunch: showQuickLaunch ?? this.showQuickLaunch,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'targetCount': targetCount,
      'cooldownMinutes': cooldownMinutes,
      'ringtoneLabel': ringtoneLabel,
      'ringtoneSource': ringtoneSource.name,
      'ringtoneValue': ringtoneValue,
      'showQuickLaunch': showQuickLaunch,
    };
  }

  factory AssistantTaskDefinition.fromJson(Map<String, Object?> json) {
    return AssistantTaskDefinition(
      id: json['id'] as String,
      kind: AssistantTaskKind.values.byName(json['kind'] as String),
      title: json['title'] as String,
      startHour: json['startHour'] as int,
      startMinute: json['startMinute'] as int,
      endHour: json['endHour'] as int?,
      endMinute: json['endMinute'] as int?,
      targetCount: json['targetCount'] as int? ?? 0,
      cooldownMinutes: json['cooldownMinutes'] as int? ?? 0,
      ringtoneLabel: json['ringtoneLabel'] as String? ?? '默认铃声',
      ringtoneSource: json['ringtoneSource'] == null
          ? RingtoneSource.systemDefault
          : RingtoneSource.values.byName(json['ringtoneSource'] as String),
      ringtoneValue: json['ringtoneValue'] as String?,
      showQuickLaunch: json['showQuickLaunch'] as bool? ?? false,
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class TaskTemplateGroup {
  const TaskTemplateGroup({
    required this.id,
    required this.name,
    required this.tasks,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final List<AssistantTaskDefinition> tasks;
  final bool builtIn;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'builtIn': builtIn,
      'tasks': tasks.map((task) => task.toJson()).toList(),
    };
  }

  factory TaskTemplateGroup.fromJson(Map<String, Object?> json) {
    return TaskTemplateGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      builtIn: json['builtIn'] as bool? ?? false,
      tasks: ((json['tasks'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<String, Object?>>()
          .map(AssistantTaskDefinition.fromJson)
          .toList(),
    );
  }
}

class DailyTaskState {
  const DailyTaskState({
    required this.dateKey,
    required this.taskDefinitions,
    required this.templateGroups,
    required this.enabledTaskIds,
    required this.homeVisibleTaskIds,
    required this.completedTaskIds,
    required this.intervalCompletedCounts,
    required this.intervalNextAvailableAt,
    required this.selectedAppPackage,
    required this.selectedAppLabel,
  });

  final String dateKey;
  final List<AssistantTaskDefinition> taskDefinitions;
  final List<TaskTemplateGroup> templateGroups;
  final Set<String> enabledTaskIds;
  final Set<String> homeVisibleTaskIds;
  final Set<String> completedTaskIds;
  final Map<String, int> intervalCompletedCounts;
  final Map<String, DateTime> intervalNextAvailableAt;
  final String selectedAppPackage;
  final String selectedAppLabel;

  factory DailyTaskState.freshFor(
    DateTime now,
    List<AssistantTaskDefinition> definitions, {
    List<TaskTemplateGroup> templateGroups = const [],
    String selectedAppPackage = 'com.ss.android.ugc.aweme.lite',
    String selectedAppLabel = '抖音极速版',
    Set<String>? homeVisibleTaskIds,
  }) {
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final taskIds = definitions.map((it) => it.id).toSet();
    return DailyTaskState(
      dateKey: dateKey,
      taskDefinitions: definitions,
      templateGroups: templateGroups,
      enabledTaskIds: taskIds,
      homeVisibleTaskIds: homeVisibleTaskIds ?? taskIds,
      completedTaskIds: const {},
      intervalCompletedCounts: const {},
      intervalNextAvailableAt: const {},
      selectedAppPackage: selectedAppPackage,
      selectedAppLabel: selectedAppLabel,
    );
  }

  bool isEnabled(String taskId) => enabledTaskIds.contains(taskId);

  bool isHomeVisible(String taskId) => homeVisibleTaskIds.contains(taskId);

  bool isCompleted(String taskId) => completedTaskIds.contains(taskId);

  int intervalCompleted(String taskId) => intervalCompletedCounts[taskId] ?? 0;

  DateTime? intervalNextAt(String taskId) => intervalNextAvailableAt[taskId];

  DailyTaskState copyWith({
    String? dateKey,
    List<AssistantTaskDefinition>? taskDefinitions,
    List<TaskTemplateGroup>? templateGroups,
    Set<String>? enabledTaskIds,
    Set<String>? homeVisibleTaskIds,
    Set<String>? completedTaskIds,
    Map<String, int>? intervalCompletedCounts,
    Map<String, DateTime>? intervalNextAvailableAt,
    String? selectedAppPackage,
    String? selectedAppLabel,
  }) {
    return DailyTaskState(
      dateKey: dateKey ?? this.dateKey,
      taskDefinitions: taskDefinitions ?? this.taskDefinitions,
      templateGroups: templateGroups ?? this.templateGroups,
      enabledTaskIds: enabledTaskIds ?? this.enabledTaskIds,
      homeVisibleTaskIds: homeVisibleTaskIds ?? this.homeVisibleTaskIds,
      completedTaskIds: completedTaskIds ?? this.completedTaskIds,
      intervalCompletedCounts:
          intervalCompletedCounts ?? this.intervalCompletedCounts,
      intervalNextAvailableAt:
          intervalNextAvailableAt ?? this.intervalNextAvailableAt,
      selectedAppPackage: selectedAppPackage ?? this.selectedAppPackage,
      selectedAppLabel: selectedAppLabel ?? this.selectedAppLabel,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'dateKey': dateKey,
      'taskDefinitions': taskDefinitions.map((item) => item.toJson()).toList(),
      'templateGroups': templateGroups.map((item) => item.toJson()).toList(),
      'enabledTaskIds': enabledTaskIds.toList(),
      'homeVisibleTaskIds': homeVisibleTaskIds.toList(),
      'completedTaskIds': completedTaskIds.toList(),
      'intervalCompletedCounts': intervalCompletedCounts,
      'intervalNextAvailableAt': intervalNextAvailableAt.map(
        (key, value) => MapEntry(key, value.millisecondsSinceEpoch),
      ),
      'selectedAppPackage': selectedAppPackage,
      'selectedAppLabel': selectedAppLabel,
    };
  }

  factory DailyTaskState.fromJson(
    Map<String, Object?> json, {
    required List<AssistantTaskDefinition> fallbackDefinitions,
  }) {
    final taskDefinitions =
        ((json['taskDefinitions'] as List<Object?>?) ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .map(AssistantTaskDefinition.fromJson)
            .toList();
    final effectiveDefinitions = taskDefinitions.isEmpty
        ? fallbackDefinitions
        : taskDefinitions;
    final templateGroups =
        ((json['templateGroups'] as List<Object?>?) ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .map(TaskTemplateGroup.fromJson)
            .toList();
    final legacyTemplateDefinitions =
        ((json['templateDefinitions'] as List<Object?>?) ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .map(AssistantTaskDefinition.fromJson)
            .toList();
    final enabled =
        ((json['enabledTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => '$item')
            .toSet();
    final visible =
        ((json['homeVisibleTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => '$item')
            .toSet();
    final completed =
        ((json['completedTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => '$item')
            .toSet();
    final oldAdCompleted = json['adCompleted'] as int? ?? 0;
    final oldAdNext = json['adNextAvailableAt'] as int?;

    final intervalCounts =
        (json['intervalCompletedCounts'] as Map<Object?, Object?>?)?.map(
          (key, value) => MapEntry('$key', value as int),
        ) ??
        (oldAdCompleted > 0 ? {'ads': oldAdCompleted} : <String, int>{});

    final intervalNext =
        (json['intervalNextAvailableAt'] as Map<Object?, Object?>?)?.map(
          (key, value) => MapEntry(
            '$key',
            DateTime.fromMillisecondsSinceEpoch(value as int),
          ),
        ) ??
        (oldAdNext != null
            ? {'ads': DateTime.fromMillisecondsSinceEpoch(oldAdNext)}
            : <String, DateTime>{});

    final taskIds = effectiveDefinitions.map((it) => it.id).toSet();
    return DailyTaskState(
      dateKey: json['dateKey'] as String,
      taskDefinitions: effectiveDefinitions,
      templateGroups: templateGroups.isNotEmpty
          ? templateGroups
          : (legacyTemplateDefinitions.isNotEmpty
                ? [
                    TaskTemplateGroup(
                      id: 'legacy_group',
                      name: '旧模板',
                      tasks: legacyTemplateDefinitions,
                    ),
                  ]
                : const []),
      enabledTaskIds: enabled.isEmpty ? taskIds : enabled,
      homeVisibleTaskIds: visible.isEmpty ? taskIds : visible,
      completedTaskIds: completed,
      intervalCompletedCounts: intervalCounts,
      intervalNextAvailableAt: intervalNext,
      selectedAppPackage:
          json['selectedAppPackage'] as String? ??
          'com.ss.android.ugc.aweme.lite',
      selectedAppLabel: json['selectedAppLabel'] as String? ?? '抖音极速版',
    );
  }
}

class ReminderPreview {
  const ReminderPreview({required this.label, required this.when});

  final String label;
  final DateTime when;

  String get timeLabel =>
      '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
}
