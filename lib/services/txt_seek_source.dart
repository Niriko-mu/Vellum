import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;

import 'html_text_pipeline.dart';
import 'txt_catalog.dart';

/// Chapter-at-a-time text cache backed by a seekable TXT source file.
///
/// Fanqie's model: `TxtParser.getContent(idx, startOffset, byteLength)` reads
/// one chapter via seek. [TxtParagraphList] exposes that as a `List<String>`
/// so the existing reader (`book.paragraphs[i]`) keeps working unchanged,
/// while only the chapters actually touched are decoded.
class TxtSeekSource {
  TxtSeekSource({
    required this.file,
    required this.catalog,
    this.pipeline = const HtmlTextPipeline(),
    this.cacheLimit = 4,
    this.cacheByteLimit = 2 * 1024 * 1024,
  });

  final File file;
  final TxtCatalog catalog;
  final HtmlTextPipeline pipeline;

  /// How many decoded chapters to keep (current ± neighbours is enough).
  final int cacheLimit;
  final int cacheByteLimit;

  RandomAccessFile? _raf;
  final Map<int, List<String>> _chapterParagraphs = {};
  final List<int> _lru = [];
  final Map<int, Future<void>> _pending = {};
  int _generation = 0;

  int get chapterCount => catalog.chapters.length;

  /// Decoded paragraphs of one chapter (cached).
  List<String> chapterParagraphs(int chapterIndex) {
    final cached = _chapterParagraphs[chapterIndex];
    if (cached != null) {
      _touch(chapterIndex);
      return cached;
    }
    final chapter = catalog.chapters[chapterIndex];
    final text = readChapterText(chapter);
    final paragraphs = text.isEmpty
        ? const <String>[]
        : splitTxtParagraphs(text, pipeline);
    _store(chapterIndex, paragraphs);
    return paragraphs;
  }

  /// Seeks to [TxtChapterRef.startOffset] and decodes [byteLength] bytes.
  String readChapterText(TxtChapterRef chapter) {
    if (chapter.byteLength <= 0) return '';
    final raf = _raf ??= file.openSync();
    raf.setPositionSync(chapter.startOffset);
    if (chapter.byteLength > 256 * 1024) {
      throw const FormatException('TXT 目录章节过大，请重新导入以建立分块目录。');
    }
    final raw = raf.readSync(chapter.byteLength);
    if (raw.isEmpty) return '';
    return decodeTxtWithEncoding(Uint8List.fromList(raw), catalog.encoding);
  }

  bool isCached(int chapterIndex) =>
      _chapterParagraphs.containsKey(chapterIndex);

  /// Decode only the requested block in a worker. The cache stores bounded
  /// paragraph lists, never a materialized whole book.
  Future<void> prefetchChapter(int chapterIndex) {
    if (chapterIndex < 0 ||
        chapterIndex >= chapterCount ||
        isCached(chapterIndex)) {
      return Future<void>.value();
    }
    return _pending.putIfAbsent(chapterIndex, () async {
      final generation = _generation;
      try {
        final paragraphs = await compute(_readTxtBlock, <String, dynamic>{
          'path': file.path,
          'encoding': catalog.encoding,
          'chapter': catalog.chapters[chapterIndex].toJson(),
        });
        if (generation == _generation) _store(chapterIndex, paragraphs);
      } finally {
        _pending.remove(chapterIndex);
      }
    });
  }

  Future<void> prefetchAroundParagraph(int paragraphIndex) async {
    if (catalog.totalParagraphs == 0) return;
    final index = catalog.chapterForParagraph(paragraphIndex).index;
    await prefetchChapter(index);
    // Warm the next block without delaying the current page.
    prefetchChapter(index + 1).catchError((Object _) {});
  }

  void _store(int chapterIndex, List<String> paragraphs) {
    _chapterParagraphs[chapterIndex] = paragraphs;
    _touch(chapterIndex);
    while (_lru.length > 1 &&
        (_lru.length > cacheLimit ||
            _chapterParagraphs.values.fold<int>(
                  0,
                  (sum, paragraphs) =>
                      sum +
                      paragraphs.fold<int>(
                        0,
                        (count, text) => count + text.length * 2,
                      ),
                ) >
                cacheByteLimit)) {
      final evict = _lru.removeAt(0);
      if (evict != chapterIndex) _chapterParagraphs.remove(evict);
    }
  }

  void _touch(int chapterIndex) {
    _lru.remove(chapterIndex);
    _lru.add(chapterIndex);
  }

  void close() {
    _generation++;
    _raf?.closeSync();
    _raf = null;
    _chapterParagraphs.clear();
    _lru.clear();
  }
}

