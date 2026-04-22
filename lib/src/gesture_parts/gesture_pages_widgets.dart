part of '../gesture_pages.dart';

class _GlassActionTile extends StatelessWidget {
  const _GlassActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = !enabled
        ? theme.colorScheme.onSurfaceVariant
        : destructive
        ? const Color(0xFFE05A5A)
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: isDark ? 0.12 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            const Color(0xFF223231).withValues(alpha: 0.96),
                            const Color(0xFF1B282B).withValues(alpha: 0.96),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.94),
                            const Color(0xFFF0FBF7).withValues(alpha: 0.88),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.70),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        icon,
                        color: tint.withValues(alpha: enabled ? 1 : 0.45),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: enabled ? 1 : 0.45,
                              ),
                            ),
                          ),
                          if (subtitle != null &&
                              subtitle!.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: enabled ? 1 : 0.35,
                      ),
                    ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: _automationCardDecoration(theme),
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
              Padding(padding: const EdgeInsets.all(16), child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactSelectionTile extends StatelessWidget {
  const _CompactSelectionTile({
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.brightness == Brightness.dark
                ? [
                    const Color(0xFF183030).withValues(alpha: 0.92),
                    const Color(0xFF1A2430).withValues(alpha: 0.88),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.88),
                    const Color(0xFFEFFBF7).withValues(alpha: 0.78),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.10 : 0.64,
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
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
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
          gradient: LinearGradient(
            colors: theme.brightness == Brightness.dark
                ? [
                    const Color(0xFF17302F).withValues(alpha: 0.92),
                    const Color(0xFF1A2430).withValues(alpha: 0.88),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.90),
                    const Color(0xFFF3FFF9).withValues(alpha: 0.80),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.10 : 0.62,
            ),
          ),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            _getActionSummary(),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Colors.redAccent,
                ),
                onPressed: onDelete,
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Icon(
                  Icons.drag_indicator_rounded,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _getActionVisuals(ThemeData theme) {
    if (action is ClickAction) {
      return (Icons.touch_app_rounded, const Color(0xFF4A9D8F));
    }
    if (action is SwipeAction) {
      return (Icons.swipe_rounded, const Color(0xFF82A7F7));
    }
    if (action is WaitAction) {
      return (Icons.timer_rounded, const Color(0xFFFFA977));
    }
    if (action is NavAction) {
      return (Icons.navigation_rounded, const Color(0xFFD69AF1));
    }
    if (action is LaunchAppAction) {
      return (Icons.rocket_launch_rounded, const Color(0xFF8EB8FF));
    }
    if (action is LockScreenAction) {
      return (Icons.lock_outline_rounded, const Color(0xFFD69AF1));
    }
    if (action is ButtonRecognizeAction) {
      return (Icons.center_focus_strong_rounded, const Color(0xFF82A7F7));
    }
    if (action is RecordedGestureAction) {
      return (Icons.gesture_rounded, const Color(0xFF4A9D8F));
    }
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
      return a.isRandom
          ? '随机: ${a.effectiveMinSeconds}-${a.effectiveMaxSeconds}秒'
          : '时长: ${a.milliseconds}ms';
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
