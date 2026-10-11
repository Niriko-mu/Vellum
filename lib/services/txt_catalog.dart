import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:charset/charset.dart' show gbk;

import 'html_text_pipeline.dart';

/// One chapter in a TXT book, addressed by **byte offset** in the source file.
///
/// Mirrors Fanqie's `com.ttreader.txtparser.Chapter`
/// (`chapterIdx / startOffset / contentLength / title`): the reader seeks to
/// [startOffset] and reads [byteLength] bytes instead of decoding the whole
/// file.
class TxtChapterRef {
  const TxtChapterRef({
    required this.index,
    required this.title,
    required this.startOffset,
    required this.byteLength,
    required this.paragraphCount,
    this.charCount = 0,
  });

  final int index;
  final String title;

  /// Byte offset of chapter *content* (the title line itself is excluded).
  final int startOffset;
  final int byteLength;

  /// Paragraphs inside this chapter (exact, measured at scan time).
  final int paragraphCount;

  /// Decoded character count (used for remaining-time / progress without
  /// touching every paragraph at open).
  final int charCount;

  bool get isEmptyContent => byteLength <= 0 || paragraphCount == 0;

  Map<String, dynamic> toJson() => {
    'index': index,
    'title': title,
    'startOffset': startOffset,
    'byteLength': byteLength,
    'paragraphCount': paragraphCount,
    'charCount': charCount,
  };

  factory TxtChapterRef.fromJson(Map<String, dynamic> json) => TxtChapterRef(
    index: (json['index'] as num).toInt(),
    title: json['title'] as String? ?? '',
    startOffset: (json['startOffset'] as num).toInt(),
    byteLength: (json['byteLength'] as num).toInt(),
    paragraphCount: (json['paragraphCount'] as num).toInt(),
    charCount: (json['charCount'] as num?)?.toInt() ?? 0,
  );

  TxtChapterRef copyWith({
    int? index,
    String? title,
    int? startOffset,
    int? byteLength,
    int? paragraphCount,
    int? charCount,
  }) => TxtChapterRef(
    index: index ?? this.index,
    title: title ?? this.title,
    startOffset: startOffset ?? this.startOffset,
    byteLength: byteLength ?? this.byteLength,
    paragraphCount: paragraphCount ?? this.paragraphCount,
    charCount: charCount ?? this.charCount,
  );
}

/// Catalog state, paralleling Fanqie's `analyse()` return codes:
/// `0` → ready, `2` → TOC still being filled (synthetic / pending).
enum TxtCatalogStatus { ready, synthetic, pending }

