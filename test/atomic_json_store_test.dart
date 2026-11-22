import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/atomic_json_store.dart';

/// The failure this pins down: a crash mid-write left a half-written document,
/// every reader then reported "empty", and the next save persisted that empty
/// document over the good one. The reader's notes were gone and nothing had
/// said a word.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vellum_atomic_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a write is visible whole or not at all', () async {
    final file = File('${dir.path}/doc.json');
    await file.writeAsString('["old"]');
    await AtomicJsonStore.write(file, '["new"]');

    expect(await file.readAsString(), '["new"]');
    // The staged file must not survive a successful publish.
    expect(
      await File('${file.path}${AtomicJsonStore.stagingSuffix}').exists(),
      isFalse,
    );
  });

  test('a missing document is "missing", not "damaged"', () async {
    final result = await AtomicJsonStore.read(File('${dir.path}/none.json'));
    expect(result.missing, isTrue);
    expect(result.damaged, isFalse);
    expect(result.text, isNull);
  });

  test('a truncated document is quarantined, not silently emptied', () async {
    final file = File('${dir.path}/doc.json');
    // Half a JSON array — exactly what a killed write used to leave behind.
    await file.writeAsString('[{"id":"n1","text":"太祖本纪"');

    final result = await AtomicJsonStore.read(file);

    expect(result.damaged, isTrue);
    expect(result.quarantined, isTrue);
    expect(await file.exists(), isFalse, reason: 'the bad file is moved aside');
    final kept = File('${file.path}${AtomicJsonStore.quarantineSuffix}');
    expect(
      await kept.readAsString(),
      '[{"id":"n1","text":"太祖本纪"',
      reason: 'the original bytes are kept for recovery',
    );
  });

  test('an empty document counts as damaged', () async {
    final file = File('${dir.path}/empty.json');
    await file.writeAsString('');

    final result = await AtomicJsonStore.read(file);

    expect(result.damaged, isTrue);
    expect(result.quarantined, isTrue);
  });

  test('serialised runs never overlap', () async {
    var inside = 0;
    var maxInside = 0;
    final order = <int>[];

    await Future.wait([
      for (var i = 0; i < 8; i++)
        AtomicJsonStore.serialised('key', () async {
          inside++;
          maxInside = inside > maxInside ? inside : maxInside;
          // Yield across several event-loop turns: without the queue this is
          // exactly where two read-modify-writes would interleave.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          order.add(i);
          inside--;
        }),
    ]);

    expect(maxInside, 1, reason: 'only one operation may be inside at a time');
    expect(order, [0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test('a failed operation does not wedge the queue', () async {
    await expectLater(
      AtomicJsonStore.serialised('key', () async {
        throw const FileSystemException('disk full');
      }),
      throwsA(isA<FileSystemException>()),
    );

    var ran = false;
    await AtomicJsonStore.serialised('key', () async {
      ran = true;
    });
    expect(ran, isTrue, reason: 'the next caller must still run');
  });

  test('a document round-trips through the store unchanged', () async {
    final file = File('${dir.path}/doc.json');
    final payload = jsonEncode([
      {'id': 'n1', 'note': '批注 · 太史公曰'},
    ]);
    await AtomicJsonStore.write(file, payload);

    final result = await AtomicJsonStore.read(file);
    expect(result.damaged, isFalse);
    expect(result.text, payload);
    expect(jsonDecode(result.text!), [{'id': 'n1', 'note': '批注 · 太史公曰'}]);
  });
}
