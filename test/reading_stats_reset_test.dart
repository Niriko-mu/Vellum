import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/reading_stats.dart';

void main() {
  group('ReadingStats model', () {
    test('reset payload is empty', () {
      const empty = ReadingStats();
      expect(empty.totalSeconds, 0);
      expect(empty.dailySeconds, isEmpty);
      expect(empty.bookSeconds, isEmpty);
    });

    test('removing a book keeps other books and cumulative total', () {
      final stats = ReadingStats.fromJson(const {
        'totalSeconds': 100,
        'bookSeconds': {'gone': 40, 'kept': 60},
      });
      final books = {...stats.bookSeconds}..remove('gone');
      final next = stats.copyWith(bookSeconds: books);
      expect(next.bookSeconds.containsKey('gone'), isFalse);
      expect(next.bookSeconds['kept'], 60);
      expect(next.totalSeconds, 100);
    });
  });

  group('buildBookReadingRows', () {
    test('drops deleted books instead of labelling them 未知书籍', () {
      const stats = ReadingStats(
        bookSeconds: {'kept': 30, 'deleted': 50, 'empty-title': 10},
      );
      final rows = buildBookReadingRows(
        stats: stats,
        titleByBookId: {
          'kept': '三体',
          'empty-title': '   ',
        },
      );
      expect(rows.length, 2);
      expect(rows.map((r) => r.bookId), isNot(contains('deleted')));
      expect(rows.any((r) => r.title == '未知书籍'), isFalse);
      // Sorted by time descending.
      expect(rows.first.bookId, 'kept');
      expect(rows.last.title, '未命名');
    });

    test('skips zero/negative durations', () {
      const stats = ReadingStats(bookSeconds: {'a': 0, 'b': -5, 'c': 3});
      final rows = buildBookReadingRows(
        stats: stats,
        titleByBookId: {'a': 'A', 'b': 'B', 'c': 'C'},
      );
      expect(rows.single.bookId, 'c');
    });
  });
}