/// File counterpart of [scanTxtCatalog], used by import/migration workers.
/// Only a 64 KiB source block and one bounded decoded block are resident.
TxtCatalog scanTxtCatalogFile(
  String path, {
  HtmlTextPipeline pipeline = const HtmlTextPipeline(),
  int syntheticChapterBytes = 5000,
  int maxTitleLength = 40,
}) {
  final handle = File(path).openSync();
  try {
    final length = handle.lengthSync();
    if (length == 0)
      return TxtCatalog(
        encoding: 'utf-8',
        chapters: [],
        status: TxtCatalogStatus.synthetic,
      );
    final probe = handle.readSync(length.clamp(0, 64 * 1024));
    var encoding = detectTxtEncoding(probe);
    if (!encoding.startsWith('utf-16')) {
      final decoder = utf8.decoder.startChunkedConversion(
        StringConversionSink.fromStringSink(_DiscardTextSink()),
      );
      handle.setPositionSync(0);
      try {
        var remaining = length;
        while (remaining > 0) {
          final bytes = handle.readSync(remaining.clamp(0, 64 * 1024));
          decoder.add(bytes);
          remaining -= bytes.length;
        }
        decoder.close();
        encoding = 'utf-8';
      } on FormatException {
        encoding = 'gbk';
      }
    }
    final wide = encoding.startsWith('utf-16');
    final width = wide ? 2 : 1;
    final titles = <({String title, int lineStart, int contentStart})>[];
    var lineStart = 0;
    var lineBytes = <int>[];
    var tooLong = false;
    var previousCr = false;
    handle.setPositionSync(0);
    var offset = 0;
    while (offset < length) {
      final chunk = handle.readSync((length - offset).clamp(0, 64 * 1024));
      final data = ByteData.sublistView(chunk);
      for (var i = 0; i + width <= chunk.length; i += width) {
        final unit = wide
            ? data.getUint16(
                i,
                encoding == 'utf-16le' ? Endian.little : Endian.big,
              )
            : chunk[i];
        final pos = offset + i;
        if (previousCr && unit == 10) {
          if (titles.isNotEmpty && titles.last.contentStart == pos) {
            final last = titles.removeLast();
            titles.add((
              title: last.title,
              lineStart: last.lineStart,
              contentStart: pos + width,
            ));
          }
          lineStart = pos + width;
          previousCr = false;
          continue;
        }
        previousCr = false;
        if (unit == 10 || unit == 13) {
          if (!tooLong) {
            final line = decodeTxtWithEncoding(
              Uint8List.fromList(lineBytes),
              encoding,
            ).trim();
            if (_isChapterTitle(line, pipeline, maxTitleLength)) {
              titles.add((
                title: pipeline.chapterTitle(line),
                lineStart: lineStart,
                contentStart: pos + width,
              ));
            }
          }
          lineBytes = [];
          tooLong = false;
          lineStart = pos + width;
          previousCr = unit == 13;
        } else if (!tooLong) {
          if (lineBytes.length + width > maxTitleLength * 4 + 4) {
            lineBytes = [];
            tooLong = true;
          } else {
            lineBytes.addAll(chunk.sublist(i, i + width));
          }
        }
      }
      offset += chunk.length;
    }
    if (!tooLong && lineBytes.isNotEmpty) {
      final line = decodeTxtWithEncoding(
        Uint8List.fromList(lineBytes),
        encoding,
      ).trim();
      if (_isChapterTitle(line, pipeline, maxTitleLength))
        titles.add((
          title: pipeline.chapterTitle(line),
          lineStart: lineStart,
          contentStart: length,
        ));
    }
    final ranges = <({String title, int start, int end})>[];
    if (titles.isEmpty) {
      ranges.add((title: '', start: 0, end: length));
    } else {
      if (titles.first.lineStart > 0)
        ranges.add((title: '前言', start: 0, end: titles.first.lineStart));
      for (var i = 0; i < titles.length; i++) {
        ranges.add((
          title: titles[i].title,
          start: titles[i].contentStart,
          end: i + 1 < titles.length ? titles[i + 1].lineStart : length,
        ));
      }
    }
    final chapters = <TxtChapterRef>[];
    var syntheticNumber = 1;
    for (final range in ranges) {
      var position = range.start;
      while (position < range.end) {
        handle.setPositionSync(position);
        final stride = titles.isEmpty
            ? syntheticChapterBytes.clamp(4, 64 * 1024)
            : 64 * 1024;
        final bytes = handle.readSync(
          (range.end - position).clamp(0, stride + 4),
        );
        // Reuse the exact same newline/codepoint boundary policy as byte imports.
        final blocks = _boundedRanges(bytes, encoding, 0, bytes.length, stride);
        final block = blocks.first;
        final body = Uint8List.sublistView(bytes, 0, block.end);
        final text = decodeTxtWithEncoding(body, encoding);
        final paragraphs = splitTxtParagraphs(text, pipeline);
        if (paragraphs.isNotEmpty) {
          chapters.add(
            TxtChapterRef(
              index: chapters.length,
              title: titles.isEmpty
                  ? '第${syntheticNumber++}章'
                  : (position == range.start ? range.title : ''),
              startOffset: position,
              byteLength: block.end,
              paragraphCount: paragraphs.length,
              charCount: text.length,
            ),
          );
        }
        position += block.end;
      }
    }
    return TxtCatalog(
      encoding: encoding,
      chapters: chapters,
      status: titles.isEmpty
          ? TxtCatalogStatus.synthetic
          : TxtCatalogStatus.ready,
    );
  } finally {
    handle.closeSync();
  }
}

