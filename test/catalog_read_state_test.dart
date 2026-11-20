import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_control_panels.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/services/notes_library.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/theme/app_icons.dart';

void main() {
  testWidgets('catalog greys chapters before the current reading position', (
    tester,
  ) async {
    // Fanqie three-state: read (60% ink) / current (accent) / unread (ink).
    const chapters = [
      MapEntry(0, '第一章'),
      MapEntry(50, '第二章'),
      MapEntry(100, '第三章'),
      MapEntry(200, '第四章'),
    ];

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SizedBox(
            height: 600,
            child: ReaderDirectoryPanel(
              bookTitle: '测试书',
              chapters: chapters,
              bookmarks: const [],
              notes: const <ReadingNote>[],
              chapterPageLabels: const {},
              currentParagraph: 120, // inside 第三章
              readingMode: ReadingMode.scroll,
              onJumpToParagraph: (_) {},
              onRemoveBookmark: (_) async {},
              onRemoveNote: (_) async {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('第三章'));
    // Panel ink is derived from the panel surface (reading paper / card),
    // not the app-bar ink — same rule as ReaderDirectoryPanel.
    final surface = VellumTheme.readerChromeOf(ctx);
    final themeInk = VellumTheme.readerChromeInk(surface);
    final readInk = themeInk.withValues(alpha: .6);

    Color? colorOf(String label) {
      final text = tester.widget<Text>(find.text(label));
      return text.style?.color;
    }

    // 第一章 / 第二章 are before current → 60% ink (read).
    expect(colorOf('第一章'), readInk);
    expect(colorOf('第二章'), readInk);
    // 第三章 contains current paragraph → accent + not grey.
    expect(colorOf('第三章'), ctx.c.primary);
    // 第四章 is after current → full ink (unread).
    expect(colorOf('第四章'), themeInk);

    // Fanqie P3/S3 secondary labels.
    expect(find.text('已读'), findsNWidgets(2));
    expect(find.text('当前章节'), findsOneWidget);
  });

  testWidgets('catalog can flip to descending order', (tester) async {
    const chapters = [
      MapEntry(0, '第一章'),
      MapEntry(50, '第二章'),
      MapEntry(100, '第三章'),
    ];

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SizedBox(
            height: 400,
            child: ReaderDirectoryPanel(
              bookTitle: '排序书',
              chapters: chapters,
              bookmarks: const [],
              notes: const <ReadingNote>[],
              chapterPageLabels: const {},
              currentParagraph: 60,
              readingMode: ReadingMode.scroll,
              onJumpToParagraph: (_) {},
              onRemoveBookmark: (_) async {},
              onRemoveNote: (_) async {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('正序'), findsOneWidget);
    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle();

    expect(find.text('倒序'), findsOneWidget);
    // Reverse: 第三章 first, 第一章 last.
    final titles = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .where((s) => s.startsWith('第') && s.endsWith('章'))
        .toList();
    expect(titles.first, '第三章');
    expect(titles.last, '第一章');
    // Current chapter (第二章) still highlighted in reverse order.
    final ctx = tester.element(find.text('第二章'));
    expect(
      tester.widget<Text>(find.text('第二章')).style?.color,
      ctx.c.primary,
    );
  });

  testWidgets('catalog item height matches Fanqie reader catalog 54dp', (
    tester,
  ) async {
    const chapters = [MapEntry(0, '第一章'), MapEntry(50, '第二章')];

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SizedBox(
            height: 400,
            child: ReaderDirectoryPanel(
              bookTitle: '高度书',
              chapters: chapters,
              bookmarks: const [],
              notes: const <ReadingNote>[],
              chapterPageLabels: const {},
              currentParagraph: 0,
              readingMode: ReadingMode.scroll,
              onJumpToParagraph: (_) {},
              onRemoveBookmark: (_) async {},
              onRemoveNote: (_) async {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final item = tester.widget<Container>(
      find
          .ancestor(of: find.text('第一章'), matching: find.byType(Container))
          .first,
    );
    // Layout height comes from ListView.itemExtent = 54.
    expect(ReaderDirectoryPanel.itemExtentForTest, 54);
    expect(item.padding, const EdgeInsets.symmetric(horizontal: 20));
  });

  testWidgets('catalog exposes resume progress and chapter jump semantics', (
    tester,
  ) async {
    final chapterJumps = <({int paragraph, bool restore})>[];
    var continued = false;
    const summary = ReaderProgressSummary(
      bookProgress: .42,
      chapterProgress: .35,
      currentChapterIndex: 1,
      currentChapterTitle: '第二章',
      currentPageLabel: '第 42 页',
      resumeChapterTitle: '第二章',
      hasResumePosition: true,
      isAtResumePosition: false,
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SizedBox(
            height: 620,
            child: ReaderDirectoryPanel(
              bookTitle: '进度书',
              chapters: const [
                MapEntry(0, '第一章'),
                MapEntry(50, '第二章'),
                MapEntry(100, '第三章'),
              ],
              bookmarks: const [],
              notes: const <ReadingNote>[],
              chapterPageLabels: const {50: '第 42 页'},
              currentParagraph: 60,
              readingMode: ReadingMode.page,
              progressSummary: summary,
              onContinueReading: () => continued = true,
              onJumpToChapter: (paragraph, {required restorePosition}) {
                chapterJumps.add((
                  paragraph: paragraph,
                  restore: restorePosition,
                ));
              },
              onJumpToParagraph: (_) {},
              onRemoveBookmark: (_) async {},
              onRemoveNote: (_) async {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('继续阅读'), findsOneWidget);
    // 本章 → 全书, matching the progress row directly above this card. The card
    // used to print the pair the other way round, so the same two numbers
    // appeared in two orders on one screen.
    expect(find.text('本章 35% · 全书 42% · 第 42 页'), findsOneWidget);
    expect(find.text('读到 35% · 第 42 页'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.chevronForward));
    expect(continued, isTrue);

    await tester.tap(find.text('第二章').last);
    await tester.tap(find.text('第一章').last);
    expect(chapterJumps, hasLength(2));
    expect(chapterJumps[0], (paragraph: 50, restore: true));
    expect(chapterJumps[1], (paragraph: 0, restore: false));
  });
}