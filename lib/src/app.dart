import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

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
part 'app_parts/app_settings_pages.dart';
part 'app_parts/app_task_pages.dart';
part 'app_parts/app_task_editor.dart';
part 'app_parts/app_motto_pages.dart';

enum ToastType { success, error, info, warning }

const _appSeed = Color(0xFF7A86FF);
const _lightSurface = Color(0xFFF7FAF8);
const _darkSurface = Color(0xFF0F1718);
const _defaultDailyMottoSourceUrl = 'https://www.wenxue360.com/gushiwen/';

String _dateKey(DateTime now) {
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

Future<List<String>> fetchDailyMottosFromUrl(String rawUrl) async {
  final url = rawUrl.trim();
  if (url.isEmpty) {
    return const [];
  }
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('抓取失败：${response.statusCode}');
  }
  final html = utf8.decode(response.bodyBytes, allowMalformed: true);
  final document = html_parser.parse(html);
  final anchors = document.querySelectorAll('div.post-body a, .post-body a');
  final results = <String>[];
  for (final anchor in anchors) {
    final text = anchor.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.length < 4 || text.length > 40) {
      continue;
    }
    if (text.contains('相关古诗文') ||
        text.contains('古诗文') ||
        text.contains('文学360')) {
      continue;
    }
    if (results.contains(text)) {
      continue;
    }
    results.add(text);
    if (results.length >= 10) {
      break;
    }
  }
  return results;
}

Future<String?> fetchDailyMottoImageUrl() async {
  final response = await http.get(
    Uri.parse(
      'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN',
    ),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('图片抓取失败：${response.statusCode}');
  }
  final decoded =
      jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true))
          as Map<String, Object?>;
  final images = decoded['images'] as List<Object?>? ?? const [];
  final first = images.firstOrNull;
  if (first is! Map<String, Object?>) {
    return null;
  }
  final url = (first['url'] as String?)?.trim();
  if (url == null || url.isEmpty) {
    return null;
  }
  return url.startsWith('http') ? url : 'https://www.bing.com$url';
}

bool _looksLikeMojibake(String value) {
  return value.contains('å') ||
      value.contains('è') ||
      value.contains('é') ||
      value.contains('æ') ||
      value.contains('ç') ||
      value.contains('Ã');
}

