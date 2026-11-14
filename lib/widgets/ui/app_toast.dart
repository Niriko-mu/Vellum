import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_shadow.dart';
import '../../theme/app_type.dart';

/// A non-blocking acknowledgement.
///
/// The pattern this replaces was a modal alert for "备份已创建" — a dialog for
/// something the reader does not have to decide. A toast says the same thing and
/// never takes the screen, so a run of actions does not become a run of taps on
/// 「好」.
///
/// It lives in the app's overlay, above the dock, and dismisses itself. A new
/// message replaces the current one rather than stacking: two toasts on screen
/// is the reader wondering which one is true.
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  IconData? icon,
  Color? color,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _AppToastHost.current?.dismiss();
  final host = _AppToastHost(
    overlay: overlay,
    message: message,
    duration: duration,
    icon: icon,
    color: color,
    colors: context.c,
  );
  _AppToastHost.current = host;
  host.show();
}

class _AppToastHost {
  _AppToastHost({
    required this.overlay,
    required this.message,
    required this.duration,
    required this.icon,
    required this.color,
    required this.colors,
  });

  static _AppToastHost? current;

  final OverlayState overlay;
  final String message;
  final Duration duration;
  final IconData? icon;
  final Color? color;
  final AppColors colors;

  OverlayEntry? _entry;
  Timer? _timer;

  void show() {
    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
    _timer = Timer(duration, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    if (identical(current, this)) current = null;
  }

  Widget _build(BuildContext context) {
    final bottom = AppSpace.dockReserve(
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Positioned(
      left: AppSpace.pageGutter,
      right: AppSpace.pageGutter,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // The inverse pair, not a new role: a toast must read as "not
                // part of the page", and foreground-on-background is the only
                // pairing guaranteed to contrast in both themes without adding
                // a colour that only this widget uses.
                color: colors.foreground,
                borderRadius: AppRadius.xlAll,
                boxShadow: AppShadow.overlay(colors),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.x4,
                  vertical: AppSpace.x3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: AppSpace.x4,
                        color: color ?? colors.background,
                      ),
                      const SizedBox(width: AppSpace.x2),
                    ],
                    Flexible(
                      child: Text(
                        message,
                        style: AppText.rowDescription(
                          color ?? colors.background,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
