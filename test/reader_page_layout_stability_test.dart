import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_markup.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/reader/reader_page_overlay.dart';
import 'package:vellum/reader/reader_page_surface.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/library_models.dart';

void main() {
  testWidgets('cover destination has the same layout after landing', (
    tester,
  ) async {
    final book = ImportedBook(
      title: '翻页布局',
      format: BookFormat.txt,
      paragraphs: [
        for (var i = 0; i < 30; i++) '$i ${'正文排版稳定，mixed text。' * 10}',
      ],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: book,
          initialState: const ReadingState(mode: 'page', pageTurn: 'cover'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<ReaderPageState>(find.byType(ReaderPage));
    for (var turn = 0; turn < 3; turn++) {
      state.startCoverTurn(turn, turn + 1);
      await tester.pump();
      final overlay = find.byType(ReaderCoverTurnOverlay);
      final destination = find.descendant(
        of: overlay,
        matching: find.byType(ReaderParagraph),
      );
      final snapshot = <String, Rect>{};
      // The static destination is built before the moving source page.
      for (final element in destination.evaluate()) {
        final paragraph = element.widget as ReaderParagraph;
        snapshot.putIfAbsent(
          paragraph.paragraph,
          () => tester.getRect(find.byWidget(paragraph)),
        );
      }
      final targetText = state.pages[turn + 1]
          .map((fragment) => fragment.text)
          .toSet();
      final expected = {for (final text in targetText) text: snapshot[text]!};
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCoverTurnOverlay), findsNothing);
      for (final element in find.byType(ReaderParagraph).evaluate()) {
        final paragraph = element.widget as ReaderParagraph;
        if (!expected.containsKey(paragraph.paragraph)) continue;
        expect(
          tester.getRect(find.byWidget(paragraph)),
          expected[paragraph.paragraph],
        );
        expected.remove(paragraph.paragraph);
      }
      expect(
        expected,
        isEmpty,
        reason: 'every destination fragment must survive landing',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final scale in [1.0, 1.5]) {
    testWidgets('page text stays inside viewport at scale $scale', (
      tester,
    ) async {
      final book = ImportedBook(
        title: '阅读排版',
        format: BookFormat.txt,
        paragraphs: [
          for (var i = 0; i < 12; i++)
            '${i.isEven ? '' : '[[vellum-quote]]'}'
                '${'这是一段用于检查最后一行完整显示的正文，包含中英文 mixed text。' * 5}',
          'English text must keep the same line breaks and every character. ' *
              30,
          '[[vellum-heading:3]]${'跨页标题' * 25}',
        ],
      );
      final config = PageLayoutConfig(
        fontSize: 24,
        lineSpacing: ReaderLineSpacing.standard,
        fontFamily: 'Roboto',
        fontWeight: ReaderFontWeight.regular,
        availableHeight: 460,
        contentWidth: 320,
        screenHeight: 600,
        title: book.title,
        textScaler: TextScaler.linear(scale),
      );
      final pages = computeBookPages(book, config);
      for (var index = 0; index < book.paragraphs.length; index++) {
        expect(
          pages
              .expand((page) => page)
              .where((fragment) => fragment.paragraphIndex == index)
              .map((fragment) => fragment.text)
              .join(),
          ReaderMarkup.stripAllMarkers(book.paragraphs[index]),
          reason: 'pagination must preserve every source character',
        );
      }
      final scroll = ScrollController();
      final controller = PageController();
      addTearDown(scroll.dispose);
      addTearDown(controller.dispose);
      final surface = ReaderPageSurface(
        book: book,
        readingMode: ReadingMode.page,
        scrollController: scroll,
        pageController: controller,
        pageCount: pages.length,
        pages: pages,
        currentPage: 0,
        showBookTitle: true,
        sideInset: 0,
        topInset: 0,
        bottomInset: 0,
        fontSize: 24,
        fontFamily: 'Roboto',
        lineSpacing: ReaderLineSpacing.standard,
        fontWeight: ReaderFontWeight.regular,
        ink: CupertinoColors.black,
        tocParagraphs: const {},
        paragraphKeys: {},
        highlights: const {},
        spokenSentence: '',
        searchHighlight: '',
        noteCountFor: (_) => 0,
        contextMenuBuilder: (_) =>
            (_, _) => const SizedBox.shrink(),
        onOpenNotes: (_) {},
        onJumpToParagraph: (_) {},
        onBookmarkPull: (_) => false,
        onRestorePage: () {},
        onPageChanged: (_) {},
      );
      for (var page = 0; page < pages.length; page++) {
        await tester.pumpWidget(
          CupertinoApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 460,
                  key: const ValueKey('viewport'),
                  child: Builder(
                    builder: (context) => surface.buildPage(context, page),
                  ),
                ),
              ),
            ),
          ),
        );
        final viewport = tester.getRect(find.byKey(const ValueKey('viewport')));
        for (final element in find.byType(SelectableText).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(
            rect.bottom,
            lessThanOrEqualTo(viewport.bottom + .01),
            reason: 'page $page clips its final text line',
          );
        }
        expect(find.byType(ReaderParagraph), findsWidgets);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
