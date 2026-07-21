import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/book_importer.dart';
import '../services/cover_palette_extractor.dart';
import '../services/local_file_picker.dart';
import '../services/reading_store.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_hero.dart';
import 'book_showcase_screen.dart';

const double _shelfItemExtent = 118;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.books,
    required this.readingStore,
    this.onBookImported,
    this.warmPresetCovers = true,
  });

  final List<Book> books;
  final ReadingStore readingStore;
  final ValueChanged<Book>? onBookImported;
  final bool warmPresetCovers;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final ValueNotifier<double> _shelfPosition;
  final ValueNotifier<int?> _touchedVirtualIndex = ValueNotifier<int?>(null);
  late final AnimationController _motionController;
  late int _currentIndex;
  String _query = '';
  String _coverWarmupSignature = '';
  bool _coversReady = true;
  int _coverWarmupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    _shelfPosition = ValueNotifier<double>(_currentIndex.toDouble());
    _motionController = AnimationController.unbounded(
      vsync: this,
      value: _shelfPosition.value,
    );
    _motionController.addListener(() {
      _shelfPosition.value = _motionController.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmPresetCovers();
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books != widget.books) _warmPresetCovers();
  }

  void _warmPresetCovers() {
    if (!widget.warmPresetCovers) {
      _coversReady = true;
      return;
    }
    final presetBooks = widget.books
        .where(
          (book) =>
              (book.coverBytes?.isEmpty ?? true) && book.coverAsset == null,
        )
        .toList();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final logicalWidth = landscape ? 132.0 : 176.0;
    final cacheWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(120, 720);
    final uniqueBooks = <String, Book>{
      for (final book in presetBooks)
        '${book.id}:${book.coverTemplate}:${book.title}:${book.author}': book,
    }.values.toList();
    final signature =
        '$cacheWidth:${uniqueBooks.map((book) => '${book.id}:${book.coverTemplate}').join(',')}';
    if (signature == _coverWarmupSignature) return;
    _coverWarmupSignature = signature;
    final generation = ++_coverWarmupGeneration;
    _coversReady = uniqueBooks.isEmpty;
    if (_coversReady) return;

    Future<void>(() async {
      for (final book in uniqueBooks) {
        if (!mounted) return;
        await precacheBookCoverArtwork(book, cacheWidth);
      }
      if (!mounted || generation != _coverWarmupGeneration) return;
      setState(() => _coversReady = true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _motionController.dispose();
    _shelfPosition.dispose();
    _touchedVirtualIndex.dispose();
    super.dispose();
  }

  List<Book> _visibleBooks() {
    final matching = widget.books.where((book) {
      final haystack = '${book.title}${book.author}'.toLowerCase();
      return haystack.contains(_query.trim().toLowerCase());
    }).toList();
    return matching;
  }

  void _onSearchChanged(String value) {
    const target = 0;
    setState(() {
      _query = value;
      _currentIndex = target;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _motionController.stop();
      _motionController.value = target.toDouble();
    });
  }

  static int _loopIndex(int virtualIndex, int count) {
    if (count <= 0) return 0;
    return ((virtualIndex % count) + count) % count;
  }

  Future<void> _animateShelfTo(
    double target, {
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    _motionController.stop();
    final distance = (target - _shelfPosition.value).abs();
    _motionController.value = _shelfPosition.value;
    final travelDuration =
        duration ??
        Duration(milliseconds: (190 + distance * 72).clamp(210, 460).round());
    try {
      await _motionController
          .animateTo(target, duration: travelDuration, curve: curve)
          .orCancel;
    } on TickerCanceled {
      return;
    }
    _motionController.value = target;
  }

  void _commitVirtualIndex(int virtualIndex, List<Book> books) {
    if (books.isEmpty || !mounted) return;
    final index = _loopIndex(virtualIndex, books.length);
    if (index != _currentIndex) setState(() => _currentIndex = index);
  }

  Future<void> _settleShelf(List<Book> books, double pixelsPerSecond) async {
    if (books.isEmpty) return;
    final velocityPages = (-pixelsPerSecond / _shelfItemExtent).clamp(
      -18.0,
      18.0,
    );
    final projectedPages = (velocityPages * .13).clamp(-3.5, 3.5);
    final target = (_shelfPosition.value + projectedPages).roundToDouble();
    _motionController.stop();
    _motionController.value = _shelfPosition.value;
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 285, damping: 31),
      _shelfPosition.value,
      target,
      velocityPages,
      tolerance: const Tolerance(distance: .0008, velocity: .001),
    );
    try {
      await _motionController.animateWith(simulation).orCancel;
    } on TickerCanceled {
      return;
    }
    _motionController.value = target;
    _commitVirtualIndex(target.round(), books);
    _touchedVirtualIndex.value = null;
  }

  Future<void> _stepShelf(List<Book> books, int direction) async {
    if (books.isEmpty) return;
    final target = _shelfPosition.value.round() + direction;
    await _animateShelfTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 260),
    );
    _commitVirtualIndex(target, books);
    HapticFeedback.selectionClick();
  }

  int _virtualIndexAt(double localX, double focusX) {
    return (_shelfPosition.value + (localX - focusX) / _shelfItemExtent)
        .round();
  }

  void _touchBookAt(double localX, double focusX, int count) {
    if (count <= 0) return;
    final virtualIndex = _virtualIndexAt(localX, focusX);
    if (_touchedVirtualIndex.value != virtualIndex) {
      _touchedVirtualIndex.value = virtualIndex;
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _tapBookAt(
    double localX,
    double focusX,
    List<Book> books,
  ) async {
    if (books.isEmpty) return;
    final virtualIndex = _virtualIndexAt(localX, focusX);
    _touchedVirtualIndex.value = virtualIndex;
    await _animateShelfTo(
      virtualIndex.toDouble(),
      duration: const Duration(milliseconds: 230),
    );
    _commitVirtualIndex(virtualIndex, books);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    await _openBook(books[_loopIndex(virtualIndex, books.length)]);
    _touchedVirtualIndex.value = null;
  }

  Future<void> _openBook(Book book) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 1100),
        reverseTransitionDuration: const Duration(milliseconds: 680),
        pageBuilder: (context, animation, secondaryAnimation) =>
            BookShowcaseScreen(book: book, readingStore: widget.readingStore),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final pageFade = CurvedAnimation(
            parent: animation,
            curve: const Interval(.64, 1, curve: Curves.easeOutCubic),
            reverseCurve: Curves.easeInCubic,
          );
          final pageArrival = Tween<double>(begin: .985, end: 1).animate(
            CurvedAnimation(
              parent: animation,
              curve: const Interval(.64, 1, curve: Curves.easeOutCubic),
            ),
          );
          return FadeTransition(
            opacity: pageFade,
            child: ScaleTransition(scale: pageArrival, child: child),
          );
        },
      ),
    );
  }

  Future<void> _importLocalBook({required bool coverImage}) async {
    PickedLocalFile? file;
    try {
      file = await LocalFilePicker.pick(coverImage: coverImage);
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = error.code == 'file_too_large'
          ? '文件不能超过 50 MB'
          : '文件读取失败，请重新选择';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted || file == null) return;

    final bytes = file.bytes;
    if (bytes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取这个文件，请换一个文件重试')));
      return;
    }

    final imported = coverImage
        ? ImportedBookData(
            title: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
            author: '本地导入',
            coverBytes: bytes,
            chapters: const [Chapter(title: '正文', content: '请从书籍文件导入正文。')],
          )
        : await BookImporter.parse(file);
    final title = imported.title.trim().isEmpty
        ? '未命名书籍'
        : imported.title.trim();
    final actualCover = imported.coverBytes == null
        ? null
        : await CoverPaletteExtractor.normalize(imported.coverBytes!);
    final palette = actualCover == null
        ? CoverPaletteExtractor.fromText(title)
        : await CoverPaletteExtractor.fromBytes(
            actualCover,
            fallbackSeed: title,
          );
    if (!mounted) return;

    final seed = title.codeUnits.fold<int>(0, (value, unit) => value + unit);
    final styles = BookBindingStyle.values;
    final book = Book(
      title: title,
      author: imported.author,
      lastRead: '刚刚导入',
      progress: 0,
      palette: palette,
      coverMark: title,
      coverBytes: actualCover,
      overlayCoverText: actualCover == null || coverImage,
      coverTemplate: seed % 20,
      bindingStyle: styles[seed % styles.length],
      chapters: imported.chapters,
    );

    final targetIndex = widget.books.length;
    widget.onBookImported?.call(book);
    _searchController.clear();
    setState(() {
      _query = '';
      _currentIndex = targetIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _motionController.stop();
      _motionController.value = targetIndex.toDouble();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已生成《${book.title}》的专属封面卡片')));
  }

  Future<void> _changeCover(Book book) async {
    PickedLocalFile? file;
    try {
      file = await LocalFilePicker.pick(coverImage: true);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('封面读取失败，请重新选择图片')));
      }
      return;
    }
    if (!mounted || file == null) return;
    final normalized = await CoverPaletteExtractor.normalize(file.bytes);
    final palette = await CoverPaletteExtractor.fromBytes(
      normalized,
      fallbackSeed: book.title,
    );
    widget.readingStore.updateImportedBook(
      book.copyWith(
        coverBytes: normalized,
        palette: palette,
        overlayCoverText: true,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('《${book.title}》的封面已更新')));
  }

  void _showImportSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF17191E),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '添加到书架',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '导入本地 EPUB、TXT 或 PDF，封面与色彩会自动融入浮光书架。',
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 20),
            _ImportOption(
              icon: Icons.folder_open_rounded,
              title: '从本地文件导入',
              subtitle: '支持 EPUB、TXT 和 PDF，并自动生成封面卡片',
              onTap: () async {
                Navigator.pop(context);
                await Future<void>.delayed(const Duration(milliseconds: 180));
                await _importLocalBook(coverImage: false);
              },
            ),
            const SizedBox(height: 10),
            _ImportOption(
              icon: Icons.image_outlined,
              title: '从封面图片创建',
              subtitle: '使用 PNG、JPG 或 WebP 创建封面卡片',
              onTap: () async {
                Navigator.pop(context);
                await Future<void>.delayed(const Duration(milliseconds: 180));
                await _importLocalBook(coverImage: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _visibleBooks();
    final safeIndex = books.isEmpty
        ? 0
        : _currentIndex.clamp(0, books.length - 1);

    return Stack(
      children: [
        Positioned.fill(
          child: _DepthBackground(books: books, fallbackIndex: safeIndex),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              _LibraryToolbar(
                controller: _searchController,
                onSearchChanged: _onSearchChanged,
                onClear: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
                hasQuery: _query.isNotEmpty,
                onAdd: _showImportSheet,
                onEditCover: books.isEmpty
                    ? null
                    : () => _changeCover(books[safeIndex]),
              ),
              if (books.isEmpty)
                Expanded(
                  child: _query.isEmpty
                      ? _EmptyLibrary(onAdd: _showImportSheet)
                      : const _EmptySearch(),
                )
              else
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 140),
                          child: _coversReady
                              ? _CoverFlowQueue(
                                  key: const ValueKey('coverflow-ready'),
                                  books: books,
                                  fallbackIndex: safeIndex,
                                  shelfPosition: _shelfPosition,
                                  touchedVirtualIndex: _touchedVirtualIndex,
                                )
                              : const Center(
                                  key: ValueKey('coverflow-warming'),
                                  child: Icon(
                                    Icons.auto_stories_outlined,
                                    size: 26,
                                    color: Colors.white24,
                                  ),
                                ),
                        ),
                      ),
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final focusX = constraints.maxWidth / 2;
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Listener(
                                    onPointerDown: (event) => _touchBookAt(
                                      event.localPosition.dx,
                                      focusX,
                                      books.length,
                                    ),
                                    onPointerMove: (event) => _touchBookAt(
                                      event.localPosition.dx,
                                      focusX,
                                      books.length,
                                    ),
                                    onPointerCancel: (_) =>
                                        _touchedVirtualIndex.value = null,
                                    child: GestureDetector(
                                      key: const ValueKey('book-carousel'),
                                      behavior: HitTestBehavior.opaque,
                                      onHorizontalDragStart: (_) {
                                        _motionController.stop();
                                        _motionController.value =
                                            _shelfPosition.value;
                                      },
                                      onHorizontalDragUpdate: (details) {
                                        _shelfPosition.value -=
                                            details.delta.dx / _shelfItemExtent;
                                        _touchBookAt(
                                          details.localPosition.dx,
                                          focusX,
                                          books.length,
                                        );
                                      },
                                      onHorizontalDragEnd: (details) =>
                                          _settleShelf(
                                            books,
                                            details.velocity.pixelsPerSecond.dx,
                                          ),
                                      onTapUp: (details) => _tapBookAt(
                                        details.localPosition.dx,
                                        focusX,
                                        books,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: focusX - _shelfItemExtent / 2,
                                  width: _shelfItemExtent,
                                  top: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    child: SizedBox(
                                      key: ValueKey(
                                        'book-${books[safeIndex].title}',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _SelectedBookOverlay(
                          book: books[safeIndex],
                          index: safeIndex,
                          count: books.length,
                          onOpen: () => _openBook(books[safeIndex]),
                          onPrevious: () => _stepShelf(books, -1),
                          onNext: () => _stepShelf(books, 1),
                          compact:
                              MediaQuery.orientationOf(context) ==
                              Orientation.landscape,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.controller,
    required this.onSearchChanged,
    required this.onClear,
    required this.hasQuery,
    required this.onAdd,
    required this.onEditCover,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;
  final bool hasQuery;
  final VoidCallback onAdd;
  final VoidCallback? onEditCover;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 12, 4),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '浮光书架',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '在书页之间穿行',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: math.min(142, MediaQuery.sizeOf(context).width * .29),
            height: 42,
            child: TextField(
              key: const ValueKey('library-search'),
              controller: controller,
              onChanged: onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索书籍',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: Colors.white54,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 38),
                suffixIcon: hasQuery
                    ? IconButton(
                        onPressed: onClear,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                          size: 16,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: .09),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .28),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('add-book-button'),
            tooltip: '导入书籍',
            onPressed: onAdd,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .08),
            ),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('edit-cover-button'),
            tooltip: '更换当前书籍封面',
            onPressed: onEditCover,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white24,
              backgroundColor: Colors.white.withValues(alpha: .08),
            ),
            icon: const Icon(Icons.photo_camera_back_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _DepthBackground extends StatelessWidget {
  const _DepthBackground({required this.books, required this.fallbackIndex});

  final List<Book> books;
  final int fallbackIndex;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const ColoredBox(color: Color(0xFF08090B));
    final glow = books[fallbackIndex].palette.first;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF050A0D),
          gradient: RadialGradient(
            center: const Alignment(0, -.12),
            radius: .9,
            colors: [
              Color.lerp(glow, const Color(0xFF102129), .72)!,
              const Color(0xFF081116),
              const Color(0xFF030608),
            ],
            stops: const [0, .5, 1],
          ),
        ),
      ),
    );
  }
}

class _CoverFlowQueue extends StatelessWidget {
  const _CoverFlowQueue({
    super.key,
    required this.books,
    required this.fallbackIndex,
    required this.shelfPosition,
    required this.touchedVirtualIndex,
  });

  final List<Book> books;
  final int fallbackIndex;
  final ValueNotifier<double> shelfPosition;
  final ValueNotifier<int?> touchedVirtualIndex;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: Listenable.merge([shelfPosition, touchedVirtualIndex]),
            builder: (context, _) {
              final page = shelfPosition.value.isFinite
                  ? shelfPosition.value
                  : fallbackIndex.toDouble();
              final center = page.floor();
              // Paint exactly seven independently transformed books. The
              // virtual indices recycle at the clipped top and bottom edges.
              final radius = books.length == 1 ? 0 : 3;
              final touched = touchedVirtualIndex.value;
              final committedVirtualIndex = books.length == 1
                  ? 0
                  : fallbackIndex +
                        ((page - fallbackIndex) / books.length).round() *
                            books.length;
              final entries =
                  <_FlowEntry>[
                    for (
                      var virtualIndex = center - radius;
                      virtualIndex <= center + radius;
                      virtualIndex++
                    )
                      _FlowEntry(
                        virtualIndex: virtualIndex,
                        bookIndex: _LibraryScreenState._loopIndex(
                          virtualIndex,
                          books.length,
                        ),
                        pose: _coverFlowPose(virtualIndex - page),
                        touched: virtualIndex == touched,
                      ),
                  ]..sort((a, b) {
                    if (a.touched != b.touched) return a.touched ? 1 : -1;
                    return a.pose.z.compareTo(b.pose.z);
                  });
              final landscape =
                  MediaQuery.orientationOf(context) == Orientation.landscape;
              final focusY = constraints.maxHeight * (landscape ? .42 : .36);
              final bookWidth = landscape
                  ? math.min(132.0, constraints.maxHeight * .5)
                  : math.min(176.0, constraints.maxWidth * .43);

              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final entry in entries)
                    _CinematicBook(
                      key: ValueKey('shelf-book-${entry.virtualIndex}'),
                      book: books[entry.bookIndex],
                      pose: entry.pose,
                      focusY: focusY,
                      width: bookWidth,
                      virtualIndex: entry.virtualIndex,
                      hasStableTestKey:
                          entry.virtualIndex == committedVirtualIndex,
                      focusAmount: (1 - (entry.virtualIndex - page).abs())
                          .clamp(0.0, 1.0),
                      touched: entry.touched,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FlowEntry {
  const _FlowEntry({
    required this.virtualIndex,
    required this.bookIndex,
    required this.pose,
    required this.touched,
  });

  final int virtualIndex;
  final int bookIndex;
  final _CoverFlowPose pose;
  final bool touched;
}

class _CoverFlowPose {
  const _CoverFlowPose({
    required this.x,
    required this.z,
    required this.scale,
    required this.tiltRadians,
  });

  final double x;
  final double z;
  final double scale;
  final double tiltRadians;
}

_CoverFlowPose _coverFlowPose(double delta) {
  final position = delta.clamp(-3.4, 3.4);
  final distance = position.abs();
  final turn = Curves.easeOutCubic.transform(distance.clamp(0.0, 1.0));
  final direction = position == 0 ? 0.0 : (position.isNegative ? 1.0 : -1.0);
  return _CoverFlowPose(
    x: position * _shelfItemExtent,
    z: 54 - distance * 46,
    scale: (1.08 - distance * .075).clamp(.82, 1.08),
    tiltRadians: direction * turn * .66,
  );
}

class _CinematicBook extends StatelessWidget {
  const _CinematicBook({
    super.key,
    required this.book,
    required this.pose,
    required this.focusY,
    required this.width,
    required this.virtualIndex,
    required this.hasStableTestKey,
    required this.focusAmount,
    required this.touched,
  });

  final Book book;
  final _CoverFlowPose pose;
  final double focusY;
  final double width;
  final int virtualIndex;
  final bool hasStableTestKey;
  final double focusAmount;
  final bool touched;

  @override
  Widget build(BuildContext context) {
    final cardHeight = width * 1.48;
    final isCenterOccurrence = focusAmount > .92;
    final volume = AnimatedScale(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      scale: touched ? 1.04 : 1,
      child: RepaintBoundary(
        key: ValueKey(
          hasStableTestKey
              ? 'shelf-volume-${book.title}'
              : 'shelf-volume-${book.title}-$virtualIndex',
        ),
        child: _CoverFlowCard(
          book: book,
          width: width,
          selected: isCenterOccurrence || touched,
        ),
      ),
    );
    final visual = isCenterOccurrence
        ? BookHero(book: book, child: volume)
        : volume;

    return Positioned(
      left: 0,
      right: 0,
      top: focusY - cardHeight / 2,
      child: Transform.translate(
        offset: Offset(pose.x, 0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, -1 / 1000)
            ..translateByDouble(0, 0, pose.z, 1)
            ..rotateY(pose.tiltRadians)
            ..scaleByDouble(pose.scale, pose.scale, pose.scale, 1),
          child: Center(child: visual),
        ),
      ),
    );
  }
}

class _CoverFlowCard extends StatelessWidget {
  const _CoverFlowCard({
    required this.book,
    required this.width,
    required this.selected,
  });

  final Book book;
  final double width;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 1.48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: selected ? .44 : .14),
            width: selected ? 1.4 : .8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          clipBehavior: Clip.hardEdge,
          child: BookCoverArtwork(book: book, width: width),
        ),
      ),
    );
  }
}

