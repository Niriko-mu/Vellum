import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:vellum/services/book_import_service.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_library.dart';

/// The import pipeline, on a real device, for the formats a shelf actually
/// accepts.
///
/// Unit tests prove the decoders handle bytes. They cannot prove that a decoded
/// book survives being written to device storage and read back — which is where
/// a format-specific bug actually shows up for a reader: the book appears on the
/// shelf and then fails to open.
///
/// This runs the app's own import code (decodeAndPersistBook) rather than a
/// parallel test-only path, so it exercises the real staging, hashing and
/// persistence. The system file picker cannot be driven from adb, so reaching
/// the pipeline this way is the only honest end-to-end check available.
/// Reads a fixture from the app bundle. The asset is shipped with the app
/// precisely so this test needs no file-picker interaction and no adb push.
Future<Uint8List> _fixtureBytes(String asset) async {
  final data = await rootBundle.load(asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an EPUB imported on device lands on the shelf and opens', (
    tester,
  ) async {
    final bytes = await _fixtureBytes('assets/test_books/inspect.epub');
    final book = await decodeAndPersistBook({
      'filename': 'inspect.epub',
      'bytes': TransferableTypedData.fromList([bytes]),
      'existingIds': const <String>[],
      'existingCount': 0,
      'storageDirectory': await const BookLibrary().bookStorageDirectoryPath(),
    });

    expect(book.format, BookFormat.epub);
    expect(book.storageId, startsWith('epub_'));
    expect(book.title, isNotEmpty, reason: 'EPUB dc:title must survive import');
    expect(book.paragraphCount, greaterThan(10));

    // The book must be readable back from storage, not just in memory.
    const library = BookLibrary();
    await library.saveIndex([book]);
    final reloaded = await library.load();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.storageId, book.storageId);

    final full = await library.loadBookContent(reloaded.single);
    expect(full.paragraphs.length, greaterThan(10));
    expect(
      full.paragraphs.any((p) => p.contains('第1章')),
      isTrue,
      reason: 'the chapter headings must be there after a round trip',
    );

    // EPUB keeps the original archive so the reader can offer 原书样式.
    final original = await library.originalEpubPath(book.storageId);
    expect(original, isNotNull);
    expect(File(original).existsSync(), isTrue);
  });

  testWidgets('a MOBI imported on device lands on the shelf and opens', (
    tester,
  ) async {
    final bytes = await _fixtureBytes('assets/test_books/inspect.mobi');
    final book = await decodeAndPersistBook({
      'filename': 'inspect.mobi',
      'bytes': TransferableTypedData.fromList([bytes]),
      'existingIds': const <String>[],
      'existingCount': 0,
      'storageDirectory': await const BookLibrary().bookStorageDirectoryPath(),
    });

    expect(book.format, BookFormat.mobi);
    expect(book.storageId, startsWith('mobi_'));
    expect(book.paragraphCount, greaterThan(5));

    const library = BookLibrary();
    await library.saveIndex([book]);
    final reloaded = await library.load();
    expect(reloaded.single.format, BookFormat.mobi);

    final full = await library.loadBookContent(reloaded.single);
    expect(
      full.paragraphs.any((p) => p.contains('MOBI')),
      isTrue,
      reason: 'the PalmDOC body must survive the round trip',
    );
  });
}
