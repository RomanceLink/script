enum AssistantTaskKind { feedWindow, adCooldown, fixedPoint }

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
    this.chunkMinutes = 0,
    this.cooldownMinutes = 0,
  });

  final String id;
  final AssistantTaskKind kind;
  final String title;
  final int startHour;
  final int startMinute;
  final int? endHour;
  final int? endMinute;
  final int targetCount;
  final int chunkMinutes;
  final int cooldownMinutes;

  String get timeLabel {
    if (endHour != null && endMinute != null) {
      return '${_two(startHour)}:${_two(startMinute)}-${_two(endHour!)}:${_two(endMinute!)}';
    }
    return '${_two(startHour)}:${_two(startMinute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class DailyTaskState {
  const DailyTaskState({
    required this.dateKey,
    required this.enabledTaskIds,
    required this.completedTaskIds,
    required this.adCompleted,
    required this.adNextAvailableAt,
  });

  final String dateKey;
  final Set<String> enabledTaskIds;
  final Set<String> completedTaskIds;
  final int adCompleted;
  final DateTime? adNextAvailableAt;

  factory DailyTaskState.freshFor(
    DateTime now,
    List<AssistantTaskDefinition> definitions,
  ) {
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return DailyTaskState(
      dateKey: dateKey,
      enabledTaskIds: definitions.map((it) => it.id).toSet(),
      completedTaskIds: const {},
      adCompleted: 0,
      adNextAvailableAt: null,
    );
  }

  bool isEnabled(String taskId) => enabledTaskIds.contains(taskId);

  bool isCompleted(String taskId) => completedTaskIds.contains(taskId);

  DailyTaskState copyWith({
    Set<String>? enabledTaskIds,
    Set<String>? completedTaskIds,
    int? adCompleted,
    DateTime? adNextAvailableAt,
    bool clearAdNextAvailableAt = false,
  }) {
    return DailyTaskState(
      dateKey: dateKey,
      enabledTaskIds: enabledTaskIds ?? this.enabledTaskIds,
      completedTaskIds: completedTaskIds ?? this.completedTaskIds,
      adCompleted: adCompleted ?? this.adCompleted,
      adNextAvailableAt: clearAdNextAvailableAt
          ? null
          : (adNextAvailableAt ?? this.adNextAvailableAt),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'dateKey': dateKey,
      'enabledTaskIds': enabledTaskIds.toList(),
      'completedTaskIds': completedTaskIds.toList(),
      'adCompleted': adCompleted,
      'adNextAvailableAt': adNextAvailableAt?.millisecondsSinceEpoch,
    };
  }

  factory DailyTaskState.fromJson(Map<String, Object?> json) {
    final enabled =
        ((json['enabledTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => '$item')
            .toSet();
    final completed =
        ((json['completedTaskIds'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => '$item')
            .toSet();
    final epoch = json['adNextAvailableAt'] as int?;

    return DailyTaskState(
      dateKey: json['dateKey'] as String,
      enabledTaskIds: enabled,
      completedTaskIds: completed,
      adCompleted: json['adCompleted'] as int? ?? 0,
      adNextAvailableAt: epoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch),
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
