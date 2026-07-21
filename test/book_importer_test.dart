import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/services/book_importer.dart';
import 'package:reading_app/services/local_file_picker.dart';

void main() {
  test('EPUB 导入会读取元数据、正文和内嵌封面', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string('OPS/book.opf', '''<?xml version="1.0"?>
          <package xmlns:dc="http://purl.org/dc/elements/1.1/">
            <metadata><dc:title>测试 EPUB</dc:title><dc:creator>测试作者</dc:creator></metadata>
            <manifest>
              <item id="cover" href="cover.png" properties="cover-image"/>
              <item id="c1" href="chapter.xhtml"/>
            </manifest>
            <spine><itemref idref="c1"/></spine>
          </package>'''),
      )
      ..addFile(ArchiveFile.bytes('OPS/cover.png', [1, 2, 3, 4]))
      ..addFile(
        ArchiveFile.string(
          'OPS/chapter.xhtml',
          '<html><head><title>开篇</title></head><body><h1>第一章</h1><p>这是可读取的 EPUB 正文内容，长度足够通过解析。</p></body></html>',
        ),
      );
    final zip = ZipEncoder().encode(archive);
    final result = await BookImporter.parse(
      PickedLocalFile(name: 'fallback.epub', bytes: Uint8List.fromList(zip)),
    );

    expect(result.title, '测试 EPUB');
    expect(result.author, '测试作者');
    expect(result.coverBytes, [1, 2, 3, 4]);
    expect(result.chapters.single.content, contains('EPUB 正文内容'));
  });

  test('TXT 无封面时保留完整正文并交给模板系统', () async {
    final result = await BookImporter.parse(
      PickedLocalFile(
        name: '我的文本.txt',
        bytes: Uint8List.fromList(utf8.encode('可以选择和复制的正文')),
      ),
    );
    expect(result.title, '我的文本');
    expect(result.coverBytes, isNull);
    expect(result.chapters.single.content, contains('选择和复制'));
  });

  test('GBK TXT 会正确识别书名作者并按章节拆分', () async {
    const source = '''第一章 初来乍到
这是超级系统的第一章正文。

第二章 系统启动
中文内容不应该出现乱码。''';
    final result = await BookImporter.parse(
      PickedLocalFile(
        name: '《超级系统》作者：疯狂小强.txt',
        bytes: Uint8List.fromList(const GbkCodec().encode(source)),
      ),
    );

    expect(result.title, '超级系统');
    expect(result.author, '疯狂小强');
    expect(result.chapters, hasLength(2));
    expect(result.chapters.last.content, contains('中文内容不应该出现乱码'));
  });
}
