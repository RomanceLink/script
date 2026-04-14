import 'dart:async';

import 'package:flutter/material.dart';

import 'logic/task_definitions.dart';
import 'logic/task_engine.dart';
import 'models/task_models.dart';
import 'services/douyin_launcher.dart';
import 'services/notification_service.dart';
import 'services/task_repository.dart';

class ScriptAssistantApp extends StatelessWidget {
  const ScriptAssistantApp({super.key, this.enablePlatformServices = true});

  final bool enablePlatformServices;

  @override
  Widget build(BuildContext context) {
    const shell = Color(0xFFF5F0E4);
    const ink = Color(0xFF201B17);
    const rust = Color(0xFFB65E35);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Task Sprite',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: shell,
        colorScheme: ColorScheme.fromSeed(
          seedColor: rust,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
      ),
      home: DashboardPage(enablePlatformServices: enablePlatformServices),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.enablePlatformServices, super.key});

  final bool enablePlatformServices;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TaskRepository _repository = TaskRepository();
  final NotificationService _notifications = NotificationService();
  final DouyinLauncher _launcher = DouyinLauncher();
  final List<AssistantTaskDefinition> _definitions = defaultTaskDefinitions;

  late Timer _ticker;
  DailyTaskState? _state;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final state = _state;
      if (state != null && state.dateKey != _todayKey(DateTime.now())) {
        await _resetToday(showMessage: false);
      }
      if (mounted) {
        setState(() {});
      }
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (widget.enablePlatformServices) {
        await _notifications.initialize();
      }
      final state = await _repository.loadOrCreateToday(_definitions);
      if (widget.enablePlatformServices) {
        await _notifications.scheduleForState(state, _definitions);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _mutateState(
    DailyTaskState Function(DailyTaskState state) transform, {
    String? message,
  }) async {
    final current = _state;
    if (current == null) {
      return;
    }
    final next = transform(current);
    await _repository.save(next);
    if (widget.enablePlatformServices) {
      await _notifications.scheduleForState(next, _definitions);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _state = next;
    });
    if (message != null) {
      _showMessage(message);
    }
  }

  Future<void> _toggleTask(String taskId, bool enabled) async {
    await _mutateState((state) {
      final nextEnabled = {...state.enabledTaskIds};
      final nextCompleted = {...state.completedTaskIds};

      if (enabled) {
        nextEnabled.add(taskId);
      } else {
        nextEnabled.remove(taskId);
        nextCompleted.remove(taskId);
      }

      final isAds = taskId == 'ads';
      return state.copyWith(
        enabledTaskIds: nextEnabled,
        completedTaskIds: nextCompleted,
        adCompleted: isAds && !enabled ? 0 : state.adCompleted,
        adNextAvailableAt: isAds && !enabled ? null : state.adNextAvailableAt,
        clearAdNextAvailableAt: isAds && !enabled,
      );
    }, message: enabled ? '任务已开启' : '任务已关闭');
  }

  Future<void> _markFeedDone(String taskId) async {
    await _mutateState((state) {
      return state.copyWith(
        completedTaskIds: {...state.completedTaskIds, taskId},
      );
    }, message: '已标记完成');
  }

  Future<void> _markFixedDone(String taskId) async {
    await _mutateState((state) {
      return state.copyWith(
        completedTaskIds: {...state.completedTaskIds, taskId},
      );
    }, message: '已标记完成');
  }

  Future<void> _markAdDone() async {
    final now = DateTime.now();
    await _mutateState((state) {
      final nextCount = (state.adCompleted + 1).clamp(0, 20);
      return state.copyWith(
        adCompleted: nextCount,
        adNextAvailableAt: nextCount >= 20
            ? null
            : now.add(const Duration(minutes: 10)),
        clearAdNextAvailableAt: nextCount >= 20,
      );
    }, message: '广告已记录，10 分钟后再提醒');
  }

  Future<void> _resetToday({bool showMessage = true}) async {
    final fresh = DailyTaskState.freshFor(DateTime.now(), _definitions);
    await _repository.save(fresh);
    if (widget.enablePlatformServices) {
      await _notifications.scheduleForState(fresh, _definitions);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _state = fresh;
    });
    if (showMessage) {
      _showMessage('今日记录已重置');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _todayKey(DateTime now) {
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!),
          ),
        ),
      );
    }

    final state = _state!;
    final nextReminder = TaskEngine.nextReminder(now, state, _definitions);
    final enabledCount = _definitions
        .where((task) => state.isEnabled(task.id))
        .length;
    final completedCount = _definitions.where((task) {
      if (!state.isEnabled(task.id)) {
        return false;
      }
      if (task.kind == AssistantTaskKind.adCooldown) {
        return state.adCompleted >= task.targetCount;
      }
      return state.isCompleted(task.id);
    }).length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8F4EA), Color(0xFFE7D8BE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _HeaderCard(
                dateLabel: state.dateKey,
                enabledCount: enabledCount,
                completedCount: completedCount,
                nextReminder: nextReminder,
                onOpenDouyin: _launcher.openDouyin,
                onReset: _resetToday,
              ),
              const SizedBox(height: 16),
              _TaskSectionLabel(title: '今日任务', subtitle: '每项可独立展开、关闭、完成。'),
              const SizedBox(height: 12),
              ..._definitions.map((definition) {
                switch (definition.kind) {
                  case AssistantTaskKind.feedWindow:
                    return _ExpandableTaskCard(
                      title: definition.title,
                      timeLabel: definition.timeLabel,
                      enabled: state.isEnabled(definition.id),
                      badge: state.isCompleted(definition.id) ? '已完成' : '待完成',
                      badgeColor: state.isCompleted(definition.id)
                          ? const Color(0xFF2E7D4F)
                          : const Color(0xFFB65E35),
                      onToggle: (value) => _toggleTask(definition.id, value),
                      child: _FeedTaskBody(
                        definition: definition,
                        enabled: state.isEnabled(definition.id),
                        isActive: TaskEngine.isFeedWindowActive(
                          now,
                          definition,
                        ),
                        isDone: state.isCompleted(definition.id),
                        onDone: () => _markFeedDone(definition.id),
                      ),
                    );
                  case AssistantTaskKind.adCooldown:
                    return _ExpandableTaskCard(
                      title: definition.title,
                      timeLabel: '每日 ${definition.targetCount} 次',
                      enabled: state.isEnabled(definition.id),
                      badge: '${state.adCompleted}/${definition.targetCount}',
                      badgeColor: const Color(0xFF3C728A),
                      onToggle: (value) => _toggleTask(definition.id, value),
                      child: _AdTaskBody(
                        enabled: state.isEnabled(definition.id),
                        completed: state.adCompleted,
                        targetCount: definition.targetCount,
                        canComplete: TaskEngine.canCompleteAd(now, state),
                        countdownLabel: TaskEngine.adCountdownLabel(now, state),
                        onDone: _markAdDone,
                      ),
                    );
                  case AssistantTaskKind.fixedPoint:
                    return _ExpandableTaskCard(
                      title: definition.title,
                      timeLabel: definition.timeLabel,
                      enabled: state.isEnabled(definition.id),
                      badge: state.isCompleted(definition.id)
                          ? '已完成'
                          : (TaskEngine.isFixedTaskDue(now, definition)
                                ? '到点'
                                : '未到时'),
                      badgeColor: state.isCompleted(definition.id)
                          ? const Color(0xFF2E7D4F)
                          : (TaskEngine.isFixedTaskDue(now, definition)
                                ? const Color(0xFFB65E35)
                                : const Color(0xFF7A7368)),
                      onToggle: (value) => _toggleTask(definition.id, value),
                      child: _FixedTaskBody(
                        enabled: state.isEnabled(definition.id),
                        isDone: state.isCompleted(definition.id),
                        isDue: TaskEngine.isFixedTaskDue(now, definition),
                        onDone: () => _markFixedDone(definition.id),
                      ),
                    );
                }
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.dateLabel,
    required this.enabledCount,
    required this.completedCount,
    required this.nextReminder,
    required this.onOpenDouyin,
    required this.onReset,
  });

  final String dateLabel;
  final int enabledCount;
  final int completedCount;
  final ReminderPreview? nextReminder;
  final Future<void> Function() onOpenDouyin;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1A16),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '半自动任务精灵',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '日期 $dateLabel',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFE8DCCA),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(label: '已开启 $enabledCount 项'),
              _InfoPill(label: '已完成 $completedCount 项'),
              _InfoPill(
                label: nextReminder == null
                    ? '无后续提醒'
                    : '下一提醒 ${nextReminder!.timeLabel}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            nextReminder == null
                ? '今日提醒已全部安排完毕。'
                : '${nextReminder!.label} 即将提醒。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFE8DCCA),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenDouyin,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开抖音'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置今日'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8E8274)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2E2823),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TaskSectionLabel extends StatelessWidget {
  const _TaskSectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF655C4F)),
        ),
      ],
    );
  }
}

