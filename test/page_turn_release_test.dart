import 'package:flutter_test/flutter_test.dart';

/// When a released drag commits a page turn.
///
/// Two inputs decide it: how far the page travelled, and whether the finger was
/// still moving at release. The second is the fragile one - velocity is sampled
/// per move event, so a reader who flicks and then parks the page still carries
/// the old speed in the last sample. Trusting it turns the page they meant to
/// leave alone.
void main() {
  /// The decision, mirroring reader_page_state_gestures.endDragTurn.
  bool commits({
    required double progress,
    required double velocity,
    required double sinceLastMove,
  }) {
    const window = .12;
    final effective = sinceLastMove >= window ? 0.0 : velocity;
    final flick = effective > 700;
    return progress >= 0.38 || (flick && progress > 0.05);
  }

  test('travelling past 38% commits regardless of speed', () {
    expect(commits(progress: .5, velocity: 0, sinceLastMove: .5), isTrue);
  });

  test('a short, still turn springs back', () {
    expect(commits(progress: .3, velocity: 0, sinceLastMove: .5), isFalse);
  });

  test('a flick at release commits a short turn', () {
    expect(commits(progress: .12, velocity: 1200, sinceLastMove: .016), isTrue);
  });

  test(
    'a finger that stopped before lifting does not commit on stale speed',
    () {
      expect(
        commits(progress: .12, velocity: 1200, sinceLastMove: .2),
        isFalse,
        reason:
            'parking the page for 200ms must beat a speed sample from before',
      );
    },
  );

  test('the stale-speed window is short enough to still allow real flicks', () {
    // A real flick releases within one or two frames of the last move.
    expect(commits(progress: .12, velocity: 1200, sinceLastMove: .033), isTrue);
    expect(
      commits(progress: .12, velocity: 1200, sinceLastMove: .117),
      isTrue,
      reason: 'just inside the window still counts as moving',
    );
  });

  test('a tiny wobble never commits on speed alone', () {
    expect(
      commits(progress: .02, velocity: 5000, sinceLastMove: .016),
      isFalse,
      reason: 'a 2% turn is not a page turn however fast it moved',
    );
  });
}
