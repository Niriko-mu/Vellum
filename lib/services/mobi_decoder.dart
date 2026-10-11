import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'book_models.dart';
import 'html_text_pipeline.dart';

class _MobiExth {
  const _MobiExth({this.author = '', this.updatedTitle = '', this.coverOffset});
  final String author;
  final String updatedTitle;
  final int? coverOffset;
}

/// MOBI Huffman/CDIC decompressor (compression type 17480).
///
/// Port of calibre's `ebooks/mobi/huffcdic.py` (GPL, darkninja/igorsk), which
/// matches the tables Fanqie's `libmobiparser.so` consumes via
/// `ttmobi::MobiHuffCdic`. A single HUFF record holds two 256-entry code
/// tables; one or more CDIC records hold the phrase dictionary. Text records
/// are a bit stream of dictionary indexes.
class MobiHuffCdic {
  final List<_HuffEntry> _dict1 = [];
  final List<int> _mincode = List<int>.filled(33, 0);
  final List<int> _maxcode = List<int>.filled(33, 0);
  final List<_CdicEntry> _dictionary = [];

  void load(Uint8List huff, List<Uint8List> cdicRecords) {
    _loadHuff(huff);
    for (final record in cdicRecords) {
      _loadCdic(record);
    }
  }

  void _loadHuff(Uint8List huff) {
    if (huff.length < 16) {
      throw const BookImportException('MOBI HUFF 记录过短。');
    }
    final data = ByteData.sublistView(huff);
    final off1 = data.getUint32(8, Endian.big);
    final off2 = data.getUint32(12, Endian.big);
    if (off1 + 256 * 4 > huff.length) {
      throw const BookImportException('MOBI HUFF 记录无效。');
    }
    _dict1.clear();
    for (var i = 0; i < 256; i++) {
      final v = data.getUint32(off1 + i * 4, Endian.big);
      final codelen = v & 0x1f;
      final term = (v & 0x80) != 0;
      final maxcode = ((v >> 8) + 1) << (32 - codelen);
      _dict1.add(_HuffEntry(codelen, term, maxcode - 1));
    }
    if (off2 + 64 * 4 > huff.length) {
      throw const BookImportException('MOBI HUFF 记录无效。');
    }
    for (var codelen = 1; codelen <= 32; codelen++) {
      final minRaw = data.getUint32(off2 + (codelen - 1) * 8, Endian.big);
      final maxRaw = data.getUint32(off2 + (codelen - 1) * 8 + 4, Endian.big);
      _mincode[codelen] = _shl32(minRaw, 32 - codelen);
      _maxcode[codelen] = _shl32(maxRaw + 1, 32 - codelen) - 1;
    }
  }

  void _loadCdic(Uint8List cdic) {
    if (cdic.length < 16) return;
    final data = ByteData.sublistView(cdic);
    final phrases = data.getUint32(8, Endian.big);
    final bits = data.getUint32(12, Endian.big);
    final remaining = phrases - _dictionary.length;
    if (remaining <= 0) return;
    var n = 1 << bits;
    if (n > remaining) n = remaining;
    if (16 + n * 2 > cdic.length) {
      n = (cdic.length - 16) >> 1;
    }
    for (var i = 0; i < n; i++) {
      final off = data.getUint16(16 + i * 2, Endian.big);
      final blenAt = 16 + off;
      if (blenAt + 2 > cdic.length) continue;
      final blen = data.getUint16(blenAt, Endian.big);
      final start = blenAt + 2;
      final end = start + (blen & 0x7fff);
      if (end > cdic.length) continue;
      _dictionary.add(
        _CdicEntry(
          Uint8List.sublistView(cdic, start, end),
          (blen & 0x8000) != 0,
        ),
      );
    }
  }

  Uint8List unpack(
    Uint8List input, {
    int maxOutput = 64 * 1024 * 1024,
    int depth = 0,
  }) {
    if (depth > 64) throw const BookImportException('MOBI 压缩词典嵌套过深。');
    if (_dict1.isEmpty || _dictionary.isEmpty) {
      throw const BookImportException('MOBI Huffman 词典未加载。');
    }
    final data = Uint8List(input.length + 8);
    data.setRange(0, input.length, input);
    var bitsleft = input.length * 8;
    var pos = 0;
    var x = _readU64(data, pos);
    var n = 32;
    final out = <int>[];
    while (true) {
      if (n <= 0) {
        pos += 4;
        if (pos + 8 > data.length) break;
        x = _readU64(data, pos);
        n += 32;
      }
      final code = _shr32(x, n);
      final head = _dict1[(code >> 24) & 0xff];
      var codelen = head.codelen;
      if (codelen < 1 || codelen > 32) {
        throw const BookImportException('MOBI Huffman 码长无效。');
      }
      var maxcode = head.maxcode;
      if (!head.term) {
        while (codelen < 33 && code < _mincode[codelen]) {
          codelen++;
        }
        if (codelen > 32) break;
        maxcode = _maxcode[codelen];
      }
      n -= codelen;
      bitsleft -= codelen;
      if (bitsleft < 0) break;

      final r = _shr32(maxcode - code, 32 - codelen);
      if (r < 0 || r >= _dictionary.length) break;
      final entry = _dictionary[r];
      var slice = entry.bytes;
      if (!entry.isTerminal) {
        _dictionary[r] = _CdicEntry(Uint8List(0), true);
        slice = unpack(slice, maxOutput: maxOutput, depth: depth + 1);
        _dictionary[r] = _CdicEntry(slice, true);
      }
      if (out.length + slice.length > maxOutput) {
        throw const BookImportException('MOBI 解压正文超过安全大小。');
      }
      out.addAll(slice);
    }
    return Uint8List.fromList(out);
  }

