import 'package:flutter/cupertino.dart';

/// Semantic palette for Vellum.
///
/// VELLUM's shell uses a warm vellum/terracotta palette. Reader papers remain
/// independent Fanqie-compatible surfaces so reading comfort is not coupled to
/// the application's brand theme.
abstract final class VellumTheme {
  static const systemUiFontFamily = 'sans-serif';
  static String fontFamily = systemUiFontFamily;
  static String contentFontFamily = 'serif';

  // Fanqie reference accent. It remains available for comparing the extracted
  // palette, but VELLUM controls use the shared shell accent below so the
  // reader and library feel like one product.
  static const readerAccent = Color(0xfffa6725);
  static const readerAccentDark = Color(0xffffa177);

  // Shared app-shell accent (nav bars, library actions and reader controls).
  // Terracotta keeps the paper-inspired identity legible in both themes.
  static const accent = Color(0xffa95c46);
  static const darkAccent = Color(0xffd8896c);

  // App shell (library / settings).
  // `paper` is retained as the legacy reading underlay used by older saved
  // states; the shell uses the warm semantic surfaces below.
  static const paper = Color(0xfff7e4cf);
  static const card = Color(0xfffff8ef);
  static const ink = Color(0xff2a211b);
  static const muted = Color(0xff7a6558);
  static const line = Color(0xffe5cdb7);
  static const darkPaper = Color(0xff111110);
  static const darkCard = Color(0xff1c1917);
  static const darkInk = Color(0xfff0ebe1);
  static const darkMuted = Color(0xffa8a29e);
  static const darkLine = Color(0xff3a3530);

  static const shellPaper = Color(0xfff7f3ed);
  static const shellCard = Color(0xfffffdf8);
  static const shellInk = Color(0xff2b2723);
  static const shellMuted = Color(0xff756c65);
  static const shellLine = Color(0xffe4dcd3);
  static const shellDarkPaper = Color(0xff151311);
  static const shellDarkCard = Color(0xff211e1a);
  static const shellDarkInk = Color(0xfff5efe7);
  static const shellDarkMuted = Color(0xffb6aaa0);
  static const shellDarkLine = Color(0xff443a33);

  // Fanqie STANDARD reader resources (ReaderBgColorType.STANDARD). The
  // similarly named `*_theme_bg_light` resources are brightness variants,
  // not the normal reading papers shown by the default background picker.
  static const readerWhite = Color(0xfff6f6f6);
  static const readerSepia = Color(0xffded9c5);
  static const readerMint = Color(0xffd8e3cc);
  static const readerBlue = Color(0xffccd8e3);
  static const readerNight = Color(0xff0e0e0e);
  static const readerNightInk = Color(0xffb7b7b7);
  static const readerCharcoal = Color(0xff1a1a1a);
  static const readerCharcoalInk = Color(0xff808080);
  static const readerSoftBlack = Color(0xff262626);
  static const readerSoftBlackInk = Color(0xff8c8c8c);

  /// Fanqie body ink on light papers is pure black.
  static const readerBodyInk = Color(0xff000000);
  static const readerHairline = Color(0x14000000);

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: accent,
    scaffoldBackgroundColor: shellPaper,
    barBackgroundColor: shellPaper,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(
        inherit: false,
        color: shellInk,
        fontFamily: systemUiFontFamily,
      ),
      navTitleTextStyle: TextStyle(
        inherit: false,
        color: shellInk,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        fontFamily: systemUiFontFamily,
      ),
      navLargeTitleTextStyle: TextStyle(
        inherit: false,
        color: shellInk,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        fontFamily: systemUiFontFamily,
      ),
    ),
  );

  static const dark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: darkAccent,
    scaffoldBackgroundColor: shellDarkPaper,
    barBackgroundColor: shellDarkPaper,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(
        inherit: false,
        color: shellDarkInk,
        fontFamily: systemUiFontFamily,
      ),
      navTitleTextStyle: TextStyle(
        inherit: false,
        color: shellDarkInk,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        fontFamily: systemUiFontFamily,
      ),
      navLargeTitleTextStyle: TextStyle(
        inherit: false,
        color: shellDarkInk,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        fontFamily: systemUiFontFamily,
      ),
    ),
  );

  static CupertinoThemeData forBrightness(
    Brightness brightness, {
    String fontFamily = systemUiFontFamily,
  }) {
    final base = brightness == Brightness.dark ? dark : light;
    return base.copyWith(
      textTheme: CupertinoTextThemeData(
        textStyle: base.textTheme.textStyle.copyWith(fontFamily: fontFamily),
        navTitleTextStyle: base.textTheme.navTitleTextStyle.copyWith(
          fontFamily: fontFamily,
        ),
        navLargeTitleTextStyle: base.textTheme.navLargeTitleTextStyle.copyWith(
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  static Color inkOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? shellDarkInk
      : shellInk;

  /// Fanqie body ink on a reader paper (pure black on light, #B7B7B7 night).
  static Color readerInkFor(Color background) {
    if (background == darkPaper) return CupertinoColors.white;
    if (background == readerSepia) return const Color(0xff141000);
    if (background == readerNight) return readerNightInk;
    if (background == readerCharcoal) return readerCharcoalInk;
    if (background == readerSoftBlack) return readerSoftBlackInk;
    return readerBodyInk;
  }

  /// Migrate papers persisted before the STANDARD Fanqie palette was restored.
  /// Reading state stores raw ARGB values, so changing constants alone would
  /// otherwise leave existing books on the old LIGHT resource variants.
  static Color? normalizeReaderBackground(Color? background) {
    if (background == null) return null;
    return switch (background.toARGB32()) {
      0xffd7d7db => readerWhite,
      0xfff7e4cf => readerSepia,
      0xffc9decb => readerMint,
      0xffc2def0 => readerBlue,
      // This used to be Vellum's first night swatch (Fanqie theme 5), whose
      // actual STANDARD background is #0E0E0E.
      0xff262626 => readerNight,
      _ => background,
    };
  }

  /// Secondary text on a reader paper (Fanqie `#66000000` body).
  static Color readerMutedInk(Color surface) {
    final ink = readerInkFor(surface);
    final night =
        surface == readerNight ||
        surface == readerCharcoal ||
        surface == readerSoftBlack;
    return ink.withValues(alpha: night ? .55 : .4);
  }

  /// App-shell surface (nav bar / scaffold) — always matches the page paper.
  static Color shellOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? shellDarkPaper
      : shellPaper;

  static Color mutedOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? shellDarkMuted
      : shellMuted;
  static Color accentOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkAccent
      : accent;

  /// Shared interactive accent for the reader and the application shell.
  ///
  /// The reading paper remains user-selectable (Fanqie's paper mechanism),
  /// while selection, progress, bookmarks and settings use the same VELLUM
  /// terracotta as the library and settings pages.
  static Color readerAccentOf(BuildContext context) => accentOf(context);
  static Color lineOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? shellDarkLine
      : shellLine;
  static Color cardOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? shellDarkCard
      : shellCard;

  /// Reader chrome surface. Prefer the active reading paper (Fanqie menu
  /// sits on theme bg). Defaults to Fanqie white paper in light mode.
  static Color readerChromeOf(BuildContext context, {Color? paper}) {
    if (paper != null) return paper;
    return CupertinoTheme.of(context).brightness == Brightness.dark
        ? darkPaper
        : readerWhite;
  }

  static Color readerChromeInk(Color surface) => readerInkFor(surface);

  static Color softAccentOf(BuildContext context) =>
      accentOf(context).withValues(alpha: .12);
}
