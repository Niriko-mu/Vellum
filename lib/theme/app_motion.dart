import 'package:flutter/widgets.dart';

/// Motion vocabulary: three curves, three durations, one spring.
///
/// Components name the pairing after the gesture; nothing invents its own
/// curve. Ease-in-out is absent on purpose — its start reads as "the interface
/// hesitated".
///
/// The file keeps two separate groups, because the reader used to mix them:
/// the durations that may appear inside an animation, and the windows that
/// merely decide *what* a gesture is. Merging the two is how one screen ended
/// up with thirteen different millisecond values.
abstract final class AppMotion {
  // ------------------------------------------------------------- curves --

  /// Pure deceleration. The default, for anything that changes an existing
  /// thing's size or place.
  static const Curve settle = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Overshoots past the target and returns. For something appearing out of
  /// nothing, where the overshoot *is* the arrival.
  static const Curve overshoot = Cubic(0.34, 1.25, 0.64, 1.0);

  /// Constant velocity, for progress loops that must not settle.
  static const Curve linear = Curves.linear;

  /// The closing direction: leaves immediately and converges hard.
  ///
  /// Opening something is worth watching; closing it is only in the way. Using
  /// one decelerating curve for both makes every dismissal feel like waiting
  /// for the interface to finish a performance it was asked to stop.
  static const Curve dismissCurve = Cubic(0.4, 0.0, 1.0, 1.0);

  // ---------------------------------------------------------- durations --

  /// Cross-fades; anything that should be over before a shape settles.
  static const Duration fast = Duration(milliseconds: 200);

  /// Size and position changes.
  static const Duration base = Duration(milliseconds: 250);

  /// Long enough for an overshoot to read as one rather than a wobble.
  static const Duration slow = Duration(milliseconds: 350);

  /// The closing direction. Shorter than [fast] on purpose.
  static const Duration dismiss = Duration(milliseconds: 180);

  /// Critically damped spring: the fastest arrival that never overshoots.
  static const SpringDescription springSettle = SpringDescription(
    mass: 1,
    stiffness: 248,
    damping: 31.5,
  );

  // ------------------------------------------------------ gesture windows --
  // These are not animation timings. They answer "is this a tap, a long press,
  // a double tap, a pull?" and must not be reused as durations above.

  /// Window in which a second tap means "double tap".
  static const Duration doubleTapWindow = Duration(milliseconds: 200);

  /// How long a press must hold before it counts as selecting text.
  static const Duration selectionHold = Duration(milliseconds: 750);

  /// Longest a bookmark pull is tracked before it commits.
  static const Duration bookmarkPullHold = Duration(milliseconds: 400);

  /// Debounce that stops one double-press from queueing two actions.
  static const Duration actionThrottle = Duration(milliseconds: 200);

  /// Quiet period before a reading position is written.
  static const Duration saveDebounce = Duration(milliseconds: 350);

  /// Quiet period before a draft is auto-saved.
  static const Duration autosaveDelay = Duration(milliseconds: 600);

  /// Quiet period before a catalogue search runs.
  static const Duration searchDebounce = Duration(milliseconds: 180);

  /// Wait before refocusing a field after the keyboard moved.
  static const Duration refocus = Duration(milliseconds: 250);
}

/// Returns [duration], or [Duration.zero] when the platform asks for reduced
/// motion. The result must stay complete and operable without movement.
Duration motionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// One curve pair for "in" and "out".
///
/// The reverse curve only applies while the controller runs backwards, so a
/// single CurvedAnimation serves both directions of one controller.
CurvedAnimation motionPair(Animation<double> parent) => CurvedAnimation(
  parent: parent,
  curve: AppMotion.settle,
  reverseCurve: AppMotion.dismissCurve,
);
