import 'dart:ui' show Offset;

import 'reader_models.dart';

enum ReaderTapAction {
  none,
  toggleBookmark,
  toggleControls,
  previousPage,
  nextPage,
}

/// Pure gesture classification for the reader surface.
///
/// Tap zones follow Fanqie (`zw4/n.java`): left third / middle third / right
/// third for paged mode; in scroll mode the control zone is a wider band
/// (0.3H–0.65H) so the thumb does not have to reach the exact centre.
abstract final class ReaderGestures {
  static const double leftZoneEnd = 0.333;
  static const double rightZoneStart = 0.667;
  static const double scrollCenterTop = 0.30;
  static const double scrollCenterBottom = 0.65;

  static bool isCenterTap(Offset position, double width, double height) {
    final inX =
        position.dx >= width * leftZoneEnd &&
        position.dx <= width * rightZoneStart;
    final inY =
        position.dy >= height * scrollCenterTop &&
        position.dy <= height * scrollCenterBottom;
    return inX && inY;
  }

  static const double bookmarkPullThreshold = 96;

  /// Minimum horizontal travel for a flick to count as a page swipe.
  /// Comfortably above the 12px tap slop, small enough for short swipes.
  static const double swipeMinDistance = 40;

  /// Long-press to select text then drag down must not arm bookmark.
  /// Bookmark requires a quick, mostly vertical downward flick at the top.
  static const Duration bookmarkMaxHold = Duration(milliseconds: 400);

  /// Fanqie throttles volume-key paging to 300 ms so a held key does not
  /// flip dozens of pages.
  static const Duration volumeKeyThrottle = Duration(milliseconds: 300);

  static ReaderTapAction resolvePointerUp({
    required DateTime? downAt,
    required Offset? downPosition,
    required Offset upPosition,
    required ReadingMode mode,
    required bool beginsAtScrollTop,
    required bool isIdle,
    required double screenWidth,
    required double screenHeight,
    bool selectionGesture = false,
  }) {
    if (downAt == null || downPosition == null) return ReaderTapAction.none;

    final elapsed = DateTime.now().difference(downAt);
    final delta = upPosition - downPosition;
    final downwardPull = delta.dy > bookmarkPullThreshold;
    final horizontalShift = delta.dx.abs();
    final quickFlick = elapsed < bookmarkMaxHold && !selectionGesture;
    final mostlyVertical = horizontalShift < 48;
    if (downwardPull && beginsAtScrollTop && quickFlick && mostlyVertical) {
      return ReaderTapAction.toggleBookmark;
    }
    // Horizontal page swipe (finger flick, not a tap). Leftward = next page.
    // Must run BEFORE the tap-distance rejection so swipes are not dropped —
    // that was why PageTurnStyle had no effect on drags.
    if (mode == ReadingMode.page &&
        !selectionGesture &&
        horizontalShift >= swipeMinDistance &&
        horizontalShift > delta.dy.abs()) {
      return delta.dx < 0
          ? ReaderTapAction.nextPage
          : ReaderTapAction.previousPage;
    }
    // A long-press drag is selection, not a tap action.
    if (elapsed >= const Duration(milliseconds: 450) || delta.distance > 12) {
      return ReaderTapAction.none;
    }
    if (!isIdle) return ReaderTapAction.none;

    if (mode != ReadingMode.page) {
      if (isCenterTap(upPosition, screenWidth, screenHeight)) {
        return ReaderTapAction.toggleControls;
      }
      return ReaderTapAction.none;
    }

    if (upPosition.dx < screenWidth * leftZoneEnd) {
      return ReaderTapAction.previousPage;
    }
    if (upPosition.dx > screenWidth * rightZoneStart) {
      return ReaderTapAction.nextPage;
    }
    return ReaderTapAction.toggleControls;
  }
}
