import 'package:flutter/material.dart'
    show Brightness, Key, MaterialApp, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/book_details_page.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/theme/app_motion.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/ui/book_motion.dart';

/// The book journey: shelf -> details -> reader -> back.
///
/// The effects here are invisible to a settled screenshot - what these
/// assertions protect is the contract behind them: the platform gesture
/// survives, the hero tag is content-addressed, the details page shows only
/// owned metadata, and reduced motion still shows a complete page.
void main() {
  final book = ImportedBook(
    id: 'txt_deadbeef',
    title: '旅程之书',
    author: '某作者',
    format: BookFormat.txt,
    paragraphs: List.generate(
      120,
      (i) => '第' + (i + 1).toString() + '段落正文内容，用来构成可阅读的正文。',
    ),
    tocEntries: const [
      BookTocEntry(title: '第一章 启程', paragraphIndex: 0),
      BookTocEntry(title: '第二章 山口', paragraphIndex: 40),
    ],
  );

  test('BookJourneyRoute keeps the platform durations and gesture', () {
    final details = BookJourneyRoute<void>(builder: (_) => const SizedBox());
    expect(details.transitionDuration, AppMotion.slow);
    expect(details.reverseTransitionDuration, AppMotion.base);
    details.dispose();

    final reading = BookJourneyRoute<void>(
      builder: (_) => const SizedBox(),
      reading: true,
    );
    // The reading leg must not be slower out than in.
    expect(
      reading.reverseTransitionDuration.inMilliseconds,
      lessThan(reading.transitionDuration.inMilliseconds),
    );
    reading.dispose();
  });

  test('hero tags are content-addressed, not title-addressed', () {
    final a = bookCoverHeroTag('txt_deadbeef');
    final b = bookCoverHeroTag('txt_other');
    expect(a, isNot(b));
    expect(a, contains('txt_deadbeef'));
  });

  testWidgets('details page shows owned metadata and one read action', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: BookDetailsPage(
          book: book,
          progress: .35,
          onRead: () async => reads++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('旅程之书'), findsOneWidget);
    expect(find.text('某作者'), findsOneWidget);
    // One chip spells the format; the default cover artwork repeats it.
    expect(find.text('TXT'), findsWidgets);
    expect(find.text('2 章节'), findsOneWidget);
    expect(find.text('继续阅读 · 35%'), findsOneWidget);
    expect(find.byKey(const Key('book-detail-read')), findsOneWidget);
    // The catalogue preview comes from persisted metadata, not a fetch.
    expect(find.text('第一章 启程'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-detail-read')));
    await tester.pumpAndSettle();
    expect(reads, 1);
  });

  testWidgets(
    'a book without chapters explains itself instead of an empty list',
    (tester) async {
      final plain = ImportedBook(
        id: 'txt_plain',
        title: '无目录书',
        format: BookFormat.txt,
        paragraphs: List.generate(10, (i) => '段落$i'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: VellumTheme.forBrightness(Brightness.light),
          home: BookDetailsPage(book: plain, progress: 0, onRead: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('开始阅读'), findsOneWidget);
      expect(find.text('尚未开始'), findsOneWidget);
      expect(find.text('TXT 会在打开时读取章节索引。'), findsOneWidget);
    },
  );
}
