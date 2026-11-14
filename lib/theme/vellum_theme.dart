import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_type.dart';

/// VELLUM's theme assembly point.
///
/// The chain is strictly one-way: [AppPalette] → [AppColors] → widgets. This
/// file wires the semantic roles into a [ThemeData] (for widgets, focus, ripples
/// and [ThemeExtension] lookup) and into a [CupertinoThemeData] (for the
/// Cupertino chrome the product uses on purpose). Widgets read colours through
/// `context.c` and never through [AppPalette].
///
/// **Reader papers are not theme roles.** They are a persisted user choice, so
/// they live here next to [readerInkFor] and are never derived from [AppColors].
abstract final class VellumTheme {
  static const systemUiFontFamily = 'sans-serif';
  static String fontFamily = systemUiFontFamily;
  static String contentFontFamily = 'serif';

  // ------------------------------------------------------------------------
  // Brand.
  // ------------------------------------------------------------------------

  /// The single emphasised accent. 5.95:1 on [AppPalette.canvas].
  static const accent = AppPalette.primary;
  static const darkAccent = AppPalette.primaryDark;

  /// Comparison token for the extracted Fanqie resources; not used by chrome.
  static const readerAccent = AppPalette.fanqieReferenceAccent;
  static const readerAccentDark = Color(0xFFFFA177);

  // ------------------------------------------------------------------------
  // Reader papers — persisted user choices, upstream of the tokens.
  // ------------------------------------------------------------------------
  static const paper = Color(0xFFF7E4CF);
  static const card = Color(0xFFFFF8EF);
  static const ink = Color(0xFF2A211B);
  static const muted = Color(0xFF7A6558);
  static const line = Color(0xFFE5CDB7);
  static const darkPaper = Color(0xFF111110);
  static const darkCard = Color(0xFF1C1917);
  static const darkInk = Color(0xFFF0EBE1);
  static const darkMuted = Color(0xFFA8A29E);
  static const darkLine = Color(0xFF3A3530);

  // Fanqie STANDARD reader resources (ReaderBgColorType.STANDARD). The
  // similarly named `*_theme_bg_light` resources are brightness variants,
  // not the normal reading papers shown by the default background picker.
  static const readerWhite = Color(0xFFF6F6F6);
  static const readerSepia = Color(0xFFDED9C5);
  static const readerMint = Color(0xFFD8E3CC);
  static const readerBlue = Color(0xFFCCD8E3);
  static const readerNight = Color(0xFF0E0E0E);
  static const readerNightInk = Color(0xFFB7B7B7);
  static const readerCharcoal = Color(0xFF1A1A1A);
  static const readerCharcoalInk = Color(0xFF808080);
  static const readerSoftBlack = Color(0xFF262626);
  static const readerSoftBlackInk = Color(0xFF8C8C8C);

  /// Fanqie body ink on light papers is pure black.
  static const readerBodyInk = Color(0xFF000000);
  static const readerHairline = Color(0x14000000);

