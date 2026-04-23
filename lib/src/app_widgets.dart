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

Color _liquidGlassFill(ThemeData theme, Color tint, {double strength = 1}) {
  final isDark = theme.brightness == Brightness.dark;
  final base = isDark
      ? const Color(0xFF132321).withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.78);
  return Color.alphaBlend(
    tint.withValues(alpha: isDark ? 0.26 * strength : 0.20 * strength),
    base,
  );
}

Color _liquidGlassBorder(ThemeData theme, Color tint, {double strength = 1}) {
  final isDark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    Colors.white.withValues(alpha: isDark ? 0.10 : 0.44),
    tint.withValues(alpha: isDark ? 0.30 * strength : 0.36 * strength),
  );
}

List<BoxShadow> _liquidGlassShadow(
  ThemeData theme,
  Color tint, {
  double strength = 1,
}) {
  final isDark = theme.brightness == Brightness.dark;
  return [
    BoxShadow(
      color: tint.withValues(alpha: isDark ? 0.24 * strength : 0.15 * strength),
      blurRadius: 30,
      offset: const Offset(0, 16),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

Color _neonGlassFill(ThemeData theme, {double alpha = 0.22}) {
  return theme.brightness == Brightness.dark
      ? const Color(0xFF2A2F63)
      : const Color(0xFFE9EEFF);
}

Color _taskMetaPanelFill(ThemeData theme, Color accent) {
  final isDark = theme.brightness == Brightness.dark;
  final base = _neonGlassFill(theme);
  return Color.alphaBlend(accent.withValues(alpha: isDark ? 0.08 : 0.10), base);
}

Color _taskMetaPanelBorder(ThemeData theme, Color accent) {
  final isDark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    Colors.white.withValues(alpha: isDark ? 0.10 : 0.32),
    accent.withValues(alpha: isDark ? 0.18 : 0.22),
  );
}

Color _neonGlassLine(Color accent, {double alpha = 0.7}) {
  return Color.alphaBlend(
    Colors.white.withValues(alpha: 0.24),
    accent.withValues(alpha: alpha),
  );
}

List<BoxShadow> _neonGlassGlow(Color accent, {double strength = 1}) {
  return [
    BoxShadow(
      color: accent.withValues(alpha: 0.26 * strength),
      blurRadius: 26,
      spreadRadius: 1,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.22),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

BoxDecoration _neonPageDecoration(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    gradient: LinearGradient(
      colors: isDark
          ? const [Color(0xFF1D214C), Color(0xFF242A5A), Color(0xFF32254E)]
          : const [Color(0xFFF4F6FF), Color(0xFFEAF0FF), Color(0xFFF5EEFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

class _NeonPageBackground extends StatelessWidget {
  const _NeonPageBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Stack(
      children: [
        Container(decoration: _neonPageDecoration(theme)),
        Positioned(
          top: -80,
          left: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(
                0xFF55DFFF,
              ).withValues(alpha: isDark ? 0.14 : 0.18),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF55DFFF,
                  ).withValues(alpha: isDark ? 0.20 : 0.28),
                  blurRadius: 120,
                  spreadRadius: 24,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: -60,
          bottom: -30,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(
                0xFFFF5FD2,
              ).withValues(alpha: isDark ? 0.12 : 0.14),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFFFF5FD2,
                  ).withValues(alpha: isDark ? 0.18 : 0.22),
                  blurRadius: 130,
                  spreadRadius: 26,
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
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

class _HeaderCard extends StatefulWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    this.attribution,
    this.imageProvider,
    this.autoSwitch = false,
    this.autoSwitchInterval = const Duration(seconds: 3),
    required this.actionRow,
  });

  final String title;
  final String subtitle;
  final String summary;
  final String? attribution;
  final ImageProvider<Object>? imageProvider;
  final bool autoSwitch;
  final Duration autoSwitchInterval;
  final Widget actionRow;

  @override
  State<_HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends State<_HeaderCard> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoSwitchTimer;
  int _lastPageCount = 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant _HeaderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _currentPage = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
    final shouldResync =
        oldWidget.title != widget.title ||
        oldWidget.autoSwitch != widget.autoSwitch ||
        oldWidget.autoSwitchInterval != widget.autoSwitchInterval;
    if (shouldResync) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncAutoSwitch(_lastPageCount),
      );
    }
  }

  @override
  void dispose() {
    _autoSwitchTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  List<String> _poemLines(String text) {
    final phrases = text
        .split(RegExp(r'(?<=[，。！？；：])'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (phrases.isEmpty) {
      return [text];
    }
    return phrases;
  }

  List<List<String>> _poemPages(List<String> lines) {
    if (lines.isEmpty) {
      return const [
        [''],
      ];
    }
    final pages = <List<String>>[];
    for (var index = 0; index < lines.length; index += 4) {
      pages.add(lines.skip(index).take(4).toList());
    }
    return pages;
  }

  void _syncAutoSwitch([int? pageCount]) {
    _autoSwitchTimer?.cancel();
    final totalPages = pageCount ?? _poemPages(_poemLines(widget.title)).length;
    _lastPageCount = totalPages;
    if (!widget.autoSwitch || totalPages <= 1 || !_pageController.hasClients) {
      return;
    }
    _autoSwitchTimer = Timer.periodic(widget.autoSwitchInterval, (_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      final nextPage = (_currentPage + 1) % totalPages;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
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
    const cyan = Color(0xFF7FE7FF);
    const pink = Color(0xFFE78BFF);
    final edgeTint = Color.lerp(cyan, pink, 0.52)!;
    final poemLines = _poemLines(widget.title);
    final poemPages = _poemPages(poemLines);
    if (_lastPageCount != poemPages.length) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncAutoSwitch(poemPages.length),
      );
    }
    final poemFontSize = _poemFontSize(poemLines);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0x3AFFFFFF),
                Color(0x24BFD8FF),
                Color(0x22E69CFF),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _neonGlassLine(edgeTint)),
            boxShadow: _neonGlassGlow(edgeTint, strength: 1.15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      widget.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  widget.actionRow,
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 124,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: poemPages.length,
                              onPageChanged: (value) {
                                if (_currentPage == value) {
                                  return;
                                }
                                setState(() => _currentPage = value);
                              },
                              itemBuilder: (context, index) {
                                final pageLines = poemPages[index];
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    pageLines.join('\n'),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: poemFontSize,
                                      fontWeight: FontWeight.w900,
                                      height: 1.28,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: cyan.withValues(alpha: 0.24),
                                          blurRadius: 12,
                                        ),
                                      ],
                                      fontFamilyFallback: const [
                                        'KaiTi',
                                        'STKaiti',
                                        'Kaiti SC',
                                        'Noto Serif SC',
                                        'serif',
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HeaderPortrait(imageProvider: widget.imageProvider),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.attribution != null &&
                  widget.attribution!.trim().isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.attribution!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontWeight: FontWeight.w700,
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
                const SizedBox(height: 10),
              ],
              Text(
                widget.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
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
      color: background.withValues(alpha: 0.82),
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
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x30FFFFFF), Color(0x18B8E5FF), Color(0x18E390FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
        boxShadow: _neonGlassGlow(const Color(0xFF8CDFFF), strength: 0.7),
        image: imageProvider == null
            ? null
            : DecorationImage(image: imageProvider!, fit: BoxFit.cover),
      ),
      child: imageProvider == null
          ? Icon(
              Icons.image_outlined,
              color: Colors.white.withValues(alpha: 0.76),
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
    required this.configDetails,
    required this.onOpenApp,
    this.taskActions,
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
  final List<String> configDetails;
  final Future<void> Function() onOpenApp;
  final Widget? taskActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glassFill = _neonGlassFill(theme, alpha: 0.16);
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
    final bool isExpired = status == '任务已过期' || progressValue == '已逾期';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [glassFill, accent.withValues(alpha: 0.16)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _neonGlassLine(accent)),
            borderRadius: BorderRadius.circular(26),
            boxShadow: _neonGlassGlow(accent, strength: 0.9),
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
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            accent.withValues(alpha: 0.40),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _neonGlassGlow(accent, strength: 0.55),
                      ),
                      child: Icon(icon, color: Colors.white, size: 23),
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
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${task.timeLabel} · 铃声 ${task.ringtoneLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(label: status, accent: accent),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (configDetails.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.34),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final line in configDetails)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      line,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.84,
                                            ),
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (taskActions != null) ...[
                          taskActions!,
                          const SizedBox(height: 12),
                        ],
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final useTwoColumns = constraints.maxWidth >= 300;
                            if (useTwoColumns) {
                              return Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // --- 底部操作区 ---
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                  ),
                  child: showQuickLaunch
                      ? Row(
                          children: [
                            Expanded(
                              child: _EnhancedTaskButton(
                                label: primaryLabel,
                                icon: isExpired
                                    ? Icons.history_rounded
                                    : Icons.check_circle_outline_rounded,
                                backgroundColor: primaryButtonFill,
                                foregroundColor: primaryButtonText,
                                onPressed: primaryEnabled ? onPrimary : null,
                                shadowColor: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _EnhancedTaskButton(
                                label: '打开$appLabel',
                                icon: Icons.open_in_new_rounded,
                                backgroundColor: secondaryButtonFill,
                                foregroundColor: secondaryButtonText,
                                onPressed: onOpenApp,
                                isTonal: true,
                              ),
                            ),
                          ],
                        )
                      : _EnhancedTaskButton(
                          label: primaryLabel,
                          icon: isExpired
                              ? Icons.history_rounded
                              : Icons.check_circle_outline_rounded,
                          backgroundColor: primaryButtonFill,
                          foregroundColor: primaryButtonText,
                          onPressed: primaryEnabled ? onPrimary : null,
                          shadowColor: accent.withValues(alpha: 0.35),
                          isFullWidth: true,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskQuickActionChip extends StatelessWidget {
  const _TaskQuickActionChip({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

Color _idealTextColor(Color background) {
  return background.computeLuminance() > 0.55
      ? const Color(0xFF12322B)
      : Colors.white;
}

/// 增强型任务按钮，带投影和图标
class _EnhancedTaskButton extends StatelessWidget {
  const _EnhancedTaskButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onPressed,
    this.shadowColor,
    this.isFullWidth = false,
    this.isTonal = false,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;
  final Color? shadowColor;
  final bool isFullWidth;
  final bool isTonal;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      height: 44, // 增加高度
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: isTonal ? 0.14 : 0.18),
        ),
        boxShadow: (onPressed != null && shadowColor != null && !isTonal)
            ? [
                BoxShadow(
                  color: shadowColor!,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: isTonal
          ? FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
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
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.white,
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
        color: _taskMetaPanelFill(theme, accent),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _taskMetaPanelBorder(theme, accent)),
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
        color: _taskMetaPanelFill(theme, accent),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _taskMetaPanelBorder(theme, accent)),
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
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _neonGlassFill(theme, alpha: 0.16),
                accent.withValues(alpha: 0.14),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _neonGlassLine(accent)),
            boxShadow: _neonGlassGlow(accent, strength: 0.82),
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
                        color: accent.withValues(alpha: 0.86),
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
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            helper,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.68),
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
        backgroundColor: background.withValues(alpha: 0.82),
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
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
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: _neonGlassGlow(iconTint, strength: 0.62),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: isDark ? const Color(0xFF2A2F63) : const Color(0xFFDCE3FF),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(
                                alpha: isDark ? 0.24 : 0.18,
                              ),
                              iconTint.withValues(alpha: isDark ? 0.38 : 0.30),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _neonGlassLine(iconTint)),
                        ),
                        child: Icon(
                          icon,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF26336F),
                          size: 24,
                        ),
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
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF26336F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.72)
                                    : const Color(0xFF5C6AA8),
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
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.88)
                                  : const Color(0xFF3E4E9A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.72)
                                : const Color(0xFF6A78B6),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionSheetTile extends StatelessWidget {
  const _ActionSheetTile({
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
                  color: _liquidGlassFill(theme, tint, strength: 0.9),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _liquidGlassBorder(theme, tint, strength: 0.8),
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
