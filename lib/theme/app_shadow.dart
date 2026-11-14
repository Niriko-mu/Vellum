import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show Brightness;

import 'app_colors.dart';

/// The only three shadows in the product.
///
/// Hierarchy comes from typography, spacing and surface role — never from
/// elevation. A shadow is allowed on exactly three things: a floating overlay
/// (menu, sheet, toast, dock), the single filled primary button of a surface,
/// and a filled search field. Anything else is a finding in `tool/design_lint.ps1`.
abstract final class AppShadow {
  /// Menus, sheets, toasts, the floating dock.
  static List<BoxShadow> overlay(AppColors colors) => [
    BoxShadow(
      color: colors.constantBlack.withValues(
        alpha: colors.brightness == Brightness.dark ? 0.45 : 0.10,
      ),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// The one filled primary action of a surface.
  static List<BoxShadow> xs(AppColors colors) => [
    BoxShadow(
      color: colors.constantBlack.withValues(alpha: 0.12),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  /// A filled search field that sits on the page.
  static List<BoxShadow> sm(AppColors colors) => [
    BoxShadow(
      color: colors.constantBlack.withValues(alpha: 0.06),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}
