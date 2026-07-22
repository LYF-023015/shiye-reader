import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../widgets/book_hero.dart';
import '../widgets/native_book_model.dart';
import 'reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'epub_reader_screen.dart';

class BookShowcaseScreen extends StatelessWidget {
  const BookShowcaseScreen({
    super.key,
    required this.book,
    required this.readingStore,
  });

  final Book book;
  final ReadingStore readingStore;

  void _continueReading(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (book.format) {
          BookFormat.pdf => PdfReaderScreen(
            book: book,
            readingStore: readingStore,
          ),
          BookFormat.epub =>
            book.sourceBytes?.isNotEmpty == true
                ? EpubReaderScreen(book: book, readingStore: readingStore)
                : ReaderScreen(book: book, readingStore: readingStore),
          BookFormat.txt => ReaderScreen(
            book: book,
            readingStore: readingStore,
          ),
        },
      ),
    );
  }

  String get _description {
    final fullText = book.chapters.first.content;
    final preview = fullText.length > 1600
        ? fullText.substring(0, 1600)
        : fullText;
    final source = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (source.length <= 108) return source;
    return '${source.substring(0, 108)}……';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(book.palette.last, Colors.black, .62)!;
    final middle = Color.lerp(book.palette.first, Colors.black, .38)!;
    final light = Color.lerp(book.palette[1], Colors.white, .18)!;

    return Scaffold(
      backgroundColor: light,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [dark, middle, light],
                  stops: const [0, .58, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ShowcaseToolbar(book: book, readingStore: readingStore),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        children: [
                          Expanded(flex: 12, child: _BookStage(book: book)),
                          Expanded(
                            flex: 10,
                            child: _BookInformationPanel(
                              book: book,
                              description: _description,
                              accent: dark,
                              onContinue: () => _continueReading(context),
                            ),
                          ),
                        ],
                      );
                    },
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

class _ShowcaseToolbar extends StatelessWidget {
  const _ShowcaseToolbar({required this.book, required this.readingStore});

  final Book book;
  final ReadingStore readingStore;

  void _showActions(BuildContext context) {
    final bookmarked = readingStore
        .stateFor(book)
        .bookmarkedChapters
        .contains(0);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (book.format == BookFormat.txt)
                ListTile(
                  leading: Icon(
                    bookmarked
                        ? Icons.bookmark_remove_rounded
                        : Icons.bookmark_add_rounded,
                  ),
                  title: Text(bookmarked ? '取消第一章书签' : '收藏第一章'),
                  onTap: () {
                    readingStore.toggleBookmark(book, 0);
                    Navigator.pop(sheetContext);
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        [
                          if (book.displayAuthor.isNotEmpty) book.displayAuthor,
                          book.format.name.toUpperCase(),
                          if (book.format == BookFormat.txt)
                            '${book.chapters.length} 章',
                        ].join(' · '),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text('从书架删除', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: sheetContext,
                    builder: (context) => AlertDialog(
                      title: const Text('删除这本书？'),
                      content: Text('《${book.title}》及其阅读进度、书签和批注将被删除。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  readingStore.removeImportedBook(book);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回书架',
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: .2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text(
                  '书籍展厅',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _GlassIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: '更多',
            onPressed: () => _showActions(context),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: .28),
        side: BorderSide(color: Colors.white.withValues(alpha: .48)),
      ),
      icon: Icon(icon, size: 19),
    );
  }
}

class _BookStage extends StatelessWidget {
  const _BookStage({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          190.0,
          math.min(constraints.maxWidth * .54, constraints.maxHeight / 1.48),
        );
        final height = width * 1.48;
        return Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: const Alignment(0, .78),
              child: Transform.scale(
                scaleY: .18,
                child: Container(
                  width: 245,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: .2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .22),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            BookHero(
              book: book,
              child: SizedBox(
                width: width,
                height: height,
                child: NativeBookModel(book: book),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BookInformationPanel extends StatelessWidget {
  const _BookInformationPanel({
    required this.book,
    required this.description,
    required this.accent,
    required this.onContinue,
  });

  final Book book;
  final String description;
  final Color accent;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final percent = (book.progress * 100).round();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = theme.colorScheme.onSurface;
    final secondary = foreground.withValues(alpha: .72);
    final panelColor = isDark
        ? Color.lerp(theme.colorScheme.surface, book.palette.last, .1)!
        : Color.lerp(Colors.white, book.palette[1], .08)!;
    final readableAccent = isDark
        ? Color.lerp(accent, Colors.white, .46)!
        : accent;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panelColor.withValues(alpha: .97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: .16)
                : Colors.white.withValues(alpha: .78),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .14),
            blurRadius: 35,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                        ),
                      ),
                      if (book.displayAuthor.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          book.displayAuthor,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: readableAccent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    '$percent%',
                    style: TextStyle(
                      color: readableAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: book.progress,
                minHeight: 4,
                backgroundColor: readableAccent.withValues(alpha: .12),
                color: readableAccent,
              ),
            ),
            const SizedBox(height: 19),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, height: 1.7, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _BookFact(
                  icon: Icons.menu_book_rounded,
                  value: '${book.chapters.length} 章',
                ),
                const SizedBox(width: 10),
                _BookFact(
                  icon: Icons.schedule_rounded,
                  value: '上次阅读 ${book.lastRead}',
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                key: const ValueKey('continue-reading-button'),
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: readableAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.auto_stories_rounded, size: 20),
                label: const Text(
                  '继续阅读',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookFact extends StatelessWidget {
  const _BookFact({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: colorScheme.onSurface.withValues(alpha: .68),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurface.withValues(alpha: .72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
