import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../models/book.dart';
import 'diagnostics_service.dart';
import 'reading_database.dart';

class BookReadingState {
  const BookReadingState({
    this.progress = 0,
    this.chapterIndex = 0,
    this.chapterProgress = 0,
    this.characterOffset = 0,
    this.epubCfi,
    this.lastReadAt,
    this.totalMinutes = 0,
    this.bookmarkedChapters = const <int>{},
    this.bookmarkOffsets = const <int, int>{},
    this.annotations = const <BookAnnotation>[],
  });

  final double progress;
  final int chapterIndex;
  final double chapterProgress;
  final int characterOffset;
  final String? epubCfi;
  final DateTime? lastReadAt;
  final int totalMinutes;
  final Set<int> bookmarkedChapters;
  final Map<int, int> bookmarkOffsets;
  final List<BookAnnotation> annotations;

  BookReadingState copyWith({
    double? progress,
    int? chapterIndex,
    double? chapterProgress,
    int? characterOffset,
    String? epubCfi,
    DateTime? lastReadAt,
    int? totalMinutes,
    Set<int>? bookmarkedChapters,
    Map<int, int>? bookmarkOffsets,
    List<BookAnnotation>? annotations,
  }) => BookReadingState(
    progress: progress ?? this.progress,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterProgress: chapterProgress ?? this.chapterProgress,
    characterOffset: characterOffset ?? this.characterOffset,
    epubCfi: epubCfi ?? this.epubCfi,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    totalMinutes: totalMinutes ?? this.totalMinutes,
    bookmarkedChapters: bookmarkedChapters ?? this.bookmarkedChapters,
    bookmarkOffsets: bookmarkOffsets ?? this.bookmarkOffsets,
    annotations: annotations ?? this.annotations,
  );

  Map<String, Object?> toJson() => {
    'progress': progress,
    'chapterIndex': chapterIndex,
    'chapterProgress': chapterProgress,
    'characterOffset': characterOffset,
    'epubCfi': epubCfi,
    'lastReadAt': lastReadAt?.toIso8601String(),
    'totalMinutes': totalMinutes,
    'bookmarkedChapters': bookmarkedChapters.toList(),
    'bookmarkOffsets': bookmarkOffsets.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
    'annotations': annotations.map((value) => value.toJson()).toList(),
  };

  factory BookReadingState.fromJson(
    Map<String, Object?> json,
  ) => BookReadingState(
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
    chapterProgress: (json['chapterProgress'] as num?)?.toDouble() ?? 0,
    characterOffset: (json['characterOffset'] as num?)?.toInt() ?? 0,
    epubCfi: json['epubCfi'] as String?,
    lastReadAt: DateTime.tryParse(json['lastReadAt'] as String? ?? ''),
    totalMinutes: (json['totalMinutes'] as num?)?.toInt() ?? 0,
    bookmarkedChapters:
        ((json['bookmarkedChapters'] as List<Object?>?) ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toSet(),
    bookmarkOffsets:
        ((json['bookmarkOffsets'] as Map?)?.cast<String, Object?>() ?? {}).map(
          (key, value) =>
              MapEntry(int.tryParse(key) ?? 0, (value as num?)?.toInt() ?? 0),
        ),
    annotations: ((json['annotations'] as List<Object?>?) ?? const [])
        .whereType<Map>()
        .map((value) => BookAnnotation.fromJson(value.cast<String, Object?>()))
        .toList(),
  );
}

class BookAnnotation {
  const BookAnnotation({
    this.id = '',
    required this.chapterIndex,
    this.chapterProgress = 0,
    this.characterStart = 0,
    this.characterEnd = 0,
    this.epubCfi,
    required this.selectedText,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final int chapterIndex;
  final double chapterProgress;
  final int characterStart;
  final int characterEnd;
  final String? epubCfi;
  final String selectedText;
  final String note;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'chapterIndex': chapterIndex,
    'chapterProgress': chapterProgress,
    'characterStart': characterStart,
    'characterEnd': characterEnd,
    'epubCfi': epubCfi,
    'selectedText': selectedText,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory BookAnnotation.fromJson(Map<String, Object?> json) => BookAnnotation(
    id: json['id'] as String? ?? '',
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
    chapterProgress: (json['chapterProgress'] as num?)?.toDouble() ?? 0,
    characterStart: (json['characterStart'] as num?)?.toInt() ?? 0,
    characterEnd: (json['characterEnd'] as num?)?.toInt() ?? 0,
    epubCfi: json['epubCfi'] as String?,
    selectedText: json['selectedText'] as String? ?? '',
    note: json['note'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class BookAnnotationEntry {
  const BookAnnotationEntry({required this.book, required this.annotation});

  final Book book;
  final BookAnnotation annotation;
}

class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.bookCount,
    required this.annotationCount,
    required this.isLegacyJson,
  });

  final DateTime? createdAt;
  final int bookCount;
  final int annotationCount;
  final bool isLegacyJson;
}

class ReadingActivity {
  const ReadingActivity({
    required this.bookId,
    required this.day,
    required this.minutes,
  });

  final String bookId;
  final DateTime day;
  final int minutes;

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'day': _dayKey(day),
    'minutes': minutes,
  };

  factory ReadingActivity.fromJson(Map<String, Object?> json) =>
      ReadingActivity(
        bookId: json['bookId'] as String? ?? '',
        day: DateTime.tryParse(json['day'] as String? ?? '') ?? DateTime.now(),
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      );
}

class ReaderPreferences {
  const ReaderPreferences({
    this.fontSize = 18,
    this.lineHeight = 1.9,
    this.backgroundValue = 0xFFF8F7F3,
    this.alignment = TextAlign.left,
    this.eyeCare = false,
    this.pageTurn = '上下滚动',
    this.appThemeMode = 'system',
  });