class _DiscardTextSink implements StringSink {
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
}

/// Byte-offset catalog for a TXT book.
class TxtCatalog {
  TxtCatalog({
    required this.encoding,
    required this.chapters,
    required this.status,
  });

  /// Charset name used to decode the file: `utf-8` / `gbk` / `utf-16le` / `utf-16be`.
  final String encoding;
  final List<TxtChapterRef> chapters;
  final TxtCatalogStatus status;

  /// Prefix sums, built once on first use.
  ///
  /// Paragraph indices are looked up per paragraph while paginating, so the
  /// obvious "walk the chapter list" implementations made every
  /// `book.paragraphs[i]` cost O(chapters) — on a several-thousand-chapter web
  /// novel that is what turned a re-layout (font switch) into seconds of frozen
  /// UI thread and, eventually, a killed process.
  List<int>? _starts;

  /// End paragraph index of each chapter (a running total).
  List<int>? _ends;

  /// Start paragraph index of each chapter plus a final total, one entry longer
  /// than [chapters].
  List<int> get _startTable => _starts ??= _buildStarts();

  /// Running paragraph total after each chapter, cached for [totalParagraphs].
  List<int> get _endTable => _ends ??= _buildEnds();

  List<int> _buildStarts() {
    final table = List<int>.filled(chapters.length + 1, 0);
    var sum = 0;
    for (var i = 0; i < chapters.length; i++) {
      table[i] = sum;
      sum += chapters[i].paragraphCount;
    }
    table[chapters.length] = sum;
    return table;
  }

  List<int> _buildEnds() {
    final table = List<int>.filled(chapters.length, 0);
    var sum = 0;
    for (var i = 0; i < chapters.length; i++) {
      sum += chapters[i].paragraphCount;
      table[i] = sum;
    }
    return table;
  }

  int get totalParagraphs => _startTable[chapters.length];

  int get totalCharCount {
    var sum = 0;
    for (final chapter in chapters) {
      sum += chapter.charCount;
    }
    return sum;
  }

  bool get isSynthetic => status == TxtCatalogStatus.synthetic;

  /// Global paragraph index at which [chapterIndex] begins.
  int paragraphStartOf(int chapterIndex) {
    if (chapters.isEmpty) return 0;
    final table = _startTable;
    return table[chapterIndex.clamp(0, chapters.length)];
  }

  /// Chapter that contains the given global paragraph index.
  ///
  /// Binary search over the cached prefix sums: the chapter list is ordered, so
  /// the previous linear walk was pure overhead on every paragraph access.
  TxtChapterRef chapterForParagraph(int paragraphIndex) {
    if (chapters.isEmpty) {
      return const TxtChapterRef(
        index: 0,
        title: '',
        startOffset: 0,
        byteLength: 0,
        paragraphCount: 0,
      );
    }
    final ends = _endTable;
    var low = 0;
    var high = chapters.length - 1;
    var index = high;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (paragraphIndex < ends[mid]) {
        index = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return chapters[index];
  }

  List<MapEntry<int, String>> get tocEntries => [
    for (final chapter in chapters)
      if (chapter.title.isNotEmpty)
        MapEntry(paragraphStartOf(chapter.index), chapter.title),
  ];

  Map<String, dynamic> toJson() => {
    'encoding': encoding,
    'status': status.name,
    'chapters': [for (final chapter in chapters) chapter.toJson()],
  };

  factory TxtCatalog.fromJson(Map<String, dynamic> json) => TxtCatalog(
    encoding: json['encoding'] as String? ?? 'utf-8',
    status: TxtCatalogStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => TxtCatalogStatus.ready,
    ),
    chapters: [
      for (final entry in json['chapters'] as List<dynamic>? ?? const [])
        TxtChapterRef.fromJson(entry as Map<String, dynamic>),
    ],
  );
}

