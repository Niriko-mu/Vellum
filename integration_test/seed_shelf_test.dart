import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vellum/services/book_import_service.dart';
import 'package:vellum/services/book_library.dart';

/// Seeds the device shelf with one reusable fixture book.
///
/// The import tests reset the library index, which leaves a manual UI pass with
/// an empty shelf and no way to get a book back without the file picker. This
/// helper exists so an adb-driven check afterwards has something to open.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed the shelf with the TXT-free EPUB fixture', (tester) async {
    final data = await rootBundle.load('assets/test_books/inspect.epub');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    const library = BookLibrary();
    final book = await decodeAndPersistBook({
      'filename': 'inspect.epub',
      'bytes': TransferableTypedData.fromList([Uint8List.fromList(bytes)]),
      'existingIds': const <String>[],
      'existingCount': 0,
      'storageDirectory': await library.bookStorageDirectoryPath(),
    });
    await library.saveIndex([book]);

    final reloaded = await library.load();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.format.name, 'epub');
  });
}
