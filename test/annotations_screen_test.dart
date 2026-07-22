import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/models/book.dart';
import 'package:reading_app/screens/annotations_screen.dart';
import 'package:reading_app/services/reading_store.dart';
import 'package:reading_app/theme/app_theme.dart';

const _book = Book(
  title: '批注测试',
  author: '拾页',
  lastRead: '刚刚',
  progress: .25,
  palette: [Color(0xFF345678), Color(0xFFDDEEFF), Color(0xFF102030)],
  coverMark: '批注',
  chapters: [Chapter(title: '第一章', content: '这里是一段测试正文。')],
);

void main() {
  Future<ReadingStore> pumpAnnotations(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    final store = ReadingStore.memory();
    addTearDown(store.dispose);
    store.addImportedBook(_book);
    store.addAnnotation(
      _book,
      BookAnnotation(
        chapterIndex: 0,
        selectedText: '测试正文',
        note: '主题与刷新测试',
        createdAt: DateTime(2026, 7, 22),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: AnnotationsScreen(readingStore: store),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return store;
  }

  testWidgets('批注中心在浅色主题下提供 Material 并使用浅色背景', (tester) async {
    await pumpAnnotations(tester, themeMode: ThemeMode.light);

    expect(find.byKey(const ValueKey('annotation-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.canvas);
    final searchContext = tester.element(
      find.byKey(const ValueKey('annotation-search')),
    );
    expect(Theme.of(searchContext).brightness, Brightness.light);
  });

  testWidgets('删除批注后列表会立即刷新', (tester) async {
    await pumpAnnotations(tester, themeMode: ThemeMode.dark);
    expect(find.text('批注测试'), findsOneWidget);

    await tester.tap(find.byTooltip('删除'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('批注测试'), findsNothing);
    expect(find.text('还没有匹配的批注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('修改阅读设置时可以保留应用主题', () {
    const preferences = ReaderPreferences(fontSize: 18, appThemeMode: 'light');

    final updated = preferences.copyWith(fontSize: 22);

    expect(updated.fontSize, 22);
    expect(updated.appThemeMode, 'light');
    expect(updated.themeMode, ThemeMode.light);
  });
}
