import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'logic/task_definitions.dart';
import 'logic/task_engine.dart';
import 'models/task_models.dart';
import 'services/alarm_bridge.dart';
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
  final AlarmBridge _alarmBridge = AlarmBridge();

  late Timer _ticker;
  DailyTaskState? _state;
  String? _error;
  bool _loading = true;
  String? _focusTaskId;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final state = _state;
      if (state != null && state.dateKey != _todayKey(DateTime.now())) {
        await _resetForNewDay(showMessage: false);
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
      var state = await _repository.loadOrCreateToday(defaultTaskDefinitions);
      if (state.templateGroups.isEmpty) {
        state = state.copyWith(templateGroups: defaultTemplateGroups);
        await _repository.save(state);
      }
      if (widget.enablePlatformServices) {
        await _notifications.scheduleForState(state, state.taskDefinitions);
        _focusTaskId = await _alarmBridge.consumeLaunchTaskId();
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

  Future<void> _persistState(DailyTaskState next, {String? message}) async {
    await _repository.save(next);
    if (widget.enablePlatformServices) {
      await _notifications.scheduleForState(next, next.taskDefinitions);
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

  Future<void> _mutateState(
    DailyTaskState Function(DailyTaskState state) transform, {
    String? message,
  }) async {
    final current = _state;
    if (current == null) {
      return;
    }
    await _persistState(transform(current), message: message);
  }

  Future<void> _resetForNewDay({bool showMessage = true}) async {
    final current = _state;
    if (current == null) {
      return;
    }
    final next = DailyTaskState.freshFor(
      DateTime.now(),
      current.taskDefinitions,
      templateGroups: current.templateGroups,
      selectedAppPackage: current.selectedAppPackage,
      selectedAppLabel: current.selectedAppLabel,
      homeVisibleTaskIds: current.homeVisibleTaskIds,
    );
    await _persistState(next, message: showMessage ? '今日记录已重置' : null);
  }

  Future<void> _markSingleTaskDone(String taskId) async {
    await _mutateState((state) {
      return state.copyWith(
        completedTaskIds: {...state.completedTaskIds, taskId},
      );
    }, message: '已标记完成');
  }

  Future<void> _markCounterTaskDone(AssistantTaskDefinition task) async {
    final now = DateTime.now();
    await _mutateState((state) {
      final nextCount = (state.intervalCompleted(task.id) + 1).clamp(
        0,
        task.targetCount,
      );
      final nextCounts = {...state.intervalCompletedCounts, task.id: nextCount};
      final nextTimes = {...state.intervalNextAvailableAt};
      if (nextCount >= task.targetCount) {
        nextTimes.remove(task.id);
      } else {
        nextTimes[task.id] = now.add(Duration(minutes: task.cooldownMinutes));
      }
      return state.copyWith(
        intervalCompletedCounts: nextCounts,
        intervalNextAvailableAt: nextTimes,
      );
    }, message: '已记录一次，倒计时开始');
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
    _showMessage(ok ? '已尝试打开 ${state.selectedAppLabel}' : '打开失败，请到设置重新选择');
  }

  Future<void> _openSettings() async {
    final state = _state;
    if (state == null) {
      return;
    }
    final next = await Navigator.of(context).push<DailyTaskState>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initialState: state, launcher: _launcher),
      ),
    );

    if (next != null) {
      await _persistState(next, message: '设置已保存');
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
    final tasks = state.taskDefinitions
        .where((task) => state.isHomeVisible(task.id))
        .toList();
    tasks.sort((a, b) {
      if (a.id == _focusTaskId) {
        return -1;
      }
      if (b.id == _focusTaskId) {
        return 1;
      }
      return 0;
    });
    final nextReminder = TaskEngine.nextReminder(
      now,
      state,
      state.taskDefinitions,
    );
    final doneCount = tasks.where((task) {
      if (!state.isEnabled(task.id)) {
        return false;
      }
      return task.kind == AssistantTaskKind.adCooldown
          ? state.intervalCompleted(task.id) >= task.targetCount
          : state.isCompleted(task.id);
    }).length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.brightness == Brightness.dark
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
                title: '半自动任务精灵',
                subtitle: nextReminder == null
                    ? '今天无后续提醒'
                    : '下一提醒 ${nextReminder.timeLabel} · ${nextReminder.label}',
                action: IconButton.filledTonal(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatPill(label: '首页显示 ${tasks.length} 项'),
                      _StatPill(label: '已完成 $doneCount 项'),
                      FilledButton.icon(
                        onPressed: _openSelectedApp,
                        icon: const Icon(Icons.open_in_new),
                        label: Text('打开${state.selectedAppLabel}'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (tasks.isEmpty)
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '首页当前无任务。去右上角设置页，开启“在首页显示”。',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ...tasks.map((task) {
                switch (task.kind) {
                  case AssistantTaskKind.feedWindow:
                    return _TaskCard(
                      task: task,
                      initiallyExpanded: task.id == _focusTaskId,
                      status: state.isCompleted(task.id)
                          ? '已完成'
                          : (TaskEngine.isFeedWindowActive(now, task)
                                ? '进行中'
                                : '等待中'),
                      child: _SingleTaskBody(
                        description: state.isEnabled(task.id)
                            ? (state.isCompleted(task.id)
                                  ? '本时段已完成。'
                                  : '时间段 ${task.timeLabel}，到时后点完成。')
                            : '今日已关闭此任务。',
                        enabled: state.isEnabled(task.id),
                        canComplete:
                            state.isEnabled(task.id) &&
                            !state.isCompleted(task.id) &&
                            TaskEngine.isFeedWindowActive(now, task),
                        buttonLabel: '标记完成',
                        onDone: () => _markSingleTaskDone(task.id),
                        showQuickLaunch: task.showQuickLaunch,
                        appLabel: state.selectedAppLabel,
                        onOpenApp: _openSelectedApp,
                      ),
                    );
                  case AssistantTaskKind.fixedPoint:
                    return _TaskCard(
                      task: task,
                      initiallyExpanded: task.id == _focusTaskId,
                      status: state.isCompleted(task.id)
                          ? '已完成'
                          : (TaskEngine.isFixedTaskDue(now, task)
                                ? '到点'
                                : '未到时'),
                      child: _SingleTaskBody(
                        description: state.isEnabled(task.id)
                            ? (state.isCompleted(task.id)
                                  ? '本任务已完成。'
                                  : '将在 ${task.timeLabel} 提醒。')
                            : '今日已关闭此任务。',
                        enabled: state.isEnabled(task.id),
                        canComplete:
                            state.isEnabled(task.id) &&
                            !state.isCompleted(task.id),
                        buttonLabel: '标记完成',
                        onDone: () => _markSingleTaskDone(task.id),
                        showQuickLaunch: task.showQuickLaunch,
                        appLabel: state.selectedAppLabel,
                        onOpenApp: _openSelectedApp,
                      ),
                    );
                  case AssistantTaskKind.adCooldown:
                    final count = state.intervalCompleted(task.id);
                    return _TaskCard(
                      task: task,
                      initiallyExpanded: task.id == _focusTaskId,
                      status: '$count/${task.targetCount}',
                      child: _CounterTaskBody(
                        description: TaskEngine.counterTaskLabel(
                          now,
                          state,
                          task,
                        ),
                        enabled: state.isEnabled(task.id),
                        canComplete:
                            state.isEnabled(task.id) &&
                            count < task.targetCount &&
                            TaskEngine.canCompleteCounterTask(now, state, task),
                        buttonLabel: count >= task.targetCount
                            ? '今日已完成'
                            : (TaskEngine.canCompleteCounterTask(
                                    now,
                                    state,
                                    task,
                                  )
                                  ? '本次已完成'
                                  : '倒计时中'),
                        onDone: () => _markCounterTaskDone(task),
                        showQuickLaunch: task.showQuickLaunch,
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.initialState,
    required this.launcher,
    super.key,
  });

  final DailyTaskState initialState;
  final DouyinLauncher launcher;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late DailyTaskState _draft;
  bool _loadingApps = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialState;
  }

  void _toggleHomeVisible(String taskId, bool visible) {
    final next = {..._draft.homeVisibleTaskIds};
    if (visible) {
      next.add(taskId);
    } else {
      next.remove(taskId);
    }
    setState(() {
      _draft = _draft.copyWith(homeVisibleTaskIds: next);
    });
  }

  Future<void> _pickApp() async {
    setState(() => _loadingApps = true);
    final apps = await widget.launcher.listLaunchableApps();
    if (!mounted) {
      return;
    }
    setState(() => _loadingApps = false);
    final selected = await showModalBottomSheet<LaunchableApp>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
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
      ),
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        selectedAppPackage: selected.packageName,
        selectedAppLabel: selected.appName,
      );
    });
  }

  Future<void> _editTask({AssistantTaskDefinition? task}) async {
    final edited = await showModalBottomSheet<AssistantTaskDefinition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TaskEditorSheet(task: task),
    );
    if (edited == null) {
      return;
    }
    setState(() {
      final exists = _draft.taskDefinitions.any((item) => item.id == edited.id);
      _draft = _draft.copyWith(
        taskDefinitions: exists
            ? _draft.taskDefinitions
                  .map((item) => item.id == edited.id ? edited : item)
                  .toList()
            : [..._draft.taskDefinitions, edited],
        enabledTaskIds: {..._draft.enabledTaskIds, edited.id},
        homeVisibleTaskIds: {..._draft.homeVisibleTaskIds, edited.id},
      );
    });
  }

  void _deleteTask(String taskId) {
    setState(() {
      _draft = _draft.copyWith(
        taskDefinitions: _draft.taskDefinitions
            .where((item) => item.id != taskId)
            .toList(),
        enabledTaskIds: {..._draft.enabledTaskIds}..remove(taskId),
        homeVisibleTaskIds: {..._draft.homeVisibleTaskIds}..remove(taskId),
        completedTaskIds: {..._draft.completedTaskIds}..remove(taskId),
        intervalCompletedCounts: {..._draft.intervalCompletedCounts}
          ..remove(taskId),
        intervalNextAvailableAt: {..._draft.intervalNextAvailableAt}
          ..remove(taskId),
      );
    });
  }

  void _moveTask(String taskId, int delta) {
    final list = [..._draft.taskDefinitions];
    final index = list.indexWhere((item) => item.id == taskId);
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= list.length) return;
    final item = list.removeAt(index);
    list.insert(nextIndex, item);
    setState(() {
      _draft = _draft.copyWith(taskDefinitions: list);
    });
  }

  void _applyTemplateGroup(TaskTemplateGroup group) {
    final base = DateTime.now().millisecondsSinceEpoch;
    final copiedTasks = group.tasks
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(id: 'task_${base}_${entry.key}'))
        .toList();
    final ids = copiedTasks.map((item) => item.id).toSet();
    setState(() {
      _draft = _draft.copyWith(
        taskDefinitions: copiedTasks,
        enabledTaskIds: ids,
        homeVisibleTaskIds: ids,
        completedTaskIds: const {},
        intervalCompletedCounts: const {},
        intervalNextAvailableAt: const {},
      );
    });
  }

  Future<void> _showSaveTemplateGroupDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存为模板'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '模板名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: [
          ..._draft.templateGroups,
          TaskTemplateGroup(
            id: 'group_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            tasks: _draft.taskDefinitions,
          ),
        ],
      );
    });
  }

  Future<void> _renameTemplateGroup(TaskTemplateGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名模板'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: _draft.templateGroups
            .map(
              (item) => item.id == group.id
                  ? TaskTemplateGroup(
                      id: item.id,
                      name: name,
                      tasks: item.tasks,
                      builtIn: item.builtIn,
                    )
                  : item,
            )
            .toList(),
      );
    });
  }

  Future<void> _editTemplateGroup(TaskTemplateGroup group) async {
    final result = await Navigator.of(context)
        .push<List<AssistantTaskDefinition>>(
          MaterialPageRoute(builder: (_) => TemplateTasksPage(group: group)),
        );
    if (result == null) return;
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: _draft.templateGroups
            .map(
              (item) => item.id == group.id
                  ? TaskTemplateGroup(
                      id: item.id,
                      name: item.name,
                      tasks: result,
                      builtIn: item.builtIn,
                    )
                  : item,
            )
            .toList(),
      );
    });
  }

  void _deleteTemplateGroup(String groupId) {
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: _draft.templateGroups
            .where((item) => item.id != groupId)
            .toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_draft),
            child: const Text('保存'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editTask(),
        icon: const Icon(Icons.add),
        label: const Text('新增任务'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '启动应用',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_draft.selectedAppLabel),
                  Text(_draft.selectedAppPackage),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _draft = _draft.copyWith(
                              selectedAppPackage:
                                  'com.ss.android.ugc.aweme.lite',
                              selectedAppLabel: '抖音极速版',
                            );
                          });
                        },
                        child: const Text('抖音极速版'),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _draft = _draft.copyWith(
                              selectedAppPackage: 'com.ss.android.ugc.aweme',
                              selectedAppLabel: '抖音',
                            );
                          });
                        },
                        child: const Text('抖音'),
                      ),
                      FilledButton.icon(
                        onPressed: _loadingApps ? null : _pickApp,
                        icon: const Icon(Icons.apps),
                        label: const Text('选择应用'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ..._buildGroupedTaskSections(context),
          const SizedBox(height: 12),
          Text(
            '模板库',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: const Text('将当前全部任务保存为模板'),
              subtitle: const Text('保存当前整套任务配置，供以后整组套用。'),
              trailing: FilledButton(
                onPressed: _showSaveTemplateGroupDialog,
                child: const Text('保存'),
              ),
            ),
          ),
          ..._draft.templateGroups.map((group) {
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(group.name),
                subtitle: Text('含 ${group.tasks.length} 个任务'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'use':
                        _applyTemplateGroup(group);
                        break;
                      case 'rename':
                        _renameTemplateGroup(group);
                        break;
                      case 'edit':
                        _editTemplateGroup(group);
                        break;
                      case 'delete':
                        _deleteTemplateGroup(group.id);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'use', child: Text('整组使用')),
                    if (!group.builtIn)
                      const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    if (!group.builtIn)
                      const PopupMenuItem(value: 'edit', child: Text('修改模板任务')),
                    if (!group.builtIn)
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _taskSummary(AssistantTaskDefinition task) {
    final type = switch (task.kind) {
      AssistantTaskKind.feedWindow => '时间段',
      AssistantTaskKind.adCooldown => '循环次数',
      AssistantTaskKind.fixedPoint => '固定时间',
    };
    final suffix = task.kind == AssistantTaskKind.adCooldown
        ? ' · ${task.targetCount}次 / 间隔${task.cooldownMinutes}分'
        : '';
    final quick = task.showQuickLaunch ? ' · 快捷打开应用' : '';
    return '$type · ${task.timeLabel}$suffix · 铃声 ${task.ringtoneLabel}$quick';
  }

  List<Widget> _buildGroupedTaskSections(BuildContext context) {
    final groups = <AssistantTaskKind, List<AssistantTaskDefinition>>{};
    for (final task in _draft.taskDefinitions) {
      groups.putIfAbsent(task.kind, () => []).add(task);
    }
    final order = [
      AssistantTaskKind.feedWindow,
      AssistantTaskKind.adCooldown,
      AssistantTaskKind.fixedPoint,
    ];
    final out = <Widget>[const SizedBox(height: 12)];
    for (final kind in order) {
      final items = groups[kind];
      if (items == null || items.isEmpty) continue;
      out.add(
        Text(
          _kindGroupLabel(kind),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
      );
      out.add(const SizedBox(height: 8));
      for (final task in items) {
        out.add(
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(task.title),
              subtitle: Text(_taskSummary(task)),
              leading: Switch(
                value: _draft.isHomeVisible(task.id),
                onChanged: (value) => _toggleHomeVisible(task.id, value),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _moveTask(task.id, -1),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    onPressed: () => _moveTask(task.id, 1),
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editTask(task: task);
                          break;
                        case 'delete':
                          _deleteTask(task.id);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  String _kindGroupLabel(AssistantTaskKind kind) {
    return switch (kind) {
      AssistantTaskKind.feedWindow => '时间段任务',
      AssistantTaskKind.adCooldown => '循环计次任务',
      AssistantTaskKind.fixedPoint => '固定时间任务',
    };
  }
}

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({this.task, super.key});

  final AssistantTaskDefinition? task;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  late TextEditingController _titleController;
  late TextEditingController _ringtoneController;
  late AssistantTaskKind _kind;
  late TimeOfDay _start;
  TimeOfDay? _end;
  late TextEditingController _targetController;
  late TextEditingController _cooldownController;
  late RingtoneSource _ringtoneSource;
  String? _ringtoneFilePath;
  late bool _showQuickLaunch;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _ringtoneController = TextEditingController(
      text: task?.ringtoneLabel ?? '默认铃声',
    );
    _ringtoneSource = task?.ringtoneSource ?? RingtoneSource.systemDefault;
    _ringtoneFilePath = task?.ringtoneValue;
    _kind = task?.kind ?? AssistantTaskKind.fixedPoint;
    _start = TimeOfDay(
      hour: task?.startHour ?? 9,
      minute: task?.startMinute ?? 0,
    );
    _end = task?.endHour == null
        ? null
        : TimeOfDay(hour: task!.endHour!, minute: task.endMinute!);
    _targetController = TextEditingController(
      text: '${task?.targetCount ?? 1}',
    );
    _cooldownController = TextEditingController(
      text: '${task?.cooldownMinutes ?? 10}',
    );
    _showQuickLaunch = task?.showQuickLaunch ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _ringtoneController.dispose();
    _targetController.dispose();
    _cooldownController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final next = await showTimePicker(context: context, initialTime: _start);
    if (next != null) {
      setState(() => _start = next);
    }
  }

  Future<void> _pickEnd() async {
    final next = await showTimePicker(
      context: context,
      initialTime: _end ?? _start,
    );
    if (next != null) {
      setState(() => _end = next);
    }
  }

  Future<void> _pickRingtoneFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'ogg', 'm4a'],
    );
    final file = result?.files.single;
    if (file == null) {
      return;
    }
    setState(() {
      _ringtoneSource = RingtoneSource.filePath;
      _ringtoneFilePath = file.path;
      _ringtoneController.text = file.name;
    });
  }

  Future<void> _pickSystemRingtone() async {
    final picked = await AlarmBridge().pickSystemRingtone();
    if (picked == null) {
      return;
    }
    setState(() {
      _ringtoneSource = RingtoneSource.systemAlarm;
      _ringtoneFilePath = picked.uri;
      _ringtoneController.text = picked.label;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCounter = _kind == AssistantTaskKind.adCooldown;
    final isWindow = _kind == AssistantTaskKind.feedWindow;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '任务名称'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AssistantTaskKind>(
              initialValue: _kind,
              items: AssistantTaskKind.values
                  .map(
                    (kind) => DropdownMenuItem(
                      value: kind,
                      child: Text(_kindLabel(kind)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _kind = value!),
              decoration: const InputDecoration(labelText: '任务类型'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开始时间'),
              subtitle: Text(_start.format(context)),
              trailing: TextButton(
                onPressed: _pickStart,
                child: const Text('选择'),
              ),
            ),
            if (isWindow)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('结束时间'),
                subtitle: Text(_end?.format(context) ?? '未选择'),
                trailing: TextButton(
                  onPressed: _pickEnd,
                  child: const Text('选择'),
                ),
              ),
            if (isCounter) ...[
              TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '循环次数'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cooldownController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '间隔分钟'),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showQuickLaunch,
              onChanged: (value) => setState(() => _showQuickLaunch = value),
              title: const Text('显示快捷打开应用'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RingtoneSource>(
              initialValue: _ringtoneSource,
              items: const [
                DropdownMenuItem(
                  value: RingtoneSource.systemDefault,
                  child: Text('系统默认铃声'),
                ),
                DropdownMenuItem(
                  value: RingtoneSource.systemAlarm,
                  child: Text('选择系统铃声'),
                ),
                DropdownMenuItem(
                  value: RingtoneSource.filePath,
                  child: Text('选择本地文件'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) {
                  return;
                }
                if (value == RingtoneSource.filePath) {
                  await _pickRingtoneFile();
                  return;
                }
                if (value == RingtoneSource.systemAlarm) {
                  await _pickSystemRingtone();
                  return;
                }
                setState(() {
                  _ringtoneSource = value;
                  _ringtoneFilePath = null;
                  _ringtoneController.text = '系统默认铃声';
                });
              },
              decoration: const InputDecoration(labelText: '提醒铃声'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ringtoneController,
              decoration: InputDecoration(
                labelText: '铃声显示名称',
                helperText: _ringtoneFilePath ?? '可用系统铃声，或选本地文件',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final title = _titleController.text.trim();
                if (title.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  AssistantTaskDefinition(
                    id:
                        widget.task?.id ??
                        'task_${DateTime.now().millisecondsSinceEpoch}',
                    kind: _kind,
                    title: title,
                    startHour: _start.hour,
                    startMinute: _start.minute,
                    endHour: isWindow ? _end?.hour ?? _start.hour : null,
                    endMinute: isWindow ? _end?.minute ?? _start.minute : null,
                    targetCount: isCounter
                        ? int.tryParse(_targetController.text) ?? 1
                        : 0,
                    cooldownMinutes: isCounter
                        ? int.tryParse(_cooldownController.text) ?? 10
                        : 0,
                    ringtoneLabel: _ringtoneController.text.trim().isEmpty
                        ? '默认铃声'
                        : _ringtoneController.text.trim(),
                    ringtoneSource: _ringtoneSource,
                    ringtoneValue: _ringtoneFilePath,
                    showQuickLaunch: _showQuickLaunch,
                  ),
                );
              },
              child: const Text('保存任务'),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(AssistantTaskKind kind) {
    return switch (kind) {
      AssistantTaskKind.feedWindow => '时间段任务',
      AssistantTaskKind.adCooldown => '循环计次任务',
      AssistantTaskKind.fixedPoint => '固定时间任务',
    };
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.status,
    required this.child,
    this.initiallyExpanded = false,
  });

  final AssistantTaskDefinition task;
  final String status;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(task.title),
        subtitle: Text('${task.timeLabel} · 铃声 ${task.ringtoneLabel}'),
        trailing: Chip(label: Text(status)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [child],
      ),
    );
  }
}

class _SingleTaskBody extends StatelessWidget {
  const _SingleTaskBody({
    required this.description,
    required this.enabled,
    required this.canComplete,
    required this.buttonLabel,
    required this.onDone,
    required this.showQuickLaunch,
    required this.appLabel,
    required this.onOpenApp,
  });

  final String description;
  final bool enabled;
  final bool canComplete;
  final String buttonLabel;
  final Future<void> Function() onDone;
  final bool showQuickLaunch;
  final String appLabel;
  final Future<void> Function() onOpenApp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(description),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled && canComplete ? onDone : null,
            child: Text(buttonLabel),
          ),
        ),
        if (showQuickLaunch) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenApp,
              child: Text('打开$appLabel'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CounterTaskBody extends StatelessWidget {
  const _CounterTaskBody({
    required this.description,
    required this.enabled,
    required this.canComplete,
    required this.buttonLabel,
    required this.onDone,
    required this.showQuickLaunch,
    required this.appLabel,
    required this.onOpenApp,
  });

  final String description;
  final bool enabled;
  final bool canComplete;
  final String buttonLabel;
  final Future<void> Function() onDone;
  final bool showQuickLaunch;
  final String appLabel;
  final Future<void> Function() onOpenApp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(description),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled && canComplete ? onDone : null,
            child: Text(buttonLabel),
          ),
        ),
        if (showQuickLaunch) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenApp,
              child: Text('打开$appLabel'),
            ),
          ),
        ],
      ],
    );
  }
}

class TemplateTasksPage extends StatefulWidget {
  const TemplateTasksPage({required this.group, super.key});

  final TaskTemplateGroup group;

  @override
  State<TemplateTasksPage> createState() => _TemplateTasksPageState();
}

class _TemplateTasksPageState extends State<TemplateTasksPage> {
  late List<AssistantTaskDefinition> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = [...widget.group.tasks];
  }

  void _removeTask(String taskId) {
    setState(() {
      _tasks = _tasks.where((item) => item.id != taskId).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_tasks),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _tasks
            .map(
              (task) => Card(
                elevation: 0,
                child: ListTile(
                  title: Text(task.title),
                  subtitle: Text('${task.timeLabel} · ${task.ringtoneLabel}'),
                  trailing: IconButton(
                    onPressed: () => _removeTask(task.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
