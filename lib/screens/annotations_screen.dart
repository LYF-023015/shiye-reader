import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../services/document_service.dart';
import '../services/reading_store.dart';
import 'reader_screen.dart';
import 'epub_reader_screen.dart';

class AnnotationsScreen extends StatefulWidget {
  const AnnotationsScreen({super.key, required this.readingStore});

  final ReadingStore readingStore;

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  String _query = '';
  bool _oldestFirst = false;

  List<BookAnnotationEntry> get _entries {
    final query = _query.trim().toLowerCase();
    final result = widget.readingStore.allAnnotations.where((entry) {
      if (query.isEmpty) return true;
      final chapter = entry.annotation.chapterIndex.clamp(
        0,
        entry.book.chapters.length - 1,
      );
      return '${entry.book.title}\n${entry.book.author}\n${entry.book.chapters[chapter].title}\n${entry.annotation.selectedText}\n${entry.annotation.note}'
          .toLowerCase()
          .contains(query);
    }).toList();
    if (_oldestFirst) return result.reversed.toList();
    return result;
  }

  Future<void> _export(String format) async {
    final entries = _entries;
    try {
      if (format == 'share') {
        await SharePlus.instance.share(
          ShareParams(
            title: '拾页批注',
            text: widget.readingStore.exportAnnotationEntriesMarkdown(entries),
          ),
        );
        return;
      }
      final json = format == 'json';
      final saved = await DocumentService.saveText(
        name: 'Shiye-annotations.${json ? 'json' : 'md'}',
        content: json
            ? widget.readingStore.exportAnnotationEntriesJson(entries)
            : widget.readingStore.exportAnnotationEntriesMarkdown(entries),
        mimeType: json ? 'application/json' : 'text/markdown',
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导出 ${entries.length} 条批注')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('批注导出失败')));
      }
    }
  }

  void _open(BookAnnotationEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            entry.book.format == BookFormat.epub &&
                entry.book.sourceBytes?.isNotEmpty == true
            ? EpubReaderScreen(
                book: entry.book,
                readingStore: widget.readingStore,
                initialCfi: entry.annotation.epubCfi,
              )
            : ReaderScreen(
                book: entry.book,
                readingStore: widget.readingStore,
                initialChapterIndex: entry.annotation.chapterIndex,
                initialCharacterOffset: entry.annotation.characterStart,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.readingStore,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final entries = _entries;
        final subdued = colors.onSurface.withValues(alpha: .58);
        final faint = colors.onSurface.withValues(alpha: .38);

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回',
                        color: subdued,
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      Text(
                        '批注中心',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _oldestFirst ? '最新优先' : '最早优先',
                        color: subdued,
                        onPressed: () =>
                            setState(() => _oldestFirst = !_oldestFirst),
                        icon: const Icon(Icons.swap_vert_rounded),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '导出批注',
                        iconColor: subdued,
                        onSelected: _export,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'md',
                            child: Text(
                              _query.isEmpty ? '导出 Markdown' : '导出当前结果',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'json',
                            child: Text('导出 JSON'),
                          ),
                          const PopupMenuItem(
                            value: 'share',
                            child: Text('分享到其他应用'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    key: const ValueKey('annotation-search'),
                    onChanged: (value) => setState(() => _query = value),
                    style: TextStyle(color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: '搜索书名、章节、摘录或笔记',
                      hintStyle: TextStyle(color: faint),
                      prefixIcon: Icon(Icons.search_rounded, color: subdued),
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: .55,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            '还没有匹配的批注',
                            style: TextStyle(color: faint),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) =>
                              Divider(color: theme.dividerColor, height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final chapter = entry.annotation.chapterIndex.clamp(
                              0,
                              entry.book.chapters.length - 1,
                            );
                            return ListTile(
                              key: ValueKey(
                                'global-annotation-${entry.annotation.id}',
                              ),
                              onTap: () => _open(entry),
                              title: Text(
                                entry.book.title,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${entry.book.chapters[chapter].title}\n“${entry.annotation.selectedText}”${entry.annotation.note.isEmpty ? '' : '\n${entry.annotation.note}'}',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: subdued),
                              ),
                              trailing: IconButton(
                                tooltip: '删除',
                                onPressed: () =>
                                    widget.readingStore.removeAnnotation(
                                      entry.book,
                                      entry.annotation,
                                    ),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: colors.error.withValues(alpha: .78),
                                ),
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
    );
  }
}