class _SelectedBookOverlay extends StatelessWidget {
  const _SelectedBookOverlay({
    required this.book,
    required this.index,
    required this.count,
    required this.onOpen,
    required this.onPrevious,
    required this.onNext,
    required this.compact,
  });

  final Book book;
  final int index;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, compact ? 4 : 24, 18, compact ? 4 : 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x08080B0E), Color(0xB8080B0E), Color(0xF505090B)],
          stops: [0, .52, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(book.id),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var dot = 0; dot < math.min(count, 7); dot++) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        width: dot == index ? 20 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: dot == index
                              ? book.palette.first
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      if (dot != math.min(count, 7) - 1)
                        const SizedBox(width: 5),
                    ],
                    const SizedBox(width: 10),
                    Text(
                      '${index + 1} / $count',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .42),
                        fontSize: 11,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 2 : 7),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 17 : 23,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: compact ? 1 : 5),
                Text(
                  '${book.author}  ·  已读 ${(book.progress * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0x82FFFFFF),
                    fontSize: 12,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 9),
                  SizedBox(
                    width: 188,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: book.progress,
                        minHeight: 4,
                        color: book.palette.first,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: compact ? 5 : 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShelfControlButton(
                key: const ValueKey('previous-book-button'),
                icon: Icons.chevron_left_rounded,
                tooltip: '上一本',
                onPressed: onPrevious,
                compact: compact,
              ),
              const SizedBox(width: 12),
              _ShelfControlButton(
                key: const ValueKey('open-showcase-button'),
                icon: Icons.menu_book_rounded,
                tooltip: '进入书籍展厅',
                onPressed: onOpen,
                compact: compact,
                primary: true,
              ),
              const SizedBox(width: 12),
              _ShelfControlButton(
                key: const ValueKey('next-book-button'),
                icon: Icons.chevron_right_rounded,
                tooltip: '下一本',
                onPressed: onNext,
                compact: compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShelfControlButton extends StatelessWidget {
  const _ShelfControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.compact,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool compact;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: primary ? const Color(0xFF111318) : Colors.white,
        backgroundColor: primary
            ? Colors.white
            : Colors.white.withValues(alpha: .09),
        side: primary
            ? BorderSide.none
            : BorderSide(color: Colors.white.withValues(alpha: .1)),
        fixedSize: Size.square(compact ? 38 : 48),
      ),
      icon: Icon(icon, size: compact ? 20 : 24),
    );
  }
}

class _ImportOption extends StatelessWidget {
  const _ImportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(17),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white38,
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_rounded, size: 48, color: Colors.white24),
          SizedBox(height: 12),
          Text('没有找到这本书', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 54,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            const Text(
              '书架还是空的',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '导入 TXT、EPUB 或 PDF，开始建立你的私人书架。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, height: 1.55),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('empty-import-button'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('导入第一本书'),
            ),
          ],
        ),
      ),
    );
  }
}
