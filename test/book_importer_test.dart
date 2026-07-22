import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/models/book.dart';
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

  test('EPUB 3 nav 会作为目录保留，图片和 CSS 资源会内联', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string('OPS/book.opf', '''<package>
          <metadata><title>富内容书</title><creator>作者</creator></metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="css" href="style.css" media-type="text/css"/>
            <item id="image" href="art.png" media-type="image/png"/>
            <item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="c1"/></spine>
        </package>'''),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/nav.xhtml',
          '<html><body><nav epub:type="toc" type="toc"><ol><li><a href="chapter.xhtml#part-a">导航章节</a></li></ol></nav></body></html>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/style.css',
          'body { background-image: url("art.png"); }',
        ),
      )
      ..addFile(ArchiveFile.bytes('OPS/art.png', [1, 2, 3]))
      ..addFile(
        ArchiveFile.string(
          'OPS/chapter.xhtml',
          '<html><head><link rel="stylesheet" href="style.css"/></head><body><h1 id="part-a">第一节</h1><p>这是一个足够长的富内容章节正文，用于验证导航和资源。</p><img src="art.png"/></body></html>',
        ),
      );
    final zip = ZipEncoder().encode(archive);
    final result = await BookImporter.parse(
      PickedLocalFile(name: 'rich.epub', bytes: Uint8List.fromList(zip)),
    );

    expect(result.navigation.single.label, '导航章节');
    expect(result.navigation.single.chapterIndex, 0);
    expect(result.chapters.single.html, contains('data:image/png;base64,AQID'));
    expect(result.chapters.single.html, contains('<style>'));
  });

  test('加密 EPUB 会拒绝，固定版式 EPUB 会交给 WebView 阅读器', () async {
    Archive baseArchive(String opf) => Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(ArchiveFile.string('book.opf', opf))
      ..addFile(
        ArchiveFile.string(
          'chapter.xhtml',
          '<html><body><p>这是足够长的正文，用于触发格式解析。</p></body></html>',
        ),
      );

    final encrypted =
        baseArchive(
          '<package><metadata><meta name="cover" content="x"/></metadata><manifest><item id="c" href="chapter.xhtml"/></manifest><spine><itemref idref="c"/></spine></package>',
        )..addFile(
          ArchiveFile.string(
            'META-INF/encryption.xml',
            '<encryption><EncryptedData/></encryption>',
          ),
        );
    final fixed = baseArchive(
      '<package><metadata><meta property="rendition:layout">pre-paginated</meta></metadata><manifest><item id="c" href="chapter.xhtml"/></manifest><spine><itemref idref="c"/></spine></package>',
    );

    Future<void> expectMessage(Archive archive, String message) async {
      final zip = ZipEncoder().encode(archive);
      await expectLater(
        () => BookImporter.parse(
          PickedLocalFile(name: 'book.epub', bytes: Uint8List.fromList(zip)),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(message),
          ),
        ),
      );
    }

    await expectMessage(encrypted, '加密');
    final zip = ZipEncoder().encode(fixed);
    final imported = await BookImporter.parse(
      PickedLocalFile(name: 'fixed.epub', bytes: Uint8List.fromList(zip)),
    );
    expect(imported.format, BookFormat.epub);
    expect(imported.sourceBytes, isNotEmpty);
  });

  test('PDF 会保留原始文件以供阅读器打开', () async {
    final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
    final result = await BookImporter.parse(
      PickedLocalFile(name: '文档.pdf', bytes: bytes),
    );

    expect(result.format, BookFormat.pdf);
    expect(result.sourceBytes, bytes);
    expect(result.title, '文档');
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
