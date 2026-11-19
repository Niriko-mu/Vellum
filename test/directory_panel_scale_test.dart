import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Brightness, MaterialApp, MediaQuery, MediaQueryData;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_directory_panel.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/services/notes_library.dart';
import 'package:vellum/theme/vellum_theme.dart';

/// The catalogue at book scale. A novel with hundreds of chapters is the
/// normal case, not the stress case: the panel must stay lazy, and it must open
/// where the reader actually is instead of at chapter one.
void main() {
  List<MapEntry<int, String>> chapters(int count) => [
    for (var i = 0; i < count; i++) MapEntry(i * 20, '第${i + 1}章 标题'),
  ];

  Widget host({
    required List<MapEntry<int, String>> entries,
    required int currentParagraph,
  }) {
    return MaterialApp(
      theme: VellumTheme.forBrightness(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Builder(
          builder: (context) => CupertinoPageScaffold(
            backgroundColor: context.c.background,
            child: SizedBox(
              height: 700,
              child: ReaderDirectoryPanel(
                chapters: entries,
                bookmarks: const [],
                notes: const <ReadingNote>[],
                chapterPageLabels: const {},
                currentParagraph: currentParagraph,
                readingMode: ReadingMode.scroll,
                onJumpToParagraph: (_) {},
                onRemoveBookmark: (_) async {},
                onRemoveNote: (_) async {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('600 chapters do not all get built', (tester) async {
    final entries = chapters(600);
    await tester.pumpWidget(host(entries: entries, currentParagraph: 0));
    await tester.pumpAndSettle();

    // A lazy list builds a window, not the whole book. If this ever becomes
    // eager, this count jumps to 600 and the panel janks on open.
    final built = find.textContaining('章 标题').evaluate().length;
    expect(built, lessThan(60));
    expect(built, greaterThan(0));
  });

  testWidgets('the panel opens at the chapter being read', (tester) async {
    // Chapter index 300 of 600: paragraph 6000 sits inside it.
    await tester.pumpWidget(
      host(entries: chapters(600), currentParagraph: 6000),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('第301章 标题'),
      findsOneWidget,
      reason: 'opening the catalogue must land on the current chapter',
    );
    expect(
      find.text('第1章 标题'),
      findsNothing,
      reason: 'and not at the top of the book',
    );
  });

  testWidgets('every chapter row is tall enough to tap', (tester) async {
    expect(ReaderDirectoryPanel.itemExtent, 54);
    await tester.pumpWidget(host(entries: chapters(20), currentParagraph: 0));
    await tester.pumpAndSettle();
    final row = tester.getSize(find.text('第1章 标题'));
    expect(row.height, lessThanOrEqualTo(ReaderDirectoryPanel.itemExtent));
  });
}
