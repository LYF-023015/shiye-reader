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
    required this.format,
    this.navigation = const <BookNavigationItem>[],
    this.sourceBytes,
    this.coverBytes,
  });

  final String title;
  final String author;
  final List<Chapter> chapters;
  final BookFormat format;
  final List<BookNavigationItem> navigation;
  final Uint8List? sourceBytes;
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
        format: BookFormat.txt,
      );
    }
    if (extension == 'epub') {
      return Isolate.run(() => _parseEpub(file.bytes, fallbackTitle));
    }
    if (extension == 'pdf') {
      return ImportedBookData(
        title: fallbackTitle,
        author: '作者未知',
        chapters: const [Chapter(title: 'PDF 文档', content: 'PDF 文档')],
        format: BookFormat.pdf,
        sourceBytes: file.bytes,
      );
    }
    throw FormatException('不支持的文件格式：${extension.toUpperCase()}');
  }

  static ImportedBookData _parseEpub(Uint8List bytes, String fallbackTitle) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final expandedBytes = archive.files.fold<int>(
      0,
      (total, file) => total + file.size,
    );
    if (expandedBytes > 300 * 1024 * 1024 ||
        archive.files.any((file) => file.size > 80 * 1024 * 1024)) {
      throw const FormatException('EPUB 解压后的内容过大，已停止导入');
    }
    final files = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) _normalize(file.name): file,
    };
    if (files.containsKey('META-INF/rights.xml')) {
      throw const FormatException('该 EPUB 包含 DRM 权限保护，暂不支持阅读');
    }
    final encryption = _readText(files['META-INF/encryption.xml']);
    if (encryption.contains(RegExp(r'<(?:\w+:)?EncryptedData\b'))) {
      throw const FormatException('该 EPUB 包含加密或 DRM 内容，暂不支持阅读');
    }
    final container = _readText(files['META-INF/container.xml']);
    final containerDocument = XmlDocument.parse(container);
    final rootFile = containerDocument.descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.name.local == 'rootfile')
        .getAttribute('full-path');
    if (rootFile == null) throw const FormatException('Missing OPF');
    final opfPath = _normalize(rootFile);
    final opf = XmlDocument.parse(_readText(files[opfPath]));
    final fixedLayout = opf.descendants.whereType<XmlElement>().any((element) {
      if (element.name.local != 'meta') return false;
      final property = element.getAttribute('property') ?? '';
      final name = element.getAttribute('name') ?? '';
      final value =
          (element.innerText.isNotEmpty
                  ? element.innerText
                  : element.getAttribute('content') ?? '')
              .trim()
              .toLowerCase();
      return (property == 'rendition:layout' || name == 'fixed-layout') &&
          (value == 'pre-paginated' || value == 'true');
    });
    final title = _firstElementText(opf, 'title')?.trim();
    final author = _firstElementText(opf, 'creator')?.trim();
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final manifest = <String, String>{};
    final mediaTypes = <String, String>{};
    final properties = <String, String>{};
    String? coverId;
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'meta' &&
          element.getAttribute('name') == 'cover') {
        coverId = element.getAttribute('content');
      }
      if (element.name.local != 'item') continue;
      final id = element.getAttribute('id');
      final href = element.getAttribute('href');
      if (id != null && href != null) {
        manifest[id] = _resolve(base, href);
        mediaTypes[id] = element.getAttribute('media-type') ?? '';
        properties[id] = element.getAttribute('properties') ?? '';
      }
      if ((element.getAttribute('properties') ?? '').contains('cover-image')) {
        coverId = id;
      }
    }
    final coverPath = coverId == null ? null : manifest[coverId];
    final coverBytes = coverPath == null
        ? null
        : _readBytes(files[_normalize(coverPath)]);

    final navigation = _readNavigation(
      opf: opf,
      opfBase: base,
      files: files,
      manifest: manifest,
      properties: properties,
    );
    final chapters = <Chapter>[];
    final chapterPaths = <String>[];
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
                (node) => const {
                  'script',
                  'form',
                  'iframe',
                  'object',
                  'embed',
                }.contains(node.name.local),
              )
              .toList()) {
        removable.remove();
      }
      final body = document.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'body',
      );
      final contentRoot = body.isEmpty ? document.rootElement : body.first;
      final content = _plainText(contentRoot)
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
          .trim();
      if (content.length < 20) continue;
      final navTitle = navigation
          .where((item) => item.path == _normalize(path))
          .map((item) => item.label)
          .firstOrNull;
      final chapterTitle =
          navTitle ??
          document.descendants
              .whereType<XmlElement>()
              .where(
                (node) => const {'h1', 'h2', 'title'}.contains(node.name.local),
              )
              .map((node) => node.innerText.trim())
              .firstWhere(
                (text) => text.isNotEmpty,
                orElse: () => '第 ${chapters.length + 1} 章',
              );
      _inlineEpubResources(
        document,
        chapterPath: path,
        files: files,
        manifest: manifest,
        mediaTypes: mediaTypes,
      );
      chapters.add(
        Chapter(
          title: chapterTitle,
          content: content,
          html: document.toXmlString(pretty: false),
          sourceHref: _normalize(path),
        ),
      );
      chapterPaths.add(_normalize(path));
    }

    final resolvedNavigation = <BookNavigationItem>[];
    for (final item in navigation) {
      final chapterIndex = chapterPaths.indexOf(item.path);
      if (chapterIndex < 0) continue;
      final content = chapters[chapterIndex].content;
      final characterOffset = item.fragment == null
          ? 0
          : _fragmentOffset(
              chapters[chapterIndex].html ?? '',
              content,
              item.fragment!,
            );
      resolvedNavigation.add(
        BookNavigationItem(
          label: item.label,
          chapterIndex: chapterIndex,
          characterOffset: characterOffset,
          depth: item.depth,
        ),
      );
    }

    return ImportedBookData(
      title: title?.isNotEmpty == true ? title! : fallbackTitle,
      author: author?.isNotEmpty == true ? author! : '作者未知',
      format: BookFormat.epub,
      sourceBytes: bytes,
      coverBytes: coverBytes,
      navigation: resolvedNavigation,
      chapters: chapters.isEmpty
          ? fixedLayout
                ? const [Chapter(title: '固定版式', content: '固定版式 EPUB')]
                : (throw const FormatException('EPUB 中没有可阅读正文'))
          : chapters,
    );
  }

  static List<_EpubNavigationEntry> _readNavigation({
    required XmlDocument opf,
    required String opfBase,
    required Map<String, ArchiveFile> files,
    required Map<String, String> manifest,
    required Map<String, String> properties,
  }) {
    final navId = properties.entries
        .where((entry) => entry.value.split(RegExp(r'\s+')).contains('nav'))
        .map((entry) => entry.key)
        .firstOrNull;
    if (navId != null) {
      final navPath = manifest[navId];
      final raw = navPath == null ? '' : _readText(files[_normalize(navPath)]);
      if (raw.isNotEmpty) {
        final document = XmlDocument.parse(raw);
        final toc = document.descendants.whereType<XmlElement>().where((node) {
          if (node.name.local != 'nav') return false;
          return node.attributes.any(
            (attribute) =>
                attribute.name.local == 'type' &&
                attribute.value.split(RegExp(r'\s+')).contains('toc'),
          );
        }).firstOrNull;
        if (toc != null) {
          final base = _directoryOf(navPath!);
          return toc.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'a')
              .map((element) {
                final href = element.getAttribute('href') ?? '';
                final uri = href.split('#');
                return _EpubNavigationEntry(
                  label: element.innerText.trim(),
                  path: _resolve(base, uri.first),
                  fragment: uri.length > 1 ? uri.sublist(1).join('#') : null,
                  depth: element.ancestors
                      .whereType<XmlElement>()
                      .where((ancestor) => ancestor.name.local == 'ol')
                      .length
                      .clamp(0, 5),
                );
              })
              .where((entry) => entry.label.isNotEmpty && entry.path.isNotEmpty)
              .toList();
        }
      }
    }

    final spine = opf.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'spine')
        .firstOrNull;
    final ncxId = spine?.getAttribute('toc');
    final fallbackNcxId = manifest.keys
        .where((id) => manifest[id]?.toLowerCase().endsWith('.ncx') == true)
        .firstOrNull;
    final ncxPath = manifest[ncxId ?? fallbackNcxId];
    final raw = ncxPath == null ? '' : _readText(files[_normalize(ncxPath)]);
    if (raw.isEmpty) return const [];
    final document = XmlDocument.parse(raw);
    final base = _directoryOf(ncxPath!);
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'navPoint')
        .map((point) {
          final label = point.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'navLabel')
              .map((element) => element.innerText.trim())
              .firstOrNull;
          final source = point.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'content')
              .map((element) => element.getAttribute('src'))
              .whereType<String>()
              .firstOrNull;
          final uri = (source ?? '').split('#');
          return _EpubNavigationEntry(
            label: label ?? '',
            path: uri.first.isEmpty ? '' : _resolve(base, uri.first),
            fragment: uri.length > 1 ? uri.sublist(1).join('#') : null,
            depth: point.ancestors
                .whereType<XmlElement>()
                .where((ancestor) => ancestor.name.local == 'navPoint')
                .length
                .clamp(0, 5),
          );
        })
        .where((entry) => entry.label.isNotEmpty && entry.path.isNotEmpty)
        .toList();
  }

  static void _inlineEpubResources(
    XmlDocument document, {
    required String chapterPath,
    required Map<String, ArchiveFile> files,
    required Map<String, String> manifest,
    required Map<String, String> mediaTypes,
  }) {
    final chapterBase = _directoryOf(chapterPath);
    final mimeByPath = <String, String>{
      for (final entry in manifest.entries)
        if (mediaTypes[entry.key]?.isNotEmpty == true)
          _normalize(entry.value): mediaTypes[entry.key]!,
    };

    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'link' &&
          (element.getAttribute('rel') ?? '').toLowerCase().contains(
            'stylesheet',
          )) {
        final href = element.getAttribute('href');
        final path = href == null ? null : _resolve(chapterBase, href);
        final css = path == null ? '' : _readText(files[_normalize(path)]);
        if (css.isNotEmpty) {
          final inlined = _inlineCssResources(
            css,
            cssBase: _directoryOf(path!),
            files: files,
            mimeByPath: mimeByPath,
          );
          element.replace(
            XmlElement(const XmlName.parts('style'), [], [XmlText(inlined)]),
          );
        }
        continue;
      }

      for (final attributeName in const ['src', 'poster']) {
        final source = element.getAttribute(attributeName);
        if (source == null || source.startsWith('data:')) continue;
        final path = _resolve(chapterBase, source);
        final data = _dataUri(
          files[_normalize(path)],
          mimeByPath[_normalize(path)] ?? _mimeForPath(path),
        );
        if (data != null) element.setAttribute(attributeName, data);
      }
      final style = element.getAttribute('style');
      if (style != null) {
        element.setAttribute(
          'style',
          _inlineCssResources(
            style,
            cssBase: chapterBase,
            files: files,
            mimeByPath: mimeByPath,
          ),
        );
      }
    }

    for (final style in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'style',
    )) {
      final value = style.innerText;
      if (value.isEmpty) continue;
      style.children
        ..clear()
        ..add(
          XmlText(
            _inlineCssResources(
              value,
              cssBase: chapterBase,
              files: files,
              mimeByPath: mimeByPath,
            ),
          ),
        );
    }
  }

  static String _inlineCssResources(
    String css, {
    required String cssBase,
    required Map<String, ArchiveFile> files,
    required Map<String, String> mimeByPath,
  }) =>
      css.replaceAllMapped(RegExp(r'''url\(\s*(['"]?)(.*?)\1\s*\)'''), (match) {
        final source = match.group(2)?.trim() ?? '';
        if (source.isEmpty ||
            source.startsWith('data:') ||
            source.startsWith('#')) {
          return match.group(0)!;
        }
        final path = _resolve(cssBase, source);
        final data = _dataUri(
          files[_normalize(path)],
          mimeByPath[_normalize(path)] ?? _mimeForPath(path),
        );
        return data == null ? match.group(0)! : 'url("$data")';
      });

  static String? _dataUri(ArchiveFile? file, String mimeType) {
    final bytes = _readBytes(file);
    if (bytes == null || bytes.isEmpty) return null;
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  static String _mimeForPath(String path) {
    final extension = _extension(path);
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      _ => 'application/octet-stream',
    };
  }

  static String _plainText(XmlElement root) {
    const blocks = {
      'address',
      'article',
      'aside',
      'blockquote',
      'br',
      'div',
      'figcaption',
      'figure',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'li',
      'main',
      'nav',
      'p',
      'pre',
      'section',
      'table',
      'tr',
    };
    final buffer = StringBuffer();
    void walk(XmlNode node) {
      if (node is XmlText) {
        buffer.write(node.value);
        return;
      }
      if (node is! XmlElement) return;
      final block = blocks.contains(node.name.local);
      if (block && buffer.isNotEmpty) buffer.write('\n');
      for (final child in node.children) {
        walk(child);
      }
      if (block) buffer.write('\n');
    }

    walk(root);
    return buffer.toString();
  }

  static int _fragmentOffset(String html, String plainText, String fragment) {
    final escaped = RegExp.escape(fragment);
    final match = RegExp(
      '<[^>]+(?:id|name)=["\']$escaped["\'][^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return 0;
    final prefix = html
        .substring(0, match.start)
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    final normalized = prefix.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length.clamp(0, plainText.length);
  }

  static String _directoryOf(String path) {
    final normalized = _normalize(path);
    return normalized.contains('/')
        ? normalized.substring(0, normalized.lastIndexOf('/') + 1)
        : '';
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
    if (match == null) return (title: title, author: '');
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
      r'^[ \t]*(?:[【\[]?[第卷][ \t]*[0-9０-９零一二三四五六七八九十百千万两〇]+[ \t]*[章节卷回部篇]?[】\]]?[^\r\n]{0,40}|[【\[]?(?:序章|楔子|前言|后记|尾声|番外(?:篇)?)[】\]]?[^\r\n]{0,30}|(?:chapter|part|volume)[ \t]+[0-9ivxlcdm]+[^\r\n]{0,40})[ \t]*$',
      multiLine: true,
      caseSensitive: false,
    );
    final matches = heading.allMatches(content).toList();
    if (matches.isNotEmpty) {
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

class _EpubNavigationEntry {
  const _EpubNavigationEntry({
    required this.label,
    required this.path,
    required this.fragment,
    required this.depth,
  });

  final String label;
  final String path;
  final String? fragment;
  final int depth;
}
