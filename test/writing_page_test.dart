import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/vellum.dart';

/// In-memory library so the editor can auto-save without path_provider.
class _MemoryWritingLibrary extends WritingLibrary {
  final List<WritingDocument> docs = [];
  int upsertCount = 0;

  @override
  Future<WritingDocument> upsert(WritingDocument document) async {
    upsertCount++;
    final index = docs.indexWhere((item) => item.id == document.id);
    if (index >= 0) {
      docs[index] = document;
    } else {
      docs.insert(0, document);
    }
    return document;
  }
}

void main() {
  testWidgets('writing tab shows empty state and new draft action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(home: WritingPage(initialDocuments: [])),
    );
    await tester.pump();

    expect(find.text('开始写作'), findsOneWidget);
    expect(find.text('新建文稿'), findsOneWidget);
  });

  testWidgets('writing editor opens with title and body fields', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      CupertinoApp(
        home: WritingEditorPage(
          document: WritingDocument(
            id: 'w_test',
            title: '草稿',
            body: '第一段',
            format: WritingFormat.md,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Markdown'), findsWidgets);
    expect(find.text('纯文本'), findsWidgets);
    expect(find.text('草稿'), findsOneWidget);
    expect(find.text('第一段'), findsOneWidget);
    expect(find.textContaining('字'), findsWidgets);
  });

  testWidgets('draft search matches body text and recovers when cleared', (
    tester,
  ) async {
    final now = DateTime.now();
    final documents = [
      WritingDocument(
        id: 'one',
        title: '第一篇',
        body: '海边的灯塔',
        createdAt: now,
        updatedAt: now,
      ),
      WritingDocument(
        id: 'two',
        title: '第二篇',
        body: '山间的来信',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await tester.pumpWidget(
      CupertinoApp(home: WritingPage(initialDocuments: documents)),
    );
    await tester.enterText(find.byType(CupertinoSearchTextField), '灯塔');
    await tester.pumpAndSettle();
    expect(find.text('第一篇'), findsOneWidget);
    expect(find.text('第二篇'), findsNothing);
    await tester.enterText(find.byType(CupertinoSearchTextField), '无匹配的文字');
    await tester.pumpAndSettle();
    expect(find.text('未找到相关文稿'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoSearchTextField), '');
    await tester.pumpAndSettle();
    expect(find.text('第一篇'), findsOneWidget);
    expect(find.text('第二篇'), findsOneWidget);
  });

  testWidgets(
    'writing supports narrow dark screens with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final doc = WritingDocument(
        id: 'narrow',
        title: '窄屏长标题测试文稿',
        body: '正文内容。' * 40,
        createdAt: now,
        updatedAt: now,
      );
      Widget shell(Widget child, {bool keyboard = false}) => CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.7),
            viewInsets: EdgeInsets.only(bottom: keyboard ? 240 : 0),
          ),
          child: child!,
        ),
        home: child,
      );
      await tester.pumpWidget(shell(WritingPage(initialDocuments: [doc])));
      await tester.pumpAndSettle();
      expect(find.text(doc.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        shell(
          WritingEditorPage(document: doc, library: _MemoryWritingLibrary()),
          keyboard: true,
        ),
      );
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.textformat_size), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edits auto-save after a typing pause, no save button', (
    tester,
  ) async {
    final library = _MemoryWritingLibrary();
    final now = DateTime.now();
    await tester.pumpWidget(
      CupertinoApp(
        home: WritingEditorPage(
          library: library,
          document: WritingDocument(
            id: 'w_auto',
            title: '草稿',
            body: '',
            format: WritingFormat.md,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();

    // The manual save button is gone — auto-save owns the commit.
    expect(find.text('保存'), findsNothing);

    await tester.enterText(find.byType(CupertinoTextField).at(1), '自动保存的正文');
    await tester.pump();
    expect(find.textContaining('即将自动保存'), findsOneWidget);

    // 600 ms debounce + the write itself.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(library.upsertCount, 1);
    expect(library.docs.single.body, '自动保存的正文');
    expect(find.textContaining('已自动保存'), findsOneWidget);
    expect(find.textContaining('未保存'), findsNothing);
  });

  testWidgets('typo panel paints taps immediately and toggles novel mode', (
    tester,
  ) async {
    final library = _MemoryWritingLibrary();
    final now = DateTime.now();
    await tester.pumpWidget(
      CupertinoApp(
        home: WritingEditorPage(
          library: library,
          document: WritingDocument(
            id: 'w_panel',
            title: '草稿',
            body: '第一段。\n第二段。',
            // Novel mode is a plain-text rule; Markdown keeps the switch off.
            format: WritingFormat.txt,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.textformat_size));
    await tester.pumpAndSettle();
    expect(find.text('排版'), findsOneWidget);
    expect(find.text('小说模式'), findsOneWidget);
    expect(find.text('系统字体'), findsOneWidget);

    // Weight segment: the chip highlights as soon as it is tapped.
    await tester.tap(find.text('粗'));
    await tester.pump();
    final segmented = tester.widget<CupertinoSlidingSegmentedControl<int>>(
      find.byType(CupertinoSlidingSegmentedControl<int>),
    );
    expect(segmented.groupValue, 3);

    // Novel switch: flips in the panel without waiting on disk.
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();
    final sw = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    expect(sw.value, isTrue);

    // Navbar also has 完成; close the sheet via its own button.
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    // Toggling on formats the draft in place (段首两格).
    expect(find.textContaining('　　第一段'), findsOneWidget);
  });

  testWidgets('Markdown drafts keep novel mode switched off', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      CupertinoApp(
        home: WritingEditorPage(
          library: _MemoryWritingLibrary(),
          document: WritingDocument(
            id: 'w_md',
            title: 'MD稿',
            body: '第一段。',
            format: WritingFormat.md,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.textformat_size));
    await tester.pumpAndSettle();
    expect(find.text('Markdown 模式下不启用，切换到纯文本即可使用'), findsOneWidget);

    final sw = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNull);
  });
}
