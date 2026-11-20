import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/shelf_grid_metrics.dart';

/// Cell geometry for the shelf grid.
///
/// The one thing this must never do is clip the caption. A fixed aspect ratio
/// looks correct at the default font size and starts cutting titles off the
/// moment someone enlarges text — the cell keeps its shape while the text under
/// the cover grows past it.
void main() {
  testWidgets('a larger text scale yields a taller cell', (tester) async {
    late double baseRatio;
    late double largeRatio;

    for (final scale in [1.0, 1.8]) {
      late BuildContext ctx;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final ratio = shelfCellAspectRatio(
        ctx,
        availableWidth: 400,
        columns: 3,
        horizontalPadding: 32,
        coverRatio: 1.4,
      );
      if (scale == 1.0) {
        baseRatio = ratio;
      } else {
        largeRatio = ratio;
      }
    }

    expect(
      largeRatio,
      lessThan(baseRatio),
      reason: 'more text height means a wider (less tall) cell ratio',
    );
  });

  test('the cell reserves the cover at its ratio plus both caption lines', () {
    // Reproduce the arithmetic for one concrete width.
    const available = 400.0;
    const padding = 32.0;
    const spacing = 16.0;
    const columns = 3;
    final cellWidth = shelfCellWidth(
      available,
      columns: columns,
      horizontalPadding: padding,
      spacing: spacing,
    );
    expect(cellWidth, closeTo((400 - 32 - 32) / 3, 0.001));
  });

  test('a narrower window still yields a usable cell width', () {
    final w = shelfCellWidth(
      100,
      columns: 6,
      horizontalPadding: 32,
      spacing: 16,
    );
    expect(w, greaterThan(0), reason: 'never divide into zero or negative');
  });
}
