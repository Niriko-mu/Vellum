import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_search.dart';
import 'package:vellum/services/txt_catalog.dart';
import 'package:vellum/services/txt_seek_source.dart';
import 'package:vellum/services/mobi_decoder.dart';
import 'package:vellum/services/tts_text.dart';

void main() {
  Uint8List utf16(String text, Endian endian) {
    final data = ByteData(2 + text.length * 2);
    data.setUint16(0, 0xfeff, endian);
    for (var i = 0; i < text.length; i++) {
      data.setUint16(2 + i * 2, text.codeUnitAt(i), endian);
    }
    return data.buffer.asUint8List();
  }

  test(
    'streamed catalog matches byte scan across encodings and block edges',
    () async {
      final directory = await Directory.systemTemp.createTemp('vellum-stream-');
      try {
        for (final bytes in [
          Uint8List.fromList(
            utf8.encode('第一章 起始\r\n${'汉😀' * 30000}\r\n第二章 后续\r\n正文'),
          ),
          Uint8List.fromList(utf8.encode('汉😀' * 12000)),
          Uint8List.fromList(gbk.encode('第一章 起始\n${'中文' * 30000}\n第二章 后续\n正文')),
          utf16('第一章 起始\r\n${'汉😀' * 30000}\r\n第二章 后续\r\n正文', Endian.little),
          utf16('第一章 起始\r\n${'汉😀' * 30000}\r\n第二章 后续\r\n正文', Endian.big),
        ]) {
          final file = await File(
            '${directory.path}/source.txt',
          ).writeAsBytes(bytes);
          expect(
            scanTxtCatalogFile(file.path).toJson(),
            scanTxtCatalog(bytes).toJson(),
          );
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  for (final endian in [Endian.little, Endian.big]) {
    test('BOM-less UTF-16 $endian with ASCII evidence is detected', () {
      final bytes = Uint8List.sublistView(
        utf16('Chapter 1\n\n正文内容\n\nChapter 2\n\n更多内容', endian),
        2,
      );
      expect(
        detectTxtEncoding(bytes),
        endian == Endian.little ? 'utf-16le' : 'utf-16be',
      );
      final book = const BookImporter().decode(
        filename: 'book.txt',
        bytes: bytes,
      );
      expect(book.paragraphs.join(), contains('正文内容'));
    });
    test('UTF-16 $endian keeps chapter offsets and body starts', () {
      final book = const BookImporter().decode(
        filename: 'book.txt',
        bytes: utf16('第一章 开始\r\n甲乙丙\r\n\r\n丁戊己\r\n第二章 后续\r\n庚辛壬', endian),
      );
      expect(book.paragraphs.toList(), ['甲乙丙', '丁戊己', '庚辛壬']);
      expect(book.tocEntries.length, 2);
      expect(book.catalog!.totalParagraphs, book.paragraphs.length);
    });
  }

  test('UTF-8 four-byte characters survive synthetic boundaries', () {
    final original = '汉😀字' * 4000;
    final book = const BookImporter().decode(
      filename: 'book.txt',
      bytes: Uint8List.fromList(utf8.encode(original)),
    );
    expect(book.catalog!.encoding, 'utf-8');
    expect(book.paragraphs.join(), original);
  });

  test('GBK synthetic boundaries preserve all characters', () {
    final original = '中文测试' * 3000;
    final book = const BookImporter().decode(
      filename: 'book.txt',
      bytes: Uint8List.fromList(gbk.encode(original)),
    );
    expect(book.catalog!.encoding, 'gbk');
    expect(book.paragraphs.join(), original);
  });

  test('empty chapters do not introduce stale paragraph counts', () {
    final book = const BookImporter().decode(
      filename: 'book.txt',
      bytes: Uint8List.fromList(utf8.encode('第一章 空\n第二章 内容\n甲\n\n乙\n第三章 空')),
    );
    expect(book.paragraphs.toList(), ['甲', '乙']);
    expect(book.catalog!.totalParagraphs, 2);
  });

  test('giant titled chapter is decoded in bounded blocks', () {
    final original = '汉😀' * 100000;
    final book = const BookImporter().decode(
      filename: 'book.txt',
      bytes: Uint8List.fromList(utf8.encode('第一章 开始\n$original')),
    );
    expect(book.paragraphs.join(), original);
    expect(
      book.catalog!.chapters.every((c) => c.byteLength <= 64 * 1024),
      isTrue,
    );
    expect(book.tocEntries.length, 1);
  });

  test('background TXT search reads path and releases its source', () async {
    final directory = await Directory.systemTemp.createTemp('vellum-search-');
    try {
      final bytes = Uint8List.fromList(utf8.encode('第一章 开始\n搜索目标\n\n其他文字'));
      final file = await File('${directory.path}/book.txt').writeAsBytes(bytes);
      final catalog = scanTxtCatalog(bytes);
      final paragraphs = TxtParagraphList(
        TxtSeekSource(file: file, catalog: catalog),
      );
      final task = BookSearchTask(
        paragraphs: paragraphs,
        query: '目标',
        chapters: catalog.tocEntries,
      );
      final result = await task.result;
      expect(result.hits.single.paragraphIndex, 0);
      final speech = await buildSpeakableSegmentsInBackground(paragraphs);
      expect(speech.map((segment) => segment.text), contains('搜索目标'));
      paragraphs.source.close();
      final cancelled = BookSearchTask(
        paragraphs: paragraphs,
        query: '不存在',
        chapters: [],
      );
      cancelled.cancel();
      expect((await cancelled.result).isEmpty, isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('speech queue budget fails explicitly without silently truncating', () {
    expect(
      () => buildSpeakableSegments(['甲。乙。丙。'], maxSegments: 2),
      throwsFormatException,
    );
    expect(
      () => buildSpeakableSegments(['甲乙丙'], maxTotalChars: 2),
      throwsFormatException,
    );
  });

  test('zero-length Huffman code fails instead of looping forever', () {
    final huff = ByteData(16 + 256 * 4 + 64 * 4);
    huff.setUint32(8, 16, Endian.big);
    huff.setUint32(12, 16 + 256 * 4, Endian.big);
    for (var i = 0; i < 256; i++) {
      huff.setUint32(16 + i * 4, 0x80, Endian.big);
    }
    final cdic = ByteData(20);
    cdic.setUint32(8, 1, Endian.big);
    cdic.setUint32(12, 0, Endian.big);
    cdic.setUint16(16, 2, Endian.big);
    cdic.setUint16(18, 0x8000, Endian.big);
    final decoder = MobiHuffCdic()
      ..load(huff.buffer.asUint8List(), [cdic.buffer.asUint8List()]);
    expect(
      () => decoder.unpack(Uint8List.fromList([0])),
      throwsA(isA<BookImportException>()),
    );
  });
}
