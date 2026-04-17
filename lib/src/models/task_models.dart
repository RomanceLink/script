enum AssistantTaskKind { feedWindow, adCooldown, fixedPoint }

enum RingtoneSource { systemDefault, systemAlarm, filePath }

enum IntervalUnit { seconds, minutes, hours, days }

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
    this.cooldownValue = 0,
    this.intervalUnit = IntervalUnit.minutes,
    this.ringtoneLabel = '默认铃声',
    this.ringtoneSource = RingtoneSource.systemDefault,
    this.ringtoneValue,
    this.showQuickLaunch = false,
    this.gestureConfigId,
  });

  final String id;
  final AssistantTaskKind kind;
  final String title;
  final int startHour;
  final int startMinute;
  final int? endHour;
  final int? endMinute;
  final int targetCount;
  final int cooldownValue;
  final IntervalUnit intervalUnit;
  final String ringtoneLabel;
  final RingtoneSource ringtoneSource;
  final String? ringtoneValue;
  final bool showQuickLaunch;
  final String? gestureConfigId;

  String get timeLabel {
    if (endHour != null && endMinute != null) {
      return '${_two(startHour)}:${_two(startMinute)}-${_two(endHour!)}:${_two(endMinute!)}';
    }
    return '${_two(startHour)}:${_two(startMinute)}';
  }

  Duration get cooldownDuration {
    return switch (intervalUnit) {
      IntervalUnit.seconds => Duration(seconds: cooldownValue),
      IntervalUnit.minutes => Duration(minutes: cooldownValue),
      IntervalUnit.hours => Duration(hours: cooldownValue),
      IntervalUnit.days => Duration(days: cooldownValue),
    };
  }

  String get intervalLabel {
    final unit = switch (intervalUnit) {
      IntervalUnit.seconds => '秒',
      IntervalUnit.minutes => '分钟',
      IntervalUnit.hours => '小时',
      IntervalUnit.days => '天',
    };
    return '$cooldownValue $unit';
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
    int? cooldownValue,
    IntervalUnit? intervalUnit,
    String? ringtoneLabel,
    RingtoneSource? ringtoneSource,
    String? ringtoneValue,
    bool? showQuickLaunch,
    String? gestureConfigId,
    bool clearEnd = false,
    bool clearGesture = false,
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
      cooldownValue: cooldownValue ?? this.cooldownValue,
      intervalUnit: intervalUnit ?? this.intervalUnit,
      ringtoneLabel: ringtoneLabel ?? this.ringtoneLabel,
      ringtoneSource: ringtoneSource ?? this.ringtoneSource,
      ringtoneValue: ringtoneValue ?? this.ringtoneValue,
      showQuickLaunch: showQuickLaunch ?? this.showQuickLaunch,
      gestureConfigId: clearGesture ? null : (gestureConfigId ?? this.gestureConfigId),
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
      'cooldownValue': cooldownValue,
      'intervalUnit': intervalUnit.name,
      'ringtoneLabel': ringtoneLabel,
      'ringtoneSource': ringtoneSource.name,
      'ringtoneValue': ringtoneValue,
      'showQuickLaunch': showQuickLaunch,
      'gestureConfigId': gestureConfigId,
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
      cooldownValue:
          json['cooldownValue'] as int? ?? json['cooldownMinutes'] as int? ?? 0,
      intervalUnit: json['intervalUnit'] == null
          ? IntervalUnit.minutes
          : IntervalUnit.values.byName(json['intervalUnit'] as String),
      ringtoneLabel: json['ringtoneLabel'] as String? ?? '默认铃声',
      ringtoneSource: json['ringtoneSource'] == null
          ? RingtoneSource.systemDefault
          : RingtoneSource.values.byName(json['ringtoneSource'] as String),
      ringtoneValue: json['ringtoneValue'] as String?,
      showQuickLaunch: json['showQuickLaunch'] as bool? ?? false,
      gestureConfigId: json['gestureConfigId'] as String?,
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

enum GestureActionType { swipe, click, nav, wait, launchApp }

sealed class GestureAction {
  const GestureAction({required this.type});
  final GestureActionType type;

  Map<String, Object?> toJson();

  factory GestureAction.fromJson(Map<String, Object?> json) {
    final type = GestureActionType.values.byName(json['type'] as String);
    return switch (type) {
      GestureActionType.swipe => SwipeAction.fromJson(json),
      GestureActionType.click => ClickAction.fromJson(json),
      GestureActionType.nav => NavAction.fromJson(json),
      GestureActionType.wait => WaitAction.fromJson(json),
      GestureActionType.launchApp => LaunchAppAction.fromJson(json),
    };
  }
}

class SwipeAction extends GestureAction {
  const SwipeAction({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.duration = 400,
  }) : super(type: GestureActionType.swipe);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final int duration;

  @override
  Map<String, Object?> toJson() => {
        'type': type.name,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'duration': duration,
      };

  factory SwipeAction.fromJson(Map<String, Object?> json) => SwipeAction(
        x1: (json['x1'] as num).toDouble(),
        y1: (json['y1'] as num).toDouble(),
        x2: (json['x2'] as num).toDouble(),
        y2: (json['y2'] as num).toDouble(),
        duration: json['duration'] as int? ?? 400,
      );
}

class ClickAction extends GestureAction {
  const ClickAction({
    required this.x1,
    required this.y1,
    this.duration = 50,
  }) : super(type: GestureActionType.click);

  final double x1;
  final double y1;
  final int duration;

  @override
  Map<String, Object?> toJson() => {
        'type': type.name,
        'x1': x1,
        'y1': y1,
        'duration': duration,
      };

  factory ClickAction.fromJson(Map<String, Object?> json) => ClickAction(
        x1: (json['x1'] as num).toDouble(),
        y1: (json['y1'] as num).toDouble(),
        duration: json['duration'] as int? ?? 50,
      );
}

enum NavType { back, home, recents }

class NavAction extends GestureAction {
  const NavAction({required this.navType}) : super(type: GestureActionType.nav);
  final NavType navType;

  @override
  Map<String, Object?> toJson() => {
        'type': type.name,
        'navType': navType.name,
      };

  factory NavAction.fromJson(Map<String, Object?> json) => NavAction(
        navType: NavType.values.byName(json['navType'] as String),
      );
}

class WaitAction extends GestureAction {
  const WaitAction({required this.seconds})
      : super(type: GestureActionType.wait);
  final int seconds;

  @override
  Map<String, Object?> toJson() => {
        'type': type.name,
        'seconds': seconds,
      };

  factory WaitAction.fromJson(Map<String, Object?> json) => WaitAction(
        seconds: json['seconds'] as int,
      );
}

class LaunchAppAction extends GestureAction {
  const LaunchAppAction({required this.packageName, required this.label})
      : super(type: GestureActionType.launchApp);
  final String packageName;
  final String label;

  @override
  Map<String, Object?> toJson() => {
        'type': type.name,
        'packageName': packageName,
        'label': label,
      };

  factory LaunchAppAction.fromJson(Map<String, Object?> json) => LaunchAppAction(
        packageName: json['packageName'] as String,
        label: json['label'] as String? ?? '应用',
      );
}

class GestureConfig {
  const GestureConfig({
    required this.id,
    required this.name,
    this.actions = const [],
  });

  final String id;
  final String name;
  final List<GestureAction> actions;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory GestureConfig.fromJson(Map<String, Object?> json) {
    return GestureConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      actions: ((json['actions'] as List<Object?>?) ?? [])
          .whereType<Map<String, Object?>>()
          .map(GestureAction.fromJson)
          .toList(),
    );
  }

  GestureConfig copyWith({
    String? id,
    String? name,
    List<GestureAction>? actions,
  }) {
    return GestureConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      actions: actions ?? this.actions,
    );
  }
}

