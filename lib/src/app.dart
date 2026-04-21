import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gesture_pages.dart';
import 'logic/task_definitions.dart';
import 'logic/task_engine.dart';
import 'models/task_models.dart';
import 'services/alarm_bridge.dart';
import 'services/douyin_launcher.dart';
import 'services/notification_service.dart';
import 'services/task_repository.dart';

part 'app_overlay.dart';
part 'app_widgets.dart';

enum ToastType { success, error, info, warning }

const _appSeed = Color(0xFF4A9D8F);
const _lightSurface = Color(0xFFF7FAF8);
const _darkSurface = Color(0xFF0F1718);

ThemeData _scriptAssistantTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _appSeed,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: isDark ? _darkSurface : _lightSurface,
    cardTheme: CardThemeData(
      color: (isDark ? const Color(0xFF162122) : Colors.white).withValues(
        alpha: isDark ? 0.9 : 0.84,
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(
          color: isDark ? const Color(0xFF223334) : const Color(0xFFE2ECE7),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF132123) : const Color(0xFFF2F6F3),
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
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF79C6B8) : _appSeed,
        ),
      ),
    ),
  );
}

class VibrantHUD {
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
  }) {
    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _CenteredToast(
        message: message,
        type: type,
        onDismiss: () {
          try {
            entry.remove();
          } catch (_) {}
        },
      ),
    );

    overlay.insert(entry);
  }
}

class ScriptAssistantApp extends StatelessWidget {
  const ScriptAssistantApp({super.key, this.enablePlatformServices = true});

