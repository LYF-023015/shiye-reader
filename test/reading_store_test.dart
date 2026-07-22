import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/models/book.dart';
import 'package:reading_app/services/reading_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('阅读进度、书签和设置可以写入并重新加载', () async {
    final file = File(
      '${Directory.systemTemp.path}'
      '${Platform.pathSeparator}reading-store-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    const book = Book(
      title: '测试书籍',
      author: '测试作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: '测试书籍',
      chapters: [Chapter(title: '第一章', content: '测试正文')],
    );
    final store = ReadingStore(storageFile: file);
    await store.initialize();
    store.updateProgress(book, .64, 1);
    store.toggleBookmark(book, 1);
    store.addAnnotation(
      book,
      BookAnnotation(
        chapterIndex: 0,
        selectedText: '测试正文',
        note: '我的批注',
        createdAt: DateTime(2026, 7, 20),
      ),
    );
    store.updateReaderPreferences(
      const ReaderPreferences(fontSize: 22, eyeCare: true, autoScrollSpeed: 2),
    );
    await store.flush();
    store.dispose();

    final restored = ReadingStore(storageFile: file);
    await restored.initialize();
    final state = restored.stateFor(book);
    expect(state.progress, .64);
    expect(state.chapterIndex, 1);
    expect(state.bookmarkedChapters, contains(1));
    expect(state.annotations.single.note, '我的批注');
    expect(restored.readerPreferences.fontSize, 22);
    expect(restored.readerPreferences.eyeCare, isTrue);
    expect(restored.readerPreferences.autoScrollSpeed, 2);
    restored.dispose();
  });

  test('章节内阅读位置会持久化', () async {
    final file = File(
      '${Directory.systemTemp.path}'
      '${Platform.pathSeparator}reading-position-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      for (final suffix in ['', '.bak', '.tmp']) {
        final candidate = File('${file.path}$suffix');
        if (await candidate.exists()) await candidate.delete();
      }
    });
    const book = Book(
      title: '位置测试',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: '位置测试',
      chapters: [Chapter(title: '第一章', content: '正文')],
    );
    final store = ReadingStore(storageFile: file);
    await store.initialize();
    store.updateProgress(book, .42, 0, chapterProgress: .73);
    await store.flush();
    final restored = ReadingStore(storageFile: file);
    await restored.initialize();
    expect(restored.stateFor(book).chapterProgress, .73);
    store.dispose();
    restored.dispose();
  });

  test('重新导入会替换旧版乱码解析产生的同一本书', () {
    final store = ReadingStore.memory();
    const palette = [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)];
    const legacy = Book(
      title: '《超级系统》作者：疯狂小强',
      author: '本地导入',
      lastRead: '刚刚导入',
      progress: 0,
      palette: palette,
      coverMark: '',
      chapters: [Chapter(title: '正文', content: '����')],
    );
    const corrected = Book(
      title: '超级系统',
      author: '疯狂小强',
      lastRead: '刚刚导入',
      progress: 0,
      palette: palette,
      coverMark: '',
      chapters: [Chapter(title: '第一章', content: '正确中文')],
    );

    store.addImportedBook(legacy);
    store.addImportedBook(corrected);

    expect(store.importedBooks, hasLength(1));
    expect(store.importedBooks.single.title, '超级系统');
    expect(store.importedBooks.single.chapters.single.content, '正确中文');
    store.dispose();
  });

  test('完整备份可以恢复书籍、进度和批注', () async {
    final store = ReadingStore.memory();
    const book = Book(
      title: '备份测试',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: '备份测试',
      chapters: [Chapter(title: '第一章', content: '正文')],
    );
    store.addImportedBook(book);
    store.updateProgress(book, .5, 0, chapterProgress: .7);
    store.addAnnotation(
      book,
      BookAnnotation(
        chapterIndex: 0,
        chapterProgress: .7,
        selectedText: '正文',
        note: '笔记',
        createdAt: DateTime(2026, 7, 21),
      ),
    );
    final backup = await store.createBackup();
    final restored = ReadingStore.memory();
    await restored.restoreBackup(backup);

    expect(restored.importedBooks.single.title, '备份测试');
    expect(restored.stateFor(book).chapterProgress, .7);
    expect(restored.stateFor(book).annotations.single.note, '笔记');
    store.dispose();
    restored.dispose();
  });

  test('ZIP 备份支持预览、资源校验和恢复', () async {
    final store = ReadingStore.memory();
    final book = Book(
      storageId: 'zip-book',
      title: 'ZIP 备份',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: const [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: 'ZIP 备份',
      coverBytes: Uint8List.fromList([1, 2, 3, 4]),
      sourceBytes: Uint8List.fromList([5, 6, 7, 8]),
      chapters: const [Chapter(title: '第一章', content: '正文')],
    );
    store.addImportedBook(book);
    store.addAnnotation(
      book,
      BookAnnotation(
        chapterIndex: 0,
        characterStart: 1,
        characterEnd: 2,
        selectedText: '正',
        note: '批注',
        createdAt: DateTime(2026, 7, 22),
      ),
    );

    final bytes = await store.createBackupArchive();
    final preview = await store.inspectBackupBytes(bytes);
    expect(preview.bookCount, 1);
    expect(preview.annotationCount, 1);
    expect(preview.isLegacyJson, isFalse);

    final restored = ReadingStore.memory();
    await restored.restoreBackupBytes(bytes);
    expect(restored.importedBooks.single.coverBytes, [1, 2, 3, 4]);
    expect(restored.importedBooks.single.sourceBytes, [5, 6, 7, 8]);
    expect(restored.allAnnotations.single.annotation.characterStart, 1);
    store.dispose();
    restored.dispose();
  });

  test('大封面会写入资源目录并可重新加载', () async {
    final directory = await Directory.systemTemp.createTemp('shiye-resources-');
    final file = File('${directory.path}${Platform.pathSeparator}store.json');
    addTearDown(() => directory.delete(recursive: true));
    final cover = Uint8List(8 * 1024 * 1024 + 1)..[0] = 42;
    final book = Book(
      storageId: 'large-cover',
      title: '大封面',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: const [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: '大封面',
      coverBytes: cover,
      chapters: const [Chapter(title: '正文', content: '正文')],
    );
    final store = ReadingStore(storageFile: file);
    await store.initialize();
    store.addImportedBook(book);
    await store.flush();
    final encoded = await file.readAsString();
    expect(encoded, contains('coverBytesPath'));
    expect(encoded.length, lessThan(100000));

    final restored = ReadingStore(storageFile: file);
    await restored.initialize();
    expect(restored.importedBooks.single.coverBytes?.length, cover.length);
    expect(restored.importedBooks.single.coverBytes?.first, 42);
    store.dispose();
    restored.dispose();
  });

  test('章节正文迁移到 SQLite，进度 JSON 不再包含正文', () async {
    final directory = await Directory.systemTemp.createTemp('shiye-sqlite-');
    final file = File('${directory.path}${Platform.pathSeparator}store.json');
    addTearDown(() => directory.delete(recursive: true));
    const marker = '仅存在于正文数据库的唯一标记';
    const book = Book(
      storageId: 'sqlite-book',
      title: '数据库测试',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: '数据库测试',
      chapters: [
        Chapter(
          title: '第一章',
          content: '这是$marker，用于验证搜索和迁移。 IndexedWord',
          html: '<p>这是$marker</p>',
        ),
      ],
    );
    final store = ReadingStore(storageFile: file);
    await store.initialize();
    store.addImportedBook(book);
    await store.flush();

    store.updateProgress(book, .8, 0, characterOffset: 12);
    await store.flush();
    final encoded = await file.readAsString();
    expect(encoded, isNot(contains(marker)));
    expect(encoded, isNot(contains('"chapters"')));
    expect(encoded, contains('"schemaVersion":5'));
    final results = await store.searchChapters(book, '唯一标记');
    expect(results, hasLength(1));
    expect(results.single.chapterIndex, 0);
    final indexedResults = await store.searchChapters(book, 'IndexedWord');
    expect(indexedResults, hasLength(1));
    store.dispose();

    final restored = ReadingStore(storageFile: file);
    await restored.initialize();
    expect(
      restored.importedBooks.single.chapters.single.content,
      contains(marker),
    );
    expect(restored.stateFor(book).progress, .8);
    restored.dispose();
  });

  test('自动备份编码不会捕获 SQLite 连接', () async {
    final directory = await Directory.systemTemp.createTemp('shiye-auto-');
    final file = File('${directory.path}${Platform.pathSeparator}store.json');
    addTearDown(() => directory.delete(recursive: true));
    const book = Book(
      storageId: 'automatic-backup-book',
      title: '自动备份测试',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0,
      palette: [Color(0xFF7890A0), Color(0xFFDDE5E8), Color(0xFF24333A)],
      coverMark: '自动备份',
      chapters: [Chapter(title: '第一章', content: '自动备份正文')],
    );
    final store = ReadingStore(storageFile: file, automaticBackups: true);
    await store.initialize();
    store.addImportedBook(book);

    await store.flush();

    expect(store.storageError, isNull);
    final backups = await Directory(
      '${directory.path}${Platform.pathSeparator}automatic_backups',
    ).list().where((entry) => entry.path.endsWith('.zip')).toList();
    expect(backups, hasLength(1));
    store.dispose();
  });
}