ThemeData _scriptAssistantTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _appSeed,
    brightness: brightness,
  );
  final glassSurface = isDark
      ? const Color(0xFF23274E)
      : const Color(0xFFF0F3FF);
  final glassBorder = isDark
      ? const Color(0xFF515A9B)
      : const Color(0xFFC5D0FF);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF171A5A)
        : const Color(0xFFF0F3FF),
    cardTheme: CardThemeData(
      color: glassSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: glassBorder),
      ),
      shadowColor: const Color(0xFF72DFFF).withValues(alpha: 0.18),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: isDark
          ? const Color(0xFF1D214C)
          : const Color(0xFFF4F6FF),
      surfaceTintColor: Colors.transparent,
      foregroundColor: isDark ? Colors.white : const Color(0xFF26336F),
      elevation: 0,
      titleTextStyle: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF26336F),
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
      iconTheme: IconThemeData(
        color: isDark ? Colors.white : const Color(0xFF39478F),
      ),
      actionsIconTheme: IconThemeData(
        color: isDark ? Colors.white : const Color(0xFF39478F),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: glassSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: glassBorder),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark
          ? const Color(0xFF202552)
          : const Color(0xFFE7ECFF),
      modalBackgroundColor: isDark
          ? const Color(0xFF202552)
          : const Color(0xFFE7ECFF),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      showDragHandle: true,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      tileColor: Colors.white.withValues(alpha: isDark ? 0.06 : 0.46),
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.42),
      iconColor: scheme.primary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF232756)
          : const Color(0xFFF1F4FF),
      indicatorColor: const Color(0xFF72DFFF).withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected
              ? (isDark ? Colors.white : const Color(0xFF1B2453))
              : (isDark
                    ? Colors.white.withValues(alpha: 0.68)
                    : const Color(0xFF53609A)),
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected
              ? (isDark ? Colors.white : const Color(0xFF1B2453))
              : (isDark
                    ? Colors.white.withValues(alpha: 0.70)
                    : const Color(0xFF53609A)),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark
            ? const Color(0xFF4858B8)
            : const Color(0xFFDCE4FF),
        foregroundColor: isDark ? Colors.white : const Color(0xFF243177),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: isDark ? Colors.white : const Color(0xFF243177),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: isDark
            ? const Color(0xFF2A2F63)
            : const Color(0xFFF3F5FF),
        foregroundColor: isDark ? Colors.white : const Color(0xFF243177),
        side: BorderSide(color: glassBorder),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2F63) : const Color(0xFFE5E9FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF616AC0) : const Color(0xFFC9D2FF),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF8BA6FF) : const Color(0xFF728BFF),
          width: 1.4,
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
  List<DailyMottoEntry> _dailyMottoEntries = const [];
  String? _pinnedDailyMottoId;
  String? _dailyMottoImageUrl;
  String? _dailyMottoImagePath;
  bool _showDailyMottoMetaOnHome = true;
  bool _autoScrollDailyMottoOnHome = false;
  int _autoScrollDailyMottoIntervalValue = 3;
  IntervalUnit _autoScrollDailyMottoIntervalUnit = IntervalUnit.seconds;
  bool _handlingOverlayCommand = false;
  final Map<String, Timer> _autoCompleteTimers = {};
  final Map<String, DateTime> _autoCompleteDueAt = {};

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
      final pendingOpenTaskId = widget.enablePlatformServices
          ? await _alarmBridge.consumePendingOpenTaskId()
          : null;
      final pendingAutoComplete = widget.enablePlatformServices
          ? await _alarmBridge.consumePendingAutoComplete()
          : null;
      final sourceUrl =
          await _repository.loadDailyMottoSourceUrl() ??
          _defaultDailyMottoSourceUrl;
      final lastFetchDate = await _repository.loadDailyMottoLastFetchDate();
      final todayKey = _dateKey(DateTime.now());
      final hasBrokenMottos =
          (await _repository.loadDailyMottoEntries()).any(
            (item) => _looksLikeMojibake(item.content),
          ) ||
          (await _repository.loadDailyMottos()).any(_looksLikeMojibake);
      if (sourceUrl.isNotEmpty &&
          (lastFetchDate != todayKey || hasBrokenMottos)) {
        try {
          final fetched = await fetchDailyMottosFromUrl(sourceUrl);
          if (fetched.isNotEmpty) {
            await _repository.saveDailyMottoEntries(
              fetched.map(DailyMottoEntry.fromLegacy).toList(),
            );
            await _repository.saveDailyMottoSourceUrl(sourceUrl);
            await _repository.saveDailyMottoLastFetchDate(todayKey);
          }
        } catch (_) {}
      }
      final gestureConfigs = await _repository.loadGestureConfigs();
      final dailyMottoEntries = await _repository.loadDailyMottoEntries();
      final pinnedDailyMottoId = await _repository.loadPinnedDailyMottoId();
      var dailyMottoImageUrl = await _repository.loadDailyMottoImageUrl();
      final dailyMottoImagePath = await _repository.loadDailyMottoImagePath();
      final showDailyMottoMetaOnHome = await _repository
          .loadShowDailyMottoMetaOnHome();
      final autoScrollDailyMottoOnHome = await _repository
          .loadAutoScrollDailyMottoOnHome();
      final autoScrollDailyMottoIntervalValue = await _repository
          .loadAutoScrollDailyMottoIntervalValue();
      final autoScrollDailyMottoIntervalUnit = await _repository
          .loadAutoScrollDailyMottoIntervalUnit();
      final dailyMottoImageFetchDate = await _repository
          .loadDailyMottoImageFetchDate();
      if (dailyMottoImageFetchDate != todayKey) {
        try {
          final fetchedImageUrl = await fetchDailyMottoImageUrl();
          if (fetchedImageUrl != null && fetchedImageUrl.isNotEmpty) {
            dailyMottoImageUrl = fetchedImageUrl;
            await _repository.saveDailyMottoImageUrl(fetchedImageUrl);
            await _repository.saveDailyMottoImageFetchDate(todayKey);
          }
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state;
        _gestureConfigs = gestureConfigs;
        _dailyMottoEntries = dailyMottoEntries;
        _pinnedDailyMottoId = pinnedDailyMottoId;
        _dailyMottoImageUrl = dailyMottoImageUrl;
        _dailyMottoImagePath = dailyMottoImagePath;
        _showDailyMottoMetaOnHome = showDailyMottoMetaOnHome;
        _autoScrollDailyMottoOnHome = autoScrollDailyMottoOnHome;
        _autoScrollDailyMottoIntervalValue = autoScrollDailyMottoIntervalValue;
        _autoScrollDailyMottoIntervalUnit = autoScrollDailyMottoIntervalUnit;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePendingAlarmTaskOpen(
          pendingOpenTaskId,
          pendingAutoComplete == null
              ? null
              : (
                  taskId: pendingAutoComplete.taskId,
                  dueAt: DateTime.fromMillisecondsSinceEpoch(
                    pendingAutoComplete.dueAtMillis,
                  ),
                ),
        );
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
    for (final timer in _autoCompleteTimers.values) {
      timer.cancel();
    }
    _autoCompleteTimers.clear();
    _autoCompleteDueAt.clear();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadStateFromRepository();
      _consumePendingAlarmActions();
      _handlePendingOverlayCommand();
    }
  }

  Future<void> _reloadStateFromRepository() async {
    final current = _state;
    if (current == null) return;
    final latest = await _repository.loadOrCreateToday(current.taskDefinitions);
    if (!mounted) return;
    setState(() {
      _state = latest;
    });
  }

  Future<void> _consumePendingAlarmActions() async {
    if (!widget.enablePlatformServices) return;
    final pendingOpenTaskId = await _alarmBridge.consumePendingOpenTaskId();
    final pending = await _alarmBridge.consumePendingAutoComplete();
    await _handlePendingAlarmTaskOpen(
      pendingOpenTaskId,
      pending == null
          ? null
          : (
              taskId: pending.taskId,
              dueAt: DateTime.fromMillisecondsSinceEpoch(pending.dueAtMillis),
            ),
    );
  }

  Future<void> _persistState(
    DailyTaskState next, {
    String? message,
    ToastType type = ToastType.info,
  }) async {
    await _repository.save(next);
    if (widget.enablePlatformServices) {
      await _notifications.scheduleForState(next, next.taskDefinitions);
      await _alarmBridge.refreshHomeWidget();
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

  Future<void> _triggerAutoCompleteTask(String taskId) async {
    _autoCompleteTimers.remove(taskId)?.cancel();
    _autoCompleteDueAt.remove(taskId);
    final state = _state;
    if (state == null) return;
    final task = state.taskDefinitions
        .where((item) => item.id == taskId)
        .firstOrNull;
    if (task == null) return;
    if (task.kind == AssistantTaskKind.adCooldown) {
      await _markCounterTaskDone(task);
      return;
    }
    await _markSingleTaskDone(taskId);
  }

  void _scheduleAutoCompleteTask(String taskId, DateTime dueAt) {
    _autoCompleteTimers.remove(taskId)?.cancel();
    _autoCompleteDueAt[taskId] = dueAt;
    final delay = dueAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      unawaited(_triggerAutoCompleteTask(taskId));
      return;
    }
    _autoCompleteTimers[taskId] = Timer(delay, () {
      unawaited(_triggerAutoCompleteTask(taskId));
    });
  }

  Future<void> _handlePendingAlarmTaskOpen(
    String? taskId,
    ({String taskId, DateTime dueAt})? pendingAutoComplete,
  ) async {
    if (!mounted) return;
    if (pendingAutoComplete != null) {
      _scheduleAutoCompleteTask(
        pendingAutoComplete.taskId,
        pendingAutoComplete.dueAt,
      );
    }
    if (taskId == null || taskId.isEmpty) return;
    final state = _state;
    if (state == null) return;
    final task = state.taskDefinitions
        .where((item) => item.id == taskId)
        .firstOrNull;
    if (task == null) return;
    final autoCompleteDueAt =
        pendingAutoComplete != null && pendingAutoComplete.taskId == taskId
        ? pendingAutoComplete.dueAt
        : _autoCompleteDueAt[taskId];
    final delay = autoCompleteDueAt == null
        ? null
        : autoCompleteDueAt.difference(DateTime.now());
    await _openSelectedApp(task, autoCompleteAfter: delay);
  }

  Future<void> _updateTaskDefinition(
    String taskId,
    AssistantTaskDefinition Function(AssistantTaskDefinition task) transform, {
    String? message,
    ToastType type = ToastType.success,
  }) async {
    await _mutateState(
      (state) {
        final nextTasks = state.taskDefinitions
            .map((task) => task.id == taskId ? transform(task) : task)
            .toList();
        return state.copyWith(taskDefinitions: nextTasks);
      },
      message: message,
      type: type,
    );
  }

  Future<void> _resetTaskProgress(AssistantTaskDefinition task) async {
    await _mutateState((state) {
      final nextCompleted = {...state.completedTaskIds}..remove(task.id);
      final nextCounts = {...state.intervalCompletedCounts}..remove(task.id);
      final nextTimes = {...state.intervalNextAvailableAt}..remove(task.id);
      return state.copyWith(
        completedTaskIds: nextCompleted,
        intervalCompletedCounts: nextCounts,
        intervalNextAvailableAt: nextTimes,
      );
    }, message: '${task.title} 已重置');
  }

  Future<void> _toggleTaskHomeVisible(AssistantTaskDefinition task) async {
    await _mutateState((state) {
      final next = {...state.homeVisibleTaskIds};
      if (next.contains(task.id)) {
        next.remove(task.id);
      } else {
        next.add(task.id);
      }
      return state.copyWith(homeVisibleTaskIds: next);
    }, message: stateMessageForHomeVisible(task));
  }

  String stateMessageForHomeVisible(AssistantTaskDefinition task) {
    final state = _state;
    if (state == null) {
      return '任务已更新';
    }
    return state.isHomeVisible(task.id) ? '已从首页隐藏' : '已显示到首页';
  }

  Future<void> _quickEditTask(AssistantTaskDefinition task) async {
    final edited = await showModalBottomSheet<AssistantTaskDefinition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          TaskEditorSheet(task: task, repository: _repository),
    );
    if (edited == null || !mounted) {
      return;
    }
    await _mutateState((state) {
      final nextTasks = state.taskDefinitions
          .map((item) => item.id == edited.id ? edited : item)
          .toList();
      return state.copyWith(
        taskDefinitions: nextTasks,
        enabledTaskIds: {...state.enabledTaskIds, edited.id},
      );
    }, message: '任务已保存');
  }

  Future<void> _pickTaskScriptBinding(AssistantTaskDefinition task) async {
    final latestConfigs = await _repository.loadGestureConfigs();
    if (!mounted) {
      return;
    }
    setState(() {
      _gestureConfigs = latestConfigs;
    });
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionSheetTile(
                icon: Icons.link_off_rounded,
                title: '清除脚本绑定',
                subtitle: '同时清除执行脚本和前置脚本',
                destructive: true,
                onTap: () => Navigator.of(context).pop('clear'),
              ),
              _ActionSheetTile(
                icon: Icons.flash_on_rounded,
                title: '更换执行脚本',
                subtitle: '设置打开应用后的主配置',
                onTap: () => Navigator.of(context).pop('main'),
              ),
              _ActionSheetTile(
                icon: Icons.first_page_rounded,
                title: '更换前置脚本',
                subtitle: '设置打开应用前先执行的配置',
                onTap: () => Navigator.of(context).pop('pre'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result == 'clear') {
      await _updateTaskDefinition(
        task.id,
        (item) => item.copyWith(clearGesture: true, clearPreGesture: true),
        message: '脚本绑定已清除',
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                _ActionSheetTile(
                  icon: Icons.block_rounded,
                  title: result == 'pre' ? '无前置脚本' : '无执行脚本',
                  subtitle: '清空当前绑定',
                  destructive: true,
                  onTap: () => Navigator.of(context).pop('none'),
                ),
                ..._gestureConfigs.map(
                  (config) => _ActionSheetTile(
                    icon: config.infiniteLoop
                        ? Icons.all_inclusive_rounded
                        : Icons.play_circle_outline_rounded,
                    title: config.name,
                    subtitle: config.infiniteLoop
                        ? '无限循环 · 间隔 ${config.loopIntervalMillis} 毫秒'
                        : '${config.loopCount} 次 · 间隔 ${config.loopIntervalMillis} 毫秒',
                    onTap: () => Navigator.of(context).pop(config.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    await _updateTaskDefinition(
      task.id,
      (item) => switch (result) {
        'pre' =>
          selected == 'none'
              ? item.copyWith(clearPreGesture: true)
              : item.copyWith(preGestureConfigId: selected),
        _ =>
          selected == 'none'
              ? item.copyWith(clearGesture: true)
              : item.copyWith(gestureConfigId: selected),
      },
      message: result == 'pre' ? '前置脚本已更新' : '执行脚本已更新',
    );
  }

  Widget _buildTaskQuickActions(AssistantTaskDefinition task, Color accent) {
    final state = _state;
    if (state == null) {
      return const SizedBox.shrink();
    }
    final homeVisible = state.isHomeVisible(task.id);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.1 : 0.07,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _TaskQuickActionChip(
            label: '重置',
            onTap: () => _resetTaskProgress(task),
            accent: accent,
          ),
          _TaskQuickActionChip(
            label: homeVisible ? '首页隐藏' : '首页显示',
            onTap: () => _toggleTaskHomeVisible(task),
            accent: accent,
          ),
          _TaskQuickActionChip(
            label: '换绑脚本',
            onTap: () => _pickTaskScriptBinding(task),
            accent: accent,
          ),
          _TaskQuickActionChip(
            label: '快捷编辑',
            onTap: () => _quickEditTask(task),
            accent: accent,
          ),
        ],
      ),
    );
  }

  List<Map<String, Object?>> _expandFiniteConfigActions(GestureConfig config) {
    final out = <Map<String, Object?>>[];
    final loops = config.loopCount.clamp(1, 9999);
    for (var i = 0; i < loops; i++) {
      out.addAll(config.actions.map((action) => action.toJson()));
      if (i < loops - 1 && config.loopIntervalMillis > 0) {
        out.add(
          WaitAction.fixedMilliseconds(
            milliseconds: config.loopIntervalMillis,
          ).toJson(),
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
  })?
  _resolveGestureExecutionPlan(
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

  Future<void> _openSelectedApp(
    AssistantTaskDefinition task, {
    Duration? autoCompleteAfter,
  }) async {
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

    if (autoCompleteAfter != null) {
      _scheduleAutoCompleteTask(
        task.id,
        DateTime.now().add(
          autoCompleteAfter <= Duration.zero
              ? Duration.zero
              : autoCompleteAfter,
        ),
      );
    } else if (task.autoCompleteDelayDuration > Duration.zero) {
      _scheduleAutoCompleteTask(
        task.id,
        DateTime.now().add(task.autoCompleteDelayDuration),
      );
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
      final dailyMottoEntries = await _repository.loadDailyMottoEntries();
      final pinnedDailyMottoId = await _repository.loadPinnedDailyMottoId();
      final dailyMottoImageUrl = await _repository.loadDailyMottoImageUrl();
      final dailyMottoImagePath = await _repository.loadDailyMottoImagePath();
      final showDailyMottoMetaOnHome = await _repository
          .loadShowDailyMottoMetaOnHome();
      final autoScrollDailyMottoOnHome = await _repository
          .loadAutoScrollDailyMottoOnHome();
      final autoScrollDailyMottoIntervalValue = await _repository
          .loadAutoScrollDailyMottoIntervalValue();
      final autoScrollDailyMottoIntervalUnit = await _repository
          .loadAutoScrollDailyMottoIntervalUnit();
      if (mounted) {
        setState(() {
          _gestureConfigs = configs;
          _dailyMottoEntries = dailyMottoEntries;
          _pinnedDailyMottoId = pinnedDailyMottoId;
          _dailyMottoImageUrl = dailyMottoImageUrl;
          _dailyMottoImagePath = dailyMottoImagePath;
          _showDailyMottoMetaOnHome = showDailyMottoMetaOnHome;
          _autoScrollDailyMottoOnHome = autoScrollDailyMottoOnHome;
          _autoScrollDailyMottoIntervalValue =
              autoScrollDailyMottoIntervalValue;
          _autoScrollDailyMottoIntervalUnit = autoScrollDailyMottoIntervalUnit;
        });
      }
      await _persistState(next, message: '设置已保存', type: ToastType.success);
    }
  }

  void _showMessage(String message, {ToastType type = ToastType.info}) {
    VibrantHUD.show(context, message, type: type);
  }

  String _todayKey(DateTime now) {
    return _dateKey(now);
  }

  DailyMottoEntry _dailyMottoEntry(DateTime now) {
    final pinnedId = _pinnedDailyMottoId;
    if (pinnedId != null && pinnedId.isNotEmpty) {
      final pinned = _dailyMottoEntries
          .where((item) => item.id == pinnedId)
          .firstOrNull;
      if (pinned != null) {
        return pinned;
      }
    }
    const fallbackMottos = [
      '天生我才必有用，千金散尽还复来',
      '长风破浪会有时，直挂云帆济沧海',
      '且将新火试新茶，诗酒趁年华',
      '莫道桑榆晚，为霞尚满天',
      '山高路远，亦要见自己',
      '日日自新，步步生光',
    ];
    final entries = _dailyMottoEntries.isEmpty
        ? fallbackMottos.map(DailyMottoEntry.fromLegacy).toList()
        : _dailyMottoEntries;
    final seed = now.year * 10000 + now.month * 100 + now.day;
    return entries[seed % entries.length];
  }

  String _dailyMottoAttribution(DailyMottoEntry entry) {
    if (!_showDailyMottoMetaOnHome) {
      return '';
    }
    return entry.attribution;
  }

  Duration _dailyMottoAutoSwitchDuration() {
    final value = _autoScrollDailyMottoIntervalValue.clamp(1, 999);
    return switch (_autoScrollDailyMottoIntervalUnit) {
      IntervalUnit.seconds => Duration(seconds: value),
      IntervalUnit.minutes => Duration(minutes: value),
      IntervalUnit.hours => Duration(hours: value),
      IntervalUnit.days => Duration(days: value),
    };
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

  String _describeConfig(String? id) {
    if (id == null || id.isEmpty) {
      return '未绑定';
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

  List<String> _configDetailsFor(AssistantTaskDefinition task) {
    return [
      '前置配置：${_describeConfig(task.preGestureConfigId)}',
      '执行配置：${_describeConfig(task.gestureConfigId)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final theme = Theme.of(context);

    if (_loading) {
      return const _HomeLoadingView();
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

    final headerMotto = _dailyMottoEntry(now);
    return Scaffold(
      body: _NeonPageBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    _HeaderCard(
                      title: headerMotto.content,
                      subtitle: nextReminder == null
                          ? '今天无后续提醒'
                          : '下一提醒 ${nextReminder.timeLabel} · ${nextReminder.label}',
                      summary: '总共 ${tasks.length} 项，完成 $doneCount 项',
                      attribution: _dailyMottoAttribution(headerMotto),
                      autoSwitch: _autoScrollDailyMottoOnHome,
                      autoSwitchInterval: _dailyMottoAutoSwitchDuration(),
                      imageProvider: _dailyMottoImagePath != null
                          ? FileImage(File(_dailyMottoImagePath!))
                          : (_dailyMottoImageUrl != null
                                ? NetworkImage(_dailyMottoImageUrl!)
                                : null),
                      actionRow: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HeaderIconAction(
                            icon: Icons.play_arrow_rounded,
                            onTap: _startAutomationMenu,
                            foreground: theme.brightness == Brightness.dark
                                ? const Color(0xFF8EF0FF)
                                : const Color(0xFF4B63D9),
                            background: theme.brightness == Brightness.dark
                                ? const Color(0xFF2A2F63)
                                : const Color(0xFFDCE3FF),
                          ),
                          const SizedBox(width: 6),
                          _HeaderIconAction(
                            icon: Icons.refresh_rounded,
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('重置今日记录'),
                                  content: const Text(
                                    '确定要重置今天所有的任务完成状态和倒计时吗？此操作不可撤销。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: FilledButton.styleFrom(
                                        foregroundColor:
                                            theme.colorScheme.error,
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
                            foreground: theme.brightness == Brightness.dark
                                ? const Color(0xFFFFC98A)
                                : const Color(0xFFB97738),
                            background: theme.brightness == Brightness.dark
                                ? const Color(0xFF2A2F63)
                                : const Color(0xFFDCE3FF),
                          ),
                          const SizedBox(width: 6),
                          _HeaderIconAction(
                            icon: Icons.settings,
                            onTap: _openSettings,
                            foreground: theme.brightness == Brightness.dark
                                ? const Color(0xFFE2A6FF)
                                : const Color(0xFF8A53D2),
                            background: theme.brightness == Brightness.dark
                                ? const Color(0xFF2A2F63)
                                : const Color(0xFFDCE3FF),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (tasks.isEmpty)
                      Expanded(
                        child: Card(
                          child: Center(
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
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Icon(
                                      Icons.inbox_rounded,
                                      size: 32,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '暂无首页任务',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '去设置页开启“首页显示”，常用任务就会出现在这里。',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                    ),
                                  ),
                                ],
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
                                      (task.gestureConfigId?.isNotEmpty ??
                                          false),
                                  appLabel: state.selectedAppLabel,
                                  configDetails: _configDetailsFor(task),
                                  onOpenApp: () => _openSelectedApp(task),
                                  taskActions: _buildTaskQuickActions(
                                    task,
                                    const Color(0xFF5EA98D),
                                  ),
                                );
                              case AssistantTaskKind.fixedPoint:
                                final isExpired = TaskEngine.isTaskExpired(
                                  now,
                                  task,
                                );
                                final isDue = TaskEngine.isFixedTaskDue(
                                  now,
                                  task,
                                );
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
                                      (task.gestureConfigId?.isNotEmpty ??
                                          false),
                                  appLabel: state.selectedAppLabel,
                                  configDetails: _configDetailsFor(task),
                                  onOpenApp: () => _openSelectedApp(task),
                                  taskActions: _buildTaskQuickActions(
                                    task,
                                    const Color(0xFF6B8FD6),
                                  ),
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
                                      (task.gestureConfigId?.isNotEmpty ??
                                          false),
                                  appLabel: state.selectedAppLabel,
                                  configDetails: _configDetailsFor(task),
                                  onOpenApp: () => _openSelectedApp(task),
                                  taskActions: _buildTaskQuickActions(
                                    task,
                                    const Color(0xFFDA8C63),
                                  ),
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
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _neonGlassFill(theme, alpha: 0.16),
            accent.withValues(alpha: 0.14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: _neonGlassGlow(accent, strength: 0.75),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  accent.withValues(alpha: 0.34),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white),
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
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  kindLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _neonGlassFill(theme, alpha: 0.15),
              accent.withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: _neonGlassGlow(accent, strength: 0.58),
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
                      color: Colors.white,
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
                                  ? accent.withValues(alpha: 0.16)
                                  : accent.withValues(alpha: 0.12))
                            : (theme.brightness == Brightness.dark
                                  ? const Color(0xFF252B61)
                                  : const Color(0xFFF1F4FF)),
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
                                  ? const Color(0xFF31397A)
                                  : const Color(0xFFE5EBFF))
                            : (theme.brightness == Brightness.dark
                                  ? const Color(0xFF252B61)
                                  : const Color(0xFFF1F4FF)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF8EA8FF)
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
                                        ? const Color(0xFF5B6EE1)
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
                              color: Color(0xFF5B6EE1),
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