/// A `List<String>` view over a [TxtSeekSource].
///
/// Drop-in replacement for `ImportedBook.paragraphs` on seek-mode TXT books:
/// `length` is O(1) from the catalog; `operator []` seeks and decodes only the
/// chapter that owns the paragraph.
class TxtParagraphList extends ListBase<String> {
  TxtParagraphList(this.source);

  final TxtSeekSource source;
  final Map<int, int> _chapterStart = {};

  TxtCatalog get catalog => source.catalog;

  @override
  int get length => catalog.totalParagraphs;

  @override
  set length(int newLength) {
    throw UnsupportedError('TXT seek paragraphs are read-only');
  }

  int paragraphStartOf(int chapterIndex) {
    return _chapterStart.putIfAbsent(chapterIndex, () {
      return catalog.paragraphStartOf(chapterIndex);
    });
  }

  @override
  String operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index');
    }
    final chapter = catalog.chapterForParagraph(index);
    final start = paragraphStartOf(chapter.index);
    final local = index - start;
    final paragraphs = source.chapterParagraphs(chapter.index);
    if (local < 0 || local >= paragraphs.length) {
      // Catalog drift (file edited after import): degrade gracefully.
      return paragraphs.isEmpty
          ? ''
          : paragraphs[local.clamp(0, paragraphs.length - 1)];
    }
    return paragraphs[local];
  }

  @override
  void operator []=(int index, String value) {
    throw UnsupportedError('TXT seek paragraphs are read-only');
  }

  /// Materialise the whole book (only used by export / tests).
  List<String> materialize() {
    final all = <String>[];
    for (var i = 0; i < catalog.chapters.length; i++) {
      all.addAll(source.chapterParagraphs(i));
    }
    return all;
  }
}

/// Wraps raw bytes + catalog into a paragraph list without a file on disk
/// (used right after import, before the source file is persisted).
///
/// Decodes chapter-at-a-time on demand, so a large TXT import never has to
/// hold the fully decoded book in memory at once.
class InMemoryTxtParagraphList extends ListBase<String> {
  InMemoryTxtParagraphList(
    this.bytes,
    this.catalog, {
    this.pipeline = const HtmlTextPipeline(),
  });

  final Uint8List bytes;
  final TxtCatalog catalog;
  final HtmlTextPipeline pipeline;
  final Map<int, List<String>> _cache = {};

  List<String> _decodeChapter(TxtChapterRef chapter) {
    if (chapter.byteLength <= 0) return const [];
    final end = chapter.startOffset + chapter.byteLength;
    if (chapter.startOffset >= bytes.length) return const [];
    final safeEnd = end > bytes.length ? bytes.length : end;
    final text = decodeTxtWithEncoding(
      Uint8List.sublistView(bytes, chapter.startOffset, safeEnd),
      catalog.encoding,
    );
    return text.isEmpty ? const [] : splitTxtParagraphs(text, pipeline);
  }

  List<String> _chapterParagraphs(int chapterIndex) =>
      _cache.putIfAbsent(chapterIndex, () {
        return _decodeChapter(catalog.chapters[chapterIndex]);
      });

  @override
  int get length => catalog.totalParagraphs;

  @override
  set length(int newLength) {
    throw UnsupportedError('TXT paragraphs are read-only');
  }

  @override
  String operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index');
    }
    final chapter = catalog.chapterForParagraph(index);
    final local = index - catalog.paragraphStartOf(chapter.index);
    final paragraphs = _chapterParagraphs(chapter.index);
    if (paragraphs.isEmpty) return '';
    return paragraphs[local.clamp(0, paragraphs.length - 1)];
  }

  @override
  void operator []=(int index, String value) {
    throw UnsupportedError('TXT paragraphs are read-only');
  }

  /// Materialise the whole book (export / tests only).
  List<String> materialize() {
    final all = <String>[];
    for (var i = 0; i < catalog.chapters.length; i++) {
      all.addAll(_chapterParagraphs(i));
    }
    return all;
  }
}

List<String> _readTxtBlock(Map<String, dynamic> message) {
  final chapter = TxtChapterRef.fromJson(
    message['chapter'] as Map<String, dynamic>,
  );
  if (chapter.byteLength > 256 * 1024) {
    throw const FormatException('TXT 目录章节过大，请重新导入。');
  }
  final handle = File(message['path'] as String).openSync();
  try {
    handle.setPositionSync(chapter.startOffset);
    final bytes = handle.readSync(chapter.byteLength);
    final text = decodeTxtWithEncoding(bytes, message['encoding'] as String);
    return splitTxtParagraphs(text, const HtmlTextPipeline());
  } finally {
    handle.closeSync();
  }
}
