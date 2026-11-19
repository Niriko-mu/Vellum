import 'package:flutter/cupertino.dart';

import '../../theme/app_motion.dart';

/// A shelf's first frames: the grid assembles instead of appearing whole.
///
/// The clock belongs to the shelf, not to the cards. One controller advances a
/// staggered window per card, so a grid of thirty covers costs one ticker and
/// thirty paint-only transforms — not thirty controllers. Cards that scroll out
/// and back in must **not** replay: the reveal is bound to the shelf's first
/// mount, and the controller is left at 1 afterwards, so for the rest of its
/// life the grid is a plain grid.
///
/// Deliberately not a spring: covers are pages laid down on a table. They
/// settle, they do not bounce. The travel is 12 logical pixels — enough to read
/// as "arriving", small enough that it never looks like a loading skeleton.
class ShelfRevealScope extends StatefulWidget {
  const ShelfRevealScope({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// Off for reduced motion.
  final bool enabled;

  @override
  State<ShelfRevealScope> createState() => _ShelfRevealScopeState();
}

class _ShelfRevealScopeState extends State<ShelfRevealScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.enabled ? 0 : 1,
  );

  bool _started = false;

  /// The effect is skipped when the platform asks it to be, even if the caller
  /// left [ShelfRevealScope.enabled] on: reduce-motion is a media query, not a
  /// call-site decision, and letting a caller override it is how it gets lost.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!widget.enabled || reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ShelfRevealScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Turning the effect off mid-life must land at once, never freeze a card
    // half-faded. Turning it on later does not restage a grid already seen.
    if (!widget.enabled && !_controller.isCompleted) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ShelfRevealController(controller: _controller, child: widget.child);
}

/// Handed down so a card can ask for its own window without the page passing
/// an index through every widget.
class _ShelfRevealController extends InheritedWidget {
  const _ShelfRevealController({
    required this.controller,
    required super.child,
  });

  final AnimationController controller;

  /// Cards share one arrival window; later cards start later, and every window
  /// closes before the clock ends so the last row is never left half-arrived.
  static const int staggerCap = 8;

  static Animation<double>? maybeProgressOf(BuildContext context, int index) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_ShelfRevealController>();
    // The clock has already finished: hand back nothing and the grid stays a
    // plain grid, so a rebuilt card is never re-staged.
    if (scope == null || scope.controller.isCompleted) return null;
    final slot = index % staggerCap;
    final start = slot / staggerCap * .55;
    return CurvedAnimation(
      parent: scope.controller,
      curve: Interval(
        start,
        (start + .45).clamp(0.0, 1.0),
        curve: AppMotion.settle,
      ),
    );
  }

  @override
  bool updateShouldNotify(_ShelfRevealController oldWidget) =>
      controller != oldWidget.controller;
}

/// One card's arrival: fade and a short lift, position and opacity only.
class ShelfRevealItem extends StatelessWidget {
  const ShelfRevealItem({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final progress = _ShelfRevealController.maybeProgressOf(context, index);
    if (progress == null) return child;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Opacity(
        opacity: progress.value,
        child: FractionalTranslation(
          translation: Offset(0, .035 * (1 - progress.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
