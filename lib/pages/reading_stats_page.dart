import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show AlwaysStoppedAnimation, LinearProgressIndicator;

import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../services/reading_stats.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_motion.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_page.dart';
import '../widgets/ui/app_section.dart';

/// Settings → 阅读统计：今日/累计 + 每本书阅读时长.
///
/// One continuous surface with three grouped blocks, not a page of cards: the
/// block is the grouping, and the hairlines inside it are structural.
class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  final _library = const BookLibrary();
  final _statsService = const ReadingStatsService();
  ReadingStats _stats = const ReadingStats();
  List<BookReadingRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    ReadingStats stats = const ReadingStats();
    List<ImportedBook> books = [];
    try {
      stats = await _statsService.load().timeout(const Duration(seconds: 2));
      books = await _library.load().timeout(const Duration(seconds: 2));
    } catch (_) {}
    // Deleted books are skipped (never 未知书籍).
    final rows = buildBookReadingRows(
      stats: stats,
      titleByBookId: {
        for (final book in books)
          book.storageId: book.title.trim().isEmpty ? '未命名' : book.title.trim(),
      },
    );
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _confirmReset() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('重置阅读统计？'),
        content: const Text('今日、累计和按书籍的阅读时长都会清零，此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _statsService.reset();
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final week = List.generate(7, (index) {
      final day = DateTime.now().subtract(Duration(days: 6 - index));
      return (
        label: _dayLabel(day),
        seconds: _stats.dailySeconds[ReadingStatsService.dayKey(day)] ?? 0,
        today: index == 6,
      );
    });
    final weekMax = week.fold<int>(
      0,
      (max, item) => item.seconds > max ? item.seconds : max,
    );
    const goalSeconds = 30 * 60;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.background,
        border: null,
        middle: const Text('阅读统计'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: _confirmReset,
          child: Text(
            '重置',
            style: AppText.rowTitle(colors.destructive),
          ),
        ),
      ),
      child: _loading
          ? const AppPage(
              child: Center(
                child: AppContentState(kind: AppContentStateKind.loading),
              ),
            )
          : AppPage(
              sections: [
                const SizedBox(height: AppSpace.x4),
                AppSection(
                  header: '今天',
                  headerTrailing: Text(
                    '目标 30 分钟',
                    style: AppText.caption(colors.mutedForeground),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.x4,
                        AppSpace.x4,
                        AppSpace.x4,
                        AppSpace.x4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ReadingStatsService.formatDuration(
                              _stats.todaySeconds,
                            ),
                            style: AppText.pageTitle(colors.foreground),
                          ),
                          const SizedBox(height: AppSpace.x3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppRadius.hairlineXs,
                            ),
                            child: LinearProgressIndicator(
                              value: (_stats.todaySeconds / goalSeconds).clamp(
                                0.0,
                                1.0,
                              ),
                              minHeight: 6,
                              backgroundColor: colors.border,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpace.x3),
                          Text(
                            _stats.todaySeconds >= goalSeconds
                                ? '今日目标已完成，继续保持。'
                                : '再阅读 \${ReadingStatsService.formatDuration(goalSeconds - _stats.todaySeconds)} 达成今日目标。',
                            style: AppText.rowDescription(
                              colors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AppSection(
                  header: '最近 7 天',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.x3,
                        AppSpace.x4,
                        AppSpace.x3,
                        AppSpace.x3,
                      ),
                      child: _WeekBars(week: week, weekMax: weekMax),
                    ),
                  ],
                ),
                AppSection(
                  header: '按书籍',
                  children: _rows.isEmpty
                      ? [
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpace.x4,
                              vertical: AppSpace.x4,
                            ),
                            child: AppContentState(
                              kind: AppContentStateKind.empty,
                              compact: true,
                              title: '暂无阅读记录',
                            ),
                          ),
                        ]
                      : [
                          for (final row in _rows)
                            AppRow(
                              label: row.title,
                              value: ReadingStatsService.formatDuration(
                                row.seconds,
                              ),
                            ),
                        ],
                ),
              ],
            ),
    );
  }

  String _dayLabel(DateTime day) {
    if (day.day == DateTime.now().day && day.month == DateTime.now().month) {
      return '今';
    }
    return '\${day.month}/\${day.day}';
  }
}

/// A single-colour bar chart. Today is distinguished by label weight and the
/// solid fill, not by a second hue.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.week, required this.weekMax});

  final List<({String label, int seconds, bool today})> week;
  final int weekMax;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final item in week)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 76,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: motionDuration(context, AppMotion.base),
                        curve: AppMotion.settle,
                        width: 14,
                        height: weekMax == 0
                            ? 5
                            : (item.seconds / weekMax * 64).clamp(5.0, 64.0),
                        decoration: BoxDecoration(
                          color: item.today
                              ? colors.primary
                              : colors.primary.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    style: item.today
                        ? AppText.caption(
                            colors.foreground,
                          ).copyWith(fontWeight: FontWeight.w500)
                        : AppText.caption(colors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
