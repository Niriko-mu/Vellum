import 'package:flutter/cupertino.dart';

import '../../theme/app_motion.dart';

/// Puts the floating dock above a page and lets the page's scroll steer it.
///
/// The dock leaves while the reader travels down through a page and comes back
/// the moment they travel up. It lives above the four tab navigators as its own
/// layer, so it can watch the active page scroll without any page knowing this
/// exists — which is why this wrapper owns the state instead of each page
/// hiding its own chrome (four copies would drift).
///
/// Rules, all of which are easy to get wrong:
/// - **Movement, not offset.** The decision comes from the scroll *delta*, so a
///   page restored at a deep offset does not start with the dock hidden, and a
///   page that cannot scroll never hides it.
/// - **A dead band, not a per-frame threshold.** A trackpad or a light flick
///   emits many tiny deltas; summing them inside a small window is what stops
///   the dock flickering between frames.
/// - **Only vertical.** A horizontal strip (folder chips, a paged reader) must
///   not count as reading down.
/// - **Hidden means gone.** No taps, no semantics. Same rule as the reader's
///   own chrome: an invisible bar that still eats a tap is worse than no bar.
/// - **Reduced motion is a hard cut.** A dock sliding in an interface the
///   platform asked to keep still is worse than a dock that is simply there.
///
/// Deliberately *not* wired to the reader: the reader covers it entirely, and
/// while a sheet or full-screen dialog is up its route sits above this layer.
class AppDockAutoHide extends StatefulWidget {
  const AppDockAutoHide({
    required this.page,
    required this.dock,
    this.enabled = true,
    this.bottomInset = 0,
    super.key,
  });

  /// The page content the scroll is watched on.
  final Widget page;

  /// The dock itself, already laid out for the bottom edge.
  final Widget dock;

  /// Off where movement is a cost rather than a cue.
  final bool enabled;

  /// Safe-area inset below the dock; it travels the distance it occupies.
  final double bottomInset;

  @override
  State<AppDockAutoHide> createState() => AppDockAutoHideState();
}

class AppDockAutoHideState extends State<AppDockAutoHide> {
  bool _hidden = false;

  /// Signed scroll accumulated inside the current decision window. Positive is
  /// "moving down the page", which is what hides the dock.
  double _accumulated = 0;

  /// Distance that means the user is actually travelling: small enough that a
  /// deliberate flick hides it, large enough that a jittery finger does not.
  static const double _travel = 28;

  /// A reversal this large is a change of intent, not noise inside a stroke.
  static const double _reversal = 12;

  /// True while the dock is out of the way.
  bool get isHidden => _hidden;

  bool _onNotification(ScrollNotification notification) {
    // Only the scroll that owns the gesture steers the dock.
    if (notification.metrics.axis != Axis.vertical) return false;
    final double? delta = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta) => scrollDelta,
      OverscrollNotification(:final overscroll) => overscroll,
      _ => null,
    };
    if (delta == null || delta == 0) return false;

    // Opposite travel cancels what the previous direction earned, so a
    // half-hearted down-then-up does not leave the dock stranded.
    if (delta > 0 && _accumulated < 0) _accumulated = 0;
    if (delta < 0 && _accumulated > 0) _accumulated = 0;
    _accumulated += delta;

    if (_accumulated > _travel && !_hidden) {
      _setHidden(true);
    } else if (_accumulated < -_reversal && _hidden) {
      _setHidden(false);
    }
    return false;
  }

  void _setHidden(bool value) {
    _accumulated = 0;
    if (_hidden == value) return;
    setState(() => _hidden = value);
  }

  /// A deliberate arrival at a new destination brings the dock back: a tab
  /// switch, a route popping, or the app returning to the foreground.
  void reveal() => _setHidden(false);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hidden = widget.enabled && _hidden;
    final duration = reduceMotion
        ? Duration.zero
        : motionDuration(context, hidden ? AppMotion.fast : AppMotion.base);
    final curve = hidden ? AppMotion.dismissCurve : AppMotion.settle;
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: widget.enabled ? _onNotification : (_) => false,
          child: widget.page,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: hidden,
            child: ExcludeSemantics(
              excluding: hidden,
              child: AnimatedSlide(
                // It leaves downward, the way a surface retreats from the
                // thumb, rather than fading in place.
                offset: hidden ? const Offset(0, 1.2) : Offset.zero,
                duration: duration,
                curve: curve,
                child: AnimatedOpacity(
                  opacity: hidden ? 0 : 1,
                  duration: duration,
                  curve: curve,
                  child: widget.dock,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
