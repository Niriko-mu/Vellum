import 'package:flutter_test/flutter_test.dart';

/// How many page turns a burst of taps may queue.
///
/// While a cover turn animates, further taps are queued rather than dropped,
/// so a fast reader is not made to wait for each animation. The queue must be
/// bounded: each queued turn lands the reader one page further, so an unbounded
/// queue turns "tap ten times quickly" into a leap across a chapter - and the
/// animation only ever showed one page turning.
void main() {
  /// Mirrors the clamp in changePage (reader_page_state_surface_rendering).
  int enqueue(int queued, int delta, {int cap = 3}) =>
      (queued + delta).clamp(-cap, cap);

  test('a few queued turns are kept', () {
    expect(enqueue(0, 1), 1);
    expect(enqueue(1, 1), 2);
    expect(enqueue(2, 1), 3);
  });

  test('the queue stops growing at the cap', () {
    var queued = 0;
    for (var i = 0; i < 20; i++) {
      queued = enqueue(queued, 1);
    }
    expect(queued, 3, reason: 'twenty taps must not become a twenty-page leap');
  });

  test('backwards taps are capped the same way', () {
    var queued = 0;
    for (var i = 0; i < 20; i++) {
      queued = enqueue(queued, -1);
    }
    expect(queued, -3);
  });

  test('tapping backwards while forwards is queued cancels out', () {
    var queued = enqueue(0, 1);
    queued = enqueue(queued, 1);
    queued = enqueue(queued, -1);
    expect(queued, 1, reason: 'a correction should not leave a phantom turn');
  });

  test('the cap cannot be exceeded in either direction at once', () {
    expect(enqueue(3, 5), 3);
    expect(enqueue(-3, -5), -3);
  });
}
