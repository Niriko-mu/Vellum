import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../reader/reader_toc.dart';
import 'book_models.dart';
import 'lazy_paragraphs.dart';

/// Immutable body segments share a seekable file; the small JSON manifest is
/// published last. Paragraph indexes never change, preserving old annotations.
Future<void> writeChunkedBook(ImportedBook book, String manifestPath) async {
  final body = File('$manifestPath.body');
  final temporary = File('${body.path}.next');
  final handle = await temporary.open(mode: FileMode.write);
  final blocks = <Map<String, int>>[];
  final images = <String, List<int>>{};
  final toc = chapterEntries(book);
  final boundaries = toc.map((entry) => entry.key).toSet();
  var totalChars = 0;
  var offset = 0;
  try {
    var start = 0;
    while (start < book.paragraphs.length) {
      final paragraphs = <String>[];
      var chars = 0;
      var end = start;
      // A long chapter is subdivided, without splitting/reindexing paragraphs.
      while (end < book.paragraphs.length &&
          (end == start ||
              (end - start < 128 &&
                  chars < 64 * 1024 &&
                  !boundaries.contains(end)))) {
        final text = book.paragraphs[end++];
        paragraphs.add(text);
        chars += text.length;
      }
      final bytes = utf8.encode(jsonEncode(paragraphs));
      await handle.writeFrom(bytes);
      blocks.add({
        'start': start,
        'count': end - start,
        'offset': offset,
        'bytes': bytes.length,
        'chars': chars,
        'charsBefore': totalChars,
      });
      offset += bytes.length;
      totalChars += chars;
      start = end;
    }
    for (final entry in book.imageBytes.entries) {
      await handle.writeFrom(entry.value);
      images['${entry.key}'] = [offset, entry.value.length];
      offset += entry.value.length;
    }
    await handle.flush();
  } finally {
    await handle.close();
  }
  // Never replace an active body. Imports use unique staging directories;
  // legacy migration has no body yet and retains its old JSON until commit.
  if (await body.exists()) {
    await temporary.delete();
    throw StateError('Book body already exists: ${body.path}');
  }
  await temporary.rename(body.path);
  final manifest = File('$manifestPath.next');
  await manifest.writeAsString(
    jsonEncode({
      'version': 1,
      'contentMode': 'chunked',
      'id': book.storageId,
      'title': book.title,
      'author': book.author,
      'format': book.format.name,
      'paragraphCount': book.paragraphs.length,
      'totalChars': totalChars,
      'blocks': blocks,
      'images': images,
      'linkTargets': {
        for (final e in book.linkTargets.entries) '${e.key}': e.value,
      },
      'tocEntries': [
        for (final e in toc) {'title': e.value, 'paragraphIndex': e.key},
      ],
    }),
    flush: true,
  );
  // Windows does not replace an existing file. Preserve a rollback copy.
  final target = File(manifestPath);
  final backup = File('$manifestPath.legacy');
  if (await target.exists()) await target.rename(backup.path);
  try {
    await manifest.rename(manifestPath);
  } catch (_) {
    if (await backup.exists()) await backup.rename(manifestPath);
    rethrow;
  }
  if (await backup.exists()) await backup.delete();
}