  final double fontSize;
  final double lineHeight;
  final int backgroundValue;
  final TextAlign alignment;
  final bool eyeCare;
  final String pageTurn;
  final String appThemeMode;

  ReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    int? backgroundValue,
    TextAlign? alignment,
    bool? eyeCare,
    String? pageTurn,
    String? appThemeMode,
  }) => ReaderPreferences(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundValue: backgroundValue ?? this.backgroundValue,
    alignment: alignment ?? this.alignment,
    eyeCare: eyeCare ?? this.eyeCare,
    pageTurn: pageTurn ?? this.pageTurn,
    appThemeMode: appThemeMode ?? this.appThemeMode,
  );

  ThemeMode get themeMode => switch (appThemeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'backgroundValue': backgroundValue,
    'alignment': alignment.name,
    'eyeCare': eyeCare,
    'pageTurn': pageTurn,
    'appThemeMode': appThemeMode,
  };

  factory ReaderPreferences.fromJson(Map<String, Object?> json) =>
      ReaderPreferences(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.9,
        backgroundValue:
            (json['backgroundValue'] as num?)?.toInt() ?? 0xFFF8F7F3,
        alignment: TextAlign.values.firstWhere(
          (value) => value.name == json['alignment'],
          orElse: () => TextAlign.left,
        ),
        eyeCare: json['eyeCare'] as bool? ?? false,
        pageTurn: json['pageTurn'] as String? ?? '上下滚动',
        appThemeMode: json['appThemeMode'] as String? ?? 'system',
      );
}

class ReadingStore extends ChangeNotifier {
  static const _storageChannel = MethodChannel('com.lyf.reading_app/storage');

  ReadingStore({File? storageFile, File? databaseFile, bool? automaticBackups})
    : _automaticBackups = automaticBackups ?? storageFile == null,
      _databasePath = databaseFile?.path {
    // Keep the public constructor parameter descriptive for tests and callers.
    // ignore: prefer_initializing_formals
    _storageFile = storageFile;
  }

  ReadingStore.memory() : _storageFile = null, _automaticBackups = false;

  File? _storageFile;
  String? _databasePath;
  ReadingDatabase? _database;
  final bool _automaticBackups;
  final Map<String, BookReadingState> _states = {};
  final List<ReadingActivity> _activities = [];
  final List<Book> _importedBooks = [];
  ReaderPreferences readerPreferences = const ReaderPreferences();
  Timer? _saveTimer;
  bool _dirty = false;
  Future<void>? _saveInFlight;
  Future<void>? _initialization;
  final Set<String> _chapterDirtyIds = {};
  final Set<String> _deletedChapterIds = {};
  String? storageError;

  List<Book> get importedBooks => List.unmodifiable(_importedBooks);

  List<BookAnnotationEntry> get allAnnotations {
    final entries = <BookAnnotationEntry>[];
    for (final book in _importedBooks) {
      for (final annotation in stateFor(book).annotations) {
        entries.add(BookAnnotationEntry(book: book, annotation: annotation));
      }
    }
    entries.sort(
      (a, b) => b.annotation.createdAt.compareTo(a.annotation.createdAt),
    );
    return entries;
  }

  Future<void> initialize() {
    final active = _initialization;
    if (active != null) return active;
    final operation = _initialize();
    _initialization = operation;
    return operation.whenComplete(() => _initialization = null);
  }

  Future<void> _initialize() async {
    if (_storageFile == null) {
      String? directory;
      try {
        directory = await _storageChannel.invokeMethod<String>(
          'getApplicationSupportPath',
        );
      } on MissingPluginException {
        storageError = '当前平台不支持本地数据存储';
        notifyListeners();
        return;
      }
      if (directory == null || directory.isEmpty) {
        storageError = '无法访问应用存储目录';
        notifyListeners();
        return;
      }
      _storageFile = File(
        '$directory${Platform.pathSeparator}reading_store_v3.json',
      );
      _databasePath ??=
          '$directory${Platform.pathSeparator}reading_content_v1.sqlite3';
      await _migrateLegacyStoreIfNeeded(_storageFile!);
    } else {
      _databasePath ??= '${_storageFile!.path}.sqlite3';
    }
    try {
      _database ??= await ReadingDatabase.open(_databasePath!);
    } on Object {
      storageError = '正文数据库无法打开，原阅读数据未被修改';
      notifyListeners();
      return;
    }
    await _readSavedData();
    notifyListeners();
  }

  BookReadingState stateFor(Book book) =>
      _states[book.id] ??
      BookReadingState(progress: book.progress, chapterIndex: 0);

  Book hydrate(Book book) {
    final state = stateFor(book);
    return book.copyWith(
      progress: state.progress,
      lastRead: state.lastReadAt == null
          ? book.lastRead
          : _relativeTime(state.lastReadAt!),
    );
  }

