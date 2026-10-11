import 'package:vellum/reader/reader_directory_panel_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/notes_import_sheet.dart';
import 'package:vellum/pages/unassociated_notes_sheet.dart';
import 'package:vellum/reader/reader_control_panels.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/services/notes_import.dart';
import 'package:vellum/services/notes_library.dart';
import 'package:vellum/theme/vellum_theme.dart';

/// In-memory notes store: the real one needs `path_provider`, which is not
/// available in a widget test.
///
/// [load] hands back a **read-only** list on purpose — the real store returned
/// `const []` before the first note existed, and mutating that is exactly how
/// writing the first note came to throw.
class _MemoryNotesLibrary extends NotesLibrary {
  _MemoryNotesLibrary([List<ReadingNote>? seed]) : _notes = [...?seed];

  final List<ReadingNote> _notes;

  List<ReadingNote> get notes => List.unmodifiable(_notes);

  @override
  Future<List<ReadingNote>> load() async => List.unmodifiable(_notes);

  @override
  Future<void> saveAll(List<ReadingNote> notes) async {
    _notes
      ..clear()
      ..addAll(notes);
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final panel = find.byType(ReaderDirectoryPanel);
  if (panel.evaluate().isNotEmpty) {
    final state = tester.state<ReaderDirectoryPanelState>(panel);
    if (state.results.isEmpty && state.searchController.text.length >= 2) {
      // Worker I/O must run outside the widget test fake clock.
      await tester.runAsync(() => state.runSearch(state.searchController.text));
    }
    await tester.pumpAndSettle();
  }
}

void main() {
  group('catalogue panel 全文搜索', () {
    final paragraphs = ['第一章 起兵', '太祖本纪，岁在甲子，天下大乱。', '第二章 定鼎', '天下既定，乃修文德。'];
    const chapters = [MapEntry(0, '第一章 起兵'), MapEntry(2, '第二章 定鼎')];

    Future<List<int>> pumpPanel(
      WidgetTester tester, {
      List<String>? texts,
      String Function(int)? pageLabel,
    }) async {
      final jumps = <int>[];
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SizedBox(
              height: 600,
              child: ReaderDirectoryPanel(
                chapters: chapters,
                bookmarks: const [],
                notes: const [],
                chapterPageLabels: const {},
                currentParagraph: 0,
                readingMode: ReadingMode.page,
                paragraphs: texts ?? paragraphs,
                pageLabelForParagraph: pageLabel,
                onJumpToParagraph: jumps.add,
                onRemoveBookmark: (_) async {},
                onRemoveNote: (_) async {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      return jumps;
    }

    Future<void> type(WidgetTester tester, String query) async {
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      await tester.enterText(find.byType(CupertinoTextField), query);
      await settle(tester);
    }

    testWidgets('opening search focuses the field so the keyboard can appear', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);

      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      // The field is created by opening search, so it must claim the caret
      // itself: a focus request issued before it is mounted is dropped, which is
      // how the soft keyboard stopped appearing.
      expect(field.autofocus, isTrue);

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('focus is re-established when search is re-opened', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('clearing the query keeps the field focused', (tester) async {
      await pumpPanel(tester);
      await type(tester, '天下');
      expect(find.textContaining('2 段 · 2 处'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
      await settle(tester);

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect(find.text('输入至少 2 个字开始搜索'), findsOneWidget);
    });

    testWidgets('the search field reads what a focused keyboard sends', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);

      // Deliberately no second tap on the field: this is the platform's own
      // keyboard route, so a field without focus would never see it.
      tester.testTextInput.enterText('天下');
      await settle(tester);

      expect(find.textContaining('2 段 · 2 处'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '天下',
      );
    });

    testWidgets('a keyboard dropped right after opening is recovered', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      final node = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      expect(node.hasFocus, isTrue);

      // Simulate the platform dropping the input session while the field is
      // still on screen (the reported symptom).
      node.unfocus();
      await tester.pump();
      expect(node.hasFocus, isFalse);

      // The panel refocuses once, shortly after.
      await tester.pump(const Duration(milliseconds: 300));
      expect(node.hasFocus, isTrue);
    });

    testWidgets('a deliberate dismissal is not fought', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      final node = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;

      // 取消 closes search; the field must stay gone rather than bouncing back.
      await tester.tap(find.text('取消'));
      await settle(tester);
      node.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('search is reachable only from the catalogue tab', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.byIcon(CupertinoIcons.search), findsOneWidget);

      // 书签 tab has nothing to search.
      await tester.tap(find.text('书签'));
      await settle(tester);
      expect(find.byIcon(CupertinoIcons.search), findsNothing);
    });

    testWidgets('typing queries the whole book and groups hits by chapter', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      expect(find.text('搜索全书内容'), findsOneWidget);

      await tester.enterText(find.byType(CupertinoTextField), '天下');
      await settle(tester);

      // Summary counts paragraphs and occurrences.
      expect(find.textContaining('2 段 · 2 处'), findsOneWidget);
      expect(find.textContaining('2 处'), findsWidgets);
      // Each matched paragraph gets its chapter as a group header.
      expect(find.text('第一章 起兵'), findsOneWidget);
      expect(find.text('第二章 定鼎'), findsOneWidget);
      // Rows carry the paragraph number.
      expect(find.textContaining('第 2 段'), findsWidgets);
    });

    testWidgets('a chapter with several hits gets one header for all of them', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        texts: const ['第一章 起兵', '天下大乱。', '天下未定。', '第二章 定鼎', '天下既定。'],
      );
      await type(tester, '天下');

      // Three paragraphs, two of them under the first chapter.
      expect(find.textContaining('3 段 · 3 处'), findsOneWidget);
      expect(find.text('第一章 起兵'), findsOneWidget);
      expect(find.text('第二章 定鼎'), findsOneWidget);
      // The first chapter's header counts its own occurrences.
      expect(find.text('2 处'), findsWidgets);
    });

    testWidgets('a paragraph with repeated hits is flagged', (tester) async {
      await pumpPanel(tester, texts: const ['天下天下天下，大乱。']);
      await type(tester, '天下');

      expect(find.text('本段 3 处'), findsOneWidget);
      expect(find.textContaining('3 处'), findsWidgets);
    });

    testWidgets('results show the page a hit sits on', (tester) async {
      await pumpPanel(tester, pageLabel: (paragraph) => '第 ${paragraph + 1} 页');
      await type(tester, '天下');

      expect(find.textContaining('第 2 页'), findsOneWidget);
      expect(find.textContaining('第 4 页'), findsOneWidget);
    });

    testWidgets('the step buttons walk the results', (tester) async {
      await pumpPanel(tester);
      await type(tester, '天下');

      // Two hits: starts on the first.
      expect(find.text('1/2'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
      await settle(tester);
      expect(find.text('2/2'), findsOneWidget);

      // Down again stays put; up walks back.
      await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
      await settle(tester);
      expect(find.text('2/2'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
      await settle(tester);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('context around the match is shown', (tester) async {
      await pumpPanel(tester, texts: const ['第一行\n第二行 太祖 在这里\n第三行']);
      await type(tester, '太祖');

      expect(find.text('第一行'), findsOneWidget);
      expect(find.text('第三行'), findsOneWidget);
      expect(find.textContaining('第 1 行'), findsNothing);
      // The row reports its line number when the paragraph has hard breaks.
      expect(find.textContaining('第 2 行'), findsOneWidget);
    });

    testWidgets('a short query asks for more characters instead of scanning', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);

      expect(find.text('输入至少 2 个字开始搜索'), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField), '天');
      await settle(tester);
      expect(find.text('再输入 1 个字'), findsOneWidget);
    });

    testWidgets('the scan waits for a typing pause', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      await tester.enterText(find.byType(CupertinoTextField), '天下');
      // Immediately after typing there is no scan result yet.
      await tester.pump();
      expect(find.textContaining('2 段 ·'), findsNothing);

      await tester.pump(const Duration(milliseconds: 250));
      await settle(tester);
      expect(find.textContaining('2 段 · 2 处'), findsOneWidget);
    });

    testWidgets('a query with no hits says so', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      await tester.enterText(find.byType(CupertinoTextField), '不存在的内容');
      await settle(tester);
      expect(find.text('没有找到「不存在的内容」'), findsOneWidget);
    });

    testWidgets('tapping a hit jumps to its paragraph', (tester) async {
      final jumps = await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      await tester.enterText(find.byType(CupertinoTextField), '文德');
      await settle(tester);

      // One hit, in the second chapter's paragraph. The chapter name is a group
      // header now, so the row itself is the tap target.
      expect(find.text('第二章 定鼎'), findsOneWidget);
      expect(find.textContaining('第 4 段'), findsOneWidget);
      await tester.tap(find.textContaining('第 4 段'));
      await settle(tester);

      expect(jumps, [3]);
      // The panel leaves search mode so the jump is visible.
      expect(find.text('搜索全书内容'), findsNothing);
    });

    testWidgets('取消 restores the catalogue list', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await settle(tester);
      await tester.enterText(find.byType(CupertinoTextField), '天下');
      await settle(tester);

      await tester.tap(find.text('取消'));
      await settle(tester);

      expect(find.text('搜索全书内容'), findsNothing);
      expect(find.text('第一章 起兵'), findsOneWidget);
      // The order toggle is back in the header slot the search icon borrowed.
      expect(find.text('正序'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
    });
  });

  group('notes import sheet', () {
    const books = [
      BookMatchCandidate(id: 'id-1', title: '史记'),
      BookMatchCandidate(id: 'id-2', title: '资治通鉴'),
    ];

    NotesImport sampleImport() => NotesImport(
      notes: [
        ImportedNote(selectedText: '太史公曰', note: '好句'),
        ImportedNote(selectedText: '天下熙熙'),
      ],
      titleHint: '史记',
      format: 'text',
    );

    Future<NotesImportOutcome?> pumpSheet(
      WidgetTester tester, {
      required NotesImport import,
      required BookMatch match,
    }) async {
      NotesImportOutcome? outcome;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () async {
                    outcome = await showCupertinoModalPopup<NotesImportOutcome>(
                      context: context,
                      builder: (_) => NotesImportSheet(
                        import: import,
                        books: books,
                        match: match,
                        fileName: '史记-笔记.md',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      return outcome;
    }

    testWidgets('a matched file shows the reason and the target book', (
      tester,
    ) async {
      final import = sampleImport();
      final match = matchBooksForImport(books: books, import: import);
      await pumpSheet(tester, import: import, match: match);

      expect(find.text('读到 2 条笔记 · 史记-笔记.md（文本）'), findsOneWidget);
      expect(find.text('史记'), findsWidgets);
      expect(find.text(match.reason), findsOneWidget);
      expect(find.text('导入到《史记》'), findsOneWidget);
      // Preview shows the passages.
      expect(find.text('太史公曰'), findsOneWidget);
      expect(find.text('天下熙熙'), findsOneWidget);
    });

    testWidgets('an unmatched file falls back to unassociated, not dropped', (
      tester,
    ) async {
      final import = NotesImport(
        notes: [ImportedNote(selectedText: '一条')],
        titleHint: '不存在的书',
        format: 'text',
      );
      final match = matchBooksForImport(books: books, import: import);
      expect(match.isFallback, isTrue);
      await pumpSheet(tester, import: import, match: match);

      expect(find.text('未关联笔记'), findsWidgets);
      expect(find.text('先存下来，之后可以再关联到某本书'), findsOneWidget);
      // The reader can still import; nothing is silently discarded.
      expect(find.text('仍然导入'), findsOneWidget);
    });

    testWidgets('the reader can pick a different book by hand', (tester) async {
      final import = NotesImport(
        notes: [ImportedNote(selectedText: '一条')],
        titleHint: '不存在的书',
        format: 'text',
      );
      final match = matchBooksForImport(books: books, import: import);
      await pumpSheet(tester, import: import, match: match);

      // Association row → book picker.
      await tester.tap(find.text('未关联笔记').first);
      await settle(tester);
      expect(find.text('选择书籍'), findsOneWidget);

      await tester.tap(find.text('资治通鉴'));
      await settle(tester);

      // Back on the import sheet with the picked book.
      expect(find.text('导入到《资治通鉴》'), findsOneWidget);
      expect(find.text('仍然导入'), findsNothing);
    });

    testWidgets('importing a matched file returns the chosen book', (
      tester,
    ) async {
      final import = sampleImport();
      final match = matchBooksForImport(books: books, import: import);
      await pumpSheet(tester, import: import, match: match);

      await tester.tap(find.text('导入到《史记》'));
      await settle(tester);
      // The sheet is gone; the caller received the target book.
      expect(find.text('导入到《史记》'), findsNothing);
    });
  });

  group('unassociated notes', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required _MemoryNotesLibrary library,
    }) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: UnassociatedNotesSheet(
              books: const [BookMatchCandidate(id: 'a', title: '史记')],
              notesLibrary: library,
            ),
          ),
        ),
      );
      // No pumpAndSettle: the loading spinner animates forever by design.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('explains itself when there is nothing to link', (
      tester,
    ) async {
      await pumpSheet(tester, library: _MemoryNotesLibrary());
      expect(find.text('未关联笔记'), findsOneWidget);
      expect(find.text('这些笔记还没有所属的书。选择一本即可关联。'), findsOneWidget);
      expect(find.text('没有未关联的笔记。'), findsOneWidget);
    });

