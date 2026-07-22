import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart' as fh;
import 'package:flutter_html_svg/flutter_html_svg.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../services/document_service.dart';
import '../theme/app_theme.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.readingStore,
    this.initialChapterIndex,
    this.initialCharacterOffset,
  });

  final Book book;
  final ReadingStore readingStore;
  final int? initialChapterIndex;
  final int? initialCharacterOffset;

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
  late double _restoreChapterProgress;
  late int _restoreCharacterOffset;
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  final FlutterTts _tts = FlutterTts();
  final DateTime _openedAt = DateTime.now();
  Timer? _progressTimer;
  String _selectedText = '';
  Timer? _autoScrollTimer;
  bool _autoScrolling = false;
  bool _speaking = false;
  List<_TextPage> _textPages = const [];
  String _paginationKey = '';
  int _pageIndex = 0;
  bool _turningChapter = false;

  Chapter get _chapter => widget.book.chapters[_chapterIndex];

  Color get _effectiveBackground =>
      _eyeCare ? const Color(0xFFEAF2E4) : _background;

  Color get _readerForeground =>
      ThemeData.estimateBrightnessForColor(_effectiveBackground) ==
          Brightness.dark
      ? const Color(0xFFF2F0EA)
      : const Color(0xFF34363A);

  Color get _readerSecondary => _readerForeground.withValues(alpha: .62);

  int get _currentCharacterOffset {
    if (_isPaged && _textPages.isNotEmpty) {
      return _textPages[_pageIndex.clamp(0, _textPages.length - 1)].start;
    }
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent <= 0) {
      return 0;
    }
    final local =
        (_scrollController.offset / _scrollController.position.maxScrollExtent)
            .clamp(0.0, 1.0);
    return (_chapter.content.length * local).round();
  }

  int _selectedTextOffset() {
    final selected = _selectedText.trim();
    if (selected.isEmpty) return _currentCharacterOffset;
    final matches = RegExp(
      RegExp.escape(selected),
    ).allMatches(_chapter.content).map((match) => match.start).toList();
    if (matches.isEmpty) return _currentCharacterOffset;
    final estimate = _currentCharacterOffset;
    matches.sort(
      (a, b) => (a - estimate).abs().compareTo((b - estimate).abs()),
    );
    return matches.first;
  }

  @override
  void initState() {
    super.initState();
    final state = widget.readingStore.stateFor(widget.book);
    final preferences = widget.readingStore.readerPreferences;
    _chapterIndex = (widget.initialChapterIndex ?? state.chapterIndex).clamp(
      0,
      widget.book.chapters.length - 1,
    );
    _fontSize = preferences.fontSize;
    _lineHeight = preferences.lineHeight;
    _background = Color(preferences.backgroundValue);
    _alignment = preferences.alignment;
    _eyeCare = preferences.eyeCare;
    _pageTurn = preferences.pageTurn == '仿真翻页' ? '左右滑动' : preferences.pageTurn;
    _liveProgress = state.progress;
    _restoreChapterProgress = state.chapterProgress;
    _restoreCharacterOffset =
        widget.initialCharacterOffset ?? state.characterOffset;
    _scrollController.addListener(_queueProgressUpdate);
    _tts
      ..setStartHandler(() {
        if (mounted) setState(() => _speaking = true);
      })
      ..setCompletionHandler(() {
        if (mounted) setState(() => _speaking = false);
      })
      ..setCancelHandler(() {
        if (mounted) setState(() => _speaking = false);
      })
      ..setErrorHandler((_) {
        if (mounted) setState(() => _speaking = false);
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePosition());
  }

  void _restorePosition() {
    if (!_scrollController.hasClients || widget.book.chapters.isEmpty) return;
    final contentLength = _chapter.content.length;
    final characterProgress =
        contentLength <= 0 ||
            (_restoreCharacterOffset == 0 && _restoreChapterProgress > 0)
        ? _restoreChapterProgress
        : (_restoreCharacterOffset / contentLength).clamp(0.0, 1.0);
    _scrollController.jumpTo(
      _scrollController.position.maxScrollExtent * characterProgress,
    );
  }

  void _queueProgressUpdate() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 180), _commitProgress);
  }

  bool get _isPaged => _pageTurn != '上下滚动';

  Future<void> _toggleSpeech() async {
    if (_speaking) {
      await _tts.stop();
      return;
    }
    final offset = _isPaged && _textPages.isNotEmpty
        ? _textPages[_pageIndex.clamp(0, _textPages.length - 1)].start
        : _currentCharacterOffset;
    final content = _chapter.content.substring(
      offset.clamp(0, _chapter.content.length),
    );
    if (content.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本章已经读完')));
      }
      return;
    }
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(.48);
      await _tts.awaitSpeakCompletion(true);
      final result = await _tts.speak(content);
      if (result != 1) throw StateError('TTS did not start');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('系统朗读暂时不可用')));
      }
    }
  }

  void _toggleAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_autoScrolling || _isPaged) {
      setState(() => _autoScrolling = false);
      return;
    }
    setState(() => _autoScrolling = true);
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 45), (_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) {
        _autoScrollTimer?.cancel();
        setState(() => _autoScrolling = false);
        return;
      }
      _scrollController.jumpTo(
        (position.pixels + .7).clamp(0, position.maxScrollExtent),
      );
    });
  }

  Future<void> _showReaderTools() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('全文搜索'),
              onTap: () => Navigator.pop(context, 'search'),
            ),
            ListTile(
              enabled: !_isPaged,
              leading: Icon(
                _autoScrolling
                    ? Icons.pause_circle_outline_rounded
                    : Icons.slow_motion_video_rounded,
              ),
              title: Text(_autoScrolling ? '停止自动滚动' : '自动滚动'),
              subtitle: _isPaged ? const Text('仅上下滚动模式可用') : null,
              onTap: () => Navigator.pop(context, 'auto'),
            ),
            ListTile(
              leading: Icon(
                _speaking
                    ? Icons.stop_circle_outlined
                    : Icons.record_voice_over_outlined,
              ),
              title: Text(_speaking ? '停止朗读' : '朗读本章'),
              onTap: () => Navigator.pop(context, 'speech'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'search':
        await _showSearch();
        return;
      case 'auto':
        _toggleAutoScroll();
        return;
      case 'speech':
        await _toggleSpeech();
        return;
      case null:
        return;
    }
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
    widget.readingStore.updateProgress(
      widget.book,
      overall,
      _chapterIndex,
      chapterProgress: local,
      characterOffset: (_chapter.content.length * local).round(),
    );
  }

  void _jumpToOffset(int chapterIndex, int characterOffset) {
    final chapter = widget.book.chapters[chapterIndex];
    final offset = characterOffset.clamp(0, chapter.content.length);
    setState(() {
      _chapterIndex = chapterIndex;
      _restoreCharacterOffset = offset;
      _restoreChapterProgress = chapter.content.isEmpty
          ? 0
          : offset / chapter.content.length;
      _liveProgress =
          (chapterIndex + _restoreChapterProgress) /
          widget.book.chapters.length;
    });
    _paginationKey = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restorePosition();
      widget.readingStore.updateProgress(
        widget.book,
        _liveProgress,
        chapterIndex,
        chapterProgress: _restoreChapterProgress,
        characterOffset: offset,
      );
    });
  }

  void _seekOverall(double value) {
    final scaled = value.clamp(0.0, .999999) * widget.book.chapters.length;
    final chapterIndex = scaled.floor().clamp(
      0,
      widget.book.chapters.length - 1,
    );
    final local = scaled - chapterIndex;
    final offset = (widget.book.chapters[chapterIndex].content.length * local)
        .round();
    _jumpToOffset(chapterIndex, offset);
  }

  Future<void> _showSearch() async {
    final result = await showSearch<_ReaderSearchResult?>(
      context: context,
      delegate: _ReaderSearchDelegate(widget.book, widget.readingStore),
    );
    if (result != null) {
      _jumpToOffset(result.chapterIndex, result.characterOffset);
    }
  }

  Future<void> _openLink(String? value) async {
    if (value == null || value.isEmpty) return;
    final targetPath = value.split('#').first;
    if (value.startsWith('#') || targetPath.isNotEmpty) {
      final currentPath = _chapter.sourceHref ?? '';
      final chapterIndex = value.startsWith('#')
          ? _chapterIndex
          : widget.book.chapters.indexWhere(
              (chapter) =>
                  chapter.sourceHref == targetPath ||
                  chapter.sourceHref?.endsWith('/$targetPath') == true,
            );
      if (chapterIndex >= 0 &&
          (value.startsWith('#') || currentPath.isNotEmpty)) {
        _jumpToOffset(chapterIndex, 0);
        return;
      }
    }
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('这个书内链接无法定位')));
      }
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开这个链接')));
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _autoScrollTimer?.cancel();
    _tts.stop();
    _commitProgress(rebuild: false);
    widget.readingStore.recordSession(
      widget.book,
      DateTime.now().difference(_openedAt),
    );
    _scrollController.dispose();
    _pageController.dispose();
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
                    tooltip: '搜索全文',
                    onPressed: () {
                      Navigator.pop(context);
                      _showSearch();
                    },
                    icon: const Icon(Icons.search_rounded),
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
                itemCount: widget.book.navigation.isEmpty
                    ? widget.book.chapters.length
                    : widget.book.navigation.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final navigation = widget.book.navigation.isEmpty
                      ? null
                      : widget.book.navigation[index];
                  final targetChapter = navigation?.chapterIndex ?? index;
                  final selected = targetChapter == _chapterIndex;
                  return ListTile(
                    key: ValueKey('chapter-$index'),
                    minTileHeight: 54,
                    onTap: () {
                      _jumpToOffset(
                        targetChapter,
                        navigation?.characterOffset ?? 0,
                      );
                      Navigator.pop(context);
                    },
                    title: Text(
                      navigation?.label ?? widget.book.chapters[index].title,
                      style: TextStyle(
                        color: selected ? AppColors.accent : AppColors.ink,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    contentPadding: EdgeInsets.only(
                      left: (navigation?.depth ?? 0) * 16.0,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.readingStore
                            .stateFor(widget.book)
                            .bookmarkedChapters
                            .contains(targetChapter))
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
          final modeChanged = settings.pageTurn != _pageTurn;
          if (modeChanged) {
            _restoreCharacterOffset = _currentCharacterOffset;
            _restoreChapterProgress = _chapter.content.isEmpty
                ? 0
                : _restoreCharacterOffset / _chapter.content.length;
            _autoScrollTimer?.cancel();
            _autoScrolling = false;
            _paginationKey = '';
          }
          setState(() {
            _fontSize = settings.fontSize;
            _lineHeight = settings.lineHeight;
            _background = settings.background;
            _alignment = settings.alignment;
            _eyeCare = settings.eyeCare;
            _pageTurn = settings.pageTurn;
          });
          final preferences = widget.readingStore.readerPreferences;
          widget.readingStore.updateReaderPreferences(
            preferences.copyWith(
              fontSize: settings.fontSize,
              lineHeight: settings.lineHeight,
              backgroundValue: settings.background.toARGB32(),
              alignment: settings.alignment,
              eyeCare: settings.eyeCare,
              pageTurn: settings.pageTurn,
            ),
          );
          if (modeChanged && settings.pageTurn == '上下滚动') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _restorePosition();
            });
          }
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
        chapterProgress:
            _scrollController.hasClients &&
                _scrollController.position.maxScrollExtent > 0
            ? (_scrollController.offset /
                      _scrollController.position.maxScrollExtent)
                  .clamp(0, 1)
            : 0,
        characterStart: _selectedTextOffset(),
        characterEnd: _selectedTextOffset() + selected.length,
        selectedText: selected,
        note: note,
        createdAt: DateTime.now(),
      ),
    );
    setState(() => _selectedText = '');
  }

  void _showAnnotations() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: widget.readingStore,
        builder: (context, _) {
          final annotations = widget.readingStore
              .stateFor(widget.book)
              .annotations;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 10, 14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '我的批注',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '导出批注',
                          onPressed: annotations.isEmpty
                              ? null
                              : _exportAnnotations,
                          icon: const Icon(Icons.ios_share_rounded),
                        ),
                      ],
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
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final annotation = annotations[index];
                              return ListTile(
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _jumpToOffset(
                                    annotation.chapterIndex,
                                    annotation.characterStart,
                                  );
                                },
                                onLongPress: () => _editAnnotation(annotation),
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
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editAnnotation(annotation);
                                    }
                                    if (value == 'delete') {
                                      widget.readingStore.removeAnnotation(
                                        widget.book,
                                        annotation,
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('编辑'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除'),
                                    ),
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
        },
      ),
    );
  }

  Future<void> _editAnnotation(BookAnnotation annotation) async {
    final controller = TextEditingController(text: annotation.note);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑批注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    widget.readingStore.updateAnnotation(
      widget.book,
      BookAnnotation(
        id: annotation.id,
        chapterIndex: annotation.chapterIndex,
        chapterProgress: annotation.chapterProgress,
        characterStart: annotation.characterStart,
        characterEnd: annotation.characterEnd,
        selectedText: annotation.selectedText,
        note: note,
        createdAt: annotation.createdAt,
      ),
    );
  }

  Future<void> _exportAnnotations() async {
    try {
      final saved = await DocumentService.saveText(
        name: '${widget.book.title}-批注.md',
        content: widget.readingStore.exportAnnotations(widget.book),
        mimeType: 'text/markdown',
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('批注已导出')));
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('批注导出失败')));
      }
    }
  }

  Widget _buildReadingBody() {
    if (!_isPaged) return _buildScrollingBody();
    return LayoutBuilder(
      builder: (context, constraints) => _buildPagedBody(constraints),
    );
  }

  Widget _buildScrollingBody() => GestureDetector(
    key: const ValueKey('reader-page'),
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _showControls = !_showControls),
    child: SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(34, 92, 34, 90),
      child: SelectionArea(
        onSelectionChanged: (content) {
          final selected = content?.plainText ?? '';
          if (selected != _selectedText && mounted) {
            setState(() => _selectedText = selected);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _chapter.title,
              style: TextStyle(
                fontSize: _fontSize * .78,
                color: _readerSecondary,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 26),
            if (_chapter.hasRichContent)
              fh.Html(
                key: ValueKey('rich-chapter-$_chapterIndex'),
                data: _chapter.html,
                extensions: const [TableHtmlExtension(), SvgHtmlExtension()],
                onLinkTap: (url, _, _) => _openLink(url),
                style: {
                  'body': fh.Style(
                    margin: fh.Margins.zero,
                    padding: fh.HtmlPaddings.zero,
                    fontSize: fh.FontSize(_fontSize),
                    lineHeight: fh.LineHeight.number(_lineHeight),
                    color: _readerForeground,
                    textAlign: _alignment,
                  ),
                  'img': fh.Style(width: fh.Width.auto()),
                  'table': fh.Style(
                    backgroundColor: Colors.white.withValues(alpha: .35),
                  ),
                  'blockquote': fh.Style(
                    border: const Border(
                      left: BorderSide(color: AppColors.secondary, width: 3),
                    ),
                    padding: fh.HtmlPaddings.only(left: 14),
                  ),
                  'pre': fh.Style(
                    whiteSpace: fh.WhiteSpace.pre,
                    fontFamily: 'monospace',
                  ),
                },
              )
            else
              Text(
                _chapter.content,
                textAlign: _alignment,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: _lineHeight,
                  color: _readerForeground,
                  letterSpacing: .35,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _buildPagedBody(BoxConstraints constraints) {
    final pageStyle = TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      color: _readerForeground,
      letterSpacing: .35,
    );
    final width = (constraints.maxWidth - 68).clamp(120.0, double.infinity);
    final height = (constraints.maxHeight - 190).clamp(120.0, double.infinity);
    final key = '$_chapterIndex:$width:$height:$_fontSize:$_lineHeight';
    if (key != _paginationKey) {
      _paginationKey = key;
      _textPages = _paginateText(
        _chapter.content,
        width: width,
        height: height,
        style: pageStyle,
      );
      _pageIndex = _textPages.indexWhere(
        (page) =>
            _restoreCharacterOffset >= page.start &&
            _restoreCharacterOffset < page.end,
      );
      if (_pageIndex < 0) _pageIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_pageIndex);
        }
      });
    }

    return GestureDetector(
      key: const ValueKey('reader-page'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showControls = !_showControls),
      child: NotificationListener<OverscrollNotification>(
        onNotification: (notification) {
          if (_turningChapter || notification.overscroll.abs() < 12) {
            return false;
          }
          if (notification.overscroll > 0 &&
              _pageIndex == _textPages.length - 1 &&
              _chapterIndex < widget.book.chapters.length - 1) {
            _turningChapter = true;
            _jumpToOffset(_chapterIndex + 1, 0);
          } else if (notification.overscroll < 0 &&
              _pageIndex == 0 &&
              _chapterIndex > 0) {
            _turningChapter = true;
            final previous = widget.book.chapters[_chapterIndex - 1];
            _jumpToOffset(_chapterIndex - 1, previous.content.length);
          }
          if (_turningChapter) {
            Future<void>.delayed(const Duration(milliseconds: 350), () {
              _turningChapter = false;
            });
          }
          return false;
        },
        child: PageView.builder(
          key: ValueKey('paged-$_chapterIndex-$key'),
          controller: _pageController,
          itemCount: _textPages.length,
          onPageChanged: (index) {
            final page = _textPages[index];
            final local = _chapter.content.isEmpty
                ? 0.0
                : page.start / _chapter.content.length;
            final overall =
                (_chapterIndex + local) / widget.book.chapters.length;
            setState(() {
              _pageIndex = index;
              _liveProgress = overall;
              _restoreCharacterOffset = page.start;
              _restoreChapterProgress = local;
            });
            widget.readingStore.updateProgress(
              widget.book,
              overall,
              _chapterIndex,
              chapterProgress: local,
              characterOffset: page.start,
            );
          },
          itemBuilder: (context, index) {
            final page = _textPages[index];
            return Padding(
              padding: const EdgeInsets.fromLTRB(34, 86, 34, 86),
              child: SelectionArea(
                onSelectionChanged: (content) {
                  final selected = content?.plainText ?? '';
                  if (selected != _selectedText && mounted) {
                    setState(() => _selectedText = selected);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (index == 0) ...[
                      Text(
                        _chapter.title,
                        style: TextStyle(
                          fontSize: _fontSize * .78,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(page.text, textAlign: _alignment, style: pageStyle),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<_TextPage> _paginateText(
    String content, {
    required double width,
    required double height,
    required TextStyle style,
  }) {
    if (content.isEmpty) return const [_TextPage(start: 0, end: 0, text: '')];
    final pages = <_TextPage>[];
    var start = 0;
    while (start < content.length) {
      var low = start + 1;
      var high = content.length;
      var best = low;
      while (low <= high) {
        final middle = low + ((high - low) >> 1);
        final painter = TextPainter(
          text: TextSpan(text: content.substring(start, middle), style: style),
          textDirection: TextDirection.ltr,
          textAlign: _alignment,
        )..layout(maxWidth: width);
        if (painter.height <= height) {
          best = middle;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      if (best < content.length) {
        final boundary = content.lastIndexOf(RegExp(r'[\n。！？.!?；;]'), best);
        if (boundary > start + 40) best = boundary + 1;
      }
      if (best <= start) best = (start + 1).clamp(0, content.length);
      pages.add(
        _TextPage(
          start: start,
          end: best,
          text: content.substring(start, best).trim(),
        ),
      );
      start = best;
      while (start < content.length && RegExp(r'\s').hasMatch(content[start])) {
        start++;
      }
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book.chapters.isEmpty) {
      return const Scaffold(body: Center(child: Text('这本书没有可阅读的正文')));
    }
    final chapterProgress = _liveProgress;

    return Scaffold(
      backgroundColor: _effectiveBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildReadingBody()),
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
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        widget.book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: _readerSecondary),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '阅读工具',
                    onPressed: _showReaderTools,
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
                                      characterOffset: _currentCharacterOffset,
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
                        child: Slider(
                          key: const ValueKey('reader-progress-slider'),
                          value: chapterProgress.clamp(0, 1),
                          onChanged: (value) {
                            setState(() => _liveProgress = value);
                          },
                          onChangeEnd: _seekOverall,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isPaged && _textPages.isNotEmpty
                            ? '${_pageIndex + 1}/${_textPages.length}'
                            : '${_chapterIndex + 1}/${widget.book.chapters.length}',
                        style: TextStyle(fontSize: 12, color: _readerSecondary),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
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
          const _SettingTitle(title: '字体', trailing: '系统字体'),
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

class _ReaderSearchResult {
  const _ReaderSearchResult({
    required this.chapterIndex,
    required this.characterOffset,
    required this.excerpt,
  });

  final int chapterIndex;
  final int characterOffset;
  final String excerpt;
}

class _TextPage {
  const _TextPage({required this.start, required this.end, required this.text});

  final int start;
  final int end;
  final String text;
}

class _ReaderSearchDelegate extends SearchDelegate<_ReaderSearchResult?> {
  _ReaderSearchDelegate(this.book, this.readingStore);

  final Book book;
  final ReadingStore readingStore;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清除',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    if (query.trim().isEmpty) {
      return const Center(child: Text('输入正文内容进行全文搜索'));
    }
    return FutureBuilder(
      future: readingStore.searchChapters(book, query),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? const [];
        if (results.isEmpty) {
          return const Center(child: Text('没有找到相关内容'));
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final match = results[index];
            final result = _ReaderSearchResult(
              chapterIndex: match.chapterIndex,
              characterOffset: match.characterOffset,
              excerpt: match.excerpt,
            );
            return ListTile(
              key: ValueKey(
                'search-${result.chapterIndex}-${result.characterOffset}',
              ),
              title: Text(book.chapters[result.chapterIndex].title),
              subtitle: Text(
                result.excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => close(context, result),
            );
          },
        );
      },
    );
  }
}
