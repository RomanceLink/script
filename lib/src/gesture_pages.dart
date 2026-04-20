import 'dart:convert';
import 'dart:typed_data';

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
    this.onRunConfig,
    this.onClose,
    super.key,
  });

  final TaskRepository repository;
  final DouyinLauncher launcher;
  final bool autoCreateOnOpen;
  final Future<void> Function(List<GestureConfig> configs)? onConfigsChanged;
  final Future<void> Function(GestureConfig config)? onRunConfig;
  final VoidCallback? onClose;

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

  Future<void> _showUnlockMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_open_rounded),
              title: Text(_unlockConfig == null ? '录制锁屏解锁' : '重新录制锁屏解锁'),
              onTap: () {
                Navigator.of(context).pop();
                _recordUnlockConfig();
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('验证锁屏解锁'),
              enabled: _unlockConfig != null,
              onTap: () {
                Navigator.of(context).pop();
                _verifyUnlockConfig();
              },
            ),
            if (_unlockConfig != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('删除锁屏脚本'),
                textColor: Colors.redAccent,
                iconColor: Colors.redAccent,
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.repository.saveUnlockGestureConfig(null);
                  if (!mounted) return;
                  setState(() => _unlockConfig = null);
                },
              ),
          ],
        ),
      ),
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

  Future<void> _showConfigActions(GestureConfig config) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text('删除'),
              textColor: Colors.redAccent,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      _addOrEdit(config);
    } else if (action == 'delete') {
      _delete(config.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          '自动化配置中心',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '锁屏脚本',
            onPressed: _showUnlockMenu,
            icon: Icon(
              _unlockConfig == null
                  ? Icons.lock_open_rounded
                  : Icons.lock_rounded,
              color: _unlockConfig == null ? null : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.paddingOf(context).bottom + 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _addOrEdit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建自动化配置', style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            if (widget.onClose != null) ...[
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_motion_rounded, size: 64, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text('尚未创建任何配置', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _configs.length,
              itemBuilder: (context, index) {
                final config = _configs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: widget.onRunConfig == null
                        ? () => _addOrEdit(config)
                        : () => widget.onRunConfig!(config),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF1E2628)
                            : const Color(0xFFF1F6F4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.gesture_rounded,
                              color: theme.colorScheme.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  config.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${config.actions.length}步骤 · ${config.loopCount}次循环 · 约${estimateGestureConfigDuration(config).label}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              IconButton(
                                tooltip: '执行',
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                onPressed: widget.onRunConfig == null
                                    ? null
                                    : () => widget.onRunConfig!(config),
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                                onPressed: () => _showConfigActions(config),
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
  }
}

class _SchemeSettingsDialog extends StatefulWidget {
  const _SchemeSettingsDialog({
    required this.name,
    required this.loopCount,
    required this.loopInterval,
  });

  final String name;
  final String loopCount;
  final String loopInterval;

  @override
  State<_SchemeSettingsDialog> createState() => _SchemeSettingsDialogState();
}

class _SchemeSettingsDialogState extends State<_SchemeSettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _loopCountController;
  late final TextEditingController _loopIntervalController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _loopCountController = TextEditingController(text: widget.loopCount);
    _loopIntervalController = TextEditingController(text: widget.loopInterval);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _loopCountController.dispose();
    _loopIntervalController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      loopCount: _loopCountController.text.trim(),
      loopInterval: _loopIntervalController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight =
        MediaQuery.sizeOf(context).height -
        viewInsets.bottom -
        MediaQuery.paddingOf(context).vertical -
        32;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight.clamp(260.0, 520.0)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '方案设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _compactField(
                  controller: _nameController,
                  label: '名称',
                  hint: '例如：刷抖音专用',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _compactField(
                        controller: _loopCountController,
                        label: '循环次数',
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _compactField(
                        controller: _loopIntervalController,
                        label: '间隔毫秒',
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
    );
    Navigator.of(context).pop(config);
  }

  Future<void> _editName() async {
    final next =
        await showDialog<
          ({String name, String loopCount, String loopInterval})
        >(
          context: context,
          builder: (context) => _SchemeSettingsDialog(
            name: _nameController.text.trim(),
            loopCount: _loopCountController.text.trim(),
            loopInterval: _loopIntervalController.text.trim(),
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
    final theme = Theme.of(context);
    final previewConfig = GestureConfig(
      id: '_preview',
      name: '',
      actions: _actions,
      loopCount: _loopCount,
      loopIntervalMillis: _loopIntervalMillis,
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.config == null ? '新建配置' : '编辑配置'),
        actions: [
          TextButton(
            onPressed: _save,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ModernSectionCard(
                  accent: const Color(0xFF76C7AE),
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
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '循环 $_loopCount 次 · 间隔 $_loopIntervalMillis 毫秒',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: _editName,
                            icon: const Icon(Icons.settings_suggest_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '预计耗时：${estimateGestureConfigDuration(previewConfig).label}',
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
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
                                Icon(Icons.ads_click_rounded,
                                    size: 40, color: theme.colorScheme.outlineVariant),
                                const SizedBox(height: 8),
                                const Text('暂无动作，点击下方按钮添加',
                                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _actions.length,
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
                              onDelete: () => setState(() => _actions.removeAt(index)),
                              onEdit: _isPositionEditable(action) ? () => _editAction(index) : null,
                            );
                          },
                        ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.paddingOf(context).bottom + 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showAddMenu,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('添加动作', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

class _ModernSectionCard extends StatelessWidget {
  const _ModernSectionCard({
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
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E2628)
            : const Color(0xFFF1F6F4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ModernActionTile extends StatelessWidget {
  const _ModernActionTile({
    super.key,
    required this.index,
    required this.action,
    required this.onDelete,
    this.onEdit,
  });

  final int index;
  final GestureAction action;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _getActionVisuals(theme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          title: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _getActionTitle(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            _getActionSummary(),
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                onPressed: onDelete,
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator_rounded, color: Colors.grey),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _getActionVisuals(ThemeData theme) {
    if (action is ClickAction) return (Icons.touch_app_rounded, const Color(0xFF76C7AE));
    if (action is SwipeAction) return (Icons.swipe_rounded, const Color(0xFF82A7F7));
    if (action is WaitAction) return (Icons.timer_rounded, const Color(0xFFFFB17E));
    if (action is NavAction) return (Icons.navigation_rounded, const Color(0xFFD69AF1));
    if (action is LaunchAppAction) return (Icons.rocket_launch_rounded, const Color(0xFF8EB8FF));
    if (action is LockScreenAction) return (Icons.lock_outline_rounded, const Color(0xFFD69AF1));
    if (action is ButtonRecognizeAction) return (Icons.center_focus_strong_rounded, const Color(0xFF82A7F7));
    if (action is RecordedGestureAction) return (Icons.gesture_rounded, const Color(0xFF76C7AE));
    return (Icons.extension_rounded, Colors.grey);
  }

  String _getActionTitle() {
    if (action is ClickAction) return '点击屏幕';
    if (action is SwipeAction) return '滑动屏幕';
    if (action is WaitAction) return '等待延迟';
    if (action is NavAction) return '系统导航';
    if (action is LaunchAppAction) return '启动应用';
    if (action is LockScreenAction) return '锁定屏幕';
    if (action is ButtonRecognizeAction) {
      final a = action as ButtonRecognizeAction;
      return a.source == ButtonRecognizeSource.imageTemplate ? '识别图片' : '识别按钮';
    }
    if (action is RecordedGestureAction) return '轨迹动作';
    return '未知动作';
  }

  String _getActionSummary() {
    if (action is ClickAction) {
      final a = action as ClickAction;
      return '坐标: (${(a.x1 * 100).toInt()}%, ${(a.y1 * 100).toInt()}%)';
    }
    if (action is SwipeAction) {
      final a = action as SwipeAction;
      return '从(${(a.x1 * 100).toInt()}%, ${(a.y1 * 100).toInt()}%)到(${(a.x2 * 100).toInt()}%, ${(a.y2 * 100).toInt()}%)';
    }
    if (action is WaitAction) {
      final a = action as WaitAction;
      return a.isRandom ? '随机: ${a.effectiveMinSeconds}-${a.effectiveMaxSeconds}秒' : '时长: ${a.milliseconds}ms';
    }
    if (action is NavAction) {
      final a = action as NavAction;
      return switch (a.navType) {
        NavType.back => '返回上一级',
        NavType.home => '返回桌面',
        NavType.recents => '打开最近任务',
      };
    }
    if (action is LaunchAppAction) {
      return '启动 ${(action as LaunchAppAction).label}';
    }
    if (action is ButtonRecognizeAction) {
      final a = action as ButtonRecognizeAction;
      return '文字: "${a.buttonText}"${a.retryCount > 0 ? " · 失败重试 ${a.retryCount} 次" : ""}';
    }
    return '手势自动化操作步骤';
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
    this.isBusy = false,
    this.canChangeMode = true,
  });

  final String title;
  final ButtonResultActionMode mode;
  final List<GestureAction> actions;
  final ValueChanged<ButtonResultActionMode> onModeChanged;
  final VoidCallback onRecord;
  final bool isBusy;
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
            onPressed: isBusy ? null : onRecord,
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fiber_manual_record_rounded),
            label: Text(
              isBusy
                  ? '正在打开录制'
                  : actions.isEmpty
                  ? '录制自定义动作'
                  : '已录制 ${actions.length} 个动作',
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageTemplatePreview extends StatelessWidget {
  const _ImageTemplatePreview({
    required this.templateBase64,
    required this.width,
    required this.height,
    required this.region,
  });

  final String templateBase64;
  final int width;
  final int height;
  final Map<String, double>? region;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _decodeTemplate();
    final regionText = region == null
        ? '区域：全屏查找'
        : '区域：${_pct(region!['left'])}, ${_pct(region!['top'])} - ${_pct(region!['right'])}, ${_pct(region!['bottom'])}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 86,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes == null
                ? const Icon(Icons.image_not_supported_outlined)
                : Image.memory(bytes, fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已圈选图片',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${width}x$height px', style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  regionText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
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

  String _pct(double? value) {
    return '${(((value ?? 0) * 1000).round() / 10).toStringAsFixed(1)}%';
  }

  Uint8List? _decodeTemplate() {
    if (templateBase64.isEmpty) return null;
    try {
      return base64Decode(templateBase64);
    } catch (_) {
      return null;
    }
  }
}
