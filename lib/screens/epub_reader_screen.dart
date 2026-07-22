import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../services/reading_store.dart';

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({
    super.key,
    required this.book,
    required this.readingStore,
    this.initialCfi,
  });

  final Book book;
  final ReadingStore readingStore;
  final String? initialCfi;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final EpubController _controller = EpubController();
  final DateTime _openedAt = DateTime.now();
  late final Future<File> _source = _prepareSource();
  List<EpubChapter> _chapters = const [];
  EpubTextSelection? _selection;
  bool _loaded = false;

  Future<File> _prepareSource() async {
    final bytes = widget.book.sourceBytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('EPUB 原文件缺失，请重新导入');
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'shiye-${widget.book.id.hashCode}-${bytes.length}.epub',
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }

  @override
  void dispose() {
    widget.readingStore.recordSession(
      widget.book,
      DateTime.now().difference(_openedAt),
    );
    super.dispose();
  }

  Future<void> _showSearch() async {
    final queryController = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全文搜索'),
        content: TextField(
          controller: queryController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: const InputDecoration(hintText: '输入正文内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, queryController.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    queryController.dispose();
    if (query?.trim().isNotEmpty != true || !mounted) return;
    try {
      final results = await _controller.search(query: query!.trim());
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: results.isEmpty
                ? const Center(child: Text('没有找到相关内容'))
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      title: Text(results[index].excerpt),
                      onTap: () {
                        Navigator.pop(context);
                        _controller.display(cfi: results[index].cfi);
                      },
                    ),
                  ),
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('EPUB 搜索失败')));
      }
    }
  }

  void _showContents() {
    final entries = <({EpubChapter chapter, int depth})>[];
    void add(List<EpubChapter> chapters, int depth) {
      for (final chapter in chapters) {
        entries.add((chapter: chapter, depth: depth));
        add(chapter.subitems, depth + 1);
      }
    }

    add(_chapters, 0);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: entries.isEmpty
              ? const Center(child: Text('这本书没有可用目录'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      contentPadding: EdgeInsets.only(
                        left: 18 + entry.depth * 16,
                        right: 18,
                      ),
                      title: Text(entry.chapter.title),
                      onTap: () {
                        Navigator.pop(context);
                        _controller.display(cfi: entry.chapter.href);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _addAnnotation() async {
    final selection = _selection;
    if (selection == null || selection.selectedText.trim().isEmpty) return;
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加批注'),
        content: TextField(
          controller: noteController,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '写下想法（可选）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, noteController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null) return;
    widget.readingStore.addAnnotation(
      widget.book,
      BookAnnotation(
        chapterIndex: 0,
        epubCfi: selection.selectionCfi,
        selectedText: selection.selectedText.trim(),
        note: note.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _controller
      ..addHighlight(cfi: selection.selectionCfi)
      ..clearSelection();
    if (mounted) setState(() => _selection = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.readingStore.stateFor(widget.book);
    final preferences = widget.readingStore.readerPreferences;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '全文搜索',
            onPressed: _loaded ? _showSearch : null,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '目录',
            onPressed: _loaded ? _showContents : null,
            icon: const Icon(Icons.format_list_bulleted_rounded),
          ),
        ],
      ),
      body: FutureBuilder<File>(
        future: _source,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return EpubViewer(
            epubController: _controller,
            epubSource: EpubSource.fromFile(snapshot.data!),
            initialCfi: widget.initialCfi ?? state.epubCfi,
            displaySettings: EpubDisplaySettings(
              fontSize: preferences.fontSize.round(),
              flow: preferences.pageTurn == '上下滚动'
                  ? EpubFlow.scrolled
                  : EpubFlow.paginated,
              spread: EpubSpread.none,
              snap: preferences.pageTurn != '上下滚动',
              useSnapAnimationAndroid: false,
              allowScriptedContent: false,
            ),
            onEpubLoaded: () {
              if (!mounted) return;
              setState(() => _loaded = true);
              for (final annotation
                  in widget.readingStore.stateFor(widget.book).annotations) {
                final cfi = annotation.epubCfi;
                if (cfi != null && cfi.isNotEmpty) {
                  _controller.addHighlight(cfi: cfi);
                }
              }
            },
            onChaptersLoaded: (chapters) => _chapters = chapters,
            onRelocated: (location) => widget.readingStore.updateEpubProgress(
              widget.book,
              location.progress,
              location.startCfi,
            ),
            onTextSelected: (selection) {
              if (mounted) setState(() => _selection = selection);
            },
            onDeselection: () {
              if (mounted) setState(() => _selection = null);
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: _loaded ? _controller.prev : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${(state.progress * 100).round()}%'),
              IconButton(
                tooltip: '添加批注',
                onPressed: _selection == null ? null : _addAnnotation,
                icon: const Icon(Icons.add_comment_outlined),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: _loaded ? _controller.next : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
