import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// A shared cover is stable across shelf, details and the reader's context.
/// The id, rather than a title, prevents duplicate titles sharing a Hero.
String bookCoverHeroTag(String bookId) => 'vellum.book.cover.$bookId';

/// The connected book journey: shelf → details → reading.
///
/// This deliberately extends [CupertinoPageRoute]. Keeping the framework's
/// transition preserves its interactive edge swipe; wrapping it must never
/// replace the gesture recognizer or disable the system back action.
class BookJourneyRoute<T> extends CupertinoPageRoute<T> {
  BookJourneyRoute({
    required super.builder,
    super.settings,
    this.reading = false,
  });

  /// Reading opens as a quiet paper plane, rather than a second details card.
  final bool reading;

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
    final platform = super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
    if (MediaQuery.disableAnimationsOf(context)) return platform;

    final settle = CurvedAnimation(
      parent: animation,
      curve: AppMotion.settle,
      reverseCurve: AppMotion.dismissCurve,
    );
    // The outgoing surface recedes a little: it remains spatially behind the
    // incoming book instead of vanishing on the first frame.
    final recede = ScaleTransition(
      scale: Tween<double>(begin: 1, end: .965).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.settle),
      ),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: .72).animate(secondaryAnimation),
        child: platform,
      ),
    );
    if (!reading) return recede;

    // A very small lift and a clipped corner make the paper arrive continuously
    // without replaying the Hero flight or delaying access to the book.
    final radius = Tween<BorderRadius>(
      begin: const BorderRadius.vertical(top: Radius.circular(20)),
      end: BorderRadius.zero,
    ).animate(settle);
    return ScaleTransition(
      scale: Tween<double>(begin: .985, end: 1).animate(settle),
      child: AnimatedBuilder(
        animation: radius,
        builder: (context, child) =>
            ClipRRect(borderRadius: radius.value, child: child),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(.12, .68, curve: AppMotion.settle),
            reverseCurve: const Interval(0, .82, curve: AppMotion.linear),
          ),
          child: platform,
        ),
      ),
    );
  }
}

/// One finite, route-owned clock for a page's content. No item owns a timer and
/// offstage pages do not keep animating. Reduced motion is a complete page,
/// not a page that waits for its content to appear.
class BookPageReveal extends StatelessWidget {
  const BookPageReveal({required this.child, this.order = 0, super.key});

  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final start = (order * .08).clamp(0.0, .38);
    final reveal = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + .58).clamp(0.0, 1.0),
        curve: AppMotion.settle,
      ),
      reverseCurve: Interval(0, .65, curve: AppMotion.dismissCurve),
    );
    return FadeTransition(
      opacity: reveal,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, .022 + order * .002),
          end: Offset.zero,
        ).animate(reveal),
        child: child,
      ),
    );
  }
}

/// A small layer of colour sampled from the current theme, not cover pixels.
/// It keeps an uncontrolled image from owning the page's theme.
class BookAtmosphere extends StatelessWidget {
  const BookAtmosphere({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.primary.withValues(
                alpha: colors.brightness == Brightness.dark ? .11 : .08,
              ),
              colors.background.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
