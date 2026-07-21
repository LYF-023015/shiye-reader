import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reading_app/models/book.dart';
import 'package:reading_app/screens/library_screen.dart';
import 'package:reading_app/services/reading_store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile horizontal card CoverFlow drag trace', (tester) async {
    final store = ReadingStore.memory();
    final books = <Book>[
      for (var index = 0; index < 7; index++)
        Book(
          title: '性能测试 ${index + 1}',
          author: '测试作者',
          lastRead: '尚未阅读',
          progress: 0,
          palette: const [
            Color(0xFF74AFC4),
            Color(0xFFDCECEF),
            Color(0xFF173946),
          ],
          coverMark: '性能测试',
          overlayCoverText: true,
          coverTemplate: index,
          chapters: const [Chapter(title: '正文', content: '性能测试正文')],
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryScreen(books: books, readingStore: store),
        ),
      ),
    );
    for (var frame = 0; frame < 180; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(const ValueKey('coverflow-ready')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('coverflow-ready')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    final carousel = find.byKey(const ValueKey('book-carousel'));

    await binding.traceAction(() async {
      for (var index = 0; index < 6; index++) {
        await tester.timedDrag(
          carousel,
          const Offset(-190, 0),
          const Duration(milliseconds: 650),
        );
        await tester.pumpAndSettle();
        await tester.timedDrag(
          carousel,
          const Offset(190, 0),
          const Duration(milliseconds: 650),
        );
        await tester.pumpAndSettle();
      }
    }, reportKey: 'coverflow');
    store.dispose();
  });
}