/// Scans raw TXT bytes into a [TxtCatalog].
///
/// Algorithm (Fanqie `TxtParser.analyse` + `TTTxtCatalogHelper`):
/// 1. Detect encoding (BOM → UTF-8 probe → GBK).
/// 2. Walk the file line by line, recording byte offsets of chapter titles.
/// 3. Post-process: name a content-only opening「前言」, merge empty chapters.
/// 4. Measure each chapter's paragraph count (decode that range only).
/// 5. If no title was recognised, synthesise `第N章` every
///    [syntheticChapterBytes] bytes (Fanqie uses 5000).
TxtCatalog scanTxtCatalog(
  Uint8List bytes, {
  HtmlTextPipeline pipeline = const HtmlTextPipeline(),
  int syntheticChapterBytes = 5000,
  int maxTitleLength = 40,
}) {
  if (bytes.isEmpty) {
    return TxtCatalog(
      encoding: 'utf-8',
      chapters: [],
      status: TxtCatalogStatus.synthetic,
    );
  }
  final encoding = detectTxtEncoding(bytes);

  // --- 2. Line scan: find chapter title byte offsets ---
  final titleAt = <({String title, int lineStart, int contentStart})>[];
  var pos = 0;
  while (pos < bytes.length) {
    final boundary = _lineEnd(bytes, pos, encoding);
    final nl = boundary.end;
    final lineBytes = nl > pos
        ? Uint8List.sublistView(bytes, pos, nl)
        : Uint8List(0);
    final line = lineBytes.length > maxTitleLength * 4 + 4
        ? ''
        : decodeTxtWithEncoding(lineBytes, encoding).trim();
    if (_isChapterTitle(line, pipeline, maxTitleLength)) {
      titleAt.add((
        title: pipeline.chapterTitle(line),
        lineStart: pos,
        contentStart: boundary.next,
      ));
    }
    pos = boundary.next;
  }

  // --- 3. Build raw chapter ranges ---
  var raw = <({String title, int start, int end})>[];
  if (titleAt.isEmpty) {
    raw = _boundedRanges(
      bytes,
      encoding,
      0,
      bytes.length,
      syntheticChapterBytes,
      synthetic: true,
    );
  } else {
    // Content sitting before the first title line: Fanqie names it「前言」.
    final firstTitleLineStart = titleAt.first.lineStart;
    if (firstTitleLineStart > 0 &&
        _hasVisibleContent(bytes, 0, firstTitleLineStart)) {
      raw.add((title: '前言', start: 0, end: firstTitleLineStart));
    }
    for (var i = 0; i < titleAt.length; i++) {
      final start = titleAt[i].contentStart;
      final end = i + 1 < titleAt.length
          ? titleAt[i + 1].lineStart
          : bytes.length;
      raw.add((
        title: titleAt[i].title,
        start: start,
        end: end > start ? end : start,
      ));
    }
  }

  // Bound every decode, including novels containing one enormous chapter.
  raw = [
    for (final range in raw)
      ..._boundedRanges(
        bytes,
        encoding,
        range.start,
        range.end,
        64 * 1024,
        title: range.title,
      ),
  ];

  // --- 4. Measure paragraphs + merge empty chapters (Fanqie t()) ---
  final measured = <TxtChapterRef>[];
  for (var i = 0; i < raw.length; i++) {
    final range = raw[i];
    final length = range.end - range.start;
    final text = length > 0
        ? _sanitize(
            decodeTxtWithEncoding(
              Uint8List.sublistView(bytes, range.start, range.end),
              encoding,
            ),
          )
        : '';
    final paragraphs = text.isEmpty
        ? const <String>[]
        : splitTxtParagraphs(text, pipeline);
    measured.add(
      TxtChapterRef(
        index: i,
        title: range.title,
        startOffset: range.start,
        byteLength: length,
        paragraphCount: paragraphs.length,
        charCount: text.length,
      ),
    );
  }

  // Empty title-only sections do not contain body paragraphs. Dropping them
  // preserves the exact offsets/counts of the following readable section.
  final merged = measured.where((chapter) => !chapter.isEmptyContent).toList();
  final reindexed = [
    for (var i = 0; i < merged.length; i++) merged[i].copyWith(index: i),
  ];

  // Empty/untitled first chapter →「前言」(Fanqie naming rule).
  final named = <TxtChapterRef>[];
  for (var i = 0; i < reindexed.length; i++) {
    var chapter = reindexed[i];
    if (i == 0 && chapter.title.isEmpty) {
      chapter = chapter.copyWith(title: '前言');
    }
    named.add(chapter);
  }

  final status = titleAt.isEmpty
      ? TxtCatalogStatus.synthetic
      : TxtCatalogStatus.ready;
  return TxtCatalog(encoding: encoding, chapters: named, status: status);
}

