import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../theme/vellum_theme.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'reader_page_curl.dart';

/// Compact reading-time indicator shown while reader chrome is hidden.
class ReaderReadingTimePill extends StatelessWidget {
  const ReaderReadingTimePill({
    required this.sessionSeconds,
    required this.todaySeconds,
    required this.surface,
    this.bookmarkTabVisible = false,
    super.key,
  });

  final ValueListenable<int> sessionSeconds;
  final ValueListenable<int> todaySeconds;
  final Color surface;

  /// Whether the pinned bookmark tab is on the paper right now: it shares this
  /// corner, so the pill has to make room for it.
  final bool bookmarkTabVisible;

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
          // The bookmark tab lives in the same corner at the same moment as
          // this pill. It is 28 wide and flush to the edge, so the pill steps
          // in to clear it instead of being painted over.
          padding: EdgeInsets.only(top: 4, right: bookmarkTabVisible ? 44 : 18),
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
    this.curl = false,
    this.backgroundColor = const Color(0xFFFFFFFF),
    super.key,
  });

  /// Paint the turn as a simulated curl instead of a sliding sheet. Both read
  /// the same controller, so the drag path, the commit threshold and the settle
  /// curve are shared; only the painting differs.
  final bool curl;

  /// The surface behind the curl's mirror; the lifted corner must not show
  /// whatever is behind the reader through it.
  final Color backgroundColor;

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
    if (curl) {
      return Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => ReaderPageCurl(
              outgoing: RepaintBoundary(
                child: pageSurface(context, movingPage),
              ),
              incoming: RepaintBoundary(
                child: pageSurface(context, staticPage),
              ),
              progress: animation.value,
              forward: isNext,
              backgroundColor: backgroundColor,
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Keyed by page so a turn reuses the same subtree; the pages
                // are already rendered below by the PageView, and rebuilding
                // either of them per frame is what made a turn expensive.
                RepaintBoundary(
                  key: ValueKey<int>(staticPage),
                  child: pageSurface(context, staticPage),
                ),
                AnimatedBuilder(
                  animation: animation,
                  // The moving page is built once, outside the builder: only its
                  // translation changes while the turn runs.
                  child: RepaintBoundary(
                    key: ValueKey<int>(movingPage),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: context.c.constantBlack.withValues(
                              alpha: .22,
                            ),
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
