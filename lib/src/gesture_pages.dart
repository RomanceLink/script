import 'package:flutter/material.dart';

import 'models/task_models.dart';
import 'services/task_repository.dart';
import 'services/douyin_launcher.dart';

import 'services/alarm_bridge.dart';

class GestureConfigPage extends StatefulWidget {
  const GestureConfigPage({
    required this.repository,
    required this.launcher,
    this.autoCreateOnOpen = false,
    this.onConfigsChanged,
    super.key,
  });

  final TaskRepository repository;
  final DouyinLauncher launcher;
  final bool autoCreateOnOpen;
  final Future<void> Function(List<GestureConfig> configs)? onConfigsChanged;

  @override
  State<GestureConfigPage> createState() => _GestureConfigPageState();
}

class _GestureConfigPageState extends State<GestureConfigPage> {
  List<GestureConfig> _configs = [];
  GestureConfig? _unlockConfig;
  bool _loading = true;
  bool _handledAutoCreate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = await widget.repository.loadGestureConfigs();
    final unlockConfig = await widget.repository.loadUnlockGestureConfig();
    if (mounted) {
      setState(() {
        _configs = configs;
        _unlockConfig = unlockConfig;
        _loading = false;
      });
      if (widget.autoCreateOnOpen && !_handledAutoCreate) {
        _handledAutoCreate = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _addOrEdit();
          }
        });
      }
    }
  }

  Future<void> _recordUnlockConfig() async {
    if (_unlockConfig != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('已有锁屏脚本'),
          content: const Text('已经录制过锁屏解锁脚本，是否重新录制？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    final result = await AlarmBridge().enterPickerMode('unlockRecord');
    final actions = _unlockActionsFromResult(result);
    if (!mounted || actions.isEmpty) {
      return;
    }
    final config = GestureConfig(
      id: 'unlock_script',
      name: '锁屏解锁脚本',
      actions: actions,
    );
    await widget.repository.saveUnlockGestureConfig(config);
    if (!mounted) return;
    setState(() => _unlockConfig = config);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('锁屏解锁脚本已保存')));
  }

  Future<void> _verifyUnlockConfig() async {
    if (_unlockConfig == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先录制锁屏解锁脚本')));
      return;
    }
    final ok = await AlarmBridge().verifyUnlockScript();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已开始验证锁屏解锁脚本' : '验证失败，请检查无障碍服务')),
    );
  }

  List<GestureAction> _unlockActionsFromResult(Map<String, Object?>? result) {
    final rawSegments = (result?['segments'] as List<Object?>?) ?? const [];
    if (result == null || result['cancelled'] == true || rawSegments.isEmpty) {
      return const [];
    }
    return _UnlockActionBuilder.build(result);
  }

  Future<void> _addOrEdit([GestureConfig? config]) async {
    final result = await Navigator.of(context).push<GestureConfig>(
      MaterialPageRoute(
        builder: (_) =>
            GestureEditPage(config: config, launcher: widget.launcher),
      ),
    );

    if (result != null) {
      final next = List<GestureConfig>.from(_configs);
      final index = next.indexWhere((c) => c.id == result.id);
      if (index >= 0) {
        next[index] = result;
      } else {
        next.add(result);
      }
      setState(() => _configs = next);
      await widget.repository.saveGestureConfigs(next);
      await widget.onConfigsChanged?.call(next);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除配置'),
        content: const Text('确定要删除这个自动化方案吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final next = _configs.where((c) => c.id != id).toList();
      setState(() => _configs = next);
      await widget.repository.saveGestureConfigs(next);
      await widget.onConfigsChanged?.call(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动化配置中心')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: _ConfigBottomAction(
                icon: Icons.lock_open_rounded,
                label: _unlockConfig == null ? '锁屏录制' : '重录锁屏',
                onPressed: _recordUnlockConfig,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ConfigBottomAction(
                icon: Icons.verified_user_outlined,
                label: '验证锁屏',
                onPressed: _unlockConfig == null ? null : _verifyUnlockConfig,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ConfigBottomAction(
                icon: Icons.add_rounded,
                label: '新建方案',
                onPressed: () => _addOrEdit(),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
          ? const Center(
              child: Text('尚未创建任何配置', style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _configs.length,
              itemBuilder: (context, index) {
                final config = _configs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    title: Text(
                      config.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${config.actions.length} 个动作 · ${config.loopCount} 次 · 间隔 ${config.loopIntervalMillis} 毫秒 · 约 ${estimateGestureConfigDuration(config).label}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _addOrEdit(config),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => _delete(config.id),
                        ),
                      ],
                    ),
                    onTap: () => _addOrEdit(config),
                  ),
                );
              },
            ),
    );
  }
}

