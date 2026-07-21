import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../models/book.dart';

class BookReadingState {
  const BookReadingState({
    this.progress = 0,
    this.chapterIndex = 0,
    this.lastReadAt,
    this.totalMinutes = 0,
    this.bookmarkedChapters = const <int>{},
    this.annotations = const <BookAnnotation>[],
  });

  final double progress;
  final int chapterIndex;
  final DateTime? lastReadAt;
  final int totalMinutes;
  final Set<int> bookmarkedChapters;
  final List<BookAnnotation> annotations;

  BookReadingState copyWith({
    double? progress,
    int? chapterIndex,
    DateTime? lastReadAt,
    int? totalMinutes,
    Set<int>? bookmarkedChapters,
    List<BookAnnotation>? annotations,
  }) => BookReadingState(
    progress: progress ?? this.progress,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    totalMinutes: totalMinutes ?? this.totalMinutes,
    bookmarkedChapters: bookmarkedChapters ?? this.bookmarkedChapters,
    annotations: annotations ?? this.annotations,
  );

  Map<String, Object?> toJson() => {
    'progress': progress,
    'chapterIndex': chapterIndex,
    'lastReadAt': lastReadAt?.toIso8601String(),
    'totalMinutes': totalMinutes,
    'bookmarkedChapters': bookmarkedChapters.toList(),
    'annotations': annotations.map((value) => value.toJson()).toList(),
  };

  factory BookReadingState.fromJson(Map<String, Object?> json) =>
      BookReadingState(
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
        lastReadAt: DateTime.tryParse(json['lastReadAt'] as String? ?? ''),
        totalMinutes: (json['totalMinutes'] as num?)?.toInt() ?? 0,
        bookmarkedChapters:
            ((json['bookmarkedChapters'] as List<Object?>?) ?? const [])
                .whereType<num>()
                .map((value) => value.toInt())
                .toSet(),
        annotations: ((json['annotations'] as List<Object?>?) ?? const [])
            .whereType<Map>()
            .map(
              (value) => BookAnnotation.fromJson(value.cast<String, Object?>()),
            )
            .toList(),
      );
}

class BookAnnotation {
  const BookAnnotation({
    required this.chapterIndex,
    required this.selectedText,
    required this.note,
    required this.createdAt,
  });

  final int chapterIndex;
  final String selectedText;
  final String note;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'chapterIndex': chapterIndex,
    'selectedText': selectedText,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory BookAnnotation.fromJson(Map<String, Object?> json) => BookAnnotation(
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
    selectedText: json['selectedText'] as String? ?? '',
    note: json['note'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
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
  });

  final double fontSize;
  final double lineHeight;
  final int backgroundValue;
  final TextAlign alignment;
  final bool eyeCare;
  final String pageTurn;

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'backgroundValue': backgroundValue,
    'alignment': alignment.name,
    'eyeCare': eyeCare,
    'pageTurn': pageTurn,
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
      );
}

/// Pure-Dart persistence keeps the app buildable without native preference
/// plugins. The file lives in the app sandbox on Android and beside the
/// process cache on desktop.
class ReadingStore extends ChangeNotifier {
  ReadingStore({File? storageFile})
    : _storageFile =
          storageFile ??
          File(
            '${Directory.systemTemp.parent.path}'
            '${Platform.pathSeparator}reading_store_v2.json',
          );

  ReadingStore.memory() : _storageFile = null;

  final File? _storageFile;
  final Map<String, BookReadingState> _states = {};
  final List<ReadingActivity> _activities = [];
  final List<Book> _importedBooks = [];
  ReaderPreferences readerPreferences = const ReaderPreferences();
  Timer? _saveTimer;
  bool _dirty = false;
  Future<void>? _saveInFlight;

  List<Book> get importedBooks => List.unmodifiable(_importedBooks);