  static int _readU64(Uint8List data, int pos) {
    // Big-endian 8-byte read; only the high 32 bits are used per step.
    var value = 0;
    for (var i = 0; i < 8 && pos + i < data.length; i++) {
      value = (value << 8) | data[pos + i];
    }
    // Pad with zeros if the tail is short.
    final have = data.length - pos < 8 ? data.length - pos : 8;
    if (have < 8) value <<= (8 - have) * 8;
    return value;
  }

  static int _shl32(int value, int shift) {
    if (shift <= 0) return value & 0xffffffff;
    return (value << shift) & 0xffffffffffffffff;
  }

  static int _shr32(int value, int shift) {
    if (shift <= 0) return value & 0xffffffff;
    return (value >> shift) & 0xffffffff;
  }
}

class _HuffEntry {
  const _HuffEntry(this.codelen, this.term, this.maxcode);
  final int codelen;
  final bool term;
  final int maxcode;
}

class _CdicEntry {
  _CdicEntry(this.bytes, this.isTerminal);
  final Uint8List bytes;
  final bool isTerminal;
}

class MobiDecoder {
  const MobiDecoder({this.pipeline = const HtmlTextPipeline()});

  final HtmlTextPipeline pipeline;

  static final _tocAnchor = RegExp(
    r'''<a\b[^>]*\bfilepos\s*=\s*["']?(\d+)["']?[^>]*>([\s\S]*?)</a\s*>''',
    caseSensitive: false,
  );
  static final _filePosMarker = RegExp(r'\[\[vellum-filepos:(\d+)\]\]');

  /// How far back a marker looks for an enclosing tag / character entity.
  static const _tagWindow = 4096;
  static const _entityWindow = 12;

