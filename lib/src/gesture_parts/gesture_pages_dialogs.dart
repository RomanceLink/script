part of '../gesture_pages.dart';

class _SchemeSettingsDialog extends StatefulWidget {
  const _SchemeSettingsDialog({
    required this.name,
    required this.loopCount,
    required this.loopInterval,
    required this.infiniteLoop,
  });

  final String name;
  final String loopCount;
  final String loopInterval;
  final bool infiniteLoop;

  @override
  State<_SchemeSettingsDialog> createState() => _SchemeSettingsDialogState();
}

class _SchemeSettingsDialogState extends State<_SchemeSettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _loopCountController;
  late final TextEditingController _loopIntervalController;
  late bool _infiniteLoop;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _loopCountController = TextEditingController(text: widget.loopCount);
    _loopIntervalController = TextEditingController(text: widget.loopInterval);
    _infiniteLoop = widget.infiniteLoop;
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
      infiniteLoop: _infiniteLoop,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeVertical = MediaQuery.paddingOf(context).vertical;
    final keyboardVisible = viewInsets.bottom > 0;
    final maxDialogHeight = keyboardVisible
        ? (screenHeight * 0.52).clamp(220.0, 420.0)
        : (screenHeight - safeVertical - 24).clamp(220.0, 420.0);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(18, 12, 18, viewInsets.bottom + 8),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxDialogHeight),
            child: Material(
              color: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
              elevation: 16,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '方案设置',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              _compactField(
                controller: _nameController,
                label: '名称',
                hint: '请填写方案名称',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _compactField(
                      controller: _loopCountController,
                      label: '循环次数',
                      enabled: !_infiniteLoop,
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
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _infiniteLoop = !_infiniteLoop),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '无限循环',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Switch(
                        value: _infiniteLoop,
                        onChanged: (value) =>
                            setState(() => _infiniteLoop = value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
        ),
      ),
    );
  }

  Widget _compactField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool enabled = true,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
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

