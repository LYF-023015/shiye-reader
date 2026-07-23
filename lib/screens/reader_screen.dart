import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  Timer? _controlsTimer;
  String _selectedText = '';
  Timer? _autoScrollTimer;
  bool _autoScrolling = false;
  late double _autoScrollSpeed;
  bool _speaking = false;
  List<String> _ttsChunks = const [];
  int _ttsChunkIndex = 0;
  int _ttsChapterIndex = 0;
  List<_TextPage> _textPages = const [];
  String _paginationKey = '';
  int _pageIndex = 0;
  bool _turningChapter = false;
  // Continuous-scroll geometry: a stable key per chapter block plus cached
  // pixel offsets/heights so scroll position can be mapped to a chapter.
  late final List<GlobalKey> _chapterKeys;
  final Map<int, double> _chapterTopOffsets = {};
  final Map<int, double> _chapterBlockHeights = {};
  String _layoutSignature = '';

  Chapter get _chapter => widget.book.chapters[_chapterIndex];

  Color get _effectiveBackground =>
      _eyeCare ? const Color(0xFFEAF2E4) : _background;

  Color get _readerForeground =>
      ThemeData.estimateBrightnessForColor(_effectiveBackground) ==
          Brightness.dark
      ? const Color(0xFFF2F0EA)
      : const Color(0xFF34363A);

  Color get _readerSecondary => _readerForeground.withValues(alpha: .76);

  TextStyle get _chapterTitleStyle => TextStyle(
    fontSize: (_fontSize + 7).clamp(22.0, 30.0),
    height: 1.3,
    fontWeight: FontWeight.w800,
    color: _readerForeground,
    letterSpacing: .4,
  );

  Widget _chapterNavPill({
    Key? key,
    required String label,
    required String chapterTitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: _readerSecondary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  '$label · $chapterTitle',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: _readerSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSelectionChanged(String selected) {
    if (selected == _selectedText) return;
    final hasSelection = selected.trim().isNotEmpty;
    if (hasSelection) _controlsTimer?.cancel();
    setState(() {
      _selectedText = selected;
      if (hasSelection) _showControls = true;
    });
  }

  String get _currentLayoutSignature =>
      '${widget.book.chapters.length}:${_fontSize.toStringAsFixed(2)}:'
      '${_lineHeight.toStringAsFixed(2)}:${_alignment.name}'
      ':${_readerForeground.toARGB32()}'
      ':${MediaQuery.sizeOf(context).width.toStringAsFixed(0)}';

  /// Refreshes cached per-chapter pixel offsets/heights for chapters that are
  /// currently built (visible). Lazy rendering means only a few chapters exist
  /// at once, so this is cheap; it also accumulates offsets as the reader
  /// scrolls so navigation stays accurate without building the whole book.
  void _ensureChapterGeometry() {
    final signatureChanged = _currentLayoutSignature != _layoutSignature;
    if (signatureChanged) {
      _layoutSignature = _currentLayoutSignature;
      _chapterTopOffsets.clear();
      _chapterBlockHeights.clear();
    }
    for (var index = 0; index < widget.book.chapters.length; index++) {
      if (!signatureChanged && _chapterTopOffsets.containsKey(index)) continue;
      final key = _chapterKeys[index];
      final context = key.currentContext;
      final object = context?.findRenderObject();
      if (object == null || !object.attached) continue;
      final viewport = RenderAbstractViewport.of(object);
      _chapterTopOffsets[index] = viewport
          .getOffsetToReveal(object, 0)
          .offset
          .clamp(0.0, double.infinity);
      if (object is RenderBox && object.hasSize) {
        _chapterBlockHeights[index] = object.size.height;
      }
    }
  }

  /// Maps the current scroll offset to a chapter index and a 0..1 progress
  /// within that chapter. Falls back to the last known chapter when geometry
  /// is not available yet (e.g. before the first layout).
  ({int index, double local}) _positionFromScroll() {
    if (widget.book.chapters.isEmpty) return (index: 0, local: 0.0);
    _ensureChapterGeometry();
    final fallbackIndex = _chapterIndex.clamp(
      0,
      widget.book.chapters.length - 1,
    );
    if (!_scrollController.hasClients || _chapterTopOffsets.isEmpty) {
      return (index: fallbackIndex, local: _restoreChapterProgress.clamp(0, 1));
    }
    // Probe a point just inside the reading area (below the top inset/controls).
    final probe = _scrollController.offset + 96;
    var index = 0;
    for (var entry = 0; entry < widget.book.chapters.length; entry++) {
      final top = _chapterTopOffsets[entry];
      if (top == null) continue;
      if (top <= probe + .1) {
        index = entry;
      } else {
        break;
      }
    }
    final top = _chapterTopOffsets[index] ?? 0.0;
    final height = _chapterBlockHeights[index] ?? 1.0;
    final local = height <= 0 ? 0.0 : ((probe - top) / height).clamp(0.0, 1.0);
    return (index: index, local: local);
  }

  int get _liveChapterIndex =>
      _isPaged ? _chapterIndex : _positionFromScroll().index;

  int get _currentCharacterOffset {
    if (_isPaged && _textPages.isNotEmpty) {
      return _textPages[_pageIndex.clamp(0, _textPages.length - 1)].start;
    }
    final pos = _positionFromScroll();
    final length = widget.book.chapters[pos.index].content.length;
    return (length * pos.local).round().clamp(0, length);
  }

  /// Locates the selected text across the whole book, returning the chapter it
  /// lives in and the character offset within it. In continuous scroll a
  /// selection can sit in any chapter, not just the one at the scroll focus.
  ({int chapterIndex, int offset}) _resolveSelection() {
    final selected = _selectedText.trim();
    final fallback = (
      chapterIndex: _liveChapterIndex,
      offset: _currentCharacterOffset,
    );
    if (selected.isEmpty) return fallback;
    final anchor = _liveChapterIndex;
    var bestChapter = -1;
    var bestOffset = 0;
    var bestScore = double.infinity;
    final pattern = RegExp(RegExp.escape(selected));
    for (var entry = 0; entry < widget.book.chapters.length; entry++) {
      final content = widget.book.chapters[entry].content;
      for (final match in pattern.allMatches(content)) {
        // Prefer the chapter nearest the reading focus, then the earliest hit.
        final score = (entry - anchor).abs() * 1e9 + match.start.toDouble();
        if (score < bestScore) {
          bestScore = score;
          bestChapter = entry;
          bestOffset = match.start;
        }
      }
    }
    if (bestChapter < 0) return fallback;
    return (chapterIndex: bestChapter, offset: bestOffset);
  }

  @override
  void initState() {
    super.initState();
    _chapterKeys = List.generate(
      widget.book.chapters.length,
      (_) => GlobalKey(debugLabel: 'chapter-block'),
      growable: false,
    );
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
    _autoScrollSpeed =
        const <double>[.75, 1, 1.5, 2, 3].contains(preferences.autoScrollSpeed)
        ? preferences.autoScrollSpeed
        : 1.5;
    _liveProgress = state.progress;
    _restoreChapterProgress = state.chapterProgress;
    _restoreCharacterOffset =
        widget.initialCharacterOffset ?? state.characterOffset;
    _scrollController.addListener(_queueProgressUpdate);
    _tts
      ..setStartHandler(() {
        if (mounted) setState(() => _speaking = true);
      })
      // Android's TextToSpeech silently drops very long utterances, so the
      // chapter is split into chunks and chained here as each chunk finishes.
      // When a chapter ends, reading continues into the next one.
      ..setCompletionHandler(() {
        if (!mounted) return;
        if (_ttsChunkIndex < _ttsChunks.length) {
          _speakNextChunk();
        } else if (_advanceTtsToNextChapter()) {
          _followTtsChapter();
          _speakNextChunk();
        } else {
          setState(() => _speaking = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('全书朗读完毕')));
        }
      })
      ..setCancelHandler(() {
        if (!mounted) return;
        _ttsChunks = const [];
        _ttsChunkIndex = 0;
        setState(() => _speaking = false);
      })
      ..setErrorHandler((_) {
        if (!mounted) return;
        _ttsChunks = const [];
        _ttsChunkIndex = 0;
        setState(() => _speaking = false);
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePosition();
      _restartControlsTimer();
    });
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    if (!_showControls) return;
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _setControlsVisible(bool visible) {
    _controlsTimer?.cancel();
    if (_showControls != visible) setState(() => _showControls = visible);
    if (visible) _restartControlsTimer();
  }

  void _handleReaderTap(TapUpDetails details) {
    final lowerHalf =
        details.globalPosition.dy >= MediaQuery.sizeOf(context).height * .52;
    if (!_showControls && !lowerHalf) return;
    _setControlsVisible(!_showControls);
  }

  void _restorePosition() {
    if (widget.book.chapters.isEmpty) return;
    if (_isPaged) return; // paged mode restores inside _buildPagedBody.
    if (!_scrollController.hasClients) return;
    _ensureChapterGeometry();
    final max = _scrollController.position.maxScrollExtent;
    final index = _chapterIndex.clamp(0, widget.book.chapters.length - 1);
    final top = _chapterTopOffsets[index];
    final height = _chapterBlockHeights[index];
    if (top != null) {
      final contentLength = widget.book.chapters[index].content.length;
      final fraction =
          contentLength <= 0 ||
              (_restoreCharacterOffset == 0 && _restoreChapterProgress > 0)
          ? _restoreChapterProgress
          : (_restoreCharacterOffset / contentLength).clamp(0.0, 1.0);
      final within = (height ?? 0) * fraction;
      _scrollController.jumpTo((top + within).clamp(0.0, max));
      return;
    }
    // Target chapter isn't built yet (lazy list): land proportionally in the
    // whole-book scroll extent, which tracks reading position closely enough.
    final overall =
        (index + _restoreChapterProgress.clamp(0, 1)) /
        widget.book.chapters.length;
    _scrollController.jumpTo((overall * max).clamp(0.0, max));
  }

  void _queueProgressUpdate() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 180), _commitProgress);
  }

  bool get _isPaged => _pageTurn != '上下滚动';

  Future<void> _toggleSpeech() async {
    if (_speaking) {
      await _stopSpeech();
      return;
    }
    final startChapter = _liveChapterIndex.clamp(
      0,
      widget.book.chapters.length - 1,
    );
    final startOffset = _isPaged && _textPages.isNotEmpty
        ? _textPages[_pageIndex.clamp(0, _textPages.length - 1)].start
        : _currentCharacterOffset;
    _ttsChapterIndex = startChapter;
    final firstChapter = widget.book.chapters[startChapter];
    final from = startOffset.clamp(0, firstChapter.content.length);
    _ttsChunks = _splitForSpeech(firstChapter.content.substring(from));
    // If the reader is already at the end of this chapter, start from the next.
    if (_ttsChunks.isEmpty && !_advanceTtsToNextChapter()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有可朗读的内容')));
      }
      return;
    }
    _ttsChunkIndex = 0;
    setState(() => _speaking = true);
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(.46);
    } on Object {
      // Language and rate are best-effort; the engine falls back to defaults.
    }
    await _speakNextChunk();
  }

  /// Loads the next non-empty chapter into the TTS queue. Returns false when
  /// there are no more chapters to read.
  bool _advanceTtsToNextChapter() {
    while (_ttsChapterIndex < widget.book.chapters.length - 1) {
      _ttsChapterIndex++;
      final chunks = _splitForSpeech(
        widget.book.chapters[_ttsChapterIndex].content,
      );
      if (chunks.isNotEmpty) {
        _ttsChunks = chunks;
        _ttsChunkIndex = 0;
        return true;
      }
    }
    return false;
  }

  /// Scrolls/pages the view to the chapter currently being read so the reader
  /// can follow along.
  void _followTtsChapter() {
    if (_isPaged) {
      if (_chapterIndex != _ttsChapterIndex) {
        setState(() {
          _chapterIndex = _ttsChapterIndex;
          _restoreCharacterOffset = 0;
          _restoreChapterProgress = 0;
          _paginationKey = '';
        });
      }
      return;
    }
    _ensureChapterGeometry();
    final top = _chapterTopOffsets[_ttsChapterIndex];
    if (top == null || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final target = top.clamp(0.0, max);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    if (_chapterIndex != _ttsChapterIndex) {
      setState(() => _chapterIndex = _ttsChapterIndex);
    }
  }

  Future<void> _speakNextChunk() async {
    if (_ttsChunkIndex >= _ttsChunks.length) {
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final chunk = _ttsChunks[_ttsChunkIndex];
    _ttsChunkIndex++;
    try {
      final result = await _tts.speak(chunk);
      if (result != 1) throw StateError('TTS did not start');
    } on Object {
      await _stopSpeech();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('系统朗读暂时不可用')));
      }
    }
  }

  Future<void> _stopSpeech() async {
    _ttsChunks = const [];
    _ttsChunkIndex = 0;
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  List<String> _splitForSpeech(String text) {
    const maxChunk = 1400;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    final chunks = <String>[];
    var start = 0;
    while (start < trimmed.length) {
      if (trimmed.length - start <= maxChunk) {
        final chunk = trimmed.substring(start).trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        break;
      }
      var end = start + maxChunk;
      final boundary = trimmed.lastIndexOf(RegExp(r'[。！？!?\n；;]'), end);
      if (boundary > start + 200) end = boundary + 1;
      final chunk = trimmed.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      start = end;
    }
    return chunks;
  }

  void _toggleAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_autoScrolling || _isPaged) {
      setState(() => _autoScrolling = false);
      return;
    }
    setState(() => _autoScrolling = true);
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - .5) {
        _autoScrollTimer?.cancel();
        setState(() => _autoScrolling = false);
        return;
      }
      _scrollController.jumpTo(
        (position.pixels + .65 * _autoScrollSpeed).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _setAutoScrollSpeed(double value) {
    final speed = value.clamp(.75, 3.0);
    setState(() => _autoScrollSpeed = speed);
    widget.readingStore.updateReaderPreferences(
      widget.readingStore.readerPreferences.copyWith(autoScrollSpeed: speed),
    );
  }

  Future<void> _showReaderTools() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
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
                trailing: _isPaged
                    ? null
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          key: const ValueKey('auto-scroll-speed'),
                          value: _autoScrollSpeed,
                          borderRadius: BorderRadius.circular(14),
                          items: const [
                            DropdownMenuItem(value: .75, child: Text('0.75×')),
                            DropdownMenuItem(value: 1.0, child: Text('1.0×')),
                            DropdownMenuItem(value: 1.5, child: Text('1.5×')),
                            DropdownMenuItem(value: 2.0, child: Text('2.0×')),
                            DropdownMenuItem(value: 3.0, child: Text('3.0×')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _setAutoScrollSpeed(value);
                            setSheetState(() {});
                          },
                        ),
                      ),
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
    if (widget.book.chapters.isEmpty || _isPaged) return;
    if (!_scrollController.hasClients) return;
    final pos = _positionFromScroll();
    final chapterLength = widget.book.chapters[pos.index].content.length;
    final overall = ((pos.index + pos.local) / widget.book.chapters.length)
        .clamp(0.0, 1.0);
    _restoreChapterProgress = pos.local;
    _restoreCharacterOffset = (chapterLength * pos.local).round();
    final chapterChanged = pos.index != _chapterIndex;
    // Only rebuild while scrolling when something visible depends on it: the
    // progress slider/controls are showing, or the current chapter changed.
    final needsRebuild =
        rebuild && mounted && (_showControls || chapterChanged);
    if (needsRebuild) {
      setState(() {
        _liveProgress = overall;
        _chapterIndex = pos.index;
      });
    } else {
      _liveProgress = overall;
      _chapterIndex = pos.index;
    }
    widget.readingStore.updateProgress(
      widget.book,
      overall,
      pos.index,
      chapterProgress: pos.local,
      characterOffset: _restoreCharacterOffset,
    );
  }

  void _jumpToOffset(int chapterIndex, int characterOffset) {
    final chapter = widget.book.chapters[chapterIndex];
    final offset = characterOffset.clamp(0, chapter.content.length);
    if (_speaking) {
      _tts.stop();
      _ttsChunks = const [];
      _ttsChunkIndex = 0;
      _speaking = false;
    }
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
    _controlsTimer?.cancel();
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
                    if (widget.book.displayAuthor.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.book.displayAuthor,
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
    final resolved = _resolveSelection();
    final chapterLength =
        widget.book.chapters[resolved.chapterIndex].content.length;
    widget.readingStore.addAnnotation(
      widget.book,
      BookAnnotation(
        chapterIndex: resolved.chapterIndex,
        chapterProgress: chapterLength <= 0
            ? 0.0
            : (resolved.offset / chapterLength).clamp(0, 1),
        characterStart: resolved.offset,
        characterEnd: (resolved.offset + selected.length).clamp(
          resolved.offset,
          chapterLength,
        ),
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
    onTapUp: _handleReaderTap,
    // Lazy: only visible chapters are built/laid out, so opening a large
    // book never blocks the UI thread on a single huge frame. SelectionArea is
    // applied per chapter block below; wrapping the whole ListView in one
    // SelectionArea intercepts taps on empty areas.
    child: ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(34, 92, 34, 110),
      itemCount: widget.book.chapters.length,
      itemBuilder: (context, index) => _buildChapterBlock(index),
    ),
  );

  Widget _buildChapterBlock(int index) {
    final chapter = widget.book.chapters[index];
    return Container(
      key: _chapterKeys[index],
      margin: EdgeInsets.only(top: index == 0 ? 0 : 40),
      child: SelectionArea(
        onSelectionChanged: (content) =>
            _handleSelectionChanged(content?.plainText ?? ''),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chapter.title, style: _chapterTitleStyle),
            const SizedBox(height: 22),
            if (chapter.hasRichContent)
              fh.Html(
                key: ValueKey('rich-chapter-$index'),
                data: chapter.html,
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
                chapter.content,
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
    );
  }

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
      onTapUp: _handleReaderTap,
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
                onSelectionChanged: (content) =>
                    _handleSelectionChanged(content?.plainText ?? ''),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (index == 0) ...[
                      if (_chapterIndex > 0)
                        _chapterNavPill(
                          label: '上一章',
                          chapterTitle:
                              widget.book.chapters[_chapterIndex - 1].title,
                          icon: Icons.chevron_left_rounded,
                          onTap: () {
                            final previous =
                                widget.book.chapters[_chapterIndex - 1];
                            _jumpToOffset(
                              _chapterIndex - 1,
                              previous.content.length,
                            );
                          },
                        ),
                      Text(_chapter.title, style: _chapterTitleStyle),
                      const SizedBox(height: 18),
                    ],
                    Text(page.text, textAlign: _alignment, style: pageStyle),
                    if (index == _textPages.length - 1 &&
                        _chapterIndex < widget.book.chapters.length - 1) ...[
                      const SizedBox(height: 28),
                      _chapterNavPill(
                        label: '下一章',
                        chapterTitle:
                            widget.book.chapters[_chapterIndex + 1].title,
                        icon: Icons.chevron_right_rounded,
                        onTap: () => _jumpToOffset(_chapterIndex + 1, 0),
                      ),
                    ],
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
    final darkReader =
        ThemeData.estimateBrightnessForColor(_effectiveBackground) ==
        Brightness.dark;
    final controlSurface = darkReader
        ? const Color(0xF22A2C31)
        : Colors.white.withValues(alpha: .96);
    final controlForeground = darkReader
        ? const Color(0xFFF7F5F0)
        : const Color(0xFF282B30);
    final controlDivider = controlForeground.withValues(alpha: .17);

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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _showControls
                    ? Row(
                        key: const ValueKey('reader-top-controls'),
                        children: [
                          IconButton(
                            key: const ValueKey('reader-back'),
                            onPressed: () => Navigator.pop(context),
                            style: IconButton.styleFrom(
                              foregroundColor: controlForeground,
                              backgroundColor: controlSurface,
                            ),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: _readerForeground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('reader-more-button'),
                            tooltip: '阅读工具',
                            onPressed: _showReaderTools,
                            style: IconButton.styleFrom(
                              foregroundColor: controlForeground,
                              backgroundColor: controlSurface,
                            ),
                            icon: const Icon(Icons.more_horiz_rounded),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('reader-top-controls-hidden'),
                      ),
              ),
            ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 12,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _showControls
                    ? Column(
                        key: const ValueKey('reader-bottom-controls'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            key: const ValueKey('reader-controls'),
                            margin: const EdgeInsets.only(bottom: 13),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: controlSurface,
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
                                  foregroundColor: controlForeground,
                                  onTap: _showChapterList,
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: controlDivider,
                                ),
                                _ReaderAction(
                                  key: const ValueKey('settings-button'),
                                  icon: Icons.text_fields_rounded,
                                  label: '设置',
                                  foregroundColor: controlForeground,
                                  onTap: _showSettings,
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: controlDivider,
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
                                  foregroundColor: controlForeground,
                                  onTap: () {
                                    if (!_isPaged) _commitProgress();
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
                                  color: controlDivider,
                                ),
                                _ReaderAction(
                                  key: const ValueKey('annotation-button'),
                                  icon: _selectedText.trim().isEmpty
                                      ? Icons.comment_outlined
                                      : Icons.add_comment_rounded,
                                  label: _selectedText.trim().isEmpty
                                      ? '批注'
                                      : '添加',
                                  foregroundColor: controlForeground,
                                  onTap: _selectedText.trim().isEmpty
                                      ? _showAnnotations
                                      : _addAnnotation,
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${(chapterProgress.clamp(0, 1) * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _readerSecondary,
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
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _readerSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('reader-bottom-controls-hidden'),
                      ),
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
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
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
              Icon(icon, size: 20, color: foregroundColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 11,
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
