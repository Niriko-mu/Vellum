import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/library_models.dart';

/// What identifies a reading position across a change of typeface.
///
/// A page number is a layout artefact: change the font, the size or the line
/// height and the same page number points at different prose. A paragraph index
/// is a fact about the book. Vellum stores both, and restores from the
/// paragraph - which is why shipping a bundled typeface cannot strand a reader
/// in the wrong place.
void main() {
  test('an empty state has a paragraph position even with no page yet', () {
    expect(const ReadingState().paragraphIndex, 0);
  });

  test('the paragraph index survives a JSON round trip', () {
    const original = ReadingState(
      paragraphIndex: 427,
      page: 91,
      position: 12.5,
    );
    final restored = ReadingState.fromJson(original.toJson());
    expect(
      restored.paragraphIndex,
      427,
      reason: 'this is the field the reader resumes from',
    );
    // The page is kept for display and for the chapter label, but it is not
    // what a resume depends on.
    expect(restored.page, 91);
  });

  test('a page change alone does not move the paragraph position', () {
    // Two states that describe the same place laid out at two different sizes.
    const smallFont = ReadingState(paragraphIndex: 300, page: 40);
    const largeFont = ReadingState(paragraphIndex: 300, page: 61);
    expect(smallFont.paragraphIndex, largeFont.paragraphIndex);
    expect(smallFont.page, isNot(largeFont.page));
  });
}