  void updateProgress(
    Book book,
    double progress,
    int chapterIndex, {
    double chapterProgress = 0,
    int characterOffset = 0,
  }) {
    final previous = stateFor(book);
    _states[book.id] = previous.copyWith(
      progress: progress.clamp(0, 1),
      chapterIndex: chapterIndex,
      chapterProgress: chapterProgress.clamp(0, 1),
      characterOffset: characterOffset < 0 ? 0 : characterOffset,
      lastReadAt: DateTime.now(),
    );
    _scheduleSave();
    notifyListeners();
  }

  void updateEpubProgress(Book book, double progress, String cfi) {
    final previous = stateFor(book);
    _states[book.id] = previous.copyWith(
      progress: progress.clamp(0, 1),
      chapterProgress: progress.clamp(0, 1),
      epubCfi: cfi,
      lastReadAt: DateTime.now(),
    );
    _scheduleSave();
    notifyListeners();
  }

  void recordSession(Book book, Duration elapsed) {
    if (elapsed.inSeconds < 5) return;
    final minutes = elapsed.inMinutes.clamp(1, 240).toInt();
    final previous = stateFor(book);
    _states[book.id] = previous.copyWith(
      totalMinutes: previous.totalMinutes + minutes,
      lastReadAt: DateTime.now(),
    );
    final today = DateTime.now();
    final index = _activities.indexWhere(
      (activity) =>
          activity.bookId == book.id && _dayKey(activity.day) == _dayKey(today),
    );
    if (index == -1) {
      _activities.add(
        ReadingActivity(bookId: book.id, day: today, minutes: minutes),
      );
    } else {
      final current = _activities[index];
      _activities[index] = ReadingActivity(
        bookId: current.bookId,
        day: current.day,
        minutes: current.minutes + minutes,
      );
    }
    _scheduleSave();
    notifyListeners();
  }

  void toggleBookmark(Book book, int chapterIndex, {int characterOffset = 0}) {
    final previous = stateFor(book);
    final chapters = Set<int>.of(previous.bookmarkedChapters);
    final offsets = Map<int, int>.of(previous.bookmarkOffsets);
    if (chapters.contains(chapterIndex)) {
      chapters.remove(chapterIndex);
      offsets.remove(chapterIndex);
    } else {
      chapters.add(chapterIndex);
      offsets[chapterIndex] = characterOffset < 0 ? 0 : characterOffset;
    }
    _states[book.id] = previous.copyWith(
      bookmarkedChapters: chapters,
      bookmarkOffsets: offsets,
    );
    _scheduleSave();
    notifyListeners();
  }

  void updateReaderPreferences(ReaderPreferences value) {
    readerPreferences = value;
    _scheduleSave();
    notifyListeners();
  }

  void addImportedBook(Book book) {
    final legacyTitles = {
      '《${book.title}》作者：${book.author}',
      '《${book.title}》作者:${book.author}',
    };
    final existing = _importedBooks.indexWhere(
      (item) =>
          item.id == book.id ||
          _sameBookMetadata(item, book) ||
          legacyTitles.contains(item.title.trim()),
    );
    if (existing >= 0) {
      final previous = _importedBooks[existing];
      final replacement = book.copyWith(storageId: previous.id);
      _importedBooks[existing] = replacement;
      _markChaptersDirty(replacement.id);
    } else {
      _importedBooks.add(book);
      _markChaptersDirty(book.id);
    }
    _scheduleSave();
    notifyListeners();
  }

  bool containsImportedBook(Book book) => _importedBooks.any(
    (item) => item.id == book.id || _sameBookMetadata(item, book),
  );

  void addImportedBookAsCopy(Book book) {
    var suffix = 2;
    var candidate = book;
    while (containsImportedBook(candidate)) {
      candidate = book.copyWith(title: '${book.title} ($suffix)');
      suffix++;
    }
    _importedBooks.add(candidate);
    _markChaptersDirty(candidate.id);
    _scheduleSave();
    notifyListeners();
  }

  void updateImportedBook(Book book) {
    final index = _importedBooks.indexWhere((item) => item.id == book.id);
    if (index < 0) return;
    _importedBooks[index] = book;
    _scheduleSave();
    notifyListeners();
  }

  void replaceImportedBook(Book original, Book replacement) {
    final index = _importedBooks.indexWhere((item) => item.id == original.id);
    if (index < 0) return;
    final value = replacement.copyWith(storageId: original.id);
    _importedBooks[index] = value;
    _markChaptersDirty(value.id);
    _scheduleSave();
    notifyListeners();
  }

  void addAnnotation(Book book, BookAnnotation annotation) {
    final previous = stateFor(book);
    final value = annotation.id.isEmpty
        ? BookAnnotation(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            chapterIndex: annotation.chapterIndex,
            chapterProgress: annotation.chapterProgress,
            characterStart: annotation.characterStart,
            characterEnd: annotation.characterEnd,
            epubCfi: annotation.epubCfi,
            selectedText: annotation.selectedText,
            note: annotation.note,
            createdAt: annotation.createdAt,
          )
        : annotation;
    _states[book.id] = previous.copyWith(
      annotations: [...previous.annotations, value],
    );
    _scheduleSave();
    notifyListeners();
  }