  ImportedBook decode(String filename, Uint8List bytes) {
    try {
      if (bytes.length < 100) throw const BookImportException('MOBI 文件不完整。');
      final data = ByteData.sublistView(bytes);
      final records = data.getUint16(76, Endian.big);
      if (records < 2 || bytes.length < 78 + records * 8) {
        throw const BookImportException('MOBI 记录表无效。');
      }
      final offsets = List<int>.generate(
        records,
        (index) => data.getUint32(78 + index * 8, Endian.big),
      );
      final header = offsets.first;
      if (header + 20 > bytes.length ||
          ascii.decode(bytes.sublist(header + 16, header + 20)) != 'MOBI') {
        throw const BookImportException('不是受支持的经典 MOBI 文件。');
      }
      final compression = data.getUint16(header, Endian.big);
      final textLength = data.getUint32(header + 4, Endian.big);
      final textRecords = data.getUint16(header + 8, Endian.big);
      final textEncoding = data.getUint32(header + 28, Endian.big);
      final encryption = data.getUint16(header + 12, Endian.big);
      if (encryption != 0) {
        throw const BookImportException('加密/DRM MOBI 暂不支持。');
      }
      if (textRecords == 0 || textRecords >= records) {
        throw const BookImportException('MOBI 中没有正文记录。');
      }

      // Metadata: PalmDB name + EXTH + MOBI Full Name
      // (Fanqie: MobiParser.f() → nativeGetFullName / GetFullName).
      final meta = _readExth(bytes, data, header);
      final fullName = _mobiFullName(bytes, data, header);
      final title = _resolveTitle(
        filename: filename,
        palmName: _palmDbName(bytes),
        exthTitle: meta.updatedTitle,
        fullName: fullName,
      );
      final author = meta.author;

      final builder = BytesBuilder(copy: false);
      if (compression == 17480) {
        // Huffman/CDIC — common on Amazon-produced MOBI. Fanqie's
        // libmobiparser.so handles this via MobiHuffCdic; Vellum previously
        // only decoded PalmDOC (compression 2) and threw on these books.
        final huff = _findMagicRecord(bytes, offsets, textRecords + 1, 'HUFF');
        final cdic = _findAllMagicRecords(
          bytes,
          offsets,
          textRecords + 1,
          'CDIC',
        );
        if (huff == null || cdic.isEmpty) {
          throw const BookImportException('MOBI 使用 Huffman 压缩但缺少词典记录。');
        }
        final decoder = MobiHuffCdic()..load(huff, cdic);
        for (var index = 1; index <= textRecords; index++) {
          final remaining = textLength == 0
              ? null
              : textLength - builder.length;
          if (remaining != null && remaining <= 0) break;
          final start = offsets[index];
          final end = index + 1 < records ? offsets[index + 1] : bytes.length;
          if (start >= end || end > bytes.length) {
            throw const BookImportException('MOBI 正文记录无效。');
          }
          final record = Uint8List.sublistView(bytes, start, end);
          final decoded = decoder.unpack(
            record,
            maxOutput: 64 * 1024 * 1024 - builder.length,
          );
          if (remaining != null && decoded.length > remaining) {
            builder.add(Uint8List.sublistView(decoded, 0, remaining));
          } else {
            builder.add(decoded);
          }
        }
      } else {
        for (var index = 1; index <= textRecords; index++) {
          final remaining = textLength == 0
              ? null
              : textLength - builder.length;
          if (remaining != null && remaining <= 0) break;
          final recordLimit = remaining == null || remaining > 4096
              ? 4096
              : remaining;
          final start = offsets[index];
          final end = index + 1 < records ? offsets[index + 1] : bytes.length;
          if (start >= end || end > bytes.length) {
            throw const BookImportException('MOBI 正文记录无效。');
          }
          // A view, not a copy: palmDoc only reads its input.
          final record = Uint8List.sublistView(bytes, start, end);
          final decoded = compression == 2
              ? palmDoc(record, maxOutput: recordLimit)
              : record;
          builder.add(
            decoded.length <= recordLimit
                ? decoded
                : Uint8List.sublistView(decoded, 0, recordLimit),
          );
        }
      }
      final decodedText = decodeMobiText(builder.takeBytes(), textEncoding);
      final content = pipeline.convert(decodedText, 'mobi.html');
      final paragraphs = content.paragraphs;
      final tocEntries = mobiTocEntries(decodedText, paragraphs, textEncoding);
      final linkTargets = <int, int>{
        for (final entry in content.links.entries)
          if (content.anchors[entry.value] != null)
            entry.key: content.anchors[entry.value]!,
      };
      final firstImage = content.images.isEmpty
          ? null
          : firstImageRecord(bytes, offsets, textRecords);
      final imageBytes = <int, Uint8List>{};
      if (firstImage != null) {
        for (final entry in content.images.entries) {
          final image = mobiImage(bytes, offsets, firstImage, entry.value);
          if (image != null) imageBytes[entry.key] = image;
        }
      }
      if (paragraphs.isEmpty) {
        throw const BookImportException('MOBI 中没有可阅读的正文。');
      }
      final coverBytes =
          mobiCover(
            bytes,
            data,
            offsets,
            header,
            coverOffset: meta.coverOffset,
          ) ??
          firstImageAsCover(bytes, offsets, textRecords);
      return ImportedBook(
        title: title,
        author: author,
        format: BookFormat.mobi,
        paragraphs: paragraphs,
        coverBytes: coverBytes,
        linkTargets: linkTargets,
        tocEntries: tocEntries,
        imageBytes: imageBytes,
      );
    } on BookImportException {
      rethrow;
    } catch (_) {
      throw const BookImportException('无法读取此 MOBI 文件。');
    }
  }

  /// PalmDB database name — the 32-byte title stored at the file head.
  ///
  /// Historically ASCII-only, so Chinese books often carry pinyin here
  /// (`hali bote`) instead of the real title.
  String _palmDbName(Uint8List bytes) {
    if (bytes.length < 32) return '';
    final raw = ascii.decode(bytes.sublist(0, 32), allowInvalid: true);
    return raw.replaceAll('\x00', '').trim();
  }

  /// MOBI header "full name" — the real display title, pointed to by
  /// offset/length at record0+84/88 (MOBI header + 0x44/0x48).
  ///
  /// Fanqie exposes this via `nativeGetFullName`; it is usually the correct
  /// Chinese title when PalmDB is pinyin.
  String _mobiFullName(Uint8List bytes, ByteData data, int header) {
    try {
      if (header + 92 > bytes.length) return '';
      final offset = data.getUint32(header + 84, Endian.big);
      final length = data.getUint32(header + 88, Endian.big);
      if (length <= 0 || length > 2048) return '';
      if (offset <= 0 || offset + length > bytes.length) return '';
      final raw = bytes.sublist(offset, offset + length);
      return _decodeMobiMetaString(
        raw,
        declaredEncoding: data.getUint32(header + 28, Endian.big),
      );
    } catch (_) {
      return '';
    }
  }

