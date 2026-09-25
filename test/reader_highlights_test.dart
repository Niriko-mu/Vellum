import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_chrome.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/reader/reader_selection.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/notes_library.dart';

ImportedBook _book({bool withChapter = false}) => ImportedBook(
  title: '测试书',
  format: BookFormat.txt,
  paragraphs: withChapter ? ['第一章 夜雨', '正文一句。'] : ['一段正文'],
  tocEntries: withChapter
      ? const [BookTocEntry(title: '第一章 夜雨', paragraphIndex: 0)]
      : const [],
);

ReaderParagraph _paragraph(
  ImportedBook book, {
  required String text,
  List<String> highlights = const [],
}) => ReaderParagraph(
  book: book,
  paragraph: text,
  paragraphIndex: 0,
  fontSize: 19,
  fontFamily: 'Georgia',
  lineSpacing: ReaderLineSpacing.standard,
  fontWeight: ReaderFontWeight.regular,
  ink: const Color(0xff111111),
  contextMenuBuilder: createReaderSelectionToolbar(
    bookId: 'book',
    bookTitle: '测试书',
    currentParagraph: () => 0,
  ),
  highlights: highlights,
);

/// All background colours painted anywhere in the rendered paragraph.
List<Color?> _backgrounds(WidgetTester tester) {
  final widget = tester.widget<SelectableText>(find.byType(SelectableText));
  final span = widget.textSpan;
  final colors = <Color?>[];
  span?.visitChildren((child) {
    if (child is TextSpan) colors.add(child.style?.backgroundColor);
    return true;
  });
  return colors;
}

void main() {
  testWidgets('highlights paint only the selected passage', (tester) async {
    final book = _book();
    const text = '他只是站在那里，看着窗外。';

    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderParagraphHost(
          child: _paragraph(book, text: text, highlights: const ['看着窗外']),
        ),
      ),
    );
    final colors = _backgrounds(tester);
    expect(colors.where((color) => color != null), isNotEmpty);
    // The unmatched remainder stays unhighlighted.
    expect(colors.where((color) => color == null), isNotEmpty);
  });

  testWidgets('no highlight is painted without a marked passage', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderParagraphHost(child: _paragraph(_book(), text: '普通段落')),
      ),
    );
    expect(_backgrounds(tester).where((color) => color != null), isEmpty);
  });

  testWidgets('status bar shows page number and battery only', (tester) async {
    const status = ReaderStatusBar(
      pageLabel: '12 / 80',
      batteryLabel: '80%',
      surface: Color(0xffd7d7db),
    );
    await tester.pumpWidget(
      const CupertinoApp(home: CupertinoPageScaffold(child: status)),
    );

    expect(find.text('12 / 80'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    // Chapter / remaining-time no longer clutter the bottom strip.
    expect(find.textContaining('剩余'), findsNothing);
    expect(find.textContaining('本章'), findsNothing);

    // Page number sits hard-left, battery hard-right.
    final pageDx = tester.getTopLeft(find.text('12 / 80')).dx;
    final batteryDx = tester.getTopLeft(find.text('80%')).dx;
    expect(pageDx, lessThan(batteryDx));
    expect(pageDx, lessThan(80));
  });

  testWidgets('reader running head shows the chapter at top left', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(home: ReaderPage(book: _book(withChapter: true))),
    );
    await tester.pump();

    expect(find.textContaining('第一章 夜雨'), findsWidgets);
  });

  test('eye care levels expose their warm-tint strength', () {
    expect(ReaderEyeCare.fromStorage('off'), ReaderEyeCare.off);
    expect(ReaderEyeCare.fromStorage('warm'), ReaderEyeCare.warm);
    expect(ReaderEyeCare.fromStorage('nonsense'), ReaderEyeCare.off);
    expect(ReaderEyeCare.off.opacity, 0);
    expect(ReaderEyeCare.soft.opacity, lessThan(ReaderEyeCare.warm.opacity));
    expect(ReaderEyeCare.warm.opacity, lessThanOrEqualTo(0.25));
  });

  test('reader preferences round-trip the new display settings', () {
    const prefs = ReaderPreferences(
      brightness: 0.42,
      eyeCare: 'warm',
      keepScreenOn: false,
      volumeKeys: true,
    );
    final restored = ReaderPreferences.fromJson(prefs.toJson());
    expect(restored.brightness, 0.42);
    expect(restored.eyeCare, 'warm');
    expect(restored.keepScreenOn, isFalse);
    expect(restored.volumeKeys, isTrue);

    // Older files without the new keys keep the documented defaults.
    final legacy = ReaderPreferences.fromJson(const {'fontSize': 21});
    expect(legacy.brightness, -1);
    expect(legacy.eyeCare, 'off');
    expect(legacy.keepScreenOn, isTrue);
    expect(legacy.volumeKeys, isFalse);
  });

  test('reading state round-trips the new display settings', () {
    const state = ReadingState(
      brightness: 0.7,
      eyeCare: 'soft',
      keepScreenOn: false,
      volumeKeys: true,
      bookmarks: [3],
    );
    final restored = ReadingState.fromJson(state.toJson());
    expect(restored.brightness, 0.7);
    expect(restored.eyeCare, 'soft');
    expect(restored.keepScreenOn, isFalse);
    expect(restored.volumeKeys, isTrue);
    expect(restored.bookmarks, [3]);
  });
  test('notes keep their kind and stay readable from older files', () {
    final highlight = ReadingNote(
      id: 'n_1',
      bookId: 'book',
      bookTitle: '测试书',
      paragraphIndex: 4,
      selectedText: '看着窗外',
      createdAt: DateTime(2026, 1, 2),
      style: ReadingNoteStyle.highlight.name,
    );
    final restored = ReadingNote.fromJson(highlight.toJson());
    expect(restored.kind, ReadingNoteStyle.highlight);
    expect(restored.selectedText, '看着窗外');

    // Files written before highlights existed carry no `style`.
    final legacy = ReadingNote.fromJson(const {
      'id': 'n_2',
      'bookId': 'book',
      'bookTitle': '测试书',
      'paragraphIndex': 1,
      'selectedText': '一句',
    });
    expect(legacy.kind, ReadingNoteStyle.note);
  });
}

/// Minimal themed host so a bare paragraph can be pumped on its own. so a bare paragraph can be pumped on its own.
class ReaderParagraphHost extends StatelessWidget {
  const ReaderParagraphHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(child: SingleChildScrollView(child: child)),
  );
}
