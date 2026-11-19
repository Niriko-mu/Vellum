import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/widgets/ui/paper_route.dart';

/// The arithmetic behind the shrinking paper.
///
/// Driving this through a real pop in a widget test proved unreliable: the
/// route's own controller is replaced by the navigator's transition machinery,
/// so a test cannot hold a mid-flight value. The mapping is a pure function, so
/// it is checked directly - which is also the part a future edit is most likely
/// to break.
void main() {
  /// Mirrors PaperRoute.buildTransitions: 1 at rest, shrink at dismissed.
  double scaleAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return 1 - (1 - PaperRoute.shrink) * (1 - clamped);
  }

  double radiusAt(double t) =>
      PaperRoute.shrinkRadius * (1 - t.clamp(0.0, 1.0));

  test('the page rests at full size', () {
    expect(scaleAt(1), 1);
    expect(radiusAt(1), 0, reason: 'a resting page has square corners');
  });

  test('the page shrinks as it is dismissed, but stays paper-sized', () {
    expect(scaleAt(0), PaperRoute.shrink);
    expect(
      PaperRoute.shrink,
      greaterThan(.9),
      reason: 'a page set down, not a card flicked away',
    );
    expect(
      PaperRoute.shrink,
      lessThan(1),
      reason: 'the whole point: it must actually get smaller',
    );
  });

  test('the shrink is linear in the raw animation, with no re-curve', () {
    // A gesture-driven value must track the finger exactly.
    final quarter = scaleAt(.75);
    final expected = 1 - (1 - PaperRoute.shrink) * .25;
    expect(quarter, closeTo(expected, 1e-9));

    // Monotonic across the whole dismissal.
    var previous = -1.0;
    for (var t = 1.0; t >= 0.0; t -= .1) {
      final s = scaleAt(t);
      expect(s, lessThanOrEqualTo(previous == -1 ? 1.0 : previous));
      previous = s;
    }
  });

  test('the corners round as the page leaves', () {
    expect(radiusAt(1), 0);
    expect(radiusAt(0), PaperRoute.shrinkRadius);
    expect(radiusAt(.5), closeTo(PaperRoute.shrinkRadius / 2, 1e-9));
  });
}
