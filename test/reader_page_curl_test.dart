import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_page_curl.dart';

/// The fold geometry of a simulated page curl.
///
/// The maths here is the part that fails quietly: a reflection with a sign
/// flipped still looks plausible mid-progress, and a fold that leans the wrong
/// way only shows at the extremes. Being pure, it can be checked directly.
void main() {
  const size = Size(400, 800);

  CurlGeometry geo(double progress, {bool forward = true}) =>
      CurlGeometry(size: size, progress: progress, forward: forward);

  test('a forward curl starts at the right edge and ends at the left', () {
    expect(geo(0).foldTop.dx, closeTo(400, 0.001));
    expect(geo(0).foldBottom.dx, closeTo(400, 0.001));
    expect(geo(1).foldTop.dx, closeTo(0, 0.001));
    expect(geo(1).foldBottom.dx, closeTo(0, 0.001));
  });

  test('the fold leans while travelling and straightens at both ends', () {
    // At the extremes the line is vertical, so it cannot leave the page.
    expect(geo(0).foldTop.dx, closeTo(geo(0).foldBottom.dx, 0.001));
    expect(geo(1).foldTop.dx, closeTo(geo(1).foldBottom.dx, 0.001));
    // Mid-turn it leans.
    final mid = geo(.5);
    expect((mid.foldTop.dx - mid.foldBottom.dx).abs(), greaterThan(1));
  });

  test('a backward curl travels the other way', () {
    expect(geo(0, forward: false).foldBottom.dx, closeTo(0, 0.001));
    expect(geo(1, forward: false).foldBottom.dx, closeTo(400, 0.001));
  });

  test('both halves are built from the same fold points', () {
    for (final p in [.2, .5, .8]) {
      final g = geo(p);
      // The flap and the visible part must meet along the fold; if they
      // drifted apart the page would show a seam or a doubled edge.
      expect(g.flapPath.contains(g.foldTop), isTrue);
      expect(g.flapPath.contains(g.foldBottom), isTrue);
      expect(g.visiblePath.contains(g.foldTop), isTrue);
      expect(g.visiblePath.contains(g.foldBottom), isTrue);
    }
  });

  test('the reflection maps a fold point onto itself', () {
    // A point on the fold is its own mirror image; if the matrix were wrong
    // the flap would detach from the fold line.
    final g = geo(.5);
    final m = g.reflection;
    final onFold = (g.foldTop + g.foldBottom) / 2;
    final v = MatrixUtils.transformPoint(m, onFold);
    expect(v.dx, closeTo(onFold.dx, 0.01));
    expect(v.dy, closeTo(onFold.dy, 0.01));
  });

  test('the fold normal points at the side the incoming page shows on', () {
    final forward = geo(.5);
    // Forward turns expose the incoming page from the right.
    expect(forward.incomingNormal.dx, greaterThan(0));
    final backward = geo(.5, forward: false);
    expect(backward.incomingNormal.dx, lessThan(0));
  });

  test('both shadow quads straddle the fold', () {
    final g = geo(.5);
    expect(g.incomingShadowQuad, hasLength(4));
    expect(g.flapShadowQuad, hasLength(4));
    // One extends to each side of the fold line.
    final incomingMid = (g.incomingShadowQuad[2] + g.incomingShadowQuad[3]) / 2;
    final flapMid = (g.flapShadowQuad[2] + g.flapShadowQuad[3]) / 2;
    expect((incomingMid.dx - flapMid.dx).sign, isNot(0));
  });

  test('progress is clamped so a stray value cannot invert the fold', () {
    expect(geo(-1).progress, 0);
    expect(geo(2).progress, 1);
  });
}
