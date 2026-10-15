import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vellum/reader/reader_toc.dart';
import 'package:vellum/services/book_cover.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/book_models.dart';
import 'package:vellum/services/book_search.dart';
import 'package:vellum/services/chunked_book_store.dart';
import 'package:vellum/services/tts_text.dart';
import 'package:vellum/services/txt_catalog.dart';
import 'package:vellum/services/txt_seek_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vellum_chunks_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  ImportedBook fixture() => ImportedBook(
    id: 'mobi_chunk_fixture',
    title: '分块大书',
    author: '作者',
    format: BookFormat.mobi,
    paragraphs: [
      for (var i = 0; i < 1800; i++) i == 777 ? '第二章' : '第$i段 ${'正文' * 80}。',
    ],
    tocEntries: const [BookTocEntry(title: '第二章', paragraphIndex: 777)],
    linkTargets: const {900: 777},
    imageBytes: {
      600: Uint8List.fromList([1, 2, 3, 255]),
    },
  );

  Future<ImportedBook> persist(ImportedBook book) async {
    final path = '${root.path}/book.json';
    await writeChunkedBook(book, path);
    return openChunkedBook(
      path,
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>,
    );
  }

  test(
    'random access, LRU eviction and metadata never materialize the book',
    () async {
      final original = fixture();
      final book = await persist(original);
      final body = book.paragraphs as ChunkedParagraphList;
      expect(body.cachedBlockCount, 0);
      expect(chapterEntries(book).single.key, 777);
      expect(book.totalCharCount, original.totalCharCount);
      expect(body.cachedBlockCount, 0);
      for (final index in [1799, 0, 777, 128, 600, 1000, 1400, 1600, 33]) {
        expect(body[index], original.paragraphs[index]);
        expect(body.cachedBlockCount, lessThanOrEqualTo(5));
        expect(body.cachedBytes, lessThanOrEqualTo(2 * 1024 * 1024));
        expect(
          body.charactersBefore(index),
          original.paragraphs
              .take(index)
              .fold<int>(0, (sum, s) => sum + s.length),
        );
      }
      expect(book.imageBytes.containsKey(600), isTrue);
      expect(book.imageBytes[600], original.imageBytes[600]);
      expect(book.linkTargets[900], 777);
      body.close();
      expect(body.cachedBlockCount, 0);
      await body.prefetchAroundParagraph(777);
      expect(body.isParagraphCached(777), isTrue);
      expect(body.blockEndForParagraph(776), 777);
      // Wait for the adjacent prefetch before removing its temporary directory.
      await body.prefetchAroundParagraph(body.blockEndForParagraph(777));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test('legacy migration preserves IDs, offsets, search and speech', () async {
    const library = BookLibrary();
    final original = fixture();
    await library.save([original]);
    final shell = (await library.load()).single;
    final book = await library.loadBookContent(shell);
    expect(book.paragraphs, isA<ChunkedParagraphList>());
    expect(book.storageId, original.storageId);
    expect(book.author, original.author);
    expect(book.paragraphs[777], '第二章');
    final search = BookSearchTask(
      paragraphs: book.paragraphs,
      query: '第1799段',
      chapters: chapterEntries(book),
    );
    expect((await search.result).hits.single.paragraphIndex, 1799);
    final speech = await buildSpeakableSegmentsInBackground(book.paragraphs);
    expect(speech.any((s) => s.paragraphIndex == 1799), isTrue);
    await library.save([book]);
    expect(
      (await library.loadBookContent(shell)).paragraphs[1799],
      original.paragraphs[1799],
    );
    await library.deleteBook(book);
    expect(
      File(
        '${root.path}/vellum_books/${book.storageId}.json.body',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'migration recovers original JSON after an interrupted manifest swap',
    () async {
      const library = BookLibrary();
      await library.save([fixture()]);
      final shell = (await library.load()).single;
      final path = '${root.path}/vellum_books/${shell.storageId}.json';
      await File(path).rename('$path.legacy');
      await File('$path.body').writeAsString('partial body');
      final loaded = await library.loadBookContent(shell);
      expect(loaded.paragraphs, isA<ChunkedParagraphList>());
      expect(loaded.paragraphs[777], '第二章');
      expect(File('$path.legacy').existsSync(), isFalse);
    },
  );

  test('covers are bounded and retain transparency', () {
    final opaque = image.Image(width: 2000, height: 1000);
    final jpg = optimizeBookCover(Uint8List.fromList(image.encodePng(opaque)))!;
    final decoded = image.decodeImage(jpg)!;
    expect(decoded.width, 1600);
    expect(decoded.height, 800);
    final transparent = image.Image(width: 2, height: 2, numChannels: 4);
    transparent.setPixelRgba(0, 0, 10, 20, 30, 0);
    final png = optimizeBookCover(
      Uint8List.fromList(image.encodePng(transparent)),
    )!;
    expect(image.decodePng(png)!.getPixel(0, 0).a, 0);
  });

  test(
    'same-title books have independent progress and legacy state still loads',
    () async {
      const library = BookLibrary();
      final first = fixture();
      final second = first.copyWith(id: 'mobi_another_copy');
      await File('${root.path}/vellum_reading_state.json').writeAsString(
        jsonEncode({
          'mobi:分块大书': {'paragraphIndex': 777},
        }),
      );
      expect((await library.loadReadingState(first)).paragraphIndex, 777);
      await library.saveReadingState(
        first,
        const ReadingState(paragraphIndex: 900),
      );
      await library.saveReadingState(
        second,
        const ReadingState(paragraphIndex: 1200),
      );
      expect((await library.loadReadingState(first)).paragraphIndex, 900);
      expect((await library.loadReadingState(second)).paragraphIndex, 1200);
      final renamed = ImportedBook(
        id: first.storageId,
        title: '改名',
        format: BookFormat.mobi,
        paragraphs: const [],
      );
      expect((await library.loadReadingState(renamed)).paragraphIndex, 900);
    },
  );

  test('GB18030 four-byte characters survive byte chunk boundaries', () async {
    // Python GB18030 golden vectors: U+0080, U+20000 and U+1F600.
    final bytes = Uint8List.fromList([
      ...List.filled(4999, 0x61),
      0x81,
      0x30,
      0x81,
      0x30,
      0x95,
      0x32,
      0x82,
      0x36,
      0x94,
      0x39,
      0xfc,
      0x36,
      ...List.filled(6000, 0x62),
    ]);
    final expected = '${'a' * 4999}\u0080𠀀😀${'b' * 6000}';
    expect(decodeTxtWithEncoding(bytes, 'gb18030'), expected);
    final path = '${root.path}/wide.txt';
    await File(path).writeAsBytes(bytes);
    final catalog = scanTxtCatalogFile(path);
    final paragraphs = TxtParagraphList(
      TxtSeekSource(file: File(path), catalog: catalog),
    );
    expect(paragraphs.join(), expected);
    paragraphs.close();
  });
}
