import 'package:flutter/services.dart';

/// The system bars (status bar icons, navigation bar icons) for one surface.
///
/// Two things live here rather than in a widget:
///
/// * **The icon brightness is stated, not inherited.** The framework's
///   `SystemUiOverlayStyle.light` and `.dark` both leave the *navigation* bar
///   icons light, so a light theme drew white buttons on a near-white page.
/// * **Contrast enforcement is switched off.** With a transparent bar, Android
///   may paint its own scrim behind the status bar; that is the grey band that
///   appeared above the reader on a cold start and disappeared after a tab
///   switch.
abstract final class VellumSystemUi {
  /// Chrome for a normal app surface of the given brightness.
  static SystemUiOverlayStyle forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: const Color(0x00000000),
      systemNavigationBarDividerColor: const Color(0x00000000),
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Chrome for the reading paper.
  ///
  /// The paper is a persisted user choice and does not follow the app theme, so
  /// the icons have to follow the *paper*: a night paper under a light app theme
  /// otherwise left dark icons on a near-black page.
  static SystemUiOverlayStyle forPaper(Color paper) {
    // The paper decides, not its ink: a night paper's ink is a mid grey whose
    // own luminance sits near the midpoint, so asking the ink where the paper
    // is gives the wrong answer for exactly the case this exists for.
    final lightPaper = paper.computeLuminance() > .5;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: lightPaper ? Brightness.dark : Brightness.light,
      statusBarBrightness: lightPaper ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: const Color(0x00000000),
      systemNavigationBarDividerColor: const Color(0x00000000),
      systemNavigationBarIconBrightness: lightPaper
          ? Brightness.dark
          : Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
