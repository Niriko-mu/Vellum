import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_importer.dart';

/// The import boundary between the two halves of the app.
///
/// Markdown belongs to the writing tab, where a .md file is a draft that the
/// editor opens and the preview renders. It is deliberately NOT a book format:
/// the shelf imports EPUB / MOBI / TXT only. This split was a product decision,
/// so it gets a test - otherwise a future 'just add md to the picker' change
/// silently puts drafts and books in the same list.
void main() {
  const importer = BookImporter();

  test('the shelf accepts exactly EPUB, MOBI and TXT', () {
    expect(importer.formatForFilename('a.epub'), BookFormat.epub);
    expect(importer.formatForFilename('a.mobi'), BookFormat.mobi);
    expect(importer.formatForFilename('a.txt'), BookFormat.txt);
  });

  test(
    'Markdown is rejected as a book instead of being quietly read as TXT',
    () {
      for (final name in ['draft.md', 'notes.markdown', 'README.MD']) {
        expect(
          () => importer.formatForFilename(name),
          throwsA(isA<BookImportException>()),
          reason: '$name is a writing draft, not a shelf book',
        );
      }
    },
  );

  test('the rejection message names what is actually supported', () {
    try {
      importer.formatForFilename('draft.md');
      fail('expected a BookImportException');
    } on BookImportException catch (error) {
      expect(error.message, contains('EPUB'));
      expect(error.message, contains('MOBI'));
      expect(error.message, contains('TXT'));
      expect(
        error.message.contains('MD'),
        isFalse,
        reason: 'the message must not imply Markdown is importable',
      );
    }
  });
}
