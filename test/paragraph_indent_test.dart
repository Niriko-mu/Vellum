import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_markup.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/services/book_models.dart';
import 'package:vellum/theme/vellum_theme.dart';

ImportedBook _bookWith(
  List<String> paragraphs, {
  List<BookTocEntry> toc = const [],
}) {
  return ImportedBook(
    id: 'indent-book',
    title: '缩进书',
    format: BookFormat.txt,
    paragraphs: paragraphs,
    tocEntries: toc,
  );
}

Widget _wrap(
  ImportedBook book,
  String paragraph,
  int index, {
  bool heading = false,
}) {
  return CupertinoApp(
    home: CupertinoPageScaffold(
      backgroundColor: VellumTheme.readerWhite,
      child: ReaderParagraph(
        book: book,
        paragraph: paragraph,
        paragraphIndex: index,
        fontSize: 18,
        fontFamily: '.AppleSystemUIFont',
        lineSpacing: ReaderLineSpacing.standard,
        fontWeight: ReaderFontWeight.regular,
        ink: VellumTheme.readerInkFor(VellumTheme.readerWhite),
        contextMenuBuilder: (BuildContext context, EditableTextState state) =>
            const SizedBox.shrink(),
        selectable: false,
        isChapterHeading: heading,
      ),
    ),
  );
}

String _plainOfFirstText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text).first);
  final span = text.textSpan;
  if (span is TextSpan) return span.toPlainText();
  return text.data ?? '';
}

List<InlineSpan> _childrenOfFirstText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text).first);
  final span = text.textSpan;
  if (span is TextSpan && span.children != null) {
    return span.children!;
  }
  if (span != null) return [span];
  return [TextSpan(text: text.data ?? '')];
}

void main() {
  group('ReaderMarkup indent rules', () {
    test('body prose gets indent; chapter titles do not', () {
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: '他转身走进雨里，再也没有回头。',
          fullParagraph: '他转身走进雨里，再也没有回头。',
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isTrue,
      );
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: '第十二章 夜雨',
          fullParagraph: '第十二章 夜雨',
          headingLevel: 2,
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isFalse,
      );
    });

    test('synthetic TOC landing on body prose still indents', () {
      const body = '那天夜里雨下得很大，街上几乎没有行人。';
      expect(
        ReaderMarkup.effectiveHeadingLevel(
          paragraph: body,
          fullParagraph: body,
          isTocEntry: true,
        ),
        isNull,
      );
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: body,
          fullParagraph: body,
          headingLevel: ReaderMarkup.effectiveHeadingLevel(
            paragraph: body,
            fullParagraph: body,
            isTocEntry: true,
          ),
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isTrue,
      );
    });

    test('short dialogue and English body still indent by default', () {
      // Chinese one-word reply — not a chapter head → indent.
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: '好',
          fullParagraph: '好',
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isTrue,
      );
      // English line ending with '.' — old rule missed this.
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: 'He walked home.',
          fullParagraph: 'He walked home.',
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isTrue,
      );
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: 'Chapter 3',
          fullParagraph: 'Chapter 3',
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isFalse,
      );
    });

    test('whole-book center layout still indents body prose', () {
      const body = '他望着窗外的江面，心里空落落的，一句话也说不出来。';
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: '[[vellum-center]]$body',
          fullParagraph: '[[vellum-center]]$body',
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: true,
        ),
        isTrue,
      );
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: '[[vellum-center]]封面',
          fullParagraph: '[[vellum-center]]封面',
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: true,
        ),
        isFalse,
      );
    });

    test('source that already carries indent is not double-prefixed', () {
      const body = '　　他点了点头，没有多说。';
      expect(ReaderMarkup.alreadyHasFirstLineIndent(body), isTrue);
      expect(
        ReaderMarkup.shouldIndentFirstLine(
          paragraph: body,
          fullParagraph: body,
          headingLevel: null,
          isQuote: false,
          isList: false,
          isCenter: false,
        ),
        isFalse,
      );
    });
  });

  testWidgets('ReaderParagraph paints two full-width spaces on body text', (
    tester,
  ) async {
    final book = _bookWith(['他转身走进雨里，再也没有回头。']);
    await tester.pumpWidget(_wrap(book, book.paragraphs[0], 0));
    await tester.pumpAndSettle();

    final children = _childrenOfFirstText(tester);
    expect(children.first.toPlainText(), '　　');
  });

  testWidgets(
    'body paragraphs use full-width justification while preserving indent',
    (tester) async {
      // A wrapping paragraph is the failing case: `TextAlign.justify` hangs the
      // leading `　　` of every non-last line, deleting the two-em first-line
      // indent for any paragraph long enough to wrap.
      final long = '他转身走进雨里，再也没有回头。' * 8;
      final book = _bookWith([long]);
      await tester.pumpWidget(_wrap(book, book.paragraphs[0], 0));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.byType(Text).first);
      expect(
        text.textAlign,
        TextAlign.justify,
        reason:
            'TextAlign.justify hangs leading whitespace and removes the '
            'two-em first-line indent on wrapped lines; body text must use '
            'full-width justification.',
      );
      final children = _childrenOfFirstText(tester);
      expect(children.first.toPlainText(), '　　');
    },
  );

  testWidgets('chapter title paragraphs stay flush without indent', (
    tester,
  ) async {
    const title = '[[vellum-heading:1]]第一章 夜雨';
    final book = _bookWith(
      [title, '他转身走进雨里，再也没有回头。'],
      toc: [BookTocEntry(title: '第一章 夜雨', paragraphIndex: 0)],
    );
    await tester.pumpWidget(_wrap(book, title, 0, heading: true));
    await tester.pumpAndSettle();

    final plain = _plainOfFirstText(tester);
    expect(plain.startsWith('　　'), isFalse);
    expect(plain.contains('第一章'), isTrue);
  });
}
