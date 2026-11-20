import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A simulated page curl: a straight fold line, the lifted corner mirrored back
/// as the paper's reverse side, and a gradient shadow on both sides of the fold.
///
/// Geometry only — it takes the two page surfaces as widgets and paints nothing
/// itself but the fold's shadows, so a page turn costs no rasterisation of its
/// own and the whole thing can be unit-tested against [CurlGeometry] without a
/// widget tree.
///
/// [progress] runs 0 (not turned) → 1 (turned). [forward] peels from the right
/// edge for a forward turn and from the left for a backward one.
class ReaderPageCurl extends StatelessWidget {
  const ReaderPageCurl({
    required this.outgoing,
    required this.incoming,
    required this.progress,
    required this.forward,
    required this.backgroundColor,
    super.key,
  });

  final Widget outgoing;
  final Widget incoming;
  final double progress;
  final bool forward;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    // The extremes are just the pages themselves: painting a degenerate fold
    // there would leave a hairline of the other page along an edge.
    if (progress <= 0.001) return outgoing;
    if (progress >= 0.999) return incoming;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return outgoing;
        final geo = CurlGeometry(
          size: size,
          progress: progress,
          forward: forward,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: backgroundColor, child: incoming),
            ClipPath(
              clipper: _CurlClipper(geo.visiblePath),
              child: ColoredBox(color: backgroundColor, child: outgoing),
            ),
            Transform(
              transform: geo.reflection,
              child: ClipPath(
                clipper: _CurlClipper(geo.flapPath),
                child: ColoredBox(
                  color: backgroundColor,
                  child: Stack(
                    children: [
                      outgoing,
                      // The reverse of the paper is not lit like its face.
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0x1F000000)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            CustomPaint(painter: _CurlShadowPainter(geo)),
          ],
        );
      },
    );
  }
}

/// The pure geometry of one curl, with no widget dependency.
///
/// Kept separate from the widget on purpose: the fold maths is the part most
/// likely to be got subtly wrong (a reflection matrix with the wrong sign still
/// looks plausible at mid-progress), and being pure makes it directly testable.
class CurlGeometry {
  CurlGeometry({
    required this.size,
    required double progress,
    required this.forward,
  }) : progress = progress.clamp(0.0, 1.0);

  final Size size;
  final double progress;
  final bool forward;

  /// The fold leans while it travels and straightens at both ends, so the line
  /// never leaves the page.
  double get _tilt => size.height * 0.18 * math.sin(math.pi * progress);

  Offset get foldTop => forward
      ? Offset(size.width * (1 - progress) + _tilt, 0)
      : Offset(size.width * progress, 0);

  Offset get foldBottom => forward
      ? Offset(size.width * (1 - progress), size.height)
      : Offset(size.width * progress - _tilt, size.height);

  /// The part of the outgoing page still flat on the table.
  Path get visiblePath {
    final path = Path();
    if (forward) {
      path
        ..moveTo(0, 0)
        ..lineTo(foldTop.dx, 0)
        ..lineTo(foldBottom.dx, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(foldTop.dx, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(foldBottom.dx, size.height)
        ..close();
    }
    return path;
  }

  /// The lifted part, mirrored across the fold to read as the paper's back.
  Path get flapPath {
    final path = Path();
    if (forward) {
      path
        ..moveTo(foldTop.dx, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(foldBottom.dx, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(foldTop.dx, 0)
        ..lineTo(foldBottom.dx, size.height)
        ..lineTo(0, size.height)
        ..close();
    }
    return path;
  }

  /// Reflection across the fold: P' = (I - 2nnᵀ)P + 2(n·B)n, with n the unit
  /// normal and B a point on the fold (the bottom end).
  Matrix4 get reflection {
    final d = foldTop - foldBottom;
    final length = d.distance;
    if (length < 0.001) return Matrix4.identity();
    final nx = -d.dy / length;
    final ny = d.dx / length;
    final dot = nx * foldBottom.dx + ny * foldBottom.dy;
    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, 1 - 2 * nx * nx);
    matrix.setEntry(0, 1, -2 * nx * ny);
    matrix.setEntry(1, 0, -2 * nx * ny);
    matrix.setEntry(1, 1, 1 - 2 * ny * ny);
    matrix.setEntry(0, 3, 2 * dot * nx);
    matrix.setEntry(1, 3, 2 * dot * ny);
    return matrix;
  }

  /// The unit normal pointing at the side the *incoming* page shows on.
  Offset get incomingNormal {
    final d = foldBottom - foldTop;
    final length = d.distance;
    if (length < 0.001) {
      return forward ? const Offset(1, 0) : const Offset(-1, 0);
    }
    var normal = Offset(-d.dy / length, d.dx / length);
    final mid = (foldTop + foldBottom) / 2;
    final sidePoint = forward
        ? Offset(size.width, size.height / 2)
        : Offset(0, size.height / 2);
    if ((sidePoint - mid).dx * normal.dx + (sidePoint - mid).dy * normal.dy <
        0) {
      normal = -normal;
    }
    return normal;
  }

  /// Shadow on the incoming side: darkest at the fold, fading outward.
  List<Offset> get incomingShadowQuad {
    final n = incomingNormal * 30;
    return [foldTop, foldBottom, foldBottom + n, foldTop + n];
  }

  /// Shadow on the paper's back side, mirrored the other way.
  List<Offset> get flapShadowQuad {
    final n = incomingNormal * 30;
    return [foldTop, foldBottom, foldBottom - n, foldTop - n];
  }
}

class _CurlClipper extends CustomClipper<Path> {
  const _CurlClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _CurlClipper oldClipper) => true;
}

class _CurlShadowPainter extends CustomPainter {
  const _CurlShadowPainter(this.geo);

  final CurlGeometry geo;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _paintQuad(canvas, size, geo.incomingShadowQuad, 0.32);
    _paintQuad(canvas, size, geo.flapShadowQuad, 0.28);
  }

  void _paintQuad(Canvas canvas, Size size, List<Offset> quad, double alpha) {
    final foldMid = (quad[0] + quad[1]) / 2;
    final outerMid = (quad[2] + quad[3]) / 2;
    final gradient = LinearGradient(
      colors: [
        const Color(0xFF000000).withValues(alpha: alpha),
        const Color(0x00000000),
      ],
      begin: _align(foldMid, size),
      end: _align(outerMid, size),
    );
    final paint = Paint()..shader = gradient.createShader(Offset.zero & size);
    canvas.drawPath(Path()..addPolygon(quad, true), paint);
  }

  Alignment _align(Offset point, Size size) =>
      Alignment(2 * point.dx / size.width - 1, 2 * point.dy / size.height - 1);

  @override
  bool shouldRepaint(covariant _CurlShadowPainter oldDelegate) =>
      oldDelegate.geo != geo;
}
