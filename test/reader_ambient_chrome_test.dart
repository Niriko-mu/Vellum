import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_ambient_chrome.dart';
import 'package:vellum/theme/app_motion.dart';

/// Ambient reader chrome (page number, running head, reading time).
///
/// The visible contract is small and easy to break silently: it must leave and
/// return with the menu instead of between two frames, must never eat a tap
/// while it is on its way out, and must be a hard cut - not a half-faded bar -
/// when the platform asks for reduced motion.
void main() {
  Widget host({required bool visible, bool reduceMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: ReaderAmbientChrome(
            visible: visible,
            child: const Text('页码', key: Key('ambient-label')),
          ),
        ),
      ),
    );
  }

  testWidgets('fades out and back instead of vanishing', (tester) async {
    await tester.pumpWidget(host(visible: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ambient-label')), findsOneWidget);

    await tester.pumpWidget(host(visible: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-flight the label is still mounted (fading), not already gone.
    expect(find.byKey(const Key('ambient-label')), findsOneWidget);
    final mid = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(const Key('ambient-label')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(mid.opacity.value, lessThan(1));
    expect(mid.opacity.value, greaterThan(0));
  });

  testWidgets('the way out is shorter than the way in', (tester) async {
    expect(
      AppMotion.dismiss.inMilliseconds,
      lessThan(AppMotion.base.inMilliseconds),
    );
  });

  testWidgets('hidden chrome takes no taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
              ReaderAmbientChrome(
                visible: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps += 100,
                  child: const SizedBox(width: 320, height: 80),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(160, 40));
    // The invisible bar must not have swallowed the tap.
    expect(taps, 1);
  });

  testWidgets('reduced motion is a hard cut, not a half-faded bar', (
    tester,
  ) async {
    await tester.pumpWidget(host(visible: false, reduceMotion: true));
    await tester.pump();
    expect(find.byKey(const Key('ambient-label')), findsNothing);

    await tester.pumpWidget(host(visible: true, reduceMotion: true));
    await tester.pump();
    // Present on the very first frame: nothing to wait for.
    expect(find.byKey(const Key('ambient-label')), findsOneWidget);
  });
}
