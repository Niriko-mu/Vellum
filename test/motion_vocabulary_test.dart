import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The motion vocabulary is only real if nothing bypasses it.
///
/// A design system's duration scale is easy to establish and easy to erode:
/// one screen writes 500 ms because that is what felt right that afternoon, and
/// a year later the app has eleven speeds. These checks fail loudly when a new
/// library file starts inventing its own timing.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no library file besides app_motion.dart invents a duration literal', () {
    final offenders = <String>[];
    for (final file in libFiles) {
      final path = file.path.replaceAll(RegExp(r'[\\/]'), '/');
      if (path.endsWith('theme/app_motion.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'Duration\(milliseconds: \d+\)',
      ).allMatches(source)) {
        // Gesture windows and business debounces legitimately live near their
        // own logic; the rule is about *animations*.
        offenders.add('$path -> ${match.group(0)}');
      }
    }
    // Every remaining hit must be justified: a timer, a debounce, a hold window
    // or a scroll-into-view, never something that animates a surface.
    const allowed = <String>[
      // A delay before an update check, not an animation.
      'app.dart',
      'pages/book_details_page.dart',
      'pages/writing_editor_page.dart',
      'reader/epub_original_reader_page.dart',
      'reader/reader_directory_panel_state.dart',
      'reader/reader_gestures.dart',
      'reader/reader_page_state.dart',
      'reader/reader_page_state_pagination.dart',
      'reader/reader_page_state_surface_rendering.dart',
      'services/book_import_service.dart',
      'widgets/conversion_progress.dart',
      'widgets/font_preview.dart',
    ];
    final unexpected = [
      for (final entry in offenders)
        if (!allowed.any((a) => entry.contains(a))) entry,
    ];
    expect(
      unexpected,
      isEmpty,
      reason: 'use AppMotion / motionDuration instead of a private duration',
    );
  });
}
