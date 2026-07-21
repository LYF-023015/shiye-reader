import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../theme/app_theme.dart';
import '../widgets/book_cover.dart';
import 'reader_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.books,
    required this.readingStore,
  });

  final List<Book> books;
  final ReadingStore readingStore;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _rangeDays = 183;

  Future<void> _showFilter() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF15191D),
      builder: (context) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF79C5DB)),
        ),
        child: SafeArea(
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
                          : Colors.white38,
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
      ),
    );
    if (selected != null && mounted) setState(() => _rangeDays = selected);
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.readingStore.activityByDay(days: _rangeDays);
    final books = widget.readingStore.sortByRecent(widget.books);
    final weeklyHours = widget.readingStore.weeklyMinutes / 60;
    final totalHours = widget.readingStore.totalMinutes / 60;

    return ColoredBox(
      color: const Color(0xFF08090B),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('history-filter'),
                      onPressed: _showFilter,
                      tooltip: '筛选',
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white70,
                      ),
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
                    color: const Color(0xFF11161A),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white10),
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
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(24, 26, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '最近阅读',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: books.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 34),
                        child: Center(
                          child: Text(
                            '开始阅读后，记录会出现在这里',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      ),
                    )
                  : SliverList.builder(
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        final state = widget.readingStore.stateFor(book);
                        return ListTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReaderScreen(
                                book: book,
                                readingStore: widget.readingStore,
                              ),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          leading: BookCover(book: book, width: 46),
                          title: Text(
                            book.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${book.lastRead} · 累计阅读 ${state.totalMinutes} 分钟',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          trailing: Text(
                            '${(book.progress * 100).round()}%',
                            style: const TextStyle(color: Colors.white54),
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

  static const _colors = [
    Color(0xFF1A2226),
    Color(0xFF244049),
    Color(0xFF326171),
    Color(0xFF4D8DA0),
    Color(0xFF79C5DB),
  ];

  @override
  Widget build(BuildContext context) {
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
        color: const Color(0xFF10171B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'READING HALF YEAR',
                    style: TextStyle(
                      color: Color(0xFF79C5DB),
                      fontSize: 11,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '阅读足迹',
                    style: TextStyle(
                      color: Colors.white,
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
                style: const TextStyle(
                  color: Colors.white54,
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
                                style: const TextStyle(
                                  color: Colors.white38,
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
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const Spacer(),
              const Text(
                '少',
                style: TextStyle(color: Colors.white54, fontSize: 9),
              ),
              const SizedBox(width: 5),
              for (final color in _colors) ...[
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
              const Text(
                '多',
                style: TextStyle(color: Colors.white54, fontSize: 9),
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
  });

  final DateTime date;
  final int minutes;
  final double size;
  final bool enabled;

  Color get color {
    if (!enabled) return Colors.transparent;
    if (minutes <= 0) return _ReadingHeatmap._colors[0];
    if (minutes < 15) return _ReadingHeatmap._colors[1];
    if (minutes < 30) return _ReadingHeatmap._colors[2];
    if (minutes < 60) return _ReadingHeatmap._colors[3];
    return _ReadingHeatmap._colors[4];
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
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }
}

class _HistoryDivider extends StatelessWidget {
  const _HistoryDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: Colors.white12);
}