  final bool enablePlatformServices;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '自律时钟',
      themeMode: ThemeMode.system,
      theme: _scriptAssistantTheme(Brightness.light),
      darkTheme: _scriptAssistantTheme(Brightness.dark),
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

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
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
  List<GestureConfig> _gestureConfigs = [];
  List<String> _dailyMottos = const [];
  bool _handlingOverlayCommand = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      final gestureConfigs = await _repository.loadGestureConfigs();
      final dailyMottos = await _repository.loadDailyMottos();
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state;
        _gestureConfigs = gestureConfigs;
        _dailyMottos = dailyMottos;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePendingOverlayCommand();
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
    WidgetsBinding.instance.removeObserver(this);
    _ticker.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handlePendingOverlayCommand();
    }
  }

  Future<void> _persistState(
    DailyTaskState next, {
    String? message,
    ToastType type = ToastType.info,
  }) async {
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
      _showMessage(message, type: type);
    }
  }

  Future<void> _mutateState(
    DailyTaskState Function(DailyTaskState state) transform, {
    String? message,
    ToastType type = ToastType.info,
  }) async {
    final current = _state;
    if (current == null) {
      return;
    }
    await _persistState(transform(current), message: message, type: type);
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
      enabledTaskIds: current.enabledTaskIds,
    );
    await _persistState(
      next,
      message: showMessage ? '今日记录已重置' : null,
      type: ToastType.success,
    );
  }

  Future<void> _markSingleTaskDone(String taskId) async {
    await _mutateState(
      (state) {
        return state.copyWith(
          completedTaskIds: {...state.completedTaskIds, taskId},
        );
      },
      message: '太棒了，任务已完成！',
      type: ToastType.success,
    );
  }

  Future<void> _markCounterTaskDone(AssistantTaskDefinition task) async {
    final now = DateTime.now();
    await _mutateState(
      (state) {
        final rawNextCount = state.intervalCompleted(task.id) + 1;
        final nextCount = task.infiniteLoop
            ? rawNextCount
            : rawNextCount.clamp(0, task.targetCount);
        final nextCounts = {
          ...state.intervalCompletedCounts,
          task.id: nextCount,
        };
        final nextTimes = {...state.intervalNextAvailableAt};
        if (!task.infiniteLoop && nextCount >= task.targetCount) {
          nextTimes.remove(task.id);
        } else {
          nextTimes[task.id] = now.add(task.cooldownDuration);
        }
        return state.copyWith(
          intervalCompletedCounts: nextCounts,
          intervalNextAvailableAt: nextTimes,
        );
      },
      message: '记录成功，计时开始！',
      type: ToastType.success,
    );
  }

  List<Map<String, Object?>> _expandFiniteConfigActions(GestureConfig config) {
    final out = <Map<String, Object?>>[];
    final loops = config.loopCount.clamp(1, 9999);
    for (var i = 0; i < loops; i++) {
      out.addAll(config.actions.map((action) => action.toJson()));
      if (i < loops - 1 && config.loopIntervalMillis > 0) {
        out.add(
          WaitAction.fixedMilliseconds(milliseconds: config.loopIntervalMillis)
              .toJson(),
        );
      }
    }
    return out;
  }

  ({
    String name,
    List<Map<String, Object?>> beforeLoopActions,
    List<Map<String, Object?>> loopActions,
    int loopCount,
    int loopIntervalMillis,
    bool infiniteLoop,
  })? _resolveGestureExecutionPlan(
    GestureConfig? config,
    List<GestureConfig> configs, {
    bool allowInfinite = true,
    Set<String>? visited,
  }) {
    if (config == null) {
      return null;
    }
    final nextVisited = {...?visited};
    if (!nextVisited.add(config.id)) {
      return (
        name: config.name,
        beforeLoopActions: _expandFiniteConfigActions(config),
        loopActions: const [],
        loopCount: 1,
        loopIntervalMillis: 0,
        infiniteLoop: false,
      );
    }
    if (config.infiniteLoop && allowInfinite) {
      return (
        name: config.name,
        beforeLoopActions: const [],
        loopActions: config.actions.map((action) => action.toJson()).toList(),
        loopCount: config.loopCount,
        loopIntervalMillis: config.loopIntervalMillis,
        infiniteLoop: true,
      );
    }
    final currentActions = _expandFiniteConfigActions(config);
    final child = configs
        .where((item) => item.id == config.followUpConfigId)
        .firstOrNull;
    final childPlan = _resolveGestureExecutionPlan(
      child,
      configs,
      allowInfinite: allowInfinite,
      visited: nextVisited,
    );
    if (childPlan == null) {
      return (
        name: config.name,
        beforeLoopActions: currentActions,
        loopActions: const [],
        loopCount: 1,
        loopIntervalMillis: 0,
        infiniteLoop: false,
      );
    }
    return (
      name: '${config.name} -> ${childPlan.name}',
      beforeLoopActions: [...currentActions, ...childPlan.beforeLoopActions],
      loopActions: childPlan.loopActions,
      loopCount: childPlan.loopCount,
      loopIntervalMillis: childPlan.loopIntervalMillis,
      infiniteLoop: childPlan.infiniteLoop,
    );
  }

  Future<void> _openSelectedApp(AssistantTaskDefinition task) async {
    final state = _state;
    if (state == null) {
      return;
    }

    final configs = await _repository.loadGestureConfigs();
    final preConfigId = task.preGestureConfigId;
    final preConfig = preConfigId == null
        ? null
        : configs.where((c) => c.id == preConfigId).firstOrNull;
    final configId = task.gestureConfigId;
    final config = configId == null
        ? null
        : configs.where((c) => c.id == configId).firstOrNull;
    final prePlan = _resolveGestureExecutionPlan(
      preConfig,
      configs,
      allowInfinite: false,
    );
    final mainPlan = _resolveGestureExecutionPlan(config, configs);
    final ok = await _alarmBridge.openAppAndRunConfig(
      packageName: state.selectedAppPackage,
      packageLabel: state.selectedAppLabel,
      preConfigName: prePlan?.name,
      preActions: prePlan?.beforeLoopActions ?? const [],
      preLoopCount: 1,
      preLoopIntervalMillis: 0,
      configName: mainPlan?.name,
      beforeLoopActions: mainPlan?.beforeLoopActions ?? const [],
      actions: mainPlan?.loopActions ?? const [],
      loopCount: mainPlan?.loopCount ?? 1,
      loopIntervalMillis: mainPlan?.loopIntervalMillis ?? 0,
      infiniteLoop: mainPlan?.infiniteLoop ?? false,
      delaySeconds: 5,
    );
    if (!mounted) {
      return;
    }

    if (!ok) {
      _showMessage('应用打开失败，请检查设置', type: ToastType.error);
      return;
    }

    _showMessage(
      mainPlan == null
          ? '已打开 ${state.selectedAppLabel}'
          : prePlan == null
          ? '已打开 ${state.selectedAppLabel}，5 秒后执行 ${mainPlan.name}'
          : '先执行前置脚本 ${prePlan.name}，再打开 ${state.selectedAppLabel}',
      type: ToastType.info,
    );
  }

  Future<void> _startAutomationMenu() async {
    final configs = await _repository.loadGestureConfigs();
    final ok = await _alarmBridge.showAutomationMenu(
      configs: configs.map((config) => config.toJson()).toList(),
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      _showMessage('悬浮菜单已启动', type: ToastType.success);
      return;
    }
    _showMessage('请先开启辅助功能服务，再启动悬浮菜单', type: ToastType.warning);
    await _alarmBridge.openAccessibilitySettings();
  }

  Future<void> _syncAutomationConfigs() async {
    final configs = await _repository.loadGestureConfigs();
    if (mounted) {
      setState(() => _gestureConfigs = configs);
    }
    final state = _state;
    if (widget.enablePlatformServices && state != null) {
      await _notifications.scheduleForState(state, state.taskDefinitions);
    }
    await _alarmBridge.syncAutomationConfigs(
      configs: configs.map((config) => config.toJson()).toList(),
    );
  }

  Future<void> _openGestureConfigsFromOverlay() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GestureConfigPage(repository: _repository, launcher: _launcher),
      ),
    );
    await _syncAutomationConfigs();
  }

  Future<void> _createGestureConfigFromOverlay() async {
    final result = await Navigator.of(context).push<GestureConfig>(
      MaterialPageRoute(
        builder: (_) =>
            GestureEditPage(launcher: _launcher, repository: _repository),
      ),
    );
    if (result == null) {
      return;
    }
    final configs = await _repository.loadGestureConfigs();
    final next = [...configs, result];
    await _repository.saveGestureConfigs(next);
    await _syncAutomationConfigs();
    if (mounted) {
      _showMessage('配置已保存', type: ToastType.success);
    }
  }

  Future<void> _handlePendingOverlayCommand() async {
    if (!widget.enablePlatformServices ||
        _loading ||
        _handlingOverlayCommand ||
        !mounted) {
      return;
    }
    _handlingOverlayCommand = true;
    try {
      final command = await _alarmBridge.consumeOverlayCommand();
      if (!mounted || command == null || command.isEmpty) {
        return;
      }
      switch (command) {
        case 'open_configs':
          await _openGestureConfigsFromOverlay();
          break;
        case 'new_config':
          await _createGestureConfigFromOverlay();
          break;
      }
    } finally {
      _handlingOverlayCommand = false;
    }
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
          repository: _repository,
        ),
      ),
    );

    if (next != null) {
      final configs = await _repository.loadGestureConfigs();
      final dailyMottos = await _repository.loadDailyMottos();
      if (mounted) {
        setState(() {
          _gestureConfigs = configs;
          _dailyMottos = dailyMottos;
        });
      }
      await _persistState(next, message: '设置已保存', type: ToastType.success);
    }
  }

  void _showMessage(String message, {ToastType type = ToastType.info}) {
    VibrantHUD.show(context, message, type: type);
  }

  String _todayKey(DateTime now) {
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _dailyMotto(DateTime now) {
    const fallbackMottos = [
      '天生我才必有用，千金散尽还复来',
      '长风破浪会有时，直挂云帆济沧海',
      '且将新火试新茶，诗酒趁年华',
      '莫道桑榆晚，为霞尚满天',
      '山高路远，亦要见自己',
      '日日自新，步步生光',
    ];
    final mottos = _dailyMottos.isEmpty ? fallbackMottos : _dailyMottos;
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

  String? _configLabelFor(AssistantTaskDefinition task) {
    final id = task.gestureConfigId;
    if (id == null || id.isEmpty) {
      return null;
    }
    final config = _gestureConfigs.where((item) => item.id == id).firstOrNull;
    if (config == null) {
      return '配置已删除';
    }
    final loopLabel = config.infiniteLoop ? '无限循环' : '${config.loopCount} 次';
    final durationLabel = config.infiniteLoop
        ? '持续执行'
        : '约 ${estimateGestureConfigDuration(config).label}';
    final followUpLabel = config.followUpConfigId == null ? '' : ' · 含追加配置';
    return '${config.name} · $loopLabel · 间隔 ${config.loopIntervalMillis} 毫秒$followUpLabel · $durationLabel';
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
      // 按照开始时间排序
      if (a.startHour != b.startHour) {
        return a.startHour.compareTo(b.startHour);
      }
      return a.startMinute.compareTo(b.startMinute);
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
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        _pageController.animateToPage(
          focusIndex,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        setState(() {
          _currentTaskPage = focusIndex;
          _focusTaskId = null;
        });
      });
    }
    if (_currentTaskPage >= tasks.length && tasks.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentTaskPage = tasks.length - 1;
          });
        }
      });
    }
    final doneCount = tasks.where((task) {
      if (!state.isEnabled(task.id)) {
        return false;
      }
      return task.kind == AssistantTaskKind.adCooldown
          ? (!task.infiniteLoop &&
                state.intervalCompleted(task.id) >= task.targetCount)
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
                  stats: ['首页显示 ${tasks.length} 项', '已完成 $doneCount 项'],
                  onReset: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('重置今日记录'),
                        content: const Text('确定要重置今天所有的任务完成状态和倒计时吗？此操作不可撤销。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: FilledButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                            child: const Text('确定重置'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _resetForNewDay();
                    }
                  },
                  action: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: _startAutomationMenu,
                        icon: const Icon(Icons.play_arrow_rounded),
                        tooltip: '启动悬浮菜单',
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _openSettings,
                        icon: const Icon(Icons.settings),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (tasks.isEmpty)
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 28,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    Icons.inbox_rounded,
                                    size: 32,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '暂无首页任务',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '去设置页开启“首页显示”，常用任务就会出现在这里。',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
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
                            final isExpired = TaskEngine.isTaskExpired(
                              now,
                              task,
                            );
                            final isActive = TaskEngine.isFeedWindowActive(
                              now,
                              task,
                            );
                            return _TaskDeckCard(
                              task: task,
                              accent: const Color(0xFF5EA98D),
                              icon: Icons.play_circle_outline_rounded,
                              status: state.isCompleted(task.id)
                                  ? '已完成'
                                  : (isActive
                                        ? '进行中'
                                        : (isExpired ? '任务已过期' : '未开始')),
                              headline: task.timeLabel,
                              detail: state.isEnabled(task.id)
                                  ? (state.isCompleted(task.id)
                                        ? '本时段已完成，今日无需再记录。'
                                        : (isExpired
                                              ? '任务时间已过，没关系，补上吧！'
                                              : (isActive
                                                    ? '现在正是执行时间，预留 5 分钟缓冲打卡，超时将过期哦！'
                                                    : '还没到开始时间，请耐心等待。')))
                                  : '今日未启用，不会提醒。',
                              progressLabel: state.isCompleted(task.id)
                                  ? '完成状态'
                                  : '当前状态',
                              progressValue: state.isCompleted(task.id)
                                  ? '已完成'
                                  : (isActive
                                        ? '可执行'
                                        : (isExpired ? '已逾期' : '未开始')),
                              primaryLabel: isExpired ? '再接再厉' : '标记完成',
                              onPrimary: () => _markSingleTaskDone(task.id),
                              primaryEnabled:
                                  state.isEnabled(task.id) &&
                                  !state.isCompleted(task.id) &&
                                  (isActive || isExpired),
                              showQuickLaunch:
                                  task.showQuickLaunch ||
                                  (task.gestureConfigId?.isNotEmpty ?? false),
                              appLabel: state.selectedAppLabel,
                              configLabel: _configLabelFor(task),
                              onOpenApp: () => _openSelectedApp(task),
                            );
                          case AssistantTaskKind.fixedPoint:
                            final isExpired = TaskEngine.isTaskExpired(
                              now,
                              task,
                            );
                            final isDue = TaskEngine.isFixedTaskDue(now, task);
                            return _TaskDeckCard(
                              task: task,
                              accent: const Color(0xFF6B8FD6),
                              icon: Icons.alarm_rounded,
                              status: state.isCompleted(task.id)
                                  ? '已完成'
                                  : (isDue
                                        ? (isExpired ? '任务已过期' : '到点')
                                        : '未开始'),
                              headline: task.timeLabel,
                              detail: state.isEnabled(task.id)
                                  ? (state.isCompleted(task.id)
                                        ? '该提醒已完成。'
                                        : (isExpired
                                              ? '任务已过，现在标记补卡吧。'
                                              : (isDue
                                                    ? '到点了，赶紧去执行吧！预留 5 分钟缓冲打卡，超时将过期哦！'
                                                    : '还没到提醒时间。')))
                                  : '今日未启用，不会提醒。',
                              progressLabel: '提醒时间',
                              progressValue: task.timeLabel,
                              primaryLabel: isExpired ? '再接再厉' : '标记完成',
                              onPrimary: () => _markSingleTaskDone(task.id),
                              primaryEnabled:
                                  state.isEnabled(task.id) &&
                                  !state.isCompleted(task.id) &&
                                  isDue,
                              showQuickLaunch:
                                  task.showQuickLaunch ||
                                  (task.gestureConfigId?.isNotEmpty ?? false),
                              appLabel: state.selectedAppLabel,
                              configLabel: _configLabelFor(task),
                              onOpenApp: () => _openSelectedApp(task),
                            );
                          case AssistantTaskKind.adCooldown:
                            final count = state.intervalCompleted(task.id);
                            final progressText = task.infiniteLoop
                                ? '$count / ∞'
                                : '$count / ${task.targetCount}';
                            return _TaskDeckCard(
                              task: task,
                              accent: const Color(0xFFDA8C63),
                              icon: Icons.hourglass_bottom_rounded,
                              status: progressText,
                              headline: '间隔 ${task.intervalLabel}',
                              detail: TaskEngine.counterTaskLabel(
                                now,
                                state,
                                task,
                              ),
                              progressLabel: '今日进度',
                              progressValue: progressText,
                              primaryLabel:
                                  (!task.infiniteLoop &&
                                      count >= task.targetCount)
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
                                  (task.infiniteLoop ||
                                      count < task.targetCount) &&
                                  TaskEngine.canCompleteCounterTask(
                                    now,
                                    state,
                                    task,
                                  ),
                              showQuickLaunch:
                                  task.showQuickLaunch ||
                                  (task.gestureConfigId?.isNotEmpty ?? false),
                              appLabel: state.selectedAppLabel,
                              configLabel: _configLabelFor(task),
                              onOpenApp: () => _openSelectedApp(task),
                            );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Wrap(
                      spacing: 8,
                      children: List.generate(tasks.length, (index) {
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
                      }),
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
    required this.repository,
    super.key,
  });

  final DailyTaskState initialState;
  final DouyinLauncher launcher;
  final AlarmBridge alarmBridge;
  final TaskRepository repository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late DailyTaskState _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialState;
  }

  Future<void> _openAppSettingsPage() async {
    final result = await Navigator.of(context).push<DailyTaskState>(
      MaterialPageRoute(
        builder: (_) => _AppSelectionSettingsPage(
          initialState: _draft,
          launcher: widget.launcher,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _draft = result);
    }
  }

  Future<void> _openScriptsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ScriptSettingsPage(
          repository: widget.repository,
          launcher: widget.launcher,
          alarmBridge: widget.alarmBridge,
        ),
      ),
    );
  }

  Future<void> _openPermissionsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _PermissionSettingsPage(alarmBridge: widget.alarmBridge),
      ),
    );
  }

  Future<void> _openTasksPage() async {
    final result = await Navigator.of(context).push<DailyTaskState>(
      MaterialPageRoute(
        builder: (_) => _TaskManagementSettingsPage(
          initialState: _draft,
          repository: widget.repository,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _draft = result);
    }
  }

  Future<void> _openTemplatesPage() async {
    final result = await Navigator.of(context).push<DailyTaskState>(
      MaterialPageRoute(
        builder: (_) => _TemplateLibrarySettingsPage(
          initialState: _draft,
          repository: widget.repository,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _draft = result);
    }
  }

  Future<void> _openMottoPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DailyMottoSettingsPage(repository: widget.repository),
      ),
    );
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SettingsNavCell(
            icon: Icons.rocket_launch_rounded,
            iconTint: const Color(0xFF2F7D6B),
            iconBackground: const Color(0xFFDDF5EC),
            title: '启动应用',
            subtitle: '选择任务快捷打开的目标应用。',
            trailingText: _draft.selectedAppLabel,
            onTap: _openAppSettingsPage,
          ),
          _SettingsNavCell(
            icon: Icons.auto_fix_high_rounded,
            iconTint: const Color(0xFF7E22CE),
            iconBackground: const Color(0xFFF3E8FF),
            title: '脚本配置',
            subtitle: '管理自动化配置、启动悬浮菜单。',
            trailingText: '自动化',
            onTap: _openScriptsPage,
          ),
          _SettingsNavCell(
            icon: Icons.shield_outlined,
            iconTint: const Color(0xFF456DAA),
            iconBackground: const Color(0xFFE5F0FF),
            title: '提醒权限与系统设置',
            subtitle: '全屏通知、精确闹钟、辅助功能、自测。',
            trailingText: '6项',
            onTap: _openPermissionsPage,
          ),
          _SettingsNavCell(
            icon: Icons.checklist_rounded,
            iconTint: const Color(0xFFB06C22),
            iconBackground: const Color(0xFFFFEFD9),
            title: '任务管理',
            subtitle: '编辑任务、排序、启用状态、首页显示。',
            trailingText: '${_draft.taskDefinitions.length}个任务',
            onTap: _openTasksPage,
          ),
          _SettingsNavCell(
            icon: Icons.layers_rounded,
            iconTint: const Color(0xFF8A53B5),
            iconBackground: const Color(0xFFF2E4FF),
            title: '模板库',
            subtitle: '保存当前整套任务，整组复用与编辑。',
            trailingText: '${_draft.templateGroups.length}个模板',
            onTap: _openTemplatesPage,
          ),
          _SettingsNavCell(
            icon: Icons.auto_awesome_rounded,
            iconTint: const Color(0xFFB85082),
            iconBackground: const Color(0xFFFFE5F2),
            title: '每日箴言',
            subtitle: '可添加预设，也可自定义编辑。',
            trailingText: '自定义',
            onTap: _openMottoPage,
          ),
        ],
      ),
    );
  }
}

