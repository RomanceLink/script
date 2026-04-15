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
    const seed = Color(0xFF4A9D8F);
    const lightSurface = Color(0xFFF7FAF8);
    const darkSurface = Color(0xFF0F1718);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '自律时钟',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: lightSurface,
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.84),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xFFE2ECE7)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF2F6F3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: seed),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: darkSurface,
        cardTheme: CardThemeData(
          color: const Color(0xFF162122).withValues(alpha: 0.9),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xFF223334)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF132123),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF79C6B8)),
          ),
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
  final AlarmBridge _alarmBridge = AlarmBridge();

  late Timer _ticker;
  late final PageController _pageController;
  DailyTaskState? _state;
  String? _error;
  bool _loading = true;
  String? _focusTaskId;
  int _currentTaskPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
    _pageController.dispose();
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
        builder: (_) => SettingsPage(
          initialState: state,
          launcher: _launcher,
          alarmBridge: _alarmBridge,
        ),
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

  String _dailyMotto(DateTime now) {
    const mottos = [
      '天生我才必有用，千金散尽还复来',
      '长风破浪会有时，直挂云帆济沧海',
      '且将新火试新茶，诗酒趁年华',
      '莫道桑榆晚，为霞尚满天',
      '山高路远，亦要见自己',
      '日日自新，步步生光',
    ];
    final seed = now.year * 10000 + now.month * 100 + now.day;
    return mottos[seed % mottos.length];
  }

  List<Color> _indicatorPalette(Brightness brightness) {
    return brightness == Brightness.dark
        ? const [
            Color(0xFF7ED8C3),
            Color(0xFF8EB8FF),
            Color(0xFFFFB989),
            Color(0xFFE8A8FF),
            Color(0xFFF6D77A),
          ]
        : const [
            Color(0xFF69C5AF),
            Color(0xFF7FA7F8),
            Color(0xFFFFA977),
            Color(0xFFD38FF2),
            Color(0xFFE5C45A),
          ];
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
    final focusIndex = _focusTaskId == null
        ? -1
        : tasks.indexWhere((task) => task.id == _focusTaskId);
    if (focusIndex >= 0 && focusIndex != _currentTaskPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) {
          return;
        }
        _pageController.animateToPage(
          focusIndex,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      });
      _currentTaskPage = focusIndex;
      _focusTaskId = null;
    }
    if (_currentTaskPage >= tasks.length && tasks.isNotEmpty) {
      _currentTaskPage = tasks.length - 1;
    }
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              children: [
                _HeaderCard(
                  title: _dailyMotto(now),
                  subtitle: nextReminder == null
                      ? '今天无后续提醒'
                      : '下一提醒 ${nextReminder.timeLabel} · ${nextReminder.label}',
                  stats: [
                    '首页显示 ${tasks.length} 项',
                    '已完成 $doneCount 项',
                  ],
                  action: IconButton.filledTonal(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                  ),
                ),
                const SizedBox(height: 14),
                if (tasks.isEmpty)
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            '首页当前无任务。去右上角设置页，开启“在首页显示”。',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: tasks.length,
                      onPageChanged: (value) {
                        setState(() {
                          _currentTaskPage = value;
                        });
                      },
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        switch (task.kind) {
                          case AssistantTaskKind.feedWindow:
                            return _TaskDeckCard(
                              task: task,
                              accent: const Color(0xFF5EA98D),
                              icon: Icons.play_circle_outline_rounded,
                              status: state.isCompleted(task.id)
                                  ? '已完成'
                                  : (TaskEngine.isFeedWindowActive(now, task)
                                        ? '进行中'
                                        : '等待中'),
                              headline: task.timeLabel,
                              detail: state.isEnabled(task.id)
                                  ? (state.isCompleted(task.id)
                                        ? '本时段已完成，今日无需再记录。'
                                        : '进入时间段后，再点完成即可。')
                                  : '今日未启用，不会提醒。',
                              progressLabel: state.isCompleted(task.id)
                                  ? '完成状态'
                                  : '当前状态',
                              progressValue: state.isCompleted(task.id)
                                  ? '已完成'
                                  : (TaskEngine.isFeedWindowActive(now, task)
                                        ? '可执行'
                                        : '未到时'),
                              primaryLabel: '标记完成',
                              onPrimary: () => _markSingleTaskDone(task.id),
                              primaryEnabled:
                                  state.isEnabled(task.id) &&
                                  !state.isCompleted(task.id) &&
                                  TaskEngine.isFeedWindowActive(now, task),
                              showQuickLaunch: task.showQuickLaunch,
                              appLabel: state.selectedAppLabel,
                              onOpenApp: _openSelectedApp,
                            );
                          case AssistantTaskKind.fixedPoint:
                            return _TaskDeckCard(
                              task: task,
                              accent: const Color(0xFF6B8FD6),
                              icon: Icons.alarm_rounded,
                              status: state.isCompleted(task.id)
                                  ? '已完成'
                                  : (TaskEngine.isFixedTaskDue(now, task)
                                        ? '到点'
                                        : '未到时'),
                              headline: task.timeLabel,
                              detail: state.isEnabled(task.id)
                                  ? (state.isCompleted(task.id)
                                        ? '该提醒已完成。'
                                        : '到 ${task.timeLabel} 会提醒一次。')
                                  : '今日未启用，不会提醒。',
                              progressLabel: '提醒时间',
                              progressValue: task.timeLabel,
                              primaryLabel: '标记完成',
                              onPrimary: () => _markSingleTaskDone(task.id),
                              primaryEnabled:
                                  state.isEnabled(task.id) &&
                                  !state.isCompleted(task.id),
                              showQuickLaunch: task.showQuickLaunch,
                              appLabel: state.selectedAppLabel,
                              onOpenApp: _openSelectedApp,
                            );
                          case AssistantTaskKind.adCooldown:
                            final count = state.intervalCompleted(task.id);
                            return _TaskDeckCard(
                              task: task,
                              accent: const Color(0xFFDA8C63),
                              icon: Icons.hourglass_bottom_rounded,
                              status: '$count/${task.targetCount}',
                              headline: '间隔 ${task.cooldownMinutes} 分钟',
                              detail: TaskEngine.counterTaskLabel(
                                now,
                                state,
                                task,
                              ),
                              progressLabel: '今日进度',
                              progressValue: '$count / ${task.targetCount}',
                              primaryLabel: count >= task.targetCount
                                  ? '今日已完成'
                                  : (TaskEngine.canCompleteCounterTask(
                                          now,
                                          state,
                                          task,
                                        )
                                        ? '本次已完成'
                                        : '倒计时中'),
                              onPrimary: () => _markCounterTaskDone(task),
                              primaryEnabled:
                                  state.isEnabled(task.id) &&
                                  count < task.targetCount &&
                                  TaskEngine.canCompleteCounterTask(
                                    now,
                                    state,
                                    task,
                                  ),
                              showQuickLaunch: task.showQuickLaunch,
                              appLabel: state.selectedAppLabel,
                              onOpenApp: _openSelectedApp,
                            );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Wrap(
                      spacing: 8,
                      children: List.generate(
                        tasks.length,
                        (index) {
                          final palette = _indicatorPalette(theme.brightness);
                          final dotColor = palette[index % palette.length];
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: _currentTaskPage == index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentTaskPage == index
                                  ? dotColor
                                  : dotColor.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
    required this.alarmBridge,
    super.key,
  });

  final DailyTaskState initialState;
  final DouyinLauncher launcher;
  final AlarmBridge alarmBridge;

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

  void _toggleTaskEnabled(String taskId, bool enabled) {
    final next = {..._draft.enabledTaskIds};
    if (enabled) {
      next.add(taskId);
    } else {
      next.remove(taskId);
    }
    setState(() {
      _draft = _draft.copyWith(
        enabledTaskIds: next,
        completedTaskIds: enabled
            ? _draft.completedTaskIds
            : ({..._draft.completedTaskIds}..remove(taskId)),
        intervalCompletedCounts: enabled
            ? _draft.intervalCompletedCounts
            : ({..._draft.intervalCompletedCounts}..remove(taskId)),
        intervalNextAvailableAt: enabled
            ? _draft.intervalNextAvailableAt
            : ({..._draft.intervalNextAvailableAt}..remove(taskId)),
      );
    });
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
    final theme = Theme.of(context);
    final mintFill = theme.brightness == Brightness.dark
        ? const Color(0xFF1F3D39)
        : const Color(0xFFDDF5EC);
    final mintText = theme.brightness == Brightness.dark
        ? const Color(0xFF94DFC9)
        : const Color(0xFF2F7D6B);
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
        label: const Text('新增任务'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _SettingsSectionCard(
            accent: const Color(0xFF78BEA8),
            title: '启动应用',
            subtitle: _draft.selectedAppLabel,
            helper: _draft.selectedAppPackage,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _PastelButton(
                  label: '抖音极速版',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF1F3D39)
                      : const Color(0xFFDDF5EC),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFF94DFC9)
                      : const Color(0xFF2F7D6B),
                  onPressed: () {
                    setState(() {
                      _draft = _draft.copyWith(
                        selectedAppPackage: 'com.ss.android.ugc.aweme.lite',
                        selectedAppLabel: '抖音极速版',
                      );
                    });
                  },
                ),
                _PastelButton(
                  label: '抖音',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF243649)
                      : const Color(0xFFE5F0FF),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFA7C5FF)
                      : const Color(0xFF456DAA),
                  onPressed: () {
                    setState(() {
                      _draft = _draft.copyWith(
                        selectedAppPackage: 'com.ss.android.ugc.aweme',
                        selectedAppLabel: '抖音',
                      );
                    });
                  },
                ),
                _PastelButton(
                  label: _loadingApps ? '加载中...' : '选择应用',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF3F3022)
                      : const Color(0xFFFFEFD9),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFFFCF8D)
                      : const Color(0xFFB06C22),
                  onPressed: _loadingApps ? null : _pickApp,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSectionCard(
            accent: const Color(0xFF80A7F5),
            title: '提醒权限与系统设置',
            subtitle: '闹钟、通知、锁屏弹出',
            helper: '全屏提醒不依赖悬浮窗或辅助功能。核心是：精确闹钟、通知、忽略电池优化。',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _PastelButton(
                  label: '全屏通知',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF243649)
                      : const Color(0xFFE5F0FF),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFA7C5FF)
                      : const Color(0xFF456DAA),
                  onPressed: widget.alarmBridge.openFullScreenIntentSettings,
                ),
                _PastelButton(
                  label: '精确闹钟',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF1F3D39)
                      : const Color(0xFFDDF5EC),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFF94DFC9)
                      : const Color(0xFF2F7D6B),
                  onPressed: widget.alarmBridge.openExactAlarmSettings,
                ),
                _PastelButton(
                  label: '通知权限',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF3A2F44)
                      : const Color(0xFFF2E4FF),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFE0BAFF)
                      : const Color(0xFF8A53B5),
                  onPressed: widget.alarmBridge.openNotificationSettings,
                ),
                _PastelButton(
                  label: '电池白名单',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF3F3022)
                      : const Color(0xFFFFEFD9),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFFFCF8D)
                      : const Color(0xFFB06C22),
                  onPressed: widget.alarmBridge.requestIgnoreBatteryOptimizations,
                ),
                _PastelButton(
                  label: '悬浮窗设置',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF353A21)
                      : const Color(0xFFF4F6D9),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFDBE28F)
                      : const Color(0xFF7B8128),
                  onPressed: widget.alarmBridge.openOverlaySettings,
                ),
                _PastelButton(
                  label: '辅助功能设置',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF3A3040)
                      : const Color(0xFFFFE5F2),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFFFB5D7)
                      : const Color(0xFFB85082),
                  onPressed: widget.alarmBridge.openAccessibilitySettings,
                ),
                _PastelButton(
                  label: '10秒自测',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF1F3D39)
                      : const Color(0xFFDDF5EC),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFF94DFC9)
                      : const Color(0xFF2F7D6B),
                  onPressed: () async {
                    final now = DateTime.now().add(const Duration(seconds: 10));
                    await widget.alarmBridge.scheduleSelfTest(
                      AlarmReminder(
                        id: 'self_test',
                        taskId: 'self_test',
                        title: '10秒自测提醒',
                        body: '若正常，10秒后应直接弹出全屏提醒。',
                        whenEpochMillis: now.millisecondsSinceEpoch,
                        ringtoneSource: RingtoneSource.systemAlarm,
                        ringtoneLabel: '系统闹钟铃声',
                        ringtoneValue: null,
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已安排 10 秒后自测')),
                      );
                    }
                  },
                ),
                _PastelButton(
                  label: '厂商指引',
                  background: theme.brightness == Brightness.dark
                      ? const Color(0xFF243649)
                      : const Color(0xFFE5F0FF),
                  foreground: theme.brightness == Brightness.dark
                      ? const Color(0xFFA7C5FF)
                      : const Color(0xFF456DAA),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const VendorGuidePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          ..._buildGroupedTaskSections(context),
          const SizedBox(height: 12),
          Text(
            '模板库',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: const Text('将当前全部任务保存为模板'),
              subtitle: const Text('保存当前整套任务配置，供以后整组套用。'),
              trailing: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: mintFill,
                  foregroundColor: mintText,
                ),
                onPressed: _showSaveTemplateGroupDialog,
                child: const Text('保存'),
              ),
            ),
          ),
          ..._draft.templateGroups.map((group) {
            return Card(
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
    final theme = Theme.of(context);
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
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
      );
      out.add(const SizedBox(height: 8));
      for (final task in items) {
        final enabled = _draft.isEnabled(task.id);
        final homeVisible = _draft.isHomeVisible(task.id);
        out.add(
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _taskSummary(task),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _MiniIconButton(
                        onPressed: () => _moveTask(task.id, -1),
                        icon: Icons.keyboard_arrow_up_rounded,
                      ),
                      const SizedBox(width: 6),
                      _MiniIconButton(
                        onPressed: () => _moveTask(task.id, 1),
                        icon: Icons.keyboard_arrow_down_rounded,
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ToggleChip(
                          label: '今日启用',
                          value: enabled,
                          onChanged: (value) => _toggleTaskEnabled(task.id, value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ToggleChip(
                          label: '首页显示',
                          value: homeVisible,
                          onChanged: (value) =>
                              _toggleHomeVisible(task.id, value),
                        ),
                      ),
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
    final theme = Theme.of(context);
    final mintFill = theme.brightness == Brightness.dark
        ? const Color(0xFF1F3D39)
        : const Color(0xFFDDF5EC);
    final mintText = theme.brightness == Brightness.dark
        ? const Color(0xFF94DFC9)
        : const Color(0xFF2F7D6B);
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
            _EditorHeroCard(kindLabel: _kindLabel(_kind)),
            const SizedBox(height: 14),
            _EditorSectionCard(
              accent: const Color(0xFF76C7AE),
              title: '基础信息',
              child: Column(
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
                ],
              ),
            ),
            const SizedBox(height: 12),
            _EditorSectionCard(
              accent: const Color(0xFF82A7F7),
              title: '时间安排',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _EditorPickerTile(
                          label: '开始时间',
                          value: _start.format(context),
                          onTap: _pickStart,
                        ),
                      ),
                      if (isWindow) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _EditorPickerTile(
                            label: '结束时间',
                            value: _end?.format(context) ?? '未选择',
                            onTap: _pickEnd,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isCounter) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _targetController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '循环次数'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _cooldownController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '间隔分钟'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _EditorSectionCard(
              accent: const Color(0xFFFFB17E),
              title: '快捷行为',
              child: SwitchTheme(
                data: SwitchThemeData(
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF83D8BD);
                    }
                    return theme.brightness == Brightness.dark
                        ? const Color(0xFF384A46)
                        : const Color(0xFFD7E3DE);
                  }),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF172425)
                        : const Color(0xFFF4F8F6),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '显示快捷打开应用',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '任务卡片底部显示一键打开目标应用',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _showQuickLaunch,
                        onChanged: (value) =>
                            setState(() => _showQuickLaunch = value),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _EditorSectionCard(
              accent: const Color(0xFFD69AF1),
              title: '提醒铃声',
              child: Column(
                children: [
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
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: mintFill,
                foregroundColor: mintText,
                minimumSize: const Size.fromHeight(52),
              ),
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

class _EditorHeroCard extends StatelessWidget {
  const _EditorHeroCard({required this.kindLabel});

  final String kindLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.brightness == Brightness.dark
              ? const [Color(0xFF1A2C2A), Color(0xFF1A2232)]
              : const [Color(0xFFE7F7F1), Color(0xFFE8F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '编辑任务',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  kindLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorSectionCard extends StatelessWidget {
  const _EditorSectionCard({
    required this.accent,
    required this.title,
    required this.child,
  });

  final Color accent;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.12 : 0.1),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 22,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorPickerTile extends StatelessWidget {
  const _EditorPickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF172425)
              : const Color(0xFFF4F8F6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.stats,
    required this.action,
  });

  final String title;
  final String subtitle;
  final List<String> stats;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.95),
            colors.secondaryContainer.withValues(alpha: 0.92),
            colors.tertiaryContainer.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '今日箴言',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: stats
                        .asMap()
                        .entries
                        .map(
                          (entry) => _StatPill(
                            label: entry.value,
                            tone: entry.key,
                          ),
                        )
                        .toList(),
                  ),
                ],
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
  const _StatPill({required this.label, required this.tone});

  final String label;
  final int tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palettes = theme.brightness == Brightness.dark
        ? const [
            (Color(0xFF1F3D39), Color(0xFF8ED8C8)),
            (Color(0xFF23364A), Color(0xFF9BC2FF)),
          ]
        : const [
            (Color(0xFFDFF5EE), Color(0xFF2F7D6B)),
            (Color(0xFFE4F0FF), Color(0xFF436EAF)),
          ];
    final palette = palettes[tone % palettes.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.$2,
        ),
      ),
    );
  }
}

