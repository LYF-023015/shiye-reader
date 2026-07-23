import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/book_importer.dart';
import '../services/cover_palette_extractor.dart';
import '../services/document_service.dart';
import '../services/local_file_picker.dart';
import '../services/reading_store.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_hero.dart';
import 'book_showcase_screen.dart';

const double _shelfItemExtent = 150;

Color _onSurface(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;
Color _onSurfaceSubdued(BuildContext context, {double alpha = .54}) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha);

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
  _ShelfSort _sort = _ShelfSort.recent;
  _ShelfFilter _filter = _ShelfFilter.all;
  _ShelfViewMode _viewMode = _ShelfViewMode.coverFlow;
  final Set<String> _selectedBookIds = {};
  String _coverWarmupSignature = '';
  bool _coversReady = true;
  int _coverWarmupGeneration = 0;
  bool _isImporting = false;

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
      if (!haystack.contains(_query.trim().toLowerCase())) return false;
      final progress = widget.readingStore.stateFor(book).progress;
      return switch (_filter) {
        _ShelfFilter.all => true,
        _ShelfFilter.unread => progress <= 0,
        _ShelfFilter.reading => progress > 0 && progress < .99,
        _ShelfFilter.finished => progress >= .99,
        _ShelfFilter.annotated =>
          widget.readingStore.stateFor(book).annotations.isNotEmpty,
      };
    }).toList();
    switch (_sort) {
      case _ShelfSort.recent:
        return widget.readingStore.sortByRecent(matching);
      case _ShelfSort.title:
        return widget.readingStore.sortByTitle(matching);
      case _ShelfSort.imported:
        matching.sort(
          (a, b) => (b.importedAt ?? DateTime(2000)).compareTo(
            a.importedAt ?? DateTime(2000),
          ),
        );
        return matching;
      case _ShelfSort.author:
        matching.sort(
          (a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()),
        );
        return matching;
      case _ShelfSort.progress:
        matching.sort(
          (a, b) => widget.readingStore
              .stateFor(b)
              .progress
              .compareTo(widget.readingStore.stateFor(a).progress),
        );
        return matching;
      case _ShelfSort.fileSize:
        matching.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        return matching;
    }
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

  /// The carousel only loops when there are at least three books. With one or
  /// two books looping produces duplicated neighbour cards (the same cover on
  /// both sides), so it is clamped to a bounded range instead.
  static bool _isLooping(int count) => count >= 3;

  static double _clampShelf(double value, int count) {
    if (count < 3) return value.clamp(0.0, math.max(0, count - 1).toDouble());
    return value;
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
    final target = _clampShelf(
      (_shelfPosition.value + projectedPages).roundToDouble(),
      books.length,
    );
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
    final current = _shelfPosition.value.round();
    final target = _clampShelf(
      (current + direction).toDouble(),
      books.length,
    ).round();
    if (target == current) {
      HapticFeedback.selectionClick();
      return;
    }
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
    final raw = _virtualIndexAt(localX, focusX);
    final virtualIndex = _isLooping(count)
        ? raw
        : _clampShelf(raw.toDouble(), count).round();
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
    final raw = _virtualIndexAt(localX, focusX);
    final virtualIndex = _isLooping(books.length)
        ? raw
        : _clampShelf(raw.toDouble(), books.length).round();
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
    if (_isImporting) return;
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

    setState(() => _isImporting = true);
    try {
      final imported = coverImage
          ? ImportedBookData(
              title: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
              author: '本地导入',
              format: BookFormat.txt,
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
        storageId: '${DateTime.now().microsecondsSinceEpoch}-$seed',
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
        format: imported.format,
        importedAt: DateTime.now(),
        fileSize: bytes.lengthInBytes,
        navigation: imported.navigation,
        sourceBytes: imported.sourceBytes,
      );

      var bookToAdd = book;
      if (widget.readingStore.containsImportedBook(book)) {
        final action = await showDialog<_DuplicateAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('发现同名书籍'),
            content: Text('《${book.title}》已在书架中。'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _DuplicateAction.cancel),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _DuplicateAction.keepBoth),
                child: const Text('保留两本'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _DuplicateAction.replace),
                child: const Text('替换'),
              ),
            ],
          ),
        );
        if (!mounted || action == null || action == _DuplicateAction.cancel) {
          return;
        }
        if (action == _DuplicateAction.keepBoth) {
          var copyNumber = 2;
          while (widget.readingStore.containsImportedBook(bookToAdd)) {
            bookToAdd = book.copyWith(title: '${book.title} ($copyNumber++)');
          }
        }
      }
      final existingIndex = widget.books.indexWhere(
        (item) => item.id == bookToAdd.id,
      );
      final targetIndex = existingIndex < 0
          ? widget.books.length
          : existingIndex;
      widget.onBookImported?.call(bookToAdd);
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
      ).showSnackBar(SnackBar(content: Text('已添加《${bookToAdd.title}》到书架')));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导入失败，请确认文件完整后重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
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

  Future<void> _editMetadata(Book book) async {
    final titleController = TextEditingController(text: book.title);
    final authorController = TextEditingController(text: book.author);
    final formKey = GlobalKey<FormState>();
    final updated = await showDialog<({String title, String author})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑书籍信息'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                autofocus: true,
                validator: (value) =>
                    value?.trim().isEmpty == true ? '书名不能为空' : null,
                decoration: const InputDecoration(labelText: '书名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: authorController,
                decoration: const InputDecoration(labelText: '作者'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final title = titleController.text.trim();
              Navigator.pop(context, (
                title: title,
                author: authorController.text.trim().isEmpty
                    ? '作者未知'
                    : authorController.text.trim(),
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    titleController.dispose();
    authorController.dispose();
    if (updated == null) return;
    widget.readingStore.replaceImportedBook(
      book,
      book.copyWith(
        title: updated.title,
        author: updated.author,
        coverMark: book.coverMark == book.title
            ? updated.title
            : book.coverMark,
      ),
    );
  }

  Future<void> _showBookActions(Book book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑书名与作者'),
              onTap: () => Navigator.pop(context, 'metadata'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_back_outlined),
              title: const Text('更换封面'),
              onTap: () => Navigator.pop(context, 'cover'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'metadata') await _editMetadata(book);
    if (action == 'cover') await _changeCover(book);
  }

  void _toggleSelected(Book book) {
    setState(() {
      _selectedBookIds.contains(book.id)
          ? _selectedBookIds.remove(book.id)
          : _selectedBookIds.add(book.id);
    });
  }

  Future<void> _deleteSelected() async {
    final books = widget.books
        .where((book) => _selectedBookIds.contains(book.id))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${books.length} 本书？'),
        content: const Text('对应阅读进度、书签、批注和记录也会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.readingStore.removeImportedBooks(books);
    if (mounted) setState(_selectedBookIds.clear);
  }

  Future<void> _exportSelected() async {
    final ids = Set<String>.of(_selectedBookIds);
    try {
      final saved = await DocumentService.saveBytes(
        name: 'Shiye-selected-backup.zip',
        content: await widget.readingStore.createBackupArchive(bookIds: ids),
        mimeType: 'application/zip',
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导出 ${ids.length} 本书的备份')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选书籍导出失败')));
      }
    }
  }

  void _showImportSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
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
            Text(
              '添加到书架',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '导入本地 EPUB 或 TXT，封面与色彩会自动融入浮光书架。',
              style: TextStyle(color: _onSurfaceSubdued(context), height: 1.5),
            ),
            const SizedBox(height: 20),
            _ImportOption(
              icon: Icons.folder_open_rounded,
              title: '从本地文件导入',
              subtitle: '支持 EPUB 和 TXT，并自动生成封面卡片',
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

  void _showSortMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '书架视图',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<_ShelfViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: _ShelfViewMode.coverFlow,
                      icon: Icon(Icons.view_carousel_outlined),
                    ),
                    ButtonSegment(
                      value: _ShelfViewMode.grid,
                      icon: Icon(Icons.grid_view_rounded),
                    ),
                    ButtonSegment(
                      value: _ShelfViewMode.list,
                      icon: Icon(Icons.view_list_rounded),
                    ),
                  ],
                  selected: {_viewMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    setState(() => _viewMode = value.first);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 18),
                const Text('筛选', style: TextStyle(fontWeight: FontWeight.w700)),
                Wrap(
                  spacing: 8,
                  children: _ShelfFilter.values
                      .map(
                        (filter) => FilterChip(
                          label: Text(filter.label),
                          selected: _filter == filter,
                          onSelected: (_) {
                            setState(() => _filter = filter);
                            setSheetState(() {});
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                const Text('排序', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final sort in _ShelfSort.values)
                  ListTile(
                    title: Text(sort.label),
                    trailing: _sort == sort
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () {
                      setState(() => _sort = sort);
                      setSheetState(() {});
                    },
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionView(List<Book> books) {
    if (_viewMode == _ShelfViewMode.list) {
      return ListView.separated(
        key: const ValueKey('shelf-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        itemCount: books.length,
        separatorBuilder: (_, _) =>
            Divider(color: Theme.of(context).dividerColor),
        itemBuilder: (context, index) {
          final book = books[index];
          final selected = _selectedBookIds.contains(book.id);
          return ListTile(
            key: ValueKey('shelf-list-${book.id}'),
            onTap: () => _selectedBookIds.isEmpty
                ? _openBook(book)
                : _toggleSelected(book),
            onLongPress: () => _toggleSelected(book),
            leading: BookCover(book: book, width: 42),
            title: Text(
              book.title,
              style: TextStyle(color: _onSurface(context)),
            ),
            subtitle: Text(
              [
                if (book.displayAuthor.isNotEmpty) book.displayAuthor,
                '${(widget.readingStore.stateFor(book).progress * 100).round()}%',
                _formatBytes(book.fileSize),
              ].join(' · '),
              style: TextStyle(color: _onSurfaceSubdued(context)),
            ),
            trailing: selected
                ? Icon(
                    Icons.check_circle_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : IconButton(
                    tooltip: '书籍操作',
                    onPressed: () => _showBookActions(book),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: _onSurfaceSubdued(context),
                    ),
                  ),
          );
        },
      );
    }
    return GridView.builder(
      key: const ValueKey('shelf-grid'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: .58,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final selected = _selectedBookIds.contains(book.id);
        return GestureDetector(
          key: ValueKey('shelf-grid-${book.id}'),
          onTap: () => _selectedBookIds.isEmpty
              ? _openBook(book)
              : _toggleSelected(book),
          onLongPress: () => _toggleSelected(book),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BookCoverArtwork(book: book),
                    if (selected)
                      ColoredBox(
                        color: const Color(0x66000000),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _onSurface(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (book.displayAuthor.isNotEmpty)
                Text(
                  book.displayAuthor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _onSurfaceSubdued(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        );
      },
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
                onSort: _showSortMenu,
                onEditCover:
                    books.isEmpty || _viewMode != _ShelfViewMode.coverFlow
                    ? null
                    : () => _showBookActions(books[safeIndex]),
              ),
              if (books.isEmpty)
                Expanded(
                  child: _query.isEmpty
                      ? _EmptyLibrary(onAdd: _showImportSheet)
                      : const _EmptySearch(),
                )
              else
                Expanded(
                  child: _viewMode == _ShelfViewMode.coverFlow
                      ? Stack(
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
                                        touchedVirtualIndex:
                                            _touchedVirtualIndex,
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
                                          onPointerDown: (event) =>
                                              _touchBookAt(
                                                event.localPosition.dx,
                                                focusX,
                                                books.length,
                                              ),
                                          onPointerMove: (event) =>
                                              _touchBookAt(
                                                event.localPosition.dx,
                                                focusX,
                                                books.length,
                                              ),
                                          onPointerCancel: (_) =>
                                              _touchedVirtualIndex.value = null,
                                          child: GestureDetector(
                                            key: const ValueKey(
                                              'book-carousel',
                                            ),
                                            behavior: HitTestBehavior.opaque,
                                            onHorizontalDragStart: (_) {
                                              _motionController.stop();
                                              _motionController.value =
                                                  _shelfPosition.value;
                                            },
                                            onHorizontalDragUpdate: (details) {
                                              _shelfPosition.value -=
                                                  details.delta.dx /
                                                  _shelfItemExtent;
                                              _touchBookAt(
                                                details.localPosition.dx,
                                                focusX,
                                                books.length,
                                              );
                                            },
                                            onHorizontalDragEnd: (details) =>
                                                _settleShelf(
                                                  books,
                                                  details
                                                      .velocity
                                                      .pixelsPerSecond
                                                      .dx,
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
                                onPrevious:
                                    books.length < 2 ||
                                        (_isLooping(books.length)
                                            ? false
                                            : safeIndex <= 0)
                                    ? null
                                    : () => _stepShelf(books, -1),
                                onNext:
                                    books.length < 2 ||
                                        (_isLooping(books.length)
                                            ? false
                                            : safeIndex >= books.length - 1)
                                    ? null
                                    : () => _stepShelf(books, 1),
                                compact:
                                    MediaQuery.orientationOf(context) ==
                                    Orientation.landscape,
                              ),
                            ),
                          ],
                        )
                      : _buildCollectionView(books),
                ),
            ],
          ),
        ),
        if (_isImporting)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_selectedBookIds.isNotEmpty)
          Positioned(
            left: 18,
            right: 18,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Material(
                color: const Color(0xFF20252A),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '取消选择',
                        onPressed: () => setState(_selectedBookIds.clear),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '已选 ${_selectedBookIds.length} 本',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '导出所选',
                        onPressed: _exportSelected,
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: '删除所选',
                        onPressed: _deleteSelected,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _DuplicateAction { replace, keepBoth, cancel }

enum _ShelfSort {
  recent('最近阅读'),
  imported('最近导入'),
  title('书名排序'),
  author('作者排序'),
  progress('阅读进度'),
  fileSize('文件大小');

  const _ShelfSort(this.label);
  final String label;
}

enum _ShelfFilter {
  all('全部'),
  unread('未读'),
  reading('阅读中'),
  finished('已读完'),
  annotated('有批注');

  const _ShelfFilter(this.label);
  final String label;
}

enum _ShelfViewMode { coverFlow, grid, list }

String _formatBytes(int bytes) {
  if (bytes <= 0) return '未知大小';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.controller,
    required this.onSearchChanged,
    required this.onClear,
    required this.hasQuery,
    required this.onAdd,
    required this.onSort,
    required this.onEditCover,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;
  final bool hasQuery;
  final VoidCallback onAdd;
  final VoidCallback onSort;
  final VoidCallback? onEditCover;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = Theme.of(context).colorScheme.onSurface;
    final iconBg = isDark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .06);
    final iconFg = titleColor;
    final searchFill = isDark
        ? Colors.white.withValues(alpha: .09)
        : Colors.black.withValues(alpha: .05);
    final searchHint = isDark ? Colors.white38 : Colors.black38;
    final searchIcon = isDark ? Colors.white54 : Colors.black54;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '浮光书架',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '书架排序',
                onPressed: onSort,
                style: IconButton.styleFrom(
                  foregroundColor: iconFg,
                  backgroundColor: iconBg,
                ),
                icon: const Icon(Icons.sort_rounded, size: 20),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('add-book-button'),
                tooltip: '导入书籍',
                onPressed: onAdd,
                style: IconButton.styleFrom(
                  foregroundColor: iconFg,
                  backgroundColor: iconBg,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
              if (onEditCover != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('edit-cover-button'),
                  tooltip: '更换当前书籍封面',
                  onPressed: onEditCover,
                  style: IconButton.styleFrom(
                    foregroundColor: iconFg,
                    backgroundColor: iconBg,
                  ),
                  icon: const Icon(Icons.photo_camera_back_outlined, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: TextField(
              key: const ValueKey('library-search'),
              controller: controller,
              onChanged: onSearchChanged,
              style: TextStyle(color: titleColor, fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索书籍',
                hintStyle: TextStyle(color: searchHint, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: searchIcon,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 38),
                suffixIcon: hasQuery
                    ? IconButton(
                        onPressed: onClear,
                        icon: Icon(
                          Icons.close_rounded,
                          color: searchIcon,
                          size: 16,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: searchFill,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: .1)
                        : Colors.black.withValues(alpha: .1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: .28)
                        : Theme.of(context).colorScheme.primary,
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

class _DepthBackground extends StatelessWidget {
  const _DepthBackground({required this.books, required this.fallbackIndex});

  final List<Book> books;
  final int fallbackIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (books.isEmpty) {
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    }
    final glow = books[fallbackIndex].palette.first;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.12),
            radius: .9,
            colors: isDark
                ? [
                    Color.lerp(glow, const Color(0xFF102129), .72)!,
                    const Color(0xFF081116),
                    const Color(0xFF030608),
                  ]
                : [
                    Color.lerp(glow, Colors.white, .75)!,
                    Color.lerp(glow, const Color(0xFFF0F2F5), .88)!,
                    Theme.of(context).scaffoldBackgroundColor,
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
              final loop = _LibraryScreenState._isLooping(books.length);
              // Keep recycled entries outside the visible stage to avoid edge
              // flashes while a transformed card crosses an integer page.
              final radius = books.length == 1 ? 0 : 4;
              final first = loop
                  ? center - radius
                  : math.max(0, center - radius);
              final last = loop
                  ? center + radius
                  : math.min(books.length - 1, center + radius);
              final touched = touchedVirtualIndex.value;
              final committedVirtualIndex = books.length <= 1
                  ? 0
                  : loop
                  ? fallbackIndex +
                        ((page - fallbackIndex) / books.length).round() *
                            books.length
                  : page.round().clamp(0, books.length - 1);
              final entries = <_FlowEntry>[
                for (
                  var virtualIndex = first;
                  virtualIndex <= last;
                  virtualIndex++
                )
                  _FlowEntry(
                    virtualIndex: virtualIndex,
                    bookIndex: loop
                        ? _LibraryScreenState._loopIndex(
                            virtualIndex,
                            books.length,
                          )
                        : virtualIndex,
                    pose: _coverFlowPose(virtualIndex - page),
                    touched: virtualIndex == touched,
                  ),
              ]..sort((a, b) => a.pose.z.compareTo(b.pose.z));
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
    final visual = hasStableTestKey
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
            width: 1,
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
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
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
                  [
                    if (book.displayAuthor.isNotEmpty) book.displayAuthor,
                    '已读 ${(book.progress * 100).round()}%',
                  ].join('  ·  '),
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
  final VoidCallback? onPressed;
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(17),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: Icon(icon, color: colors.onSurface.withValues(alpha: .7)),
        title: Text(
          title,
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: .48),
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colors.onSurface.withValues(alpha: .38),
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    final subdued = _onSurfaceSubdued(context, alpha: .42);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_rounded, size: 48, color: subdued),
          const SizedBox(height: 12),
          Text('没有找到这本书', style: TextStyle(color: subdued)),
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
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 54,
              color: colors.onSurface.withValues(alpha: .28),
            ),
            const SizedBox(height: 16),
            Text(
              '书架还是空的',
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '导入 TXT、EPUB 或 PDF，开始建立你的私人书架。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: .48),
                height: 1.55,
              ),
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
