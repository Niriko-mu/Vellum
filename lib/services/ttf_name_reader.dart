import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _maxNameTableBytes = 1024 * 1024;

bool _isFontSignature(ByteData data) => switch (data.getUint32(0)) {
  0x00010000 || 0x74727565 || 0x4f54544f || 0x74797031 => true,
  _ => false,
};

/// Reads only the SFNT directory (at most 64 KiB), never glyph outlines.
Future<Uint8List> _fontDirectory(RandomAccessFile file) async {
  final length = await file.length();
  if (length < 12) throw const FormatException('字体文件不完整');
  final header = await file.read(12);
  final data = ByteData.sublistView(header);
  final count = data.getUint16(4);
  if (!_isFontSignature(data) ||
      count == 0 ||
      count > 4096 ||
      12 + count * 16 > length) {
    throw const FormatException('不是有效的 TTF 字体');
  }
  final directory = await file.read(count * 16);
  if (directory.length != count * 16) {
    throw const FormatException('字体目录不完整');
  }
  return directory;
}

Future<void> validateFontFile(File source) async {
  final file = await source.open();
  try {
    final directory = await _fontDirectory(file);
    final data = ByteData.sublistView(directory);
    final length = await file.length();
    var hasData = false;
    for (var at = 0; at < directory.length; at += 16) {
      final offset = data.getUint32(at + 8);
      final size = data.getUint32(at + 12);
      if (size > 0) hasData = true;
      if (offset > length || size > length - offset) {
        throw const FormatException('字体数据表损坏');
      }
    }
    if (!hasData) throw const FormatException('字体数据为空');
  } finally {
    await file.close();
  }
}

/// Build a tiny one-table SFNT for the existing byte parser. Keeping this
/// bounded also makes listing hundreds of large CJK fonts inexpensive.
Future<String?> readFontDisplayNameFromFile(File source) async {
  final file = await source.open();
  try {
    final directory = await _fontDirectory(file);
    final data = ByteData.sublistView(directory);
    final length = await file.length();
    for (var at = 0; at < directory.length; at += 16) {
      if (data.getUint32(at) != 0x6e616d65) continue; // name
      final offset = data.getUint32(at + 8);
      final size = data.getUint32(at + 12);
      if (size < 6 ||
          size > _maxNameTableBytes ||
          offset > length ||
          size > length - offset)
        return null;
      await file.setPosition(offset);
      final table = await file.read(size);
      if (table.length != size) return null;
      final bytes = Uint8List(28 + size);
      final wrapper = ByteData.sublistView(bytes);
      wrapper.setUint32(0, 0x00010000);
      wrapper.setUint16(4, 1);
      wrapper.setUint32(12, 0x6e616d65);
      wrapper.setUint32(20, 28);
      wrapper.setUint32(24, size);
      bytes.setRange(28, bytes.length, table);
      return readTtfDisplayName(bytes);
    }
    return null;
  } on FormatException {
    return null;
  } finally {
    await file.close();
  }
}

/// Resolves the font label exposed to the user.
///
/// The TTF/OTF internal `name` table is authoritative. The filename is used
/// only when that metadata is missing, invalid, or empty.
String resolveImportedFontDisplayName({
  required Uint8List bytes,
  required String filename,
}) {
  final internalName = readTtfDisplayName(bytes)?.trim();
  return (internalName?.isNotEmpty ?? false) ? internalName! : filename;
}

/// Reads the human-readable font name from a TTF/OTF `name` table.
/// Prefers Full name (ID 4), then Typographic Family (16), then Family (1).
String? readTtfDisplayName(Uint8List bytes) {
  try {
    if (bytes.length < 12) return null;
    final data = ByteData.sublistView(bytes);
    final tag = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    // OTTO = CFF OpenType; \x00\x01\x00\x00 or 'true' = TTF.
    final isSfnt =
        tag == '\u0000\u0001\u0000\u0000' ||
        tag == 'true' ||
        tag == 'OTTO' ||
        tag == 'typ1';
    if (!isSfnt) return null;

    final numTables = data.getUint16(4, Endian.big);
    var nameOffset = -1;
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      if (rec + 16 > bytes.length) break;
      final tableTag = ascii.decode(
        bytes.sublist(rec, rec + 4),
        allowInvalid: true,
      );
      if (tableTag == 'name') {
        nameOffset = data.getUint32(rec + 8, Endian.big);
        break;
      }
    }
    if (nameOffset < 0 || nameOffset + 6 > bytes.length) return null;

    final nameCount = data.getUint16(nameOffset + 2, Endian.big);
    final stringOffset = data.getUint16(nameOffset + 4, Endian.big);
    final stringsStart = nameOffset + stringOffset;

    String? full;
    String? typographic;
    String? family;
    for (var i = 0; i < nameCount; i++) {
      final rec = nameOffset + 6 + i * 12;
      if (rec + 12 > bytes.length) break;
      final platformId = data.getUint16(rec, Endian.big);
      final nameId = data.getUint16(rec + 6, Endian.big);
      if (nameId != 1 && nameId != 4 && nameId != 16) continue;
      final length = data.getUint16(rec + 8, Endian.big);
      final offset = data.getUint16(rec + 10, Endian.big);
      final start = stringsStart + offset;
      if (start < 0 || start + length > bytes.length || length == 0) {
        continue;
      }
      final raw = bytes.sublist(start, start + length);
      // Windows (3) name records are UTF-16BE; Mac (1) is usually ASCII.
      final value = platformId == 3
          ? _decodeUtf16Be(raw).trim()
          : utf8.decode(raw, allowMalformed: true).trim();
      if (value.isEmpty) continue;
      if (nameId == 4 && full == null) full = value;
      if (nameId == 16 && typographic == null) typographic = value;
      if (nameId == 1 && family == null) family = value;
    }
    return full ?? typographic ?? family;
  } catch (_) {
    return null;
  }
}

String _decodeUtf16Be(List<int> bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}
