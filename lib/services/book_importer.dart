import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:xml/xml.dart';

import '../models/book.dart';
import 'local_file_picker.dart';

class ImportedBookData {
  const ImportedBookData({
    required this.title,
    required this.author,
    required this.chapters,
    this.coverBytes,
  });

  final String title;
  final String author;
  final List<Chapter> chapters;
  final Uint8List? coverBytes;
}

abstract final class BookImporter {
  static Future<ImportedBookData> parse(PickedLocalFile file) async {
    final extension = _extension(file.name);
    final fallbackTitle = _cleanTitle(file.name);
    if (extension == 'txt') {
      final metadata = _metadataFromFileName(file.name);
      final chapters = await Isolate.run(() {
        final content = _decodeText(file.bytes).trim();
        return _splitTxtIntoChapters(content);
      });
      return ImportedBookData(
        title: metadata.title,
        author: metadata.author,
        chapters: chapters,
      );
    }
    if (extension == 'epub') {
      return _parseEpub(file.bytes, fallbackTitle);
    }
    if (extension == 'pdf') {
      throw const FormatException('当前版本暂不支持 PDF 正文阅读');
    }
    throw FormatException('不支持的文件格式：${extension.toUpperCase()}');
  }

  static ImportedBookData _parseEpub(Uint8List bytes, String fallbackTitle) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) _normalize(file.name): file,
    };
    final container = _readText(files['META-INF/container.xml']);
    final containerDocument = XmlDocument.parse(container);
    final rootFile = containerDocument.descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.name.local == 'rootfile')
        .getAttribute('full-path');
    if (rootFile == null) throw const FormatException('Missing OPF');
    final opfPath = _normalize(rootFile);
    final opf = XmlDocument.parse(_readText(files[opfPath]));
    final title = _firstElementText(opf, 'title')?.trim();
    final author = _firstElementText(opf, 'creator')?.trim();
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final manifest = <String, String>{};
    String? coverId;
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'meta' &&
          element.getAttribute('name') == 'cover') {
        coverId = element.getAttribute('content');
      }
      if (element.name.local != 'item') continue;
      final id = element.getAttribute('id');
      final href = element.getAttribute('href');
      if (id != null && href != null) manifest[id] = _resolve(base, href);
      if ((element.getAttribute('properties') ?? '').contains('cover-image')) {
        coverId = id;
      }
    }
    final coverPath = coverId == null ? null : manifest[coverId];
    final coverBytes = coverPath == null
        ? null
        : _readBytes(files[_normalize(coverPath)]);

    final chapters = <Chapter>[];
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'itemref') continue;
      final id = element.getAttribute('idref');
      final path = id == null ? null : manifest[id];
      if (path == null) continue;
      final raw = _readText(files[_normalize(path)]);
      if (raw.isEmpty) continue;
      final document = XmlDocument.parse(raw);
      for (final removable
          in document.descendants
              .whereType<XmlElement>()
              .where(
                (node) =>
                    const {'script', 'style', 'nav'}.contains(node.name.local),
              )
              .toList()) {
        removable.remove();
      }
      final body = document.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'body',
      );
      final content = (body.isEmpty ? document.innerText : body.first.innerText)
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
          .trim();
      if (content.length < 20) continue;
      final chapterTitle = document.descendants
          .whereType<XmlElement>()
          .where(
            (node) => const {'h1', 'h2', 'title'}.contains(node.name.local),
          )
          .map((node) => node.innerText.trim())
          .firstWhere(
            (text) => text.isNotEmpty,
            orElse: () => '第 ${chapters.length + 1} 章',
          );
      chapters.add(Chapter(title: chapterTitle, content: content));
      if (chapters.length >= 120) break;
    }

    return ImportedBookData(
      title: title?.isNotEmpty == true ? title! : fallbackTitle,
      author: author?.isNotEmpty == true ? author! : '作者未知',
      coverBytes: coverBytes,
      chapters: chapters.isEmpty
          ? (throw const FormatException('EPUB 中没有可阅读正文'))
          : chapters,
    );
  }

  static Uint8List? _readBytes(ArchiveFile? file) {
    if (file == null) return null;
    return file.content;
  }

  static String _readText(ArchiveFile? file) {
    final bytes = _readBytes(file);
    return bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  static String? _firstElementText(XmlDocument document, String localName) {
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element.innerText;
    }
    return null;
  }

  static String _resolve(String base, String href) {
    final decoded = Uri.decodeFull(href.split('#').first);
    final parts = <String>[];
    for (final part in '$base$decoded'.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static String _normalize(String value) => value.replaceAll('\\', '/');

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String _cleanTitle(String name) {
    final dot = name.lastIndexOf('.');
    final raw = dot > 0 ? name.substring(0, dot) : name;
    final value = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return value.isEmpty ? '未命名书籍' : value;
  }

  static ({String title, String author}) _metadataFromFileName(String name) {
    final title = _cleanTitle(name);
    final match = RegExp(r'^《(.+?)》\s*作者\s*[：:]\s*(.+)$').firstMatch(title);
    if (match == null) return (title: title, author: '本地导入');
    return (title: match.group(1)!.trim(), author: match.group(2)!.trim());
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, littleEndian: true, offset: 2);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, littleEndian: false, offset: 2);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return const GbkCodec(allowMalformed: true).decode(bytes);
    }
  }

  static String _decodeUtf16(
    Uint8List bytes, {
    required bool littleEndian,
    required int offset,
  }) {
    final units = <int>[];
    for (var index = offset; index + 1 < bytes.length; index += 2) {
      units.add(
        littleEndian
            ? bytes[index] | (bytes[index + 1] << 8)
            : (bytes[index] << 8) | bytes[index + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static List<Chapter> _splitTxtIntoChapters(String content) {
    if (content.isEmpty) {
      return const [Chapter(title: '正文', content: '这个 TXT 文件没有可读取的文字。')];
    }
    final heading = RegExp(
      r'^[ \t]*第[0-9零一二三四五六七八九十百千万两〇]+[章节卷回部篇][^\r\n]*',
      multiLine: true,
    );
    final matches = heading.allMatches(content).toList();
    if (matches.length >= 2) {
      final chapters = <Chapter>[];
      final preface = content.substring(0, matches.first.start).trim();
      if (preface.length >= 20) {
        chapters.add(Chapter(title: '前言', content: preface));
      }
      for (var index = 0; index < matches.length; index++) {
        final match = matches[index];
        final end = index + 1 < matches.length
            ? matches[index + 1].start
            : content.length;
        final body = content.substring(match.end, end).trim();
        if (body.isNotEmpty) {
          chapters.add(Chapter(title: match.group(0)!.trim(), content: body));
        }
      }
      if (chapters.isNotEmpty) return chapters;
    }

    const chunkSize = 12000;
    final chapters = <Chapter>[];
    var offset = 0;
    while (offset < content.length) {
      var end = (offset + chunkSize).clamp(0, content.length);
      if (end < content.length) {
        final paragraph = content.lastIndexOf('\n', end);
        if (paragraph > offset + chunkSize ~/ 2) end = paragraph;
      }
      chapters.add(
        Chapter(
          title: chapters.isEmpty ? '正文' : '正文 ${chapters.length + 1}',
          content: content.substring(offset, end).trim(),
        ),
      );
      offset = end;
      while (offset < content.length &&
          (content.codeUnitAt(offset) == 10 ||
              content.codeUnitAt(offset) == 13)) {
        offset++;
      }
    }
    return chapters;
  }
}
