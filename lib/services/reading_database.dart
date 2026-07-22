import 'package:sqflite/sqflite.dart';

import '../models/book.dart';

class ChapterSearchMatch {
  const ChapterSearchMatch({
    required this.chapterIndex,
    required this.characterOffset,
    required this.excerpt,
  });

  final int chapterIndex;
  final int characterOffset;
  final String excerpt;
}

class ReadingDatabase {
  ReadingDatabase._(this._database, this._hasSearchIndex);

  final Database _database;
  final bool _hasSearchIndex;

  static Future<ReadingDatabase> open(String path) async {
    final database = await openDatabase(
      path,
      version: 2,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, _) async {
        await database.execute('''
            CREATE TABLE chapters(
              row_id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL,
              ordinal INTEGER NOT NULL,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              html TEXT,
              source_href TEXT,
              UNIQUE(book_id, ordinal)
            )
          ''');
        await database.execute(
          'CREATE INDEX chapters_book_ordinal ON chapters(book_id, ordinal)',
        );
        await _createSearchIndex(database);
      },
      onUpgrade: (database, oldVersion, _) async {
        if (oldVersion < 2) {
          if (await _createSearchIndex(database)) {
            await database.execute('''
              INSERT INTO chapter_fts(book_id, ordinal, title, content)
              SELECT book_id, ordinal, title, content FROM chapters
            ''');
          }
        }
      },
    );
    final index = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'chapter_fts'",
    );
    return ReadingDatabase._(database, index.isNotEmpty);
  }

  Future<List<Chapter>> chaptersFor(String bookId) async {
    final rows = await _database.rawQuery(
      'SELECT title, content, html, source_href FROM chapters '
      'WHERE book_id = ? ORDER BY ordinal',
      [bookId],
    );
    return rows
        .map(
          (row) => Chapter(
            title: row['title'] as String,
            content: row['content'] as String,
            html: row['html'] as String?,
            sourceHref: row['source_href'] as String?,
          ),
        )
        .toList();
  }

  Future<void> replaceChapters(String bookId, List<Chapter> chapters) async {
    await _database.transaction((tx) async {
      if (_hasSearchIndex) {
        await tx.delete(
          'chapter_fts',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
      }
      await tx.execute('DELETE FROM chapters WHERE book_id = ?', [bookId]);
      for (var index = 0; index < chapters.length; index++) {
        final chapter = chapters[index];
        await tx.execute(
          'INSERT INTO chapters('
          'book_id, ordinal, title, content, html, source_href'
          ') VALUES (?, ?, ?, ?, ?, ?)',
          [
            bookId,
            index,
            chapter.title,
            chapter.content,
            chapter.html,
            chapter.sourceHref,
          ],
        );
        if (_hasSearchIndex) {
          await tx.insert('chapter_fts', {
            'book_id': bookId,
            'ordinal': index,
            'title': chapter.title,
            'content': chapter.content,
          });
        }
      }
    });
  }

  Future<void> deleteBooks(Iterable<String> bookIds) async {
    final ids = bookIds.toList();
    if (ids.isEmpty) return;
    await _database.transaction((tx) async {
      for (final id in ids) {
        if (_hasSearchIndex) {
          await tx.delete('chapter_fts', where: 'book_id = ?', whereArgs: [id]);
        }
        await tx.execute('DELETE FROM chapters WHERE book_id = ?', [id]);
      }
    });
  }

  Future<List<ChapterSearchMatch>> search(
    String bookId,
    String value, {
    int limit = 200,
  }) async {
    final term = value.trim();
    if (term.isEmpty) return const [];
    final useIndex =
        _hasSearchIndex && RegExp(r'^[a-zA-Z0-9_]{2,}$').hasMatch(term);
    final rows = useIndex
        ? await _database.rawQuery(
            'SELECT ordinal, content FROM chapter_fts '
            'WHERE book_id = ? AND content MATCH ? ORDER BY ordinal',
            [bookId, term],
          )
        : await _database.rawQuery(
            'SELECT ordinal, content FROM chapters '
            'WHERE book_id = ? AND instr(lower(content), lower(?)) > 0 '
            'ORDER BY ordinal',
            [bookId, term],
          );
    final matches = <ChapterSearchMatch>[];
    final lowerTerm = term.toLowerCase();
    for (final row in rows) {
      final content = row['content'] as String;
      final lowerContent = content.toLowerCase();
      var offset = 0;
      while (matches.length < limit) {
        final found = lowerContent.indexOf(lowerTerm, offset);
        if (found < 0) break;
        final start = (found - 32).clamp(0, content.length);
        final end = (found + term.length + 56).clamp(start, content.length);
        matches.add(
          ChapterSearchMatch(
            chapterIndex: _asInt(row['ordinal']),
            characterOffset: found,
            excerpt: content
                .substring(start, end)
                .replaceAll(RegExp(r'\s+'), ' '),
          ),
        );
        offset = found + term.length;
      }
      if (matches.length >= limit) break;
    }
    return matches;
  }

  Future<void> close() => _database.close();
}

Future<bool> _createSearchIndex(DatabaseExecutor database) async {
  try {
    await database.execute(
      'CREATE VIRTUAL TABLE chapter_fts USING fts4('
      'book_id, ordinal, title, content, tokenize=unicode61)',
    );
    return true;
  } on DatabaseException {
    return false;
  }
}

int _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
