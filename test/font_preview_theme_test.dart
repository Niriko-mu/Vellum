import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/font_preview.dart';

void main() {
  testWidgets(
    'imported font preview binds both glyph samples to its font family',
    (tester) async {
      const font = InstalledFont(
        name: 'reader-font',
        family: 'Font_123',
        displayName: '阅读字体',
      );
      await tester.pumpWidget(
        const CupertinoApp(home: FontPreview(font: font, compact: true)),
      );

      for (final text in ['永', 'Aa']) {
        expect(
          tester.widget<Text>(find.text(text)).style!.fontFamily,
          font.family,
        );
      }
    },
  );

  test('the shell reads its surfaces from the token layer', () {
    // Legacy reader paper stays a user choice, not a theme role.
    expect(VellumTheme.paper, const Color(0xfff7e4cf));
    expect(VellumTheme.accent, AppColors.light.primary);
    expect(VellumTheme.darkAccent, AppColors.dark.primary);

    final theme = VellumTheme.forBrightness(Brightness.light);
    final colors = theme.extension<AppColors>()!;
    expect(colors.background, AppColors.light.background);
    expect(colors.card, AppColors.light.card);
    expect(theme.scaffoldBackgroundColor, colors.background);
    expect(theme.canvasColor, colors.background);
  });

  test('every semantic role differs between the two themes', () {
    final light = AppColors.light;
    final dark = AppColors.dark;
    expect(light.background, isNot(dark.background));
    expect(light.card, isNot(dark.card));
    expect(light.foreground, isNot(dark.foreground));
    expect(light.mutedForeground, isNot(dark.mutedForeground));
    expect(light.border, isNot(dark.border));
  });
}
