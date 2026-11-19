import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Brightness, MaterialApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/vellum.dart';

/// Defaults decide what a new reader sees first.
///
/// The product wants a book to open like a book: reflowed text, turned by the
/// page, not an endless vertical strip. These assertions pin that, and pin the
/// one case that deliberately still opens scrolled.
void main() {
  test('a fresh reading state asks for page mode', () {
    expect(const ReadingState().mode, 'page');
    expect(const ReaderPreferences().mode, 'page');
  });

  testWidgets('a new reader opens page mode, not a scroll list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: ReaderPage(
          book: ImportedBook(
            title: '默认分页',
            format: BookFormat.txt,
            paragraphs: List.generate(40, (i) => '第 $i 段正文，' * 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(PageView),
      findsOneWidget,
      reason: 'the default reading surface is a page, not a scroll view',
    );
  });
}
