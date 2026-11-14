import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// The one press feedback in the product: a full-surface fill, not a scale
/// bounce and not an opacity fade of the content.
///
/// A row does not shrink when touched and its label does not fade — the
/// background under it changes. The fill appears instantly on press and fades
/// out on release, so a tap feels answered before the animation runs.
class AppPressable extends StatefulWidget {
  const AppPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.pressedColor,
    this.semanticLabel,
    this.semanticHint,
    this.onPressChanged,
    this.isButton = true,
    this.enabled = true,
    this.behaviour = HitTestBehavior.opaque,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Clips the pressed fill to the surface's corner.
  final BorderRadius? borderRadius;

  /// Defaults to `foreground @ 5%`.
  final Color? pressedColor;

  final String? semanticLabel;
  final String? semanticHint;

  /// Reports press state. Grouped sections use it to hide the hairline above
  /// and below the pressed row: a pressed row with a line running through it
  /// looks like two rows, not one surface being touched.
  final ValueChanged<bool>? onPressChanged;
  final bool isButton;
  final bool enabled;
  final HitTestBehavior behaviour;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setPressed(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
    widget.onPressChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.pressedColor ?? context.c.pressedFill;
    final longPress = widget.enabled ? widget.onLongPress : null;
    final tap = widget.enabled ? widget.onTap : null;

    Widget surface = AnimatedContainer(
      duration: motionDuration(context, AppMotion.fast),
      curve: AppMotion.settle,
      color: _pressed ? fill : const Color(0x00000000),
      child: widget.child,
    );

    if (widget.borderRadius != null) {
      surface = ClipRRect(borderRadius: widget.borderRadius!, child: surface);
    }

    return Semantics(
      button: widget.isButton,
      enabled: _interactive,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      onTap: tap,
      child: GestureDetector(
        behavior: widget.behaviour,
        excludeFromSemantics: true,
        onTapDown: _interactive ? (_) => _setPressed(true) : null,
        onTapUp: _interactive ? (_) => _setPressed(false) : null,
        onTapCancel: _interactive ? () => _setPressed(false) : null,
        onTap: tap == null
            ? null
            : () {
                // Release the fill before the route change so the next page does
                // not inherit a pressed row.
                _setPressed(false);
                tap();
              },
        onLongPress: longPress == null
            ? null
            : () {
                _setPressed(false);
                longPress();
              },
        child: surface,
      ),
    );
  }
}
