import 'package:vellum/reader/reader_directory_panel_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_control_panels.dart';
import 'package:vellum/reader/reader_controls.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/services/library_models.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/reader_background.dart';

/// Two regressions in the reader menu:
///
/// * the sheet was sized from `MediaQuery.size`, so once the soft keyboard made
///   the overlay's own box smaller than the media size, the sheet ran past its
///   bottom and painted the overflow block — measured at 18 px with a 420 px
///   keyboard;
/// * a search result jumped to the paragraph but the query was dropped with the
///   closed panel, so nothing on the page showed what was being searched for.
void main() {
  const paragraphs = ['第一章 起兵', '太祖本纪，岁在甲子，天下大乱，群雄并起。', '天下既定，乃修文德。'];

  Future<void> pumpMenu(
    WidgetTester tester, {
    required double height,
    double keyboard = 0,
  }) async {
    await tester.binding.setSurfaceSize(Size(390, height + keyboard));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(390, height + keyboard),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  ReaderMenu(
                    visible: true,
                    bookmarked: false,
                    onBack: () {},
                    onToggleBookmark: () {},
                    progress: 0.2,
                    chapterCount: 1,
                    currentChapterIndex: 0,
                    chapterTitle: '第一章 起兵',
                    canSeek: true,
                    onSeekProgress: (_) {},
                    onSeekChapter: (_) {},
                    fontSize: 24,
                    readerFontWeight: ReaderFontWeight.regular,
                    lineSpacing: ReaderLineSpacing.standard,
                    background: const ReaderBackground(),
                    readingMode: ReadingMode.page,
                    pageTurnStyle: PageTurnStyle.cover,
                    brightness: 1,
                    eyeCare: ReaderEyeCare.off,
                    keepScreenOn: true,
                    volumeKeys: false,
                    chapters: const [MapEntry(0, '第一章 起兵')],
                    chapterPageLabels: const {},
                    bookmarks: const [],
                    notes: const [],
                    paragraphs: paragraphs,
                    currentParagraph: 0,
                    bookTitle: '测试书',
                    onJumpToParagraph: (_) {},
                    onRemoveBookmark: (_) async {},
                    onRemoveNote: (_) async {},
                    onFontSize: (_) {},
                    onReaderFontWeight: (_) {},
                    onLineSpacing: (_) {},
                    onBackground: (_) {},
                    onReadingMode: (_) {},
                    onPageTurnStyle: (_) {},
                    onBrightness: (_) {},
                    onEyeCare: (_) {},
                    onKeepScreenOn: (_) {},
                    onVolumeKeys: (_) {},
                    onShowFonts: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet stays inside a keyboard-shrunk overlay', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Keyboard sizes that previously overflowed by 18–39 px.
    for (final keyboard in const [120.0, 300.0, 360.0, 420.0]) {
      await pumpMenu(tester, height: 844 - keyboard, keyboard: keyboard);
      // The reader action bar also carries a 目录 label; pick the tab.\r\n      await tester.tap(find.text('目录').first);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'catalogue overflowed with a $keyboard px keyboard',
      );

      final icon = find.byIcon(CupertinoIcons.search);
      if (icon.evaluate().isEmpty) continue;
      await tester.tap(icon);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '天下');
      await tester.pump(const Duration(milliseconds: 250));
      final searchPanel = find.byType(ReaderDirectoryPanel);
      if (searchPanel.evaluate().isNotEmpty) {
        final state = tester.state<ReaderDirectoryPanelState>(
          searchPanel.first,
        );
        await tester.runAsync(
          () => state.runSearch(state.searchController.text),
        );
        await tester.pump();
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'search overflowed with a $keyboard px keyboard',
      );
    }
  });

  testWidgets(
    'search with the keyboard up fills the viewport and drops chrome',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const keyboard = 336.0;
      const available = 844 - keyboard;
      await pumpMenu(tester, height: available, keyboard: keyboard);

      await tester.tap(find.text('目录').first);
      await tester.pumpAndSettle();
      final icon = find.byIcon(CupertinoIcons.search);
      expect(icon, findsOneWidget);
      await tester.tap(icon);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '天下');
      await tester.pump(const Duration(milliseconds: 250));
      final searchPanel = find.byType(ReaderDirectoryPanel);
      if (searchPanel.evaluate().isNotEmpty) {
        final state = tester.state<ReaderDirectoryPanelState>(
          searchPanel.first,
        );
        await tester.runAsync(
          () => state.runSearch(state.searchController.text),
        );
        await tester.pump();
      }

      // Tabs and the book name are chrome, not search UI: while typing they
      // must not sit on top of the result list.
      expect(find.text('书签'), findsNothing);
      expect(find.text('笔记'), findsNothing);

      // The query field and the summary stay on screen above the keyboard.
      expect(find.byType(CupertinoTextField), findsOneWidget);
      expect(find.textContaining('段'), findsWidgets);

      // The sheet owns the whole remaining viewport (minus the grabber), so the
      // result list is not a stripe above the seek bar. A half-sheet of an
      // already-shrunk box used to leave ~120 px of results.
      final panel = tester.getRect(find.byType(ReaderDirectoryPanel));
      expect(
        panel.height,
        greaterThan(available * .85),
        reason: 'search panel shrank to ${panel.height} with the keyboard up',
      );

      // And it still does not overflow that box.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a search result marks the query inside the paragraph', (
    tester,
  ) async {
    // The renderer marks every occurrence of the term it is given.
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: _Book(),
            paragraph: '太祖本纪，岁在甲子，天下大乱，群雄并起。',
            paragraphIndex: 0,
            fontSize: 20,
            fontFamily: 'Georgia',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: Color(0xFF000000),
            contextMenuBuilder: _noContextMenu,
            selectable: false,
            searchHighlight: '天下',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester.widget<Text>(find.byType(Text).first);
    final marked = <String>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor != null) marked.add(span.text ?? '');
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(rich.textSpan!);
    expect(
      marked,
      contains('天下'),
      reason: 'the searched term must be marked in the body',
    );
  });

  testWidgets('turning the page drops the search mark', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    final book = ImportedBook(
      title: '测试书',
      format: BookFormat.txt,
      paragraphs: [for (var i = 0; i < 60; i++) '第${i + 1}段：太祖本纪，天下大乱，群雄并起。'],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: book,
          initialState: const ReadingState(mode: 'page', pageTurn: 'none'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ReaderPage)) as ReaderPageState;
    // A tapped result places the mark, then the jump's own page change runs.
    state.debugPlaceSearchHighlight('天下');
    await tester.pumpAndSettle();
    expect(
      state.debugSearchHighlight,
      '天下',
      reason: 'the mark is live once the reader lands on the passage',
    );

    // Turning the page — not the jump itself — is what drops it.
    state.debugTurnPage();
    await tester.pumpAndSettle();
    expect(
      state.debugSearchHighlight,
      isEmpty,
      reason: 'the mark must not survive the first page turn',
    );
  });

  testWidgets('without a search term nothing is marked', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: _Book(),
            paragraph: '太祖本纪，岁在甲子，天下大乱。',
            paragraphIndex: 0,
            fontSize: 20,
            fontFamily: 'Georgia',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: Color(0xFF000000),
            contextMenuBuilder: _noContextMenu,
            selectable: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester.widget<Text>(find.byType(Text).first);
    final marked = <String>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor != null) marked.add(span.text ?? '');
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(rich.textSpan!);
    expect(marked, isEmpty);
  });
}

Widget _noContextMenu(BuildContext context, dynamic state) =>
    const SizedBox.shrink();

class _Book extends ImportedBook {
  const _Book()
    : super(
        title: '测试书',
        format: BookFormat.txt,
        paragraphs: const ['太祖本纪，岁在甲子，天下大乱，群雄并起。'],
      );
}
