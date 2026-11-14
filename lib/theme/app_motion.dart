import 'package:flutter/widgets.dart';

/// Motion vocabulary: three curves, three durations, one spring.
///
/// Components name the pairing after the gesture; nothing invents its own
/// curve. `Curves.easeInOut` is absent on purpose — ease-in reads as "the
/// interface hesitated".
abstract final class AppMotion {
  /// Pure deceleration. The default, for anything that changes an existing
  /// thing's size or place.
  static const Curve settle = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Overshoots past the target and returns. For something appearing out of
  /// nothing, where the overshoot *is* the arrival.
  static const Curve overshoot = Cubic(0.34, 1.25, 0.64, 1.0);

  /// Constant velocity, for progress loops that must not settle.
  static const Curve linear = Curves.linear;

  /// Cross-fades; anything that should be over before a shape settles.
  static const Duration fast = Duration(milliseconds: 200);

  /// Size and position changes.
  static const Duration base = Duration(milliseconds: 250);

  /// Long enough for an overshoot to read as one rather than a wobble.
  static const Duration slow = Duration(milliseconds: 350);

  /// Critically damped spring: the fastest arrival that never overshoots.
  static const SpringDescription springSettle = SpringDescription(
    mass: 1,
    stiffness: 248,
    damping: 31.5,
  );
}

/// Returns [duration], or [Duration.zero] when the platform asks for reduced
/// motion. The result must stay complete and operable without movement.
Duration motionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
