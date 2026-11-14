import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/library_models.dart';
import 'package:vellum/theme/app_icons.dart';

void main() {
  group('font size aligned to the reference reader', () {
    test('defaults match the 24dp body text the reference reader uses', () {
      expect(kReaderFontDefault, 24);
      expect(const ReaderPreferences().fontSize, 24);
      expect(const ReadingState().fontSize, 24);
    });

    test('legacy preferences are scaled once and then left alone', () {
      final legacy = ReaderPreferences.fromJson(const {'fontSize': 19});
      expect(legacy.fontScaleAligned, isFalse);

      final aligned = alignedReaderPreferences(legacy);
      expect(aligned.fontSize, 24);
      expect(aligned.fontScaleAligned, isTrue);

      // Applying again must not scale a second time.
      expect(alignedReaderPreferences(aligned).fontSize, 24);
    });

    test('scaled sizes stay inside the slider range', () {
      final huge = ReaderPreferences.fromJson(const {'fontSize': 40});
      final tiny = ReaderPreferences.fromJson(const {'fontSize': 10});
      expect(alignedReaderPreferences(huge).fontSize, kReaderFontMax);
      expect(
        alignedReaderPreferences(tiny).fontSize,
        greaterThanOrEqualTo(kReaderFontMin),
      );
    });

    test('aligned flags round-trip through storage', () {
      const prefs = ReaderPreferences(fontSize: 27, fontScaleAligned: true);
      final restored = ReaderPreferences.fromJson(prefs.toJson());
      expect(restored.fontSize, 27);
      expect(restored.fontScaleAligned, isTrue);
    });
  });

  test('legacy comfortable line spacing resolves to standard', () {
    expect(
      ReaderLineSpacing.fromStorage('comfortable'),
      ReaderLineSpacing.standard,
    );
    expect(
      ReaderLineSpacing.values.map((spacing) => spacing.label),
      isNot(contains('舒适')),
    );
  });

  testWidgets('panel keeps the seek row so chapter jump stays reachable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '测试书',
            format: BookFormat.txt,
            paragraphs: ['第一段正文'],
          ),
        ),
      ),
    );
    expect(find.byType(CupertinoNavigationBar), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    // Middle tap reveals chrome: progress row + action bar together.
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('上一章'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byIcon(AppIcons.chevronBack), findsOneWidget);
    expect(find.byIcon(AppIcons.bookmark), findsOneWidget);

    // A second centre tap retracts the header entirely; its back/bookmark
    // buttons must not remain on the reader surface.
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.chevronBack), findsNothing);
    expect(find.byIcon(AppIcons.bookmark), findsNothing);

    // Re-open controls for the panel assertions below.
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    // Opening a panel keeps seek row (P1) and shows the sheet.
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('上一章'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('阅读设置'), findsOneWidget);

    // Closing the panel leaves chrome (and seek) in place.
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('上一章'), findsOneWidget);
    expect(find.text('阅读设置'), findsNothing);
  });
}
