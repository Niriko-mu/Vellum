import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/widgets/ui/shelf_reveal.dart';

/// The shelf's first frames. The rules that matter are the ones a plausible
/// implementation gets wrong: a card that scrolls away and back must not
/// replay its entrance, and the whole grid must land even when the last cards
/// start late.
void main() {
  Widget host({
    required int count,
    bool reduceMotion = false,
    ScrollController? controller,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 600,
          child: ShelfRevealScope(
            child: ListView.builder(
              controller: controller,
              itemCount: count,
              itemBuilder: (context, index) => ShelfRevealItem(
                index: index,
                child: SizedBox(
                  height: 60,
                  child: Text('card $index', key: Key('card-$index')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('cards assemble over the first frames', (tester) async {
    await tester.pumpWidget(host(count: 12));
    await tester.pump();
    // First frame: cards exist but are not yet fully opaque.
    await tester.pump(const Duration(milliseconds: 40));
    final early = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('card-0')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(early.opacity, lessThan(1));

    await tester.pumpAndSettle();
    // The grid is a plain grid once the clock ends.
    final settled = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('card-0')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(settled.opacity, 1);
  });

  testWidgets('the last row still lands: every window closes by the end', (
    tester,
  ) async {
    await tester.pumpWidget(host(count: 40));
    await tester.pumpAndSettle();
    // Index 7 is the last slot of the stagger ring; it must not be stranded.
    final last = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('card-7')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(last.opacity, 1);
  });

  testWidgets('a card scrolled away and back does not replay', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(count: 60, controller: controller));
    await tester.pumpAndSettle();

    // Scroll far enough that the first card is disposed.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-0')), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 2200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-0')), findsOneWidget);
    // Rebuilt, but not re-staged: the clock is done, so no Opacity wrapper.
    expect(
      find.ancestor(
        of: find.byKey(const Key('card-0')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: 'a returning card must not fade in again',
    );
  });

  testWidgets('reduced motion renders the grid immediately', (tester) async {
    await tester.pumpWidget(host(count: 12, reduceMotion: true));
    await tester.pump();
    expect(find.byKey(const Key('card-0')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('card-0')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });
}