class _ConfigBottomAction extends StatelessWidget {
  const _ConfigBottomAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class GestureEditPage extends StatefulWidget {
  const GestureEditPage({this.config, required this.launcher, super.key});

  final GestureConfig? config;
  final DouyinLauncher launcher;

  @override
  State<GestureEditPage> createState() => _GestureEditPageState();
}

class _GestureEditPageState extends State<GestureEditPage> {
  static const _defaultGestureBeforeWaitMillis = 300;
  static const _defaultGestureAfterWaitMillis = 800;

  late TextEditingController _nameController;
  late TextEditingController _loopCountController;
  late TextEditingController _loopIntervalController;
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
    if (widget.config != null) {
      _actions.addAll(widget.config!.actions);
    }
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

  void _addAction(GestureAction action) {
    setState(() => _actions.add(action));
  }

  void _addGestureActionsWithBuffers(List<GestureAction> actions) {
    if (actions.isEmpty) return;
    setState(() {
      for (final action in actions) {
        _actions.add(
          WaitAction.fixedMilliseconds(
            milliseconds: _defaultGestureBeforeWaitMillis,
          ),
        );
        _actions.add(action);
        _actions.add(
          WaitAction.fixedMilliseconds(
            milliseconds: _defaultGestureAfterWaitMillis,
          ),
        );
      }
    });
  }

  Future<void> _waitForOverlayDismissal() {
    return Future<void>.delayed(const Duration(milliseconds: 280));
  }

  void _showAddMenu() {
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
                color: Colors.blue,
              ),
              ListTile(
                leading: const Icon(
                  Icons.touch_app_rounded,
                  color: Colors.blue,
                ),
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
                color: Colors.indigo,
              ),
              ListTile(
                leading: const Icon(
                  Icons.select_all_rounded,
                  color: Colors.indigo,
                ),
                title: const Text('按钮识别'),
                subtitle: const Text('识别屏幕按钮，成功后点击或执行自定义动作'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickButtonRecognizeAction();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.image_search_rounded,
                  color: Colors.teal,
                ),
                title: const Text('图片按钮识别'),
                subtitle: const Text('截图 OCR 识别图片按钮上的文字'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickButtonRecognizeAction(
                    source: ButtonRecognizeSource.imageText,
                  );
                },
              ),
              _ActionCategoryHeader(
                title: '等待',
                icon: Icons.timer_rounded,
                color: Colors.orange,
              ),
              ListTile(
                leading: const Icon(Icons.timer_rounded, color: Colors.orange),
                title: const Text('随机等待'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickRandomWaitAction();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.more_time_rounded,
                  color: Colors.deepOrange,
                ),
                title: const Text('毫秒等待'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickMillisecondWaitAction();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.hourglass_bottom_rounded,
                  color: Colors.brown,
                ),
                title: const Text('固定等待'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickFixedWaitAction();
                },
              ),
              _ActionCategoryHeader(
                title: '系统',
                icon: Icons.settings_suggest_rounded,
                color: Colors.green,
              ),
              ListTile(
                leading: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.green,
                ),
                title: const Text('导航动作'),
                subtitle: const Text('返回、首页、多任务'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickNavAction();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('锁屏'),
                onTap: () {
                  Navigator.of(context).pop();
                  _addAction(const LockScreenAction());
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.purple,
                ),
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

  List<ClickAction> _clickActionsFromSteps(Map<String, Object?>? result) {
    if (result == null || result['cancelled'] == true) {
      return const [];
    }
    final rawPoints = (result['points'] as List<Object?>?) ?? const [];
    final actions = rawPoints
        .whereType<Map<Object?, Object?>>()
        .map(
          (point) => ClickAction(
            x1: (point['x'] as num).toDouble(),
            y1: (point['y'] as num).toDouble(),
          ),
        )
        .toList();
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
        source == ButtonRecognizeSource.imageText
            ? 'imageButtonDetect'
            : 'buttonDetect',
      );
    }
    if (!mounted || result == null || result['cancelled'] == true) {
      return;
    }

