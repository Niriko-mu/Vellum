import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/system_ui.dart';
import 'package:vellum/theme/vellum_theme.dart';

/// The system bars are drawn over surfaces the app owns, and which surface that
/// is changes as the reader moves through the app.
///
/// Two failures motivated these tests: the framework's own light/dark presets
/// leave the *navigation* bar icons light in both themes (white buttons on a
/// near-white page), and the reader paints its paper under the status bar while
/// its icons still followed the app theme — a night paper under a light theme
/// left dark icons on a near-black page.
void main() {
  test('a light surface gets dark navigation bar icons', () {
    final style = VellumSystemUi.forBrightness(Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.statusBarIconBrightness, Brightness.dark);
    // Android otherwise paints its own scrim behind a transparent bar: that is
    // the grey band that appeared over the reader on a cold start.
    expect(style.systemStatusBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
    expect(style.statusBarColor, const Color(0x00000000));
  });

  test('a dark surface gets light icons', () {
    final style = VellumSystemUi.forBrightness(Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.statusBarIconBrightness, Brightness.light);
  });

  test('the reader follows the paper, not the app theme', () {
    // The white paper is light whatever the app theme says.
    final white = VellumSystemUi.forPaper(VellumTheme.readerWhite);
    expect(white.statusBarIconBrightness, Brightness.dark);
    expect(white.systemNavigationBarIconBrightness, Brightness.dark);

    // A night paper under the same light theme must flip the icons.
    final night = VellumSystemUi.forPaper(VellumTheme.readerNight);
    expect(night.statusBarIconBrightness, Brightness.light);
    expect(night.systemNavigationBarIconBrightness, Brightness.light);

    // ... and so must a custom ink that happens to be darker than the paper.
    final custom = VellumSystemUi.forPaper(const Color(0xFF202020));
    expect(custom.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('the reader page states its own overlay style', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: AppColors.light.primary,
        ),
        home: const ReaderPage(
          book: ImportedBook(
            title: '状态栏测试',
            format: BookFormat.txt,
            paragraphs: ['一段足够长的正文，用来让阅读页完成首次布局。'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(
      region.where((r) => r.value.systemNavigationBarIconBrightness != null),
      isNotEmpty,
      reason: 'the reader must state the bar style it wants',
    );
  });
}
