import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_markup.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  group('Latin body detection', () {
    test('English prose is Latin', () {
      expect(
        ReaderMarkup.isLatinBody(
          'It was the best of times, it was the worst of times.',
        ),
        isTrue,
      );
    });

    test('Chinese prose is not Latin', () {
      expect(ReaderMarkup.isLatinBody('他转身走进雨里，再也没有回头。'), isFalse);
    });

    test('mixed paragraphs follow the dominant script', () {
      expect(ReaderMarkup.isLatinBody('Hello world 你好'), isTrue);
      expect(
        ReaderMarkup.isLatinBody('你好世界，这是一段中文正文。hello'),
        isFalse,
      );
    });

    test('indent prefix follows script', () {
      expect(ReaderMarkup.indentPrefixFor('Call me Ishmael.'), '\u2003');
      expect(ReaderMarkup.indentPrefixFor('他转身走进雨里。'), '　　');
      expect(ReaderMarkup.indentPrefixLengthFor('Call me Ishmael.'), 1);
      expect(ReaderMarkup.indentPrefixLengthFor('他转身走进雨里。'), 2);
    });

    test('image markers do not vote Latin', () {
      expect(ReaderMarkup.isLatinBody('你好[[image:1]]'), isFalse);
    });
  });

  testWidgets('English body prose is justified with a 1em indent', (
    tester,
  ) async {
    final book = ImportedBook(
      title: 'Moby Dick',
      format: BookFormat.txt,
      paragraphs: [
        'Call me Ishmael. Some years ago, never mind how long precisely, '
            'having little or no money in my purse, I thought I would sail '
            'about a little and see the watery part of the world.',
      ],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: book,
            paragraph: book.paragraphs[0],
            paragraphIndex: 0,
            fontSize: 24,
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

    final text = tester.widget<Text>(find.byType(Text).first);
    // Justified, block form: no leading indent span (justify would hang it).
    expect(text.textAlign, TextAlign.justify);
    final span = text.textSpan! as TextSpan;
    final first = span.children!.first as TextSpan;
    expect(first.text, isNot('\u2003'));
    expect(first.text, isNot('　　'));
    expect(span.toPlainText().trim().startsWith('Call me Ishmael'), isTrue);
  });

  testWidgets('Chinese body prose keeps start alignment and two-em indent', (
    tester,
  ) async {
    final book = ImportedBook(
      title: '夜雨',
      format: BookFormat.txt,
      paragraphs: ['他转身走进雨里，再也没有回头。'],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: book,
            paragraph: book.paragraphs[0],
            paragraphIndex: 0,
            fontSize: 24,
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

    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.textAlign, TextAlign.start);
    final span = text.textSpan! as TextSpan;
    expect((span.children!.first as TextSpan).text, '　　');
  });
}
