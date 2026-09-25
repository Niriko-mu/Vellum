import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../services/reading_stats.dart';
import '../theme/vellum_theme.dart';

/// Settings → 阅读统计：今日/累计 + 每本书阅读时长。
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
    final pageBackground = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final pressedBackground = VellumTheme.cardOf(context);
    final muted = VellumTheme.mutedOf(context);

    return CupertinoPageScaffold(
      backgroundColor: pageBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: VellumTheme.shellOf(context),
        border: null,
        middle: const Text('阅读统计'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: _confirmReset,
          child: Text(
            '重置',
            style: TextStyle(
              color: CupertinoColors.destructiveRed.resolveFrom(context),
              fontSize: 16,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  CupertinoListSection.insetGrouped(
                    backgroundColor: pageBackground,
                    header: const Text('汇总'),
                    children: [
                      CupertinoListTile(
                        backgroundColor: pageBackground,
                        backgroundColorActivated: pressedBackground,
                        leading: const Icon(CupertinoIcons.sun_max),
                        title: const Text('今日阅读'),
                        additionalInfo: Text(
                          ReadingStatsService.formatDuration(
                            _stats.todaySeconds,
                          ),
                        ),
                      ),
                      CupertinoListTile(
                        backgroundColor: pageBackground,
                        backgroundColorActivated: pressedBackground,
                        leading: const Icon(CupertinoIcons.clock),
                        title: const Text('累计阅读'),
                        additionalInfo: Text(
                          ReadingStatsService.formatDuration(
                            _stats.totalSeconds,
                          ),
                        ),
                      ),
                    ],
                  ),
                  CupertinoListSection.insetGrouped(
                    backgroundColor: pageBackground,
                    header: const Text('按书籍'),
                    children: _rows.isEmpty
                        ? [
                            CupertinoListTile(
                              backgroundColor: pageBackground,
                              backgroundColorActivated: pressedBackground,
                              leading: Icon(CupertinoIcons.book, color: muted),
                              title: Text(
                                '暂无阅读记录',
                                style: TextStyle(color: muted),
                              ),
                            ),
                          ]
                        : [
                            for (final row in _rows)
                              CupertinoListTile(
                                backgroundColor: pageBackground,
                                backgroundColorActivated: pressedBackground,
                                leading: const Icon(CupertinoIcons.book),
                                title: Text(row.title),
                                additionalInfo: Text(
                                  ReadingStatsService.formatDuration(
                                    row.seconds,
                                  ),
                                ),
                              ),
                          ],
                  ),
                ],
              ),
      ),
    );
  }
}