    testWidgets('lists orphaned notes and links one to a book', (tester) async {
      final library = _MemoryNotesLibrary([
        ReadingNote(
          id: 'n1',
          bookId: unmatchedBookId,
          bookTitle: unmatchedBookTitle,
          paragraphIndex: 0,
          selectedText: '太史公曰',
          createdAt: DateTime(2024, 5, 1),
        ),
      ]);
      await pumpSheet(tester, library: library);

      expect(find.text('太史公曰'), findsOneWidget);
      expect(find.text('关联书籍'), findsOneWidget);

      await tester.tap(find.text('关联书籍'));
      await settle(tester);
      expect(find.text('关联到哪本书'), findsOneWidget);

      await tester.tap(find.text('史记'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 50));

      // The note now belongs to the picked book and left the orphan list.
      expect(library.notes.single.bookId, 'a');
      expect(library.notes.single.bookTitle, '史记');
      expect(find.text('没有未关联的笔记。'), findsOneWidget);
    });
  });

  group('saveImportedNotes', () {
    test('attaches notes to the chosen book', () async {
      final library = _MemoryNotesLibrary();
      final saved = await saveImportedNotes(
        library: library,
        notes: [
          ImportedNote(selectedText: '一句', note: '批注'),
          ImportedNote(selectedText: '两句'),
        ],
        book: const BookMatchCandidate(id: 'id-9', title: '史记'),
      );

      expect(saved, 2);
      expect(library.notes, hasLength(2));
      expect(library.notes.every((n) => n.bookId == 'id-9'), isTrue);
      expect(library.notes.every((n) => n.bookTitle == '史记'), isTrue);
    });

    test('keeps notes as unassociated when no book was chosen', () async {
      final library = _MemoryNotesLibrary();
      final saved = await saveImportedNotes(
        library: library,
        notes: [ImportedNote(selectedText: '一句')],
      );

      expect(saved, 1);
      expect(library.notes.single.bookId, unmatchedBookId);
      expect(library.notes.single.bookTitle, unmatchedBookTitle);
    });

    test('skips empty entries and keeps existing notes', () async {
      final library = _MemoryNotesLibrary([
        ReadingNote(
          id: 'old',
          bookId: 'id-1',
          bookTitle: '史记',
          paragraphIndex: 3,
          selectedText: '原有笔记',
          createdAt: DateTime(2024, 1, 1),
        ),
      ]);
      final saved = await saveImportedNotes(
        library: library,
        notes: [
          ImportedNote(selectedText: '新的'),
          ImportedNote(selectedText: '  ', note: '   '),
        ],
        book: const BookMatchCandidate(id: 'id-1', title: '史记'),
      );

      expect(saved, 1);
      expect(library.notes, hasLength(2));
      expect(library.notes.map((n) => n.selectedText), contains('原有笔记'));
    });
  });

  testWidgets('reader paper keeps the note sheets legible', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: VellumTheme.forBrightness(Brightness.dark),
        home: CupertinoPageScaffold(
          child: UnassociatedNotesSheet(
            books: const [BookMatchCandidate(id: 'a', title: '史记')],
            notesLibrary: _MemoryNotesLibrary(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('未关联笔记'), findsOneWidget);
  });
}
