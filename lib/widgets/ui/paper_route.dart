import 'package:flutter/cupertino.dart';

import '../../theme/app_motion.dart';

/// A Cupertino page that dissolves in as it slides.
///
/// Used for the reader, the one destination that replaces the whole screen and
/// replaces the whole context. A bare slide delivers that page as a fully formed
/// opaque slab — that is what reads as abrupt, not the speed.
///
/// What this keeps, deliberately:
/// - **the Cupertino transition itself.** [super.buildTransitions] is wrapped,
///   not replaced, so the edge-swipe-back gesture, the shadow on the outgoing
///   page and the parallax all still come from the framework.
/// - **no scale.** The paper is full-bleed; scaling it would expose the page
///   underneath along every edge, which reads as a misfitting sheet rather than
///   as a page arriving.
///
/// Durations come from [AppMotion]: 350 ms in (the framework's own 500 ms makes
/// a full-width, full-screen translate the longest motion in the app), 250 ms
/// out, both shorter than Cupertino's default and inside the product vocabulary.
class PaperRoute<T> extends CupertinoPageRoute<T> {
  PaperRoute({required super.builder, super.settings, super.fullscreenDialog});

  /// Opening: opaque by 58 % of the way, so the page has fully developed before
  /// it finishes travelling and the last 40 % is a clean, quiet slide.
  static const Curve _enterFade = Interval(0, .58, curve: AppMotion.settle);

  /// Closing: the opacity tracks the finger instead of easing after it. A
  /// gesture-driven value must not be re-curved, or the page lags the drag.
  static const Curve _exitFade = Interval(0, .9, curve: AppMotion.linear);

  @override
  Duration get transitionDuration => AppMotion.slow;

  @override
  Duration get reverseTransitionDuration => AppMotion.base;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final cupertino = super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
    // Reduced motion: the framework's own transition is already the least
    // surprising thing to show, and a crossfade is still movement.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return cupertino;
    }
    return FadeTransition(
      // One CurvedAnimation covers both directions of the one controller, the
      // same shape as [motionPair] — but with each direction's own window,
      // because a fade that completes at the same fraction both ways would be
      // too ghostly on the way out and too slow on the way in.
      opacity: CurvedAnimation(
        parent: animation,
        curve: _enterFade,
        reverseCurve: _exitFade,
      ),
      child: cupertino,
    );
  }
}