/// Fanqie-compatible encoding detection (`pt5/h.java` + ICU in libTxtParser).
String detectTxtEncoding(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return 'utf-16le';
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return 'utf-16be';
  }
  // BOM-less UTF-16 with ASCII/line breaks has NULs concentrated on one
  // byte lane. Require strong evidence to avoid treating ordinary GBK as wide.
  var evenNulls = 0;
  var oddNulls = 0;
  final probeLength = bytes.length.clamp(0, 4096);
  for (var i = 0; i < probeLength; i++) {
    if (bytes[i] == 0) {
      if (i.isEven) {
        evenNulls++;
      } else {
        oddNulls++;
      }
    }
  }
  if (oddNulls >= 4 &&
      oddNulls > evenNulls * 10 &&
      oddNulls * 32 >= probeLength) {
    return 'utf-16le';
  }
  if (evenNulls >= 4 &&
      evenNulls > oddNulls * 10 &&
      evenNulls * 32 >= probeLength) {
    return 'utf-16be';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return 'utf-8';
  }
  final content =
      bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? bytes.sublist(3)
      : bytes;
  return _looksLikeUtf8(content) ? 'utf-8' : 'gbk';
}

/// Decodes a full buffer with a catalog-recorded encoding.
String decodeTxtWithEncoding(Uint8List bytes, String encoding) {
  switch (encoding) {
    case 'utf-16le':
    case 'utf-16be':
      final endian = encoding == 'utf-16le' ? Endian.little : Endian.big;
      final hasBom =
          bytes.length >= 2 &&
          ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
              (bytes[0] == 0xfe && bytes[1] == 0xff));
      final body = hasBom ? Uint8List.sublistView(bytes, 2) : bytes;
      final units = <int>[];
      final data = ByteData.sublistView(body);
      for (var i = 0; i + 1 < body.length; i += 2) {
        units.add(data.getUint16(i, endian));
      }
      return _sanitize(String.fromCharCodes(units));
    case 'gbk':
      return _sanitize(gbk.decode(bytes, allowMalformed: true));
    case 'utf-8':
    default:
      return _sanitize(utf8.decode(bytes, allowMalformed: true));
  }
}

String _sanitize(String text) => text.replaceAll('﻿', '').replaceAll('　', ' ');

/// Bound layout work for TXT files with no line breaks. Unicode surrogate
/// pairs remain intact, and scanning and seeking use exactly the same splits.
List<String> splitTxtParagraphs(String text, HtmlTextPipeline pipeline) {
  final result = <String>[];
  for (final paragraph in pipeline.splitParagraphs(text)) {
    var start = 0;
    while (start < paragraph.length) {
      var end = (start + 2048).clamp(start, paragraph.length);
      if (end < paragraph.length) {
        final last = paragraph.codeUnitAt(end - 1);
        if (last >= 0xd800 && last <= 0xdbff) end--;
      }
      result.add(paragraph.substring(start, end));
      start = end;
    }
  }
  return result;
}

