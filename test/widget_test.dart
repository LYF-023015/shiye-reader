import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/models/book.dart';
import 'package:reading_app/screens/book_showcase_screen.dart';
import 'package:reading_app/screens/library_screen.dart';
import 'package:reading_app/services/reading_store.dart';

const _chapter = Chapter(
  title: '第一章',
  content: '二月二，龙抬头。春风穿过长安城，故事从这一页开始。这里是一段用于测试选择、复制和批注功能的正文。',
);

final _books = <Book>[
  for (final entry in const [
    ('长安的荔枝', '马伯庸', .32),
    ('庆余年', '猫腻', .56),
    ('偷偷藏不住', '竹已', .18),
    ('人间失格', '太宰治', .07),
    ('活着', '余华', .41),
    ('月亮与六便士', '毛姆', .23),
    ('局外人', '加缪', .11),
  ])
    Book(
      title: entry.$1,
      author: entry.$2,
      lastRead: '尚未阅读',
      progress: entry.$3,
      palette: const [Color(0xFF78BDD4), Color(0xFFDCECF1), Color(0xFF173B4B)],
      coverMark: entry.$1,
      overlayCoverText: true,
      coverTemplate: entry.$1.codeUnits.fold(0, (sum, unit) => sum + unit) % 20,
      chapters: const [_chapter],
    ),
];

