import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_importer.dart';

/// End-to-end parsing of real, on-disk files - not in-memory fixtures.
///
/// The unit tests build minimal archives inline, which proves the decoders
/// handle the shapes they were told to handle. These run the same decoders
/// over files written by tool/make_inspect_samples.dart, so a regression in
/// how a normal file is actually laid out is caught too.
void main() {
  const importer = BookImporter();

  ImportedBook parse(String name) {
    final file = File('test/fixtures/$name');
    expect(file.existsSync(), isTrue, reason: 'run the sample generator first');
    return importer.decode(
      filename: name,
      bytes: Uint8List.fromList(file.readAsBytesSync()),
    );
  }

  test('an EPUB file on disk parses into chapters and body text', () {
    final book = parse('inspect.epub');
    expect(book.format, BookFormat.epub);
    expect(book.title, contains('EPUB'));
    expect(book.paragraphs.length, greaterThan(10));
    expect(book.tocEntries.length, 3);
    expect(
      book.paragraphs.any((p) => p.contains('第1章')),
      isTrue,
      reason: 'chapter headings survive decoding',
    );
  });

  test('a MOBI file on disk parses into body text', () {
    final book = parse('inspect.mobi');
    expect(book.format, BookFormat.mobi);
    expect(book.paragraphs.length, greaterThan(10));
    expect(
      book.paragraphs.any((p) => p.contains('MOBI')),
      isTrue,
      reason: 'the UTF-8 body survives PalmDOC decoding',
    );
  });

  test('both formats produce paginatable paragraph lists', () {
    for (final name in ['inspect.epub', 'inspect.mobi']) {
      final book = parse(name);
      final nonEmpty = book.paragraphs.where((p) => p.trim().isNotEmpty);
      expect(nonEmpty.length, greaterThan(8), reason: name);
      // Every paragraph must carry text a reader surface can lay out.
      expect(nonEmpty.every((p) => p.length > 1), isTrue, reason: name);
    }
  });
}
