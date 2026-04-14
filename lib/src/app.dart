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
    const seed = Color(0xFF55B7A7);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Task Sprite',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4FBF8),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1717),
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
  bool _loadingApps = false;

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
    }, message: '已记录一次广告，倒计时开始');
  }

  Future<void> _openSelectedApp() async {
    final state = _state;
    if (state == null) {
      return;
    }
    final ok = await _launcher.openPackage(state.selectedAppPackage);
    if (!mounted) {
      return;
    }
    _showMessage(ok ? '已尝试打开 ${state.selectedAppLabel}' : '打开失败，请重新选择应用');
  }

  Future<void> _usePresetApp({
    required String packageName,
    required String label,
  }) async {
    await _mutateState((state) {
      return state.copyWith(
        selectedAppPackage: packageName,
        selectedAppLabel: label,
      );
    }, message: '已切换为 $label');
  }

  Future<void> _pickApp() async {
    if (_loadingApps) {
      return;
    }
    setState(() {
      _loadingApps = true;
    });

    final apps = await _launcher.listLaunchableApps();
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingApps = false;
    });

    final selected = await showModalBottomSheet<LaunchableApp>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 520,
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                return ListTile(
                  title: Text(app.appName),
                  subtitle: Text(app.packageName),
                  onTap: () => Navigator.of(context).pop(app),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    await _mutateState((state) {
      return state.copyWith(
        selectedAppPackage: selected.packageName,
        selectedAppLabel: selected.appName,
      );
    }, message: '已选择 ${selected.appName}');
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF102021), const Color(0xFF0E1717)]
                : [const Color(0xFFF4FBF8), const Color(0xFFE4F5EF)],
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
                onOpenApp: _openSelectedApp,
                onReset: _resetToday,
                selectedAppLabel: state.selectedAppLabel,
              ),
              const SizedBox(height: 14),
              _AppTargetCard(
                label: state.selectedAppLabel,
                packageName: state.selectedAppPackage,
                loadingApps: _loadingApps,
                onUseLite: () => _usePresetApp(
                  packageName: 'com.ss.android.ugc.aweme.lite',
                  label: '抖音极速版',
                ),
                onUseDouyin: () => _usePresetApp(
                  packageName: 'com.ss.android.ugc.aweme',
                  label: '抖音',
                ),
                onPickApp: _pickApp,
              ),
              const SizedBox(height: 14),
              _TaskSectionLabel(title: '今日任务', subtitle: '展开单项卡片，处理完成、开关、倒计时。'),
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
                          ? colors.primary
                          : colors.tertiary,
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
                      timeLabel:
                          '默认显示于通知栏 ${state.adCompleted}/${definition.targetCount}',
                      enabled: state.isEnabled(definition.id),
                      badge: '${state.adCompleted}/${definition.targetCount}',
                      badgeColor: colors.secondary,
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
                          ? colors.primary
                          : (TaskEngine.isFixedTaskDue(now, definition)
                                ? colors.tertiary
                                : colors.outline),
                      onToggle: (value) => _toggleTask(definition.id, value),
                      child: _FixedTaskBody(
                        enabled: state.isEnabled(definition.id),
                        isDone: state.isCompleted(definition.id),
                        isDue: TaskEngine.isFixedTaskDue(now, definition),
                        onDone: () => _markFixedDone(definition.id),
                        appLabel: state.selectedAppLabel,
                        onOpenApp: _openSelectedApp,
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
    required this.onOpenApp,
    required this.onReset,
    required this.selectedAppLabel,
  });

  final String dateLabel;
  final int enabledCount;
  final int completedCount;
  final ReminderPreview? nextReminder;
  final Future<void> Function() onOpenApp;
  final Future<void> Function() onReset;
  final String selectedAppLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '半自动任务精灵',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text('日期 $dateLabel'),
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
                ? '今天剩余提醒已排完。'
                : '${nextReminder!.label} 即将提醒。',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenApp,
                  icon: const Icon(Icons.open_in_new),
                  label: Text('打开$selectedAppLabel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置今日'),
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AppTargetCard extends StatelessWidget {
  const _AppTargetCard({
    required this.label,
    required this.packageName,
    required this.loadingApps,
    required this.onUseLite,
    required this.onUseDouyin,
    required this.onPickApp,
  });

  final String label;
  final String packageName;
  final bool loadingApps;
  final Future<void> Function() onUseLite;
  final Future<void> Function() onUseDouyin;
  final Future<void> Function() onPickApp;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '启动应用设置',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text('当前：$label'),
            const SizedBox(height: 2),
            Text(
              packageName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  onPressed: onUseLite,
                  child: const Text('抖音极速版'),
                ),
                OutlinedButton(onPressed: onUseDouyin, child: const Text('抖音')),
                FilledButton.icon(
                  onPressed: loadingApps ? null : onPickApp,
                  icon: loadingApps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.apps),
                  label: const Text('选择其他应用'),
                ),
              ],
            ),
          ],
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
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
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                        color: Theme.of(context).colorScheme.outline,
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
                  enabled ? '今日开启' : '今日关闭',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
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
        ? '今日已关闭。'
        : isDone
        ? '本时段已完成。'
        : (isActive ? '当前时段进行中，可直接点完成。' : '未到时段，届时会锁屏提醒。');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status),
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
    final buttonLabel = !enabled
        ? '今日已关闭'
        : completed >= targetCount
        ? '今日已完成'
        : (canComplete ? '本次广告已完成' : '倒计时中');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          countdownLabel,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('通知栏会显示进度，例如 $completed/$targetCount。点击一次后即锁 10 分钟。'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled && completed < targetCount && canComplete
                ? onDone
                : null,
            icon: const Icon(Icons.alarm),
            label: Text(buttonLabel),
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
    required this.appLabel,
    required this.onOpenApp,
  });

  final bool enabled;
  final bool isDone;
  final bool isDue;
  final Future<void> Function() onDone;
  final String appLabel;
  final Future<void> Function() onOpenApp;

  @override
  Widget build(BuildContext context) {
    final status = !enabled
        ? '今日已关闭。'
        : isDone
        ? '本任务已完成。'
        : (isDue ? '已到时间，可处理。' : '未到时间，届时会锁屏提醒。');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: enabled && !isDone ? onDone : null,
                icon: const Icon(Icons.task_alt),
                label: const Text('标记完成'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenApp,
                icon: const Icon(Icons.open_in_new),
                label: Text('打开$appLabel'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
