part of '../app.dart';

class _DailyMottoSettingsPage extends StatefulWidget {
  const _DailyMottoSettingsPage({required this.repository});

  final TaskRepository repository;

  @override
  State<_DailyMottoSettingsPage> createState() =>
      _DailyMottoSettingsPageState();
}

class _DailyMottoSettingsPageState extends State<_DailyMottoSettingsPage> {
  static const List<String> _presetMottos = [
    '天生我才必有用，千金散尽还复来',
    '长风破浪会有时，直挂云帆济沧海',
    '且将新火试新茶，诗酒趁年华',
    '莫道桑榆晚，为霞尚满天',
    '山高路远，亦要见自己',
    '日日自新，步步生光',
  ];

  List<DailyMottoEntry> _mottos = const [];
  String? _pinnedMottoId;
  String _sourceUrl = _defaultDailyMottoSourceUrl;
  String? _imageUrl;
  String? _imagePath;
  bool _showMetaOnHome = true;
  bool _autoSwitchOnHome = false;
  int _autoSwitchValue = 3;
  IntervalUnit _autoSwitchUnit = IntervalUnit.seconds;
  bool _selectingDelete = false;
  final Set<String> _selectedDeleteIds = <String>{};
  bool _loading = true;
  bool _fetching = false;
  bool _fetchingImage = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await widget.repository.loadDailyMottoEntries();
    final sourceUrl =
        await widget.repository.loadDailyMottoSourceUrl() ??
        _defaultDailyMottoSourceUrl;
    final pinnedMottoId = await widget.repository.loadPinnedDailyMottoId();
    final imageUrl = await widget.repository.loadDailyMottoImageUrl();
    final imagePath = await widget.repository.loadDailyMottoImagePath();
    final showMetaOnHome = await widget.repository
        .loadShowDailyMottoMetaOnHome();
    final autoSwitchOnHome = await widget.repository
        .loadAutoScrollDailyMottoOnHome();
    final autoSwitchValue = await widget.repository
        .loadAutoScrollDailyMottoIntervalValue();
    final autoSwitchUnit = await widget.repository
        .loadAutoScrollDailyMottoIntervalUnit();
    final lastFetchDate = await widget.repository.loadDailyMottoLastFetchDate();
    final todayKey = _dateKey(DateTime.now());
    if (!mounted) return;
    setState(() {
      _mottos = values.isEmpty
          ? _presetMottos.map(DailyMottoEntry.fromLegacy).toList()
          : values;
      _pinnedMottoId = pinnedMottoId;
      _sourceUrl = sourceUrl;
      _imageUrl = imageUrl;
      _imagePath = imagePath;
      _showMetaOnHome = showMetaOnHome;
      _autoSwitchOnHome = autoSwitchOnHome;
      _autoSwitchValue = autoSwitchValue;
      _autoSwitchUnit = autoSwitchUnit;
      _loading = false;
    });
    final hasBrokenMottos = values.any(
      (item) => _looksLikeMojibake(item.content),
    );
    if (sourceUrl.isNotEmpty &&
        (lastFetchDate != todayKey || hasBrokenMottos)) {
      await _fetchFromSource(silentOnFailure: true);
    }
  }

  Future<void> _save() async {
    await widget.repository.saveDailyMottoEntries(_mottos);
    if (_pinnedMottoId != null &&
        !_mottos.any((item) => item.id == _pinnedMottoId)) {
      _pinnedMottoId = null;
      await widget.repository.savePinnedDailyMottoId(null);
    }
    await widget.repository.saveShowDailyMottoMetaOnHome(_showMetaOnHome);
    await widget.repository.saveAutoScrollDailyMottoOnHome(_autoSwitchOnHome);
    await widget.repository.saveAutoScrollDailyMottoIntervalValue(
      _autoSwitchValue,
    );
    await widget.repository.saveAutoScrollDailyMottoIntervalUnit(
      _autoSwitchUnit,
    );
    if (!mounted) return;
    VibrantHUD.show(context, '每日箴言已保存', type: ToastType.success);
  }

  Future<void> _setHomeMotto(DailyMottoEntry motto) async {
    setState(() => _pinnedMottoId = motto.id);
    await widget.repository.savePinnedDailyMottoId(motto.id);
    if (!mounted) return;
    VibrantHUD.show(context, '已设为首页显示', type: ToastType.success);
  }

  Future<void> _deleteItem(int index) async {
    final item = _mottos[index];
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '删除箴言',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(item.content),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _mottos = [
        for (var i = 0; i < _mottos.length; i++)
          if (i != index) _mottos[i],
      ];
      if (_pinnedMottoId == item.id) {
        _pinnedMottoId = null;
      }
    });
    await widget.repository.saveDailyMottoEntries(_mottos);
    if (_pinnedMottoId == null) {
      await widget.repository.savePinnedDailyMottoId(null);
    }
    if (!mounted) return;
    VibrantHUD.show(context, '删除成功', type: ToastType.success);
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedDeleteIds.isEmpty) {
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '批量删除箴言',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text('确定删除 ${_selectedDeleteIds.length} 条吗？'),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _mottos = _mottos
          .where((item) => !_selectedDeleteIds.contains(item.id))
          .toList();
      if (_pinnedMottoId != null &&
          _selectedDeleteIds.contains(_pinnedMottoId)) {
        _pinnedMottoId = null;
      }
      _selectedDeleteIds.clear();
      _selectingDelete = false;
    });
    await widget.repository.saveDailyMottoEntries(_mottos);
    if (_pinnedMottoId == null) {
      await widget.repository.savePinnedDailyMottoId(null);
    }
    if (!mounted) return;
    VibrantHUD.show(context, '删除成功', type: ToastType.success);
  }

  Future<void> _editItem({DailyMottoEntry? initialEntry, int? index}) async {
    final previousId = initialEntry?.id;
    final result = await showModalBottomSheet<DailyMottoEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MottoEntrySheet(
        title: index == null ? '新增箴言' : '编辑箴言',
        initialEntry: initialEntry,
      ),
    );
    if (!mounted || result == null || result.content.isEmpty) return;
    setState(() {
      if (index == null) {
        _mottos = [..._mottos, result];
      } else {
        _mottos = [
          for (var i = 0; i < _mottos.length; i++)
            if (i == index) result else _mottos[i],
        ];
        if (_pinnedMottoId == previousId) {
          _pinnedMottoId = result.id;
        }
      }
    });
    if (_pinnedMottoId == result.id) {
      await widget.repository.savePinnedDailyMottoId(result.id);
    }
    await _save();
  }

  Future<void> _pickPreset() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _presetMottos
              .map(
                (item) => ListTile(
                  title: Text(item),
                  onTap: () => Navigator.of(context).pop(item),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (result == null) return;
    setState(() => _mottos = [..._mottos, DailyMottoEntry.fromLegacy(result)]);
    await _save();
  }

  Future<void> _editSourceUrl() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TemplateNameSheet(
        title: '在线抓取地址',
        fieldLabel: '网页地址',
        actionLabel: '保存',
        initialValue: _sourceUrl,
      ),
    );
    if (!mounted || result == null || result.trim().isEmpty) {
      return;
    }
    setState(() => _sourceUrl = result.trim());
    await widget.repository.saveDailyMottoSourceUrl(_sourceUrl);
    await _fetchFromSource();
  }

  Future<void> _fetchFromSource({bool silentOnFailure = false}) async {
    if (_fetching) {
      return;
    }
    setState(() => _fetching = true);
    try {
      final mottos = await fetchDailyMottosFromUrl(_sourceUrl);
      if (mottos.isEmpty) {
        throw Exception('没有抓到可用内容');
      }
      final entries = mottos.map(DailyMottoEntry.fromLegacy).toList();
      setState(() => _mottos = entries);
      await widget.repository.saveDailyMottoEntries(entries);
      if (_pinnedMottoId != null &&
          !entries.any((item) => item.id == _pinnedMottoId)) {
        _pinnedMottoId = null;
        await widget.repository.savePinnedDailyMottoId(null);
      }
      await widget.repository.saveDailyMottoSourceUrl(_sourceUrl);
      await widget.repository.saveDailyMottoLastFetchDate(
        _dateKey(DateTime.now()),
      );
      if (mounted) {
        VibrantHUD.show(context, '已在线抓取 10 条箴言', type: ToastType.success);
      }
    } catch (error) {
      if (!silentOnFailure && mounted) {
        VibrantHUD.show(context, '$error', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _fetching = false);
      }
    }
  }

  Future<void> _openWebRecognizer() async {
    final result = await Navigator.of(context).push<List<DailyMottoEntry>>(
      MaterialPageRoute(
        builder: (_) => _MottoWebRecognizePage(initialUrl: _sourceUrl),
      ),
    );
    if (!mounted || result == null || result.isEmpty) {
      return;
    }
    final merged = <DailyMottoEntry>[..._mottos, ...result];
    final deduped = <DailyMottoEntry>[];
    for (final item in merged) {
      final existingIndex = deduped.indexWhere(
        (entry) => entry.content.trim() == item.content.trim(),
      );
      if (existingIndex == -1) {
        deduped.add(item);
      } else {
        final existing = deduped[existingIndex];
        deduped[existingIndex] = existing.copyWith(
          author: existing.author?.trim().isNotEmpty == true
              ? existing.author
              : item.author,
          poemTitle: existing.poemTitle?.trim().isNotEmpty == true
              ? existing.poemTitle
              : item.poemTitle,
        );
      }
    }
    setState(() {
      _mottos = deduped;
      if (_pinnedMottoId != null &&
          !deduped.any((item) => item.id == _pinnedMottoId)) {
        _pinnedMottoId = null;
      }
    });
    await widget.repository.saveDailyMottoEntries(deduped);
    if (_pinnedMottoId == null) {
      await widget.repository.savePinnedDailyMottoId(null);
    }
    await widget.repository.saveDailyMottoSourceUrl(_sourceUrl);
    if (!mounted) {
      return;
    }
    VibrantHUD.show(
      context,
      '已识别并保存 ${result.length} 条',
      type: ToastType.success,
    );
  }

  Future<void> _useBingImage() async {
    if (_fetchingImage) {
      return;
    }
    setState(() => _fetchingImage = true);
    try {
      final imageUrl = await fetchDailyMottoImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('没有抓到可用图片');
      }
      await widget.repository.saveDailyMottoImageUrl(imageUrl);
      await widget.repository.saveDailyMottoImagePath(null);
      await widget.repository.saveDailyMottoImageFetchDate(
        _dateKey(DateTime.now()),
      );
      if (!mounted) return;
      setState(() {
        _imageUrl = imageUrl;
        _imagePath = null;
      });
      VibrantHUD.show(context, '已切换到微软每日壁纸', type: ToastType.success);
    } catch (error) {
      if (mounted) {
        VibrantHUD.show(context, '$error', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _fetchingImage = false);
      }
    }
  }

  Future<void> _pickMottoImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }
    await widget.repository.saveDailyMottoImagePath(path);
    if (!mounted) return;
    setState(() => _imagePath = path);
    VibrantHUD.show(context, '已设置箴言图片', type: ToastType.success);
  }

  Future<void> _clearMottoImage() async {
    await widget.repository.saveDailyMottoImagePath(null);
    await widget.repository.saveDailyMottoImageUrl(null);
    if (!mounted) return;
    setState(() {
      _imagePath = null;
      _imageUrl = null;
    });
    VibrantHUD.show(context, '已清除箴言图片', type: ToastType.success);
  }

  String _mottoPreview(String value) {
    final sentences = value
        .split(RegExp(r'(?<=[。！？；：])'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (sentences.isEmpty) {
      return value.trim();
    }
    if (sentences.length <= 2) {
      return sentences.join('\n');
    }
    return '${sentences.take(2).join('\n')}...';
  }

  String _mottoSubtitle(DailyMottoEntry value) {
    final parts = <String>[];
    if (_pinnedMottoId == value.id) {
      parts.add('当前首页显示');
    }
    if (value.author?.trim().isNotEmpty == true ||
        value.poemTitle?.trim().isNotEmpty == true) {
      parts.add(value.attribution);
    }
    return parts.join(' · ');
  }

  void _toggleDeleteSelection(DailyMottoEntry entry) {
    setState(() {
      if (_selectedDeleteIds.contains(entry.id)) {
        _selectedDeleteIds.remove(entry.id);
      } else {
        _selectedDeleteIds.add(entry.id);
      }
    });
  }

  String _autoSwitchLabel() {
    final unitLabel = switch (_autoSwitchUnit) {
      IntervalUnit.seconds => '秒',
      IntervalUnit.minutes => '分钟',
      IntervalUnit.hours => '小时',
      IntervalUnit.days => '天',
    };
    return '$_autoSwitchValue $unitLabel';
  }

  Future<void> _pickAutoSwitchValue() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in const [1, 2, 3, 4, 5, 10, 15, 30, 60])
              ListTile(
                title: Text('$item'),
                trailing: item == _autoSwitchValue
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(item),
              ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _autoSwitchValue = result);
    await widget.repository.saveAutoScrollDailyMottoIntervalValue(result);
  }

  Future<void> _pickAutoSwitchUnit() async {
    final result = await showModalBottomSheet<IntervalUnit>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final unit in IntervalUnit.values)
              ListTile(
                title: Text(switch (unit) {
                  IntervalUnit.seconds => '秒',
                  IntervalUnit.minutes => '分钟',
                  IntervalUnit.hours => '小时',
                  IntervalUnit.days => '天',
                }),
                trailing: unit == _autoSwitchUnit
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(unit),
              ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _autoSwitchUnit = result);
    await widget.repository.saveAutoScrollDailyMottoIntervalUnit(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日箴言'),
        actions: [
          if (_selectingDelete) ...[
            TextButton(
              onPressed: _selectedDeleteIds.isEmpty
                  ? null
                  : _deleteSelectedItems,
              child: Text('删除${_selectedDeleteIds.length}'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectingDelete = false;
                  _selectedDeleteIds.clear();
                });
              },
              child: const Text('取消'),
            ),
          ] else ...[
            TextButton(onPressed: _pickPreset, child: const Text('预设')),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectingDelete = true;
                  _selectedDeleteIds.clear();
                });
              },
              child: const Text('多选删除'),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(),
        label: const Text('新增箴言'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '在线抓取',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sourceUrl,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _editSourceUrl,
                          child: const Text('设置地址'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _fetching ? null : _fetchFromSource,
                          child: Text(_fetching ? '抓取中' : '立即抓取'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openWebRecognizer,
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text('打开网页识别保存'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _fetchingImage ? null : _useBingImage,
                          icon: const Icon(Icons.wallpaper_rounded),
                          label: Text(_fetchingImage ? '更新中' : '微软壁纸'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickMottoImage,
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('图库选择'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('首页显示作者和古诗名'),
                    value: _showMetaOnHome,
                    onChanged: (value) async {
                      setState(() => _showMetaOnHome = value);
                      await widget.repository.saveShowDailyMottoMetaOnHome(
                        value,
                      );
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('首页箴言自动切换'),
                    subtitle: Text('每 ${_autoSwitchLabel()} 切换'),
                    value: _autoSwitchOnHome,
                    onChanged: (value) async {
                      setState(() => _autoSwitchOnHome = value);
                      await widget.repository.saveAutoScrollDailyMottoOnHome(
                        value,
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动切换数值'),
                    subtitle: Text('当前 $_autoSwitchValue'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickAutoSwitchValue,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动切换单位'),
                    subtitle: Text(switch (_autoSwitchUnit) {
                      IntervalUnit.seconds => '秒',
                      IntervalUnit.minutes => '分钟',
                      IntervalUnit.hours => '小时',
                      IntervalUnit.days => '天',
                    }),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickAutoSwitchUnit,
                  ),
                  const SizedBox(height: 6),
                  if (_imagePath != null || _imageUrl != null)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _clearMottoImage,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('清除图片'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '每天首次打开时，会自动从该网页抓取 10 条并保存。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ..._mottos.indexed.map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                onTap: _selectingDelete
                    ? () => _toggleDeleteSelection(item)
                    : null,
                leading: _selectingDelete
                    ? Checkbox(
                        value: _selectedDeleteIds.contains(item.id),
                        onChanged: (_) => _toggleDeleteSelection(item),
                      )
                    : null,
                title: Text(
                  _mottoPreview(item.content),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: _mottoSubtitle(item).isEmpty
                    ? null
                    : Text(_mottoSubtitle(item)),
                trailing: _selectingDelete
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _pinnedMottoId == item.id
                                ? null
                                : () => _setHomeMotto(item),
                            child: const Text('设为首页'),
                          ),
                          const SizedBox(width: 4),
                          _MiniIconButton(
                            onPressed: () =>
                                _editItem(initialEntry: item, index: index),
                            icon: Icons.edit_rounded,
                          ),
                          const SizedBox(width: 8),
                          _MiniIconButton(
                            onPressed: () => _deleteItem(index),
                            icon: Icons.delete_outline_rounded,
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

class _MottoWebRecognizePage extends StatefulWidget {
  const _MottoWebRecognizePage({required this.initialUrl});

  final String initialUrl;

  @override
  State<_MottoWebRecognizePage> createState() => _MottoWebRecognizePageState();
}

class _MottoWebRecognizePageState extends State<_MottoWebRecognizePage> {
  final _webAreaKey = GlobalKey();
  late final WebViewController _controller;
  bool _loading = true;
  bool _recognizing = false;
  bool _selectingRegion = false;
  Offset? _dragStart;
  Rect? _selectedRegion;
  _MottoLineGroupMode _groupMode = _MottoLineGroupMode.quatrain;

  List<String> _groupPoemClauses(List<String> clauses, {int groupSize = 4}) {
    if (clauses.isEmpty) return const [];
    final results = <String>[];
    for (var index = 0; index < clauses.length; index += groupSize) {
      final chunk = clauses.skip(index).take(groupSize).toList();
      if (chunk.isEmpty) continue;
      results.add(chunk.join());
    }
    return results;
  }

  List<String> _applyGroupingMode(List<String> clauses) {
    if (clauses.isEmpty) return const [];
    switch (_groupMode) {
      case _MottoLineGroupMode.couplet:
        return _groupPoemClauses(clauses, groupSize: 2);
      case _MottoLineGroupMode.quatrain:
        return _groupPoemClauses(clauses, groupSize: 4);
      case _MottoLineGroupMode.fullPoem:
        return [clauses.join()];
    }
  }

  @override
  void initState() {
    super.initState();
    final initialUri = Uri.tryParse(widget.initialUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(
        initialUri == null || !initialUri.hasScheme
            ? Uri.parse(_defaultDailyMottoSourceUrl)
            : initialUri,
      );
  }

  List<String> _extractReadableLines(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[|｜]'), '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    final clauses = normalized
        .split(RegExp(r'(?<=[。！？；：])|[\n\r]+'))
        .map((item) => item.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((item) => item.length >= 2 && item.length <= 40)
        .where(
          (item) =>
              !item.contains('文学360') &&
              !item.contains('搜索') &&
              !item.contains('首页') &&
              !item.contains('相关古诗文') &&
              !item.contains('Copyright') &&
              !item.contains('ICP备'),
        )
        .toList();
    final lines = _applyGroupingMode(clauses).expand<String>((item) sync* {
      if (item.length <= 120) {
        yield item;
        return;
      }
      for (var start = 0; start < item.length; start += 60) {
        yield item.substring(start, (start + 60).clamp(0, item.length));
      }
    }).toList();
    final results = <String>[];
    for (final line in lines) {
      if (results.contains(line)) {
        continue;
      }
      results.add(line);
      if (results.length >= 10) {
        break;
      }
    }
    return results;
  }

  List<String> _rawOcrFallbackLines(String text) {
    final results = <String>[];
    for (final raw in text.split(RegExp(r'[\n\r]+'))) {
      final value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (value.isEmpty || results.contains(value)) {
        continue;
      }
      results.add(value.length > 120 ? value.substring(0, 120) : value);
      if (results.length >= 10) {
        break;
      }
    }
    return results;
  }

  ({String? author, String? poemTitle}) _extractMottoMetadata(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final titleMatch = RegExp(r'《([^》]{1,24})》').firstMatch(normalized);
    final authorBeforeTitle = RegExp(
      r'([一-龥]{2,4})\s*《[^》]{1,24}》',
    ).firstMatch(normalized);
    final authorAfterDash = RegExp(r'--\s*([一-龥]{2,4})').firstMatch(normalized);
    final authorAfterLabel = RegExp(
      r'作者[:：]?\s*([一-龥]{2,4})',
    ).firstMatch(normalized);
    final author =
        authorBeforeTitle?.group(1) ??
        authorAfterDash?.group(1) ??
        authorAfterLabel?.group(1);
    return (
      author: author?.trim().isEmpty == true ? null : author?.trim(),
      poemTitle: titleMatch?.group(1)?.trim().isEmpty == true
          ? null
          : titleMatch?.group(1)?.trim(),
    );
  }

  List<DailyMottoEntry> _buildEntries(List<String> lines, String rawText) {
    final meta = _extractMottoMetadata(rawText);
    return lines
        .map(
          (line) => DailyMottoEntry(
            id: dailyMottoEntryId(line),
            content: line.trim(),
            author: meta.author,
            poemTitle: meta.poemTitle,
          ),
        )
        .where((item) => item.content.isNotEmpty)
        .toList();
  }

  Future<String?> _editRecognizedLine(String value) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TemplateNameSheet(
        title: '编辑识别内容',
        fieldLabel: '内容',
        actionLabel: '保存',
        initialValue: value,
        multiline: true,
      ),
    );
  }

  Future<DailyMottoEntry?> _editRecognizedEntry(DailyMottoEntry entry) async {
    return showModalBottomSheet<DailyMottoEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _MottoEntrySheet(title: '编辑识别内容', initialEntry: entry),
    );
  }

  Future<void> _confirmAndPop(List<DailyMottoEntry> lines) async {
    if (!mounted) {
      return;
    }
    if (lines.isEmpty) {
      VibrantHUD.show(context, '当前页面没有识别到可保存内容', type: ToastType.warning);
      return;
    }
    final editedLines = [...lines];
    final confirmed = await showModalBottomSheet<List<DailyMottoEntry>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '识别结果',
                          style: Theme.of(sheetContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${editedLines.length} 条',
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: editedLines.length < 2
                            ? null
                            : () {
                                final mergedContent = editedLines
                                    .map((item) => item.content.trim())
                                    .where((item) => item.isNotEmpty)
                                    .join('\n');
                                final mergedAuthor = editedLines
                                    .map((item) => item.author?.trim() ?? '')
                                    .firstWhere(
                                      (item) => item.isNotEmpty,
                                      orElse: () => '',
                                    );
                                final mergedPoemTitle = editedLines
                                    .map((item) => item.poemTitle?.trim() ?? '')
                                    .firstWhere(
                                      (item) => item.isNotEmpty,
                                      orElse: () => '',
                                    );
                                setSheetState(() {
                                  editedLines
                                    ..clear()
                                    ..add(
                                      DailyMottoEntry(
                                        id: dailyMottoEntryId(mergedContent),
                                        content: mergedContent,
                                        author: mergedAuthor.isEmpty
                                            ? null
                                            : mergedAuthor,
                                        poemTitle: mergedPoemTitle.isEmpty
                                            ? null
                                            : mergedPoemTitle,
                                      ),
                                    );
                                });
                              },
                        icon: const Icon(Icons.merge_type_rounded),
                        label: const Text('合并'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: editedLines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = editedLines[index];
                      return ListTile(
                        dense: true,
                        title: Text(line.content),
                        subtitle: line.attribution.isEmpty
                            ? null
                            : Text(line.attribution),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '编辑',
                              onPressed: () async {
                                final result = await _editRecognizedEntry(line);
                                if (result == null ||
                                    result.content.trim().isEmpty) {
                                  return;
                                }
                                setSheetState(() {
                                  editedLines[index] = result.copyWith(
                                    id: dailyMottoEntryId(
                                      result.content.trim(),
                                    ),
                                    content: result.content.trim(),
                                  );
                                });
                              },
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed: () {
                                setSheetState(() {
                                  editedLines.removeAt(index);
                                });
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: editedLines.isEmpty
                              ? null
                              : () => Navigator.of(sheetContext).pop(
                                  editedLines
                                      .where(
                                        (item) =>
                                            item.content.trim().isNotEmpty,
                                      )
                                      .toList(),
                                ),
                          child: const Text('保存这些内容'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != null && confirmed.isNotEmpty && mounted) {
      Navigator.of(context).pop(confirmed);
    }
  }

  Map<String, Object?>? _selectedRegionAsScreenRatio() {
    final selected = _selectedRegion;
    final context = _webAreaKey.currentContext;
    if (selected == null || context == null) {
      return null;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final screenSize = MediaQuery.sizeOf(context);
    final topLeft = box.localToGlobal(selected.topLeft);
    final bottomRight = box.localToGlobal(selected.bottomRight);
    return {
      'left': (topLeft.dx / screenSize.width).clamp(0.0, 1.0),
      'top': (topLeft.dy / screenSize.height).clamp(0.0, 1.0),
      'right': (bottomRight.dx / screenSize.width).clamp(0.0, 1.0),
      'bottom': (bottomRight.dy / screenSize.height).clamp(0.0, 1.0),
    };
  }

  Future<String> _readDomText() async {
    final raw = await _controller.runJavaScriptReturningResult('''
(() => {
  const selectors = ['.post-body', '.post', 'article', 'main', 'body'];
  for (const selector of selectors) {
    const el = document.querySelector(selector);
    if (el && el.innerText && el.innerText.trim().length > 0) {
      return el.innerText;
    }
  }
  return document.body ? document.body.innerText : '';
})()
''');
    final text = raw.toString();
    return text.startsWith('"') && text.endsWith('"')
        ? text
              .substring(1, text.length - 1)
              .replaceAll(r'\n', '\n')
              .replaceAll(r'\"', '"')
        : text;
  }

  Future<void> _recognizeDomAndSave() async {
    if (_recognizing) {
      return;
    }
    setState(() => _recognizing = true);
    try {
      final normalized = await _readDomText();
      final lines = _extractReadableLines(normalized);
      await _confirmAndPop(_buildEntries(lines, normalized));
    } catch (error) {
      if (mounted) {
        VibrantHUD.show(context, '$error', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _recognizing = false);
      }
    }
  }

  Future<void> _recognizeClipboardAndSave() async {
    if (_recognizing) {
      return;
    }
    setState(() => _recognizing = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final lines = _extractReadableLines(text);
      await _confirmAndPop(
        _buildEntries(lines.isEmpty ? _rawOcrFallbackLines(text) : lines, text),
      );
    } finally {
      if (mounted) {
        setState(() => _recognizing = false);
      }
    }
  }

  Future<void> _recognizeScreenshotAndSave({bool selectedOnly = false}) async {
    if (_recognizing) {
      return;
    }
    final region = selectedOnly ? _selectedRegionAsScreenRatio() : null;
    if (selectedOnly && region == null) {
      VibrantHUD.show(context, '先拖动框选要识别的文字区域', type: ToastType.warning);
      return;
    }
    setState(() => _recognizing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final rows = await AlarmBridge().recognizeScreenText(region: region);
      final text = rows
          .map((item) => (item['text'] ?? '').toString().trim())
          .where((item) => item.isNotEmpty)
          .join('\n');
      final lines = _extractReadableLines(text);
      final fallbackLines = lines.isEmpty ? _rawOcrFallbackLines(text) : lines;
      if (fallbackLines.isEmpty) {
        final domRaw = await _readDomText();
        await _confirmAndPop(
          _buildEntries(_extractReadableLines(domRaw), domRaw),
        );
        return;
      }
      await _confirmAndPop(_buildEntries(fallbackLines, text));
    } catch (error) {
      if (mounted) {
        VibrantHUD.show(context, '$error', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _recognizing = false;
          _selectingRegion = false;
        });
      }
    }
  }

  Widget _regionSelector() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          setState(() {
            _dragStart = details.localPosition;
            _selectedRegion = Rect.fromPoints(
              details.localPosition,
              details.localPosition,
            );
          });
        },
        onPanUpdate: (details) {
          final start = _dragStart;
          if (start == null) {
            return;
          }
          setState(() {
            _selectedRegion = Rect.fromPoints(start, details.localPosition);
          });
        },
        child: CustomPaint(
          painter: _MottoRegionPainter(_selectedRegion),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                '拖动框选文字区域',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网页识别'),
        actions: [
          IconButton(
            onPressed: _controller.reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          KeyedSubtree(
            key: _webAreaKey,
            child: WebViewWidget(controller: _controller),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_selectingRegion) _regionSelector(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('2句一组'),
                      selected: _groupMode == _MottoLineGroupMode.couplet,
                      onSelected: (_) {
                        setState(() {
                          _groupMode = _MottoLineGroupMode.couplet;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('4句一组'),
                      selected: _groupMode == _MottoLineGroupMode.quatrain,
                      onSelected: (_) {
                        setState(() {
                          _groupMode = _MottoLineGroupMode.quatrain;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('整首'),
                      selected: _groupMode == _MottoLineGroupMode.fullPoem,
                      onSelected: (_) {
                        setState(() {
                          _groupMode = _MottoLineGroupMode.fullPoem;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _recognizing ? null : _recognizeDomAndSave,
                    icon: const Icon(Icons.code_rounded),
                    label: const Text('网页文字'),
                  ),
                  FilledButton.icon(
                    onPressed: _recognizing ? null : _recognizeClipboardAndSave,
                    icon: const Icon(Icons.content_paste_go_rounded),
                    label: const Text('剪切板'),
                  ),
                  FilledButton.icon(
                    onPressed: _recognizing
                        ? null
                        : () => _recognizeScreenshotAndSave(),
                    icon: const Icon(Icons.document_scanner_rounded),
                    label: Text(_recognizing ? '识别中' : '截图OCR'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _recognizing
                        ? null
                        : () {
                            if (_selectingRegion && _selectedRegion != null) {
                              _recognizeScreenshotAndSave(selectedOnly: true);
                            } else {
                              setState(() {
                                _selectingRegion = true;
                                _selectedRegion = null;
                              });
                            }
                          },
                    icon: const Icon(Icons.crop_free_rounded),
                    label: Text(_selectingRegion ? '识别框选' : '框选OCR'),
                  ),
                  if (_selectingRegion)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectingRegion = false;
                          _selectedRegion = null;
                        });
                      },
                      child: const Text('取消'),
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

enum _MottoLineGroupMode { couplet, quatrain, fullPoem }

class _MottoRegionPainter extends CustomPainter {
  const _MottoRegionPainter(this.region);

  final Rect? region;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.08);
    canvas.drawRect(Offset.zero & size, overlayPaint);
    final rect = region;
    if (rect == null) {
      return;
    }
    final normalized = Rect.fromLTRB(
      rect.left.clamp(0.0, size.width),
      rect.top.clamp(0.0, size.height),
      rect.right.clamp(0.0, size.width),
      rect.bottom.clamp(0.0, size.height),
    );
    canvas.drawRect(
      normalized,
      Paint()
        ..color = const Color(0xFFFF3B30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRect(normalized, Paint()..color = const Color(0x22FF3B30));
  }

  @override
  bool shouldRepaint(covariant _MottoRegionPainter oldDelegate) {
    return oldDelegate.region != region;
  }
}

class _MottoEntrySheet extends StatefulWidget {
  const _MottoEntrySheet({required this.title, this.initialEntry});

  final String title;
  final DailyMottoEntry? initialEntry;

  @override
  State<_MottoEntrySheet> createState() => _MottoEntrySheetState();
}

class _MottoEntrySheetState extends State<_MottoEntrySheet> {
  late final TextEditingController _contentController;
  late final TextEditingController _authorController;
  late final TextEditingController _poemTitleController;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _authorController = TextEditingController(
      text: widget.initialEntry?.author ?? '',
    );
    _poemTitleController = TextEditingController(
      text: widget.initialEntry?.poemTitle ?? '',
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    _poemTitleController.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      DailyMottoEntry(
        id: widget.initialEntry?.id ?? dailyMottoEntryId(content),
        content: content,
        author: _authorController.text.trim().isEmpty
            ? null
            : _authorController.text.trim(),
        poemTitle: _poemTitleController.text.trim().isEmpty
            ? null
            : _poemTitleController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(16, 4, 16, viewInsets.bottom + 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _contentController,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(labelText: '${widget.title}内容'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _authorController,
                    decoration: const InputDecoration(labelText: '作者名'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _poemTitleController,
                    decoration: const InputDecoration(labelText: '古诗名'),
                  ),
                  const SizedBox(height: 12),
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
                        child: FilledButton.tonal(
                          onPressed: _submit,
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
    );
  }
}

class _TemplateNameSheet extends StatefulWidget {
  const _TemplateNameSheet({
    required this.title,
    required this.fieldLabel,
    required this.actionLabel,
    this.initialValue = '',
    this.multiline = false,
  });

  final String title;
  final String fieldLabel;
  final String actionLabel;
  final String initialValue;
  final bool multiline;

  @override
  State<_TemplateNameSheet> createState() => _TemplateNameSheetState();
}

class _TemplateNameSheetState extends State<_TemplateNameSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(16, 4, 16, viewInsets.bottom + 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.58),
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: theme.brightness == Brightness.dark
                              ? const [Color(0xFF1A2C2A), Color(0xFF1A2232)]
                              : const [Color(0xFFE7F7F1), Color(0xFFE8F0FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('template_name_field'),
                      controller: _controller,
                      autofocus: true,
                      keyboardType: widget.multiline
                          ? TextInputType.multiline
                          : TextInputType.text,
                      textInputAction: widget.multiline
                          ? TextInputAction.newline
                          : TextInputAction.done,
                      onSubmitted: widget.multiline ? null : (_) => _submit(),
                      minLines: widget.multiline ? 4 : 1,
                      maxLines: widget.multiline ? 8 : 1,
                      decoration: InputDecoration(labelText: widget.fieldLabel),
                    ),
                    const SizedBox(height: 12),
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
                          child: FilledButton.tonal(
                            key: const ValueKey('template_name_submit_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  theme.brightness == Brightness.dark
                                  ? const Color(0xFF1F3D39)
                                  : const Color(0xFFDDF5EC),
                              foregroundColor:
                                  theme.brightness == Brightness.dark
                                  ? const Color(0xFF94DFC9)
                                  : const Color(0xFF2F7D6B),
                            ),
                            onPressed: _submit,
                            child: Text(widget.actionLabel),
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
}
