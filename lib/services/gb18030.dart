import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;

import 'gb18030_ranges.dart';

bool _lead(int byte) => byte >= 0x81 && byte <= 0xfe;
bool _digit(int byte) => byte >= 0x30 && byte <= 0x39;

/// Size at a known character boundary, also used by TXT chunking.
int gb18030SequenceLength(List<int> bytes, int index) {
  if (!_lead(bytes[index])) return 1;
  if (index + 3 < bytes.length &&
      _digit(bytes[index + 1]) &&
      _lead(bytes[index + 2]) &&
      _digit(bytes[index + 3]))
    return 4;
  return 2;
}

/// GB18030 extends GBK with four-byte sequences, including non-BMP characters.
/// The charset package aliases GB18030 to GBK; implement those ranges here.
String decodeGb18030(Uint8List bytes) {
  final result = StringBuffer();
  var start = 0;
  var index = 0;
  while (index < bytes.length) {
    final size = gb18030SequenceLength(bytes, index);
    if (size != 4) {
      index += size;
      continue;
    }
    if (start < index) {
      result.write(
        gbk.decode(
          Uint8List.sublistView(bytes, start, index),
          allowMalformed: true,
        ),
      );
    }
    final pointer =
        (((bytes[index] - 0x81) * 10 + bytes[index + 1] - 0x30) * 126 +
                bytes[index + 2] -
                0x81) *
            10 +
        bytes[index + 3] -
        0x30;
    var low = 0;
    var high = gb18030Ranges.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (gb18030Ranges[mid].$1 <= pointer) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final range = gb18030Ranges[low];
    final code = range.$2 + pointer - range.$1;
    result.writeCharCode(
      (pointer > 39419 && pointer < 189000) || code > 0x10ffff ? 0xfffd : code,
    );
    index += 4;
    start = index;
  }
  if (start < bytes.length) {
    result.write(
      gbk.decode(Uint8List.sublistView(bytes, start), allowMalformed: true),
    );
  }
  return result.toString();
}