class _AppSelectionSettingsPage extends StatefulWidget {
  const _AppSelectionSettingsPage({
    required this.initialState,
    required this.launcher,
  });

  final DailyTaskState initialState;
  final DouyinLauncher launcher;

  @override
  State<_AppSelectionSettingsPage> createState() =>
      _AppSelectionSettingsPageState();
}

class _AppSelectionSettingsPageState extends State<_AppSelectionSettingsPage> {
  late DailyTaskState _draft;
  bool _loadingApps = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialState;
  }

  Future<void> _pickApp() async {
    setState(() => _loadingApps = true);
    final apps = await widget.launcher.listLaunchableApps();
    if (!mounted) return;
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
    if (selected == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        selectedAppPackage: selected.packageName,
        selectedAppLabel: selected.appName,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('启动应用'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_draft),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSectionCard(
            accent: const Color(0xFF78BEA8),
            title: '选择目标应用',
            subtitle: '当前：${_draft.selectedAppLabel}',
            helper: '任务卡片底部的快捷打开，将使用这里的目标应用。',
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.8,
              children: [
                _PastelButton(
                  label: '抖音极速版',
                  icon: Icons.rocket_launch_rounded,
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
                  label: _loadingApps
                      ? '加载中...'
                      : (_draft.selectedAppPackage ==
                                'com.ss.android.ugc.aweme.lite'
                            ? '选择更多'
                            : _draft.selectedAppLabel),
                  icon: Icons.apps_rounded,
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
        ],
      ),
    );
  }
}