class TaskTemplateGroup {
  const TaskTemplateGroup({
    required this.id,
    required this.name,
    required this.tasks,
    this.enabledTaskIds = const {},
    this.homeVisibleTaskIds = const {},
    this.builtIn = false,
  });

  final String id;
  final String name;
  final List<AssistantTaskDefinition> tasks;
  final Set<String> enabledTaskIds;
  final Set<String> homeVisibleTaskIds;
  final bool builtIn;

  Set<String> get effectiveEnabledTaskIds {
    return enabledTaskIds.isEmpty
        ? tasks.map((task) => task.id).toSet()
        : enabledTaskIds;
  }

  Set<String> get effectiveHomeVisibleTaskIds {
    return homeVisibleTaskIds.isEmpty
        ? tasks.map((task) => task.id).toSet()
        : homeVisibleTaskIds;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'builtIn': builtIn,
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'enabledTaskIds': effectiveEnabledTaskIds.toList(),
      'homeVisibleTaskIds': effectiveHomeVisibleTaskIds.toList(),
    };
  }

  factory TaskTemplateGroup.fromJson(Map<String, Object?> json) {
    final tasks = ((json['tasks'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map<String, Object?>>()
        .map(AssistantTaskDefinition.fromJson)
        .toList();
    final taskIds = tasks.map((task) => task.id).toSet();
    final enabled =
        ((json['enabledTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .whereType<String>()
            .where(taskIds.contains)
            .toSet();
    final visible =
        ((json['homeVisibleTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .whereType<String>()
            .where(taskIds.contains)
            .toSet();
    return TaskTemplateGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      builtIn: json['builtIn'] as bool? ?? false,
      tasks: tasks,
      enabledTaskIds: enabled.isEmpty ? taskIds : enabled,
      homeVisibleTaskIds: visible.isEmpty ? taskIds : visible,
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
    Set<String>? enabledTaskIds,
  }) {
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final taskIds = definitions.map((it) => it.id).toSet();
    return DailyTaskState(
      dateKey: dateKey,
      taskDefinitions: definitions,
      templateGroups: templateGroups,
      enabledTaskIds: enabledTaskIds ?? taskIds,
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
          (key, value) => MapEntry('$key', (value as num).toInt()),
        ) ??
        (oldAdCompleted > 0 ? {'ads': oldAdCompleted} : <String, int>{});

    final intervalNext =
        (json['intervalNextAvailableAt'] as Map<Object?, Object?>?)?.map(
          (key, value) => MapEntry(
            '$key',
            DateTime.fromMillisecondsSinceEpoch((value as num).toInt()),
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
