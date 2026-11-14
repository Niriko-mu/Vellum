import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Semantic colour roles.
///
/// Every role exists in **both** themes and is `required`, so a missing dark
/// value is a compile error rather than a black rectangle. Widgets read roles
/// through `context.c` (see [VellumColors]) and never touch [AppPalette].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.backgroundSubtle,
    required this.card,
    required this.popover,
    required this.foreground,
    required this.mutedForeground,
    required this.foregroundTertiary,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryActive,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.borderSelected,
    required this.destructive,
    required this.success,
    required this.warning,
    required this.info,
    required this.scrim,
    required this.constantBlack,
    required this.constantWhite,
  });

  /// Page surface.
  final Color background;

  /// Inset region, sidebar in light mode.
  final Color backgroundSubtle;

  /// Grouped section, list block.
  final Color card;

  /// Menu panel, sheet.
  final Color popover;

  /// Primary text and leading icons.
  final Color foreground;

  /// Secondary text, chevrons, captions. 4.5:1 on both [background] and [card].
  final Color mutedForeground;

  /// Tertiary, non-text graphics only.
  final Color foregroundTertiary;

  /// Emphasised action, selection, adjustable progress.
  final Color primary;

  /// Text and icons drawn on [primary].
  final Color primaryForeground;

  /// Neutral overlay fill: chips, icon discs.
  final Color secondary;

  /// Pressed state of a [secondary] fill.
  final Color secondaryActive;

  /// Default hairline.
  final Color border;

  /// Faintest divider.
  final Color borderSubtle;

  /// Control outlines.
  final Color borderStrong;

  /// Selected chip outline, switch track when off.
  final Color borderSelected;

  final Color destructive;
  final Color success;
  final Color warning;
  final Color info;

  /// Dims the layer below, whatever colour it is.
  final Color scrim;

  /// Chrome over uncontrolled content (a book cover, a photo).
  final Color constantBlack;
  final Color constantWhite;

  static const light = AppColors(
    background: AppPalette.canvas,
    backgroundSubtle: AppPalette.canvasSubtle,
    card: AppPalette.card,
    popover: AppPalette.popover,
    foreground: AppPalette.foreground,
    mutedForeground: AppPalette.mutedForeground,
    foregroundTertiary: AppPalette.foregroundTertiary,
    primary: AppPalette.primary,
    primaryForeground: AppPalette.primaryForeground,
    secondary: AppPalette.secondaryLight,
    secondaryActive: AppPalette.secondaryActiveLight,
    border: AppPalette.borderLight,
    borderSubtle: AppPalette.borderSubtleLight,
    borderStrong: AppPalette.borderStrongLight,
    borderSelected: AppPalette.borderSelectedLight,
    destructive: AppPalette.destructive,
    success: AppPalette.success,
    warning: AppPalette.warning,
    info: AppPalette.info,
    scrim: AppPalette.scrim,
    constantBlack: AppPalette.constantBlack,
    constantWhite: AppPalette.constantWhite,
  );

  static const dark = AppColors(
    background: AppPalette.canvasDark,
    backgroundSubtle: AppPalette.canvasSubtleDark,
    card: AppPalette.cardDark,
    popover: AppPalette.popoverDark,
    foreground: AppPalette.foregroundDark,
    mutedForeground: AppPalette.mutedForegroundDark,
    foregroundTertiary: AppPalette.foregroundTertiaryDark,
    primary: AppPalette.primaryDark,
    primaryForeground: AppPalette.primaryForegroundDark,
    secondary: AppPalette.secondaryDark,
    secondaryActive: AppPalette.secondaryActiveDark,
    border: AppPalette.borderDark,
    borderSubtle: AppPalette.borderSubtleDark,
    borderStrong: AppPalette.borderStrongDark,
    borderSelected: AppPalette.borderSelectedDark,
    destructive: AppPalette.destructiveDark,
    success: AppPalette.successDark,
    warning: AppPalette.warningDark,
    info: AppPalette.infoDark,
    scrim: AppPalette.scrim,
    constantBlack: AppPalette.constantBlack,
    constantWhite: AppPalette.constantWhite,
  );

  /// Whether these roles belong to the dark theme.
  Brightness get brightness =>
      background.computeLuminance() < 0.5 ? Brightness.dark : Brightness.light;

  /// The pressed fill of a row. Five per cent of the foreground, so it darkens
  /// in light mode and lightens in dark mode without a second token.
  Color get pressedFill => foreground.withValues(alpha: 0.05);

  /// Fill for a field that sits on [background].
  Color get fieldFill => secondary;

  @override
  AppColors copyWith({
    Color? background,
    Color? backgroundSubtle,
    Color? card,
    Color? popover,
    Color? foreground,
    Color? mutedForeground,
    Color? foregroundTertiary,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryActive,
    Color? border,
    Color? borderSubtle,
    Color? borderStrong,
    Color? borderSelected,
    Color? destructive,
    Color? success,
    Color? warning,
    Color? info,
    Color? scrim,
    Color? constantBlack,
    Color? constantWhite,
  }) => AppColors(
    background: background ?? this.background,
    backgroundSubtle: backgroundSubtle ?? this.backgroundSubtle,
    card: card ?? this.card,
    popover: popover ?? this.popover,
    foreground: foreground ?? this.foreground,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    foregroundTertiary: foregroundTertiary ?? this.foregroundTertiary,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    secondary: secondary ?? this.secondary,
    secondaryActive: secondaryActive ?? this.secondaryActive,
    border: border ?? this.border,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    borderStrong: borderStrong ?? this.borderStrong,
    borderSelected: borderSelected ?? this.borderSelected,
    destructive: destructive ?? this.destructive,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    scrim: scrim ?? this.scrim,
    constantBlack: constantBlack ?? this.constantBlack,
    constantWhite: constantWhite ?? this.constantWhite,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      backgroundSubtle: mix(backgroundSubtle, other.backgroundSubtle),
      card: mix(card, other.card),
      popover: mix(popover, other.popover),
      foreground: mix(foreground, other.foreground),
      mutedForeground: mix(mutedForeground, other.mutedForeground),
      foregroundTertiary: mix(foregroundTertiary, other.foregroundTertiary),
      primary: mix(primary, other.primary),
      primaryForeground: mix(primaryForeground, other.primaryForeground),
      secondary: mix(secondary, other.secondary),
      secondaryActive: mix(secondaryActive, other.secondaryActive),
      border: mix(border, other.border),
      borderSubtle: mix(borderSubtle, other.borderSubtle),
      borderStrong: mix(borderStrong, other.borderStrong),
      borderSelected: mix(borderSelected, other.borderSelected),
      destructive: mix(destructive, other.destructive),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      info: mix(info, other.info),
      scrim: mix(scrim, other.scrim),
      constantBlack: mix(constantBlack, other.constantBlack),
      constantWhite: mix(constantWhite, other.constantWhite),
    );
  }
}

/// Short accessor: `context.c.primary`.
///
/// Resolves the [AppColors] extension mounted by `VellumTheme`. A Cupertino
/// surface that is mounted **outside** the Material shell — a test harness, a
/// reader panel rendered on its own paper — has no extension, so the ambient
/// brightness decides instead of crashing on a null check.
extension VellumColors on BuildContext {
  AppColors get c {
    final theme = Theme.of(this);
    final themed = theme.extension<AppColors>();
    if (themed != null) return themed;
    final cupertino = findAncestorWidgetOfExactType<CupertinoTheme>();
    final brightness = cupertino?.data.brightness ?? theme.brightness;
    return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  }
}
