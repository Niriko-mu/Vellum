import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  testWidgets('custom ink colour paints the body text', (tester) async {
    final book = ImportedBook(
      title: '墨色',
      format: BookFormat.txt,
      paragraphs: ['这是一段正文。'],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: book,
            paragraph: book.paragraphs.first,
            paragraphIndex: 0,
            fontSize: 24,
            fontFamily: 'Roboto',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: const Color(0xff3355ff),
            contextMenuBuilder: (context, state) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    final rich = tester.widget<SelectableText>(find.byType(SelectableText));
    final span = rich.textSpan!;
    expect(span.style?.color, const Color(0xff3355ff));
  });
}
