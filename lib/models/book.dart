import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum BookBindingStyle { hardcover, clothbound, paperback, japaneseBinding }

class Chapter {
  const Chapter({required this.title, required this.content});

  final String title;
  final String content;

  Map<String, Object?> toJson() => {'title': title, 'content': content};

  factory Chapter.fromJson(Map<String, Object?> json) => Chapter(
    title: json['title'] as String? ?? '正文',
    content: json['content'] as String? ?? '',
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

  /// Whether title/author typography should be added to artwork-only covers.
  final bool overlayCoverText;
  final int coverTemplate;
  final BookBindingStyle bindingStyle;
  final List<Chapter> chapters;

  String get id => '${title.trim()}::${author.trim()}';

  Book copyWith({
    String? title,
    String? author,
    String? lastRead,
    double? progress,
    List<Color>? palette,
    String? coverMark,
    List<Chapter>? chapters,
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
    coverAsset: coverAsset ?? this.coverAsset,
    coverBytes: coverBytes ?? this.coverBytes,
    overlayCoverText: overlayCoverText ?? this.overlayCoverText,
    coverTemplate: coverTemplate ?? this.coverTemplate,
    bindingStyle: bindingStyle ?? this.bindingStyle,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'author': author,
    'lastRead': lastRead,
    'progress': progress,
    'palette': palette.map((color) => color.toARGB32()).toList(),
    'coverMark': coverMark,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'coverAsset': coverAsset,
    'coverBytes': coverBytes == null || coverBytes!.lengthInBytes > 8000000
        ? null
        : base64Encode(coverBytes!),
    'overlayCoverText': overlayCoverText,
    'coverTemplate': coverTemplate,
    'bindingStyle': bindingStyle.name,
  };

  factory Book.fromJson(Map<String, Object?> json) {
    final rawPalette = json['palette'] as List<Object?>? ?? const [];
    final rawChapters = json['chapters'] as List<Object?>? ?? const [];
    final encodedCover = json['coverBytes'] as String?;
    final bindingName = json['bindingStyle'] as String?;
    return Book(
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
