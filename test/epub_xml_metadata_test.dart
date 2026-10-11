import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/epub_decoder.dart';

void main() {
  test(
    'container, package and spine support namespaces, single quotes and XML entities',
    () {
      final archive = Archive();
      final files = {
        'META-INF/container.xml':
            "<c:container xmlns:c='urn:oasis:names:tc:opendocument:xmlns:container'><c:rootfiles><c:rootfile full-path='OPS/book.opf'/></c:rootfiles></c:container>",
        'OPS/book.opf':
            """<o:package xmlns:o='http://www.idpf.org/2007/opf' xmlns:meta='http://purl.org/dc/elements/1.1/'><o:metadata><meta:title>标题 &amp; 测试</meta:title><meta:creator>作者 (Author)</meta:creator></o:metadata><o:manifest><o:item media-type='application/xhtml+xml' href='chapter.xhtml' id='c'/></o:manifest><o:spine><o:itemref idref='c'/></o:spine></o:package>""",
        'OPS/chapter.xhtml': '<html><body><p>章节正文。</p></body></html>',
      };
      for (final entry in files.entries) {
        archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
      }
      final book = const EpubDecoder().decode(
        'book.epub',
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      expect(book.title, '标题 & 测试');
      expect(book.author, '作者');
      expect(book.paragraphs, contains('章节正文。'));
    },
  );
}
