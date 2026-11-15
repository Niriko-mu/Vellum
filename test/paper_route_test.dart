import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/theme/app_motion.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/ui/app_controls.dart';
import 'package:vellum/widgets/ui/paper_route.dart';

/// The reader's page transition: a Cupertino slide with a dissolve on top.
///
/// These assertions exist because the effect is invisible to every other test:
/// a route that slides without fading looks identical in a settled screenshot,
/// and a route that replaced the Cupertino transition would silently take the
/// edge-swipe-back gesture with it.
void main() {
  group('PaperRoute', () {
    test('stays inside the motion vocabulary', () {
      final route = PaperRoute<void>(builder: (_) => const SizedBox());
      expect(route.transitionDuration, AppMotion.slow);
      expect(route.reverseTransitionDuration, AppMotion.base);
      // Closing must not be slower than opening.
      expect(
        route.reverseTransitionDuration.inMilliseconds,
        lessThan(route.transitionDuration.inMilliseconds),
      );
      route.dispose();
    });

    testWidgets('keeps the Cupertino slide and adds a fade over it', (tester) async {
      await _openReader(tester);

      final page = find.text('reader-page');
      expect(
        find.ancestor(of: page, matching: find.byType(SlideTransition)),
        findsWidgets,
        reason: 'the framework transition must be wrapped, not replaced: it '
            'is what carries the edge-swipe-back gesture',
      );
      expect(
        find.ancestor(of: page, matching: find.byType(FadeTransition)),
        findsWidgets,
      );
    });

    testWidgets('the incoming page is translucent mid-flight, opaque at rest', (
      tester,
    ) async {
      await _openReader(tester);

      double opacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text('reader-page'),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;

      // 100 ms into a 350 ms route: still travelling, must not be solid yet.
      expect(opacity(), lessThan(1));
      expect(opacity(), greaterThan(0));

      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });

    testWidgets('is a clean slide when the platform asks for reduced motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _openReader(tester);

      expect(
        find.ancestor(
          of: find.text('reader-page'),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
        reason: 'a crossfade is still movement; reduced motion keeps the '
            'platform transition alone',
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

Future<void> _openReader(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: VellumTheme.forBrightness(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AppTextButton(
              label: 'open',
              onPressed: () => Navigator.of(context).push(
                PaperRoute<void>(builder: (_) => const _ReaderLike()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  // The route starts on the next frame; step a third of the way in.
  await tester.pump(const Duration(milliseconds: 100));
}

class _ReaderLike extends StatelessWidget {
  const _ReaderLike();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFFF5F3EF), child: Text('reader-page'));
}