  void removeAnnotation(Book book, BookAnnotation annotation) {
    final previous = stateFor(book);
    final annotations = List<BookAnnotation>.of(previous.annotations)
      ..removeWhere(
        (item) => annotation.id.isNotEmpty
            ? item.id == annotation.id
            : identical(item, annotation),
      );
    _states[book.id] = previous.copyWith(annotations: annotations);
    _scheduleSave();
    notifyListeners();
  }

  void updateAnnotation(Book book, BookAnnotation annotation) {
    final previous = stateFor(book);
    final annotations = List<BookAnnotation>.of(previous.annotations);
    final index = annotations.indexWhere((item) => item.id == annotation.id);
    if (index < 0) return;
    annotations[index] = annotation;
    _states[book.id] = previous.copyWith(annotations: annotations);
    _scheduleSave();
    notifyListeners();
  }

  Future<String> createBackup({Set<String>? bookIds}) async {
    await flush();
    final payload = bookIds == null ? _payload() : _payloadForBooks(bookIds);
    payload['backupVersion'] = 1;
    payload['createdAt'] = DateTime.now().toIso8601String();
    return Isolate.run(() => jsonEncode(payload));
  }

  Future<void> restoreBackup(String encoded) async {
    final root = (jsonDecode(encoded) as Map).cast<String, Object?>();
    if ((root['backupVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('不支持的备份文件版本');
    }
    _replaceRoot(root);
    _dirty = true;
    await flush();
    notifyListeners();
  }

  Future<Uint8List> createBackupArchive({Set<String>? bookIds}) async {
    await flush();
    final payload = bookIds == null ? _payload() : _payloadForBooks(bookIds);
    final books = (payload['importedBooks'] as List<Object?>)
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList();
    payload['importedBooks'] = books;
    final resources = <Map<String, Object?>>[];
    final archive = Archive();
    for (var index = 0; index < books.length; index++) {
      final book = books[index];
      for (final field in const ['coverBytes', 'sourceBytes']) {
        final encoded = book[field] as String?;
        if (encoded == null || encoded.isEmpty) continue;
        final bytes = base64Decode(encoded);
        final path = 'resources/$index-$field.bin';
        resources.add({
          'bookIndex': index,
          'field': field,
          'path': path,
          'size': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        });
        archive.addFile(ArchiveFile.bytes(path, bytes));
        book[field] = null;
      }
    }
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        const JsonEncoder.withIndent('  ').convert({
          'format': 'shiye-backup',
          'backupVersion': 2,
          'createdAt': DateTime.now().toIso8601String(),
          'resources': resources,
          'payload': payload,
        }),
      ),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<BackupPreview> inspectBackupBytes(Uint8List bytes) async {
    final decoded = await Isolate.run(() => _decodeBackupBytes(bytes));
    final root = decoded.root;
    final books = root['importedBooks'] as List<Object?>? ?? const [];
    final states =
        (root['states'] as Map?)?.values.whereType<Map>() ?? const [];
    final annotationCount = states.fold<int>(
      0,
      (total, state) =>
          total + ((state['annotations'] as List<Object?>?)?.length ?? 0),
    );
    return BackupPreview(
      createdAt: decoded.createdAt,
      bookCount: books.length,
      annotationCount: annotationCount,
      isLegacyJson: decoded.legacy,
    );
  }

  Future<void> restoreBackupBytes(Uint8List bytes, {bool merge = false}) async {
    final decoded = await Isolate.run(() => _decodeBackupBytes(bytes));
    final snapshot = _payload();
    try {
      _replaceRoot(merge ? _mergeBackupRoot(decoded.root) : decoded.root);
      _dirty = true;
      await flush();
      notifyListeners();
    } on Object {
      _loadRoot(snapshot);
      rethrow;
    }
  }

  Map<String, Object?> _mergeBackupRoot(Map<String, Object?> incoming) {
    final current = _payload();
    final books = (current['importedBooks'] as List<Object?>)
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList();
    final existingIds = books
        .map((book) => book['id'] as String? ?? '')
        .toSet();
    for (final raw in incoming['importedBooks'] as List<Object?>? ?? const []) {
      final book = (raw as Map).cast<String, Object?>();
      if (existingIds.add(book['id'] as String? ?? '')) books.add(book);
    }
    final states = Map<String, Object?>.of(
      (current['states'] as Map).cast<String, Object?>(),
    );
    final incomingStates =
        (incoming['states'] as Map?)?.cast<String, Object?>() ?? const {};
    for (final entry in incomingStates.entries) {
      states.putIfAbsent(entry.key, () => entry.value);
    }
    final activity = List<Object?>.of(
      current['activity'] as List<Object?>? ?? const [],
    )..addAll(incoming['activity'] as List<Object?>? ?? const []);
    return {
      'schemaVersion': 3,
      'states': states,
      'activity': activity,
      'preferences': current['preferences'],
      'importedBooks': books,
    };
  }

  String exportAnnotations(Book book) {
    final buffer = StringBuffer('# ${book.title}\n\n作者：${book.author}\n\n');
    for (final annotation in stateFor(book).annotations) {
      final chapter = annotation.chapterIndex.clamp(
        0,
        book.chapters.length - 1,
      );
      buffer
        ..writeln('## ${book.chapters[chapter].title}')
        ..writeln('> ${annotation.selectedText.replaceAll('\n', '\n> ')}')
        ..writeln()
        ..writeln(annotation.note)
        ..writeln()
        ..writeln('时间：${annotation.createdAt.toIso8601String()}')
        ..writeln();
    }
    return buffer.toString();
  }

  String exportAnnotationEntriesJson(Iterable<BookAnnotationEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'shiye-annotations',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'annotations': entries
            .map(
              (entry) => {
                'bookId': entry.book.id,
                'bookTitle': entry.book.title,
                'bookAuthor': entry.book.author,
                ...entry.annotation.toJson(),
              },
            )
            .toList(),
      });

  String exportAnnotationEntriesMarkdown(
    Iterable<BookAnnotationEntry> entries,
  ) {
    final buffer = StringBuffer('# 拾页批注\n\n');
    for (final entry in entries) {
      final annotation = entry.annotation;
      final chapterIndex = annotation.chapterIndex.clamp(
        0,
        entry.book.chapters.length - 1,
      );
      buffer
        ..writeln(
          '## ${entry.book.title} · ${entry.book.chapters[chapterIndex].title}',
        )
        ..writeln('> ${annotation.selectedText.replaceAll('\n', '\n> ')}')
        ..writeln()
        ..writeln(annotation.note)
        ..writeln()
        ..writeln('时间：${annotation.createdAt.toIso8601String()}')
        ..writeln();
    }
    return buffer.toString();
  }

  void removeImportedBook(Book book) {
    _importedBooks.removeWhere((item) => item.id == book.id);
    _states.remove(book.id);
    _activities.removeWhere((activity) => activity.bookId == book.id);
    _chapterDirtyIds.remove(book.id);
    _deletedChapterIds.add(book.id);
    _scheduleSave();
    notifyListeners();
  }

  void removeImportedBooks(Iterable<Book> books) {
    final ids = books.map((book) => book.id).toSet();
    if (ids.isEmpty) return;
    _importedBooks.removeWhere((book) => ids.contains(book.id));
    _states.removeWhere((id, _) => ids.contains(id));
    _activities.removeWhere((activity) => ids.contains(activity.bookId));
    _chapterDirtyIds.removeAll(ids);
    _deletedChapterIds.addAll(ids);
    _scheduleSave();
    notifyListeners();
  }

  Map<DateTime, int> activityByDay({int days = 183}) {
    final today = DateTime.now();
    final first = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: days - 1));
    final result = <DateTime, int>{};
    for (final activity in _activities) {
      final day = DateTime(
        activity.day.year,
        activity.day.month,
        activity.day.day,
      );
      if (!day.isBefore(first)) {
        result[day] = (result[day] ?? 0) + activity.minutes;
      }
    }
    return result;
  }

  int get weeklyMinutes {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return _activities
        .where((activity) => !activity.day.isBefore(start))
        .fold(0, (sum, activity) => sum + activity.minutes);
  }

  int get totalMinutes =>
      _activities.fold(0, (sum, activity) => sum + activity.minutes);

  int get readingDays =>
      _activities.map((item) => _dayKey(item.day)).toSet().length;

  List<Book> sortByRecent(List<Book> books) {
    final result = List<Book>.of(books);
    result.sort((a, b) {
      final aDate = stateFor(a).lastReadAt ?? DateTime(2000);
      final bDate = stateFor(b).lastReadAt ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });
    return result;
  }

  List<Book> sortByTitle(List<Book> books) {
    final result = List<Book>.of(books);
    result.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return result;
  }

  Future<void> _readSavedData() async {
    final storageFile = _storageFile;
    if (storageFile == null) return;
    final backupFile = File('${storageFile.path}.bak');
    if (!await storageFile.exists() && !await backupFile.exists()) return;
    try {
      Map<String, Object?> root;
      try {
        root = (jsonDecode(await storageFile.readAsString()) as Map)
            .cast<String, Object?>();
      } on Object {
        root = (jsonDecode(await backupFile.readAsString()) as Map)
            .cast<String, Object?>();
        storageError = '主数据文件损坏，已从备份恢复';
      }
      await _hydrateExternalResources(root, storageFile.parent);
      final hadInlineChapters = await _hydrateDatabaseChapters(root);
      _loadRoot(root);
      if (hadInlineChapters) {
        _chapterDirtyIds.addAll(_importedBooks.map((book) => book.id));
        _dirty = true;
        await _saveNow();
      }
    } on Object {
      _states.clear();
      _activities.clear();
      _importedBooks.clear();
      storageError = '阅读数据无法读取，原文件已保留';
    }
  }

  void _loadRoot(Map<String, Object?> root) {
    final states = (root['states'] as Map?)?.cast<String, Object?>() ?? {};
    final loadedStates = <String, BookReadingState>{};
    for (final entry in states.entries) {
      final state = BookReadingState.fromJson(
        (entry.value as Map).cast<String, Object?>(),
      );
      var changed = false;
      final annotations = <BookAnnotation>[];
      for (var index = 0; index < state.annotations.length; index++) {
        final annotation = state.annotations[index];
        if (annotation.id.isNotEmpty) {
          annotations.add(annotation);
          continue;
        }
        changed = true;
        annotations.add(
          BookAnnotation(
            id: 'legacy-${entry.key.hashCode}-$index-${annotation.createdAt.microsecondsSinceEpoch}',
            chapterIndex: annotation.chapterIndex,
            chapterProgress: annotation.chapterProgress,
            characterStart: annotation.characterStart,
            characterEnd: annotation.characterEnd,
            epubCfi: annotation.epubCfi,
            selectedText: annotation.selectedText,
            note: annotation.note,
            createdAt: annotation.createdAt,
          ),
        );
      }
      loadedStates[entry.key] = changed
          ? state.copyWith(annotations: annotations)
          : state;
    }
    final loadedActivities = ((root['activity'] as List<Object?>?) ?? const [])
        .whereType<Map>()
        .map((value) => ReadingActivity.fromJson(value.cast<String, Object?>()))
        .toList();
    final loadedBooks = ((root['importedBooks'] as List<Object?>?) ?? const [])
        .whereType<Map>()
        .map((value) => Book.fromJson(value.cast<String, Object?>()))
        .where((book) => book.chapters.isNotEmpty)
        .toList();
    final preferences = root['preferences'];

    _states
      ..clear()
      ..addAll(loadedStates);
    _activities
      ..clear()
      ..addAll(loadedActivities);
    _importedBooks
      ..clear()
      ..addAll(loadedBooks);
    if (preferences is Map) {
      readerPreferences = ReaderPreferences.fromJson(
        preferences.cast<String, Object?>(),
      );
    }
  }

  void _replaceRoot(Map<String, Object?> root) {
    final previousIds = _importedBooks.map((book) => book.id).toSet();
    _loadRoot(root);
    final currentIds = _importedBooks.map((book) => book.id).toSet();
    _deletedChapterIds.addAll(previousIds.difference(currentIds));
    _chapterDirtyIds.addAll(currentIds);
    _deletedChapterIds.removeAll(currentIds);
  }

  Map<String, Object?> _payload() => {
    'schemaVersion': 3,
    'states': _states.map((key, value) => MapEntry(key, value.toJson())),
    'activity': _activities.map((value) => value.toJson()).toList(),
    'preferences': readerPreferences.toJson(),
    'importedBooks': _importedBooks.map((book) => book.toJson()).toList(),
  };

  Map<String, Object?> _storagePayload() => {
    'schemaVersion': 5,
    'states': _states.map((key, value) => MapEntry(key, value.toJson())),
    'activity': _activities.map((value) => value.toJson()).toList(),
    'preferences': readerPreferences.toJson(),
    'importedBooks': _importedBooks
        .map(
          (book) => book.toJson(includeBinary: false, includeChapters: false),
        )
        .toList(),
  };

  Future<bool> _hydrateDatabaseChapters(Map<String, Object?> root) async {
    final database = _database;
    if (database == null) return false;
    var hadInlineChapters = false;
    final books = root['importedBooks'] as List<Object?>? ?? const [];
    for (final raw in books.whereType<Map>()) {
      final json = raw.cast<String, Object?>();
      final inline = json['chapters'] as List<Object?>?;
      if (inline != null && inline.isNotEmpty) {
        hadInlineChapters = true;
        continue;
      }
      final bookId = json['id'] as String? ?? '';
      if (bookId.isEmpty) continue;
      final chapters = await database.chaptersFor(bookId);
      if (chapters.isNotEmpty) {
        json['chapters'] = chapters.map((chapter) => chapter.toJson()).toList();
      }
    }
    return hadInlineChapters;
  }

  void _markChaptersDirty(String bookId) {
    _deletedChapterIds.remove(bookId);
    _chapterDirtyIds.add(bookId);
  }

  Future<List<ChapterSearchMatch>> searchChapters(
    Book book,
    String query,
  ) async {
    final database = _database;
    if (database != null) return database.search(book.id, query);
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const [];
    final matches = <ChapterSearchMatch>[];
    for (
      var chapterIndex = 0;
      chapterIndex < book.chapters.length && matches.length < 200;
      chapterIndex++
    ) {
      final content = book.chapters[chapterIndex].content;
      final source = content.toLowerCase();
      var offset = 0;
      while (matches.length < 200) {
        final found = source.indexOf(term, offset);
        if (found < 0) break;
        final start = (found - 32).clamp(0, content.length);
        final end = (found + term.length + 56).clamp(start, content.length);
        matches.add(
          ChapterSearchMatch(
            chapterIndex: chapterIndex,
            characterOffset: found,
            excerpt: content
                .substring(start, end)
                .replaceAll(RegExp(r'\s+'), ' '),
          ),
        );
        offset = found + term.length;
      }
    }
    return matches;
  }

  Future<void> _externalizeResources(
    Map<String, Object?> payload,
    Directory directory,
  ) async {
    final resourcesDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}resources',
    );
    await resourcesDirectory.create(recursive: true);
    final books = (payload['importedBooks'] as List<Object?>)
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList();
    final referenced = <String>{};
    for (var index = 0; index < books.length; index++) {
      final json = books[index];
      final book = _importedBooks[index];
      for (final entry in <String, Uint8List?>{
        'coverBytes': book.coverBytes,
        'sourceBytes': book.sourceBytes,
      }.entries) {
        final bytes = entry.value;
        if (bytes == null || bytes.isEmpty) continue;
        final fileName = '${sha256.convert(bytes)}-${entry.key}.bin';
        referenced.add(fileName);
        final file = File(
          '${resourcesDirectory.path}${Platform.pathSeparator}$fileName',
        );
        if (!await file.exists() || await file.length() != bytes.length) {
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          if (await file.exists()) await file.delete();
          await temporary.rename(file.path);
        }
        json['${entry.key}Path'] = fileName;
      }
    }
    payload['importedBooks'] = books;
    await for (final entity in resourcesDirectory.list()) {
      if (entity is File &&
          !entity.path.endsWith('.tmp') &&
          !referenced.contains(entity.uri.pathSegments.last)) {
        await entity.delete();
      }
    }
  }

  Future<void> _hydrateExternalResources(
    Map<String, Object?> root,
    Directory directory,
  ) async {
    final books = root['importedBooks'] as List<Object?>? ?? const [];
    for (final raw in books.whereType<Map>()) {
      final json = raw.cast<String, Object?>();
      for (final field in const ['coverBytes', 'sourceBytes']) {
        if (json[field] != null) continue;
        final fileName = json['${field}Path'] as String?;
        if (fileName == null ||
            fileName.contains('/') ||
            fileName.contains('\\')) {
          continue;
        }
        final file = File(
          '${directory.path}${Platform.pathSeparator}resources'
          '${Platform.pathSeparator}$fileName',
        );
        if (await file.exists()) {
          json[field] = base64Encode(await file.readAsBytes());
        }
      }
    }
  }

  Map<String, Object?> _payloadForBooks(Set<String> bookIds) => {
    'schemaVersion': 3,
    'states': {
      for (final entry in _states.entries)
        if (bookIds.contains(entry.key)) entry.key: entry.value.toJson(),
    },
    'activity': _activities
        .where((activity) => bookIds.contains(activity.bookId))
        .map((value) => value.toJson())
        .toList(),
    'preferences': readerPreferences.toJson(),
    'importedBooks': _importedBooks
        .where((book) => bookIds.contains(book.id))
        .map((book) => book.toJson())
        .toList(),
  };

  Future<void> _migrateLegacyStoreIfNeeded(File storageFile) async {
    if (await storageFile.exists()) return;
    final legacyFile = File(
      '${Directory.systemTemp.parent.path}'
      '${Platform.pathSeparator}reading_store_v2.json',
    );
    if (!await legacyFile.exists()) return;
    try {
      await storageFile.parent.create(recursive: true);
      await legacyFile.copy(storageFile.path);
    } on FileSystemException {
      storageError = '旧版本阅读数据迁移失败，原数据未被删除';
    }
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 260), _saveNow);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saveNow();
    if (_dirty) await _saveNow();
  }

  Future<void> _saveNow() {
    final active = _saveInFlight;
    if (active != null) return active;
    final operation = _performSave();
    _saveInFlight = operation;
    return operation.whenComplete(() {
      _saveInFlight = null;
      if (_dirty) _scheduleSave();
    });
  }

  Future<void> _performSave() async {
    if (!_dirty) return;
    final storageFile = _storageFile;
    if (storageFile == null) {
      _dirty = false;
      return;
    }
    try {
      _dirty = false;
      final database = _database;
      final dirtyChapterIds = Set<String>.of(_chapterDirtyIds);
      final deletedChapterIds = Set<String>.of(_deletedChapterIds);
      if (database != null) {
        await database.deleteBooks(deletedChapterIds);
        for (final book in _importedBooks.where(
          (book) => dirtyChapterIds.contains(book.id),
        )) {
          await database.replaceChapters(book.id, book.chapters);
        }
      }
      final payload = _storagePayload();
      await _externalizeResources(payload, storageFile.parent);
      final encoded = await Isolate.run(() => jsonEncode(payload));
      await storageFile.parent.create(recursive: true);
      final temporaryFile = File('${storageFile.path}.tmp');
      final backupFile = File('${storageFile.path}.bak');
      await temporaryFile.writeAsString(encoded, flush: true);
      if (await storageFile.exists()) {
        if (await backupFile.exists()) await backupFile.delete();
        await storageFile.rename(backupFile.path);
      }
      await temporaryFile.rename(storageFile.path);
      _chapterDirtyIds.removeAll(dirtyChapterIds);
      _deletedChapterIds.removeAll(deletedChapterIds);
      if (_automaticBackups) {
        await _writeAutomaticBackupIfDue(storageFile.parent);
      }
      final hadStorageError = storageError != null;
      storageError = null;
      if (hadStorageError) notifyListeners();
    } on Object catch (error, stackTrace) {
      _dirty = true;
      storageError = switch (error) {
        FileSystemException() => '保存失败：${error.osError?.message ?? '请检查存储空间'}',
        DatabaseException() => '保存失败：正文数据库暂时无法写入',
        _ => '保存失败：自动备份未能完成',
      };
      unawaited(DiagnosticsService.record(error, stackTrace));
      notifyListeners();
    }
  }

  Future<void> _writeAutomaticBackupIfDue(Directory directory) async {
    final backupDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}automatic_backups',
    );
    await backupDirectory.create(recursive: true);
    final existing = await backupDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zip'))
        .cast<File>()
        .toList();
    existing.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    if (existing.isNotEmpty &&
        DateTime.now().difference(await existing.first.lastModified()).inHours <
            24) {
      return;
    }
    final day = _dayKey(DateTime.now());
    final target = File(
      '${backupDirectory.path}${Platform.pathSeparator}Shiye-auto-$day.zip',
    );
    // Build the sendable snapshot before entering the isolate. Calling
    // `_payload()` inside the closure captures this store and its SQLite
    // connection, which cannot be sent across isolates.
    final payload = _payload();
    final bytes = await Isolate.run(() => _encodeBackupPayload(payload));
    await target.writeAsBytes(bytes, flush: true);
    for (final obsolete in existing.skip(2)) {
      await obsolete.delete();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final database = _database;
    if (_dirty) {
      unawaited(_saveNow().whenComplete(() => database?.close()));
    } else {
      unawaited(database?.close());
    }
    super.dispose();
  }
}

