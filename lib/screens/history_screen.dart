import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../theme/app_theme.dart';
import '../widgets/book_cover.dart';
import 'reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'epub_reader_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.books,
    required this.readingStore,
    required this.onOpenAnnotations,
  });

  final List<Book> books;
  final ReadingStore readingStore;
  final VoidCallback onOpenAnnotations;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _rangeDays = 183;

  Future<void> _showFilter() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '阅读记录范围',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final option in const [30, 90, 183])
                ListTile(
                  leading: Icon(
                    option == _rangeDays
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: option == _rangeDays
                        ? AppColors.accent
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .38),
                  ),
                  title: Text(
                    option == 30
                        ? '最近30天'
                        : option == 90
                        ? '最近3个月'
                        : '最近半年',
                  ),
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _rangeDays = selected);
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.readingStore.activityByDay(days: _rangeDays);
    final cutoff = DateTime.now().subtract(Duration(days: _rangeDays));
    final books = widget.readingStore.sortByRecent(
      widget.books.where((book) {
        final lastReadAt = widget.readingStore.stateFor(book).lastReadAt;
        return lastReadAt != null && !lastReadAt.isBefore(cutoff);
      }).toList(),
    );
    final weeklyHours = widget.readingStore.weeklyMinutes / 60;
    final totalHours = widget.readingStore.totalMinutes / 60;

    final titleColor = Theme.of(context).colorScheme.onSurface;
    final subduedColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .6);

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const ValueKey('history-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(
                      '阅读记录',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('annotations-button'),
                      onPressed: widget.onOpenAnnotations,
                      tooltip: '全部批注',
                      icon: Icon(
                        Icons.format_quote_rounded,
                        color: subduedColor,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('history-filter'),
                      onPressed: _showFilter,
                      tooltip: '筛选',
                      icon: Icon(Icons.tune_rounded, color: subduedColor),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverToBoxAdapter(
                child: _ReadingHeatmap(
                  activity: activity,
                  days: _rangeDays,
                  totalMinutes: activity.values.fold(
                    0,
                    (sum, value) => sum + value,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _HistoryStat(
                        value: weeklyHours.toStringAsFixed(1),
                        label: '本周小时',
                      ),
                      const _HistoryDivider(),
                      _HistoryStat(
                        value: widget.readingStore.readingDays.toString(),
                        label: '阅读天数',
                      ),
                      const _HistoryDivider(),
                      _HistoryStat(
                        value: totalHours.toStringAsFixed(0),
                        label: '累计小时',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '最近阅读',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: books.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        child: Center(
                          child: Text(
                            '开始阅读后，记录会出现在这里',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: .4),
                            ),
                          ),
                        ),
                      ),
                    )
                  : SliverList.builder(
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        final state = widget.readingStore.stateFor(book);
                        return Slidable(
                          key: ValueKey('history-${book.id}'),
                          endActionPane: ActionPane(
                            motion: const BehindMotion(),
                            extentRatio: .24,
                            children: [
                              SlidableAction(
                                borderRadius: BorderRadius.circular(16),
                                backgroundColor: const Color(0xFFB33A3A),
                                foregroundColor: Colors.white,
                                icon: Icons.delete_outline_rounded,
                                label: '删除',
                                onPressed: (_) => _confirmDelete(book),
                              ),
                            ],
                          ),
                          child: ListTile(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => switch (book.format) {
                                  BookFormat.pdf => PdfReaderScreen(
                                    book: book,
                                    readingStore: widget.readingStore,
                                  ),
                                  BookFormat.epub =>
                                    book.sourceBytes?.isNotEmpty == true
                                        ? EpubReaderScreen(
                                            book: book,
                                            readingStore: widget.readingStore,
                                          )
                                        : ReaderScreen(
                                            book: book,
                                            readingStore: widget.readingStore,
                                          ),
                                  BookFormat.txt => ReaderScreen(
                                    book: book,
                                    readingStore: widget.readingStore,
                                  ),
                                },
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            leading: BookCover(book: book, width: 46),
                            title: Text(
                              book.title,
                              style: TextStyle(
                                color: titleColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${book.lastRead} · 累计阅读 ${state.totalMinutes} 分钟',
                              style: TextStyle(
                                color: subduedColor,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              '${(book.progress * 100).round()}%',
                              style: TextStyle(color: subduedColor),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这本书？'),
        content: Text('《${book.title}》及其阅读进度、书签和批注将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.readingStore.removeImportedBook(book);
  }
}

class _ReadingHeatmap extends StatelessWidget {
  const _ReadingHeatmap({
    required this.activity,
    required this.days,
    required this.totalMinutes,
  });

  final Map<DateTime, int> activity;
  final int days;
  final int totalMinutes;

  static const _darkColors = [
    Color(0xFF1A2226),
    Color(0xFF244049),
    Color(0xFF326171),
    Color(0xFF4D8DA0),
    Color(0xFF79C5DB),
  ];

  static const _lightColors = [
    Color(0xFFE4ECEE),
    Color(0xFFC8E0E5),
    Color(0xFF91C4CF),
    Color(0xFF59A1B1),
    Color(0xFF28798C),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = isDark ? _darkColors : _lightColors;
    final foreground = theme.colorScheme.onSurface;
    final today = DateTime.now();
    final lastDay = DateTime(today.year, today.month, today.day);
    final requestedFirst = lastDay.subtract(Duration(days: days - 1));
    final firstDay = requestedFirst.subtract(
      Duration(days: requestedFirst.weekday - DateTime.monday),
    );
    final weekCount = (lastDay.difference(firstDay).inDays / 7).ceil() + 1;

    return Container(
      key: const ValueKey('reading-heatmap'),
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10171B) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .32 : .08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    days == 183
                        ? 'READING HALF YEAR'
                        : days == 90
                        ? 'READING 90 DAYS'
                        : 'READING 30 DAYS',
                    style: const TextStyle(
                      color: Color(0xFF79C5DB),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '阅读足迹',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '过去${days == 183 ? '半年' : '$days天'}\n$totalMinutes 分钟',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: foreground.withValues(alpha: .54),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              const labelWidth = 25.0;
              const gap = 2.0;
              final cell = math.min(
                10.0,
                (constraints.maxWidth - labelWidth - gap * (weekCount - 1)) /
                    weekCount,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      children: [
                        for (var day = 0; day < 7; day++)
                          SizedBox(
                            height: cell + gap,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                day == 0
                                    ? '一'
                                    : day == 2
                                    ? '三'
                                    : day == 4
                                    ? '五'
                                    : '',
                                style: TextStyle(
                                  color: foreground.withValues(alpha: .38),
                                  fontSize: 8,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var week = 0; week < weekCount; week++) ...[
                    Column(
                      children: [
                        for (var day = 0; day < 7; day++)
                          _HeatCell(
                            date: firstDay.add(Duration(days: week * 7 + day)),
                            minutes:
                                activity[firstDay.add(
                                  Duration(days: week * 7 + day),
                                )] ??
                                0,
                            size: cell,
                            colors: colors,
                            enabled: !firstDay
                                .add(Duration(days: week * 7 + day))
                                .isAfter(lastDay),
                          ),
                      ],
                    ),
                    if (week != weekCount - 1) const SizedBox(width: gap),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${requestedFirst.year}.${requestedFirst.month.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: foreground.withValues(alpha: .54),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                '少',
                style: TextStyle(
                  color: foreground.withValues(alpha: .54),
                  fontSize: 9,
                ),
              ),
              const SizedBox(width: 5),
              for (final color in colors) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
              ],
              Text(
                '多',
                style: TextStyle(
                  color: foreground.withValues(alpha: .54),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.date,
    required this.minutes,
    required this.size,
    required this.enabled,
    required this.colors,
  });

  final DateTime date;
  final int minutes;
  final double size;
  final bool enabled;
  final List<Color> colors;

  Color get color {
    if (!enabled) return Colors.transparent;
    if (minutes <= 0) return colors[0];
    if (minutes < 15) return colors[1];
    if (minutes < 30) return colors[2];
    if (minutes < 60) return colors[3];
    return colors[4];
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${date.month}月${date.day}日，阅读$minutes分钟',
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2.2),
        ),
      ),
    );
  }
}

class _HistoryStat extends StatelessWidget {
  const _HistoryStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.onSurface.withValues(alpha: .54),
          ),
        ),
      ],
    );
  }
}

class _HistoryDivider extends StatelessWidget {
  const _HistoryDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: Theme.of(context).dividerColor);
}
