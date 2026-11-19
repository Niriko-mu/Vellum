import 'package:flutter/material.dart'
    show Brightness, MaterialApp, MediaQuery, MediaQueryData;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/home_page.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/theme/vellum_theme.dart';

/// The home page's arrival must never get between the reader and the book.
///
/// Its reveal is shared with the shelf, so this test guards the property that
/// matters at this call site: the continue-reading card is on screen and
/// tappable on the very first frame, while the entrance is still running.
void main() {
  ImportedBook book(int i) => ImportedBook(
    id: 'txt_home_$i',
    title: '首页测试书 $i',
    author: '作者 $i',
    format: BookFormat.txt,
    paragraphs: List.generate(50, (p) => '段落$p'),
  );

  testWidgets('continue-reading is tappable on the first frame', (
    tester,
  ) async {
    ImportedBook? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: HomePage(
          books: [book(0), book(1)],
          onOpen: (b) => opened = b,
          onOpenDetails: (_) {},
          onImport: () {},
        ),
      ),
    );
    // One frame only: the reveal has barely started.
    await tester.pump();
    final card = find.text('首页测试书 0');
    expect(card, findsWidgets);

    await tester.tap(find.text('首页测试书 0').first);
    await tester.pump();
    expect(
      opened?.id,
      'txt_home_0',
      reason: 'an entrance animation must never swallow the first tap',
    );
  });

  testWidgets('reduced motion shows the home page whole immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: HomePage(
            books: [book(0)],
            onOpen: (_) {},
            onOpenDetails: (_) {},
            onImport: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('继续阅读'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
