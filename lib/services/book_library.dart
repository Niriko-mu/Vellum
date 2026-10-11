import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

import 'book_importer.dart';
import 'font_storage.dart';
import 'reader_background.dart';
import 'tts_cache.dart';
import 'library_models.dart';
import 'txt_catalog.dart';
import 'txt_seek_source.dart';
import 'book_search.dart';
import 'library_file_mutex.dart';

export 'font_storage.dart';
export 'library_models.dart';
export 'txt_catalog.dart' show TxtCatalog, TxtCatalogStatus, TxtChapterRef;

/// Size of the JSON fragments streamed to disk by [writeBookContentJson].
const _jsonChunkSize = 1 << 20;

/// Streams one book's content JSON through [write] in ~1 MB chunks.
///
/// Hand-rolled instead of `jsonEncode` so a large book never has to exist as a
/// single string, which keeps memory flat and lets the write start immediately.
/// Key order and shape must stay in sync with [_decodeBookContent].
void writeBookContentJson(
  ImportedBook book,
  void Function(String chunk) write,
) {
  final buffer = StringBuffer();

  void flush({bool force = false}) {
    if (buffer.isEmpty) return;
    if (!force && buffer.length < _jsonChunkSize) return;
    write(buffer.toString());
    buffer.clear();
  }

  buffer
    ..write('{"id":')
    ..write(jsonEncode(book.storageId))
    ..write(',"title":')
    ..write(jsonEncode(book.title))
    ..write(',"format":')
    ..write(jsonEncode(book.format.name))
    ..write(',"paragraphs":[');
  var first = true;
  for (final paragraph in book.paragraphs) {
    if (first) {
      first = false;
    } else {
      buffer.write(',');
    }
    buffer.write(jsonEncode(paragraph));
    flush();
  }
  buffer.write('],"linkTargets":{');
  first = true;
  for (final entry in book.linkTargets.entries) {
    if (first) {
      first = false;
    } else {
      buffer.write(',');
    }
    buffer
      ..write(jsonEncode(entry.key.toString()))
      ..write(':')
      ..write(entry.value.toString());
  }
  buffer.write('},"tocEntries":[');
  first = true;
  for (final entry in book.tocEntries) {
    if (first) {
      first = false;
    } else {
      buffer.write(',');
    }
    buffer
      ..write('{"title":')
      ..write(jsonEncode(entry.title))
      ..write(',"paragraphIndex":')
      ..write(entry.paragraphIndex.toString())
      ..write('}');
  }
  buffer.write('],"imageBytes":{');
  first = true;
  for (final entry in book.imageBytes.entries) {
    if (first) {
      first = false;
    } else {
      buffer.write(',');
    }
    buffer
      ..write(jsonEncode(entry.key.toString()))
      ..write(':"')
      ..write(base64Encode(entry.value))
      ..write('"');
    flush();
  }
  buffer.write('}}');
  flush(force: true);
}

Map<String, dynamic> _bookIndexJson(ImportedBook book) => {
  'id': book.storageId,
  'title': book.title,
  'author': book.author,
  'format': book.format.name,
  'paragraphCount': book.paragraphCount,
  'cover': book.coverBytes == null ? null : base64Encode(book.coverBytes!),
  'coverText': book.coverText,
  'folderId': book.folderId,
  'contentMode': book.contentMode,
  if (book.catalog != null) 'catalog': book.catalog!.toJson(),
};

String _encodeLibraryIndex(List<ImportedBook> books) =>
    jsonEncode([for (final book in books) _bookIndexJson(book)]);

/// Isolate entry point: streams a book's content JSON straight into its file.
Future<int> _writeBookContentFile(Map<String, dynamic> message) async {
  final file = File(message['path'] as String);
  final book = message['book'] as ImportedBook;
  final sink = file.openWrite();
  try {
    writeBookContentJson(book, sink.write);
    await sink.flush();
  } finally {
    await sink.close();
  }
  return file.lengthSync();
}

