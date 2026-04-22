part of '../gesture_pages.dart';

class GestureEditPage extends StatefulWidget {
  const GestureEditPage({
    this.config,
    required this.launcher,
    required this.repository,
    super.key,
  });

  final GestureConfig? config;
  final DouyinLauncher launcher;
  final TaskRepository repository;

  @override
  State<GestureEditPage> createState() => _GestureEditPageState();
}

class _GestureEditPageState extends State<GestureEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _loopCountController;
  late TextEditingController _loopIntervalController;
  bool _infiniteLoop = false;
  String? _followUpConfigId;
  List<GestureConfig> _availableConfigs = const [];
  final List<GestureAction> _actions = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.config?.name ?? '');
    _loopCountController = TextEditingController(
      text: '${widget.config?.loopCount ?? 1}',
    );
    _loopIntervalController = TextEditingController(
      text: '${widget.config?.loopIntervalMillis ?? 0}',
    );
    _infiniteLoop = widget.config?.infiniteLoop ?? false;
    _followUpConfigId = widget.config?.followUpConfigId;
    if (widget.config != null) {
      _actions.addAll(widget.config!.actions);
    }
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await widget.repository.loadGestureConfigs();
    if (!mounted) return;
    setState(() {
      _availableConfigs = configs;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _loopCountController.dispose();
    _loopIntervalController.dispose();
    super.dispose();
  }

  int get _loopCount =>
      (int.tryParse(_loopCountController.text.trim()) ?? 1).clamp(1, 9999);

  int get _loopIntervalMillis =>
      (int.tryParse(_loopIntervalController.text.trim()) ?? 0).clamp(
        0,
        10000000,
      );

  double _actionListHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final desired = (_actions.length * 84.0).clamp(180.0, screenHeight * 0.46);
    return desired.toDouble();
  }

  Future<void> _pickFollowUpConfig() async {
    final currentId = widget.config?.id;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('无追加配置'),
              onTap: () => Navigator.of(context).pop('none'),
            ),
            if (_availableConfigs.isNotEmpty) const Divider(),
            ..._availableConfigs
                .where((item) => item.id != currentId)
                .map(
                  (item) => ListTile(
                    title: Text(item.name),
                    onTap: () => Navigator.of(context).pop(item.id),
                  ),
                ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _followUpConfigId = result == 'none' ? null : result;
      });
    }
  }

  void _addAction(GestureAction action) {
    setState(() => _actions.add(action));
  }

  void _addGestureActionsWithBuffers(List<GestureAction> actions) {
    if (actions.isEmpty) return;
    setState(() {
      _actions.addAll(actions);
    });
  }

  Future<void> _waitForOverlayDismissal() {
    return Future<void>.delayed(const Duration(milliseconds: 280));
  }

  void _showAddMenu() {
    final theme = Theme.of(context);
    final gestureColor = theme.brightness == Brightness.dark
        ? const Color(0xFF94DFC9)
        : const Color(0xFF2F7D6B);
    final logicColor = theme.brightness == Brightness.dark
        ? const Color(0xFFA7C5FF)
        : const Color(0xFF456DAA);
    final waitColor = theme.brightness == Brightness.dark
        ? const Color(0xFFFFCF8D)
        : const Color(0xFFB06C22);
    final systemColor = theme.brightness == Brightness.dark
        ? const Color(0xFFD8B4FE)
        : const Color(0xFF7E22CE);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              _ActionCategoryHeader(
                title: '手势',
                icon: Icons.gesture_rounded,
                color: gestureColor,
              ),
              ListTile(
                leading: Icon(Icons.touch_app_rounded, color: gestureColor),
                title: const Text('录制手势'),
                subtitle: const Text('点击、滑动、完整轨迹'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _waitForOverlayDismissal();
                  if (!mounted) return;
                  _pickGestureType();
                },
              ),
              _ActionCategoryHeader(
                title: '逻辑',
                icon: Icons.account_tree_rounded,
                color: logicColor,
              ),
              ListTile(
                leading: Icon(Icons.select_all_rounded, color: logicColor),
                title: const Text('按钮识别'),
                subtitle: const Text('用无障碍识别按钮文字、ID、描述'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickButtonRecognizeAction();
                },
              ),
              ListTile(
                leading: Icon(Icons.image_search_rounded, color: logicColor),
                title: const Text('图片识别'),
                subtitle: const Text('圈住一块图片，后续在屏幕中查找匹配'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickButtonRecognizeAction(
                    source: ButtonRecognizeSource.imageTemplate,
                  );
                },
              ),
              _ActionCategoryHeader(
                title: '等待',
                icon: Icons.timer_rounded,
                color: waitColor,
              ),
              ListTile(
                leading: Icon(Icons.timer_rounded, color: waitColor),
                title: const Text('随机等待'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickRandomWaitAction();
                },
              ),
              ListTile(
                leading: Icon(Icons.more_time_rounded, color: waitColor),
                title: const Text('毫秒等待'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickMillisecondWaitAction();
                },
              ),
              ListTile(
                leading: Icon(Icons.hourglass_bottom_rounded, color: waitColor),
                title: const Text('固定等待'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickFixedWaitAction();
                },
              ),
              _ActionCategoryHeader(
                title: '系统',
                icon: Icons.settings_suggest_rounded,
                color: systemColor,
              ),
              ListTile(
                leading: Icon(Icons.navigation_rounded, color: systemColor),
                title: const Text('导航动作'),
                subtitle: const Text('返回、首页、多任务'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickNavAction();
                },
              ),
              ListTile(
                leading: Icon(Icons.lock_outline_rounded, color: systemColor),
                title: const Text('锁屏'),
                onTap: () {
                  Navigator.of(context).pop();
                  _addAction(const LockScreenAction());
                },
              ),
              ListTile(
                leading: Icon(Icons.rocket_launch_rounded, color: systemColor),
                title: const Text('启动应用'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAppAction();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickGestureType() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.fiber_manual_record_rounded),
            title: const Text('录制完整手势轨迹'),
            subtitle: const Text('像录音一样计时，结束后保存点击、滑动和轨迹'),
            onTap: () async {
              Navigator.of(context).pop();
              await _waitForOverlayDismissal();
              if (!mounted) return;
              final result = await AlarmBridge().enterPickerMode('record');
              final actions = _actionsFromRecordedResult(result);
              if (actions.isNotEmpty) {
                _addGestureActionsWithBuffers(actions);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.pin_drop_outlined),
            title: const Text('录制点击步骤'),
            subtitle: const Text('点击屏幕生成编号圆点，保存后每个点都是独立步骤'),
            onTap: () async {
              Navigator.of(context).pop();
              await _waitForOverlayDismissal();
              if (!mounted) return;
              final result = await AlarmBridge().enterPickerMode('clickSteps');
              final actions = _clickActionsFromSteps(result);
              if (actions.isNotEmpty) {
                _addGestureActionsWithBuffers(actions);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: const Text('手动标点：单次点击'),
            subtitle: const Text('拖动标记到目标位置后保存'),
            onTap: () async {
              Navigator.of(context).pop();
              await _waitForOverlayDismissal();
              if (!mounted) return;
              final result = await AlarmBridge().enterPickerMode('click');
              if (result != null && result['cancelled'] != true) {
                _addGestureActionsWithBuffers([
                  ClickAction(
                    x1: (result['x1'] as num).toDouble(),
                    y1: (result['y1'] as num).toDouble(),
                  ),
                ]);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.swipe_outlined),
            title: const Text('手动标点：直线滑动'),
            subtitle: const Text('拖动起点和终点后保存'),
            onTap: () async {
              Navigator.of(context).pop();
              await _waitForOverlayDismissal();
              if (!mounted) return;
              final result = await AlarmBridge().enterPickerMode('swipe');
              if (result != null && result['cancelled'] != true) {
                _addGestureActionsWithBuffers([
                  SwipeAction(
                    x1: (result['x1'] as num).toDouble(),
                    y1: (result['y1'] as num).toDouble(),
                    x2: (result['x2'] as num).toDouble(),
                    y2: (result['y2'] as num).toDouble(),
                  ),
                ]);
              }
            },
          ),
        ],
      ),
    );
  }

  List<GestureAction> _clickActionsFromSteps(Map<String, Object?>? result) {
    if (result == null || result['cancelled'] == true) {
      return const [];
    }
    final rawPoints = (result['points'] as List<Object?>?) ?? const [];
    final points = rawPoints.whereType<Map<Object?, Object?>>().toList()
      ..sort(
        (a, b) => ((a['t'] as num?)?.toInt() ?? 0).compareTo(
          (b['t'] as num?)?.toInt() ?? 0,
        ),
      );
    final actions = <GestureAction>[];
    var previousTime = 0;
    for (final point in points) {
      final time = ((point['t'] as num?)?.toInt() ?? previousTime).clamp(
        0,
        10000000,
      );
      final waitMillis = (time - previousTime).clamp(0, 10000000);
      if (waitMillis > 0) {
        actions.add(WaitAction.fixedMilliseconds(milliseconds: waitMillis));
      }
      actions.add(
        ClickAction(
          x1: (point['x'] as num).toDouble(),
          y1: (point['y'] as num).toDouble(),
        ),
      );
      previousTime = time;
    }
    if (actions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有录制到点击步骤')));
    }
    return actions;
  }

  RecordedGestureAction? _recordedActionFromResult(
    Map<String, Object?>? result,
  ) {
    if (result == null || result['cancelled'] == true) {
      return null;
    }
    final rawSegments = (result['segments'] as List<Object?>?) ?? const [];
    final segments = rawSegments
        .whereType<Map<Object?, Object?>>()
        .map(GestureSegment.fromJson)
        .where((segment) => segment.points.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有录制到有效手势')));
      return null;
    }
    return RecordedGestureAction(
      duration: (result['duration'] as num?)?.toInt() ?? 0,
      segments: segments,
    );
  }

  List<GestureAction> _actionsFromRecordedResult(Map<String, Object?>? result) {
    final recorded = _recordedActionFromResult(result);
    if (recorded == null) {
      return const [];
    }
    final segments = [...recorded.segments]
      ..sort((a, b) => _segmentStart(a).compareTo(_segmentStart(b)));
    final actions = <GestureAction>[];
    var previousEnd = 0;
    for (final segment in segments) {
      final start = _segmentStart(segment);
      final end = _segmentEnd(segment, start);
      final waitMillis = (start - previousEnd).clamp(0, 10000000);
      if (waitMillis > 0) {
        actions.add(WaitAction.fixedMilliseconds(milliseconds: waitMillis));
      }
      if (_isTapSegment(segment)) {
        final point = segment.points.first;
        actions.add(ClickAction(x1: point.x, y1: point.y));
      } else {
        final normalizedPoints = segment.points
            .map(
              (point) => GesturePoint(
                x: point.x.clamp(0.0, 1.0),
                y: point.y.clamp(0.0, 1.0),
                t: (point.t - start).clamp(0, 10000000),
              ),
            )
            .toList();
        final duration = (end - start).clamp(50, 10000000);
        actions.add(
          RecordedGestureAction(
            duration: duration,
            segments: [
              GestureSegment(
                start: 0,
                duration: duration,
                points: normalizedPoints,
              ),
            ],
          ),
        );
      }
      previousEnd = end;
    }
    return actions;
  }

  int _segmentStart(GestureSegment segment) {
    var start = segment.start;
    for (final point in segment.points) {
      if (point.t < start || start == 0) {
        start = point.t;
      }
    }
    return start.clamp(0, 10000000);
  }

  int _segmentEnd(GestureSegment segment, int start) {
    var end = start + segment.duration;
    for (final point in segment.points) {
      if (point.t > end) {
        end = point.t;
      }
    }
    return end.clamp(start, 10000000);
  }

  bool _isTapSegment(GestureSegment segment) {
    if (segment.points.length <= 1) {
      return true;
    }
    final first = segment.points.first;
    final last = segment.points.last;
    var maxDistanceSquared = 0.0;
    for (final point in segment.points) {
      final dx = point.x - first.x;
      final dy = point.y - first.y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared > maxDistanceSquared) {
        maxDistanceSquared = distanceSquared;
      }
    }
    return maxDistanceSquared <= 0.0004 && (last.t - first.t) <= 220;
  }

  void _pickNavAction() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('返回键'),
            onTap: () {
              Navigator.of(context).pop();
              _addAction(const NavAction(navType: NavType.back));
            },
          ),
          ListTile(
            title: const Text('回到桌面'),
            onTap: () {
              Navigator.of(context).pop();
              _addAction(const NavAction(navType: NavType.home));
            },
          ),
          ListTile(
            title: const Text('多任务界面'),
            onTap: () {
              Navigator.of(context).pop();
              _addAction(const NavAction(navType: NavType.recents));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickRandomWaitAction() async {
    var minText = '30';
    var maxText = '120';
    final action = await showDialog<WaitAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置随机等待范围'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: minText,
              onChanged: (value) => minText = value,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '最小秒数',
                hintText: '例如 30',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: maxText,
              onChanged: (value) => maxText = value,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '最大秒数',
                hintText: '例如 120',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final min = int.tryParse(minText.trim()) ?? 30;
              final max = int.tryParse(maxText.trim()) ?? 120;
              Navigator.of(
                context,
              ).pop(WaitAction.random(minSeconds: min, maxSeconds: max));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    _addAction(action);
  }

  Future<void> _pickFixedWaitAction() async {
    var secondsText = '5';
    final action = await showDialog<WaitAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置固定等待'),
        content: TextFormField(
          initialValue: secondsText,
          onChanged: (value) => secondsText = value,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '等待秒数',
            helperText: '最多 10000 秒',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final seconds = int.tryParse(secondsText.trim()) ?? 5;
              Navigator.of(context).pop(WaitAction.fixed(seconds: seconds));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    _addAction(action);
  }

  Future<void> _pickMillisecondWaitAction() async {
    var millisText = '800';
    final action = await showDialog<WaitAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置毫秒等待'),
        content: TextFormField(
          initialValue: millisText,
          onChanged: (value) => millisText = value,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '等待毫秒',
            hintText: '例如 300 或 800',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final milliseconds = int.tryParse(millisText.trim()) ?? 800;
              Navigator.of(
                context,
              ).pop(WaitAction.fixedMilliseconds(milliseconds: milliseconds));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    _addAction(action);
  }

  Future<void> _pickAppAction() async {
    final apps = await widget.launcher.listLaunchableApps();
    if (!mounted) return;

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

    if (selected != null) {
      _addAction(
        LaunchAppAction(
          packageName: selected.packageName,
          label: selected.appName,
        ),
      );
    }
  }

  Future<void> _pickButtonRecognizeAction({
    ButtonRecognizeSource source = ButtonRecognizeSource.accessibility,
    Map<String, Object?>? initialResult,
    int? editIndex,
  }) async {
    Map<String, Object?>? result = initialResult;
    if (result == null) {
      await _waitForOverlayDismissal();
      if (!mounted) return;
      result = await AlarmBridge().enterPickerMode(
        source == ButtonRecognizeSource.imageText ||
                source == ButtonRecognizeSource.imageTemplate
            ? 'imageButtonDetect'
            : 'buttonDetect',
      );
    }
    if (!mounted || result == null || result['cancelled'] == true) {
      return;
    }
    final pickerResult = result;

    final bounds = (pickerResult['bounds'] as Map<Object?, Object?>?)?.map(
      (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
    );
    final textController = TextEditingController(
      text: pickerResult['buttonText'] as String? ?? '',
    );
    final idController = TextEditingController(
      text: pickerResult['buttonId'] as String? ?? '',
    );
    final descriptionController = TextEditingController(
      text: pickerResult['buttonDescription'] as String? ?? '',
    );
    final retryCountController = TextEditingController(
      text: '${pickerResult['retryCount'] ?? 3}',
    );
    final retryWaitController = TextEditingController(
      text: '${pickerResult['retryWaitMillis'] ?? 800}',
    );
    var matchMode = ButtonMatchMode.values.byName(
      pickerResult['matchMode'] as String? ?? ButtonMatchMode.exact.name,
    );
    var regionMode = ButtonRegionMode.values.byName(
      pickerResult['regionMode'] as String? ?? ButtonRegionMode.custom.name,
    );
    var successMode = ButtonResultActionMode.defaultClick;
    var retrySuccessMode = ButtonResultActionMode.defaultClick;
    var failAction = ButtonFailAction.notify;
    var successActions = <GestureAction>[];
    var retryActions = <GestureAction>[];
    var retrySuccessActions = <GestureAction>[];
    var pickingCustomAction = false;

    Future<void> pickCustomActions(
      BuildContext dialogContext,
      ValueChanged<List<GestureAction>> onPicked,
      StateSetter setDialogState,
    ) async {
      if (pickingCustomAction) return;
      setDialogState(() => pickingCustomAction = true);
      final actions = await _pickNestedGestureActions(dialogContext);
      if (!dialogContext.mounted) return;
      setDialogState(() => pickingCustomAction = false);
      if (actions.isEmpty) return;
      onPicked(actions);
    }

    final action = await showDialog<ButtonRecognizeAction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('识别按钮', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                avatar: Icon(
                                  source == ButtonRecognizeSource.imageText ||
                                          source ==
                                              ButtonRecognizeSource
                                                  .imageTemplate
                                      ? Icons.image_search_rounded
                                      : Icons.select_all_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  source == ButtonRecognizeSource.imageText
                                      ? '图片文字 OCR'
                                      : source ==
                                            ButtonRecognizeSource.imageTemplate
                                      ? '图片识别'
                                      : '无障碍按钮',
                                ),
                              ),
                            ),
                            if (source ==
                                ButtonRecognizeSource.imageTemplate) ...[
                              const SizedBox(height: 12),
                              _ImageTemplatePreview(
                                templateBase64:
                                    pickerResult['templateImage'] as String? ??
                                    '',
                                width:
                                    (pickerResult['templateWidth'] as num?)
                                        ?.toInt() ??
                                    0,
                                height:
                                    (pickerResult['templateHeight'] as num?)
                                        ?.toInt() ??
                                    0,
                                region: bounds,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _ChoiceField<ButtonMatchMode>(
                              label: '识别方式',
                              title: '选择识别方式',
                              value: matchMode,
                              options: const [
                                _ChoiceOption(
                                  value: ButtonMatchMode.exact,
                                  label: '完全相同',
                                  icon: Icons.drag_handle_rounded,
                                ),
                                _ChoiceOption(
                                  value: ButtonMatchMode.contains,
                                  label: '包含文字',
                                  icon: Icons.subject_rounded,
                                ),
                              ],
                              onChanged: (value) =>
                                  setDialogState(() => matchMode = value),
                            ),
                            const SizedBox(height: 12),
                            _ChoiceField<ButtonRegionMode>(
                              label: '识别区域',
                              title: '选择识别区域',
                              value: regionMode,
                              options: const [
                                _ChoiceOption(
                                  value: ButtonRegionMode.full,
                                  label: '全屏',
                                  icon: Icons.fullscreen_rounded,
                                ),
                                _ChoiceOption(
                                  value: ButtonRegionMode.custom,
                                  label: '自定义：使用当前按钮区域',
                                  icon: Icons.crop_free_rounded,
                                ),
                              ],
                              onChanged: (value) =>
                                  setDialogState(() => regionMode = value),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: textController,
                              decoration: const InputDecoration(
                                labelText: '按钮文字',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: idController,
                              decoration: const InputDecoration(
                                labelText: '按钮ID',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: descriptionController,
                              decoration: const InputDecoration(
                                labelText: '按钮描述',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _InlineActionPicker(
                              title: '识别成功后的动作',
                              mode: successMode,
                              actions: successActions,
                              onModeChanged: (value) =>
                                  setDialogState(() => successMode = value),
                              isBusy: pickingCustomAction,
                              onRecord: () => pickCustomActions(
                                context,
                                (actions) => setDialogState(() {
                                  successMode = ButtonResultActionMode.custom;
                                  successActions = actions;
                                }),
                                setDialogState,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _InlineActionPicker(
                              title: '识别失败后的动作',
                              mode: ButtonResultActionMode.custom,
                              actions: retryActions,
                              canChangeMode: false,
                              onModeChanged: (_) {},
                              isBusy: pickingCustomAction,
                              onRecord: () => pickCustomActions(
                                context,
                                (actions) => setDialogState(
                                  () => retryActions = actions,
                                ),
                                setDialogState,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: retryCountController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '重试次数',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: retryWaitController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '等待毫秒',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _InlineActionPicker(
                              title: '重试成功后执行',
                              mode: retrySuccessMode,
                              actions: retrySuccessActions,
                              onModeChanged: (value) => setDialogState(
                                () => retrySuccessMode = value,
                              ),
                              isBusy: pickingCustomAction,
                              onRecord: () => pickCustomActions(
                                context,
                                (actions) => setDialogState(() {
                                  retrySuccessMode =
                                      ButtonResultActionMode.custom;
                                  retrySuccessActions = actions;
                                }),
                                setDialogState,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ChoiceField<ButtonFailAction>(
                              label: '重试失败后',
                              title: '选择失败处理',
                              value: failAction,
                              options: const [
                                _ChoiceOption(
                                  value: ButtonFailAction.notify,
                                  label: '全屏通知脚本执行失败',
                                  icon: Icons.notification_important_rounded,
                                ),
                                _ChoiceOption(
                                  value: ButtonFailAction.lockScreen,
                                  label: '锁屏',
                                  icon: Icons.lock_rounded,
                                ),
                                _ChoiceOption(
                                  value: ButtonFailAction.none,
                                  label: '不处理',
                                  icon: Icons.block_rounded,
                                ),
                              ],
                              onChanged: (value) =>
                                  setDialogState(() => failAction = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(
                              ButtonRecognizeAction(
                                buttonText: textController.text.trim(),
                                source: source,
                                matchMode: matchMode,
                                regionMode: regionMode,
                                region: regionMode == ButtonRegionMode.custom
                                    ? bounds
                                    : null,
                                templateImage:
                                    pickerResult['templateImage'] as String? ??
                                    '',
                                templateWidth:
                                    (pickerResult['templateWidth'] as num?)
                                        ?.toInt() ??
                                    0,
                                templateHeight:
                                    (pickerResult['templateHeight'] as num?)
                                        ?.toInt() ??
                                    0,
                                buttonId: idController.text.trim(),
                                buttonDescription: descriptionController.text
                                    .trim(),
                                successMode: successMode,
                                successActions: successActions,
                                retryActions: retryActions,
                                retryCount:
                                    int.tryParse(
                                      retryCountController.text.trim(),
                                    ) ??
                                    3,
                                retryWaitMillis:
                                    int.tryParse(
                                      retryWaitController.text.trim(),
                                    ) ??
                                    800,
                                retrySuccessMode: retrySuccessMode,
                                retrySuccessActions: retrySuccessActions,
                                failAction: failAction,
                              ),
                            );
                          },
                          child: const Text('添加'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || action == null) {
      return;
    }
    if (editIndex != null) {
      setState(() => _actions[editIndex] = action);
    } else {
      _addAction(action);
    }
  }

  Future<List<GestureAction>> _pickNestedGestureActions([
    BuildContext? pickerContext,
  ]) async {
    final type = await showModalBottomSheet<String>(
      context: pickerContext ?? context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fiber_manual_record_rounded),
              title: const Text('录制完整手势轨迹'),
              onTap: () => Navigator.of(context).pop('record'),
            ),
            ListTile(
              leading: const Icon(Icons.pin_drop_outlined),
              title: const Text('录制点击步骤'),
              onTap: () => Navigator.of(context).pop('clickSteps'),
            ),
            ListTile(
              leading: const Icon(Icons.touch_app_outlined),
              title: const Text('手动标点：单次点击'),
              onTap: () => Navigator.of(context).pop('click'),
            ),
            ListTile(
              leading: const Icon(Icons.swipe_outlined),
              title: const Text('手动标点：直线滑动'),
              onTap: () => Navigator.of(context).pop('swipe'),
            ),
          ],
        ),
      ),
    );
    if (type == null) return const [];

    await _waitForOverlayDismissal();
    if (!mounted) return const [];
    final result = await AlarmBridge().enterPickerMode(type);
    if (result == null || result['cancelled'] == true) return const [];
    if (type == 'record') {
      return _actionsFromRecordedResult(result);
    }
    if (type == 'clickSteps') {
      return _clickActionsFromSteps(result);
    }
    if (type == 'click') {
      return [
        ClickAction(
          x1: (result['x1'] as num).toDouble(),
          y1: (result['y1'] as num).toDouble(),
        ),
      ];
    }
    return [
      SwipeAction(
        x1: (result['x1'] as num).toDouble(),
        y1: (result['y1'] as num).toDouble(),
        x2: (result['x2'] as num).toDouble(),
        y2: (result['y2'] as num).toDouble(),
      ),
    ];
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入方案名称')));
      return;
    }
    final config = GestureConfig(
      id:
          widget.config?.id ??
          'gesture_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      actions: _actions,
      loopCount: _loopCount,
      loopIntervalMillis: _loopIntervalMillis,
      followUpConfigId: _followUpConfigId,
      infiniteLoop: _infiniteLoop,
    );
    Navigator.of(context).pop(config);
  }

  Future<void> _editName() async {
    final next =
        await showDialog<
          ({
            String name,
            String loopCount,
            String loopInterval,
            bool infiniteLoop,
          })
        >(
          context: context,
          builder: (context) => _SchemeSettingsDialog(
            name: _nameController.text.trim(),
            loopCount: _loopCountController.text.trim(),
            loopInterval: _loopIntervalController.text.trim(),
            infiniteLoop: _infiniteLoop,
          ),
        );
    if (!mounted || next == null) {
      return;
    }
    setState(() {
      _nameController.text = next.name;
      _loopCountController.text =
          '${(int.tryParse(next.loopCount) ?? 1).clamp(1, 9999)}';
      _loopIntervalController.text =
          '${(int.tryParse(next.loopInterval) ?? 0).clamp(0, 10000000)}';
      _infiniteLoop = next.infiniteLoop;
    });
  }

  Future<void> _editAction(int index) async {
    final action = _actions[index];
    if (action is ClickAction) {
      final result = await AlarmBridge().enterPickerMode('click');
      if (result == null || result['cancelled'] == true) {
        return;
      }
      setState(() {
        _actions[index] = ClickAction(
          x1: (result['x1'] as num).toDouble(),
          y1: (result['y1'] as num).toDouble(),
          duration: action.duration,
        );
      });
      return;
    }
    if (action is SwipeAction) {
      final result = await AlarmBridge().enterPickerMode('swipe');
      if (result == null || result['cancelled'] == true) {
        return;
      }
      setState(() {
        _actions[index] = SwipeAction(
          x1: (result['x1'] as num).toDouble(),
          y1: (result['y1'] as num).toDouble(),
          x2: (result['x2'] as num).toDouble(),
          y2: (result['y2'] as num).toDouble(),
          duration: action.duration,
        );
      });
      return;
    }
    if (action is WaitAction) {
      await _editWaitAction(index, action);
      return;
    }
    if (action is ButtonRecognizeAction) {
      await _pickButtonRecognizeAction(
        source: action.source,
        initialResult: action.toJson(),
        editIndex: index,
      );
    }
  }

  bool _isPositionEditable(GestureAction action) {
    return action is ClickAction ||
        action is SwipeAction ||
        action is WaitAction ||
        action is ButtonRecognizeAction;
  }

  Future<void> _editWaitAction(int index, WaitAction action) async {
    if (action.isRandom) {
      var minText = action.effectiveMinSeconds.toString();
      var maxText = action.effectiveMaxSeconds.toString();
      final next = await showDialog<WaitAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('编辑随机等待'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: minText,
                onChanged: (value) => minText = value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '最小秒数'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: maxText,
                onChanged: (value) => maxText = value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '最大秒数'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final min = int.tryParse(minText.trim()) ?? 30;
                final max = int.tryParse(maxText.trim()) ?? 120;
                Navigator.of(
                  context,
                ).pop(WaitAction.random(minSeconds: min, maxSeconds: max));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (next != null && mounted) {
        setState(() => _actions[index] = next);
      }
      return;
    }

    var millisText = action.milliseconds.toString();
    final next = await showDialog<WaitAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑等待'),
        content: TextFormField(
          initialValue: millisText,
          onChanged: (value) => millisText = value,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '等待毫秒'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final milliseconds = int.tryParse(millisText.trim()) ?? 800;
              Navigator.of(
                context,
              ).pop(WaitAction.fixedMilliseconds(milliseconds: milliseconds));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (next != null && mounted) {
      setState(() => _actions[index] = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final previewConfig = GestureConfig(
      id: '_preview',
      name: '',
      actions: _actions,
      loopCount: _loopCount,
      loopIntervalMillis: _loopIntervalMillis,
      infiniteLoop: _infiniteLoop,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: _automationHeaderColor(theme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.config == null ? '新建自动化配置' : '编辑自动化配置',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4A9D8F),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: _automationPageBackground(theme),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _ModernSectionCard(
                    accent: const Color(0xFF4A9D8F),
                    title: '方案信息',
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
                                    _nameController.text.trim().isEmpty
                                        ? '未命名方案'
                                        : _nameController.text.trim(),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _infiniteLoop
                                        ? '无限循环 · 间隔 $_loopIntervalMillis 毫秒'
                                        : '循环 $_loopCount 次 · 间隔 $_loopIntervalMillis 毫秒',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: _editName,
                              icon: const Icon(
                                Icons.settings_suggest_rounded,
                                size: 20,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF4A9D8F,
                                ).withValues(alpha: 0.1),
                                foregroundColor: const Color(0xFF4A9D8F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(
                                    0xFF163130,
                                  ).withValues(alpha: 0.88)
                                : Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 14,
                                color: Color(0xFF4A9D8F),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _infiniteLoop
                                    ? '预计耗时：持续执行'
                                    : '预计耗时：${estimateGestureConfigDuration(previewConfig).label}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CompactSelectionTile(
                          label: '追加配置',
                          value:
                              _availableConfigs
                                  .where((item) => item.id == _followUpConfigId)
                                  .firstOrNull
                                  ?.name ??
                              '无',
                          onTap: _pickFollowUpConfig,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ModernSectionCard(
                    accent: const Color(0xFF82A7F7),
                    title: '动作步骤 (可拖动排序)',
                    child: _actions.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.ads_click_rounded,
                                    size: 40,
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '暂无动作，点击下方按钮添加',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SizedBox(
                            height: _actionListHeight(context),
                            child: ReorderableListView.builder(
                              buildDefaultDragHandles: false,
                              physics: const ClampingScrollPhysics(),
                              itemCount: _actions.length,
                              proxyDecorator: (child, index, animation) {
                                return AnimatedBuilder(
                                  animation: animation,
                                  builder: (context, _) {
                                    final elevation = Tween<double>(
                                      begin: 0,
                                      end: 10,
                                    ).evaluate(animation);
                                    return Material(
                                      elevation: elevation,
                                      shadowColor: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      clipBehavior: Clip.antiAlias,
                                      child: child,
                                    );
                                  },
                                );
                              },
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (oldIndex < newIndex) newIndex -= 1;
                                  final item = _actions.removeAt(oldIndex);
                                  _actions.insert(newIndex, item);
                                });
                              },
                              itemBuilder: (context, index) {
                                final action = _actions[index];
                                return _ModernActionTile(
                                  key: ValueKey('${action.runtimeType}-$index'),
                                  index: index,
                                  action: action,
                                  onDelete: () =>
                                      setState(() => _actions.removeAt(index)),
                                  onEdit: _isPositionEditable(action)
                                      ? () => _editAction(index)
                                      : null,
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.paddingOf(context).bottom + 12,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.74 : 0.88,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.05,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _showAddMenu,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text(
                        '添加动作步骤',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A9D8F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(
                        0xFF4A9D8F,
                      ).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFF4A9D8F),
                      padding: const EdgeInsets.all(14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

