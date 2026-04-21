part of 'app.dart';

class _CenteredToast extends StatefulWidget {
  const _CenteredToast({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  @override
  State<_CenteredToast> createState() => _CenteredToastState();
}

class _CenteredToastState extends State<_CenteredToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  late Animation<double> _iconBounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );
    _iconBounce = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        widget.onDismiss();
      }
    });

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2100), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (iconColor, icon) = switch (widget.type) {
      ToastType.success => (const Color(0xFF4CAF50), Icons.thumb_up_rounded),
      ToastType.error => (const Color(0xFFF44336), Icons.error_rounded),
      ToastType.warning => (const Color(0xFFFF9800), Icons.warning_rounded),
      ToastType.info => (const Color(0xFF2196F3), Icons.info_rounded),
    };

    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          FadeTransition(
            opacity: _opacity,
            child: Container(color: Colors.black.withValues(alpha: 0.32)),
          ),
          Center(
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 260, // 固定宽度，确保视觉稳定
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF252525) : Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 36,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _iconBounce,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: iconColor, size: 52),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1D1D1F),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    this.imageProvider,
    required this.actionRow,
  });

  final String title;
  final String subtitle;
  final String summary;
  final ImageProvider<Object>? imageProvider;
  final Widget actionRow;

  List<String> _poemLines(String text) {
    final phrases = text
        .split(RegExp(r'(?<=[，。！？；：])'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (phrases.isEmpty) {
      return [text];
    }
    final lines = <String>[];
    var index = 0;
    while (index < phrases.length) {
      final current = phrases[index];
      lines.add(current);
      index += 1;
      if (lines.length >= 4) {
        break;
      }
    }
    return lines;
  }

  double _poemFontSize(List<String> lines) {
    final longest = lines.fold<int>(
      0,
      (best, line) => line.length > best ? line.length : best,
    );
    if (longest >= 22) return 18;
    if (longest >= 16) return 20;
    return 22;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final poemLines = _poemLines(title);
    final poemFontSize = _poemFontSize(poemLines);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.95),
            colors.secondaryContainer.withValues(alpha: 0.92),
            colors.tertiaryContainer.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              actionRow,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  poemLines.join('\n'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: poemFontSize,
                    fontWeight: FontWeight.w900,
                    height: 1.28,
                    fontFamilyFallback: const [
                      'KaiTi',
                      'STKaiti',
                      'Kaiti SC',
                      'Noto Serif SC',
                      'serif',
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _HeaderPortrait(imageProvider: imageProvider),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconAction extends StatelessWidget {
  const _HeaderIconAction({
    required this.icon,
    required this.onTap,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: foreground),
        ),
      ),
    );
  }
}

class _HeaderPortrait extends StatelessWidget {
  const _HeaderPortrait({required this.imageProvider});

  final ImageProvider<Object>? imageProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        image: imageProvider == null
            ? null
            : DecorationImage(image: imageProvider!, fit: BoxFit.cover),
      ),
      child: imageProvider == null
          ? Icon(
              Icons.image_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 28,
            )
          : null,
    );
  }
}

class _TaskDeckCard extends StatelessWidget {
  const _TaskDeckCard({
    required this.task,
    required this.status,
    required this.accent,
    required this.icon,
    required this.headline,
    required this.detail,
    required this.progressLabel,
    required this.progressValue,
    required this.primaryLabel,
    required this.onPrimary,
    required this.primaryEnabled,
    required this.showQuickLaunch,
    required this.appLabel,
    required this.configLabel,
    required this.onOpenApp,
  });

  final AssistantTaskDefinition task;
  final String status;
  final Color accent;
  final IconData icon;
  final String headline;
  final String detail;
  final String progressLabel;
  final String progressValue;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final bool primaryEnabled;
  final bool showQuickLaunch;
  final String appLabel;
  final String? configLabel;
  final Future<void> Function() onOpenApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryButtonFill = theme.brightness == Brightness.dark
        ? accent.withValues(alpha: 0.88)
        : Color.lerp(accent, Colors.white, 0.2)!;
    final primaryButtonText = theme.brightness == Brightness.dark
        ? Colors.white
        : _idealTextColor(primaryButtonFill);
    final secondaryButtonFill = theme.brightness == Brightness.dark
        ? accent.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.14);
    final secondaryButtonText = theme.brightness == Brightness.dark
        ? accent.withValues(alpha: 0.98)
        : accent.withValues(alpha: 0.95);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.18 : 0.15,
              ),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: accent, size: 23),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${task.timeLabel} · 铃声 ${task.ringtoneLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (configLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '绑定配置：$configLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _StatusBadge(label: status, accent: accent),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final useTwoColumns = constraints.maxWidth >= 300;
                  if (useTwoColumns) {
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _InfoPanel(
                                title: '任务时间',
                                value: headline,
                                accent: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _InfoPanel(
                                title: progressLabel,
                                value: progressValue,
                                accent: accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _DetailPanel(detail: detail, accent: accent),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _InfoPanel(
                        title: '任务时间',
                        value: headline,
                        accent: accent,
                      ),
                      const SizedBox(height: 8),
                      _InfoPanel(
                        title: progressLabel,
                        value: progressValue,
                        accent: accent,
                      ),
                      const SizedBox(height: 8),
                      _DetailPanel(detail: detail, accent: accent),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              if (showQuickLaunch)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryButtonFill,
                          foregroundColor: primaryButtonText,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: primaryEnabled ? onPrimary : null,
                        child: Text(primaryLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: secondaryButtonFill,
                          foregroundColor: secondaryButtonText,
                          side: BorderSide.none,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: onOpenApp,
                        child: Text(
                          '打开$appLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryButtonFill,
                      foregroundColor: primaryButtonText,
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: primaryEnabled ? onPrimary : null,
                    child: Text(primaryLabel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _idealTextColor(Color background) {
    return background.computeLuminance() > 0.55
        ? const Color(0xFF12322B)
        : Colors.white;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.value,
    required this.accent,
  });

  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 30,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.detail, required this.accent});

  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.brightness == Brightness.dark
        ? (value ? const Color(0xFF1E3B35) : const Color(0xFF1A2526))
        : (value ? const Color(0xFFE0F5EC) : const Color(0xFFF2F7F4));
    final text = theme.brightness == Brightness.dark
        ? (value ? const Color(0xFF96E1CC) : const Color(0xFFBCD1CA))
        : (value ? const Color(0xFF2D7A67) : const Color(0xFF5E7F75));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value
              ? const Color(0xFF86D7BF).withValues(alpha: 0.8)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF83D8BD),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: theme.brightness == Brightness.dark
                ? const Color(0xFF384A46)
                : const Color(0xFFD7E3DE),
            trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF213033)
              : const Color(0xFFEAF4F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          size: 20,
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFC7DDD7)
              : const Color(0xFF55776E),
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.helper,
    required this.child,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final String helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.16 : 0.12,
              ),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          helper,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PastelButton extends StatelessWidget {
  const _PastelButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavCell extends StatelessWidget {
  const _SettingsNavCell({
    required this.icon,
    required this.iconTint,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final Color iconTint;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final String trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconTint, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailingText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