  /// Fanqie body ink on a reader paper (pure black on light, #B7B7B7 night).
  ///
  /// This reads the paper, not a token: the paper *is* the surface, so its
  /// paired ink is the colour decision itself.
  static Color readerInkFor(Color background) {
    if (background == darkPaper) return CupertinoColors.white;
    if (background == readerSepia) return const Color(0xFF141000);
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
      0xFFD7D7DB => readerWhite,
      0xFFF7E4CF => readerSepia,
      0xFFC9DECB => readerMint,
      0xFFC2DEF0 => readerBlue,
      // This used to be Vellum's first night swatch (Fanqie theme 5), whose
      // actual STANDARD background is #0E0E0E.
      0xFF262626 => readerNight,
      _ => background,
    };
  }

  static bool _isNightPaper(Color surface) =>
      surface == readerNight ||
      surface == readerCharcoal ||
      surface == readerSoftBlack;

  /// Secondary text on a reader paper (Fanqie `#66000000` body).
  static Color readerMutedInk(Color surface) {
    final ink = readerInkFor(surface);
    return ink.withValues(alpha: _isNightPaper(surface) ? .55 : .4);
  }

  /// Secondary chrome text on a reader paper (top-bar title, panel labels).
  ///
  /// The four alphas below are pinned, not hand-tuned at each call site: the
  /// page used to derive nine different translucencies on the fly, and two of
  /// them fell under the contrast floor.
  static Color readerSecondaryInk(Color surface) {
    final ink = readerInkFor(surface);
    return ink.withValues(alpha: _isNightPaper(surface) ? .82 : .78);
  }

  /// Tertiary text and running heads on a reader paper.
  ///
  /// The alpha floor is pinned at .55 (4.65:1 on the white paper) instead of the
  /// old .38 (2.64:1, below both the 4.5 text and the 3.0 graphics threshold).
  static Color readerTertiaryInk(Color surface) {
    final ink = readerInkFor(surface);
    return ink.withValues(alpha: _isNightPaper(surface) ? .62 : .58);
  }

  /// Reader chrome surface. Prefers the active reading paper (the Fanqie menu
  /// sits on the theme bg). Defaults to the white paper.
  static Color readerChromeOf(BuildContext context, {Color? paper}) {
    if (paper != null) return paper;
    return context.c.brightness == Brightness.dark ? darkPaper : readerWhite;
  }

  static Color readerChromeInk(Color surface) => readerInkFor(surface);

  // ------------------------------------------------------------------------
  // Theme construction.
  // ------------------------------------------------------------------------
  static const _titleFallback = 'sans-serif';

  static TextTheme _textTheme(String family, AppColors colors) {
    TextStyle style(int index, FontWeight weight, Color color) {
      final step = AppTypeStep.at(index);
      return TextStyle(
        inherit: false,
        color: color,
        fontFamily: family,
        fontSize: step.size,
        height: step.heightFactor,
        fontWeight: weight,
        letterSpacing: 0,
      );
    }

    final ink = colors.foreground;
    final muted = colors.mutedForeground;
    return TextTheme(
      // 页面大标题 → 32/40 semibold
      headlineMedium: style(AppTypeStep.xxxl, FontWeight.w600, ink),
      // 分组标题 / 状态标题 → 16/24 semibold
      titleMedium: style(AppTypeStep.base, FontWeight.w600, ink),
      // 行标题 / 正文 → 16/24 regular
      bodyMedium: style(AppTypeStep.base, FontWeight.w400, ink),
      bodyLarge: style(AppTypeStep.lg, FontWeight.w400, ink),
      // 次要说明 / 页脚 → 14/20
      bodySmall: style(AppTypeStep.sm, FontWeight.w400, muted),
      // 元信息 / 计数 → 13/18
      labelSmall: style(AppTypeStep.xs, FontWeight.w500, muted),
      labelLarge: style(AppTypeStep.base, FontWeight.w500, ink),
      titleLarge: style(AppTypeStep.xl, FontWeight.w600, ink),
      titleSmall: style(AppTypeStep.sm, FontWeight.w500, ink),
      displayLarge: style(AppTypeStep.xxxxl, FontWeight.w600, ink),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required String family,
  }) {
    final textTheme = _textTheme(family, colors);
    final dark = brightness == Brightness.dark;
    final base = dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      cardColor: colors.card,
      dividerColor: colors.border,
      shadowColor: colors.constantBlack,
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.secondary,
      hoverColor: colors.secondary,
      focusColor: colors.primary.withValues(alpha: 0.20),
      primaryColor: colors.primary,
      disabledColor: colors.foregroundTertiary,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[colors],
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
            brightness: brightness,
            primary: colors.primary,
            onPrimary: colors.primaryForeground,
            secondary: colors.foreground,
            onSecondary: colors.background,
            surface: colors.card,
            onSurface: colors.foreground,
            error: colors.destructive,
            onError: colors.constantWhite,
            outline: colors.borderStrong,
            outlineVariant: colors.border,
          ),
      // The product's own chrome, not Material's: no elevation, no cards with
      // shadows, no ink ripple. The Material layer exists for text fields,
      // focus traversal and the ThemeExtension handoff.
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppText.sectionHeader(colors.foreground).copyWith(
          fontFamily: family,
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData get light => _build(
    brightness: Brightness.light,
    colors: AppColors.light,
    family: systemUiFontFamily,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    colors: AppColors.dark,
    family: systemUiFontFamily,
  );

  static ThemeData forBrightness(
    Brightness brightness, {
    String fontFamily = systemUiFontFamily,
  }) {
    final family = fontFamily.isEmpty ? _titleFallback : fontFamily;
    return _build(
      brightness: brightness,
      colors: brightness == Brightness.dark ? AppColors.dark : AppColors.light,
      family: family,
    );
  }

  /// The Cupertino layer, mounted inside [MaterialApp.builder] so the Cupertino
  /// chrome keeps native title/back composition and the edge-swipe pop.
  static CupertinoThemeData cupertinoOf(BuildContext context) {
    final theme = Theme.of(context);
    final family = theme.textTheme.bodyMedium?.fontFamily ?? systemUiFontFamily;
    return cupertinoFor(theme.brightness, fontFamily: family);
  }

  /// The Cupertino layer for a bare brightness — used by tests and by any
  /// Cupertino surface mounted outside the Material shell.
  static CupertinoThemeData cupertinoForBrightness(
    Brightness brightness, {
    String fontFamily = systemUiFontFamily,
  }) => cupertinoFor(brightness, fontFamily: fontFamily);

  static CupertinoThemeData cupertinoFor(
    Brightness brightness, {
    required String fontFamily,
  }) {
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    final family = fontFamily;
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: colors.primary,
      scaffoldBackgroundColor: colors.background,
      barBackgroundColor: colors.background,
      applyThemeToAll: true,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          inherit: false,
          color: colors.foreground,
          fontFamily: family,
          decoration: TextDecoration.none,
        ),
        navTitleTextStyle: AppText.sectionHeader(
          colors.foreground,
        ).copyWith(fontFamily: family, inherit: false),
        navLargeTitleTextStyle: AppText.pageTitle(
          colors.foreground,
        ).copyWith(fontFamily: family, inherit: false),
        actionTextStyle: AppText.rowTitle(
          colors.primary,
        ).copyWith(fontFamily: family, inherit: false),
        tabLabelTextStyle: AppText.tabLabel(
          colors.mutedForeground,
        ).copyWith(fontFamily: family, inherit: false),
      ),
    );
  }

  /// The semantic roles for the current theme.
  ///
  /// The per-role accessors that used to live here (`inkOf`, `mutedOf`, …) are
  /// gone: every call site reads `context.c.<role>` directly, so a role has one
  /// name instead of two.
  static AppColors colorsOf(BuildContext context) => context.c;
}