    final bounds = (result['bounds'] as Map<Object?, Object?>?)?.map(
      (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
    );
    final textController = TextEditingController(
      text: result['buttonText'] as String? ?? '',
    );
    final idController = TextEditingController(
      text: result['buttonId'] as String? ?? '',
    );
    final descriptionController = TextEditingController(
      text: result['buttonDescription'] as String? ?? '',
    );
    final retryCountController = TextEditingController(
      text: '${result['retryCount'] ?? 3}',
    );
    final retryWaitController = TextEditingController(
      text: '${result['retryWaitMillis'] ?? 800}',
    );
    var matchMode = ButtonMatchMode.values.byName(
      result['matchMode'] as String? ?? ButtonMatchMode.exact.name,
    );
    var regionMode = ButtonRegionMode.values.byName(
      result['regionMode'] as String? ?? ButtonRegionMode.custom.name,
    );
    var successMode = ButtonResultActionMode.defaultClick;
    var retrySuccessMode = ButtonResultActionMode.defaultClick;
    var failAction = ButtonFailAction.notify;
    var successActions = <GestureAction>[];
    var retryActions = <GestureAction>[];
    var retrySuccessActions = <GestureAction>[];

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
                                  source == ButtonRecognizeSource.imageText
                                      ? Icons.image_search_rounded
                                      : Icons.select_all_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  source == ButtonRecognizeSource.imageText
                                      ? '图片文字 OCR'
                                      : '无障碍按钮',
                                ),
                              ),
                            ),
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
                              onRecord: () async {
                                final actions =
                                    await _pickNestedGestureActions();
                                if (!context.mounted || actions.isEmpty) return;
                                setDialogState(() {
                                  successMode = ButtonResultActionMode.custom;
                                  successActions = actions;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _InlineActionPicker(
                              title: '识别失败后的动作',
                              mode: ButtonResultActionMode.custom,
                              actions: retryActions,
                              canChangeMode: false,
                              onModeChanged: (_) {},
                              onRecord: () async {
                                final actions =
                                    await _pickNestedGestureActions();
                                if (!context.mounted || actions.isEmpty) return;
                                setDialogState(() => retryActions = actions);
                              },
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
                              onRecord: () async {
                                final actions =
                                    await _pickNestedGestureActions();
                                if (!context.mounted || actions.isEmpty) return;
                                setDialogState(() {
                                  retrySuccessMode =
                                      ButtonResultActionMode.custom;
                                  retrySuccessActions = actions;
                                });
                              },
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

    textController.dispose();
    idController.dispose();
    descriptionController.dispose();
    retryCountController.dispose();
    retryWaitController.dispose();

    if (!mounted || action == null) {
      return;
    }
    if (editIndex != null) {
      setState(() => _actions[editIndex] = action);
    } else {
      _addAction(action);
    }
  }

  Future<List<GestureAction>> _pickNestedGestureActions() async {
    final type = await showModalBottomSheet<String>(
      context: context,
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
    );
    Navigator.of(context).pop(config);
  }

  Future<void> _editName() async {
    var nameDraft = _nameController.text.trim();
    var loopCountDraft = _loopCountController.text.trim();
    var loopIntervalDraft = _loopIntervalController.text.trim();
    final next =
        await showDialog<
          ({String name, String loopCount, String loopInterval})
        >(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('方案设置'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: nameDraft,
                      autofocus: true,
                      onChanged: (value) => nameDraft = value,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '例如：刷抖音专用',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: loopCountDraft,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => loopCountDraft = value,
                      decoration: const InputDecoration(
                        labelText: '循环次数',
                        helperText: '最少 1 次',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: loopIntervalDraft,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => loopIntervalDraft = value,
                      decoration: const InputDecoration(
                        labelText: '循环间隔毫秒',
                        helperText: '每轮之间等待',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop((
                  name: nameDraft.trim(),
                  loopCount: loopCountDraft.trim(),
                  loopInterval: loopIntervalDraft.trim(),
                )),
                child: const Text('保存'),
              ),
            ],
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
    final previewConfig = GestureConfig(
      id: '_preview',
      name: '',
      actions: _actions,
      loopCount: _loopCount,
      loopIntervalMillis: _loopIntervalMillis,
    );
    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '方案名称',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _nameController.text.trim().isEmpty
                        ? '未命名方案'
                        : _nameController.text.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '循环 $_loopCount 次 · 间隔 $_loopIntervalMillis 毫秒',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _editName,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('编辑'),
            ),
          ],
        ),
      ),
    ];
    if (_nameController.text.trim().isEmpty) {
      header.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '保存前请先设置方案名称',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
      );
    }
    header.addAll([
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '预计执行时长：${estimateGestureConfigDuration(previewConfig).label}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Divider(),
    ]);
    final footer = Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _showAddMenu,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加内容'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                child: FilledButton(onPressed: _save, child: const Text('保存')),
              ),
            ],
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config == null ? '新建配置' : '编辑配置'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 430;
          final actionList = _actions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '点击下方按钮添加第一个动作',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: compact,
                  physics: compact
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _actions.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _actions.removeAt(oldIndex);
                      _actions.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final action = _actions[index];
                    return ListTile(
                      key: ValueKey('${action.type}_$index'),
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(_actionLabel(action)),
                      subtitle: Text(_actionSubtitle(action)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle_rounded),
                          ),
                          if (_isPositionEditable(action))
                            IconButton(
                              icon: const Icon(Icons.edit_location_alt),
                              onPressed: () => _editAction(index),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              color: Colors.redAccent,
                            ),
                            onPressed: () =>
                                setState(() => _actions.removeAt(index)),
                          ),
                        ],
                      ),
                    );
                  },
                );
          if (compact) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [...header, actionList, footer],
            );
          }
          return Column(
            children: [
              ...header,
              Expanded(child: actionList),
              footer,
            ],
          );
        },
      ),
    );
  }

  String _actionLabel(GestureAction action) {
    if (action is WaitAction) {
      if (action.isRandom) return '随机等待';
      return action.usesMilliseconds ? '毫秒等待' : '固定等待';
    }
    return switch (action.type) {
      GestureActionType.swipe => '滑动手势',
      GestureActionType.click => '点击手势',
      GestureActionType.recorded => '录制轨迹',
      GestureActionType.nav => '导航动作',
      GestureActionType.wait => '等待',
      GestureActionType.launchApp => '启动应用',
      GestureActionType.buttonRecognize => '按钮识别',
      GestureActionType.lockScreen => '锁屏',
    };
  }

  String _actionSubtitle(GestureAction action) {
    if (action is SwipeAction) {
      return '从 (${action.x1}, ${action.y1}) 划至 (${action.x2}, ${action.y2})';
    }
    if (action is ClickAction) {
      return '坐标 (${action.x1}, ${action.y1})';
    }
    if (action is RecordedGestureAction) {
      final seconds = (action.duration / 1000).toStringAsFixed(1);
      return '${action.segments.length} 段轨迹，约 $seconds 秒';
    }
    if (action is NavAction) {
      return switch (action.navType) {
        NavType.back => '模拟返回键',
        NavType.home => '模拟首页键',
        NavType.recents => '模拟多任务键',
      };
    }
    if (action is WaitAction) {
      if (action.isRandom) {
        return '${_formatWaitDuration(action.effectiveMinMilliseconds)}-${_formatWaitDuration(action.effectiveMaxMilliseconds)} 内随机';
      }
      return '固定等待 ${_formatWaitDuration(action.milliseconds)}';
    }
    if (action is LaunchAppAction) {
      return '拉起 ${action.label}';
    }
    if (action is ButtonRecognizeAction) {
      final mode = action.matchMode == ButtonMatchMode.exact ? '完全相同' : '包含';
      final source = action.source == ButtonRecognizeSource.imageText
          ? '图片文字'
          : '无障碍';
      final retry = action.retryCount > 0 ? '，失败重试 ${action.retryCount} 次' : '';
      return '$source · 文字“${action.buttonText}” · $mode$retry';
    }
    if (action is LockScreenAction) {
      return '执行到这里时锁定屏幕';
    }
    return '';
  }

  String _formatWaitDuration(int milliseconds) {
    if (milliseconds < 1000) return '$milliseconds 毫秒';
    if (milliseconds < 60000) {
      if (milliseconds % 1000 == 0) return '${milliseconds ~/ 1000} 秒';
      return '${(milliseconds / 1000).toStringAsFixed(1)} 秒';
    }
    final seconds = (milliseconds / 1000).ceil();
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '$minutes 分钟' : '$minutes 分 $rest 秒';
  }
}