class _TaskDeckCard extends StatelessWidget {
  const _TaskDeckCard({
    required this.task,
    required this.status,
    required this.accent,
    required this.icon,
    required this.headline,
    required this.detail,
    required this.progressLabel,
    required this.progressValue,
    required this.primaryLabel,
    required this.onPrimary,
    required this.primaryEnabled,
    required this.showQuickLaunch,
    required this.appLabel,
    required this.onOpenApp,
  });

  final AssistantTaskDefinition task;
  final String status;
  final Color accent;
  final IconData icon;
  final String headline;
  final String detail;
  final String progressLabel;
  final String progressValue;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final bool primaryEnabled;
  final bool showQuickLaunch;
  final String appLabel;
  final Future<void> Function() onOpenApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryButtonFill = theme.brightness == Brightness.dark
        ? accent.withValues(alpha: 0.88)
        : Color.lerp(accent, Colors.white, 0.2)!;
    final primaryButtonText = theme.brightness == Brightness.dark
        ? Colors.white
        : _idealTextColor(primaryButtonFill);
    final secondaryButtonFill = theme.brightness == Brightness.dark
        ? accent.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.14);
    final secondaryButtonText = theme.brightness == Brightness.dark
        ? accent.withValues(alpha: 0.98)
        : accent.withValues(alpha: 0.95);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.15),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: accent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${task.timeLabel} · 铃声 ${task.ringtoneLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(label: status, accent: accent),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useTwoColumns = constraints.maxWidth >= 520;
                    if (useTwoColumns) {
                      return Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _InfoPanel(
                                  title: '任务时间',
                                  value: headline,
                                  accent: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _InfoPanel(
                                  title: progressLabel,
                                  value: progressValue,
                                  accent: accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: _DetailPanel(
                              detail: detail,
                              accent: accent,
                            ),
                          ),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          _InfoPanel(
                            title: '任务时间',
                            value: headline,
                            accent: accent,
                          ),
                          const SizedBox(height: 12),
                          _InfoPanel(
                            title: progressLabel,
                            value: progressValue,
                            accent: accent,
                          ),
                          const SizedBox(height: 14),
                          _DetailPanel(
                            detail: detail,
                            accent: accent,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              if (showQuickLaunch)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryButtonFill,
                          foregroundColor: primaryButtonText,
                        ),
                        onPressed: primaryEnabled ? onPrimary : null,
                        child: Text(primaryLabel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: secondaryButtonFill,
                          foregroundColor: secondaryButtonText,
                          side: BorderSide.none,
                        ),
                        onPressed: onOpenApp,
                        child: Text('打开$appLabel'),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryButtonFill,
                      foregroundColor: primaryButtonText,
                    ),
                    onPressed: primaryEnabled ? onPrimary : null,
                    child: Text(primaryLabel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _idealTextColor(Color background) {
    return background.computeLuminance() > 0.55
        ? const Color(0xFF12322B)
        : Colors.white;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.value,
    required this.accent,
  });

  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 36,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.detail, required this.accent});

  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.brightness == Brightness.dark
        ? (value ? const Color(0xFF1E3B35) : const Color(0xFF1A2526))
        : (value ? const Color(0xFFE0F5EC) : const Color(0xFFF2F7F4));
    final text = theme.brightness == Brightness.dark
        ? (value ? const Color(0xFF96E1CC) : const Color(0xFFBCD1CA))
        : (value ? const Color(0xFF2D7A67) : const Color(0xFF5E7F75));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value
              ? const Color(0xFF86D7BF).withValues(alpha: 0.8)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF83D8BD),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: theme.brightness == Brightness.dark
                ? const Color(0xFF384A46)
                : const Color(0xFFD7E3DE),
            trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF213033)
              : const Color(0xFFEAF4F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          size: 18,
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFC7DDD7)
              : const Color(0xFF55776E),
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.helper,
    required this.child,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final String helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.12),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          helper,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PastelButton extends StatelessWidget {
  const _PastelButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class TemplateTasksPage extends StatefulWidget {
  const TemplateTasksPage({required this.group, super.key});

  final TaskTemplateGroup group;

  @override
  State<TemplateTasksPage> createState() => _TemplateTasksPageState();
}

class VendorGuidePage extends StatelessWidget {
  const VendorGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final guides = const [
      ('小米 / Redmi', '开启自启动、无限制省电、锁屏显示、允许全屏通知。'),
      ('OPPO / 一加 / realme', '允许后台运行、关闭自动优化、通知设为高优先、允许锁屏弹出。'),
      ('vivo / iQOO', '后台高耗电允许、消息通知管理里开悬浮/锁屏、允许自启动。'),
      ('华为 / 荣耀', '应用启动管理改手动管理、允许后台活动、允许锁屏通知。'),
      ('三星', '关闭睡眠应用、允许精确闹钟、通知频道设为弹出与声音。'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('厂商权限指引')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: guides
            .map(
              (item) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(title: Text(item.$1), subtitle: Text(item.$2)),
              ),
            )
            .toList(),
      ),
    );
  }
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
