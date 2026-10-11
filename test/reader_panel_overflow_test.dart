import 'package:vellum/reader/reader_directory_panel_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_control_panels.dart';
import 'package:vellum/reader/reader_models.dart';

/// The catalogue/settings sheet is a fixed slot between the reader's top bar and
/// its bottom chrome. The soft keyboard shrinks the viewport without shrinking
/// that slot, so the panel can end up shorter than its own header — which paints
/// the black/yellow overflow stripes over the search field.
///
/// [ReaderDirectoryPanel.minPanelHeight] is the contract that keeps that from
/// happening, and the panel falls back to a compact header below its full one.
void main() {
  final paragraphs = ['第一章 起兵', '太祖本纪，岁在甲子，天下大乱。'];
  const chapters = [MapEntry(0, '第一章 起兵')];

  Future<void> pumpPanel(WidgetTester tester, double height) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: height,
              child: ReaderDirectoryPanel(
                chapters: chapters,
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
  }

  testWidgets('no overflow at the guaranteed minimum height', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPanel(tester, ReaderDirectoryPanel.minPanelHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow while searching at the minimum height', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPanel(tester, ReaderDirectoryPanel.minPanelHeight);

    await tester.tap(find.byIcon(CupertinoIcons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '天下');
    await tester.pump(const Duration(milliseconds: 250));
    final searchPanel = find.byType(ReaderDirectoryPanel);
    if (searchPanel.evaluate().isNotEmpty) {
      final state = tester.state<ReaderDirectoryPanelState>(searchPanel.first);
      await tester.runAsync(() => state.runSearch(state.searchController.text));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    // The summary bar reports both counts, even in a squeezed panel.
    expect(find.textContaining('1 段 · 1 处'), findsOneWidget);
  });

  testWidgets('the compact header keeps every way out', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPanel(tester, ReaderDirectoryPanel.minPanelHeight);

    // Close, the three tabs and the search entry point survive the squeeze.
    expect(find.byIcon(CupertinoIcons.clear), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('书签'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);

    // 取消 leaves search mode even in the compact layout.
    await tester.tap(find.byIcon(CupertinoIcons.search));
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('搜索全书内容'), findsNothing);
    expect(find.byIcon(CupertinoIcons.clear), findsOneWidget);
  });

  testWidgets('the full header returns once there is room', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPanel(tester, ReaderDirectoryPanel.headerHeight + 200);

    // Book name, tabs and the order toggle are all back.
    expect(find.text('正序'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a keyboard-shortened reader menu never overflows', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A short viewport where the keyboard would leave the sheet at its floor.
    await pumpPanel(tester, ReaderDirectoryPanel.minPanelHeight + 6);
    await tester.tap(find.byIcon(CupertinoIcons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '太祖');
    await tester.pump(const Duration(milliseconds: 250));
    final searchPanel = find.byType(ReaderDirectoryPanel);
    if (searchPanel.evaluate().isNotEmpty) {
      final state = tester.state<ReaderDirectoryPanelState>(searchPanel.first);
      await tester.runAsync(() => state.runSearch(state.searchController.text));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
