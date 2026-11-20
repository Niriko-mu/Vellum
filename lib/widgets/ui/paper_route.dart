import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// The reader's route: a page that dissolves in, and — on the way out — lifts
/// and shrinks like a sheet of paper being set down.
///
/// What this keeps, deliberately:
/// - **the Cupertino transition itself.** [super.buildTransitions] is wrapped,
///   never replaced, so the edge-swipe-back gesture, the shadow on the outgoing
///   page and the parallax still come from the framework. A hand-rolled gesture
///   would fight the system one and tear mid-swipe.
/// - **no curve on the scale.** The scale reads the raw animation value, because
///   during an edge swipe the finger drives that value directly. Re-curving it
///   here is what makes a drag feel like it is pulling against treacle.
///
/// The sheet needs something behind it. Scaling a full-bleed page exposes the
/// route underneath along all four edges; without a backdrop that reads as a
/// light seam rather than as depth, which is why an earlier version of this
/// transition declined to scale at all.
class PaperRoute<T> extends CupertinoPageRoute<T> {
  PaperRoute({required super.builder, super.settings, super.fullscreenDialog});

  /// Opening: opaque by 58 % of the way, so the page has fully developed before
  /// it finishes travelling and the last 40 % is a clean, quiet slide.
  static const Curve _enterFade = Interval(0, .58, curve: AppMotion.settle);

  /// Closing: the opacity tracks the finger instead of easing after it.
  static const Curve _exitFade = Interval(0, .9, curve: AppMotion.linear);

  /// How much of its size the sheet gives up at the very end of the swipe.
  /// Small on purpose: this is a page being set down, not a card being flicked
  /// away. Past ~8 % it stops reading as paper and starts reading as a zoom.
  static const double shrink = .93;

  /// The paper's corner as it leaves, on the product's own radius scale.
  static const double shrinkRadius = 18;

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

    // Both are read from the same raw animation the framework and the edge
    // gesture drive; neither is re-curved.
    final sheet = AnimatedBuilder(
      animation: animation,
      child: cupertino,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        // 1 at rest (fully arrived), [shrink] at fully dismissed.
        final scale = 1 - (1 - shrink) * (1 - t);
        return Transform.scale(
          scale: scale,
          // A full-bleed page must not shift while it resizes.
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(shrinkRadius * (1 - t)),
            child: child,
          ),
        );
      },
    );

    final fades = FadeTransition(
      // One CurvedAnimation covers both directions of the one controller, with
      // each direction's own window.
      opacity: CurvedAnimation(
        parent: animation,
        curve: _enterFade,
        reverseCurve: _exitFade,
      ),
      child: sheet,
    );

    // The backdrop sits *behind* the faded sheet rather than beside it in the
    // same fade, so it stays opaque while the page is leaving: what is exposed
    // by the shrink must never be the previous route showing through.
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: animation,
          // Only visible once the sheet has begun to leave. The alpha is mixed
          // into the colour rather than wrapped in an `Opacity`: an opacity
          // layer around a plain box makes Impeller log
          // `SetInheritedOpacity ... CanAcceptOpacity returns false` and fall
          // back to a slower path for every frame of the dismissal.
          builder: (context, _) => PaperDismissBackdrop(
            opacity: (1 - animation.value).clamp(0.0, 1.0),
          ),
        ),
        fades,
      ],
    );
  }
}

/// What sits behind a reader page that is being swiped away.
///
/// Not a blackout: a reader leaving a book should still see the app they are
/// returning to, quieted. A shallow darkening reads as depth without flashing
/// the screen.
class PaperDismissBackdrop extends StatelessWidget {
  const PaperDismissBackdrop({this.opacity = 1, super.key});

  /// 0 while the page is at rest, 1 once it has fully left.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final alpha = (opacity.clamp(0.0, 1.0) * .10).clamp(0.0, 1.0);
    return ColoredBox(
      color: Color.alphaBlend(
        colors.constantBlack.withValues(alpha: alpha),
        colors.background,
      ),
    );
  }
}
