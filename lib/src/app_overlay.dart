part of 'app.dart';

class FloatingAutomationOverlayApp extends StatefulWidget {
  const FloatingAutomationOverlayApp({super.key});

  @override
  State<FloatingAutomationOverlayApp> createState() =>
      _FloatingAutomationOverlayAppState();
}

class _FloatingAutomationOverlayAppState
    extends State<FloatingAutomationOverlayApp> {
  static const _channel = MethodChannel('scriptapp/alarm');
  Brightness? _brightness;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'setOverlayTheme') {
      final dark =
          (call.arguments as Map<Object?, Object?>?)?['dark'] as bool? ?? false;
      if (mounted) {
        setState(() => _brightness = dark ? Brightness.dark : Brightness.light);
      }
      return null;
    }
    return _FloatingAutomationOverlayShellState.handleNativeCall(call);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _brightness ?? MediaQuery.platformBrightnessOf(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _scriptAssistantTheme(brightness),
      home: const _FloatingAutomationOverlayShell(initialMode: 'configs'),
    );
  }
}

class _FloatingAutomationOverlayShell extends StatefulWidget {
  const _FloatingAutomationOverlayShell({required this.initialMode});

  final String initialMode;

  @override
  State<_FloatingAutomationOverlayShell> createState() =>
      _FloatingAutomationOverlayShellState();
}

