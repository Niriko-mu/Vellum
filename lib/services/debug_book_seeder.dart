import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;

import '../services/book_import_service.dart';
import '../services/book_importer.dart';
import '../services/book_library.dart';

/// Debug-only seeding of the shelf from a bundled fixture.
///
/// Why this exists at all: the system file picker cannot be driven through adb,
/// and the import confirmation page ignored every tap the harness sent it. That
/// made "open a book on the device and look at it" impossible to reach, which in
/// turn left the reader's animations verified only by widget tests.
///
/// It runs the app's own import path - the same `decodeAndPersistBook` the
/// integration test uses - so the book that lands on the shelf is a real one,
/// not a stub. Everything here is behind [kDebugMode]: in a release build the
/// constant folds away and none of this exists.
abstract final class DebugBookSeeder {
  /// The fixture shipped for on-device checks.
  static const String fixtureAsset = 'assets/test_books/inspect.epub';

  static const String fixtureName = 'inspect.epub';

  /// Imports the fixture into the real library. Returns the seeded book.
  static Future<ImportedBook> seed() async {
    assert(kDebugMode, 'only a debug build may seed the shelf');
    final data = await rootBundle.load(fixtureAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    const library = BookLibrary();
    final existing = await library.load();
    final book = await decodeAndPersistBook({
      'filename': fixtureName,
      'bytes': TransferableTypedData.fromList([Uint8List.fromList(bytes)]),
      'existingIds': [for (final b in existing) b.storageId],
      'existingCount': existing.length,
      'storageDirectory': await library.bookStorageDirectoryPath(),
    });
    if (book.title.isEmpty) {
      // Already imported: hand back the shelf entry instead of a blank shell.
      return existing.firstWhere((b) => b.storageId == book.storageId);
    }
    await library.saveIndex([...existing, book]);
    return book;
  }
}
