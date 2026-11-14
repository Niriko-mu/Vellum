
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_page_notes_controller.dart';
import 'package:vellum/reader/reader_page_pagination_controller.dart';
import 'package:vellum/reader/reader_page_progress_controller.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/services/book_models.dart';
import 'package:vellum/services/library_models.dart';
import 'package:vellum/services/notes_library.dart';

ImportedBook _book({int paragraphs = 24}) => ImportedBook(
  id: 'controller-book',
  title: '控制器测试书',
  format: BookFormat.txt,
  paragraphs: [
    for (var index = 0; index < paragraphs; index++) '正文段落 $index ' * 8,
  ],
  tocEntries: const [
    BookTocEntry(title: '第一章', paragraphIndex: 0),
    BookTocEntry(title: '第二章', paragraphIndex: 12),
  ],
);

void main() {
  test(
    'pagination controller uses a bounded anchored window for deep jumps',
    () {
      final book = _book(paragraphs: 5000);
      final controller = ReaderPaginationController(book: book);
      final page = controller.reset(
        config: const PageLayoutConfig(
          fontSize: 18,
          lineSpacing: ReaderLineSpacing.standard,
          fontFamily: 'Georgia',
          fontWeight: ReaderFontWeight.regular,
          availableHeight: 620,
          contentWidth: 360,
          screenHeight: 800,
          title: '控制器测试书',
        ),
        anchorParagraph: 4500,
      );

      expect(page, 0);
      expect(controller.pager.isAnchored, isTrue);
      expect(controller.pager.anchorParagraph, 4500);
      expect(controller.pageForParagraph(4501), greaterThanOrEqualTo(0));
      controller.dispose();
    },
  );

  test('pagination cancellation prevents an old generation callback', () async {
    final controller = ReaderPaginationController(book: _book(paragraphs: 800));
    var changes = 0;
    controller.paginateAsync(
      targetPages: 100,
      onChanged: () => changes++,
      isActive: () => true,
    );
    controller.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(changes, 0);
    controller.dispose();
  });

  test('anchored windows materialise a bounded predecessor on demand', () {
    final book = _book(paragraphs: 46978);
    final controller = ReaderPaginationController(book: book);
    controller.reset(
      config: const PageLayoutConfig(
        fontSize: 18,
        lineSpacing: ReaderLineSpacing.standard,
        fontFamily: 'Georgia',
        fontWeight: ReaderFontWeight.regular,
        availableHeight: 620,
        contentWidth: 360,
        screenHeight: 800,
        title: '控制器测试书',
      ),
      anchorParagraph: 12904,
    );

    final page = controller.preparePreviousPage(boundaryParagraph: 12904);

    expect(page, isNotNull);
    expect(page, greaterThan(0));
    expect(controller.pager.anchorParagraph, lessThan(12904));
    expect(12904 - controller.pager.anchorParagraph, lessThanOrEqualTo(512));
    expect(
      controller.pager.nextParagraph - controller.pager.anchorParagraph,
      lessThan(5000),
    );
    expect(
      controller.pager.pages[page!].any(
        (fragment) => fragment.paragraphIndex == 12904,
      ),
      isTrue,
    );
    controller.dispose();
  });

  test(
    'progress controller restores chapter positions without changing JSON',
    () {
      final state = ReadingState(
        paragraphIndex: 15,
        chapterPositions: const {
          12: ChapterReadingPosition(paragraphIndex: 17, page: 3),
        },
      );
      final controller = ReaderProgressController(
        book: _book(),
        initialState: state,
      );

      expect(controller.chapterIndexFor(17), 1);
      expect(controller.chapterStartForParagraph(17), 12);
      expect(controller.chapterLabelForParagraph(17), '第二章');
      expect(controller.chapterProgressForParagraph(18, .5), closeTo(.55, .01));
      expect(controller.chapterPositions[12]?.page, 3);
      expect(state.toJson()['chapterPositions'], isNotEmpty);
    },
  );

  test(
    'notes controller groups highlights and updates after deletion',
    () async {
      final library = _MemoryNotesLibrary([
        ReadingNote(
          id: 'one',
          bookId: 'controller-book',
          bookTitle: '控制器测试书',
          paragraphIndex: 2,
          selectedText: '划线内容',
          createdAt: DateTime(2026),
          style: 'highlight',
        ),
      ]);
      final controller = ReaderNotesController(
        bookId: 'controller-book',
        bookTitle: '控制器测试书',
        library: library,
      );

      await controller.load();
      expect(controller.noteCountFor(2), 1);
      expect(controller.highlights[2], ['划线内容']);
      await controller.removeNote('one');
      expect(controller.noteCountFor(2), 0);
      expect(controller.highlights, isEmpty);
    },
  );
}

class _MemoryNotesLibrary extends NotesLibrary {
  _MemoryNotesLibrary(Iterable<ReadingNote> values) : _notes = [...values];

  List<ReadingNote> _notes;

  @override
  Future<List<ReadingNote>> loadForBook(String bookId) async => [
    for (final note in _notes)
      if (note.bookId == bookId) note,
  ];

  @override
  Future<void> delete(String id) async {
    _notes = [
      for (final note in _notes)
        if (note.id != id) note,
    ];
  }
}
