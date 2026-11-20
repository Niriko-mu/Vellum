import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';

/// Line metrics of the bundled serif.
///
/// Noto Serif SC ships its own Latin glyphs, so a mixed Chinese/English line
/// sets both scripts from one font and the baselines agree by construction.
/// These tests pin the spacing ladder itself: it was derived from the reference
/// reader's CSS presets, and a stray edit to one step would quietly change every
/// reader's default page.
void main() {
  test('the spacing ladder is ordered and brackets the reference value', () {
    final heights = ReaderLineSpacing.values.map((s) => s.height).toList();
    expect(heights, [1.45, 1.7, 1.9, 2.2]);
    for (var i = 1; i < heights.length; i++) {
      expect(heights[i], greaterThan(heights[i - 1]));
    }
    // The reference reader sets 1.4 + 0.5 em of leading for its standard step.
    expect(
      ReaderLineSpacing.standard.height,
      1.9,
      reason: 'standard is the default every reader sees on first open',
    );
  });

  test('every step is a real multiplier, not a fixed leading value', () {
    // A fixed leading (e.g. "+12 px") would not scale with the user's font
    // size; these must be ratios so the ladder keeps its feel at 16 or 42 pt.
    for (final step in ReaderLineSpacing.values) {
      expect(step.height, greaterThan(1));
      expect(step.height, lessThan(2.5));
    }
  });

  test('a legacy comfortable value maps to standard, not to relaxed', () {
    // Readers who chose the old middle option must land on the middle option.
    expect(
      ReaderLineSpacing.fromStorage('comfortable'),
      ReaderLineSpacing.standard,
    );
  });

  test('the stored names round-trip', () {
    for (final step in ReaderLineSpacing.values) {
      expect(ReaderLineSpacing.fromStorage(step.name), step);
    }
  });

  test(
    'an unknown stored value falls back to standard rather than throwing',
    () {
      expect(
        ReaderLineSpacing.fromStorage('something-else'),
        ReaderLineSpacing.standard,
      );
    },
  );
}
