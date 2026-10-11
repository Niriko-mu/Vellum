import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_import_service.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/book_models.dart';
import 'package:vellum/services/txt_seek_source.dart';

class _FailingIndexLibrary extends BookLibrary {
  const _FailingIndexLibrary();
  @override
  Future<void> saveIndex(List<ImportedBook> books) async =>
      throw const FileSystemException('simulated disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    documents = await Directory.systemTemp.createTemp('vellum_transaction_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => documents.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documents.delete(recursive: true);
  });
  PlatformFile txt(String name, String body) {
    final bytes = Uint8List.fromList(utf8.encode(body));
    return PlatformFile(name: name, bytes: bytes, size: bytes.length);
  }

  test('duplicate renamed input preserves cover and folder metadata', () async {
    const library = BookLibrary();
    const service = BookImportService();
    final original = await service.importFile(
      library: library,
      existing: [],
      file: txt('a.txt', '第一章 标题\n正文。'),
    );
    final custom = original.book.copyWith(
      coverText: '我的封面',
      folderId: 'folder',
    );
    await library.saveIndex([custom]);
    final duplicate = await service.importFile(
      library: library,
      existing: [custom],
      file: txt('b.txt', '第一章 标题\n正文。'),
    );
    expect(duplicate.duplicate, isTrue);
    expect(duplicate.book.coverText, '我的封面');
    expect(duplicate.book.folderId, 'folder');
    expect((await library.load()).length, 1);
  });

  test(
    'duplicate EPUB repairs missing original without replacing shelf metadata',
    () async {
      const library = BookLibrary();
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'book.opf',
            '<package><metadata><dc:title>原书</dc:title></metadata><manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>',
          ),
        )
        ..addFile(
          ArchiveFile.string('c.xhtml', '<html><body><p>正文</p></body></html>'),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
      final input = PlatformFile(
        name: 'original.epub',
        bytes: bytes,
        size: bytes.length,
      );
      final imported = await const BookImportService().importFile(
        library: library,
        existing: [],
        file: input,
      );
      final customized = imported.book.copyWith(
        coverText: '自定义封面',
        folderId: 'my-folder',
      );
      await library.saveIndex([customized]);
      final original = File(
        await library.originalEpubPath(imported.book.storageId),
      );
      await original.delete();
      final duplicate = await const BookImportService().importFile(
        library: library,
        existing: [customized],
        file: input,
      );
      expect(duplicate.duplicate, isTrue);
      expect(original.readAsBytesSync(), bytes);
      expect(duplicate.book.coverText, '自定义封面');
      expect(duplicate.book.folderId, 'my-folder');
      await File('${original.path}.reader.json').writeAsString('{"cfi":"old"}');
      await File('${original.path}.reader.json.tmp').writeAsString('partial');
      await library.deleteBook(duplicate.book);
      expect(original.existsSync(), isFalse);
      expect(File('${original.path}.reader.json').existsSync(), isFalse);
      expect(File('${original.path}.reader.json.tmp').existsSync(), isFalse);
    },
  );
  test(
    'batch continues after malformed book and commits valid input',
    () async {
      const library = BookLibrary();
      final outcomes = <BookFileImportOutcome>[];
      final books = await const BookImportService().importFiles(
        library: library,
        existing: [],
        files: [txt('bad.epub', 'broken zip'), txt('good.txt', '第一章 标题\n正文。')],
        onFileResult: outcomes.add,
      );
      expect(outcomes[0].error, isNotNull);
      expect(outcomes[1].result, isNotNull);
      expect(books.length, 1);
      final dir = Directory(await library.bookStorageDirectoryPath());
      expect(dir.listSync().whereType<Directory>(), isEmpty);
      expect(File('${dir.path}/.import-journal.json').existsSync(), isFalse);
    },
  );
  test('capacity rejects before writing book body', () async {
    const library = BookLibrary();
    final existing = [
      for (var i = 0; i < 200; i++)
        ImportedBook(
          id: 'txt_$i',
          title: '$i',
          format: BookFormat.txt,
          paragraphs: const [],
        ),
    ];
    await expectLater(
      const BookImportService().importFile(
        library: library,
        existing: existing,
        file: txt('new.txt', '正文。'),
      ),
      throwsA(isA<BookImportException>()),
    );
    final dir = Directory(await library.bookStorageDirectoryPath());
    expect(dir.listSync(), isEmpty);
  });
  test(
    'cancellation kills parser and leaves no staged body or index',
    () async {
      const library = BookLibrary();
      final token = BookImportCancellation();
      await expectLater(
        const BookImportService().importFile(
          library: library,
          existing: [],
          file: txt('huge.txt', List.filled(100000, '段落内容').join('\n')),
          cancellation: token,
          onProgress: (p) {
            if (p.stage.contains('解析章节')) token.cancel();
          },
        ),
        throwsA(isA<BookImportCancelled>()),
      );
      final dir = Directory(await library.bookStorageDirectoryPath());
      expect(dir.listSync(), isEmpty);
      expect(await library.load(), isEmpty);
    },
  );
  test(
    'startup removes unpublished journal artifacts and restores backup index',
    () async {
      const library = BookLibrary();
      final root = Directory(await library.bookStorageDirectoryPath());
      await root.create(recursive: true);
      await Directory('${root.path}/.import-abandoned').create();
      await File(
        '${root.path}/.import-abandoned/partial.src',
      ).writeAsString('partial');
      await File('${root.path}/.import-abandoned/.lease').writeAsString('');
      await File(
        '${root.path}/.import-abandoned/.lease',
      ).setLastModified(DateTime.now().subtract(const Duration(days: 2)));
      await File('${root.path}/txt_orphan.src').writeAsString('orphan');
      await File('${root.path}/.import-journal.json').writeAsString(
        jsonEncode({
          'id': 'txt_orphan',
          'files': ['txt_orphan.src'],
        }),
      );
      await File(
        '${documents.path}/vellum_library.json.backup',
      ).writeAsString('[]');
      expect(await library.load(), isEmpty);
      expect(File('${root.path}/txt_orphan.src').existsSync(), isFalse);
      expect(Directory('${root.path}/.import-abandoned').existsSync(), isFalse);
      expect(
        File('${documents.path}/vellum_library.json').existsSync(),
        isTrue,
      );
    },
  );
  test('startup retains committed journal files', () async {
    const library = BookLibrary();
    final result = await const BookImportService().importFile(
      library: library,
      existing: [],
      file: txt('book.txt', '正文。'),
    );
    final root = Directory(await library.bookStorageDirectoryPath());
    final name = '${result.book.storageId}.src';
    await File('${root.path}/.import-journal.json').writeAsString(
      jsonEncode({
        'id': result.book.storageId,
        'files': [name],
      }),
    );
    expect((await library.load()).length, 1);
    expect(File('${root.path}/$name').existsSync(), isTrue);
  });

  test('failed index publication removes promoted body files', () async {
    const library = _FailingIndexLibrary();
    await expectLater(
      const BookImportService().importFile(
        library: library,
        existing: [],
        file: txt('book.txt', '正文。'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      Directory(await library.bookStorageDirectoryPath()).listSync(),
      isEmpty,
    );
    expect(await library.load(), isEmpty);
  });

  test('concurrent imports serialize commits and retain both books', () async {
    const library = BookLibrary();
    await Future.wait([
      const BookImportService().importFile(
        library: library,
        existing: [],
        file: txt('one.txt', '第一本正文。'),
      ),
      const BookImportService().importFile(
        library: library,
        existing: [],
        file: txt('two.txt', '第二本正文。'),
      ),
    ]);
    expect((await library.load()).length, 2);
  });

  test('legacy oversized TXT catalog migrates off the UI isolate', () async {
    const library = BookLibrary();
    final input = txt('legacy.txt', List.filled(40000, '正文段落。').join('\n'));
    final result = await const BookImportService().importFile(
      library: library,
      existing: [],
      file: input,
    );
    final oldCatalog = TxtCatalog(
      encoding: 'utf-8',
      status: TxtCatalogStatus.synthetic,
      chapters: [
        TxtChapterRef(
          index: 0,
          title: '第1章',
          startOffset: 0,
          byteLength: input.size,
          paragraphCount: 40000,
        ),
      ],
    );
    final legacy = result.book.copyWith(catalog: oldCatalog);
    await library.saveIndex([legacy]);
    final loaded = await library.loadBookContent(legacy);
    expect(
      loaded.catalog!.chapters.every((c) => c.byteLength <= 256 * 1024),
      isTrue,
    );
    expect(loaded.paragraphs[100], contains('正文段落'));
    (loaded.paragraphs as TxtParagraphList).source.close();
    expect(
      (await library.load()).single.catalog!.chapters.length,
      greaterThan(1),
    );
  });

  test(
    'path TXT import scans and copies source without a whole-file transfer',
    () async {
      const library = BookLibrary();
      final body = utf8.encode(
        '第一章 正文\n${List.filled(20000, '中文内容').join('\n')}',
      );
      final source = File('${documents.path}/input.txt');
      await source.writeAsBytes(body);
      final result = await const BookImportService().importFile(
        library: library,
        existing: [],
        file: PlatformFile(
          name: 'input.txt',
          path: source.path,
          size: body.length,
        ),
      );
      final root = await library.bookStorageDirectoryPath();
      expect(
        File('$root/${result.book.storageId}.src').readAsBytesSync(),
        body,
      );
      expect(
        result.book.catalog!.chapters.every((c) => c.byteLength <= 64 * 1024),
        isTrue,
      );
      expect(result.book.paragraphs, isEmpty);
    },
  );

  test(
    'corrupt primary index restores valid backup during journal recovery',
    () async {
      const library = BookLibrary();
      final root = Directory(await library.bookStorageDirectoryPath());
      await root.create(recursive: true);
      await File(
        '${documents.path}/vellum_library.json',
      ).writeAsString('{truncated');
      await File(
        '${documents.path}/vellum_library.json.backup',
      ).writeAsString('[]');
      await File('${root.path}/txt_orphan.src').writeAsString('orphan');
      await File('${root.path}/unrelated.src').writeAsString('keep');
      await File('${root.path}/.import-journal.json').writeAsString(
        jsonEncode({
          'id': 'txt_orphan',
          'files': ['txt_orphan.src', 'unrelated.src'],
        }),
      );
      expect(await library.load(), isEmpty);
      expect(File('${root.path}/txt_orphan.src').existsSync(), isFalse);
      expect(File('${root.path}/unrelated.src').existsSync(), isTrue);
    },
  );

  test(
    'corrupt index with no backup preserves uncertain journal body files',
    () async {
      const library = BookLibrary();
      final root = Directory(await library.bookStorageDirectoryPath());
      await root.create(recursive: true);
      await File(
        '${documents.path}/vellum_library.json',
      ).writeAsString('{truncated');
      await File('${root.path}/txt_orphan.src').writeAsString('keep');
      await File('${root.path}/.import-journal.json').writeAsString(
        jsonEncode({
          'id': 'txt_orphan',
          'files': ['txt_orphan.src'],
        }),
      );
      expect(await library.load(), isEmpty);
      expect(File('${root.path}/txt_orphan.src').existsSync(), isTrue);
    },
  );
  test(
    'recovery preserves fresh staging from an unregistered engine',
    () async {
      const library = BookLibrary();
      final root = Directory(await library.bookStorageDirectoryPath());
      final staging = Directory('${root.path}/.import-other-engine');
      await staging.create(recursive: true);
      final partial = File('${staging.path}/book.catalog.json.importing');
      await partial.writeAsString('partial');
      await library.load();
      expect(partial.existsSync(), isTrue);
    },
  );
}
