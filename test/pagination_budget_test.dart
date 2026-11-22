import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/services/book_importer.dart';

/// A generated book, so only pagination work is measured.
class _GeneratedParagraphs extends ListBase<String> {
  _GeneratedParagraphs(this.length);

  @override
  final int length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  String operator [](int index) => '第${index + 1}段的正文内容，用来产生足够多的页数。';

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read-only');
}

void main() {
  ImportedBook book({int paragraphs = 300000}) => ImportedBook(
    title: '二十四史',
    format: BookFormat.txt,
    paragraphs: _GeneratedParagraphs(paragraphs),
  );

  PageLayoutConfig config() => const PageLayoutConfig(
    fontSize: 24,
    lineSpacing: ReaderLineSpacing.standard,
    fontFamily: 'Georgia',
    fontWeight: ReaderFontWeight.regular,
    availableHeight: 700,
    contentWidth: 360,
    screenHeight: 800,
    title: '二十四史',
  );

  /// The footer getter used to run calibrateEstimate() inside build, which
  /// measured up to 150 paragraphs — hundreds of milliseconds on a slow phone,
  /// once per first frame after a deep jump — and changed itemCount mid-frame.
  test('reading the book page count measures nothing', () {
    final pager = ProgressiveBookPager(book(), config());
    pager.paginateFrom(250000, minPages: 12);

    final measuredBefore = pager.nextParagraph;
    final countBefore = pager.estimatedGlobalPageCount;

    // Read it the way the footer and the progress row do: repeatedly, as if
    // once per frame.
    for (var i = 0; i < 10; i++) {
      expect(pager.estimatedGlobalPageCount, countBefore);
    }

    expect(
      pager.nextParagraph,
      measuredBefore,
      reason: 'reading the page count must not paginate',
    );
  });

  test('an anchored window reports how calibrated its estimate is', () {
    final pager = ProgressiveBookPager(book(), config());
    pager.paginateFrom(250000, minPages: 12);

    // A fresh window is anchored and has not sampled 150 paragraphs yet.
    expect(pager.isAnchored, isTrue);
    final before = pager.isEstimateCalibrated;

    pager.calibrateEstimate();

    expect(pager.isEstimateCalibrated, isTrue);
    if (!before) {
      // Calibration is what widens the sample; it is allowed to measure.
      expect(pager.nextParagraph, greaterThan(250000));
    }
  });

  test('a slice stops at its time budget', () {
    final pager = ProgressiveBookPager(book(paragraphs: 20000), config());
    pager.paginateFrom(0, minPages: 4);

    final start = pager.nextParagraph;
    final clock = Stopwatch()..start();
    // Wait for the budget to already be spent, then ask for 50 paragraphs: the
    // paragraph loop must notice almost immediately instead of laying all 50 we
    // never had time for.
    while (clock.elapsedMilliseconds < 2) {}
    pager.paginateSlice(maxParagraphs: 50, clock: clock, budgetMs: 1);

    expect(
      pager.nextParagraph - start,
      lessThanOrEqualTo(1),
      reason:
          'an exhausted budget measures at most one paragraph — never zero, '
          'because a slice that never advances would spin forever',
    );
  });

  test('without a budget a slice still measures its whole request', () {
    final pager = ProgressiveBookPager(book(paragraphs: 20000), config());
    pager.paginateFrom(0, minPages: 4);

    final start = pager.nextParagraph;
    pager.paginateSlice(maxParagraphs: 5);

    expect(pager.nextParagraph, start + 5);
  });

  test('paginateThrough honours the clock as well', () {
    final pager = ProgressiveBookPager(book(paragraphs: 20000), config());
    pager.paginateFrom(0, minPages: 4);

    final start = pager.nextParagraph;
    final clock = Stopwatch()..start();
    while (clock.elapsedMilliseconds < 2) {}
    pager.paginateThrough(start + 5000, clock: clock, budgetMs: 1);

    expect(
      pager.nextParagraph,
      lessThan(start + 5000),
      reason: 'a seek must not measure a prefix past its budget',
    );
  });
}
