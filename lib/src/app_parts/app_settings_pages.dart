part of '../app.dart';

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
      body: _NeonPageBackground(
        child: ListView(
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
    final recentPackages = await widget.launcher.loadRecentAppPackages();
    if (!mounted) return;
    setState(() => _loadingApps = false);
    final selected = await showModalBottomSheet<LaunchableApp>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final controller = TextEditingController();
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = apps.where((app) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return app.appName.toLowerCase().contains(q) ||
                  app.packageName.toLowerCase().contains(q);
            }).toList();
            final recent = [
              for (final package in recentPackages)
                ...filtered.where((app) => app.packageName == package),
            ];
            final others = [
              for (final app in filtered)
                if (!recent.any((item) => item.packageName == app.packageName))
                  app,
            ];
            return SafeArea(
              child: SizedBox(
                height: 520,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: controller,
                        onChanged: (value) =>
                            setSheetState(() => query = value.trim()),
                        decoration: const InputDecoration(
                          labelText: '搜索应用',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (recent.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                              child: Text(
                                '最近使用',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            ...recent.map(
                              (app) => ListTile(
                                leading: app.icon == null
                                    ? const CircleAvatar(
                                        child: Icon(Icons.apps_rounded),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.memory(
                                          app.icon!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                title: Text(app.appName),
                                subtitle: Text(app.packageName),
                                onTap: () => Navigator.of(context).pop(app),
                              ),
                            ),
                            const Divider(height: 12),
                          ],
                          ...others.map(
                            (app) => ListTile(
                              leading: app.icon == null
                                  ? const CircleAvatar(
                                      child: Icon(Icons.apps_rounded),
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.memory(
                                        app.icon!,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                              title: Text(app.appName),
                              subtitle: Text(app.packageName),
                              onTap: () => Navigator.of(context).pop(app),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    await widget.launcher.markAppAsRecent(selected.packageName);
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
      body: _NeonPageBackground(
        child: ListView(
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
      body: _NeonPageBackground(
        child: ListView(
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
      body: _NeonPageBackground(
        child: ListView(
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
                        onPressed:
                            alarmBridge.requestIgnoreBatteryOptimizations,
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
      ),
    );
  }
}
