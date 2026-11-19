import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Brightness, MaterialApp, MediaQuery, MediaQueryData;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_page_overlay.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/vellum_theme.dart';

/// The cover-turn overlay, asserted as geometry rather than as a screenshot.
///
/// A screenshot of a 200 ms turn can only prove that one sampled frame looked
/// plausible - and the device screencap is slower than the animation, so even
/// that was unreliable. The properties that actually make a page turn read as
/// a page turn are relationships, and relationships can be asserted at every
/// progress value: the travelling page follows its own progress, it moves the
/// right way, it hides the page beneath at 0 and clears it at 1, it carries the
/// edge shadow, and it never takes the tap.
void main() {
  Widget host({
    required int from,
    required int to,
    required Animation<double> animation,
  }) {
    return MaterialApp(
      theme: VellumTheme.forBrightness(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Builder(
          builder: (context) => Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: context.c.background,
              child: SizedBox(
                width: 400,
                height: 800,
                child: Stack(
                  children: [
                    ReaderCoverTurnOverlay(
                      fromPage: from,
                      toPage: to,
                      animation: animation,
                      dragTurn: false,
                      dragCommitted: false,
                      pageSurface: (context, page) => Center(
                        child: Text('page-$page', key: Key('page-$page')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal offset of the travelling page, as a fraction of width.
  double translationOf(WidgetTester tester, String label) {
    final finder = find.ancestor(
      of: find.byKey(Key(label)),
      matching: find.byType(FractionalTranslation),
    );
    final widget = tester.widget<FractionalTranslation>(finder.first);
    return widget.translation.dx;
  }

  testWidgets('a forward turn moves the outgoing page left, by its progress', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(from: 0, to: 1, animation: controller));
    await tester.pump();

    // At rest the travelling page fully covers the page beneath.
    expect(translationOf(tester, 'page-0'), 0);

    controller.value = .5;
    await tester.pump();
    final half = translationOf(tester, 'page-0');
    expect(half, lessThan(0), reason: 'a forward turn must travel left');
    expect(half, greaterThan(-1));

    controller.value = 1;
    await tester.pump();
    expect(
      translationOf(tester, 'page-0'),
      -1,
      reason: 'at the end it has cleared the viewport entirely',
    );
  });

  testWidgets('a backward turn brings the incoming page in from the left', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(from: 1, to: 0, animation: controller));
    await tester.pump();

    // Going back, the *target* page is the one that travels.
    expect(translationOf(tester, 'page-0'), -1);
    controller.value = 1;
    await tester.pump();
    expect(translationOf(tester, 'page-0'), 0);
  });

  testWidgets('translation tracks progress monotonically, with no re-curve', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(from: 0, to: 1, animation: controller));
    await tester.pump();

    var previous = 1.0;
    for (final value in [.1, .25, .4, .6, .8, .95]) {
      controller.value = value;
      await tester.pump();
      final dx = translationOf(tester, 'page-0');
      expect(
        dx,
        lessThan(previous),
        reason: 'the page must keep moving left as progress rises',
      );
      // Linear mapping: the overlay reads the raw controller value, so a
      // re-applied curve here would show up as a mismatch.
      expect(dx, closeTo(-value, 0.001));
      previous = dx;
    }
  });

  testWidgets('the overlay never swallows a tap while turning', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 200),
      value: .5,
    );
    addTearDown(controller.dispose);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 400,
              height: 800,
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(),
                  ),
                  ReaderCoverTurnOverlay(
                    fromPage: 0,
                    toPage: 1,
                    animation: controller,
                    dragTurn: true,
                    dragCommitted: false,
                    pageSurface: (context, page) => const SizedBox.expand(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tapAt(const Offset(200, 400));
    expect(
      taps,
      1,
      reason:
          'the turn layer is paint-only; the gesture layer beneath owns taps',
    );
  });

  testWidgets('the travelling page carries the edge shadow', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 200),
      value: .5,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(from: 0, to: 1, animation: controller));
    await tester.pump();

    final decorated = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(ReaderCoverTurnOverlay),
        matching: find.byType(DecoratedBox),
      ),
    );
    final shadows = decorated
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.boxShadow?.isNotEmpty ?? false)
        .toList();
    expect(
      shadows,
      hasLength(1),
      reason: 'exactly one surface may cast the page-edge shadow',
    );
    expect(shadows.single.boxShadow!.single.offset.dx, greaterThan(0));
  });
}
