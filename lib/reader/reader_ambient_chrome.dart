import 'package:flutter/cupertino.dart';

import '../theme/app_motion.dart';

/// The chrome that lives on the paper while the menu is away: page number,
/// running head, reading-time pill, bookmark tab.
///
/// These used to be mounted and unmounted with an `if`, so the moment the menu
/// began sliding in they vanished between two frames — the one hard cut left in
/// an otherwise continuous reader. They now fade and lift out as the bars
/// arrive, and come back once the bars have gone.
///
/// The rules are the menu's rules, because two surfaces answering one gesture
/// must not move differently:
/// - position and opacity only, never size (a size change re-lays out the page
///   under it every frame);
/// - closing leaves immediately, opening settles (see [AppMotion]);
/// - while away it takes no taps and leaves the semantics tree, so the first
///   tap after opening the menu is not swallowed by an invisible bar.
class ReaderAmbientChrome extends StatelessWidget {
  const ReaderAmbientChrome({
    required this.visible,
    required this.child,
    this.alignTop = true,
    super.key,
  });

  /// Whether the menu is away and this chrome belongs on the paper.
  final bool visible;

  final Widget child;

  /// Marginal notes sit at the top edge, so they lift *up* on the way out.
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return visible ? child : const SizedBox.shrink();
    }
    // Closing is a dismissal, not a performance: shorter than the arrival, and
    // the same pair the reader menu uses for its own bars.
    final duration = motionDuration(
      context,
      visible ? AppMotion.base : AppMotion.dismiss,
    );
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: visible ? AppMotion.settle : AppMotion.dismissCurve,
          child: AnimatedFractionallyAlign(
            alignment: visible
                ? Alignment.center
                : (alignTop ? Alignment.topCenter : Alignment.bottomCenter),
            distance: alignTop ? -.22 : .22,
            duration: duration,
            curve: visible ? AppMotion.settle : AppMotion.dismissCurve,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A fractional translation driven by an alignment value, built from the same
/// pieces as [AnimatedSlide] but reading naturally as "leave towards this edge".
class AnimatedFractionallyAlign extends StatelessWidget {
  const AnimatedFractionallyAlign({
    required this.alignment,
    required this.distance,
    required this.duration,
    required this.curve,
    required this.child,
    super.key,
  });

  final Alignment alignment;
  final double distance;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hidden = alignment.y < 0;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: hidden ? 0 : 1),
      duration: duration,
      curve: curve,
      builder: (context, t, child) => FractionalTranslation(
        translation: Offset(0, distance * (1 - t)),
        child: child,
      ),
      child: child,
    );
  }
}
