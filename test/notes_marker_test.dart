import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/notes_library.dart';

void main() {
  group('ReadingNote model', () {
    test('update payload keeps identity fields', () {
      final note = ReadingNote(
        id: 'n1',
        bookId: 'b1',
        bookTitle: 'T',
        paragraphIndex: 2,
        selectedText: '选中',
        note: '旧',
        createdAt: DateTime(2026),
      );
      final updated = ReadingNote(
        id: note.id,
        bookId: note.bookId,
        bookTitle: note.bookTitle,
        paragraphIndex: note.paragraphIndex,
        selectedText: note.selectedText,
        note: '新',
        createdAt: note.createdAt,
        style: note.style,
      );
      expect(updated.id, 'n1');
      expect(updated.note, '新');
      expect(updated.paragraphIndex, 2);
    });
  });

  testWidgets('paragraph with notes shows a tapable comment marker', (
    tester,
  ) async {
    var opened = 0;
    final book = ImportedBook(
      title: '笔记书',
      format: BookFormat.txt,
      paragraphs: ['这一段有笔记。'],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: book,
            paragraph: book.paragraphs[0],
            paragraphIndex: 0,
            fontSize: 18,
            fontFamily: 'Roboto',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: const Color(0xff000000),
            contextMenuBuilder: (context, state) => const SizedBox.shrink(),
            selectable: false,
            noteCount: 2,
            onOpenNotes: () => opened++,
          ),
        ),
      ),
    );

    expect(find.byIcon(CupertinoIcons.chat_bubble_text), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chat_bubble_text));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('paragraph without notes has no marker', (tester) async {
    final book = ImportedBook(
      title: '无笔记',
      format: BookFormat.txt,
      paragraphs: ['这一段没有笔记。'],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: book,
            paragraph: book.paragraphs[0],
            paragraphIndex: 0,
            fontSize: 18,
            fontFamily: 'Roboto',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: const Color(0xff000000),
            contextMenuBuilder: (context, state) => const SizedBox.shrink(),
            selectable: false,
          ),
        ),
      ),
    );
    expect(find.byIcon(CupertinoIcons.chat_bubble_text), findsNothing);
  });
}