bool _isChapterTitle(
  String line,
  HtmlTextPipeline pipeline,
  int maxTitleLength,
) {
  if (line.isEmpty || line.length > maxTitleLength) return false;
  final value = pipeline.chapterTitle(line);
  if (value.isEmpty || value.length > maxTitleLength) return false;
  if (value.contains('。') ||
      value.contains('，') ||
      value.contains(',') ||
      value.contains('！') ||
      value.contains('？')) {
    return false;
  }
  return HtmlTextPipeline.chapterPattern.hasMatch(value);
}

({int end, int next}) _lineEnd(Uint8List bytes, int start, String encoding) {
  final wide = encoding.startsWith('utf-16');
  final step = wide ? 2 : 1;
  final data = ByteData.sublistView(bytes);
  int unit(int pos) => wide
      ? data.getUint16(pos, encoding == 'utf-16le' ? Endian.little : Endian.big)
      : bytes[pos];
  for (var pos = start; pos + step <= bytes.length; pos += step) {
    final value = unit(pos);
    if (value != 10 && value != 13) continue;
    var next = pos + step;
    if (value == 13 && next + step <= bytes.length && unit(next) == 10) {
      next += step;
    }
    return (end: pos, next: next);
  }
  return (end: bytes.length, next: bytes.length);
}

List<({String title, int start, int end})> _boundedRanges(
  Uint8List bytes,
  String encoding,
  int start,
  int end,
  int stride, {
  String title = '',
  bool synthetic = false,
}) {
  final result = <({String title, int start, int end})>[];
  final step = stride < 4 ? 4 : stride;
  var pos = start;
  var number = 1;
  while (pos < end) {
    var limit = (pos + step).clamp(pos, end);
    if (limit < end) {
      // Prefer a complete line within this bounded window.
      final wide = encoding.startsWith('utf-16');
      final width = wide ? 2 : 1;
      var newline = -1;
      final data = ByteData.sublistView(bytes);
      for (var i = pos; i + width <= limit; i += width) {
        final value = wide
            ? data.getUint16(
                i,
                encoding == 'utf-16le' ? Endian.little : Endian.big,
              )
            : bytes[i];
        if (value == 10) newline = i + width;
      }
      if (newline > pos) {
        limit = newline;
      } else if (wide) {
        limit -= (limit - pos) % 2;
        final previous = data.getUint16(
          limit - 2,
          encoding == 'utf-16le' ? Endian.little : Endian.big,
        );
        if (previous >= 0xd800 && previous <= 0xdbff) limit -= 2;
      } else if (encoding == 'utf-8') {
        while (limit > pos && bytes[limit] >= 0x80 && bytes[limit] <= 0xbf) {
          limit--;
        }
      } else {
        // GBK lead/trail bytes must be walked from a known boundary.
        var i = pos;
        var safe = pos;
        while (i < limit) {
          final size = bytes[i] >= 0x81 && bytes[i] <= 0xfe ? 2 : 1;
          if (i + size > limit) break;
          i += size;
          safe = i;
        }
        limit = safe;
      }
    }
    result.add((
      title: synthetic ? '第${number++}章' : (pos == start ? title : ''),
      start: pos,
      end: limit,
    ));
    pos = limit;
  }
  return result;
}

bool _hasVisibleContent(Uint8List bytes, int start, int end) => bytes
    .sublist(start, end)
    .any((b) => b != 0x20 && b != 9 && b != 13 && b != 10);

bool _looksLikeUtf8(List<int> bytes) {
  try {
    utf8.decode(bytes, allowMalformed: false);
    return true;
  } on FormatException {
    return false;
  }
}
