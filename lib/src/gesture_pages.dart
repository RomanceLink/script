import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'models/task_models.dart';
import 'services/task_repository.dart';
import 'services/douyin_launcher.dart';

import 'services/alarm_bridge.dart';

part 'gesture_parts/gesture_pages_dialogs.dart';
part 'gesture_parts/gesture_pages_editor.dart';
part 'gesture_parts/gesture_pages_widgets.dart';

BoxDecoration _automationPageBackground(ThemeData theme) {
  return BoxDecoration(
    gradient: LinearGradient(
      colors: theme.brightness == Brightness.dark
          ? const [Color(0xFF091616), Color(0xFF102222), Color(0xFF151B2C)]
          : const [Color(0xFFF5FFF9), Color(0xFFEAF7FF), Color(0xFFF7F0FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

BoxDecoration _automationCardDecoration(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  final tint = theme.colorScheme.primary;
  return BoxDecoration(
    color: _automationLiquidGlassFill(theme, tint),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: _automationLiquidGlassBorder(theme, tint)),
    boxShadow: [
      BoxShadow(
        color: tint.withValues(alpha: isDark ? 0.22 : 0.14),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

Color _automationLiquidGlassFill(ThemeData theme, Color tint) {
  final isDark = theme.brightness == Brightness.dark;
  final base = isDark
      ? const Color(0xFF132321).withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.78);
  return Color.alphaBlend(tint.withValues(alpha: isDark ? 0.24 : 0.18), base);
}

Color _automationLiquidGlassBorder(ThemeData theme, Color tint) {
  final isDark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    Colors.white.withValues(alpha: isDark ? 0.10 : 0.42),
    tint.withValues(alpha: isDark ? 0.28 : 0.34),
  );
}

Color _automationHeaderColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? const Color(0xFF152625).withValues(alpha: 0.96)
      : const Color(0xFFF3FBF7).withValues(alpha: 0.96);
}

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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GlassActionTile(
                icon: Icons.lock_open_rounded,
                title: _unlockConfig == null ? '录制锁屏解锁' : '重新录制锁屏解锁',
                onTap: () {
                  Navigator.of(context).pop();
                  _recordUnlockConfig();
                },
              ),
              _GlassActionTile(
                icon: Icons.verified_user_outlined,
                title: '验证锁屏解锁',
                enabled: _unlockConfig != null,
                onTap: () {
                  Navigator.of(context).pop();
                  _verifyUnlockConfig();
                },
              ),
              if (_unlockConfig != null)
                _GlassActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: '删除锁屏脚本',
                  destructive: true,
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
        builder: (_) => GestureEditPage(
          config: config,
          launcher: widget.launcher,
          repository: widget.repository,
        ),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GlassActionTile(
                icon: Icons.edit_outlined,
                title: '编辑',
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              _GlassActionTile(
                icon: Icons.delete_outline_rounded,
                title: '删除',
                destructive: true,
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: _automationHeaderColor(theme),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          '自动化配置中心',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '锁屏脚本',
            onPressed: _showUnlockMenu,
            icon: Icon(
              _unlockConfig == null
                  ? Icons.lock_open_rounded
                  : Icons.lock_rounded,
              color: _unlockConfig == null ? null : const Color(0xFF4A9D8F),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.paddingOf(context).bottom + 10,
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
                onPressed: () => _addOrEdit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  '新建自动化配置',
                  style: TextStyle(fontWeight: FontWeight.bold),
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
            if (widget.onClose != null) ...[
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: Container(
        decoration: _automationPageBackground(theme),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _configs.isEmpty
            ? Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  decoration: _automationCardDecoration(theme),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_motion_rounded,
                        size: 64,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '尚未创建任何配置',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        decoration: _automationCardDecoration(theme),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF4A9D8F,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.gesture_rounded,
                                color: const Color(0xFF4A9D8F),
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
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${config.actions.length}步骤 · '
                                    '${config.infiniteLoop ? '无限循环' : '${config.loopCount}次循环'}'
                                    '${config.followUpConfigId == null ? '' : ' · 含追加配置'}'
                                    ' · ${config.infiniteLoop ? '持续执行' : '约${estimateGestureConfigDuration(config).label}'}',
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
                                    backgroundColor: const Color(
                                      0xFF4A9D8F,
                                    ).withValues(alpha: 0.15),
                                    foregroundColor: const Color(0xFF4A9D8F),
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 20,
                                  ),
                                  onPressed: widget.onRunConfig == null
                                      ? null
                                      : () => widget.onRunConfig!(config),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 20,
                                  ),
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
      ),
    );
  }
}
