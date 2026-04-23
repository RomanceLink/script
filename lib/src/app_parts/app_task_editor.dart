part of '../app.dart';

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
  late TextEditingController _autoCompleteDelayController;
  late IntervalUnit _intervalUnit;
  late IntervalUnit _autoCompleteDelayUnit;
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
    _autoCompleteDelayController = TextEditingController(
      text: '${task?.autoCompleteDelayValue ?? 0}',
    );
    _intervalUnit = task?.intervalUnit ?? IntervalUnit.minutes;
    _autoCompleteDelayUnit =
        task?.autoCompleteDelayUnit ?? IntervalUnit.minutes;
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
    _autoCompleteDelayController.dispose();
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
                  icon: Icons.link_off_rounded,
                  title: allowNoneLabel,
                  onTap: () => Navigator.of(context).pop('none'),
                ),
                ..._availableConfigs.map(
                  (c) => _ActionSheetTile(
                    icon: c.infiniteLoop
                        ? Icons.all_inclusive_rounded
                        : Icons.play_circle_outline_rounded,
                    title: c.name,
                    subtitle: c.infiniteLoop
                        ? '无限循环 · 间隔 ${c.loopIntervalMillis} 毫秒'
                        : '${c.loopCount} 次 · 间隔 ${c.loopIntervalMillis} 毫秒',
                    onTap: () => Navigator.of(context).pop(c.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return selected;
  }

  void _submitTask() {
    final isCounter = _kind == AssistantTaskKind.adCooldown;
    final isWindow = _kind == AssistantTaskKind.feedWindow;
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
        id: widget.task?.id ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
        kind: _kind,
        title: title,
        startHour: _start.hour,
        startMinute: _start.minute,
        endHour: isWindow ? _end?.hour ?? _start.hour : null,
        endMinute: isWindow ? _end?.minute ?? _start.minute : null,
        targetCount: isCounter ? int.tryParse(_targetController.text) ?? 1 : 0,
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
        autoCompleteDelayValue:
            int.tryParse(_autoCompleteDelayController.text.trim()) ?? 0,
        autoCompleteDelayUnit: _autoCompleteDelayUnit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCounter = _kind == AssistantTaskKind.adCooldown;
    final isWindow = _kind == AssistantTaskKind.feedWindow;
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    
    return Scaffold(
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 56 + topPadding + 30,
        primary: false,
        automaticallyImplyLeading: false, // 彻底禁用默认返回
        flexibleSpace: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '返回',
                ),
                const SizedBox(width: 18), // 增加间距
                Expanded(
                  child: Text(
                    widget.task == null ? '新建任务' : '编辑任务',
                    style: theme.appBarTheme.titleTextStyle,
                  ),
                ),
                TextButton(
                  onPressed: _submitTask,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('保存'),
                ),
                const SizedBox(width: 0),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          22,
          18,
          22,
          MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        children: [
          _EditorHeroCard(kindLabel: _kindLabel(_kind)),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
                      helperText: '默认 0 关闭。到点会自动点击“打开应用/去完成任务”。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _autoCompleteDelayController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '打开后自动完成',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _IntervalUnitSelector(
                          value: _autoCompleteDelayUnit,
                          onChanged: (value) =>
                              setState(() => _autoCompleteDelayUnit = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
        ],
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
