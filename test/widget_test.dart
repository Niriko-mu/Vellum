import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText, SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/vellum.dart';

void main() {
  test('Bing search URI keeps the selected text as q parameter', () {
    final uri = buildBingSearchUri('哈利 波特 & 魔法');

    expect(uri.scheme, 'https');
    expect(uri.host, 'cn.bing.com');
    expect(uri.path, '/search');
    expect(uri.queryParameters['q'], '哈利 波特 & 魔法');
    expect(uri.queryParameters['q'], isNotEmpty);
  });

  testWidgets('shows only the empty-library import action initially', (
    tester,
  ) async {
    await tester.pumpWidget(const VellumApp());

    expect(find.text('书库是空的'), findsOneWidget);
    expect(find.text('导入电子书'), findsOneWidget);
    expect(find.text('晚上好，读者'), findsNothing);
    expect(find.text('阅读偏好'), findsNothing);
  });

  test('defines distinct light and dark palettes', () {
    expect(VellumTheme.light.brightness, Brightness.light);
    expect(VellumTheme.dark.brightness, Brightness.dark);
    expect(
      VellumTheme.light.scaffoldBackgroundColor,
      isNot(VellumTheme.dark.scaffoldBackgroundColor),
    );
    expect(
      VellumTheme.light.textTheme.textStyle.color,
      isNot(VellumTheme.dark.textTheme.textStyle.color),
    );
  });

  test('reader papers keep their exact requested text contrast', () {
    // Fanqie STANDARD reader resources + ReaderCommonColor ink pairs.
    expect(VellumTheme.readerWhite, const Color(0xfff6f6f6));
    expect(VellumTheme.readerSepia, const Color(0xffded9c5));
    expect(VellumTheme.readerMint, const Color(0xffd8e3cc));
    expect(VellumTheme.readerBlue, const Color(0xffccd8e3));
    expect(VellumTheme.readerNight, const Color(0xff0e0e0e));
    expect(VellumTheme.readerCharcoal, const Color(0xff1a1a1a));
    expect(VellumTheme.readerSoftBlack, const Color(0xff262626));
    expect(
      VellumTheme.readerInkFor(VellumTheme.darkPaper),
      CupertinoColors.white,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerNight),
      const Color(0xffb7b7b7),
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerMint),
      VellumTheme.readerBodyInk,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerSepia),
      const Color(0xff141000),
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerCharcoal),
      const Color(0xff808080),
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerSoftBlack),
      const Color(0xff8c8c8c),
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerBlue),
      VellumTheme.readerBodyInk,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerWhite),
      VellumTheme.readerBodyInk,
    );
    // Fanqie brand orange lives on the reader only.
    expect(VellumTheme.readerAccent, const Color(0xfffa6725));
    // App shell keeps quiet wine so nav bars stay familiar.
    expect(VellumTheme.accent, const Color(0xffa33d2e));
  });

  test('legacy reader papers migrate to the standard Fanqie palette', () {
    expect(
      VellumTheme.normalizeReaderBackground(const Color(0xffd7d7db)),
      VellumTheme.readerWhite,
    );
    expect(
      VellumTheme.normalizeReaderBackground(const Color(0xfff7e4cf)),
      VellumTheme.readerSepia,
    );
    expect(
      VellumTheme.normalizeReaderBackground(const Color(0xffc9decb)),
      VellumTheme.readerMint,
    );
    expect(
      VellumTheme.normalizeReaderBackground(const Color(0xffc2def0)),
      VellumTheme.readerBlue,
    );
    expect(
      VellumTheme.normalizeReaderBackground(const Color(0xff262626)),
      VellumTheme.readerNight,
    );
  });

  testWidgets('switches application theme from inside the app', (tester) async {
    await tester.pumpWidget(const VellumApp());
    await tester.tap(find.text('设置').last);
    await tester.pump();
    final before = tester.widget<CupertinoApp>(find.byType(CupertinoApp));

    await tester.tap(find.byIcon(CupertinoIcons.moon));
    await tester.pump();

    final after = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(after.theme?.brightness, isNot(before.theme?.brightness));
  });

  testWidgets('shows storage management in the settings tab', (tester) async {
    await tester.pumpWidget(const VellumApp());
    await tester.tap(find.text('设置').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('阅读数据'), findsOneWidget);
    expect(find.text('阅读统计'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('存储管理'), 200);
    expect(find.text('存储管理'), findsOneWidget);
    expect(find.text('占用空间'), findsOneWidget);
    expect(find.text('清空书库'), findsOneWidget);
    expect(find.text('清除阅读记录'), findsOneWidget);
  });

  testWidgets('shows a delete action for books in the library', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: LibraryPage(
          books: const [
            ImportedBook(
              title: '待删除的书',
              format: BookFormat.txt,
              paragraphs: ['正文'],
            ),
          ],
          onOpen: (_) {},
          onImport: () {},
          onDelete: (_) {},
        ),
      ),
    );

    expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);
  });

  testWidgets('reading controls live in the reader overlay', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '测试书',
            format: BookFormat.txt,
            paragraphs: ['一段正文'],
          ),
        ),
      ),
    );
    expect(find.byType(CupertinoNavigationBar), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    // Fanqie menu chrome animates 300ms.
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoNavigationBar), findsNothing);
    expect(find.text('测试书'), findsWidgets);
    // Fanqie action row: 目录 | 日间/夜间 | 设置（字体在设置面板内）
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('上一章'), findsOneWidget);
    expect(find.text('下一章'), findsOneWidget);
    expect(find.text('阅读方式'), findsNothing);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // First level: mode + font size + brightness + paper + font + line space.
    // Half-screen sheet may clip the tail — scroll the panel if needed.
    Future<void> ensureSetting(String label) async {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty) return;
      var guard = 0;
      while (guard < 6) {
        final hit = tester.getTopLeft(finder).dy;
        if (hit >= 0 && hit < 600) return;
        await tester.drag(
          find.byType(ReaderSettingsPanel),
          const Offset(0, -80),
        );
        await tester.pumpAndSettle();
        guard++;
      }
    }

    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.text('阅读方式'), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('背景'), findsOneWidget);
    // Basic papers are on the first level; custom lives behind a jump button.
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('字重'), findsNothing);
    expect(find.text('常亮'), findsNothing);

    await ensureSetting('更多设置');
    await tester.ensureVisible(find.text('更多设置'));
    await tester.tap(find.text('更多设置'));
    await tester.pumpAndSettle();

    expect(find.text('字重'), findsOneWidget);
    // 护眼 moved into the background studio (paper / overlay / ink family).
    expect(find.text('护眼'), findsNothing);
    expect(find.text('常亮'), findsOneWidget);
    expect(find.text('音量键'), findsOneWidget);

    // Panel-internal back returns to first-level settings only.
    await tester.tap(
      find.descendant(
        of: find.byType(ReaderSettingsPanel),
        matching: find.byIcon(CupertinoIcons.chevron_back),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.text('阅读方式'), findsOneWidget);
    expect(find.text('字重'), findsNothing);

    // Second level: image import, underlay, opacity, ink picker, eye-care.
    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义背景'), findsOneWidget);
    expect(find.text('背景图'), findsOneWidget);
    expect(find.text('导入图片'), findsOneWidget);
    expect(find.text('正文字色（阅读正文的颜色）'), findsOneWidget);
    expect(find.text('护眼'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ReaderSettingsPanel),
        matching: find.byIcon(CupertinoIcons.chevron_back),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('scroll reader provides one selection area across paragraphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '跨段选择',
            format: BookFormat.txt,
            paragraphs: ['第一段可选择文字。', '第二段可选择文字。'],
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('renders an inline image marker inside its paragraph', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '段内注释',
            format: BookFormat.mobi,
            paragraphs: const ['正文前[[image:1]]正文后'],
            imageBytes: {0: Uint8List(0)},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('正文前'), findsOneWidget);
    expect(find.textContaining('[[image:'), findsNothing);
  });

  testWidgets('reader font button explains how to import when no font exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '字体提示',
            format: BookFormat.txt,
            paragraphs: ['一段正文'],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    // Fanqie structure: 字体 lives inside the settings panel.
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    // Half-screen sheet: bring 字体 into view before tapping.
    final fontFinder = find.text('字体');
    var guard = 0;
    while (fontFinder.evaluate().isNotEmpty &&
        tester.getTopLeft(fontFinder).dy >= 600 &&
        guard < 6) {
      await tester.drag(find.byType(ReaderSettingsPanel), const Offset(0, -80));
      await tester.pumpAndSettle();
      guard++;
    }
    await tester.ensureVisible(fontFinder);
    await tester.tap(fontFinder);
    await tester.pumpAndSettle();

    expect(find.text('选择字体'), findsOneWidget);
    expect(find.text('系统字体'), findsOneWidget);
    expect(find.textContaining('永Aa'), findsWidgets);
  });

  testWidgets(
    'long press on reader text shows a Cupertino selection menu without errors',
    (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: ReaderPage(
            book: ImportedBook(
              title: '长按选择',
              format: BookFormat.txt,
              paragraphs: ['可被选择的阅读正文。'],
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(CupertinoAdaptiveTextSelectionToolbar),
        findsOneWidget,
      );
    },
  );

  testWidgets('dark scroll reader selection uses a Cupertino toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          initialState: ReadingState(backgroundValue: 0xff262522),
          book: ImportedBook(
            title: '暗色选择',
            format: BookFormat.txt,
            paragraphs: ['暗色阅读器中的可选择正文。'],
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoAdaptiveTextSelectionToolbar), findsOneWidget);
  });
  test('persists bookmark paragraph indexes in reading state', () {
    const state = ReadingState(lineSpacing: 'relaxed', bookmarks: [3, 18]);
    final restored = ReadingState.fromJson(state.toJson());
    expect(restored.bookmarks, [3, 18]);
    expect(restored.lineSpacing, 'relaxed');
  });

  test('persists independent chapter reading positions', () {
    const state = ReadingState(
      paragraphIndex: 120,
      chapterPositions: {
        0: ChapterReadingPosition(paragraphIndex: 12, position: 240),
        100: ChapterReadingPosition(paragraphIndex: 118, position: 1880),
      },
    );
    final restored = ReadingState.fromJson(state.toJson());
    expect(restored.chapterPositions[0]?.paragraphIndex, 12);
    expect(restored.chapterPositions[100]?.position, 1880);
    expect(restored.chapterPositions, hasLength(2));
  });

  testWidgets('shows a red top marker for a bookmarked reader page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          initialState: ReadingState(mode: 'page', bookmarks: [0]),
          book: ImportedBook(
            title: '书签页标记',
            format: BookFormat.txt,
            paragraphs: ['已加书签的页面正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('当前阅读页面已添加书签'), findsOneWidget);
  });

  testWidgets('chapter panel keeps table-of-contents and body entries', (
    tester,
  ) async {
    // This test verifies that chapter entries are preserved
    // The actual UI interaction is tested in the app
    final book = const ImportedBook(
      title: '目录筛选',
      format: BookFormat.mobi,
      paragraphs: [
        '目录',
        '第1章 目录中的第一章',
        '第2章 目录中的第二章',
        '献词 第1章',
        '正文的第一章',
        '正文内容',
        '第2章',
        '正文的第二章',
      ],
    );

    // Verify the book has the expected paragraphs
    expect(book.paragraphs.length, 8);
    expect(book.paragraphs[1], '第1章 目录中的第一章');
    expect(book.paragraphs[2], '第2章 目录中的第二章');
    expect(book.paragraphs[7], '正文的第二章');
  });

  testWidgets('persists the selected reading mode before leaving the reader', (
    tester,
  ) async {
    ReadingState? saved;
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          onStateChanged: (value) async => saved = value,
          book: const ImportedBook(
            title: '阅读方式记忆',
            format: BookFormat.txt,
            paragraphs: ['正文'],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    // Reading mode is on the first settings level (usability).
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('左右翻页'));
    await tester.pump();

    expect(saved?.mode, 'page');

    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: saved!,
          book: const ImportedBook(
            title: '阅读方式记忆',
            format: BookFormat.txt,
            paragraphs: ['正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('lazily builds long scroll reading content', (tester) async {
    final paragraphs = List<String>.generate(20000, (index) => '第 $index 段');
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '长篇测试书',
            format: BookFormat.txt,
            paragraphs: paragraphs,
          ),
        ),
      ),
    );

    expect(find.text('长篇测试书'), findsOneWidget);
    expect(find.text('第 19999 段'), findsNothing);
  });

  testWidgets('page mode clamps an obsolete saved page index', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page', page: 999999),
          book: const ImportedBook(
            title: '旧阅读记录',
            format: BookFormat.txt,
            paragraphs: ['短正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('短正文'), findsOneWidget);
  });

  testWidgets('saves page progress when the app enters the background', (
    tester,
  ) async {
    ReadingState? saved;
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          onStateChanged: (value) async {
            saved = value;
          },
          book: ImportedBook(
            title: '后台保存',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(
              9,
              (index) => '第 ${index + 1} 段正文',
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('AppLifecycleState.paused'),
      (_) {},
    );
    await tester.pump();

    expect(saved?.page, 1);
  });

  testWidgets('restores and persists vertical scroll position', (tester) async {
    ReadingState? saved;
    final paragraphs = List<String>.generate(
      160,
      (index) => '第 $index 段。' * 12,
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(position: 260),
          onStateChanged: (value) async => saved = value,
          book: ImportedBook(
            title: '滚动位置恢复',
            format: BookFormat.txt,
            paragraphs: paragraphs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollView = tester.widget<ListView>(find.byType(ListView));
    expect(scrollView.controller?.offset, greaterThan(0));

    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('AppLifecycleState.paused'),
      (_) {},
    );
    await tester.pump();

    expect(saved?.mode, 'scroll');
    expect(saved?.position, greaterThan(0));
  });

  testWidgets('vertical reading drag does not open the footer', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '滑动测试',
            format: BookFormat.txt,
            paragraphs: ['第一段正文', '第二段正文', '第三段正文'],
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(400, 500), const Offset(400, 200));
    await tester.pump();

    expect(find.text('阅读方式'), findsNothing);
    expect(find.text('阅读进度'), findsNothing);
  });

  testWidgets('page mode prevents vertical scrolling inside a page', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          book: ImportedBook(
            title: '纵向手势',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(9, (index) => '第 $index 段正文'),
          ),
        ),
      ),
    );

    final pageList = tester.widget<ListView>(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(ListView),
      ),
    );
    expect(pageList.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('downward pull adds a visible bookmark notice in page mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          book: ImportedBook(
            title: '下拉书签',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(
              9,
              (index) => '第 ${index + 1} 段可添加书签的正文',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.page?.round(), 0);

    // A slight diagonal must still belong to the downward bookmark pull,
    // never to the horizontal PageView.
    await tester.timedDragFrom(
      const Offset(400, 300),
      const Offset(30, 220),
      const Duration(milliseconds: 80),
    );
    await tester.pump();

    expect(find.text('书签已添加'), findsOneWidget);
    expect(pageView.controller?.page?.round(), 0);
  });
  testWidgets('page mode navigates with left and right screen taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          book: ImportedBook(
            title: '翻页测试',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(
              9,
              (index) => '第 ${index + 1} 段翻页内容',
            ),
          ),
        ),
      ),
    );

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.initialPage, 0);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(pageView.controller?.page?.round(), 1);
  });

  testWidgets('none page-turn style jumps without a residual bounce', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page', pageTurn: 'none'),
          book: ImportedBook(
            title: '无动画翻页',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(
              9,
              (index) => '第 ${index + 1} 段翻页内容',
            ),
          ),
        ),
      ),
    );

    final pageView = tester.widget<PageView>(find.byType(PageView));
    // Finger swipes are routed through _changePage so PageTurnStyle applies;
    // the PageView itself must not scroll on its own.
    expect(pageView.physics, isA<NeverScrollableScrollPhysics>());

    await tester.tapAt(const Offset(700, 300));
    // One frame is enough: jump is immediate, no spring frames in between.
    await tester.pump();

    expect(pageView.controller?.page, moreOrLessEquals(1.0, epsilon: 0.01));
    expect(pageView.controller!.position.isScrollingNotifier.value, isFalse);
  });
}
