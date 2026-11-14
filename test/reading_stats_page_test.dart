import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/reading_stats_page.dart';
import 'package:vellum/theme/vellum_theme.dart';

/// Nothing the reader sees may contain an uninterpolated placeholder.
///
/// This is a shape-of-the-bug test, not a copy test: the reading statistics
/// page once shipped a backslash-escaped interpolation, which Dart prints
/// literally. No assertion about wording would have caught it; "a dollar sign
/// or a brace reached the screen" does.
void main() {
  testWidgets('the reading stats page renders no raw placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: const ReadingStatsPage(),
      ),
    );
    // The page loads from disk with a two-second timeout; it falls back to an
    // empty snapshot, which is exactly the state that shows the goal sentence.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .toList();
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        text.contains(String.fromCharCode(36)),
        isFalse,
        reason: 'raw dollar sign reached the screen: $text',
      );
      expect(
        text.contains('{') || text.contains('}'),
        isFalse,
        reason: 'unsubstituted brace reached the screen: $text',
      );
    }
  });
}
