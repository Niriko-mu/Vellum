import 'package:vellum/reader/reader_directory_panel_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_control_panels.dart';
import 'package:vellum/reader/reader_models.dart';

/// A larger system font scale is common on Chinese phones. It grows every fixed
/// height and every label in the catalogue panel, which is how the tab row used
/// to push the search and close buttons past the right edge.
void main() {
  final paragraphs = ['第一章 起兵', '太祖本纪，岁在天下大乱。'];

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    bool search = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: SizedBox(
              height: size.height,
              child: ReaderDirectoryPanel(
                chapters: const [MapEntry(0, '第一章 起兵')],
                bookmarks: const [],
                notes: const [],
                chapterPageLabels: const {},
                currentParagraph: 0,
                readingMode: ReadingMode.page,
                paragraphs: paragraphs,
                onJumpToParagraph: (_) {},
                onRemoveBookmark: (_) async {},
                onRemoveNote: (_) async {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (search) {
      await tester.tap(find.byIcon(CupertinoIcons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '天下');
      await tester.pump(const Duration(milliseconds: 250));
      final searchPanel = find.byType(ReaderDirectoryPanel);
      if (searchPanel.evaluate().isNotEmpty) {
        final state = tester.state<ReaderDirectoryPanelState>(
          searchPanel.first,
        );
        await tester.runAsync(
          () => state.runSearch(state.searchController.text),
        );
        await tester.pump();
      }
    }
  }

  testWidgets('catalogue panel survives enlarged system text', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final scale in const [1.0, 1.15, 1.3, 1.5, 1.8]) {
      for (final size in const [Size(390, 844), Size(390, 560)]) {
        await pump(tester, size: size, textScale: scale);
        expect(
          tester.takeException(),
          isNull,
          reason: 'panel overflowed at scale $scale, $size',
        );
      }
    }
  });

  testWidgets('search view survives enlarged system text', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final scale in const [1.0, 1.3, 1.5, 1.8]) {
      await pump(
        tester,
        size: const Size(390, 844),
        textScale: scale,
        search: true,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'search overflowed at scale $scale',
      );
      // The result is still there to tap.
      expect(find.textContaining('1 段'), findsOneWidget);
    }
  });

  testWidgets('the panel floor holds at enlarged text', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final scale in const [1.0, 1.3, 1.5, 1.8]) {
      await pump(
        tester,
        size: Size(390, ReaderDirectoryPanel.minPanelHeight),
        textScale: scale,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'minimum-height panel overflowed at scale $scale',
      );
    }
  });
}