class _ActionCategoryHeader extends StatelessWidget {
  const _ActionCategoryHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Expanded(child: Divider(indent: 12)),
        ],
      ),
    );
  }
}

class _UnlockActionBuilder {
  static List<GestureAction> build(Map<String, Object?> result) {
    final rawSegments = (result['segments'] as List<Object?>?) ?? const [];
    final segments =
        rawSegments
            .whereType<Map<Object?, Object?>>()
            .map(GestureSegment.fromJson)
            .where((segment) => segment.points.isNotEmpty)
            .toList()
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
        final duration = (end - start).clamp(50, 10000000);
        actions.add(
          RecordedGestureAction(
            duration: duration,
            segments: [
              GestureSegment(
                start: 0,
                duration: duration,
                points: segment.points
                    .map(
                      (point) => GesturePoint(
                        x: point.x.clamp(0.0, 1.0),
                        y: point.y.clamp(0.0, 1.0),
                        t: (point.t - start).clamp(0, 10000000),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      }
      previousEnd = end;
    }
    return actions;
  }

  static int _segmentStart(GestureSegment segment) {
    var start = segment.start;
    for (final point in segment.points) {
      if (point.t < start || start == 0) {
        start = point.t;
      }
    }
    return start.clamp(0, 10000000);
  }

  static int _segmentEnd(GestureSegment segment, int start) {
    var end = start + segment.duration;
    for (final point in segment.points) {
      if (point.t > end) {
        end = point.t;
      }
    }
    return end.clamp(start, 10000000);
  }

  static bool _isTapSegment(GestureSegment segment) {
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
}

class _ChoiceOption<T> {
  const _ChoiceOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

class _ChoiceField<T> extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String title;
  final T value;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final option in options)
                  ListTile(
                    leading: Icon(option.icon),
                    title: Text(option.label),
                    trailing: option.value == value
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        child: Row(
          children: [
            Icon(selected.icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(selected.label)),
          ],
        ),
      ),
    );
  }
}

class _InlineActionPicker extends StatelessWidget {
  const _InlineActionPicker({
    required this.title,
    required this.mode,
    required this.actions,
    required this.onModeChanged,
    required this.onRecord,
    this.canChangeMode = true,
  });

  final String title;
  final ButtonResultActionMode mode;
  final List<GestureAction> actions;
  final ValueChanged<ButtonResultActionMode> onModeChanged;
  final VoidCallback onRecord;
  final bool canChangeMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (canChangeMode)
            _ChoiceField<ButtonResultActionMode>(
              label: '动作方式',
              title: '选择动作方式',
              value: mode,
              options: const [
                _ChoiceOption(
                  value: ButtonResultActionMode.defaultClick,
                  label: '默认点击',
                  icon: Icons.touch_app_rounded,
                ),
                _ChoiceOption(
                  value: ButtonResultActionMode.custom,
                  label: '自定义录制动作',
                  icon: Icons.fiber_manual_record_rounded,
                ),
              ],
              onChanged: onModeChanged,
            )
          else
            const InputDecorator(
              decoration: InputDecoration(labelText: '动作方式'),
              child: Row(
                children: [
                  Icon(Icons.fiber_manual_record_rounded, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('自定义录制动作')),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRecord,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            label: Text(
              actions.isEmpty ? '录制自定义动作' : '已录制 ${actions.length} 个动作',
            ),
          ),
        ],
      ),
    );
  }
}