class _ScriptSettingsPage extends StatelessWidget {
  const _ScriptSettingsPage({
    required this.repository,
    required this.launcher,
    required this.alarmBridge,
  });

  final TaskRepository repository;
  final DouyinLauncher launcher;
  final AlarmBridge alarmBridge;

  Future<void> _openGestureConfigs(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GestureConfigPage(repository: repository, launcher: launcher),
      ),
    );
    final configs = await repository.loadGestureConfigs();
    await alarmBridge.syncAutomationConfigs(
      configs: configs.map((config) => config.toJson()).toList(),
    );
  }

  Future<void> _startAutomationMenu(BuildContext context) async {
    final configs = await repository.loadGestureConfigs();
    final ok = await alarmBridge.showAutomationMenu(
      configs: configs.map((config) => config.toJson()).toList(),
    );
    if (!context.mounted) return;
    if (ok) {
      VibrantHUD.show(context, '悬浮菜单已启动', type: ToastType.success);
      return;
    }
    VibrantHUD.show(context, '请先开启辅助功能服务，再启动悬浮菜单', type: ToastType.warning);
    await alarmBridge.openAccessibilitySettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('脚本配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSectionCard(
            accent: const Color(0xFFC084FC),
            title: '自动化入口',
            subtitle: '配置点击、滑动、导航等连招',
            helper: '在这里进入自动化配置中心，或直接启动悬浮自动化菜单。',
            child: Row(
              children: [
                Expanded(
                  child: _PastelButton(
                    label: '我的配置',
                    icon: Icons.auto_fix_high_rounded,
                    background: theme.brightness == Brightness.dark
                        ? const Color(0xFF3B2A4A)
                        : const Color(0xFFF3E8FF),
                    foreground: theme.brightness == Brightness.dark
                        ? const Color(0xFFD8B4FE)
                        : const Color(0xFF7E22CE),
                    onPressed: () => _openGestureConfigs(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PastelButton(
                    label: '启动',
                    icon: Icons.play_arrow_rounded,
                    background: theme.brightness == Brightness.dark
                        ? const Color(0xFF1E3A5F)
                        : const Color(0xFFDBEAFE),
                    foreground: theme.brightness == Brightness.dark
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF1E40AF),
                    onPressed: () => _startAutomationMenu(context),
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

class _PermissionSettingsPage extends StatelessWidget {
  const _PermissionSettingsPage({required this.alarmBridge});

  final AlarmBridge alarmBridge;

  Widget _buildSubCategory(ThemeData theme, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            desc,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('提醒权限与系统设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSectionCard(
            accent: const Color(0xFF80A7F5),
            title: '提醒权限与系统设置',
            subtitle: '确保护理闹钟精准弹出',
            helper: '请依次开启以下权限，这是提醒能正常弹出的核心保障。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSubCategory(theme, '核心权限', '保证提醒必达'),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.8,
                  children: [
                    _PastelButton(
                      label: '全屏通知',
                      icon: Icons.notification_important_rounded,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF243649)
                          : const Color(0xFFE5F0FF),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFFA7C5FF)
                          : const Color(0xFF456DAA),
                      onPressed: alarmBridge.openFullScreenIntentSettings,
                    ),
                    _PastelButton(
                      label: '精确闹钟',
                      icon: Icons.alarm_on_rounded,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF1F3D39)
                          : const Color(0xFFDDF5EC),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFF94DFC9)
                          : const Color(0xFF2F7D6B),
                      onPressed: alarmBridge.openExactAlarmSettings,
                    ),
                    _PastelButton(
                      label: '通知权限',
                      icon: Icons.notifications_active_rounded,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF3A2F44)
                          : const Color(0xFFF2E4FF),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFFE0BAFF)
                          : const Color(0xFF8A53B5),
                      onPressed: alarmBridge.openNotificationSettings,
                    ),
                    _PastelButton(
                      label: '电池白名单',
                      icon: Icons.battery_charging_full_rounded,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF3F3022)
                          : const Color(0xFFFFEFD9),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFFFFCF8D)
                          : const Color(0xFFB06C22),
                      onPressed: alarmBridge.requestIgnoreBatteryOptimizations,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSubCategory(theme, '进阶优化', '提升运行稳定性'),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.8,
                  children: [
                    _PastelButton(
                      label: '悬浮窗设置',
                      icon: Icons.layers_outlined,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF353A21)
                          : const Color(0xFFF4F6D9),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFFDBE28F)
                          : const Color(0xFF7B8128),
                      onPressed: alarmBridge.openOverlaySettings,
                    ),
                    _PastelButton(
                      label: '辅助功能',
                      icon: Icons.accessibility_new_rounded,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF3A3040)
                          : const Color(0xFFFFE5F2),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFFFFB5D7)
                          : const Color(0xFFB85082),
                      onPressed: alarmBridge.openAccessibilitySettings,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSubCategory(theme, '调试与指引', '遇到问题点这里'),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.8,
                  children: [
                    _PastelButton(
                      label: '10秒自测',
                      icon: Icons.timer_outlined,
                      background: theme.brightness == Brightness.dark
                          ? const Color(0xFF1F3D39)
                          : const Color(0xFFDDF5EC),
                      foreground: theme.brightness == Brightness.dark
                          ? const Color(0xFF94DFC9)
                          : const Color(0xFF2F7D6B),
                      onPressed: () async {
                        final now = DateTime.now().add(
                          const Duration(seconds: 10),
                        );
                        await alarmBridge.scheduleSelfTest(
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
                          VibrantHUD.show(
                            context,
                            '已安排 10 秒后自测',
                            type: ToastType.success,
                          );
                        }
                      },
                    ),
                    _PastelButton(
                      label: '厂商指引',
                      icon: Icons.help_outline_rounded,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskManagementSettingsPage extends StatefulWidget {
  const _TaskManagementSettingsPage({
    required this.initialState,
    required this.repository,
  });

  final DailyTaskState initialState;
  final TaskRepository repository;

  @override
  State<_TaskManagementSettingsPage> createState() =>
      _TaskManagementSettingsPageState();
}

class _TaskManagementSettingsPageState
    extends State<_TaskManagementSettingsPage> {
  late DailyTaskState _draft;

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
    setState(() => _draft = _draft.copyWith(homeVisibleTaskIds: next));
  }

  Future<void> _editTask({AssistantTaskDefinition? task}) async {
    final edited = await showModalBottomSheet<AssistantTaskDefinition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          TaskEditorSheet(task: task, repository: widget.repository),
    );
    if (edited == null || !mounted) return;
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
    setState(() => _draft = _draft.copyWith(taskDefinitions: list));
  }

  String _taskSummary(AssistantTaskDefinition task) {
    final type = switch (task.kind) {
      AssistantTaskKind.feedWindow => '时间段',
      AssistantTaskKind.adCooldown => '循环次数',
      AssistantTaskKind.fixedPoint => '固定时间',
    };
    final suffix = task.kind == AssistantTaskKind.adCooldown
        ? (task.infiniteLoop
              ? ' · 无限循环 / 间隔${task.intervalLabel}'
              : ' · ${task.targetCount}次 / 间隔${task.intervalLabel}')
        : '';
    final quick = task.showQuickLaunch ? ' · 快捷打开应用' : '';
    final pre = (task.preGestureConfigId?.isNotEmpty ?? false)
        ? ' · 含前置脚本'
        : '';
    final autoOpen = task.autoOpenDelaySeconds > 0
        ? ' · ${task.autoOpenDelaySeconds}秒后自动打开'
        : '';
    return '$type · ${task.timeLabel}$suffix · 铃声 ${task.ringtoneLabel}$quick$pre$autoOpen';
  }

  String _kindGroupLabel(AssistantTaskKind kind) {
    return switch (kind) {
      AssistantTaskKind.feedWindow => '时间段任务',
      AssistantTaskKind.adCooldown => '循环计次任务',
      AssistantTaskKind.fixedPoint => '固定时间任务',
    };
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
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
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
                      const SizedBox(width: 10),
                      _MiniIconButton(
                        onPressed: () => _moveTask(task.id, 1),
                        icon: Icons.keyboard_arrow_down_rounded,
                      ),
                      const SizedBox(width: 10),
                      _MiniIconButton(
                        onPressed: () async {
                          final action = await showModalBottomSheet<String>(
                            context: context,
                            showDragHandle: true,
                            builder: (context) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.edit_rounded,
                                      color: Color(0xFF436EAF),
                                    ),
                                    title: const Text('编辑任务'),
                                    onTap: () =>
                                        Navigator.of(context).pop('edit'),
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFD32F2F),
                                    ),
                                    title: const Text('删除任务'),
                                    onTap: () =>
                                        Navigator.of(context).pop('delete'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          );
                          if (action == 'edit') {
                            _editTask(task: task);
                          } else if (action == 'delete') {
                            _deleteTask(task.id);
                          }
                        },
                        icon: Icons.more_vert_rounded,
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
                          onChanged: (value) =>
                              _toggleTaskEnabled(task.id, value),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
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
        children: _buildGroupedTaskSections(context),
      ),
    );
  }
}