void main() {
  Future<void> pumpAnimation(WidgetTester tester, {int frames = 80}) async {
    for (var index = 0; index < frames; index++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> setPhoneSize(
    WidgetTester tester, {
    bool landscape = false,
  }) async {
    await tester.binding.setSurfaceSize(
      landscape ? const Size(844, 390) : const Size(390, 844),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<ReadingStore> pumpLibrary(WidgetTester tester) async {
    final store = ReadingStore.memory();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Asset decoder warmup is covered by the on-device performance test.
          // Widget tests exercise layout and interaction deterministically.
          body: LibraryScreen(
            books: _books,
            readingStore: store,
            warmPresetCovers: false,
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(const ValueKey('coverflow-ready')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('coverflow-ready')), findsOneWidget);
    return store;
  }

  testWidgets('内测首次启动为空书架和空阅读记录', (tester) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(const ReadingApp());
    await tester.pumpAndSettle();

    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-import-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-阅读记录')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('nav-background-阅读记录'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(find.byKey(const ValueKey('reading-heatmap')), findsOneWidget);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('书架展示并支持搜索', (tester) async {
    await setPhoneSize(tester);
    await pumpLibrary(tester);

    expect(find.textContaining('长安的荔枝'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('library-search')), '太宰');
    await pumpAnimation(tester, frames: 4);
    expect(find.textContaining('人间失格'), findsWidgets);
  });

  testWidgets('书架基础渲染', (tester) async {
    await setPhoneSize(tester);
    await pumpLibrary(tester);
    expect(find.byKey(const ValueKey('book-carousel')), findsOneWidget);
  });

  testWidgets('竖屏书架可以横向滑动到下一本书', (tester) async {
    await setPhoneSize(tester);
    await pumpLibrary(tester);
    await tester.timedDrag(
      find.byKey(const ValueKey('book-carousel')),
      const Offset(-118, 0),
      const Duration(milliseconds: 420),
    );
    await pumpAnimation(tester);
    expect(find.textContaining('庆余年'), findsWidgets);
  });

  testWidgets('左右按钮可以循环切换书籍，进入按钮位于中间', (tester) async {
    await setPhoneSize(tester);
    await pumpLibrary(tester);
    final previous = find.byKey(const ValueKey('previous-book-button'));
    final open = find.byKey(const ValueKey('open-showcase-button'));
    final next = find.byKey(const ValueKey('next-book-button'));
    expect(previous, findsOneWidget);
    expect(open, findsOneWidget);
    expect(next, findsOneWidget);
    expect(tester.getCenter(previous).dx, lessThan(tester.getCenter(open).dx));
    expect(tester.getCenter(open).dx, lessThan(tester.getCenter(next).dx));

    await tester.tap(next);
    await pumpAnimation(tester, frames: 24);
    expect(find.textContaining('庆余年'), findsWidgets);
    await tester.tap(previous);
    await pumpAnimation(tester, frames: 24);
    expect(find.textContaining('长安的荔枝'), findsWidgets);
  });

  testWidgets('横屏仍支持横向 CoverFlow', (tester) async {
    await setPhoneSize(tester, landscape: true);
    await pumpLibrary(tester);
    expect(find.byKey(const ValueKey('book-carousel')), findsOneWidget);
    await tester.timedDrag(
      find.byKey(const ValueKey('book-carousel')),
      const Offset(-118, 0),
      const Duration(milliseconds: 420),
    );
    await pumpAnimation(tester);
    expect(find.textContaining('庆余年'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书架在手指松开前逐像素横向跟随', (tester) async {
    await setPhoneSize(tester);
    await pumpLibrary(tester);
    final carousel = find.byKey(const ValueKey('book-carousel'));
    final selected = find.byKey(const ValueKey('shelf-volume-长安的荔枝'));
    final gesture = await tester.startGesture(tester.getCenter(carousel));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    final before = tester.getCenter(selected);
    await gesture.moveBy(const Offset(-32, 0));
    await tester.pump();
    final whilePressed = tester.getCenter(selected);
    expect(whilePressed.dx, closeTo(before.dx - 32, 1.5));
    await gesture.up();
    await pumpAnimation(tester);
  });

  testWidgets('点击书籍进入展厅和阅读器，并支持目录设置批注入口', (tester) async {
    await setPhoneSize(tester);
    await pumpLibrary(tester);
    await tester.tap(find.byKey(const ValueKey('book-carousel')));
    await pumpAnimation(tester);
    expect(find.text('书籍展厅'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('continue-reading-button')));
    await pumpAnimation(tester, frames: 24);
    expect(find.textContaining('二月二'), findsWidgets);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byKey(const ValueKey('annotation-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('catalog-button')));
    await pumpAnimation(tester, frames: 24);
    expect(find.text('目录'), findsWidgets);
  });

  testWidgets('阅读记录展示半年热力图并支持范围筛选', (tester) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(const ReadingApp());
    await tester.tap(find.byKey(const ValueKey('nav-阅读记录')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reading-heatmap')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近30天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('过去30天'), findsOneWidget);
  });

  testWidgets('两本书时书架不循环且尽头禁用翻页', (tester) async {
    await setPhoneSize(tester);
    final store = ReadingStore.memory();
    addTearDown(store.dispose);
    final books = [
      for (final entry in const [('书甲', 0), ('书乙', 1)])
        Book(
          title: entry.$1,
          author: '作者',
          lastRead: '尚未阅读',
          progress: 0,
          palette: const [
            Color(0xFF78BDD4),
            Color(0xFFDCECF1),
            Color(0xFF173B4B),
          ],
          coverMark: entry.$1,
          overlayCoverText: true,
          coverTemplate: entry.$2,
          chapters: const [Chapter(title: '正文', content: '正文内容')],
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryScreen(
            books: books,
            readingStore: store,
            warmPresetCovers: false,
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(const ValueKey('coverflow-ready')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('coverflow-ready')), findsOneWidget);

    // On the first book: previous is disabled, next is enabled.
    expect(
      _shelfButtonEnabled(tester, const ValueKey('previous-book-button')),
      isFalse,
    );
    expect(
      _shelfButtonEnabled(tester, const ValueKey('next-book-button')),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('next-book-button')));
    await pumpAnimation(tester);

    // On the last book: next is disabled (no looping back to the first).
    expect(
      _shelfButtonEnabled(tester, const ValueKey('next-book-button')),
      isFalse,
    );
    expect(
      _shelfButtonEnabled(tester, const ValueKey('previous-book-button')),
      isTrue,
    );
  });

  testWidgets('书籍展厅显示当前阅读章节而非书的开头', (tester) async {
    await setPhoneSize(tester);
    final store = ReadingStore.memory();
    addTearDown(store.dispose);
    final book = Book(
      title: '展厅测试书',
      author: '作者',
      lastRead: '尚未阅读',
      progress: 0.34,
      palette: const [Color(0xFF78BDD4), Color(0xFFDCECF1), Color(0xFF173B4B)],
      coverMark: '展厅测试书',
      overlayCoverText: true,
      chapters: const [
        Chapter(title: '第一章', content: '这是书开头的文字，不应该在展厅显示。'),
        Chapter(title: '第二章', content: '这是当前阅读到第二章的开头正文内容。'),
        Chapter(title: '第三章', content: '这是后面尚未读到的章节。'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BookShowcaseScreen(book: book, readingStore: store),
      ),
    );
    await tester.pump();

    expect(find.text('读到 · 第二章'), findsOneWidget);
    expect(find.textContaining('这是当前阅读到'), findsOneWidget);
    expect(find.textContaining('不应该在展厅显示'), findsNothing);
  });
}

bool _shelfButtonEnabled(WidgetTester tester, Key key) {
  final button = tester.widget<IconButton>(
    find.descendant(of: find.byKey(key), matching: find.byType(IconButton)),
  );
  return button.onPressed != null;
}
