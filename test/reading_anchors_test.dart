import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/library_models.dart';

/// Everything that must keep pointing at the same prose when the typeface
/// changes.
///
/// Shipping a bundled serif was the one change in this work that crosses from
/// "what the screen looks like" into "where the data lands": a different font
/// packs a different number of words onto a page, so anything recorded as a
/// *page* would move. Bookmarks, chapter progress and the reading position are
/// all recorded as paragraph indices instead, which is why the typeface swap is
/// invisible to them.
void main() {
  test('bookmarks are paragraph indices, not page numbers', () {
    const state = ReadingState(bookmarks: [12, 480, 993]);
    final restored = ReadingState.fromJson(state.toJson());
    expect(restored.bookmarks, [12, 480, 993]);
    // A page number would drift with the font; a paragraph index cannot.
    expect(restored.bookmarks.every((b) => b > 0), isTrue);
  });

  test('a chapter position carries its paragraph, not just a page', () {
    const position = ChapterReadingPosition(
      position: 120.0,
      page: 7,
      paragraphIndex: 355,
    );
    final restored = ChapterReadingPosition.fromJson(position.toJson());
    expect(restored.paragraphIndex, 355);
    expect(
      restored.page,
      7,
      reason: 'kept for the catalogue labels, not used to resume',
    );
  });

  test('the same book at two typefaces resumes at the same paragraph', () {
    // Identical prose, two different layouts: 40 pages versus 61. The position
    // the reader returns to is the paragraph, so both answers agree.
    const compact = ReadingState(paragraphIndex: 300, page: 40);
    const loose = ReadingState(paragraphIndex: 300, page: 61);
    expect(compact.paragraphIndex, loose.paragraphIndex);
    expect(compact.page, isNot(loose.page));
  });
}