class _ExpandableTaskCard extends StatelessWidget {
  const _ExpandableTaskCard({
    required this.title,
    required this.timeLabel,
    required this.enabled,
    required this.badge,
    required this.badgeColor,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String timeLabel;
  final bool enabled;
  final String badge;
  final Color badgeColor;
  final ValueChanged<bool> onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3D4BA)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6D6458),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Text(
                  enabled ? '今日已开启' : '今日已关闭',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? const Color(0xFF2E7D4F)
                        : const Color(0xFF7A7368),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Switch(value: enabled, onChanged: onToggle),
              ],
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _FeedTaskBody extends StatelessWidget {
  const _FeedTaskBody({
    required this.definition,
    required this.enabled,
    required this.isActive,
    required this.isDone,
    required this.onDone,
  });

  final AssistantTaskDefinition definition;
  final bool enabled;
  final bool isActive;
  final bool isDone;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final status = !enabled
        ? '今日已关闭，不提醒。'
        : isDone
        ? '本时段已完成。'
        : (isActive ? '当前时段进行中，可直接点完成。' : '未到时段，届时会提醒。');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled && !isDone && isActive ? onDone : null,
            icon: const Icon(Icons.task_alt),
            label: const Text('标记本时段完成'),
          ),
        ),
      ],
    );
  }
}

class _AdTaskBody extends StatelessWidget {
  const _AdTaskBody({
    required this.enabled,
    required this.completed,
    required this.targetCount,
    required this.canComplete,
    required this.countdownLabel,
    required this.onDone,
  });

  final bool enabled;
  final int completed;
  final int targetCount;
  final bool canComplete;
  final String countdownLabel;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          countdownLabel,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '每次看完广告后手点一次完成。当前 $completed / $targetCount。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled && completed < targetCount && canComplete
                ? onDone
                : null,
            icon: const Icon(Icons.check_circle),
            label: const Text('本次广告已完成'),
          ),
        ),
      ],
    );
  }
}

class _FixedTaskBody extends StatelessWidget {
  const _FixedTaskBody({
    required this.enabled,
    required this.isDone,
    required this.isDue,
    required this.onDone,
  });

  final bool enabled;
  final bool isDone;
  final bool isDue;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final status = !enabled
        ? '今日已关闭，不提醒。'
        : isDone
        ? '本任务已完成。'
        : (isDue ? '已到时间，可处理。' : '未到时间，届时提醒。');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled && !isDone ? onDone : null,
            icon: const Icon(Icons.task_alt),
            label: const Text('标记完成'),
          ),
        ),
      ],
    );
  }
}