ImportedBook openChunkedBook(String path, Map<String, dynamic> manifest) {
  final source = ChunkedParagraphList(path, manifest);
  return ImportedBook(
    id: manifest['id'] as String,
    title: manifest['title'] as String,
    author: manifest['author'] as String? ?? '',
    format: BookFormat.values.byName(manifest['format'] as String),
    paragraphs: source,
    contentMode: 'chunked',
    linkTargets: (manifest['linkTargets'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(int.parse(key), value as int),
    ),
    tocEntries: [
      for (final e in manifest['tocEntries'] as List)
        BookTocEntry(
          title: e['title'] as String,
          paragraphIndex: e['paragraphIndex'] as int,
        ),
    ],
    imageBytes: _DiskImages(
      '$path.body',
      manifest['images'] as Map<String, dynamic>,
    ),
  );
}

/// Worker entry for search, speech and original-EPUB anchor matching.
List<String> readPersistedParagraphs(String path) {
  final data =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  if (data['contentMode'] == 'chunked') return ChunkedParagraphList(path, data);
  return (data['paragraphs'] as List).cast<String>();
}

List<String> _readBlock(Map<String, dynamic> message) {
  final bytes = _readRange(
    message['path'] as String,
    message['offset'] as int,
    message['bytes'] as int,
  );
  return (jsonDecode(utf8.decode(bytes)) as List).cast<String>();
}

Uint8List _readRange(String path, int offset, int length) {
  final handle = File(path).openSync();
  try {
    handle.setPositionSync(offset);
    final bytes = handle.readSync(length);
    if (bytes.length != length) throw const FormatException('书籍内容不完整');
    return bytes;
  } finally {
    handle.closeSync();
  }
}

class ChunkedParagraphList extends ListBase<String> implements LazyParagraphs {
  ChunkedParagraphList(this.manifestPath, this.manifest)
    : _blocks = (manifest['blocks'] as List)
          .map((e) => Map<String, int>.from(e as Map))
          .toList();

  final String manifestPath;
  final Map<String, dynamic> manifest;
  final List<Map<String, int>> _blocks;
  final _cache = <int, List<String>>{};
  final _pending = <int, Future<void>>{};
  int _cacheBytes = 0;
  int _generation = 0;
  static const cacheLimit = 5;
  static const cacheByteLimit = 2 * 1024 * 1024;
  int get cachedBlockCount => _cache.length;
  int get cachedBytes => _cacheBytes;

  @override
  int get length => manifest['paragraphCount'] as int;
  @override
  set length(int value) => throw UnsupportedError('Read-only book');
  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Read-only book');

  int _blockFor(int index) {
    RangeError.checkValidIndex(index, this);
    var low = 0;
    var high = _blocks.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_blocks[mid]['start']! <= index) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  Map<String, dynamic> _message(int block) => {
    'path': '$manifestPath.body',
    'offset': _blocks[block]['offset'],
    'bytes': _blocks[block]['bytes'],
  };

  void _store(int index, List<String> paragraphs) {
    if (_cache.containsKey(index)) return;
    _cache[index] = paragraphs;
    _cacheBytes += _blocks[index]['chars']! * 2;
    while (_cache.length > 1 &&
        (_cache.length > cacheLimit || _cacheBytes > cacheByteLimit)) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _cacheBytes -= _blocks[oldest]['chars']! * 2;
    }
  }

  @override
  String operator [](int index) {
    final block = _blockFor(index);
    var paragraphs = _cache.remove(block);
    if (paragraphs == null) {
      paragraphs = _readBlock(_message(block));
      _store(block, paragraphs);
    } else {
      _cache[block] = paragraphs;
    }
    return paragraphs[index - _blocks[block]['start']!];
  }

  Future<void> _prefetch(int block) {
    if (block >= _blocks.length || _cache.containsKey(block)) {
      return Future<void>.value();
    }
    return _pending.putIfAbsent(block, () async {
      final generation = _generation;
      try {
        final paragraphs = await compute(_readBlock, _message(block));
        if (_generation == generation) _store(block, paragraphs);
      } finally {
        _pending.remove(block);
      }
    });
  }

  @override
  Future<void> prefetchAroundParagraph(int index) async {
    if (isEmpty) return;
    final block = _blockFor(index.clamp(0, length - 1));
    await _prefetch(block);
    _prefetch(block + 1).catchError((Object _) {});
  }

  @override
  bool isParagraphCached(int index) => _cache.containsKey(_blockFor(index));
  @override
  int blockEndForParagraph(int index) {
    final block = _blocks[_blockFor(index)];
    return block['start']! + block['count']!;
  }

  @override
  int get totalCharacters => manifest['totalChars'] as int;
  @override
  int charactersBefore(int index) {
    if (index >= length) return totalCharacters;
    if (index <= 0) return 0;
    final block = _blocks[_blockFor(index)];
    var count = block['charsBefore']!;
    for (var i = block['start']!; i < index; i++) {
      count += this[i].length;
    }
    return count;
  }

  @override
  void close() {
    _generation++;
    _cache.clear();
    _cacheBytes = 0;
  }
}

/// Raw images stay on disk until rendered, with a separate 8 MiB LRU.
class _DiskImages extends MapBase<int, Uint8List> {
  _DiskImages(this.path, this.locations);
  final String path;
  final Map<String, dynamic> locations;
  final _cache = <int, Uint8List>{};
  int _bytes = 0;
  @override
  Iterable<int> get keys => locations.keys.map(int.parse);
  @override
  bool containsKey(Object? key) => locations.containsKey('$key');
  @override
  Uint8List? operator [](Object? key) {
    final range = locations['$key'] as List?;
    if (range == null) return null;
    final index = key as int;
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }
    final bytes = _readRange(path, range[0] as int, range[1] as int);
    if (bytes.length <= 8 * 1024 * 1024) {
      _cache[index] = bytes;
      _bytes += bytes.length;
      while (_bytes > 8 * 1024 * 1024 || _cache.length > 12) {
        _bytes -= _cache.remove(_cache.keys.first)!.length;
      }
    }
    return bytes;
  }

  @override
  void operator []=(int key, Uint8List value) =>
      throw UnsupportedError('Read-only');
  @override
  Uint8List? remove(Object? key) => throw UnsupportedError('Read-only');
  @override
  void clear() => throw UnsupportedError('Read-only');
}
