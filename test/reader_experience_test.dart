import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/models/book.dart';
import 'package:reading_app/screens/reader_screen.dart';
import 'package:reading_app/services/reading_store.dart';
import 'package:reading_app/widgets/book_cover.dart';

Book _book({String author = '作者', List<Chapter>? chapters}) => Book(
  title: '测试书名',
  author: author,
  lastRead: '尚未阅读',
  progress: 0,
  palette: const [Color(0xFF78BDD4), Color(0xFFDCECF1), Color(0xFF173B4B)],
  coverMark: '测试书名',
  overlayCoverText: true,
  chapters:
      chapters ?? const [Chapter(title: '第一章', content: '这是用于测试阅读器的正文内容。')],
);

void main() {
  Future<ReadingStore> pumpReader(
    WidgetTester tester, {
    Book? book,
    ReaderPreferences? preferences,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = ReadingStore.memory();
    if (preferences != null) store.updateReaderPreferences(preferences);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(book: book ?? _book(), readingStore: store),
      ),
    );
    await tester.pump();
    return store;
  }

  testWidgets('封面使用系统字体并隐藏本地导入占位作者', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BookCoverArtwork(book: _book(author: '本地导入')),
        ),
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(find.text('测试书名'));
    expect(title.style?.fontFamily, isNull);
    expect(title.style?.fontWeight, FontWeight.w800);
    expect(find.text('本地导入'), findsNothing);
  });

  testWidgets('阅读浮层自动隐藏且只需点击下半屏即可唤回', (tester) async {
    await pumpReader(tester);
    expect(find.byKey(const ValueKey('reader-controls')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-top-controls')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('reader-bottom-controls-hidden')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reader-top-controls-hidden')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(195, 700));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('reader-controls')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-more-button')), findsOneWidget);
  });

  testWidgets('自动滚动默认更快并提供右侧倍速设置', (tester) async {
    final store = await pumpReader(tester);
    await tester.tap(find.byKey(const ValueKey('reader-more-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auto-scroll-speed')), findsOneWidget);
    expect(find.text('1.5×'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auto-scroll-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0×').last);
    await tester.pumpAndSettle();
    expect(store.readerPreferences.autoScrollSpeed, 2.0);
  });

  testWidgets('上下滚动到章末会自动衔接下一章', (tester) async {
    final book = _book(
      chapters: [
        Chapter(title: '第一章', content: List.filled(180, '第一章正文。').join()),
        const Chapter(title: '第二章', content: '第二章已经无缝接入。'),
      ],
    );
    await pumpReader(tester, book: book);

    for (var index = 0; index < 8; index++) {
      await tester.drag(
        find.byKey(const ValueKey('reader-page')),
        const Offset(0, -700),
      );
      await tester.pump(const Duration(milliseconds: 80));
      if (find.text('第二章').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('第二章'), findsOneWidget);
    expect(find.textContaining('第二章已经无缝接入'), findsOneWidget);
  });

  testWidgets('上下滚动连续显示所有章节正文', (tester) async {
    final book = _book(
      chapters: [
        const Chapter(title: '第一章', content: '第一章正文内容在这里。'),
        const Chapter(title: '第二章', content: '第二章紧随其后，无缝衔接。'),
      ],
    );
    await pumpReader(tester, book: book);
    await tester.pump(const Duration(milliseconds: 500));

    // Continuous scroll renders every chapter together in one view, so both
    // chapters' titles and bodies exist without any chapter-boundary action.
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);
    expect(find.textContaining('第一章正文内容在这里'), findsOneWidget);
    expect(find.textContaining('第二章紧随其后，无缝衔接'), findsOneWidget);
  });

  testWidgets('大书懒加载，仅渲染可见章节，不卡死', (tester) async {
    final book = _book(
      chapters: [
        for (var index = 0; index < 80; index++)
          Chapter(title: '第${index + 1}章', content: '本章正文内容。' * 200),
      ],
    );
    await pumpReader(tester, book: book);
    await tester.pump(
      const Duration(milliseconds: 700),
    ); // flush debounced progress save

    // The first chapter is built and visible...
    expect(find.text('第1章'), findsOneWidget);
    // ...but a far-away chapter is NOT built (lazy rendering), which is what
    // keeps opening a large book from freezing the UI.
    expect(find.text('第80章'), findsNothing);
  });

  testWidgets('选中文本后批注入口保持可见', (tester) async {
    await pumpReader(tester);

    // Let the controls auto-hide first.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('reader-bottom-controls-hidden')),
      findsOneWidget,
    );

    // Long-press and drag across the body text to create a selection.
    final textCenter = tester.getCenter(find.textContaining('这是用于测试'));
    final gesture = await tester.startGesture(textCenter);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(textCenter.dx + 120, textCenter.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Selecting text must surface the annotation controls again.
    expect(find.byKey(const ValueKey('reader-controls')), findsOneWidget);
    expect(find.byKey(const ValueKey('annotation-button')), findsOneWidget);
  });
}