  Future<void> initialize() async {
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

  void updateProgress(Book book, double progress, int chapterIndex) {
    final previous = stateFor(book);
    _states[book.id] = previous.copyWith(
      progress: progress.clamp(0, 1),
      chapterIndex: chapterIndex,
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

  void toggleBookmark(Book book, int chapterIndex) {
    final previous = stateFor(book);
    final chapters = Set<int>.of(previous.bookmarkedChapters);
    chapters.contains(chapterIndex)
        ? chapters.remove(chapterIndex)
        : chapters.add(chapterIndex);
    _states[book.id] = previous.copyWith(bookmarkedChapters: chapters);
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
      (item) => item.id == book.id || legacyTitles.contains(item.title.trim()),
    );
    if (existing >= 0) {
      final previous = _importedBooks[existing];
      _importedBooks[existing] = book;
      if (previous.id != book.id) _states.remove(previous.id);
    } else {
      _importedBooks.add(book);
    }
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

  void addAnnotation(Book book, BookAnnotation annotation) {
    final previous = stateFor(book);
    _states[book.id] = previous.copyWith(
      annotations: [...previous.annotations, annotation],
    );
    _scheduleSave();
    notifyListeners();
  }

  void removeAnnotation(Book book, BookAnnotation annotation) {
    final previous = stateFor(book);
    final annotations = List<BookAnnotation>.of(previous.annotations)
      ..remove(annotation);
    _states[book.id] = previous.copyWith(annotations: annotations);
    _scheduleSave();
    notifyListeners();
  }

  void removeImportedBook(Book book) {
    _importedBooks.removeWhere((item) => item.id == book.id);
    _states.remove(book.id);
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

  Future<void> _readSavedData() async {
    final storageFile = _storageFile;
    if (storageFile == null || !await storageFile.exists()) return;
    try {
      final root = (jsonDecode(await storageFile.readAsString()) as Map)
          .cast<String, Object?>();
      final states = (root['states'] as Map?)?.cast<String, Object?>() ?? {};
      for (final entry in states.entries) {
        _states[entry.key] = BookReadingState.fromJson(
          (entry.value as Map).cast<String, Object?>(),
        );
      }
      _activities.addAll(
        ((root['activity'] as List<Object?>?) ?? const []).whereType<Map>().map(
          (value) => ReadingActivity.fromJson(value.cast<String, Object?>()),
        ),
      );
      final preferences = root['preferences'];
      if (preferences is Map) {
        readerPreferences = ReaderPreferences.fromJson(
          preferences.cast<String, Object?>(),
        );
      }
      _importedBooks.addAll(
        ((root['importedBooks'] as List<Object?>?) ?? const [])
            .whereType<Map>()
            .map((value) => Book.fromJson(value.cast<String, Object?>())),
      );
    } on Object {
      // A corrupt or stale cache should never block the reader from opening.
      _states.clear();
      _activities.clear();
      _importedBooks.clear();
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
      final payload = {
        'states': _states.map((key, value) => MapEntry(key, value.toJson())),
        'activity': _activities.map((value) => value.toJson()).toList(),
        'preferences': readerPreferences.toJson(),
        'importedBooks': _importedBooks.map((book) => book.toJson()).toList(),
      };
      final encoded = await Isolate.run(() => jsonEncode(payload));
      await storageFile.parent.create(recursive: true);
      await storageFile.writeAsString(encoded, flush: true);
    } on FileSystemException {
      // Keep the in-memory session usable if storage is temporarily unavailable.
      _dirty = true;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(_saveNow());
    super.dispose();
  }
}

String _dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _relativeTime(DateTime value) {
  final elapsed = DateTime.now().difference(value);
  if (elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
  if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
  if (elapsed.inDays < 7) return '${elapsed.inDays} 天前';
  if (elapsed.inDays < 30) return '${(elapsed.inDays / 7).floor()} 周前';
  return '${(elapsed.inDays / 30).floor()} 个月前';
}
