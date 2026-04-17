import 'package:flutter/material.dart';

import 'models/task_models.dart';
import 'services/task_repository.dart';
import 'services/douyin_launcher.dart';

import 'services/alarm_bridge.dart';

class GestureConfigPage extends StatefulWidget {
  const GestureConfigPage({
    required this.repository,
    required this.launcher,
    super.key,
  });

  final TaskRepository repository;
  final DouyinLauncher launcher;

  @override
  State<GestureConfigPage> createState() => _GestureConfigPageState();
}

class _GestureConfigPageState extends State<GestureConfigPage> {
  List<GestureConfig> _configs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = await widget.repository.loadGestureConfigs();
    if (mounted) {
      setState(() {
        _configs = configs;
        _loading = false;
      });
    }
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动化配置中心')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建方案'),
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
                      '${config.actions.length} 个动作 · 约 ${estimateGestureActionsDuration(config.actions).label}',
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
  final List<GestureAction> _actions = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.config?.name ?? '');
    if (widget.config != null) {
      _actions.addAll(widget.config!.actions);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

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

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.touch_app_rounded, color: Colors.blue),
              title: const Text('录制手势 (点击/滑动)'),
              onTap: () {
                Navigator.of(context).pop();
                _pickGestureType();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.navigation_rounded,
                color: Colors.green,
              ),
              title: const Text('导航动作 (返回/首页/多任务)'),
              onTap: () {
                Navigator.of(context).pop();
                _pickNavAction();
              },
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
              final result = await AlarmBridge().enterPickerMode('record');
              final action = _recordedActionFromResult(result);
              if (action != null) {
                _addGestureActionsWithBuffers([action]);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.pin_drop_outlined),
            title: const Text('录制点击步骤'),
            subtitle: const Text('点击屏幕生成编号圆点，保存后每个点都是独立步骤'),
            onTap: () async {
              Navigator.of(context).pop();
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
    );
    Navigator.of(context).pop(config);
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
    }
  }

  bool _isPositionEditable(GestureAction action) {
    return action is ClickAction ||
        action is SwipeAction ||
        action is WaitAction;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config == null ? '新建配置' : '编辑配置'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '方案名称',
                hintText: '例如：刷抖音专用',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '预计执行时长：${estimateGestureActionsDuration(_actions).label}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          Expanded(
            child: _actions.isEmpty
                ? const Center(
                    child: Text(
                      '点击下方按钮添加第一个动作',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
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
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
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
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
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
