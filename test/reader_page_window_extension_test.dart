import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/library_models.dart';

void main() {
  testWidgets('anchored deep pages do not render the book title as home', (
    tester,
  ) async {
    final book = ImportedBook(
      title: '深跳标题回归',
      format: BookFormat.txt,
      paragraphs: [
        for (var i = 0; i < 9000; i++)
          i == 5000
              ? '[[b]]人物[[/b]]'
              : '第${i + 1}段正文内容。${List.filled(6, '用于分页的文字。').join()}',
      ],
      tocEntries: const [BookTocEntry(title: '人物', paragraphIndex: 5000)],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: book,
          initialState: const ReadingState(mode: 'page', paragraphIndex: 5000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
    expect(state.pager.isAnchored, isTrue);
    expect(find.text('深跳标题回归'), findsNothing);
    state.debugTurnPage();
    await tester.pumpAndSettle();
    expect(state.currentPage, greaterThan(0));
  });

  testWidgets(
    'cover turns extend an anchored pagination window before it is exhausted',
    (tester) async {
      final book = ImportedBook(
        title: '长篇分页回归',
        format: BookFormat.txt,
        paragraphs: [
          for (var i = 0; i < 10000; i++)
            '第${i + 1}段内容。${List.filled(7, '这一段用于产生稳定的分页高度。').join()}',
        ],
      );
      await tester.pumpWidget(
        CupertinoApp(
          home: ReaderPage(
            book: book,
            initialState: const ReadingState(mode: 'page'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
      final initialPages = state.debugPageCount;
      expect(initialPages, greaterThanOrEqualTo(40));
      expect(state.pager.fullyPaginated, isFalse);

      // Place the reader just inside the prefetch tail, then commit a cover
      // turn. The old implementation stopped here because PageView's
      // onPageChanged is suppressed while coverJumping is true.
      final beforeTurn = initialPages;
      final nearTail = beforeTurn - 4;
      state.currentPage = nearTail;
      state.requestedPage = nearTail;
      state.coverJumping = true;
      state.finishCoverTurn(nearTail + 1);
      await tester.pumpAndSettle();

      expect(
        state.debugPageCount,
        greaterThan(beforeTurn),
        reason: 'the next window slice must be scheduled after a cover turn',
      );
    },
  );

  testWidgets(
    'a directory-style deep jump clamps the old page before forward turns',
    (tester) async {
      final book = ImportedBook(
        title: '目录深跳前进回归',
        format: BookFormat.txt,
        paragraphs: [
          for (var i = 0; i < 9000; i++)
            i == 8500
                ? '[[b]]生活[[/b]]'
                : '第${i + 1}段正文。${List.filled(8, '用于分页的文字。').join()}',
        ],
        tocEntries: const [BookTocEntry(title: '生活', paragraphIndex: 8500)],
      );
      await tester.pumpWidget(
        CupertinoApp(
          home: ReaderPage(
            book: book,
            initialState: const ReadingState(mode: 'page'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
      expect(state.debugPageCount, greaterThan(20));
      state.currentPage = 20;
      state.requestedPage = 20;
      state.jumpToPageExact(20);

      // This is the same callback path used by a directory chapter row. The
      // old implementation kept currentPage=20 while the anchored window had
      // only 12 pages, so the next-page gesture targeted an invalid item.
      state.jumpToParagraph(8500);
      expect(state.currentPage, 0);
      expect(state.requestedPage, 0);
      expect(state.pageProgress, contains('/'));
      expect(state.pageProgress, isNot(contains('--')));

      await tester.pumpAndSettle();
      state.debugTurnPage();
      await tester.pumpAndSettle();
      expect(state.currentPage, greaterThan(0));
    },
  );

  testWidgets('a deep chapter home can turn backwards and return forwards', (
    tester,
  ) async {
    const chapterParagraph = 8500;
    final book = ImportedBook(
      title: '章节首页前翻回归',
      format: BookFormat.txt,
      paragraphs: [
        for (var i = 0; i < 9000; i++)
          i == chapterParagraph
              ? '[[b]]新章节[[/b]]'
              : '第${i + 1}段内容。${List.filled(8, '用于分页的文字。').join()}',
      ],
      tocEntries: const [
        BookTocEntry(title: '新章节', paragraphIndex: chapterParagraph),
      ],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: book,
          initialState: const ReadingState(mode: 'page'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
    state.jumpToParagraph(chapterParagraph);
    await tester.pumpAndSettle();
    expect(state.currentPage, 0);
    expect(state.pager.firstParagraphOfPage(0), chapterParagraph);

    state.changePage(state.context, -1);
    await tester.pumpAndSettle();
    final previousParagraph = state.pager.firstParagraphOfPage(
      state.currentPage,
    );
    expect(previousParagraph, isNotNull);
    expect(previousParagraph!, lessThan(chapterParagraph));

    state.changePage(state.context, 1);
    await tester.pumpAndSettle();
    expect(
      state.pager.firstParagraphOfPage(state.currentPage),
      chapterParagraph,
    );
  });

  testWidgets(
    'a rightward drag from a deep chapter home uses the predecessor window',
    (tester) async {
      const chapterParagraph = 8500;
      final book = ImportedBook(
        title: '章节首页拖拽回归',
        format: BookFormat.txt,
        paragraphs: [
          for (var i = 0; i < 9000; i++)
            i == chapterParagraph
                ? '[[b]]新章节[[/b]]'
                : '第${i + 1}段内容。${List.filled(8, '用于分页的文字。').join()}',
        ],
        tocEntries: const [
          BookTocEntry(title: '新章节', paragraphIndex: chapterParagraph),
        ],
      );
      await tester.pumpWidget(
        CupertinoApp(
          home: ReaderPage(
            book: book,
            initialState: const ReadingState(mode: 'page'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
      state.jumpToParagraph(chapterParagraph);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(320, 0));
      await tester.pumpAndSettle();
      final previousParagraph = state.pager.firstParagraphOfPage(
        state.currentPage,
      );
      expect(previousParagraph, isNotNull);
      expect(previousParagraph!, lessThan(chapterParagraph));
    },
  );

  testWidgets(
    'non-cover page styles can turn backwards from an anchored home',
    (tester) async {
      const chapterParagraph = 8500;
      final book = ImportedBook(
        title: '章节首页动画回归',
        format: BookFormat.txt,
        paragraphs: [
          for (var i = 0; i < 9000; i++)
            i == chapterParagraph
                ? '[[b]]新章节[[/b]]'
                : '第${i + 1}段内容。${List.filled(8, '用于分页的文字。').join()}',
        ],
        tocEntries: const [
          BookTocEntry(title: '新章节', paragraphIndex: chapterParagraph),
        ],
      );

      for (final style in ['none', 'slide']) {
        await tester.pumpWidget(
          CupertinoApp(
            home: ReaderPage(
              key: ValueKey(style),
              book: book,
              initialState: ReadingState(mode: 'page', pageTurn: style),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
        state.jumpToParagraph(chapterParagraph);
        await tester.pumpAndSettle();
        state.changePage(state.context, -1);
        await tester.pumpAndSettle();
        expect(
          state.pager.firstParagraphOfPage(state.currentPage),
          lessThan(chapterParagraph),
          reason: '$style style must expose a predecessor page',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}
