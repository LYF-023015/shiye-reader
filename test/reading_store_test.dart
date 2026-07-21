import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/models/book.dart';
import 'package:reading_app/services/reading_store.dart';

void main() {
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
      const ReaderPreferences(fontSize: 22, eyeCare: true),
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
}
