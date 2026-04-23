part of '../app.dart';

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
      useSafeArea: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
    final autoComplete = task.autoCompleteDelayValue > 0
        ? ' · 打开后${task.autoCompleteDelayValue}${switch (task.autoCompleteDelayUnit) {
            IntervalUnit.seconds => '秒',
            IntervalUnit.minutes => '分钟',
            IntervalUnit.hours => '小时',
            IntervalUnit.days => '天',
          }}自动完成'
        : '';
    return '$type · ${task.timeLabel}$suffix · 铃声 ${task.ringtoneLabel}$quick$pre$autoOpen$autoComplete';
  }

  String _kindGroupLabel(AssistantTaskKind kind) {
    return switch (kind) {
      AssistantTaskKind.feedWindow => '时间段任务',
      AssistantTaskKind.adCooldown => '循环计次任务',
      AssistantTaskKind.fixedPoint => '固定时间任务',
    };
  }

  Color _kindGroupAccent(AssistantTaskKind kind) {
    return switch (kind) {
      AssistantTaskKind.feedWindow => const Color(0xFF76C7AE),
      AssistantTaskKind.adCooldown => const Color(0xFFFFB17E),
      AssistantTaskKind.fixedPoint => const Color(0xFF82A7F7),
    };
  }

  String _kindGroupHelper(AssistantTaskKind kind) {
    return switch (kind) {
      AssistantTaskKind.feedWindow => '在规定时间段内完成，适合刷视频、学习、训练等连续任务。',
      AssistantTaskKind.adCooldown => '按次数与间隔循环执行，适合重复性动作与计次任务。',
      AssistantTaskKind.fixedPoint => '到点提醒并处理，适合固定时刻必须完成的任务。',
    };
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
      final accent = _kindGroupAccent(kind);
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SettingsSectionCard(
            accent: accent,
            title: _kindGroupLabel(kind),
            subtitle: '${items.length} 个任务',
            helper: _kindGroupHelper(kind),
            child: Column(
              children: [
                for (final task in items) ...[
                  Builder(
                    builder: (context) {
                      final enabled = _draft.isEnabled(task.id);
                      final homeVisible = _draft.isHomeVisible(task.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        task.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _taskSummary(task),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white.withValues(
                                                alpha: 0.72,
                                              ),
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
                                    final action =
                                        await showModalBottomSheet<String>(
                                          context: context,
                                          showDragHandle: true,
                                          builder: (context) => SafeArea(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    16,
                                                    8,
                                                    16,
                                                    18,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _ActionSheetTile(
                                                    icon: Icons.edit_rounded,
                                                    title: '编辑任务',
                                                    onTap: () => Navigator.of(
                                                      context,
                                                    ).pop('edit'),
                                                  ),
                                                  _ActionSheetTile(
                                                    icon: Icons
                                                        .delete_outline_rounded,
                                                    title: '删除任务',
                                                    destructive: true,
                                                    onTap: () => Navigator.of(
                                                      context,
                                                    ).pop('delete'),
                                                  ),
                                                ],
                                              ),
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
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = _draft.taskDefinitions.isEmpty;
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
      body: _NeonPageBackground(
        child: isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.8,
                    width: double.infinity,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.event_note_rounded,
                                size: 34,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '还没有任务',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击右下角新增任务，把常用提醒和脚本绑定都配好。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => _editTask(),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新增第一个任务'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: _buildGroupedTaskSections(context),
              ),
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
        ? const Color(0xFF2F356D)
        : const Color(0xFFDCE3FF);
    final mintText = theme.brightness == Brightness.dark
        ? const Color(0xFFC7D0FF)
        : const Color(0xFF3B4AA0);
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
      body: _NeonPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _neonGlassFill(theme, alpha: 0.18),
                    const Color(0xFF72DFFF).withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _neonGlassLine(const Color(0xFF72DFFF), alpha: 0.42),
                ),
                boxShadow: _neonGlassGlow(
                  const Color(0xFF72DFFF),
                  strength: 0.34,
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
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
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _neonGlassFill(theme, alpha: 0.18),
                      const Color(0xFFD69AF1).withValues(alpha: 0.10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _neonGlassLine(const Color(0xFFD69AF1), alpha: 0.38),
                  ),
                  boxShadow: _neonGlassGlow(
                    const Color(0xFFD69AF1),
                    strength: 0.34,
                  ),
                ),
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
                                Icon(
                                  Icons.auto_awesome_motion_rounded,
                                  size: 16,
                                ),
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
      useSafeArea: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
    final autoComplete = task.autoCompleteDelayValue > 0
        ? ' · 打开后${task.autoCompleteDelayValue}${switch (task.autoCompleteDelayUnit) {
            IntervalUnit.seconds => '秒',
            IntervalUnit.minutes => '分钟',
            IntervalUnit.hours => '小时',
            IntervalUnit.days => '天',
          }}自动完成'
        : '';
    return '$type · ${task.timeLabel}$suffix · 铃声 ${task.ringtoneLabel}$quick$pre$autoOpen$autoComplete';
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
