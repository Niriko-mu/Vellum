import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Brightness, MaterialApp, MediaQuery, MediaQueryData, TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/markdown_preview.dart';

/// The preview widget itself: it must lay out the reader's paragraph model
/// without a book, without a network, and without an HTML engine.
void main() {
  Widget host(String source, {double textScale = 1}) {
    return MaterialApp(
      theme: VellumTheme.forBrightness(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Builder(
          builder: (context) => CupertinoPageScaffold(
            backgroundColor: context.c.background,
            child: MarkdownPreview(source: source),
          ),
        ),
      ),
    );
  }

  testWidgets('renders headings and body without a book or a network', (
    tester,
  ) async {
    await tester.pumpWidget(host('# 巡检标题\n\n正文段落，带**加粗**与*斜体*。'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('巡检标题'), findsWidgets);
    expect(find.textContaining('正文段落'), findsWidgets);
  });

  testWidgets(
    'an empty draft explains itself instead of showing a blank page',
    (tester) async {
      await tester.pumpWidget(host('   '));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有内容'), findsOneWidget);
    },
  );

  testWidgets('a large text scale does not overflow the preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('# 大字号标题\n\n这是一段足够长的正文，用来确认在放大字号之后仍然可以正常换行而不会溢出边界。', textScale: 1.6),
    );
    await tester.pumpAndSettle();
    // A RenderFlex overflow would surface here rather than as a visual glitch.
    expect(tester.takeException(), isNull);
  });
}
