import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  PageLayoutConfig config({double height = 800}) => PageLayoutConfig(
        fontSize: 24,
        lineSpacing: ReaderLineSpacing.standard,
        fontFamily: 'Roboto',
        fontWeight: ReaderFontWeight.regular,
        availableHeight: height,
        contentWidth: 320,
        screenHeight: 800,
        title: '长句填页',
      );

  test('a long sentence fills the page instead of leaving a 22px dead zone', () {
    // ~40 chars/line at 24dp × 320w ≈ 8–10 lines; one huge paragraph.
    final long = '这是一句会被拆到下一页的超长句子' * 20;
    final book = ImportedBook(
      title: '长句填页',
      format: BookFormat.txt,
      paragraphs: [long],
    );
    final cfg = config();
    final pager = ProgressiveBookPager(book, cfg);
    pager.paginateUntilPages(2);

    final first = pager.pages.first;
    expect(first, isNotEmpty);
    final fragmentText = first.map((f) => f.text).join();
    // Page 1 must keep a large share of the sentence — not stop early.
    expect(fragmentText.length, greaterThan(long.length * 0.15));

    // Last fragment on the page has no trailing paragraph gap in the model
    // (render gives it 0 bottom padding).
    expect(first.last.compactPadding || first.length == 1, isTrue);
  });

  test('continuation fragments skip the inter-paragraph gap', () {
    final long = '第二段同样很长' * 30;
    final book = ImportedBook(
      title: '续段',
      format: BookFormat.txt,
      paragraphs: ['前一段。', long],
    );
    final pager = ProgressiveBookPager(book, config());
    pager.paginateUntilPages(3);
    expect(pager.pages.length, greaterThanOrEqualTo(2));
    // Every continuation piece (not the paragraph's first fragment) is compact.
    for (final page in pager.pages) {
      for (final fragment in page) {
        if (fragment.paragraphIndex == 1 && fragment.text != long) {
          // split pieces of paragraph 1
        }
      }
    }
    final continues = pager.pages
        .expand((p) => p)
        .where((f) => f.paragraphIndex == 1 && f.text.isNotEmpty)
        .toList();
    expect(continues.length, greaterThan(1));
    expect(continues.first.compactPadding, isFalse);
    expect(continues.skip(1).every((f) => f.compactPadding), isTrue);
  });
}
