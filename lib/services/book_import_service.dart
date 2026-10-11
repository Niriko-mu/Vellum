import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'book_importer.dart';
import 'book_library.dart';
import 'txt_catalog.dart' show scanTxtCatalogFile;

class ImportProgress {
  const ImportProgress(
    this.stage,
    this.value, {
    this.fileIndex = 0,
    this.fileCount = 1,
  });
  final String stage;
  final double? value;
  final int fileIndex;
  final int fileCount;
}

class BookImportResult {
  const BookImportResult({
    required this.book,
    required this.library,
    this.duplicate = false,
  });
  final ImportedBook book;
  final List<ImportedBook> library;
  final bool duplicate;
}

class BookImportCancelled implements Exception {
  const BookImportCancelled();
  @override
  String toString() => '已取消导入';
}

class BookImportCancellation {
  bool _cancelled = false;
  void Function()? _abort;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    _abort?.call();
  }

  void check() {
    if (_cancelled) throw const BookImportCancelled();
  }
}

class BookFileImportOutcome {
  const BookFileImportOutcome(this.filename, {this.result, this.error});
  final String filename;
  final BookImportResult? result;
  final Object? error;
}

String _safeStorageId(String id) =>
    id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
ImportedBook decodeBookInBackground(Map<String, dynamic> message) {
  final path = message['path'] as String?;
  if (path != null && File(path).lengthSync() > 200 * 1024 * 1024) {
    throw const BookImportException('文件超过 200 MB，请先拆分后重试。');
  }
  final bytes = path != null
      ? File(path).readAsBytesSync()
      : (message['bytes'] as TransferableTypedData).materialize().asUint8List();
  return const BookImporter().decode(
    filename: message['filename'] as String,
    bytes: bytes,
  );
}

