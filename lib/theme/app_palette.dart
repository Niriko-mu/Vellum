import 'package:flutter/widgets.dart';

/// Raw palette for VELLUM.
///
/// This is the **only** file under `lib/` allowed to hold colour literals.
/// Widgets must go through [AppColors]; a role name is the API, the step it
/// points at is an implementation detail that may change.
///
/// Two families of values are deliberately *not* here:
///
/// * **Reader papers** ([VellumTheme.readerWhite] and friends). A paper is a
///   *persisted user choice*, not a theme role — switching the app theme must
///   never repaint someone's book. They live with the reader, upstream of the
///   tokens, and read back only through `readerInkFor(paper)`.
/// * **Cover artwork**. A book cover is an image; the ink and progress hairline
///   drawn over it must stay [AppColors.constantWhite] / [AppColors.constantBlack]
///   no matter the theme.
abstract final class AppPalette {
  // ---------------------------------------------------------------- light --
  static const canvas = Color(0xFFF5F3EF);
  static const canvasSubtle = Color(0xFFFAF8F5);
  static const card = Color(0xFFFFFFFF);
  static const popover = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF1C1B18);
  static const mutedForeground = Color(0xFF5C5954);
  static const foregroundTertiary = Color(0xFF8C8880);
  static const primary = Color(0xFF8F4A2E);
  static const primaryForeground = Color(0xFFFFFFFF);
  static const destructive = Color(0xFFB3261E);
  static const success = Color(0xFF107D32);
  static const warning = Color(0xFF8A5300);
  static const info = Color(0xFF1F5FA8);

  // ----------------------------------------------------------------- dark --
  static const canvasDark = Color(0xFF0F0E0D);
  static const canvasSubtleDark = Color(0xFF151311);
  static const cardDark = Color(0xFF1B1917);
  static const popoverDark = Color(0xFF1B1917);
  static const foregroundDark = Color(0xFFEDEBE6);
  static const mutedForegroundDark = Color(0xFFA3A099);
  static const foregroundTertiaryDark = Color(0xFF8A8681);
  static const primaryDark = Color(0xFFE39B76);
  static const primaryForegroundDark = Color(0xFF0F0E0D);
  static const destructiveDark = Color(0xFFFF6B63);
  static const successDark = Color(0xFF00CA50);
  static const warningDark = Color(0xFFFF9300);
  static const infoDark = Color(0xFF47A8FF);

  // ----------------------------------------------------- theme-agnostic --
  static const constantBlack = Color(0xFF000000);
  static const constantWhite = Color(0xFFFFFFFF);
  static const scrim = Color(0x66000000);

  /// Neutral overlays. They keep the surface beneath visible, so they are used
  /// for fills and outlines — never for text.
  static const secondaryLight = Color(0x0D000000); // 5 % black
  static const secondaryActiveLight = Color(0x1A000000); // 10 % black
  static const borderLight = Color(0x15000000); // 8.1 % black
  static const borderSubtleLight = Color(0x0D000000); // 5 % black
  static const borderStrongLight = Color(0x36000000); // 21 % black
  static const borderSelectedLight = Color(0x70000000); // 44 % black

  static const secondaryDark = Color(0x12FFFFFF); // 7 % white
  static const secondaryActiveDark = Color(0x21FFFFFF); // 13 % white
  static const borderDark = Color(0x17FFFFFF); // 9 % white
  static const borderSubtleDark = Color(0x12FFFFFF); // 7 % white
  static const borderStrongDark = Color(0x3DFFFFFF); // 24 % white
  static const borderSelectedDark = Color(0x8AFFFFFF); // 54 % white

  /// The single reader body accent kept as a comparison token for the extracted
  /// Fanqie resources. Not used by VELLUM chrome.
  static const fanqieReferenceAccent = Color(0xFFFA6725);
}
