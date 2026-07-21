import 'dart:async';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../theme/app_theme.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.readingStore,
  });

  final Book book;
  final ReadingStore readingStore;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _chapterIndex;
  late double _fontSize;
  late double _lineHeight;
  late Color _background;
  late TextAlign _alignment;
  late bool _eyeCare;
  bool _showControls = true;
  late String _pageTurn;
  late double _liveProgress;
  final ScrollController _scrollController = ScrollController();
  final DateTime _openedAt = DateTime.now();
  Timer? _progressTimer;
  String _selectedText = '';

  Chapter get _chapter => widget.book.chapters[_chapterIndex];

  Color get _effectiveBackground =>
      _eyeCare ? const Color(0xFFEAF2E4) : _background;

  @override
  void initState() {
    super.initState();
    final state = widget.readingStore.stateFor(widget.book);
    final preferences = widget.readingStore.readerPreferences;
    _chapterIndex = state.chapterIndex.clamp(
      0,
      widget.book.chapters.length - 1,
    );
    _fontSize = preferences.fontSize;
    _lineHeight = preferences.lineHeight;
    _background = Color(preferences.backgroundValue);
    _alignment = preferences.alignment;
    _eyeCare = preferences.eyeCare;
    _pageTurn = preferences.pageTurn;
    _liveProgress = state.progress;
    _scrollController.addListener(_queueProgressUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePosition());
  }

  void _restorePosition() {
    if (!_scrollController.hasClients || widget.book.chapters.isEmpty) return;
    final withinChapter =
        (_liveProgress * widget.book.chapters.length - _chapterIndex).clamp(
          0.0,
          1.0,
        );
    _scrollController.jumpTo(
      _scrollController.position.maxScrollExtent * withinChapter,
    );
  }

  void _queueProgressUpdate() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 180), _commitProgress);
  }

  void _commitProgress({bool rebuild = true}) {
    if (!_scrollController.hasClients || widget.book.chapters.isEmpty) return;
    final max = _scrollController.position.maxScrollExtent;
    final local = max <= 0
        ? 0.0
        : (_scrollController.offset / max).clamp(0.0, 1.0);
    final overall = ((_chapterIndex + local) / widget.book.chapters.length)
        .clamp(0.0, 1.0);
    if (rebuild && mounted) setState(() => _liveProgress = overall);
    widget.readingStore.updateProgress(widget.book, overall, _chapterIndex);
  }

  void _selectChapter(int index) {
    setState(() {
      _chapterIndex = index;
      _liveProgress = index / widget.book.chapters.length;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    widget.readingStore.updateProgress(
      widget.book,
      _liveProgress,
      _chapterIndex,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _commitProgress(rebuild: false);
    widget.readingStore.recordSession(
      widget.book,
      DateTime.now().difference(_openedAt),
    );
    _scrollController.dispose();
    super.dispose();
  }

  void _showChapterList() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        minChildSize: .55,
        maxChildSize: .94,
        builder: (context, controller) => Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD8DCE2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 5, 12, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const Expanded(
                    child: Text(
                      '目录',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.sort_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.book.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.book.author,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 4,
                ),
                itemCount: widget.book.chapters.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final selected = index == _chapterIndex;
                  return ListTile(
                    key: ValueKey('chapter-$index'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 54,
                    onTap: () {
                      _selectChapter(index);
                      Navigator.pop(context);
                    },
                    title: Text(
                      widget.book.chapters[index].title,
                      style: TextStyle(
                        color: selected ? AppColors.accent : AppColors.ink,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.readingStore
                            .stateFor(widget.book)
                            .bookmarkedChapters
                            .contains(index))
                          const Icon(
                            Icons.bookmark_rounded,
                            color: AppColors.accent,
                            size: 17,
                          ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.circle,
                            color: AppColors.accent,
                            size: 10,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ReaderSettingsSheet(
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        background: _background,
        alignment: _alignment,
        eyeCare: _eyeCare,
        pageTurn: _pageTurn,
        onChanged: (settings) {
          setState(() {
            _fontSize = settings.fontSize;
            _lineHeight = settings.lineHeight;
            _background = settings.background;
            _alignment = settings.alignment;
            _eyeCare = settings.eyeCare;
            _pageTurn = settings.pageTurn;
          });
          widget.readingStore.updateReaderPreferences(
            ReaderPreferences(
              fontSize: settings.fontSize,
              lineHeight: settings.lineHeight,
              backgroundValue: settings.background.toARGB32(),
              alignment: settings.alignment,
              eyeCare: settings.eyeCare,
              pageTurn: settings.pageTurn,
            ),
          );
        },
      ),
    );
  }

  Future<void> _addAnnotation() async {
    final selected = _selectedText.trim();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先长按并选中一段文字')));
      return;
    }
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加批注'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 110),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  selected,
                  style: const TextStyle(color: AppColors.secondary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('annotation-note-field'),
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '写下你的想法（可留空）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('save-annotation-button'),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;
    widget.readingStore.addAnnotation(
      widget.book,
      BookAnnotation(
        chapterIndex: _chapterIndex,
        selectedText: selected,
        note: note,
        createdAt: DateTime.now(),
      ),
    );
    setState(() => _selectedText = '');
  }

  void _showAnnotations() {
    final annotations = widget.readingStore.stateFor(widget.book).annotations;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 4, 22, 14),
                child: Text(
                  '我的批注',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: annotations.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有批注',
                          style: TextStyle(color: AppColors.secondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: annotations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final annotation = annotations[index];
                          return ListTile(
                            isThreeLine: annotation.note.isNotEmpty,
                            title: Text(
                              '“${annotation.selectedText}”',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: annotation.note.isEmpty
                                ? Text('第 ${annotation.chapterIndex + 1} 章')
                                : Text(
                                    annotation.note,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: IconButton(
                              tooltip: '删除批注',
                              onPressed: () {
                                widget.readingStore.removeAnnotation(
                                  widget.book,
                                  annotation,
                                );
                                Navigator.pop(sheetContext);
                                _showAnnotations();
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapterProgress = _liveProgress;

    return Scaffold(
      backgroundColor: _effectiveBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('reader-page'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showControls = !_showControls),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(34, 92, 34, 90),
                  child: SelectionArea(
                    onSelectionChanged: (content) {
                      _selectedText = content?.plainText ?? '';
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _chapter.title,
                          style: TextStyle(
                            fontSize: _fontSize * .78,
                            color: AppColors.secondary,
                            letterSpacing: .4,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          _chapter.content,
                          textAlign: _alignment,
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: _lineHeight,
                            color: const Color(0xFF34363A),
                            letterSpacing: .35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 4,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('reader-back'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      widget.book.title,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '阅读设置',
                    onPressed: _showSettings,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _showControls
                        ? Container(
                            key: const ValueKey('reader-controls'),
                            margin: const EdgeInsets.only(bottom: 13),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .92),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .06),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                _ReaderAction(
                                  key: const ValueKey('catalog-button'),
                                  icon: Icons.format_list_bulleted_rounded,
                                  label: '目录',
                                  onTap: _showChapterList,
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: AppColors.line,
                                ),
                                _ReaderAction(
                                  key: const ValueKey('settings-button'),
                                  icon: Icons.text_fields_rounded,
                                  label: '设置',
                                  onTap: _showSettings,
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: AppColors.line,
                                ),
                                _ReaderAction(
                                  key: const ValueKey('bookmark-button'),
                                  icon:
                                      widget.readingStore
                                          .stateFor(widget.book)
                                          .bookmarkedChapters
                                          .contains(_chapterIndex)
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  label: '书签',
                                  onTap: () {
                                    widget.readingStore.toggleBookmark(
                                      widget.book,
                                      _chapterIndex,
                                    );
                                    setState(() {});
                                  },
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: AppColors.line,
                                ),
                                _ReaderAction(
                                  key: const ValueKey('annotation-button'),
                                  icon: _selectedText.trim().isEmpty
                                      ? Icons.comment_outlined
                                      : Icons.add_comment_rounded,
                                  label: _selectedText.trim().isEmpty
                                      ? '批注'
                                      : '添加',
                                  onTap: _selectedText.trim().isEmpty
                                      ? _showAnnotations
                                      : _addAnnotation,
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('reader-controls-hidden'),
                          ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${(chapterProgress.clamp(0, 1) * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            value: chapterProgress.clamp(0, 1),
                            backgroundColor: AppColors.line,
                            color: AppColors.secondary.withValues(alpha: .45),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '20:41',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.battery_5_bar_rounded,
                        size: 15,
                        color: AppColors.secondary,
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

class _ReaderAction extends StatelessWidget {
  const _ReaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderSettings {
  const ReaderSettings({
    required this.fontSize,
    required this.lineHeight,
    required this.background,
    required this.alignment,
    required this.eyeCare,
    required this.pageTurn,
  });

  final double fontSize;
  final double lineHeight;
  final Color background;
  final TextAlign alignment;
  final bool eyeCare;
  final String pageTurn;
}

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.fontSize,
    required this.lineHeight,
    required this.background,
    required this.alignment,
    required this.eyeCare,
    required this.pageTurn,
    required this.onChanged,
  });

  final double fontSize;
  final double lineHeight;
  final Color background;
  final TextAlign alignment;
  final bool eyeCare;
  final String pageTurn;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late double _fontSize = widget.fontSize;
  late double _lineHeight = widget.lineHeight;
  late Color _background = widget.background;
  late TextAlign _alignment = widget.alignment;
  late bool _eyeCare = widget.eyeCare;
  late String _pageTurn = widget.pageTurn;

  static const _backgrounds = [
    Color(0xFFF8F7F3),
    Color(0xFFF7EEDC),
    Color(0xFFE6F0E4),
    Color(0xFFEFF0F2),
    Color(0xFF303136),
  ];

  void _emit() {
    widget.onChanged(
      ReaderSettings(
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        background: _background,
        alignment: _alignment,
        eyeCare: _eyeCare,
        pageTurn: _pageTurn,
      ),
    );
  }

  void _update(VoidCallback change) {
    setState(change);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        26,
        12,
        26,
        26 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFD8DCE2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              const Expanded(
                child: Text(
                  '阅读设置',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 25),
          const _SettingTitle(title: '字体', trailing: '系统字体  ›'),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('A−', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Slider(
                  key: const ValueKey('font-size-slider'),
                  value: _fontSize,
                  min: 14,
                  max: 26,
                  divisions: 12,
                  onChanged: (value) => _update(() => _fontSize = value),
                ),
              ),
              const Text('A+', style: TextStyle(fontSize: 16)),
            ],
          ),
          Text(
            _fontSize.round().toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.secondary),
          ),
          const SizedBox(height: 24),
          const _SettingTitle(title: '背景'),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _backgrounds.map((color) {
              final selected = color == _background;
              return GestureDetector(
                key: ValueKey('background-${color.toARGB32()}'),
                onTap: () => _update(() {
                  _background = color;
                  _eyeCare = false;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.line,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: .12),
                              blurRadius: 9,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
          const _SettingTitle(title: '间距'),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final spacing in [1.55, 1.9, 2.2]) ...[
                Expanded(
                  child: _SpacingButton(
                    value: spacing,
                    selected: _lineHeight == spacing,
                    onTap: () => _update(() => _lineHeight = spacing),
                  ),
                ),
                if (spacing != 2.2) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 25),
          const _SettingTitle(title: '对齐方式'),
          const SizedBox(height: 12),
          SegmentedButton<TextAlign>(
            segments: const [
              ButtonSegment(
                value: TextAlign.left,
                icon: Icon(Icons.format_align_left_rounded),
              ),
              ButtonSegment(
                value: TextAlign.center,
                icon: Icon(Icons.format_align_center_rounded),
              ),
              ButtonSegment(
                value: TextAlign.justify,
                icon: Icon(Icons.format_align_justify_rounded),
              ),
            ],
            selected: {_alignment},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                _update(() => _alignment = value.first),
          ),
          const SizedBox(height: 14),
          _SettingsRow(
            title: '翻页动画',
            trailing: DropdownButton<String>(
              value: _pageTurn,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: '左右滑动', child: Text('左右滑动')),
                DropdownMenuItem(value: '仿真翻页', child: Text('仿真翻页')),
                DropdownMenuItem(value: '上下滚动', child: Text('上下滚动')),
              ],
              onChanged: (value) {
                if (value != null) _update(() => _pageTurn = value);
              },
            ),
          ),
          _SettingsRow(
            title: '护眼模式',
            trailing: Switch(
              key: const ValueKey('eye-care-switch'),
              value: _eyeCare,
              onChanged: (value) => _update(() => _eyeCare = value),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTitle extends StatelessWidget {
  const _SettingTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(fontSize: 13, color: AppColors.secondary),
          ),
      ],
    );
  }
}

class _SpacingButton extends StatelessWidget {
  const _SpacingButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: .1)
          : AppColors.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Icon(
            value == 1.55
                ? Icons.density_small_rounded
                : value == 1.9
                ? Icons.density_medium_rounded
                : Icons.density_large_rounded,
            color: selected ? AppColors.accent : AppColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}