  /// Decodes MOBI metadata bytes trying declared encoding → UTF-8 → GBK →
  /// latin1. Chinese MOBI files frequently store metadata in GBK even when
  /// the text-encoding field says cp1252.
  String _decodeMobiMetaString(List<int> raw, {int? declaredEncoding}) {
    if (raw.isEmpty) return '';
    String tryUtf8() => utf8.decode(raw, allowMalformed: false);
    String tryGbk() => gbk.decode(raw, allowMalformed: false);

    if (declaredEncoding == 65001) {
      try {
        final value = tryUtf8().trim();
        if (value.isNotEmpty && !_looksMojibake(value)) return value;
      } catch (_) {}
    }
    try {
      final value = tryUtf8().trim();
      if (value.isNotEmpty && !_looksMojibake(value)) return value;
    } catch (_) {}
    try {
      final value = tryGbk().trim();
      if (value.isNotEmpty && !_looksMojibake(value)) return value;
    } catch (_) {}
    return latin1.decode(raw, allowInvalid: true).trim();
  }

  /// Mojibake heuristic: a run of Latin-1 supplement chars with no CJK usually
  /// means the bytes were UTF-8/GBK decoded as latin1.
  static bool _looksMojibake(String value) {
    if (_hasCjk(value)) return false;
    final supplement = RegExp(r'[À-ÿ]{2,}').allMatches(value).length;
    return supplement >= 2;
  }

  static bool _hasCjk(String value) =>
      RegExp('[\\u4e00-\\u9fff\\u3400-\\u4dbf\\uf900-\\ufaff]').hasMatch(value);

  /// True when [value] is plausible shelf metadata, not a product code.
  @visibleForTesting
  static bool looksLikeBookTitle(String value) {
    final text = value.trim();
    if (text.length < 2 || text.length > 80) return false;
    // Pure digits / hex / id-ish tokens (ASIN, ISBN-ish, record ids).
    if (RegExp(r'^[0-9]+$').hasMatch(text)) return false;
    if (RegExp(r'^[0-9A-Fa-f]{6,}$').hasMatch(text)) return false;
    if (RegExp(
      r'^(EBOK|BOOK|BOK|ITEM)[0-9A-Za-z\-_]*$',
      caseSensitive: false,
    ).hasMatch(text)) {
      return false;
    }
    // Must contain at least one letter or CJK character.
    if (!RegExp(r'[A-Za-z一-鿿㐀-䶿]').hasMatch(text)) return false;
    // Reject strings that are mostly punctuation/symbols.
    final letters = RegExp(r'[A-Za-z一-鿿㐀-䶿0-9]').allMatches(text).length;
    return letters >= text.length * 0.4;
  }

