import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/widgets/ui/app_dock_auto_hide.dart';

/// The dock answers the page's scroll instead of always occupying the edge.
///
/// Every rule here is one that a plausible-looking implementation gets wrong:
/// hiding on *offset* rather than movement, flickering on a trackpad's many
/// tiny deltas, hiding on a horizontal strip, leaving an invisible bar that
/// still eats taps, or sliding in an interface that asked to stay still.
void main() {
  Widget host({
    required ScrollController controller,
    bool enabled = true,
    bool reduceMotion = false,
    bool horizontal = false,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 600,
          child: AppDockAutoHide(
            enabled: enabled,
            dock: const SizedBox(
              height: 64,
              child: Text('dock', key: Key('dock-label')),
            ),
            page: horizontal
                ? ListView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    children: const [SizedBox(width: 2000, height: 20)],
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: 200,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 48, child: Text('row $i')),
                  ),
          ),
        ),
      ),
    );
  }

  testWidgets('travel down hides the dock, travel up brings it back', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('dock'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    var slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byKey(const Key('dock-label')),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.offset.dy, greaterThan(0), reason: 'it must leave downward');

    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byKey(const Key('dock-label')),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.offset, Offset.zero, reason: 'an upward move reveals it');
  });

  testWidgets('a page restored at a deep offset keeps the dock visible', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 2000);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();
    // Offset alone proves nothing: only movement does.
    final slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byKey(const Key('dock-label')),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.offset, Offset.zero);
  });

  testWidgets('a horizontal strip never hides the dock', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller: controller, horizontal: true));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    final slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byKey(const Key('dock-label')),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.offset, Offset.zero);
  });

  testWidgets('a hidden dock takes no taps', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var tabs = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 600,
            child: AppDockAutoHide(
              dock: SizedBox(
                height: 64,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tabs++,
                  child: const Text('dock'),
                ),
              ),
              page: ListView.builder(
                controller: controller,
                itemCount: 200,
                itemBuilder: (_, i) =>
                    SizedBox(height: 48, child: Text('row $i')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // The dock is still in the tree but covered by a zero-opacity, ignored
    // surface: tapping where it sits must reach the page, not the dock.
    expect(find.text('dock'), findsOneWidget);
    await tester.tapAt(
      tester.getBottomRight(find.text('dock')) - const Offset(20, 20),
    );
    await tester.pumpAndSettle();
    expect(tabs, 0);
  });

  testWidgets('reduced motion swaps instantly instead of sliding', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller: controller, reduceMotion: true));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    final slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byKey(const Key('dock-label')),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.duration, Duration.zero);
  });
}
