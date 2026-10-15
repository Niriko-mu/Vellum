import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'tts_preferences.dart';
import 'tts_text.dart';

/// On-device MP3 cache for synthesized segments.
///
/// Keys cover every input that changes the audio (provider, model, voice,
/// speed, book, paragraph, text), so switching settings invalidates naturally.
/// The cache is capped and pruned oldest-first, and its size feeds the
/// storage-management page.
class TtsCache {
  const TtsCache({this.maxBytes = 256 * 1024 * 1024});

  /// LRU cap; beyond this the oldest files are removed.
  final int maxBytes;

  Future<Directory> directory() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}tts_audio',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Stable cache key for one segment.
  String keyFor({
    required TtsPreferences preferences,
    required String bookId,
    required SpeakableSegment segment,
  }) {
    final source = [
      preferences.provider.name,
      preferences.model,
      preferences.voice,
      preferences.speed.toStringAsFixed(2),
      bookId,
      segment.paragraphIndex,
      segment.sentenceIndex,
      segment.text.length,
      _hash(segment.text),
    ].join('|');
    return _hash(source);
  }

  /// Returns the cached file when one exists.
  Future<File?> lookup(String key) async {
    final file = File(
      '${(await directory()).path}${Platform.pathSeparator}$key.mp3',
    );
    if (!await file.exists()) return null;
    // Pruning uses modified time as the last-use marker, including cache hits.
    await file.setLastModified(DateTime.now());
    return file;
  }

  /// Persists [bytes] under [key] and prunes the cache to its cap.
  Future<File> write(String key, Uint8List bytes) async {
    final dir = await directory();
    final file = File('${dir.path}${Platform.pathSeparator}$key.mp3');
    await file.writeAsBytes(bytes, flush: true);
    await prune();
    return file;
  }

  Future<int> sizeInBytes() async {
    var total = 0;
    final dir = await directory();
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clear() async {
    final dir = await directory();
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }

  /// Removes oldest files until the cache fits [maxBytes].
  Future<void> prune() async {
    final dir = await directory();
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }
    if (files.isEmpty) return;
    var total = 0;
    final byDate = <(DateTime, File)>[];
    for (final file in files) {
      final stat = await file.stat();
      total += stat.size;
      byDate.add((stat.modified, file));
    }
    if (total <= maxBytes) return;
    byDate.sort((a, b) => a.$1.compareTo(b.$1));
    for (final entry in byDate) {
      if (total <= maxBytes) break;
      final stat = await entry.$2.stat();
      total -= stat.size;
      try {
        await entry.$2.delete();
      } catch (_) {
        // A file vanishing mid-prune is fine.
      }
    }
  }

  /// FNV-1a, same style as the book storage ids — no crypto dependency needed.
  static String _hash(String source) {
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
