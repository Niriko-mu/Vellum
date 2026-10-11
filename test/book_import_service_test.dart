import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_import_service.dart';
import 'package:vellum/services/book_library.dart';

void main() {
  Future<Directory> tempStorage() async =>
      Directory.systemTemp.createTemp('vellum_import_test_');

  test(
    'large seek imports return a shelf shell and persist source lazily',
    () async {
      final storage = await tempStorage();
      addTearDown(() => storage.delete(recursive: true));
      final bytes = Uint8List.fromList(
        utf8.encode(
          [
            for (var index = 0; index < 50000; index++) 'paragraph-$index',
          ].join('\n\n'),
        ),
      );

      final shell = await decodeAndPersistBook({
        'filename': 'large.txt',
        'bytes': TransferableTypedData.fromList([bytes]),
        'storageDirectory': storage.path,
      });

      expect(shell.paragraphs, isEmpty);
      expect(shell.metaParagraphCount, greaterThan(45000));
      expect(shell.contentMode, 'seek');
      expect(shell.catalog, isNotNull);
      final source = File(
        '${storage.path}${Platform.pathSeparator}'
        '${shell.storageId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.src',
      );
      expect(source.existsSync(), isTrue);
      expect(source.lengthSync(), bytes.length);
      expect(
        storage.listSync().where(
          (entity) => entity.path.endsWith('.importing'),
        ),
        isEmpty,
      );
    },
  );

  test('inline imports persist content but return only the shelf metadata', () async {
    final storage = await tempStorage();
    addTearDown(() => storage.delete(recursive: true));
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/book.opf',
          '<package><metadata><dc:title>大书</dc:title></metadata>'
              '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>'
              '<spine><itemref idref="c"/></spine></package>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/c.xhtml',
          '<html><body>${[for (var index = 0; index < 2000; index++) '<p>第${index + 1}段正文。</p>'].join()}</body></html>',
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

    final shell = await decodeAndPersistBook({
      'filename': 'large.epub',
      'bytes': TransferableTypedData.fromList([bytes]),
      'storageDirectory': storage.path,
    });

    expect(shell.paragraphs, isEmpty);
    expect(shell.metaParagraphCount, 2000);
    expect(shell.contentMode, 'inline');
    final content = File(
      '${storage.path}${Platform.pathSeparator}'
      '${shell.storageId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.json',
    );
    expect(content.existsSync(), isTrue);
    final decoded =
        jsonDecode(content.readAsStringSync()) as Map<String, dynamic>;
    expect((decoded['paragraphs'] as List).length, 2000);
    expect(
      storage.listSync().where((entity) => entity.path.endsWith('.importing')),
      isEmpty,
    );
  });
}