String _dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool _sameBookMetadata(Book a, Book b) =>
    a.title.trim().toLowerCase() == b.title.trim().toLowerCase() &&
    a.author.trim().toLowerCase() == b.author.trim().toLowerCase();

String _relativeTime(DateTime value) {
  final elapsed = DateTime.now().difference(value);
  if (elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
  if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
  if (elapsed.inDays < 7) return '${elapsed.inDays} 天前';
  if (elapsed.inDays < 30) return '${(elapsed.inDays / 7).floor()} 周前';
  return '${(elapsed.inDays / 30).floor()} 个月前';
}

({Map<String, Object?> root, DateTime? createdAt, bool legacy})
_decodeBackupBytes(Uint8List bytes) {
  if (bytes.isEmpty) throw const FormatException('备份文件为空');
  final first = utf8.decode(bytes.take(1).toList(), allowMalformed: true);
  if (first == '{' || first == '[') {
    final root = (jsonDecode(utf8.decode(bytes)) as Map)
        .cast<String, Object?>();
    if ((root['backupVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('不支持的旧版备份文件');
    }
    return (
      root: root,
      createdAt: DateTime.tryParse(root['createdAt'] as String? ?? ''),
      legacy: true,
    );
  }

  final archive = ZipDecoder().decodeBytes(bytes);
  final files = <String, ArchiveFile>{
    for (final file in archive.files)
      if (file.isFile) file.name: file,
  };
  final manifestFile = files['manifest.json'];
  if (manifestFile == null) throw const FormatException('备份缺少 manifest');
  final manifest = (jsonDecode(utf8.decode(manifestFile.content)) as Map)
      .cast<String, Object?>();
  if (manifest['format'] != 'shiye-backup' ||
      (manifest['backupVersion'] as num?)?.toInt() != 2) {
    throw const FormatException('不支持的备份文件版本');
  }
  final payload = (manifest['payload'] as Map).cast<String, Object?>();
  final books = (payload['importedBooks'] as List<Object?>)
      .whereType<Map>()
      .map((value) => value.cast<String, Object?>())
      .toList();
  for (final raw in manifest['resources'] as List<Object?>? ?? const []) {
    final resource = (raw as Map).cast<String, Object?>();
    final path = resource['path'] as String? ?? '';
    final file = files[path];
    if (file == null) throw FormatException('备份资源缺失：$path');
    final data = Uint8List.fromList(file.content);
    if (data.length != (resource['size'] as num?)?.toInt() ||
        sha256.convert(data).toString() != resource['sha256']) {
      throw FormatException('备份资源校验失败：$path');
    }
    final bookIndex = (resource['bookIndex'] as num?)?.toInt() ?? -1;
    final field = resource['field'] as String? ?? '';
    if (bookIndex < 0 ||
        bookIndex >= books.length ||
        !const {'coverBytes', 'sourceBytes'}.contains(field)) {
      throw const FormatException('备份资源索引无效');
    }
    books[bookIndex][field] = base64Encode(data);
  }
  payload['importedBooks'] = books;
  return (
    root: payload,
    createdAt: DateTime.tryParse(manifest['createdAt'] as String? ?? ''),
    legacy: false,
  );
}

Uint8List _encodeBackupPayload(Map<String, Object?> payload) {
  final books = (payload['importedBooks'] as List<Object?>)
      .whereType<Map>()
      .map((value) => value.cast<String, Object?>())
      .toList();
  payload['importedBooks'] = books;
  final resources = <Map<String, Object?>>[];
  final archive = Archive();
  for (var index = 0; index < books.length; index++) {
    final book = books[index];
    for (final field in const ['coverBytes', 'sourceBytes']) {
      final encoded = book[field] as String?;
      if (encoded == null || encoded.isEmpty) continue;
      final bytes = base64Decode(encoded);
      final path = 'resources/$index-$field.bin';
      resources.add({
        'bookIndex': index,
        'field': field,
        'path': path,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
      archive.addFile(ArchiveFile.bytes(path, bytes));
      book[field] = null;
    }
  }
  archive.addFile(
    ArchiveFile.string(
      'manifest.json',
      const JsonEncoder.withIndent('  ').convert({
        'format': 'shiye-backup',
        'backupVersion': 2,
        'createdAt': DateTime.now().toIso8601String(),
        'resources': resources,
        'payload': payload,
      }),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
