import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_gestures.dart';
import 'package:vellum/reader/reader_models.dart';

void main() {
  group('page swipes reach the page-turn style', () {
    final now = DateTime.now();

    test('leftward flick turns to the next page', () {
      final action = ReaderGestures.resolvePointerUp(
        downAt: now,
        downPosition: const Offset(320, 400),
        upPosition: const Offset(240, 410),
        mode: ReadingMode.page,
        beginsAtScrollTop: false,
        isIdle: true,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(action, ReaderTapAction.nextPage);
    });

    test('rightward flick turns to the previous page', () {
      final action = ReaderGestures.resolvePointerUp(
        downAt: now,
        downPosition: const Offset(100, 400),
        upPosition: const Offset(190, 395),
        mode: ReadingMode.page,
        beginsAtScrollTop: false,
        isIdle: true,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(action, ReaderTapAction.previousPage);
    });

    test('short horizontal nudge stays a tap, not a swipe', () {
      final action = ReaderGestures.resolvePointerUp(
        downAt: now,
        downPosition: const Offset(350, 400),
        upPosition: const Offset(340, 402),
        mode: ReadingMode.page,
        beginsAtScrollTop: false,
        isIdle: true,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(action, ReaderTapAction.nextPage); // right-edge tap zone
    });

    test('selection drag is never a page swipe', () {
      final action = ReaderGestures.resolvePointerUp(
        downAt: now,
        downPosition: const Offset(200, 400),
        upPosition: const Offset(80, 405),
        mode: ReadingMode.page,
        beginsAtScrollTop: false,
        isIdle: true,
        screenWidth: 400,
        screenHeight: 800,
        selectionGesture: true,
      );
      expect(action, ReaderTapAction.none);
    });

    test('scroll mode ignores horizontal flicks', () {
      final action = ReaderGestures.resolvePointerUp(
        downAt: now,
        downPosition: const Offset(320, 400),
        upPosition: const Offset(200, 400),
        mode: ReadingMode.scroll,
        beginsAtScrollTop: true,
        isIdle: true,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(action, ReaderTapAction.none);
    });
  });
}
