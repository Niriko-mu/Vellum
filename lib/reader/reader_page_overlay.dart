import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../theme/vellum_theme.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Compact reading-time indicator shown while reader chrome is hidden.
class ReaderReadingTimePill extends StatelessWidget {
  const ReaderReadingTimePill({
    required this.sessionSeconds,
    required this.todaySeconds,
    required this.surface,
    super.key,
  });

  final ValueListenable<int> sessionSeconds;
  final ValueListenable<int> todaySeconds;
  final Color surface;

  /// Reading time is ambient information, so it is rendered in minutes.
  ///
  /// A seconds-precision label changes every single second for the first
  /// minute, which makes the reader repaint once a second forever — measured
  /// at 6 needless frames per 5 idle seconds. Minutes are what a reader
  /// actually reads.
  static String compactDuration(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;
    if (hours > 0) return '${hours}h${minutes.toString().padLeft(2, '0')}';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.readerChromeInk(surface);
    final accent = context.c.primary;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, right: 18),
          child: ValueListenableBuilder<int>(
            valueListenable: sessionSeconds,
            builder: (context, session, _) => ValueListenableBuilder<int>(
              valueListenable: todaySeconds,
              builder: (context, today, _) => DecoratedBox(
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: ink.withValues(alpha: .12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.timer, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        '本次 ${compactDuration(session)} · 今日 ${compactDuration(today)}',
                        style: TextStyle(
                          color: ink.withValues(alpha: .62),
                          fontSize: 13,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual cover-turn layer. Page ownership and animation lifecycle stay in the
/// reader state; this widget only composes the two cached page surfaces.
class ReaderCoverTurnOverlay extends StatelessWidget {
  const ReaderCoverTurnOverlay({
    required this.fromPage,
    required this.toPage,
    required this.animation,
    required this.dragTurn,
    required this.dragCommitted,
    required this.pageSurface,
    super.key,
  });

  final int fromPage;
  final int toPage;
  final Animation<double> animation;
  final bool dragTurn;
  final bool dragCommitted;
  final Widget Function(BuildContext context, int page) pageSurface;

  @override
  Widget build(BuildContext context) {
    final isNext = toPage > fromPage;
    final movingPage = isNext ? fromPage : toPage;
    final staticPage = isNext ? toPage : fromPage;
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: pageSurface(context, staticPage)),
                AnimatedBuilder(
                  animation: animation,
                  child: RepaintBoundary(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(alpha: .22),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(10, 0),
                          ),
                        ],
                      ),
                      child: pageSurface(context, movingPage),
                    ),
                  ),
                  builder: (context, child) {
                    // Raw controller value: the curve is applied once, by the
                    // animateTo that drives this controller. Transforming here
                    // as well double-eased the tap path and forced the drag
                    // path to bypass the curve entirely.
                    final progress = animation.value;
                    final dx = isNext ? -progress : -1 + progress;
                    return FractionalTranslation(
                      translation: Offset(dx, 0),
                      child: child,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}