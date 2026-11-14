import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/font_manager_sheet.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/vellum_theme.dart';

const _font = InstalledFont(
  name: 'manager-font',
  family: 'Font_manager',
  displayName: '阅读字体',
);

void main() {
  testWidgets('font manager empty state follows the warm shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: VellumTheme.cupertinoForBrightness(Brightness.light),
        home: CupertinoPageScaffold(
          child: FontManagerSheet(
            installedFonts: [],
            activeFontName: '',
            onActivateFont: _noopFontAction,
            onDeleteFont: _noopFontAction,
            onImportFonts: _noopAsync,
          ),
        ),
      ),
    );

    expect(find.text('字体管理'), findsOneWidget);
    expect(find.text('暂无字体'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('暂无字体')).style!.color,
      AppColors.light.mutedForeground,
    );
  });

  testWidgets('font manager card and delete dialog adapt to dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: VellumTheme.cupertinoForBrightness(Brightness.dark),
        home: CupertinoPageScaffold(
          child: FontManagerSheet(
            installedFonts: const [_font],
            activeFontName: _font.name,
            onActivateFont: _noopFontAction,
            onDeleteFont: _noopFontAction,
            onImportFonts: _noopAsync,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.text('阅读字体')).style!.color,
      AppColors.dark.foreground,
    );
    expect(find.text('当前使用中'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.trash));
    await tester.pumpAndSettle();
    expect(find.text('删除字体'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}

Future<void> _noopFontAction(String value) async {}
Future<void> _noopAsync() async {}
