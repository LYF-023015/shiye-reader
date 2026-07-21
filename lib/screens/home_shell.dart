import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'library_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  final ReadingStore _readingStore = ReadingStore();

  @override
  void initState() {
    super.initState();
    _readingStore.initialize();
  }

  @override
  void dispose() {
    _readingStore.dispose();
    super.dispose();
  }

  void _addImportedBook(Book book) {
    _readingStore.addImportedBook(book);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _readingStore,
      builder: (context, _) {
        final books = _readingStore.importedBooks
            .map(_readingStore.hydrate)
            .toList();
        const darkNavigation = true;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: const Color(0xFF08090B),
            body: IndexedStack(
              index: _currentIndex,
              children: [
                LibraryScreen(
                  books: books,
                  readingStore: _readingStore,
                  onBookImported: _addImportedBook,
                ),
                HistoryScreen(books: books, readingStore: _readingStore),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(64, 6, 64, 14),
              child: Container(
                height: 58,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161A),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .07),
                  ),
                ),
                child: Row(
                  children: [
                    _NavigationItem(
                      icon: Icons.auto_stories_rounded,
                      label: '书架',
                      selected: _currentIndex == 0,
                      darkMode: darkNavigation,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavigationItem(
                      icon: Icons.history_rounded,
                      label: '阅读记录',
                      selected: _currentIndex == 1,
                      darkMode: darkNavigation,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.darkMode,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool darkMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected
            ? (darkMode ? Colors.white.withValues(alpha: .1) : Colors.white)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          key: ValueKey('nav-$label'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(25),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: darkMode
                    ? (selected ? Colors.white : Colors.white38)
                    : (selected ? AppColors.accent : AppColors.secondary),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: darkMode
                      ? (selected ? Colors.white : Colors.white38)
                      : (selected ? AppColors.accent : AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