  /// Spaced pinyin / romanisation heuristic (e.g. `hali bote`, `HaLi BoTe`).
  @visibleForTesting
  static bool looksLikePinyin(String value) {
    final text = value.trim();
    if (text.isEmpty || _hasCjk(text)) return false;
    if (!RegExp(r'^[A-Za-z\s·-]+$').hasMatch(text)) return false;
    final tokens = text
        .split(RegExp(r'[\s·-]+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.length < 2) return false;
    var totalLen = 0;
    var shortTokens = 0;
    for (final token in tokens) {
      totalLen += token.length;
      if (token.length <= 6 && RegExp(r'^[A-Za-z]+$').hasMatch(token)) {
        shortTokens++;
      }
    }
    final avg = totalLen / tokens.length;
    // Pinyin syllables cluster at 1–4 letters; English words run longer
    // (`Harry Potter` avg≈5.5, `hali bote` avg≈4.0).
    return avg <= 4.5 && shortTokens >= tokens.length * 0.8;
  }

  /// Scores a title candidate. Higher is better.
  ///
  /// Fanqie's `GetFullName` prefers the MOBI full-name field; when that is
  /// missing or romanised, a CJK filename (用户命名的「哈利·波特」) beats
  /// pinyin metadata.
  @visibleForTesting
  static int titleScore(String candidate, {required String fileTitle}) {
    var score = 0;
    if (!looksLikeBookTitle(candidate)) return -1000;
    if (_hasCjk(candidate)) score += 100;
    if (looksLikePinyin(candidate)) score -= 60;
    // Filename has CJK but this candidate does not → likely pinyin/English id.
    if (_hasCjk(fileTitle) && !_hasCjk(candidate)) score -= 40;
    if (candidate.length >= 2 && candidate.length <= 40) score += 10;
    if (candidate.length > 60) score -= 20;
    return score;
  }

  String _resolveTitle({
    required String filename,
    required String palmName,
    required String exthTitle,
    required String fullName,
  }) {
    final fileTitle = pipeline.titleFromFilename(filename);
    final candidates = <String>[exthTitle, fullName, palmName, fileTitle];
    String? best;
    var bestScore = -10000;
    for (final raw in candidates) {
      final cleaned = pipeline.chapterTitle(raw);
      if (cleaned.isEmpty) continue;
      final score = titleScore(cleaned, fileTitle: fileTitle);
      if (score > bestScore) {
        bestScore = score;
        best = cleaned;
      }
    }
    if (best != null && bestScore > 0) return best;
    return fileTitle;
  }

  /// First record after the text block whose first four bytes match [magic].
  Uint8List? _findMagicRecord(
    Uint8List bytes,
    List<int> offsets,
    int fromRecord,
    String magic,
  ) {
    final units = ascii.encode(magic);
    for (var record = fromRecord; record < offsets.length; record++) {
      final start = offsets[record];
      final end = record + 1 < offsets.length
          ? offsets[record + 1]
          : bytes.length;
      if (start + 4 > end || end > bytes.length) continue;
      if (bytes[start] == units[0] &&
          bytes[start + 1] == units[1] &&
          bytes[start + 2] == units[2] &&
          bytes[start + 3] == units[3]) {
        return Uint8List.sublistView(bytes, start, end);
      }
    }
    return null;
  }

  /// Every record after the text block whose first four bytes match [magic].
  /// CDIC dictionaries are often split across several records.
  List<Uint8List> _findAllMagicRecords(
    Uint8List bytes,
    List<int> offsets,
    int fromRecord,
    String magic,
  ) {
    final units = ascii.encode(magic);
    final found = <Uint8List>[];
    for (var record = fromRecord; record < offsets.length; record++) {
      final start = offsets[record];
      final end = record + 1 < offsets.length
          ? offsets[record + 1]
          : bytes.length;
      if (start + 4 > end || end > bytes.length) continue;
      if (bytes[start] == units[0] &&
          bytes[start + 1] == units[1] &&
          bytes[start + 2] == units[2] &&
          bytes[start + 3] == units[3]) {
        found.add(Uint8List.sublistView(bytes, start, end));
      }
    }
    return found;
  }

  Uint8List? firstImageAsCover(
    Uint8List bytes,
    List<int> offsets,
    int textRecords,
  ) {
    final record = firstImageRecord(bytes, offsets, textRecords);
    if (record == null) return null;
    return mobiImage(bytes, offsets, record, 1);
  }

  /// EXTH header: author (100), updated title (503), cover offset (201).
  _MobiExth _readExth(Uint8List bytes, ByteData data, int header) {
    var author = '';
    var updatedTitle = '';
    int? coverOffset;
    try {
      if (header + 0x44 > bytes.length) return const _MobiExth();
      final mobiHeaderLength = data.getUint32(header + 0x40, Endian.big);
      final exthStart = header + mobiHeaderLength;
      if (exthStart + 12 > bytes.length) return const _MobiExth();
      if (ascii.decode(bytes.sublist(exthStart, exthStart + 4)) != 'EXTH') {
        return const _MobiExth();
      }
      final recordCount = data.getUint32(exthStart + 8, Endian.big);
      var cursor = exthStart + 12;
      final declared = data.getUint32(header + 28, Endian.big);
      for (var i = 0; i < recordCount && cursor + 8 <= bytes.length; i++) {
        final type = data.getUint32(cursor, Endian.big);
        final length = data.getUint32(cursor + 4, Endian.big);
        if (length < 8 || cursor + length > bytes.length) break;
        final payload = bytes.sublist(cursor + 8, cursor + length);
        if (type == 100 && author.isEmpty) {
          author = _decodeMobiMetaString(payload, declaredEncoding: declared);
        } else if (type == 503 && updatedTitle.isEmpty) {
          updatedTitle = _decodeMobiMetaString(
            payload,
            declaredEncoding: declared,
          );
        } else if (type == 201 && payload.length >= 4) {
          coverOffset = ByteData.sublistView(payload).getUint32(0, Endian.big);
        }
        cursor += length;
      }
    } catch (_) {
      // Metadata is best-effort; a malformed EXTH must not fail the import.
    }
    return _MobiExth(
      author: author,
      updatedTitle: updatedTitle,
      coverOffset: coverOffset,
    );
  }

  int? firstImageRecord(Uint8List bytes, List<int> offsets, int textRecords) {
    for (var record = textRecords + 1; record < offsets.length; record++) {
      final start = offsets[record];
      final end = record + 1 < offsets.length
          ? offsets[record + 1]
          : bytes.length;
      if (start >= end || end > bytes.length) continue;
      // Only the magic number matters, so read it in place.
      final length = end - start;
      if (length > 3 && bytes[start] == 0xff && bytes[start + 1] == 0xd8) {
        return record;
      }
      if (length > 8 && bytes[start] == 0x89 && bytes[start + 1] == 0x50) {
        return record;
      }
      if (length > 6 && bytes[start] == 0x47 && bytes[start + 1] == 0x49) {
        return record;
      }
    }
    return null;
  }

  /// MOBI `recindex` is 1-based: 1 maps to the first image record after text.
  Uint8List? mobiImage(
    Uint8List bytes,
    List<int> offsets,
    int firstImageRecord,
    int imageIndex,
  ) {
    if (imageIndex <= 0) return null;
    final record = firstImageRecord + imageIndex - 1;
    if (record <= 0 || record >= offsets.length) return null;
    final start = offsets[record];
    final end = record + 1 < offsets.length
        ? offsets[record + 1]
        : bytes.length;
    if (start >= end || end > bytes.length) return null;
    final image = Uint8List.sublistView(bytes, start, end);
    final jpeg = image.length > 3 && image[0] == 0xff && image[1] == 0xd8;
    final png = image.length > 8 && image[0] == 0x89 && image[1] == 0x50;
    final gif = image.length > 6 && image[0] == 0x47 && image[1] == 0x49;
    return jpeg || png || gif ? image.sublist(0) : null;
  }

  Uint8List? mobiCover(
    Uint8List bytes,
    ByteData data,
    List<int> offsets,
    int header, {
    int? coverOffset,
  }) {
    if (header + 112 > bytes.length) return null;
    final firstImage = data.getUint32(header + 108, Endian.big);
    // EXTH 201 is an offset relative to the first image record; some producers
    // store an absolute record index instead. Try relative first.
    final candidates = <int>[
      if (coverOffset != null && firstImage != 0) firstImage + coverOffset,
      ?coverOffset,
      firstImage,
    ];
    for (final record in candidates) {
      if (record <= 0 || record >= offsets.length) continue;
      final start = offsets[record];
      final end = record + 1 < offsets.length
          ? offsets[record + 1]
          : bytes.length;
      if (start >= end || end > bytes.length) continue;
      final image = Uint8List.sublistView(bytes, start, end);
      final isJpeg = image.length > 3 && image[0] == 0xff && image[1] == 0xd8;
      final isPng = image.length > 8 && image[0] == 0x89 && image[1] == 0x50;
      if (isJpeg || isPng) return image.sublist(0);
    }
    return null;
  }

  String decodeMobiText(Uint8List bytes, int encoding) => encoding == 65001
      ? utf8.decode(bytes, allowMalformed: true)
      : latin1.decode(bytes, allowInvalid: true);

  /// Decodes one PalmDOC record. Returns a [Uint8List] so the UTF-8 / latin1
  /// decoders downstream can take their typed-data fast path.
  Uint8List palmDoc(Uint8List input, {int? maxOutput}) {
    final output = <int>[];
    for (
      var index = 0;
      index < input.length && (maxOutput == null || output.length < maxOutput);
      index++
    ) {
      final value = input[index];
      if (value == 0) {
        output.add(value);
      } else if (value <= 8) {
        if (index + value >= input.length) {
          throw const BookImportException('MOBI PalmDOC 压缩数据无效。');
        }
        output.addAll(input.sublist(++index, index + value));
        index += value - 1;
      } else if (value <= 0x7f) {
        output.add(value);
      } else if (value <= 0xbf) {
        if (++index >= input.length) {
          throw const BookImportException('MOBI PalmDOC 引用无效。');
        }
        final pair = (value << 8) | input[index];
        final length = (pair & 0x7) + 3;
        final distance = ((value & 0x3f) << 5) | (input[index] >> 3);
        if (distance == 0 || distance > output.length) {
          throw const BookImportException('MOBI PalmDOC 回溯无效。');
        }
        for (var repeat = 0; repeat < length; repeat++) {
          output.add(output[output.length - distance]);
        }
      } else {
        output
          ..add(0x20)
          ..add(value ^ 0x80);
      }
    }
    return Uint8List.fromList(output);
  }

  List<BookTocEntry> mobiTocEntries(
    String source,
    List<String> paragraphs,
    int encoding,
  ) {
    final matches = _tocAnchor.allMatches(source).toList();
    if (matches.isEmpty || paragraphs.isEmpty) return const [];

    final filePositions = [
      for (final match in matches) int.parse(match.group(1)!),
    ];
    final offsets = encoding == 65001
        ? utf8OffsetsToStringOffsets(source, filePositions)
        : [
            for (final position in filePositions)
              position.clamp(0, source.length),
          ];
    // Resolve every marker position against the untouched source and splice all
    // markers in one pass. Re-inserting into a growing string one entry at a
    // time is O(chapters × book size) and dominates import time for novels
    // with a chapter entry per scene.
    final inserts = <({int offset, int index})>[
      for (var index = 0; index < offsets.length; index++)
        (offset: _markerOffset(source, offsets[index]), index: index),
    ]..sort((a, b) => a.offset.compareTo(b.offset));
    final markedBuffer = StringBuffer();
    var cursor = 0;
    for (final insert in inserts) {
      if (insert.offset > cursor) {
        markedBuffer.write(source.substring(cursor, insert.offset));
        cursor = insert.offset;
      }
      markedBuffer.write('[[vellum-filepos:${insert.index}]]');
    }
    markedBuffer.write(source.substring(cursor));

    final positions = <int, int>{};
    final markedParagraphs = pipeline.splitParagraphs(
      pipeline.htmlToText(markedBuffer.toString()),
    );
    // A marker dropped between block tags (`…</h2><p>第一章`) becomes a paragraph
    // of its own, which the book's own paragraph list does not contain — every
    // later entry would then be off by one. Number only paragraphs that carry
    // text, and point a marker-only paragraph at the next real one.
    final hasMarkerOnly = markedParagraphs.any(_isMarkerOnlyParagraph);
    final effective = hasMarkerOnly
        ? _numberTextParagraphs(markedParagraphs)
        : null;
    for (var index = 0; index < markedParagraphs.length; index++) {
      final target = effective == null ? index : effective[index];
      for (final marker in _filePosMarker.allMatches(markedParagraphs[index])) {
        positions[int.parse(marker.group(1)!)] = target;
      }
    }

    // Fill missing hits from the nearest previous known paragraph so a single
    // lost marker does not collapse a chapter onto paragraph 0.
    final resolved = List<int>.filled(matches.length, -1);
    var last = -1;
    for (var index = 0; index < matches.length; index++) {
      final hit = positions[index];
      if (hit != null) {
        last = hit;
        resolved[index] = hit;
      } else {
        resolved[index] = last;
      }
    }
    var next = paragraphs.length - 1;
    for (var index = matches.length - 1; index >= 0; index--) {
      if (positions[index] != null) {
        next = positions[index]!;
      } else if (resolved[index] < 0) {
        resolved[index] = next;
      }
    }

    final entries = <BookTocEntry>[];
    final seen = <int>{};
    var total = 0;
    for (var index = 0; index < matches.length; index++) {
      total++;
      final title = cleanMobiTocTitle(matches[index].group(2) ?? '');
      if (isDirtyTocTitle(title)) {
        continue;
      }
      final paragraphIndex = resolved[index].clamp(0, paragraphs.length - 1);
      if (!seen.add(paragraphIndex)) continue;
      entries.add(BookTocEntry(title: title, paragraphIndex: paragraphIndex));
    }
    // If most anchors were junk (encoding damage, HTML leftovers), drop the
    // whole TOC so `chapterEntries` can rebuild from body-text heuristics
    // instead of showing a half-broken catalog.
    if (total > 0 && entries.length * 3 < total) {
      return const [];
    }
    return entries;
  }

  /// Aggressive TOC-label cleaner for MOBI `filepos` anchors.
  ///
  /// Fanqie's native parser feeds labels through `TTHtmlParser`; our anchors
  /// often still carry tags, entities, control bytes or encoding damage.
  @visibleForTesting
  static String cleanMobiTocTitle(String raw) {
    var text = raw;
    // Decode entities first so escaped markup (`&lt;b&gt;`) becomes real tags
    // and can be stripped in the next pass.
    text = text.replaceAllMapped(RegExp(r'&(#x?[0-9A-Fa-f]+|[a-zA-Z]+);'), (
      match,
    ) {
      final body = match.group(1)!;
      if (body.startsWith('#')) {
        final isHex = body.length > 2 && (body[1] == 'x' || body[1] == 'X');
        final digits = isHex ? body.substring(2) : body.substring(1);
        final code = int.tryParse(digits, radix: isHex ? 16 : 10);
        if (code != null && code > 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return ' ';
      }
      const named = {
        'nbsp': ' ',
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        'apos': "'",
        'hellip': '…',
        'mdash': '—',
        'ndash': '–',
      };
      return named[body.toLowerCase()] ?? ' ';
    });
    // Strip tags (including unterminated) and reader markers.
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text.replaceAll(RegExp(r'\[\[[^\]]*\]\]'), ' ');
    // Second entity pass is unnecessary; filepos / control bytes next.
    text = text.replaceAll(
      RegExp('filepos\\s*=\\s*["\']?\\d+["\']?', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    // Collapse whitespace (incl. fullwidth / BOM residue).
    text = text
        .replaceAll('﻿', ' ')
        .replaceAll('　', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text;
  }

  /// True when a TOC label is unusable junk rather than a chapter name.
  @visibleForTesting
  static bool isDirtyTocTitle(String title) {
    final text = title.trim();
    if (text.length < 2 || text.length > 60) return true;
    // Mojibake: Latin-1 supplement run without CJK (GBK/UTF-8 read as latin1).
    if (!_hasCjk(text) && RegExp(r'[À-ÿ]{3,}').hasMatch(text)) return true;
    // Replacement characters from failed decodes.
    if (text.contains('�')) return true;
    // Mostly symbols / punctuation / leftover markup glyphs.
    final letters = RegExp(r'[A-Za-z0-9一-鿿㐀-䶿]').allMatches(text).length;
    if (letters < text.length * 0.35) return true;
    // Classic junk anchors: lone punctuation, "…" only, etc.
    if (RegExp(r'^[\s\.\,\;\:\-\_\|\*\/\\\#\@\!\?…—–]+$').hasMatch(text)) {
      return true;
    }
    return false;
  }

  /// True when a paragraph holds nothing but TOC markers.
  bool _isMarkerOnlyParagraph(String paragraph) {
    if (!paragraph.startsWith('[[vellum-filepos:')) return false;
    return paragraph.replaceAll(_filePosMarker, '').trim().isEmpty;
  }

  /// Paragraph indexes as the book sees them: marker-only paragraphs inherit
  /// the index of the next paragraph that has text.
  List<int> _numberTextParagraphs(List<String> paragraphs) {
    final effective = List<int>.filled(paragraphs.length, 0);
    var counted = -1;
    for (var index = 0; index < paragraphs.length; index++) {
      if (_isMarkerOnlyParagraph(paragraphs[index])) continue;
      counted++;
      effective[index] = counted;
    }
    var next = counted < 0 ? 0 : counted;
    for (var index = paragraphs.length - 1; index >= 0; index--) {
      if (!_isMarkerOnlyParagraph(paragraphs[index])) {
        next = effective[index];
        continue;
      }
      effective[index] = next;
    }
    return effective;
  }

  /// Nudges a marker offset so it never lands inside a tag or a character
  /// entity, which would split it and stop the marker from surviving HTML
  /// conversion.
  ///
  /// The look-backs are deliberately windowed: `lastIndexOf` on the whole book
  /// text costs a full backwards scan per chapter entry, which dominated import
  /// time. A real tag is far shorter than [_tagWindow].
  int _markerOffset(String source, int raw) {
    var offset = raw.clamp(0, source.length);
    final lastOpen = _lastWithin(source, 0x3c, offset, _tagWindow);
    final lastClose = _lastWithin(source, 0x3e, offset, _tagWindow);
    if (lastOpen > lastClose) {
      var closing = _firstWithin(source, 0x3e, offset, _tagWindow);
      if (closing < 0 && offset + _tagWindow < source.length) {
        // Tag longer than the window: fall back to an exact scan.
        closing = source.indexOf('>', offset + _tagWindow);
      }
      offset = closing < 0 ? source.length : closing + 1;
    }
    final entityStart = _lastWithin(source, 0x26, offset, _entityWindow);
    final entityEnd = entityStart < 0
        ? -1
        : _firstWithin(source, 0x3b, offset, _entityWindow);
    if (entityStart >= 0 &&
        entityStart < offset &&
        entityEnd >= 0 &&
        entityEnd - entityStart < 12) {
      offset = entityEnd + 1;
    }
    return offset;
  }

  /// Nearest [unit] at or before [from], searching at most [limit] units back.
  int _lastWithin(String source, int unit, int from, int limit) {
    var index = from >= source.length ? source.length - 1 : from;
    final stop = index - limit;
    for (; index > stop && index >= 0; index--) {
      if (source.codeUnitAt(index) == unit) return index;
    }
    return -1;
  }

  /// Next [unit] at or after [from], searching at most [limit] units forward.
  int _firstWithin(String source, int unit, int from, int limit) {
    final stop = from + limit;
    final end = stop > source.length ? source.length : stop;
    for (var index = from; index < end; index++) {
      if (source.codeUnitAt(index) == unit) return index;
    }
    return -1;
  }

  List<int> utf8OffsetsToStringOffsets(String source, List<int> targets) {
    final ordered = <({int target, int original})>[
      for (var index = 0; index < targets.length; index++)
        (target: targets[index].clamp(0, 1 << 62), original: index),
    ]..sort((a, b) => a.target.compareTo(b.target));
    final result = List<int>.filled(targets.length, source.length);
    var targetIndex = 0;
    var byteOffset = 0;
    var stringOffset = 0;
    for (final rune in source.runes) {
      while (targetIndex < ordered.length &&
          ordered[targetIndex].target <= byteOffset) {
        result[ordered[targetIndex].original] = stringOffset;
        targetIndex++;
      }
      byteOffset += rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      stringOffset += rune > 0xffff ? 2 : 1;
    }
    while (targetIndex < ordered.length) {
      result[ordered[targetIndex].original] = source.length;
      targetIndex++;
    }
    return result;
  }
}
