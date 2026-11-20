import 'package:flutter/widgets.dart';

import '../theme/app_shape.dart';
import '../theme/app_type.dart';

/// Cell width for a grid of [columns] covers inside [availableWidth].
double shelfCellWidth(
  double availableWidth, {
  required int columns,
  required double horizontalPadding,
  required double spacing,
}) {
  final raw =
      (availableWidth - horizontalPadding - spacing * (columns - 1)) / columns;
  return raw < 1 ? 1 : raw;
}

/// The aspect ratio that keeps a cover at [coverRatio] while the two caption
/// lines below it still fit at the *current* text scale.
///
/// A hardcoded ratio is the usual shortcut and the usual bug: it looks right at
/// the default font size and clips the title for anyone who has enlarged text.
/// Deriving the height from the measured cover plus the scaled caption keeps the
/// cell honest at every size.
double shelfCellAspectRatio(
  BuildContext context, {
  required double availableWidth,
  required int columns,
  required double horizontalPadding,
  required double coverRatio,
  double spacing = 16,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final cellWidth = shelfCellWidth(
    availableWidth,
    columns: columns,
    horizontalPadding: horizontalPadding,
    spacing: spacing,
  );
  final titleLine = scaler.scale(AppTypeStep.at(AppTypeStep.sm).size) * 1.3;
  final metaLine = scaler.scale(AppTypeStep.at(AppTypeStep.xs).size) * 1.4;
  final cellHeight =
      cellWidth * coverRatio +
      AppSpace.x2 +
      titleLine * 2 +
      AppSpace.x1 +
      metaLine;
  return cellWidth / cellHeight;
}
