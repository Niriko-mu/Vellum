import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show TransferableTypedData;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;

import 'book_importer.dart';
import 'book_library.dart';

class ImportProgress {
  const ImportProgress(this.stage, this.value);
  final String stage;
  final double value;
}

class BookImportResult {
  const BookImportResult({required this.book, required this.library});

  final ImportedBook book;
  final List<ImportedBook> library;
}

String _safeStorageId(String id) =>
    id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

ImportedBook decodeBookInBackground(Map<String, dynamic> message) {
  final path = message['path'] as String?;
  final source = message['bytes'];
  final bytes = path != null
      ? File(path).readAsBytesSync()
      : (source as TransferableTypedData).materialize().asUint8List();
  return const BookImporter().decode(
    filename: message['filename'] as String,
    bytes: bytes,
  );
}

Future<void> _replaceFile(
  String path,
  Future<void> Function(IOSink sink) write,
) async {
  final file = File(path);
  final temp = File('$path.importing');
  final sink = temp.openWrite();
  try {
    await write(sink);
    await sink.flush();
  } finally {
    await sink.close();
  }
  if (await file.exists()) await file.delete();
  await temp.rename(path);
}

/// Decodes and persists one book entirely inside a worker isolate.
///
/// Returning the full [ImportedBook] from the decode isolate and then sending
/// it to another writer isolate copied a multi-megabyte paragraph list twice
/// through the UI isolate. Large imports looked frozen during those copies.
/// This entry point writes the book first and returns only its shelf shell.
Future<ImportedBook> decodeAndPersistBook(Map<String, dynamic> message) async {
  final path = message['path'] as String?;
  final source = message['bytes'];
  final bytes = path != null
      ? File(path).readAsBytesSync()
      : (source as TransferableTypedData).materialize().asUint8List();
  final decoded = const BookImporter().decode(
    filename: message['filename'] as String,
    bytes: bytes,
  );
  final book = decoded.copyWith(
    id: BookLibraryIds.forBytes(bytes, decoded.format),
  );
  final root = Directory(message['storageDirectory'] as String);
  await root.create(recursive: true);
  final stem = _safeStorageId(book.storageId);
  final contentPath = '${root.path}${Platform.pathSeparator}$stem.json';
  final sourcePath = '${root.path}${Platform.pathSeparator}$stem.src';
  final catalogPath = '${root.path}${Platform.pathSeparator}$stem.catalog.json';

  if (book.usesSeek) {
    await _replaceFile(sourcePath, (sink) async {
      sink.add(bytes);
    });
    final catalog = book.catalog;
    if (catalog != null) {
      await _replaceFile(catalogPath, (sink) async {
        sink.write(jsonEncode(catalog.toJson()));
      });
    }
  } else {
    await _replaceFile(contentPath, (sink) async {
      writeBookContentJson(book, sink.write);
    });
  }
  return book.asIndexShell();
}

/// Picks an ebook file and imports it without moving its body through the UI
/// isolate.
class BookImportService {
  const BookImportService();

  Future<BookImportResult?> importAndPersist({
    required BookLibrary library,
    required List<ImportedBook> existing,
    void Function(String stage)? onStage,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    void report(String stage, double value) {
      onStage?.call(stage);
      onProgress?.call(ImportProgress(stage, value));
    }

    report('正在打开文件选择器…', 0.05);
    await Future<void>.delayed(Duration.zero);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'mobi', 'txt'],
      withData: false,
    );
    if (result == null) return null;
    final file = result.files.single;
    final path = file.path;
    final bytes = file.bytes;
    if (path == null && bytes == null) {
      throw const BookImportException('文件提供方没有返回可读路径。请将电子书复制到本地磁盘后重试。');
    }
    if (file.size > 8 * 1024 * 1024) {
      onStage?.call('正在解析并保存大型电子书，可能需要一些时间…');
    }
    report('正在读取《${file.name}》…', 0.2);
    await Future<void>.delayed(Duration.zero);
    report('正在解析并保存《${file.name}》…', 0.45);
    await Future<void>.delayed(Duration.zero);

    final book = await compute(decodeAndPersistBook, <String, dynamic>{
      'filename': file.name,
      'storageDirectory': await library.bookStorageDirectoryPath(),
      if (path != null)
        'path': path
      else
        'bytes': TransferableTypedData.fromList([bytes!]),
    });
    report('解析完成，共 ${book.paragraphCount} 段', 0.85);
    final updated = await persistImportedIndex(library, existing, book);
    return BookImportResult(book: book, library: updated);
  }

  /// Replaces an existing entry with the same content id and refreshes the
  /// lightweight shelf index. The book body was already persisted by the
  /// import worker, so it is never copied back through the UI isolate.
  Future<List<ImportedBook>> persistImportedIndex(
    BookLibrary library,
    List<ImportedBook> existing,
    ImportedBook book,
  ) async {
    final incomingId = book.storageId;
    final updatedBooks = <ImportedBook>[
      book,
      for (final item in existing)
        if (item.storageId != incomingId) item,
    ];
    if (updatedBooks.length > BookImporter.maxBookCount) {
      throw const BookImportException(
        '书架已满（上限 ${BookImporter.maxBookCount} 本），请先删除部分书籍。',
      );
    }
    await library.saveIndex(updatedBooks);
    return updatedBooks;
  }
}