class _TemplateLibrarySettingsPage extends StatefulWidget {
  const _TemplateLibrarySettingsPage({
    required this.initialState,
    required this.repository,
  });

  final DailyTaskState initialState;
  final TaskRepository repository;

  @override
  State<_TemplateLibrarySettingsPage> createState() =>
      _TemplateLibrarySettingsPageState();
}

class _TemplateLibrarySettingsPageState
    extends State<_TemplateLibrarySettingsPage> {
  late DailyTaskState _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialState;
  }

  void _applyTemplateGroup(TaskTemplateGroup group) {
    final base = DateTime.now().millisecondsSinceEpoch;
    final copiedTasks = group.tasks
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(id: 'task_${base}_${entry.key}'))
        .toList();
    final idMap = {
      for (final entry in group.tasks.asMap().entries)
        entry.value.id: copiedTasks[entry.key].id,
    };
    final ids = copiedTasks.map((item) => item.id).toSet();
    final enabledIds = group.effectiveEnabledTaskIds
        .map((id) => idMap[id])
        .whereType<String>()
        .toSet();
    final visibleIds = group.effectiveHomeVisibleTaskIds
        .map((id) => idMap[id])
        .whereType<String>()
        .toSet();
    setState(() {
      _draft = _draft.copyWith(
        taskDefinitions: copiedTasks,
        enabledTaskIds: enabledIds.isEmpty ? ids : enabledIds,
        homeVisibleTaskIds: visibleIds.isEmpty ? ids : visibleIds,
        completedTaskIds: const {},
        intervalCompletedCounts: const {},
        intervalNextAvailableAt: const {},
      );
    });
  }

  Future<void> _showSaveTemplateGroupDialog() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _TemplateNameSheet(
        title: '保存为模板',
        fieldLabel: '模板名称',
        actionLabel: '保存',
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: [
          ..._draft.templateGroups,
          TaskTemplateGroup(
            id: 'group_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            tasks: _draft.taskDefinitions.map((t) => t.copyWith()).toList(),
            enabledTaskIds: _draft.enabledTaskIds
                .where(
                  _draft.taskDefinitions
                      .map((task) => task.id)
                      .toSet()
                      .contains,
                )
                .toSet(),
            homeVisibleTaskIds: _draft.homeVisibleTaskIds
                .where(
                  _draft.taskDefinitions
                      .map((task) => task.id)
                      .toSet()
                      .contains,
                )
                .toSet(),
          ),
        ],
      );
    });
  }

  Future<void> _renameTemplateGroup(TaskTemplateGroup group) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TemplateNameSheet(
        title: '重命名模板',
        fieldLabel: '模板名称',
        actionLabel: '保存',
        initialValue: group.name,
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: _draft.templateGroups
            .map(
              (item) => item.id == group.id
                  ? TaskTemplateGroup(
                      id: item.id,
                      name: name,
                      tasks: item.tasks,
                      enabledTaskIds: item.effectiveEnabledTaskIds,
                      homeVisibleTaskIds: item.effectiveHomeVisibleTaskIds,
                      builtIn: item.builtIn,
                    )
                  : item,
            )
            .toList(),
      );
    });
  }

  Future<void> _editTemplateGroup(TaskTemplateGroup group) async {
    final result = await Navigator.of(context).push<TaskTemplateGroup>(
      MaterialPageRoute(
        builder: (_) =>
            TemplateTasksPage(group: group, repository: widget.repository),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        templateGroups: _draft.templateGroups
            .map((item) => item.id == group.id ? result : item)
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
        title: const Text('模板库'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_draft),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: const Text('将当前全部任务保存为模板'),
              subtitle: const Text('保存当前整套任务配置，供以后整组套用。'),
              trailing: FilledButton.tonal(
                key: const ValueKey('save_template_group_button'),
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
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (!group.builtIn) ...[
                          _MiniIconButton(
                            onPressed: () => _renameTemplateGroup(group),
                            icon: Icons.drive_file_rename_outline_rounded,
                          ),
                          const SizedBox(width: 8),
                          _MiniIconButton(
                            onPressed: () => _editTemplateGroup(group),
                            icon: Icons.edit_note_rounded,
                          ),
                          const SizedBox(width: 8),
                          _MiniIconButton(
                            onPressed: () => _deleteTemplateGroup(group.id),
                            icon: Icons.delete_outline_rounded,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '含 ${group.tasks.length} 个任务',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: mintFill,
                            foregroundColor: mintText,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () => _applyTemplateGroup(group),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_motion_rounded, size: 16),
                              SizedBox(width: 6),
                              Text(
                                '整组使用',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({this.task, required this.repository, super.key});

  final AssistantTaskDefinition? task;
  final TaskRepository repository;

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
  late TextEditingController _autoOpenDelayController;
  late IntervalUnit _intervalUnit;
  late RingtoneSource _ringtoneSource;
  String? _ringtoneFilePath;
  late bool _showQuickLaunch;
  late bool _infiniteLoop;
  String? _preGestureConfigId;
  String? _gestureConfigId;
  List<GestureConfig> _availableConfigs = [];
  bool _showError = false;

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
      text: '${task?.cooldownValue ?? 10}',
    );
    _autoOpenDelayController = TextEditingController(
      text: '${task?.autoOpenDelaySeconds ?? 0}',
    );
    _intervalUnit = task?.intervalUnit ?? IntervalUnit.minutes;
    _showQuickLaunch = task?.showQuickLaunch ?? false;
    _infiniteLoop = task?.infiniteLoop ?? false;
    _preGestureConfigId = task?.preGestureConfigId;
    _gestureConfigId = task?.gestureConfigId;
    _loadConfigs();
    _titleController.addListener(() {
      if (_showError && _titleController.text.trim().isNotEmpty) {
        setState(() => _showError = false);
      }
    });
  }

  Future<void> _loadConfigs() async {
    final configs = await widget.repository.loadGestureConfigs();
    if (mounted) {
      setState(() => _availableConfigs = configs);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _ringtoneController.dispose();
    _targetController.dispose();
    _cooldownController.dispose();
    _autoOpenDelayController.dispose();
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

  Future<void> _pickGestureConfig() async {
    final selected = await _pickConfigId(
      title: '选择执行脚本',
      allowNoneLabel: '无 (不关联脚本)',
    );
    if (selected != null) {
      setState(() {
        _gestureConfigId = selected == 'none' ? null : selected;
      });
    }
  }

  Future<void> _pickPreGestureConfig() async {
    final selected = await _pickConfigId(
      title: '选择前置脚本',
      allowNoneLabel: '无 (不执行前置脚本)',
    );
    if (selected != null) {
      setState(() {
        _preGestureConfigId = selected == 'none' ? null : selected;
      });
    }
  }

  Future<String?> _pickConfigId({
    required String title,
    required String allowNoneLabel,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(allowNoneLabel),
              onTap: () => Navigator.of(context).pop('none'),
            ),
            if (_availableConfigs.isNotEmpty) const Divider(),
            ..._availableConfigs.map(
              (c) => ListTile(
                title: Text(c.name),
                onTap: () => Navigator.of(context).pop(c.id),
              ),
            ),
          ],
        ),
      ),
    );
    return selected;
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
                    decoration: InputDecoration(
                      labelText: '任务名称',
                      errorText: _showError ? '任务名称不能为空' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TaskKindSelector(
                    value: _kind,
                    onChanged: (value) => setState(() => _kind = value),
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('无限循环'),
                      subtitle: const Text('开启后，不再受循环次数限制'),
                      value: _infiniteLoop,
                      onChanged: (value) =>
                          setState(() => _infiniteLoop = value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _targetController,
                            enabled: !_infiniteLoop,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '循环次数',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _cooldownController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '间隔值'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _IntervalUnitSelector(
                            value: _intervalUnit,
                            onChanged: (value) =>
                                setState(() => _intervalUnit = value),
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
                child: Column(
                  children: [
                    Container(
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _autoOpenDelayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '全屏提醒后自动打开秒数',
                        helperText: '填 0 为关闭。到时后自动点击“打开应用 / 去完成任务”。',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _EditorSectionCard(
              accent: const Color(0xFF8EB8FF),
              title: '脚本配置',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _EditorPickerTile(
                      label: '前置脚本',
                      value:
                          _availableConfigs
                              .where((c) => c.id == _preGestureConfigId)
                              .firstOrNull
                              ?.name ??
                          '未关联',
                      onTap: _pickPreGestureConfig,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EditorPickerTile(
                      label: '执行脚本',
                      value:
                          _availableConfigs
                              .where((c) => c.id == _gestureConfigId)
                              .firstOrNull
                              ?.name ??
                          '未关联',
                      onTap: _pickGestureConfig,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _EditorSectionCard(
              accent: const Color(0xFFD69AF1),
              title: '提醒铃声',
              child: Column(
                children: [
                  _RingtoneSourceSelector(
                    value: _ringtoneSource,
                    onChanged: (value) async {
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
                  setState(() => _showError = true);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('请填写任务名称')));
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
                    cooldownValue: isCounter
                        ? int.tryParse(_cooldownController.text) ?? 10
                        : 0,
                    intervalUnit: _intervalUnit,
                    ringtoneLabel: _ringtoneController.text.trim().isEmpty
                        ? '默认铃声'
                        : _ringtoneController.text.trim(),
                    ringtoneSource: _ringtoneSource,
                    ringtoneValue: _ringtoneFilePath,
                    showQuickLaunch: _showQuickLaunch,
                    preGestureConfigId: _preGestureConfigId,
                    gestureConfigId: _gestureConfigId,
                    infiniteLoop: _infiniteLoop,
                    autoOpenDelaySeconds:
                        int.tryParse(_autoOpenDelayController.text.trim()) ?? 0,
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

class _DailyMottoSettingsPage extends StatefulWidget {
  const _DailyMottoSettingsPage({required this.repository});

  final TaskRepository repository;

  @override
  State<_DailyMottoSettingsPage> createState() =>
      _DailyMottoSettingsPageState();
}

class _DailyMottoSettingsPageState extends State<_DailyMottoSettingsPage> {
  static const List<String> _presetMottos = [
    '天生我才必有用，千金散尽还复来',
    '长风破浪会有时，直挂云帆济沧海',
    '且将新火试新茶，诗酒趁年华',
    '莫道桑榆晚，为霞尚满天',
    '山高路远，亦要见自己',
    '日日自新，步步生光',
  ];

  List<String> _mottos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await widget.repository.loadDailyMottos();
    if (!mounted) return;
    setState(() {
      _mottos = values.isEmpty ? [..._presetMottos] : values;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await widget.repository.saveDailyMottos(_mottos);
    if (!mounted) return;
    VibrantHUD.show(context, '每日箴言已保存', type: ToastType.success);
  }

  Future<void> _editItem({String initialValue = '', int? index}) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TemplateNameSheet(
        title: index == null ? '新增箴言' : '编辑箴言',
        fieldLabel: '箴言内容',
        actionLabel: '保存',
        initialValue: initialValue,
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      if (index == null) {
        _mottos = [..._mottos, result];
      } else {
        _mottos = [
          for (var i = 0; i < _mottos.length; i++)
            if (i == index) result else _mottos[i],
        ];
      }
    });
    await _save();
  }

  Future<void> _pickPreset() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _presetMottos
              .map(
                (item) => ListTile(
                  title: Text(item),
                  onTap: () => Navigator.of(context).pop(item),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (result == null) return;
    setState(() => _mottos = [..._mottos, result]);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日箴言'),
        actions: [TextButton(onPressed: _pickPreset, child: const Text('预设'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(),
        label: const Text('新增箴言'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          ..._mottos.indexed.map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(item),
                subtitle: const Text('首页按日期随机展示'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniIconButton(
                      onPressed: () =>
                          _editItem(initialValue: item, index: index),
                      icon: Icons.edit_rounded,
                    ),
                    const SizedBox(width: 8),
                    _MiniIconButton(
                      onPressed: () async {
                        setState(() {
                          _mottos = [
                            for (var i = 0; i < _mottos.length; i++)
                              if (i != index) _mottos[i],
                          ];
                        });
                        await _save();
                      },
                      icon: Icons.delete_outline_rounded,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TemplateNameSheet extends StatefulWidget {
  const _TemplateNameSheet({
    required this.title,
    required this.fieldLabel,
    required this.actionLabel,
    this.initialValue = '',
  });

  final String title;
  final String fieldLabel;
  final String actionLabel;
  final String initialValue;

  @override
  State<_TemplateNameSheet> createState() => _TemplateNameSheetState();
}

class _TemplateNameSheetState extends State<_TemplateNameSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(16, 4, 16, viewInsets.bottom + 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.58),
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: theme.brightness == Brightness.dark
                              ? const [Color(0xFF1A2C2A), Color(0xFF1A2232)]
                              : const [Color(0xFFE7F7F1), Color(0xFFE8F0FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('template_name_field'),
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(labelText: widget.fieldLabel),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonal(
                            key: const ValueKey('template_name_submit_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  theme.brightness == Brightness.dark
                                  ? const Color(0xFF1F3D39)
                                  : const Color(0xFFDDF5EC),
                              foregroundColor:
                                  theme.brightness == Brightness.dark
                                  ? const Color(0xFF94DFC9)
                                  : const Color(0xFF2F7D6B),
                            ),
                            onPressed: _submit,
                            child: Text(widget.actionLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
              accent.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.12 : 0.1,
              ),
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

class _TaskKindSelector extends StatelessWidget {
  const _TaskKindSelector({required this.value, required this.onChanged});

  final AssistantTaskKind value;
  final ValueChanged<AssistantTaskKind> onChanged;

  static const _items = [
    (
      AssistantTaskKind.fixedPoint,
      '固定时间',
      '到点即响，适合单次或循环任务',
      Color(0xFF7FA7F8),
      Icons.alarm_rounded,
    ),
    (
      AssistantTaskKind.feedWindow,
      '时间段',
      '在设定的时间段内手动完成',
      Color(0xFF69C5AF),
      Icons.play_circle_outline_rounded,
    ),
    (
      AssistantTaskKind.adCooldown,
      '循环计次',
      '多次任务，带自动冷却倒计时',
      Color(0xFFFFA977),
      Icons.hourglass_bottom_rounded,
    ),
  ];

  String _labelFor(AssistantTaskKind kind) {
    return _items.firstWhere((item) => item.$1 == kind).$2;
  }

  Future<void> _showPicker(BuildContext context) async {
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<AssistantTaskKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            children: [
              Text(
                '选择任务类型',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ..._items.map((item) {
                final isSelected = value == item.$1;
                final accent = item.$4;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(item.$1),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (theme.brightness == Brightness.dark
                                  ? accent.withValues(alpha: 0.15)
                                  : accent.withValues(alpha: 0.1))
                            : (theme.brightness == Brightness.dark
                                  ? const Color(0xFF172425)
                                  : const Color(0xFFF4F8F6)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : theme.colorScheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(item.$5, color: accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$2,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: isSelected
                                        ? accent
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.$3,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_rounded, color: accent),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: '任务类型'),
        child: Text(
          _labelFor(value),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _IntervalUnitSelector extends StatelessWidget {
  const _IntervalUnitSelector({required this.value, required this.onChanged});

  final IntervalUnit value;
  final ValueChanged<IntervalUnit> onChanged;

  static const _items = [
    (IntervalUnit.seconds, '秒', '10秒后'),
    (IntervalUnit.minutes, '分', '1分钟后'),
    (IntervalUnit.hours, '时', '1小时后'),
    (IntervalUnit.days, '天', '1天后'),
  ];

  String _labelFor(IntervalUnit unit) {
    return _items.firstWhere((item) => item.$1 == unit).$2;
  }

  Future<void> _showPicker(BuildContext context) async {
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<IntervalUnit>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            children: [
              Text(
                '选择间隔单位',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ..._items.map((item) {
                final selected = value == item.$1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(item.$1),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? (theme.brightness == Brightness.dark
                                  ? const Color(0xFF1F3D39)
                                  : const Color(0xFFDDF5EC))
                            : (theme.brightness == Brightness.dark
                                  ? const Color(0xFF172425)
                                  : const Color(0xFFF4F8F6)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF83D8BD)
                              : theme.colorScheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$2,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: selected
                                        ? const Color(0xFF2F7D6B)
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.$3,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_rounded,
                              color: Color(0xFF2F7D6B),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: '单位'),
        child: Text(
          _labelFor(value),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _RingtoneSourceSelector extends StatelessWidget {
  const _RingtoneSourceSelector({required this.value, required this.onChanged});

  final RingtoneSource value;
  final ValueChanged<RingtoneSource> onChanged;

  static const _items = [
    (
      RingtoneSource.systemDefault,
      '系统默认',
      '直接使用应用自带的提醒音',
      Color(0xFF69C5AF),
      Icons.music_note_rounded,
    ),
    (
      RingtoneSource.systemAlarm,
      '系统铃声',
      '从手机系统闹钟铃声库中选择',
      Color(0xFF7FA7F8),
      Icons.library_music_rounded,
    ),
    (
      RingtoneSource.filePath,
      '本地文件',
      '从手机存储空间选择 MP3/WAV 等',
      Color(0xFFD38FF2),
      Icons.folder_open_rounded,
    ),
  ];

  String _labelFor(RingtoneSource source) {
    return _items.firstWhere((item) => item.$1 == source).$2;
  }

  Future<void> _showPicker(BuildContext context) async {
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<RingtoneSource>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            children: [
              Text(
                '选择铃声来源',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ..._items.map((item) {
                final isSelected = value == item.$1;
                final accent = item.$4;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(item.$1),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (theme.brightness == Brightness.dark
                                  ? accent.withValues(alpha: 0.15)
                                  : accent.withValues(alpha: 0.1))
                            : (theme.brightness == Brightness.dark
                                  ? const Color(0xFF172425)
                                  : const Color(0xFFF4F8F6)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : theme.colorScheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(item.$5, color: accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$2,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: isSelected
                                        ? accent
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.$3,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_rounded, color: accent),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: '铃声来源'),
        child: Text(
          _labelFor(value),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class TemplateTasksPage extends StatefulWidget {
  const TemplateTasksPage({
    required this.group,
    required this.repository,
    super.key,
  });

  final TaskTemplateGroup group;
  final TaskRepository repository;

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
  late Set<String> _enabledTaskIds;
  late Set<String> _homeVisibleTaskIds;

  @override
  void initState() {
    super.initState();
    _tasks = [...widget.group.tasks];
    _enabledTaskIds = widget.group.effectiveEnabledTaskIds;
    _homeVisibleTaskIds = widget.group.effectiveHomeVisibleTaskIds;
  }

  void _removeTask(String taskId) {
    setState(() {
      _tasks = _tasks.where((item) => item.id != taskId).toList();
      _enabledTaskIds = {..._enabledTaskIds}..remove(taskId);
      _homeVisibleTaskIds = {..._homeVisibleTaskIds}..remove(taskId);
    });
  }

  Future<void> _editTask({AssistantTaskDefinition? task}) async {
    final edited = await showModalBottomSheet<AssistantTaskDefinition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          TaskEditorSheet(task: task, repository: widget.repository),
    );
    if (edited == null) {
      return;
    }
    setState(() {
      final exists = _tasks.any((item) => item.id == edited.id);
      _tasks = exists
          ? _tasks.map((item) => item.id == edited.id ? edited : item).toList()
          : [..._tasks, edited];
      _enabledTaskIds = {..._enabledTaskIds, edited.id};
      _homeVisibleTaskIds = {..._homeVisibleTaskIds, edited.id};
    });
  }

  void _toggleTaskEnabled(String taskId, bool enabled) {
    final next = {..._enabledTaskIds};
    if (enabled) {
      next.add(taskId);
    } else {
      next.remove(taskId);
    }
    setState(() {
      _enabledTaskIds = next;
    });
  }

  void _toggleHomeVisible(String taskId, bool visible) {
    final next = {..._homeVisibleTaskIds};
    if (visible) {
      next.add(taskId);
    } else {
      next.remove(taskId);
    }
    setState(() {
      _homeVisibleTaskIds = next;
    });
  }

  TaskTemplateGroup _buildResult() {
    final taskIds = _tasks.map((task) => task.id).toSet();
    return TaskTemplateGroup(
      id: widget.group.id,
      name: widget.group.name,
      tasks: _tasks,
      enabledTaskIds: _enabledTaskIds.where(taskIds.contains).toSet(),
      homeVisibleTaskIds: _homeVisibleTaskIds.where(taskIds.contains).toSet(),
      builtIn: widget.group.builtIn,
    );
  }

  void _moveTask(String taskId, int delta) {
    final list = [..._tasks];
    final index = list.indexWhere((item) => item.id == taskId);
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= list.length) return;
    final item = list.removeAt(index);
    list.insert(nextIndex, item);
    setState(() {
      _tasks = list;
    });
  }

  String _taskSummary(AssistantTaskDefinition task) {
    final type = switch (task.kind) {
      AssistantTaskKind.feedWindow => '时间段',
      AssistantTaskKind.adCooldown => '循环次数',
      AssistantTaskKind.fixedPoint => '固定时间',
    };
    final suffix = task.kind == AssistantTaskKind.adCooldown
        ? (task.infiniteLoop
              ? ' · 无限循环 / 间隔${task.intervalLabel}'
              : ' · ${task.targetCount}次 / 间隔${task.intervalLabel}')
        : '';
    final quick = task.showQuickLaunch ? ' · 快捷打开应用' : '';
    final pre = (task.preGestureConfigId?.isNotEmpty ?? false)
        ? ' · 含前置脚本'
        : '';
    final autoOpen = task.autoOpenDelaySeconds > 0
        ? ' · ${task.autoOpenDelaySeconds}秒后自动打开'
        : '';
    return '$type · ${task.timeLabel}$suffix · 铃声 ${task.ringtoneLabel}$quick$pre$autoOpen';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_buildResult()),
            child: const Text('保存'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editTask(),
        label: const Text('新增任务'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_tasks.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '这个模板还没有任务。点击右下角“新增任务”添加。',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          ..._tasks.map((task) {
            final enabled = _enabledTaskIds.contains(task.id);
            final homeVisible = _homeVisibleTaskIds.contains(task.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
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
                                  fontWeight: FontWeight.w900,
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
                        const SizedBox(width: 6),
                        _MiniIconButton(
                          onPressed: () => _editTask(task: task),
                          icon: Icons.edit_note_rounded,
                        ),
                        const SizedBox(width: 6),
                        _MiniIconButton(
                          onPressed: () => _removeTask(task.id),
                          icon: Icons.delete_outline_rounded,
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
                            onChanged: (value) =>
                                _toggleTaskEnabled(task.id, value),
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
            );
          }),
        ],
      ),
    );
  }
}
