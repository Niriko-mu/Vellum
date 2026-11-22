import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'atomic_json_store.dart';
import 'notes_library.dart' show StorageDamagedException;

/// Cumulative reading-time statistics for the local reader.
class ReadingStats {
  const ReadingStats({
    this.totalSeconds = 0,
    this.dailySeconds = const {},
    this.bookSeconds = const {},
  });

  final int totalSeconds;
  final Map<String, int> dailySeconds;
  final Map<String, int> bookSeconds;

  int get todaySeconds =>
      dailySeconds[ReadingStatsService.dayKey(DateTime.now())] ?? 0;

  ReadingStats copyWith({
    int? totalSeconds,
    Map<String, int>? dailySeconds,
    Map<String, int>? bookSeconds,
  }) => ReadingStats(
    totalSeconds: totalSeconds ?? this.totalSeconds,
    dailySeconds: dailySeconds ?? this.dailySeconds,
    bookSeconds: bookSeconds ?? this.bookSeconds,
  );

  Map<String, dynamic> toJson() => {
    'totalSeconds': totalSeconds,
    'dailySeconds': dailySeconds,
    'bookSeconds': bookSeconds,
  };

  factory ReadingStats.fromJson(Map<String, dynamic> json) => ReadingStats(
    totalSeconds: (json['totalSeconds'] as num?)?.toInt() ?? 0,
    dailySeconds: (json['dailySeconds'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    ),
    bookSeconds: (json['bookSeconds'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    ),
  );
}

/// One visible per-book row. Orphaned book ids (deleted books) are dropped
/// so the stats page never labels them 未知书籍.
class BookReadingRow {
  const BookReadingRow({required this.bookId, required this.title, required this.seconds});
  final String bookId;
  final String title;
  final int seconds;
}

/// Pure projection: stats × library index → sorted display rows.
List<BookReadingRow> buildBookReadingRows({
  required ReadingStats stats,
  required Map<String, String> titleByBookId,
}) {
  final rows = <BookReadingRow>[];
  for (final entry in stats.bookSeconds.entries) {
    if (entry.value <= 0) continue;
    final title = titleByBookId[entry.key];
    if (title == null) continue;
    rows.add(
      BookReadingRow(
        bookId: entry.key,
        title: title.trim().isEmpty ? '未命名' : title.trim(),
        seconds: entry.value,
      ),
    );
  }
  rows.sort((a, b) => b.seconds.compareTo(a.seconds));
  return rows;
}

class ReadingStatsService {
  const ReadingStatsService();

  static String dayKey(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static String formatDuration(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    if (minutes > 0) return '$minutes 分钟';
    return '$value 秒';
  }

  /// Totals so far. An unreadable document reads as zero because a stats page
  /// with no numbers is better than one that will not open — but every write
  /// goes through [guardWritable], so the zeros are never saved over it.
  Future<ReadingStats> load() async {
    final stats = await _read();
    return stats ?? const ReadingStats();
  }

  Future<ReadingStats?> _read() async {
    try {
      final file = await _file();
      final result = await AtomicJsonStore.read(file);
      _damaged = result.damaged;
      _damagedPath = result.damaged ? file.path : '';
      if (result.missing) return const ReadingStats();
      if (result.damaged) return null;
      final raw = jsonDecode(result.text!);
      if (raw is Map<String, dynamic>) return ReadingStats.fromJson(raw);
      _damaged = true;
      _damagedPath = file.path;
      return null;
    } catch (_) {
      _damaged = false;
      _damagedPath = '';
      return null;
    }
  }

  Future<void> save(ReadingStats stats) async {
    final file = await _file();
    await AtomicJsonStore.write(file, jsonEncode(stats.toJson()));
  }

  /// Set by [load] when the document exists but cannot be parsed.
  static bool _damaged = false;
  static String _damagedPath = '';

  /// Refuses to overwrite a stats document that cannot be read.
  Future<void> guardWritable() async {
    if (!_damaged) return;
    throw StorageDamagedException(
      '阅读统计文件已损坏，本次没有写入。'
      '${_damagedPath.isEmpty ? '' : '原文件已保留为 $_damagedPath${AtomicJsonStore.quarantineSuffix}。'}',
      path: _damagedPath,
    );
  }

  /// Serialised on a constant key: resolving the path is itself platform I/O.
  Future<T> _serialised<T>(Future<T> Function() operation) =>
      AtomicJsonStore.serialised('vellum_reading_stats', operation);

  /// Adds [seconds] of active reading for [bookId].
  Future<ReadingStats> addSeconds({
    required String bookId,
    required int seconds,
  }) async {
    if (seconds <= 0) return load();
    // Serialised and guarded: the reader flushes every ~10 s while the stats
    // page and book deletion also touch this file, and interleaved
    // read-modify-write loses whole sessions of reading time.
    return _serialised(() async {
      await guardWritable();
      final current = await load();
      final day = dayKey(DateTime.now());
      final next = current.copyWith(
        totalSeconds: current.totalSeconds + seconds,
        dailySeconds: {
          ...current.dailySeconds,
          day: (current.dailySeconds[day] ?? 0) + seconds,
        },
        bookSeconds: {
          ...current.bookSeconds,
          bookId: (current.bookSeconds[bookId] ?? 0) + seconds,
        },
      );
      await save(next);
      return next;
    });
  }

  /// Wipes all accumulated stats (today / total / per-book).
  ///
  /// Deliberately not guarded: resetting is the reader asking to discard the
  /// file, so a damaged one may be replaced.
  Future<void> reset() async {
    await _serialised(() => save(const ReadingStats()));
  }

  /// Drops [bookId]'s row after the book is deleted so the stats page never
  /// has to label it 未知书籍. Totals keep the already-read time (cumulative).
  Future<void> removeBook(String bookId) async {
    if (bookId.isEmpty) return;
    await _serialised(() async {
      await guardWritable();
      final current = await load();
      if (!current.bookSeconds.containsKey(bookId)) return;
      final books = {...current.bookSeconds}..remove(bookId);
      await save(current.copyWith(bookSeconds: books));
    });
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_reading_stats.json',
    );
  }
}