Future<void> _replaceFile(
  String path,
  Future<void> Function(IOSink) write,
) async {
  final file = File(path), temp = File('$path.importing');
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

/// Interactive imports write only to a per-job staging directory.
Future<ImportedBook> decodeAndPersistBook(Map<String, dynamic> message) async {
  final port = message['progressPort'] as SendPort?;
  void stage(String text) => port?.send(ImportProgress(text, null));
  stage('正在读取文件…');
  final path = message['path'] as String?;
  final format = const BookImporter().formatForFilename(
    message['filename'] as String,
  );
  final maxBytes = format == BookFormat.txt
      ? BookImporter.maxTxtBytes
      : 200 * 1024 * 1024;
  if (path != null && await File(path).length() > maxBytes) {
    throw BookImportException('文件超过 ${maxBytes ~/ (1024 * 1024)} MB，请先拆分后重试。');
  }
  if (path != null && format == BookFormat.txt) {
    final file = File(path);
    final size = await file.length();
    if (size == 0) throw const BookImportException('文件为空。');
    stage('正在检查重复内容…');
    final id = 'txt_${await md5.bind(file.openRead()).first}';
    if ((message['existingIds'] as List<String>? ?? const []).contains(id)) {
      return ImportedBook(
        id: id,
        title: '',
        format: format,
        paragraphs: const [],
      );
    }
    if ((message['existingCount'] as int? ?? 0) >= BookImporter.maxBookCount) {
      throw const BookImportException('书架已满（上限 200 本），请先删除部分书籍。');
    }
    final root = Directory(message['storageDirectory'] as String);
    await root.create(recursive: true);
    final stem = _safeStorageId(id);
    stage('正在暂存原文件…');
    await _replaceFile('${root.path}/$stem.src', (sink) async {
      var copied = 0;
      await for (final chunk in file.openRead()) {
        copied += chunk.length;
        if (copied > maxBytes)
          throw const BookImportException('导入时文件发生变化或超过大小限制。');
        sink.add(chunk);
      }
    });
    final stagedSource = File('${root.path}/$stem.src');
    if ('txt_${await md5.bind(stagedSource.openRead()).first}' != id) {
      throw const BookImportException('导入时原文件发生变化，请重试。');
    }
    stage('正在解析章节与正文…');
    final catalog = scanTxtCatalogFile(stagedSource.path);
    if (catalog.totalParagraphs == 0)
      throw const BookImportException('文件中没有可阅读的文字。');
    final book = ImportedBook(
      id: id,
      title: const BookImporter().pipeline.titleFromFilename(
        message['filename'] as String,
      ),
      format: format,
      paragraphs: const [],
      metaParagraphCount: catalog.totalParagraphs,
      catalog: catalog,
      contentMode: 'seek',
    );
    port?.send(const ImportProgress('解析完成，正在保存目录…', 0.7));
    await _replaceFile(
      '${root.path}/$stem.catalog.json',
      (sink) async => sink.write(jsonEncode(catalog.toJson())),
    );
    port?.send(const ImportProgress('文件已保存，正在提交书架…', 0.9));
    return book.asIndexShell();
  }
  final bytes = path != null
      ? await File(path).readAsBytes()
      : (message['bytes'] as TransferableTypedData).materialize().asUint8List();
  if (bytes.isEmpty) throw const BookImportException('文件为空。');
  if (bytes.length > maxBytes)
    throw BookImportException('文件超过 ${maxBytes ~/ (1024 * 1024)} MB，请先拆分后重试。');
  stage('正在检查重复内容…');
  final id = BookLibraryIds.forBytes(bytes, format);
  if ((message['existingIds'] as List<String>? ?? const []).contains(id)) {
    if (format == BookFormat.epub) {
      final root = Directory(message['storageDirectory'] as String);
      await root.create(recursive: true);
      await _replaceFile(
        '${root.path}/${_safeStorageId(id)}.original.epub',
        (sink) async => sink.add(bytes),
      );
    }
    return ImportedBook(
      id: id,
      title: '',
      format: format,
      paragraphs: const [],
    );
  }
  if ((message['existingCount'] as int? ?? 0) >= BookImporter.maxBookCount) {
    throw const BookImportException('书架已满（上限 200 本），请先删除部分书籍。');
  }
  stage('正在解析章节与正文…');
  final book = const BookImporter().decode(
    filename: message['filename'] as String,
    bytes: bytes,
  );
  port?.send(const ImportProgress('解析完成，正在保存…', 0.7));
  final root = Directory(message['storageDirectory'] as String);
  await root.create(recursive: true);
  final stem = _safeStorageId(book.storageId);
  if (book.usesSeek) {
    await _replaceFile(
      '${root.path}/$stem.src',
      (sink) async => sink.add(bytes),
    );
    await _replaceFile(
      '${root.path}/$stem.catalog.json',
      (sink) async => sink.write(jsonEncode(book.catalog!.toJson())),
    );
  } else {
    await _replaceFile(
      '${root.path}/$stem.json',
      (sink) async => writeBookContentJson(book, sink.write),
    );
  }
  if (format == BookFormat.epub) {
    await _replaceFile(
      '${root.path}/$stem.original.epub',
      (sink) async => sink.add(bytes),
    );
  }
  port?.send(const ImportProgress('文件已保存，正在提交书架…', 0.9));
  return book.asIndexShell();
}

Future<void> _worker(Map<String, dynamic> message) async {
  final port = message['progressPort'] as SendPort;
  try {
    port.send(await decodeAndPersistBook(message));
  } catch (error) {
    port.send({'error': error.toString()});
  }
}

class BookImportService {
  const BookImportService();
  Future<BookImportResult?> importAndPersist({
    required BookLibrary library,
    required List<ImportedBook> existing,
    void Function(String)? onStage,
    void Function(ImportProgress)? onProgress,
    BookImportCancellation? cancellation,
  }) async {
    onStage?.call('正在打开文件选择器…');
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'mobi', 'txt'],
      withData: false,
    );
    if (picked == null) return null;
    return importFile(
      library: library,
      existing: existing,
      file: picked.files.single,
      cancellation: cancellation,
      onProgress: (p) {
        onStage?.call(p.stage);
        onProgress?.call(p);
      },
    );
  }

  Future<BookImportResult> importFile({
    required BookLibrary library,
    required List<ImportedBook> existing,
    required PlatformFile file,
    BookImportCancellation? cancellation,
    void Function(ImportProgress)? onProgress,
  }) async {
    final token = cancellation ?? BookImportCancellation();
    token.check();
    if (file.path == null && file.bytes == null) {
      throw const BookImportException('文件提供方没有返回可读路径。请先复制到本地后重试。');
    }
    final root = Directory(await library.bookStorageDirectoryPath());
    await root.create(recursive: true);
    final staging = await root.createTemp('.import-');
    BookLibrary.trackImportStaging(staging, active: true);
    RandomAccessFile? stagingLease;
    final port = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    Isolate? isolate;
    final completed = Completer<ImportedBook>();
    unawaited(
      completed.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    final subscription = port.listen((event) {
      if (event is ImportProgress) {
        onProgress?.call(event);
      } else if (event is ImportedBook && !completed.isCompleted) {
        completed.complete(event);
      } else if (event is Map && !completed.isCompleted) {
        completed.completeError(BookImportException(event['error'] as String));
      }
    });
    final errorSubscription = errors.listen((event) {
      if (!completed.isCompleted)
        completed.completeError(BookImportException('导入进程失败：$event'));
    });
    final exitSubscription = exits.listen((_) {
      Timer(const Duration(milliseconds: 50), () {
        if (!completed.isCompleted)
          completed.completeError(const BookImportException('导入进程意外结束。'));
      });
    });
    token._abort = () {
      isolate?.kill(priority: Isolate.immediate);
      if (!completed.isCompleted)
        completed.completeError(const BookImportCancelled());
    };
    try {
      stagingLease = await File(
        '${staging.path}/.lease',
      ).open(mode: FileMode.append);
      await stagingLease.lock(FileLock.exclusive);
      isolate = await Isolate.spawn(
        _worker,
        <String, dynamic>{
          'filename': file.name,
          'storageDirectory': staging.path,
          'progressPort': port.sendPort,
          'existingIds': [for (final book in existing) book.storageId],
          'existingCount': existing.length,
          if (file.path != null)
            'path': file.path
          else
            'bytes': TransferableTypedData.fromList([file.bytes!]),
        },
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      if (token.isCancelled) token._abort?.call();
      final book = await completed.future;
      token.check();
      final matches = existing.where(
        (item) => item.storageId == book.storageId,
      );
      if (matches.isNotEmpty) {
        if (book.format == BookFormat.epub) {
          token._abort = null;
          final stagedOriginal = File(
            '${staging.path}/${_safeStorageId(book.storageId)}.original.epub',
          );
          final original = File(await library.originalEpubPath(book.storageId));
          if (!await original.exists() && await stagedOriginal.exists()) {
            await stagedOriginal.rename(original.path);
          }
        }
        onProgress?.call(const ImportProgress('已在书架，保留原有设置与进度', 1));
        return BookImportResult(
          book: matches.first,
          library: existing,
          duplicate: true,
        );
      }
      // Publication is a short, non-cancellable critical section. A late
      // cancellation stops the next file without tearing this book in half.
      token._abort = null;
      final updated = await library.commitImport(book, staging, existing);
      final stored = updated.firstWhere(
        (item) => item.storageId == book.storageId,
      );
      onProgress?.call(const ImportProgress('导入完成', 1));
      return BookImportResult(
        book: stored,
        library: updated,
        duplicate: !identical(stored, book),
      );
    } finally {
      token._abort = null;
      isolate?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      port.close();
      errors.close();
      exits.close();
      await stagingLease?.close();
      if (await staging.exists()) await staging.delete(recursive: true);
      BookLibrary.trackImportStaging(staging, active: false);
    }
  }

  Future<List<ImportedBook>> importFiles({
    required BookLibrary library,
    required List<ImportedBook> existing,
    required List<PlatformFile> files,
    BookImportCancellation? cancellation,
    void Function(ImportProgress)? onProgress,
    void Function(BookFileImportOutcome)? onFileResult,
  }) async {
    final token = cancellation ?? BookImportCancellation();
    var current = existing;
    for (var i = 0; i < files.length; i++) {
      if (token.isCancelled) break;
      try {
        final result = await importFile(
          library: library,
          existing: current,
          file: files[i],
          cancellation: token,
          onProgress: (p) => onProgress?.call(
            ImportProgress(
              '${files[i].name}：${p.stage}',
              p.value,
              fileIndex: i,
              fileCount: files.length,
            ),
          ),
        );
        current = result.library;
        onFileResult?.call(
          BookFileImportOutcome(files[i].name, result: result),
        );
      } catch (error) {
        onFileResult?.call(BookFileImportOutcome(files[i].name, error: error));
        if (error is BookImportCancelled) break;
      }
    }
    return current;
  }

  Future<List<ImportedBook>> persistImportedIndex(
    BookLibrary library,
    List<ImportedBook> existing,
    ImportedBook book,
  ) async {
    if (existing.any((item) => item.storageId == book.storageId))
      return existing;
    if (existing.length >= BookImporter.maxBookCount)
      throw const BookImportException('书架已满，请先删除部分书籍。');
    final updated = [book, ...existing];
    await library.saveIndex(updated);
    return updated;
  }
}