class _FloatingAutomationOverlayShellState
    extends State<_FloatingAutomationOverlayShell> {
  static _FloatingAutomationOverlayShellState? _instance;
  final TaskRepository _repository = TaskRepository();
  final DouyinLauncher _launcher = DouyinLauncher();
  final AlarmBridge _alarmBridge = AlarmBridge();
  late String _mode;
  int _overlayRevision = 0;

  @override
  void initState() {
    super.initState();
    _instance = this;
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    if (_instance == this) {
      _instance = null;
    }
    super.dispose();
  }

  static Future<dynamic> handleNativeCall(MethodCall call) async {
    final state = _instance;
    if (state == null || !state.mounted || call.method != 'setOverlayMode') {
      return null;
    }
    final mode =
        (call.arguments as Map<Object?, Object?>?)?['mode'] as String? ??
        state.widget.initialMode;
    state.setState(() {
      state._mode = mode;
      state._overlayRevision += 1;
    });
    return null;
  }

  Future<void> _syncConfigs(List<GestureConfig> configs) {
    return _alarmBridge.syncAutomationConfigs(
      configs: configs.map((config) => config.toJson()).toList(),
    );
  }

  Future<void> _runConfig(GestureConfig config) async {
    ({
      String name,
      List<Map<String, Object?>> beforeLoopActions,
      List<Map<String, Object?>> loopActions,
      int loopCount,
      int loopIntervalMillis,
      bool infiniteLoop,
    })?
    resolvePlan(
      GestureConfig? item,
      List<GestureConfig> all, {
      Set<String>? visited,
    }) {
      if (item == null) {
        return null;
      }
      final nextVisited = {...?visited};
      if (!nextVisited.add(item.id)) {
        return (
          name: item.name,
          beforeLoopActions: item.actions
              .map((action) => action.toJson())
              .toList(),
          loopActions: const [],
          loopCount: 1,
          loopIntervalMillis: 0,
          infiniteLoop: false,
        );
      }
      List<Map<String, Object?>> finiteActions(GestureConfig config) {
        final out = <Map<String, Object?>>[];
        for (var i = 0; i < config.loopCount.clamp(1, 9999); i++) {
          out.addAll(config.actions.map((action) => action.toJson()));
          if (i < config.loopCount - 1 && config.loopIntervalMillis > 0) {
            out.add(
              WaitAction.fixedMilliseconds(
                milliseconds: config.loopIntervalMillis,
              ).toJson(),
            );
          }
        }
        return out;
      }

      if (item.infiniteLoop) {
        return (
          name: item.name,
          beforeLoopActions: const [],
          loopActions: item.actions.map((action) => action.toJson()).toList(),
          loopCount: item.loopCount,
          loopIntervalMillis: item.loopIntervalMillis,
          infiniteLoop: true,
        );
      }
      final child = all
          .where((entry) => entry.id == item.followUpConfigId)
          .firstOrNull;
      final childPlan = resolvePlan(child, all, visited: nextVisited);
      final current = finiteActions(item);
      if (childPlan == null) {
        return (
          name: item.name,
          beforeLoopActions: current,
          loopActions: const [],
          loopCount: 1,
          loopIntervalMillis: 0,
          infiniteLoop: false,
        );
      }
      return (
        name: '${item.name} -> ${childPlan.name}',
        beforeLoopActions: [...current, ...childPlan.beforeLoopActions],
        loopActions: childPlan.loopActions,
        loopCount: childPlan.loopCount,
        loopIntervalMillis: childPlan.loopIntervalMillis,
        infiniteLoop: childPlan.infiniteLoop,
      );
    }

    final configs = await _repository.loadGestureConfigs();
    final selected =
        configs.where((entry) => entry.id == config.id).firstOrNull ?? config;
    final plan = resolvePlan(selected, configs);
    await _repository.saveLastGestureConfigId(config.id);
    await _alarmBridge.runGestureConfig(
      name: plan?.name ?? config.name,
      beforeLoopActions: plan?.beforeLoopActions ?? const [],
      actions:
          plan?.loopActions ??
          config.actions.map((action) => action.toJson()).toList(),
      loopCount: plan == null
          ? config.loopCount
          : (plan.infiniteLoop ? plan.loopCount : 1),
      loopIntervalMillis: plan == null
          ? config.loopIntervalMillis
          : (plan.infiniteLoop ? plan.loopIntervalMillis : 0),
      infiniteLoop: plan?.infiniteLoop ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _mode == 'run'
        ? _GestureRunChooserPage(
            repository: _repository,
            onRunConfig: _runConfig,
            alarmBridge: _alarmBridge,
          )
        : GestureConfigPage(
            repository: _repository,
            launcher: _launcher,
            autoCreateOnOpen: _mode == 'create',
            onConfigsChanged: _syncConfigs,
            onRunConfig: _runConfig,
            onClose: _alarmBridge.closeAutomationOverlay,
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final maxHeight = constraints.maxHeight;
            if (maxWidth <= 0 || maxHeight <= 0) {
              return const SizedBox.shrink();
            }
            final isRunMode = _mode == 'run';
            final width = isRunMode
                ? (maxWidth < 420 ? maxWidth - 40 : 360.0).clamp(0.0, maxWidth)
                : (maxWidth < 548
                      ? (maxWidth - 24).clamp(0.0, maxWidth)
                      : 520.0.clamp(0.0, maxWidth));
            final height = isRunMode
                ? (maxHeight < 560 ? maxHeight : 520.0).clamp(0.0, maxHeight)
                : (maxHeight < 408
                      ? maxHeight
                      : (maxHeight - 48).clamp(360.0, maxHeight));
            return Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF232756)
                              : const Color(0xFFF1F4FF),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF72DFFF,
                              ).withValues(alpha: 0.14),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Navigator(
                          key: ValueKey('$_mode-$_overlayRevision'),
                          onGenerateRoute: (_) =>
                              MaterialPageRoute<void>(builder: (_) => content),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GestureRunChooserPage extends StatefulWidget {
  const _GestureRunChooserPage({
    required this.repository,
    required this.onRunConfig,
    required this.alarmBridge,
  });

  final TaskRepository repository;
  final Future<void> Function(GestureConfig config) onRunConfig;
  final AlarmBridge alarmBridge;

  @override
  State<_GestureRunChooserPage> createState() => _GestureRunChooserPageState();
}

class _GestureRunChooserPageState extends State<_GestureRunChooserPage> {
  List<GestureConfig> _configs = [];
  GestureConfig? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = await widget.repository.loadGestureConfigs();
    final lastId = await widget.repository.loadLastGestureConfigId();
    if (!mounted) return;
    final selected = configs.where((config) => config.id == lastId).firstOrNull;
    setState(() {
      _configs = configs;
      _selected = selected ?? (configs.isNotEmpty ? configs.last : null);
      _loading = false;
    });
  }

  Future<void> _run(GestureConfig config) async {
    await widget.onRunConfig(config);
  }

  Future<void> _switchConfig() async {
    final selected = await showModalBottomSheet<GestureConfig>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '选择自动化配置',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _configs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final config = _configs[index];
                  final isSelected = config.id == _selected?.id;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      config.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                    subtitle: Text(
                      '${config.actions.length}步骤 · ${estimateGestureConfigDuration(config).label}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => Navigator.of(context).pop(config),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selected = selected);
    await widget.repository.saveLastGestureConfigId(selected.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget buildCloseAction() {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: widget.alarmBridge.closeAutomationOverlay,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text(
                '关闭',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.78,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF232756)
          : const Color(0xFFF1F4FF),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const Center(
                  child: Text('尚未创建任何配置', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '先去配置页新建一个方案，再回来执行。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                buildCloseAction(),
              ],
            )
          : Center(
              // 整体居中
              child: SingleChildScrollView(
                // 滚动保护
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // 紧凑排列
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '准备执行自动化',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _liquidGlassFill(
                              theme,
                              theme.colorScheme.primary,
                              strength: 0.92,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: _liquidGlassBorder(
                                theme,
                                theme.colorScheme.primary,
                              ),
                              width: 2.0,
                            ),
                            boxShadow: _liquidGlassShadow(
                              theme,
                              theme.colorScheme.primary,
                              strength: 0.65,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.bolt_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        _selected?.name ?? '未选择',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.8,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: _liquidGlassFill(
                                      theme,
                                      theme.colorScheme.primary,
                                      strength: 0.45,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: _liquidGlassBorder(
                                        theme,
                                        theme.colorScheme.primary,
                                        strength: 0.45,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      _InfoRow(
                                        icon: Icons.ads_click_rounded,
                                        label: '动作步骤',
                                        value:
                                            '${_selected?.actions.length ?? 0} 个步骤',
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Divider(
                                          height: 1,
                                          thickness: 1.0,
                                        ),
                                      ),
                                      _InfoRow(
                                        icon: Icons.loop_rounded,
                                        label: '执行轮次',
                                        value:
                                            '${_selected?.loopCount ?? 0} 次循环',
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Divider(
                                          height: 1,
                                          thickness: 1.0,
                                        ),
                                      ),
                                      _InfoRow(
                                        icon: Icons.timer_outlined,
                                        label: '预估耗时',
                                        value: _selected == null
                                            ? '-'
                                            : estimateGestureConfigDuration(
                                                _selected!,
                                              ).label,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          backgroundColor: const Color(
                                            0xFF7F8CFF,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          elevation: 2,
                                          shadowColor: const Color(
                                            0xFF7F8CFF,
                                          ).withValues(alpha: 0.3),
                                        ),
                                        onPressed: _selected == null
                                            ? null
                                            : () => _run(_selected!),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 28,
                                        ),
                                        label: const Text(
                                          '开始自动化',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton.filledTonal(
                                      style: IconButton.styleFrom(
                                        padding: const EdgeInsets.all(16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                      ),
                                      tooltip: '切换配置',
                                      onPressed: _switchConfig,
                                      icon: const Icon(
                                        Icons.swap_horiz_rounded,
                                        size: 28,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildCloseAction(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
