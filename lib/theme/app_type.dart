import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show immutable;

/// The 13-step type scale.
///
/// The first nine carry product roles; the last four exist so the ladder keeps
/// ascending. This array is also the accessibility ladder: a font-size setting
/// of 0/1/2 shifts the index, so "one step up" is always the next real size.
/// Editing a hardcoded size in a widget does nothing — edit this array.
const List<(double size, double lineHeight)> appTypeSequence = [
  (13, 18), // xs
  (14, 20), // sm
  (16, 24), // base
  (18, 28), // lg
  (20, 26), // xl
  (24, 32), // 2xl
  (32, 40), // 3xl
  (40, 48), // 4xl
  (48, 56), // 5xl
  (60, 72), // 6xl
  (72, 96), // 7xl
  (96, 128), // 8xl
  (128, 128), // 9xl
];

/// A resolved size pair from [appTypeSequence].
@immutable
class AppTypeStep {
  const AppTypeStep._(this.index, this.size, this.lineHeight);

  final int index;
  final double size;
  final double lineHeight;

  double get heightFactor => lineHeight / size;

  /// Resolves [index], shifted by the user's font-size setting and clamped to
  /// the end of the ladder.
  static AppTypeStep at(int index, {int fontScaleStep = 0}) {
    final i = (index + fontScaleStep).clamp(0, appTypeSequence.length - 1);
    final step = appTypeSequence[i];
    return AppTypeStep._(i, step.$1, step.$2);
  }

  static const int xs = 0;
  static const int sm = 1;
  static const int base = 2;
  static const int lg = 3;
  static const int xl = 4;
  static const int xxl = 5;
  static const int xxxl = 6;
  static const int xxxxl = 7;
}

/// Product roles. Each role names one step, one weight, and no colour: colours
/// come from [AppColors] at the call site so a role never bakes in a surface.
///
/// Weights are capped at semibold. `bold` is deliberately absent — a heavier
/// weight is a loudness fix for a hierarchy problem.
abstract final class AppText {
  /// Page title of a top-level destination (32/40 semibold, no letter spacing).
  static TextStyle pageTitle(Color color) =>
      _style(AppTypeStep.xxxl, FontWeight.w600, color);

  /// Grouped section header and row title (16/24).
  static TextStyle sectionHeader(Color color) =>
      _style(AppTypeStep.base, FontWeight.w600, color);

  /// Heading of a book-sized surface: the details page's title and its
  /// catalogue heading (24/32 semibold, no tracking).
  ///
  /// A role rather than a per-call-site copyWith: both places had reached for
  /// pageTitle and then overridden its size and weight by hand, which is how
  /// one screen ended up with a w800 heading under a scale that stops at
  /// semibold.
  static TextStyle bookTitle(Color color) =>
      _style(AppTypeStep.xxl, FontWeight.w600, color);

  static TextStyle rowTitle(Color color) =>
      _style(AppTypeStep.base, FontWeight.w400, color);

  /// Trailing value in a row (16/24 regular).
  static TextStyle rowValue(Color color) =>
      _style(AppTypeStep.base, FontWeight.w400, color);

  /// Description under a row title, and section footers (14/20).
  static TextStyle rowDescription(Color color) =>
      _style(AppTypeStep.sm, FontWeight.w400, color);

  /// Metadata and captions (13/18). The floor of the ladder.
  static TextStyle caption(Color color) =>
      _style(AppTypeStep.xs, FontWeight.w400, color);

  /// Button label (16/24 medium).
  static TextStyle buttonLabel(Color color) =>
      _style(AppTypeStep.base, FontWeight.w500, color);

  static TextStyle buttonLabelSmall(Color color) =>
      _style(AppTypeStep.sm, FontWeight.w500, color);

  /// Chip label (14/20 medium).
  static TextStyle chipLabel(Color color) =>
      _style(AppTypeStep.sm, FontWeight.w500, color);

  /// Content state title (16/24 semibold).
  static TextStyle stateTitle(Color color) =>
      _style(AppTypeStep.base, FontWeight.w600, color);

  /// Tab bar label (13/18 medium).
  static TextStyle tabLabel(Color color) =>
      _style(AppTypeStep.xs, FontWeight.w500, color);

  static TextStyle _style(int index, FontWeight weight, Color color) {
    final step = AppTypeStep.at(index);
    return TextStyle(
      color: color,
      fontSize: step.size,
      height: step.heightFactor,
      fontWeight: weight,
      letterSpacing: 0,
    );
  }
}
