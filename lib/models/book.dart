import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum BookBindingStyle { hardcover, clothbound, paperback, japaneseBinding }

enum BookFormat { txt, epub, pdf }

class BookNavigationItem {
  const BookNavigationItem({
    required this.label,
    required this.chapterIndex,
    this.characterOffset = 0,
    this.depth = 0,
  });

  final String label;
  final int chapterIndex;
  final int characterOffset;
  final int depth;

  Map<String, Object?> toJson() => {
    'label': label,
    'chapterIndex': chapterIndex,
    'characterOffset': characterOffset,
    'depth': depth,
  };

  factory BookNavigationItem.fromJson(Map<String, Object?> json) =>
      BookNavigationItem(
        label: json['label'] as String? ?? '章节',
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
        characterOffset: (json['characterOffset'] as num?)?.toInt() ?? 0,
        depth: (json['depth'] as num?)?.toInt() ?? 0,
      );
}

class Chapter {
  const Chapter({
    required this.title,
    required this.content,
    this.html,
    this.sourceHref,
  });

  final String title;
  final String content;
  final String? html;
  final String? sourceHref;

  bool get hasRichContent => html?.trim().isNotEmpty == true;

  Map<String, Object?> toJson() => {
    'title': title,
    'content': content,
    if (html != null) 'html': html,
    if (sourceHref != null) 'sourceHref': sourceHref,
  };

  factory Chapter.fromJson(Map<String, Object?> json) => Chapter(
    title: json['title'] as String? ?? '正文',
    content: json['content'] as String? ?? '',
    html: json['html'] as String?,
    sourceHref: json['sourceHref'] as String?,
  );
}

class Book {
  const Book({
    required this.title,
    required this.author,
    required this.lastRead,
    required this.progress,
    required this.palette,
    required this.coverMark,
    required this.chapters,
    this.storageId = '',
    this.format = BookFormat.txt,
    this.importedAt,
    this.fileSize = 0,
    this.navigation = const <BookNavigationItem>[],
    this.sourceBytes,
    this.coverAsset,
    this.coverBytes,
    this.overlayCoverText = false,
    this.coverTemplate = 0,
    this.bindingStyle = BookBindingStyle.hardcover,
  });

  final String title;
  final String author;
  final String lastRead;
  final double progress;
  final List<Color> palette;
  final String coverMark;
  final String? coverAsset;
  final Uint8List? coverBytes;
  final String storageId;
  final BookFormat format;
  final DateTime? importedAt;
  final int fileSize;
  final List<BookNavigationItem> navigation;
  final Uint8List? sourceBytes;

  /// Whether title/author typography should be added to artwork-only covers.
  final bool overlayCoverText;
  final int coverTemplate;
  final BookBindingStyle bindingStyle;
  final List<Chapter> chapters;

  String get id =>
      storageId.isEmpty ? '${title.trim()}::${author.trim()}' : storageId;

  Book copyWith({
    String? title,
    String? author,
    String? lastRead,
    double? progress,
    List<Color>? palette,
    String? coverMark,
    List<Chapter>? chapters,
    String? storageId,
    BookFormat? format,
    DateTime? importedAt,
    int? fileSize,
    List<BookNavigationItem>? navigation,
    Uint8List? sourceBytes,
    String? coverAsset,
    Uint8List? coverBytes,
    bool? overlayCoverText,
    int? coverTemplate,
    BookBindingStyle? bindingStyle,
  }) => Book(
    title: title ?? this.title,
    author: author ?? this.author,
    lastRead: lastRead ?? this.lastRead,
    progress: progress ?? this.progress,
    palette: palette ?? this.palette,
    coverMark: coverMark ?? this.coverMark,
    chapters: chapters ?? this.chapters,
    storageId: storageId ?? this.storageId,
    format: format ?? this.format,
    importedAt: importedAt ?? this.importedAt,
    fileSize: fileSize ?? this.fileSize,
    navigation: navigation ?? this.navigation,
    sourceBytes: sourceBytes ?? this.sourceBytes,
    coverAsset: coverAsset ?? this.coverAsset,
    coverBytes: coverBytes ?? this.coverBytes,
    overlayCoverText: overlayCoverText ?? this.overlayCoverText,
    coverTemplate: coverTemplate ?? this.coverTemplate,
    bindingStyle: bindingStyle ?? this.bindingStyle,
  );

  Map<String, Object?> toJson({
    bool includeBinary = true,
    bool includeChapters = true,
  }) => {
    'id': id,
    'title': title,
    'author': author,
    'lastRead': lastRead,
    'progress': progress,
    'palette': palette.map((color) => color.toARGB32()).toList(),
    'coverMark': coverMark,
    if (includeChapters)
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'format': format.name,
    'importedAt': importedAt?.toIso8601String(),
    'fileSize': fileSize,
    'navigation': navigation.map((item) => item.toJson()).toList(),
    if (includeBinary && sourceBytes != null)
      'sourceBytes': base64Encode(sourceBytes!),
    'coverAsset': coverAsset,
    'coverBytes': includeBinary && coverBytes != null
        ? base64Encode(coverBytes!)
        : null,
    'overlayCoverText': overlayCoverText,
    'coverTemplate': coverTemplate,
    'bindingStyle': bindingStyle.name,
  };

  factory Book.fromJson(Map<String, Object?> json) {
    final rawPalette = json['palette'] as List<Object?>? ?? const [];
    final rawChapters = json['chapters'] as List<Object?>? ?? const [];
    final encodedCover = json['coverBytes'] as String?;
    final encodedSource = json['sourceBytes'] as String?;
    final bindingName = json['bindingStyle'] as String?;
    final formatName = json['format'] as String?;
    final rawNavigation = json['navigation'] as List<Object?>? ?? const [];
    return Book(
      storageId: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名书籍',
      author: json['author'] as String? ?? '本地导入',
      lastRead: json['lastRead'] as String? ?? '尚未阅读',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      palette: rawPalette.isEmpty
          ? const [Color(0xFF8AA8B8), Color(0xFFDDE8EC), Color(0xFF263A46)]
          : rawPalette.map((value) => Color((value as num).toInt())).toList(),
      coverMark: json['coverMark'] as String? ?? '本地书籍',
      chapters: rawChapters
          .whereType<Map>()
          .map((value) => Chapter.fromJson(value.cast<String, Object?>()))
          .toList(),
      format: BookFormat.values.firstWhere(
        (format) => format.name == formatName,
        orElse: () => BookFormat.txt,
      ),
      importedAt: DateTime.tryParse(json['importedAt'] as String? ?? ''),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      navigation: rawNavigation
          .whereType<Map>()
          .map(
            (value) =>
                BookNavigationItem.fromJson(value.cast<String, Object?>()),
          )
          .toList(),
      sourceBytes: encodedSource == null ? null : base64Decode(encodedSource),
      coverAsset: json['coverAsset'] as String?,
      coverBytes: encodedCover == null ? null : base64Decode(encodedCover),
      overlayCoverText: json['overlayCoverText'] as bool? ?? false,
      coverTemplate: (json['coverTemplate'] as num?)?.toInt() ?? 0,
      bindingStyle: BookBindingStyle.values.firstWhere(
        (style) => style.name == bindingName,
        orElse: () => BookBindingStyle.hardcover,
      ),
    );
  }
}
