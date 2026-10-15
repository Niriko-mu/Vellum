import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Run in the import worker: shelf thumbnails do not need scan resolution.
Uint8List? optimizeBookCover(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return bytes;
  try {
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    // Refuse pathological decoded allocations. Unsupported covers remain
    // readable by Flutter's native codec and can be replaced by the user.
    if (info == null || info.width * info.height > 40 * 1024 * 1024)
      return bytes;
    var cover = decoder!.decodeFrame(0);
    if (cover == null) return bytes;
    cover = image.bakeOrientation(cover);
    if (cover.width > 1600 || cover.height > 1600) {
      cover = image.copyResize(
        cover,
        width: cover.width >= cover.height ? 1600 : null,
        height: cover.height > cover.width ? 1600 : null,
        interpolation: image.Interpolation.average,
      );
    }
    return Uint8List.fromList(
      cover.hasAlpha
          ? image.encodePng(cover)
          : image.encodeJpg(cover, quality: 85),
    );
  } catch (_) {
    return bytes;
  }
}
