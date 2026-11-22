import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/tts_cache.dart';
import 'package:vellum/services/tts_preferences.dart';
import 'package:vellum/services/tts_text.dart';

/// The cache wrote and pruned per sentence. Pruning walks the whole directory
/// and stats every file, so a book with a thousand cached sentences meant a
/// thousand stats after every single sentence — continuous disk churn while
/// listening, which is exactly when the device is expected to be idle.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vellum_tts_cache_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('writes are cheap until the prune interval is reached', () async {
    final cache = _TempCache(root);

    final writes = <int>[];
    for (var i = 0; i < 8; i++) {
      await cache.write('k$i', Uint8List.fromList([i]));
      writes.add(cache.pruneCount);
    }

    expect(
      writes.every((count) => count == 0),
      isTrue,
      reason: 'eight small writes must not trigger a directory scan',
    );
    expect(cache.pruneCount, 0);
  });

  test('the cache still prunes eventually', () async {
    final cache = _TempCache(root);
    for (var i = 0; i < 40; i++) {
      await cache.write('k$i', Uint8List.fromList([i]));
    }

    expect(
      cache.pruneCount,
      greaterThan(0),
      reason: 'the cap must be enforced, just not after every sentence',
    );
  });

  test('a hit does not rewrite the timestamp every time', () async {
    final cache = _TempCache(root);
    await cache.write('hit', Uint8List.fromList([1, 2, 3]));

    final file = await cache.lookupRaw('hit');
    final first = (await file!.stat()).modified;

    // Two reads inside the touch interval: the metadata must be left alone.
    await cache.lookup('hit');
    await cache.lookup('hit');

    final after = (await file.stat()).modified;
    expect(
      after,
      first,
      reason: 'a fresh hit is already recent; rewriting it is a needless write',
    );
  });

  test('keys cover every input that changes the audio', () {
    const cache = TtsCache();
    const preferences = TtsPreferences(
      provider: TtsProvider.openai,
      baseUrl: 'https://api.example.com',
      apiKey: 'k',
      model: 'tts-1',
      voice: 'alloy',
      speed: 1.0,
    );
    const segment = SpeakableSegment(
      paragraphIndex: 3,
      sentenceIndex: 1,
      text: '一句话。',
    );

    final key = cache.keyFor(
      preferences: preferences,
      bookId: 'b1',
      segment: segment,
    );
    final same = cache.keyFor(
      preferences: preferences,
      bookId: 'b1',
      segment: segment,
    );
    expect(key, same);

    final faster = cache.keyFor(
      preferences: preferences.copyWith(speed: 1.25),
      bookId: 'b1',
      segment: segment,
    );
    expect(faster, isNot(key), reason: 'speed changes the audio');
  });
}

/// A cache rooted in a temp directory, counting the prunes it performs.
class _TempCache extends TtsCache {
  _TempCache(this.root);

  final Directory root;
  int pruneCount = 0;

  @override
  Future<Directory> directory() async {
    final dir = Directory('${root.path}/tts_audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<void> prune() async {
    pruneCount++;
    await super.prune();
  }

  Future<File?> lookupRaw(String key) async {
    final dir = await directory();
    final file = File('${dir.path}/$key.mp3');
    return await file.exists() ? file : null;
  }
}
