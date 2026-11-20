import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';

enum ReadingMode { scroll, page }

/// A lightweight snapshot for the reader's catalogue and seek controls.
///
/// It is derived from the live reader position and is deliberately separate
/// from [ReadingState]: opening the catalogue should never introduce a new
/// persisted format or migrate an existing book's progress JSON.
class ReaderProgressSummary {
  const ReaderProgressSummary({
    required this.bookProgress,
    required this.chapterProgress,
    required this.currentChapterIndex,
    required this.currentChapterTitle,
    required this.currentPageLabel,
    required this.resumeChapterTitle,
    required this.hasResumePosition,
    required this.isAtResumePosition,
  });

  final double bookProgress;
  final double chapterProgress;
  final int currentChapterIndex;
  final String currentChapterTitle;
  final String currentPageLabel;
  final String resumeChapterTitle;
  final bool hasResumePosition;
  final bool isAtResumePosition;
}

/// PagePhysics that settles on a page without a visible overscroll bounce.
///
/// Tuned toward Fanqie's custom Scroller (`nt5/g.java`): friction is very low
/// (≈0.01) and a fling can travel ~0.8 screen-heights, so the page *coasts*
/// instead of stopping dead. Default [PageScrollPhysics] uses a soft spring
/// that overshoots, which reads as an unexpected rebound; [SnapPageScrollPhysics]
/// keeps the no-bounce settle but lets fast flicks carry further.
class SnapPageScrollPhysics extends PageScrollPhysics {
  const SnapPageScrollPhysics({super.parent});

  /// Critical damping: settle without bounce. Slightly softer than the old
  /// stiffness:800 so a medium flick still travels a full page.
  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.5,
    stiffness: 480.0,
    ratio: 1.0,
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final page = position is PageMetrics ? position.page : null;
    if (page == null) {
      return super.createBallisticSimulation(position, velocity);
    }
    final targetPixels = page.roundToDouble() * position.viewportDimension;
    // Already on a page boundary and nearly at rest: do not start a spring.
    final tolerance = toleranceFor(position);
    if (velocity.abs() < tolerance.velocity &&
        (position.pixels - targetPixels).abs() < 0.5) {
      return null;
    }
    // Fast flicks: coast toward the adjacent page with critical damping.
    // Fanqie's low-friction fling lets a confident swipe clear a page; the
    // default spring stops too early and feels "sticky".
    final viewport = position.viewportDimension;
    if (viewport > 0 && velocity.abs() > 700) {
      final maxPage = position.maxScrollExtent / viewport;
      final direction = velocity.sign;
      final targetPage = (page + direction).clamp(0.0, maxPage);
      final target = targetPage * viewport;
      return SpringSimulation(spring, position.pixels, target, velocity);
    }
    return super.createBallisticSimulation(position, velocity);
  }
}

enum PageTurnStyle {
  /// A flipped sheet carried across on its own layer, with an edge shadow.
  cover('覆盖'),

  /// The whole page slides, as if the book were a strip.
  slide('平移'),

  /// A simulated curl: the corner lifts, the fold travels, and the lifted part
  /// is mirrored back as the paper's reverse.
  curl('仿真'),

  none('无动画');

  const PageTurnStyle(this.label);
  final String label;

  static PageTurnStyle fromStorage(String value) =>
      PageTurnStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => PageTurnStyle.cover,
      );
}

/// Line-height presets for the reader surface.
///
/// Fanqie drives this through CSS `line-space` presets (0.35em / 0.5em /
/// 0.68em / 1em on a 1.4 base) plus a custom clamp of 4.0–44.0px. Flutter's
/// `TextStyle.height` is a font-size multiplier, so the presets below map the
/// same feel onto multipliers: 超窄≈1.4+0.15, 窄≈1.4+0.3, 标准≈1.4+0.5,
/// 宽松≈1.4+0.8. Older persisted `comfortable` values map to `standard`.
enum ReaderLineSpacing {
  xNarrow('超窄', 1.45),
  narrow('窄', 1.7),
  standard('标准', 1.9),
  relaxed('宽松', 2.2);

  const ReaderLineSpacing(this.label, this.height);

  final String label;
  final double height;

  static ReaderLineSpacing fromStorage(String value) {
    if (value == 'comfortable') return ReaderLineSpacing.standard;
    return ReaderLineSpacing.values.firstWhere(
      (spacing) => spacing.name == value,
      orElse: () => ReaderLineSpacing.standard,
    );
  }
}

/// Warm-tint overlay laid over the reading surface. [opacity] is the strength
/// of the amber wash — enough to cut blue light without hiding the page.
///
/// Fanqie's eye-protect layer is a single overlay at alpha 0.15
/// (`is_eye_protect_open`); `standard` matches that level.
enum ReaderEyeCare {
  off('关闭', 0),
  soft('柔和', 0.10),
  standard('标准', 0.15),
  warm('暖黄', 0.20);

  const ReaderEyeCare(this.label, this.opacity);

  final String label;
  final double opacity;

  static ReaderEyeCare fromStorage(String value) =>
      ReaderEyeCare.values.firstWhere(
        (level) => level.name == value,
        orElse: () => ReaderEyeCare.off,
      );
}

enum ReaderFontWeight {
  light('细', FontWeight.w300),
  regular('常规', FontWeight.w400),
  bold('粗', FontWeight.w600);

  const ReaderFontWeight(this.label, this.value);

  final String label;
  final FontWeight value;

  static ReaderFontWeight fromStorage(String value) =>
      ReaderFontWeight.values.firstWhere(
        (weight) => weight.name == value,
        orElse: () => ReaderFontWeight.regular,
      );
}

class PageFragment {
  const PageFragment({
    required this.paragraphIndex,
    required this.text,
    this.showImage = false,
    this.showLinkAction = false,
    this.compactPadding = false,
    this.indentFirstLine = true,
  });

  final int paragraphIndex;
  final String text;
  final bool showImage;
  final bool showLinkAction;
  final bool compactPadding;
  final bool indentFirstLine;
}