ImportedBook _decodeIndexEntry(Map<String, dynamic> data) => ImportedBook(
  id: data['id'] as String?,
  title: data['title'] as String,
  author: data['author'] as String? ?? '',
  format: BookFormat.values.byName(data['format'] as String),
  paragraphs: const [],
  metaParagraphCount: (data['paragraphCount'] as num?)?.toInt() ?? 0,
  coverBytes: data['cover'] == null
      ? null
      : Uint8List.fromList(base64Decode(data['cover'] as String)),
  coverText: data['coverText'] as String?,
  folderId: data['folderId'] as String?,
  contentMode: data['contentMode'] as String? ?? 'inline',
  catalog: data['catalog'] == null
      ? null
      : TxtCatalog.fromJson(data['catalog'] as Map<String, dynamic>),
);

ImportedBook _decodeBookContent(Map<String, dynamic> data) {
  final paragraphs = (data['paragraphs'] as List<dynamic>? ?? [])
      .cast<String>();
  return ImportedBook(
    id: data['id'] as String?,
    title: data['title'] as String,
    author: data['author'] as String? ?? '',
    format: BookFormat.values.byName(data['format'] as String),
    paragraphs: paragraphs,
    coverBytes: data['cover'] == null
        ? null
        : Uint8List.fromList(base64Decode(data['cover'] as String)),
    linkTargets: (data['linkTargets'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(int.parse(key), value as int),
    ),
    tocEntries: (data['tocEntries'] as List<dynamic>? ?? [])
        .map(
          (entry) => BookTocEntry(
            title: (entry as Map<String, dynamic>)['title'] as String,
            paragraphIndex: entry['paragraphIndex'] as int,
          ),
        )
        .toList(),
    imageBytes: (data['imageBytes'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(
        int.parse(key),
        Uint8List.fromList(base64Decode(value as String)),
      ),
    ),
  );
}

/// JSON decoding is CPU-heavy for large novels. Keep it off the UI isolate so
/// the reader can present its chrome and loading state while the body is being
/// materialized.
ImportedBook _decodeBookContentJson(String raw) =>
    _decodeBookContent(jsonDecode(raw) as Map<String, dynamic>);

/// Reads and decodes a content file inside the worker isolate.
ImportedBook _loadBookContentFile(String path) =>
    _decodeBookContentJson(File(path).readAsStringSync());

Future<TxtCatalog> _migrateTxtCatalog(String path) async =>
    scanTxtCatalogFile(path);

class BookLibrary {
  static Future<void> _commitTail = Future<void>.value();
  static Future<void> _indexTail = Future<void>.value();
  static final Set<String> _activeCommits = {};
  static final Set<String> _activeStaging = {};

  static void trackImportStaging(Directory directory, {required bool active}) {
    if (active) {
      _activeStaging.add(directory.path);
    } else {
      _activeStaging.remove(directory.path);
    }
  }

  const BookLibrary({this.fonts = const FontStorage()});

  final FontStorage fonts;

  Future<T> _locked<T>(Future<T> Function() operation) async {
    final file = await _file();
    return LibraryFileMutex.run('${file.path}.lock', operation);
  }

  Future<List<ImportedBook>> load() => _locked(_load);

  Future<List<ImportedBook>> _load() async {
    await _indexTail;
    final file = await _file();
    await _recoverIndex(file);
    await recoverImports();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return [];
      List<ImportedBook> books;
      if (raw.isNotEmpty && raw.first is Map<String, dynamic>) {
        final first = raw.first as Map<String, dynamic>;
        if (first.containsKey('paragraphs')) {
          books = [
            for (final entry in raw)
              _decodeBookContent(entry as Map<String, dynamic>),
          ];
          books = _ensureUniqueBookIds(books);
          await save(books);
          return [for (final book in books) book.asIndexShell()];
        }
      }
      books = [
        for (final entry in raw)
          _decodeIndexEntry(entry as Map<String, dynamic>),
      ];
      final repaired = _ensureUniqueBookIds(books);
      if (!_sameBookIds(books, repaired)) {
        await saveIndex(repaired);
      }
      return repaired;
    } catch (_) {
      return [];
    }
  }

  bool _sameBookIds(List<ImportedBook> a, List<ImportedBook> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].storageId != b[i].storageId) return false;
    }
    return true;
  }

  /// Repairs ids from the broken interpolation era and any accidental
  /// collisions so each shelf item maps to its own content file.
  List<ImportedBook> _ensureUniqueBookIds(List<ImportedBook> books) {
    final seen = <String>{};
    final result = <ImportedBook>[];
    for (final book in books) {
      final id = book.id;
      final usable =
          id != null && id.isNotEmpty && !BookLibraryIds.isLegacyBrokenId(id);
      if (usable && seen.add(id)) {
        result.add(book);
        continue;
      }
      final base = BookLibraryIds.forBook(book);
      var candidate = base;
      var suffix = 1;
      while (!seen.add(candidate)) {
        candidate = '${base}_$suffix';
        suffix++;
      }
      result.add(book.copyWith(id: candidate));
    }
    return result;
  }

  Future<ImportedBook> loadBookContent(ImportedBook book) async {
    if (book.paragraphs is TxtParagraphList) return book;
    if (book.hasContentLoaded && !book.usesSeek) return book;

    // Seek-mode TXT: rebuild a paragraph list from catalog + source file.
    if (book.contentMode == 'seek' || book.catalog != null) {
      var catalog = book.catalog;
      final catFile = await _bookCatalogFile(book.storageId);
      if (catalog == null && await catFile.exists()) {
        try {
          catalog = TxtCatalog.fromJson(
            jsonDecode(await catFile.readAsString()) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
      final src = await _bookSourceFile(book.storageId);
      if (catalog != null && await src.exists()) {
        if (catalog.chapters.any(
          (chapter) => chapter.byteLength > 256 * 1024,
        )) {
          catalog = await compute(_migrateTxtCatalog, src.path);
          final temp = File('${catFile.path}.next');
          await temp.writeAsString(jsonEncode(catalog.toJson()), flush: true);
          if (await catFile.exists()) await catFile.delete();
          await temp.rename(catFile.path);
          // Persist revised counts in the shell; source bytes and storage id
          // remain unchanged, preserving book identity and reading metadata.
          final shelf = await load();
          await saveIndex([
            for (final item in shelf)
              if (item.storageId == book.storageId)
                item.copyWith(
                  catalog: catalog,
                  metaParagraphCount: catalog.totalParagraphs,
                )
              else
                item,
          ]);
        }
        final source = TxtSeekSource(file: src, catalog: catalog);
        return book.copyWith(
          paragraphs: TxtParagraphList(source),
          catalog: catalog,
          contentMode: 'seek',
          tocEntries: [
            for (final entry in catalog.tocEntries)
              BookTocEntry(title: entry.value, paragraphIndex: entry.key),
          ],
        );
      }
    }

    if (book.hasContentLoaded) return book;
    final file = await _bookContentFile(book.storageId);
    if (await file.exists()) {
      try {
        final full = await compute(_loadBookContentFile, file.path);
        registerBookSearchPath(full.paragraphs, file.path);
        // Content files do not carry shelf cover; keep the index shell's cover.
        return full.copyWith(
          coverBytes: book.coverBytes,
          coverText: book.coverText,
          folderId: book.folderId,
        );
      } catch (_) {}
    }
    return book;
  }

  /// Updates only the shelf cover (image and/or text) and rewrites the index.
  Future<void> updateBookCover(
    ImportedBook book, {
    Uint8List? coverBytes,
    String? coverText,
    bool clearCoverImage = false,
    bool clearCoverText = false,
  }) async {
    final updated = book.copyWith(
      coverBytes: coverBytes,
      coverText: coverText,
      clearCoverImage: clearCoverImage,
      clearCoverText: clearCoverText,
    );
    final books = await load();
    final next = <ImportedBook>[
      for (final item in books)
        item.storageId == updated.storageId ? updated : item,
    ];
    if (!next.any((item) => item.storageId == updated.storageId)) {
      next.insert(0, updated);
    }
    // Rewrite index without loading every book body.
    await saveIndex(next);
  }

  Future<List<LibraryFolder>> loadFolders() async {
    final file = await _foldersFile();
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return [
        for (final entry in raw)
          LibraryFolder(
            id: entry['id'] as String,
            name: entry['name'] as String,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<LibraryFolder> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const BookImportException('文件夹名称不能为空。');
    }
    final folders = await loadFolders();
    final folder = LibraryFolder(
      id: 'f_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
    );
    await _writeFolders([...folders, folder]);
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final folders = await loadFolders();
    await _writeFolders([
      for (final folder in folders)
        if (folder.id == id)
          LibraryFolder(id: folder.id, name: trimmed)
        else
          folder,
    ]);
  }

  Future<void> deleteFolder(String id) async {
    final folders = await loadFolders();
    await _writeFolders([
      for (final folder in folders)
        if (folder.id != id) folder,
    ]);
    final books = await load();
    final next = <ImportedBook>[
      for (final book in books)
        if (book.folderId == id) book.copyWith(clearFolder: true) else book,
    ];
    await saveIndex(next);
  }

  Future<void> setBookFolder(ImportedBook book, String? folderId) async {
    final updated = folderId == null
        ? book.copyWith(clearFolder: true)
        : book.copyWith(folderId: folderId);
    final books = await load();
    final next = <ImportedBook>[
      for (final item in books)
        item.storageId == updated.storageId ? updated : item,
    ];
    if (!next.any((item) => item.storageId == updated.storageId)) {
      next.insert(0, updated);
    }
    await saveIndex(next);
  }

  Future<void> _writeFolders(List<LibraryFolder> folders) async {
    await (await _foldersFile()).writeAsString(
      jsonEncode([
        for (final folder in folders) {'id': folder.id, 'name': folder.name},
      ]),
      flush: true,
    );
  }

  /// Empty string means the built-in default update repository.
  Future<String> loadUpdateRepository() async {
    final file = await _updateRepoFile();
    if (!await file.exists()) return '';
    try {
      final raw = (await file.readAsString()).trim();
      return raw;
    } catch (_) {
      return '';
    }
  }

  Future<void> saveUpdateRepository(String repository) async {
    await (await _updateRepoFile()).writeAsString(
      repository.trim(),
      flush: true,
    );
  }

  /// Whether entering the app should check for updates. On unless turned off.
  Future<bool> loadAutoUpdateCheck() async {
    final file = await _autoUpdateFile();
    if (!await file.exists()) return true;
    try {
      return (await file.readAsString()).trim() != '0';
    } catch (_) {
      return true;
    }
  }

  Future<void> saveAutoUpdateCheck(bool enabled) async {
    await (await _autoUpdateFile()).writeAsString(
      enabled ? '1' : '0',
      flush: true,
    );
  }

  Future<void> save(List<ImportedBook> books) async {
    final directory = await _booksDir();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final fullBooks = <ImportedBook>[];
    for (final book in books) {
      fullBooks.add(book.hasContentLoaded ? book : await loadBookContent(book));
    }
    await Future.wait([for (final book in fullBooks) saveBookContent(book)]);
    await saveIndex(fullBooks);
  }

  /// Writes a single book's content file off the UI isolate.
  ///
  /// Import uses this instead of [save] so adding one book never re-encodes
  /// the rest of the library.
  ///
  /// Seek-mode TXT books persist a raw source file + catalog sidecar instead
  /// of a full paragraphs JSON (Fanqie keeps the original file and seeks).
  Future<void> saveBookContent(ImportedBook book) async {
    final dir = await _booksDir();
    if (!await dir.exists()) await dir.create(recursive: true);

    if (book.contentMode == 'seek') {
      final src = await _bookSourceFile(book.storageId);
      final paras = book.paragraphs;
      if (paras is InMemoryTxtParagraphList) {
        await src.writeAsBytes(paras.bytes, flush: true);
      } else if (paras is TxtParagraphList) {
        final existing = paras.source.file;
        if (existing.path != src.path && await existing.exists()) {
          await existing.copy(src.path);
        }
      }
      final catalog = book.catalog;
      if (catalog != null) {
        final catFile = await _bookCatalogFile(book.storageId);
        await catFile.writeAsString(jsonEncode(catalog.toJson()), flush: true);
      }
      return;
    }

    final file = await _bookContentFile(book.storageId);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await compute(_writeBookContentFile, <String, dynamic>{
      'path': file.path,
      'book': book,
    });
  }

  /// Rewrites only the lightweight shelf index (titles, covers, counts).
  Future<void> saveIndex(List<ImportedBook> books) =>
      _locked(() => _queueIndex(books));

  Future<void> _queueIndex(List<ImportedBook> books) async {
    final previous = _indexTail;
    final done = Completer<void>();
    _indexTail = done.future;
    await previous;
    try {
      await _saveIndex(books);
    } finally {
      done.complete();
    }
  }

  Future<void> _saveIndex(List<ImportedBook> books) async {
    final index = await compute(_encodeLibraryIndex, books);
    final file = await _file();
    await _recoverIndex(file);
    final temporary = File('${file.path}.next');
    final backup = File('${file.path}.backup');
    await temporary.writeAsString(index, flush: true);
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
      try {
        if (await backup.exists()) await backup.delete();
      } on FileSystemException {
        // Publication succeeded; startup will retry obsolete-backup cleanup.
      }
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<void> _recoverIndex(File file) async {
    final backup = File('${file.path}.backup');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    } else if (await backup.exists()) {
      try {
        if (jsonDecode(await file.readAsString()) is! List) {
          throw const FormatException('Invalid shelf index');
        }
        await backup.delete();
      } on FormatException {
        Object? backupData;
        try {
          backupData = jsonDecode(await backup.readAsString());
        } on FormatException {
          return;
        }
        if (backupData is List) {
          final corrupt = File('${file.path}.corrupt');
          if (await corrupt.exists()) await corrupt.delete();
          await file.rename(corrupt.path);
          await backup.rename(file.path);
        }
      }
    }
  }

  /// Promotes staged body files before publishing their shell in the index.
  /// A journal permits startup to remove files from interrupted commits.
  Future<List<ImportedBook>> commitImport(
    ImportedBook book,
    Directory staging,
    List<ImportedBook> fallback,
  ) => _locked(() => _queueCommit(book, staging, fallback));

  Future<List<ImportedBook>> _queueCommit(
    ImportedBook book,
    Directory staging,
    List<ImportedBook> fallback,
  ) async {
    final previous = _commitTail;
    final done = Completer<void>();
    _commitTail = done.future;
    await previous;
    try {
      return await _commitImport(book, staging, fallback);
    } finally {
      done.complete();
    }
  }

  Future<List<ImportedBook>> _commitImport(
    ImportedBook book,
    Directory staging,
    List<ImportedBook> fallback,
  ) async {
    final indexFile = await _file();
    final current = await indexFile.exists() ? await load() : fallback;
    if (current.any((item) => item.storageId == book.storageId)) return current;
    if (current.length >= BookImporter.maxBookCount) {
      throw const BookImportException('书架已满，请先删除部分书籍。');
    }
    final root = await _booksDir();
    await root.create(recursive: true);
    final files = await staging
        .list()
        .where((e) => e is File && e.uri.pathSegments.last != '.lease')
        .cast<File>()
        .toList();
    final journal = File(
      '${root.path}${Platform.pathSeparator}.import-journal.json',
    );
    final names = [for (final f in files) f.uri.pathSegments.last];
    await journal.writeAsString(
      jsonEncode({'id': book.storageId, 'files': names}),
      flush: true,
    );
    _activeCommits.add(root.path);
    try {
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final target = File('${root.path}${Platform.pathSeparator}$name');
        // No indexed file is overwritten: duplicate imports return above.
        if (await target.exists()) await target.delete();
        await file.rename(target.path);
      }
      final updated = [book, ...current];
      await saveIndex(updated);
      try {
        await journal.delete();
      } on FileSystemException {
        // The published index is authoritative. Startup can remove the marker.
      }
      return updated;
    } catch (_) {
      _activeCommits.remove(root.path);
      await recoverImports();
      rethrow;
    } finally {
      _activeCommits.remove(root.path);
    }
  }

  Future<void> recoverImports() => _locked(_recoverImports);

  Future<void> _recoverImports() async {
    final root = await _booksDir();
    if (_activeCommits.contains(root.path)) return;
    if (await root.exists()) {
      await for (final entry in root.list()) {
        if (entry is Directory &&
            entry.uri.pathSegments
                .where((e) => e.isNotEmpty)
                .last
                .startsWith('.import-') &&
            !_activeStaging.contains(entry.path)) {
          final lease = File('${entry.path}${Platform.pathSeparator}.lease');
          final modified = await lease.exists()
              ? (await lease.stat()).modified
              : (await entry.stat()).modified;
          // Engine-local statics cannot establish ownership in another engine.
          // Fresh work is never treated as abandoned; old work additionally
          // needs an uncontended OS lease before startup can reclaim it.
          if (DateTime.now().difference(modified) < const Duration(hours: 24))
            continue;
          RandomAccessFile? handle;
          try {
            handle = await lease.open(mode: FileMode.append);
            await handle.lock(FileLock.exclusive);
            await handle.close();
            handle = null;
            await entry.delete(recursive: true);
          } on FileSystemException {
            // Another process still owns the lease, or cleanup can be retried.
          } finally {
            await handle?.close();
          }
        }
      }
    }
    final journal = File(
      '${root.path}${Platform.pathSeparator}.import-journal.json',
    );
    if (!await journal.exists()) return;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(await journal.readAsString());
      if (decoded is! Map<String, dynamic>)
        throw const FormatException('Invalid import journal');
      data = decoded;
      if (data['id'] is! String || data['files'] is! List)
        throw const FormatException('Invalid import journal');
    } on FormatException {
      // A truncated write precedes file promotion. Keep unknown body files,
      // rather than infer targets from an incomplete journal.
      await journal.delete();
      return;
    }
    final index = await _file();
    await _recoverIndex(index);
    List raw;
    try {
      final decoded = await index.exists()
          ? jsonDecode(await index.readAsString())
          : const [];
      if (decoded is! List) return;
      raw = decoded;
    } on FormatException {
      // Unknown index state: preserve files rather than delete possibly indexed
      // books. load() can still apply its existing corrupt-index fallback.
      return;
    }
    final committed = raw.any((e) => e is Map && e['id'] == data['id']);
    if (!committed) {
      for (final value in data['files'] as List) {
        if (value is! String) continue;
        final name = value;
        final stem = (data['id'] as String).replaceAll(
          RegExp(r'[^a-zA-Z0-9_\-]'),
          '_',
        );
        if (!{
          '$stem.src',
          '$stem.json',
          '$stem.catalog.json',
          '$stem.original.epub',
        }.contains(name))
          continue;
        final file = File('${root.path}${Platform.pathSeparator}$name');
        if (await file.exists()) await file.delete();
      }
    }
    await journal.delete();
  }

  /// Original EPUB retained for the renderer, independent of paragraph JSON.
  Future<String> originalEpubPath(String storageId) async {
    final root = await _booksDir();
    final safe = storageId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '${root.path}${Platform.pathSeparator}$safe.original.epub';
  }

  Future<void> deleteBook(ImportedBook book) =>
      _locked(() => _deleteBook(book));

  Future<void> _deleteBook(ImportedBook book) async {
    final original = File(await originalEpubPath(book.storageId));
    for (final suffix in ['.reader.json', '.reader.json.tmp']) {
      final state = File('${original.path}$suffix');
      if (await state.exists()) await state.delete();
    }
    if (await original.exists()) await original.delete();
    final content = await _bookContentFile(book.storageId);
    if (await content.exists()) await content.delete();
    final src = await _bookSourceFile(book.storageId);
    if (await src.exists()) await src.delete();
    final cat = await _bookCatalogFile(book.storageId);
    if (await cat.exists()) await cat.delete();
  }

  /// Display settings that live in the shared preferences file.
  ReadingState _displayState(ReaderPreferences prefs) => ReadingState(
    fontSize: prefs.fontSize,
    readerFontFamily: prefs.readerFontFamily,
    readerFontWeight: prefs.readerFontWeight,
    lineSpacing: prefs.lineSpacing,
    backgroundValue: prefs.backgroundValue,
    mode: prefs.mode,
    pageTurn: prefs.pageTurn,
    brightness: prefs.brightness,
    eyeCare: prefs.eyeCare,
    keepScreenOn: prefs.keepScreenOn,
    volumeKeys: prefs.volumeKeys,
  );

  /// Display settings stay global; only progress and bookmarks are per book.
  ReadingState _mergeProgress(ReadingState display, ReadingState saved) =>
      ReadingState(
        fontSize: display.fontSize,
        readerFontFamily: display.readerFontFamily,
        readerFontWeight: display.readerFontWeight,
        lineSpacing: display.lineSpacing,
        backgroundValue: display.backgroundValue,
        mode: display.mode,
        pageTurn: display.pageTurn,
        brightness: display.brightness,
        eyeCare: display.eyeCare,
        keepScreenOn: display.keepScreenOn,
        volumeKeys: display.volumeKeys,
        position: saved.position,
        page: saved.page,
        paragraphIndex: saved.paragraphIndex,
        bookmarks: saved.bookmarks,
        chapterPositions: saved.chapterPositions,
        bookId: display.bookId,
      );

  Future<ReadingState> loadReadingState(ImportedBook book) async {
    final prefs = await loadReaderPreferences();
    final display = _displayState(prefs).copyWith(bookId: book.storageId);
    final file = await _stateFile();
    if (!await file.exists()) return display;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final value = raw[_key(book)];
      if (value is! Map<String, dynamic>) return display;
      return _mergeProgress(display, ReadingState.fromJson(value));
    } catch (_) {
      return display;
    }
  }

  Future<void> saveReadingState(ImportedBook book, ReadingState state) async {
    await saveReaderPreferences(
      ReaderPreferences(
        fontSize: state.fontSize,
        readerFontFamily: state.readerFontFamily,
        readerFontWeight: state.readerFontWeight,
        lineSpacing: state.lineSpacing,
        backgroundValue: state.backgroundValue,
        mode: state.mode,
        pageTurn: state.pageTurn,
        brightness: state.brightness,
        eyeCare: state.eyeCare,
        keepScreenOn: state.keepScreenOn,
        volumeKeys: state.volumeKeys,
      ),
    );
    final file = await _stateFile();
    Map<String, dynamic> states = {};
    if (await file.exists()) {
      try {
        states =
            (jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        states = {};
      }
    }
    // Progress only — display prefs live in the shared preferences file.
    states[_key(book)] = {
      'position': state.position,
      'page': state.page,
      'paragraphIndex': state.paragraphIndex,
      'bookmarks': state.bookmarks,
      'bookId': book.storageId,
      'chapterPositions': {
        for (final entry in state.chapterPositions.entries)
          entry.key.toString(): entry.value.toJson(),
      },
    };
    await file.writeAsString(jsonEncode(states));
  }

  Future<ReaderPreferences> loadReaderPreferences() async {
    try {
      final file = await _prefsFile();
      if (!await file.exists()) return const ReaderPreferences();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        final prefs = ReaderPreferences.fromJson(raw);
        final aligned = alignedReaderPreferences(prefs);
        if (identical(aligned, prefs)) return prefs;
        // Persist immediately so the scale is applied once, not per launch.
        await saveReaderPreferences(aligned);
        return aligned;
      }
    } catch (_) {}
    return const ReaderPreferences();
  }

  Future<void> saveReaderPreferences(ReaderPreferences prefs) async {
    final file = await _prefsFile();
    await file.writeAsString(jsonEncode(prefs.toJson()), flush: true);
  }

  Future<void> deleteReadingState(ImportedBook book) async {
    final file = await _stateFile();
    if (!await file.exists()) return;
    try {
      final states =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      states.remove(_key(book));
      await file.writeAsString(jsonEncode(states));
    } catch (_) {}
  }

  Future<Uint8List?> loadFont() => fonts.loadFont();
  Future<void> saveFont(Uint8List bytes) => fonts.saveFont(bytes);

  Future<StorageUsage> storageUsage() async {
    final directory = await _booksDir();
    var libraryBytes = 0;
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) libraryBytes += await entity.length();
      }
    }
    final index = await _file();
    if (await index.exists()) libraryBytes += await index.length();
    final stateFile = await _stateFile();
    final fontFile = await fonts.fontFile();
    return StorageUsage(
      libraryBytes: libraryBytes,
      readingStateBytes: await stateFile.exists()
          ? await stateFile.length()
          : 0,
      fontBytes: await fontFile.exists() ? await fontFile.length() : 0,
      backgroundBytes: await const ReaderBackgroundStore().sizeInBytes(),
      ttsBytes: await const TtsCache().sizeInBytes(),
    );
  }

  String bookAsPlainText(ImportedBook book) {
    final marker = RegExp(
      r'^\[\[vellum-(?:heading:[1-6]|quote|list|center)\]\]+',
    );
    final image = RegExp(r'\[\[image:\d+\]\]');
    final inline = RegExp(r'\[\[/?[biu]\]\]');
    return book.paragraphs
        .map(
          (paragraph) => paragraph
              .replaceFirst(marker, '')
              .replaceAll(image, '')
              .replaceAll(inline, '')
              .trim(),
        )
        .where((paragraph) => paragraph.isNotEmpty)
        .join('\n\n');
  }

  String suggestedTxtFilename(ImportedBook book) {
    final safeTitle = book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return safeTitle.isEmpty ? 'book.txt' : '$safeTitle.txt';
  }

  Future<File> exportAsTxt(ImportedBook book, {String? outputPath}) async {
    final text = bookAsPlainText(book);
    if (outputPath != null && outputPath.isNotEmpty) {
      final file = File(outputPath);
      final parent = file.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      await file.writeAsString(text, encoding: utf8, flush: true);
      return file;
    }
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_exports',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${suggestedTxtFilename(book)}',
    );
    await file.writeAsString(text, encoding: utf8, flush: true);
    return file;
  }

  Future<void> clearBooks() => _locked(_clearBooks);

  Future<void> _clearBooks() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final directory = await _booksDir();
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) await entity.delete();
      }
    }
  }

  Future<void> clearReadingStates() async {
    final file = await _stateFile();
    if (await file.exists()) await file.delete();
  }

  Future<FontPreferences> loadFontPreferences() => fonts.loadFontPreferences();
  Future<void> saveFontPreferences(FontPreferences preferences) =>
      fonts.saveFontPreferences(preferences);
  Future<List<InstalledFont>> listFonts() => fonts.listFonts();
  Future<void> saveFontWithName(String name, Uint8List bytes) =>
      fonts.saveFontWithName(name, bytes);
  Future<Uint8List?> loadFontByName(String name) => fonts.loadFontByName(name);
  Future<void> deleteFontByName(String name) => fonts.deleteFontByName(name);
  Future<void> clearFont() => fonts.clearFont();

  String _key(ImportedBook book) => '${book.format.name}:${book.title}';

  Future<Directory> _booksDir() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_books',
  );

  /// Storage root used by the import worker. Decoding and persistence stay in
  /// one worker so a large book is never sent back to the UI and copied again
  /// into a writer isolate.
  Future<String> bookStorageDirectoryPath() async => (await _booksDir()).path;

  Future<File> _bookContentFile(String id) async {
    final dir = await _booksDir();
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.json');
  }

  /// Raw TXT source copy for seek-mode books.
  Future<File> _bookSourceFile(String id) async {
    final dir = await _booksDir();
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.src');
  }

  /// Catalog sidecar (byte offsets) for seek-mode books.
  Future<File> _bookCatalogFile(String id) async {
    final dir = await _booksDir();
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.catalog.json');
  }

  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_library.json',
  );

  Future<File> _stateFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_reading_state.json',
  );

  Future<File> _prefsFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_reader_prefs.json',
  );

  Future<File> _foldersFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_folders.json');
  }

  Future<File> _updateRepoFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_update_repo.txt');
  }

  Future<File> _autoUpdateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_update_auto.txt');
  }
}
