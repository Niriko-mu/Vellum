import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';

/// Fanqie top bar (alg.xml): **44dp**, back @16dp. Chapter/book label sits
/// **left-aligned** next to the back chevron (not centred).
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    required this.bookmarked,
    this.onBack,
    this.onToggleBookmark,
    this.title = '',
    this.surface,
    super.key,
  });

  final bool bookmarked;
  final VoidCallback? onBack;
  final VoidCallback? onToggleBookmark;
  final String title;
  final Color? surface;

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    return ColoredBox(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.only(left: 16, right: 4),
                minimumSize: const Size(48, 44),
                onPressed: onBack,
                child: Icon(CupertinoIcons.chevron_back, size: 26, color: ink),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: ink.withValues(alpha: .72),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(48, 44),
                onPressed: onToggleBookmark,
                child: Icon(
                  bookmarked
                      ? CupertinoIcons.bookmark_fill
                      : CupertinoIcons.bookmark,
                  size: 22,
                  color: bookmarked
                      ? VellumTheme.readerAccentOf(context)
                      : ink.withValues(alpha: .85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fanqie BottomIndicator: **page number + battery only**.
class ReaderStatusBar extends StatelessWidget {
  const ReaderStatusBar({
    required this.pageLabel,
    required this.batteryLabel,
    this.surface,
    super.key,
  });

  final String pageLabel;
  final String batteryLabel;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    if (pageLabel.isEmpty && batteryLabel.isEmpty) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            children: [
              // Page number hard-left, battery hard-right (Fanqie bottom strip).
              if (pageLabel.isNotEmpty)
                Text(
                  pageLabel,
                  style: TextStyle(
                    color: ink.withValues(alpha: .55),
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              const Spacer(),
              if (batteryLabel.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.battery_75_percent,
                      size: 14,
                      color: ink.withValues(alpha: .55),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      batteryLabel,
                      style: TextStyle(
                        color: ink.withValues(alpha: .55),
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-left running head while chrome is hidden (Fanqie page header).
class ReaderRunningHead extends StatelessWidget {
  const ReaderRunningHead({
    required this.chapterLabel,
    this.surface,
    super.key,
  });

  final String chapterLabel;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    if (chapterLabel.isEmpty) return const SizedBox.shrink();
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 20, top: 4),
          child: Text(
            chapterLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink.withValues(alpha: .38),
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bookmark pull ribbon (Fanqie BookMarkView notch ~4dp).
class BookmarkRibbon extends StatelessWidget {
  const BookmarkRibbon({
    required this.progress,
    required this.armed,
    required this.alreadyBookmarked,
    required this.label,
    this.pinned = false,
    this.showLabel = true,
    this.surface,
    super.key,
  });

  final double progress;
  final bool armed;
  final bool alreadyBookmarked;
  final String label;

  /// A saved bookmark remains as a physical tab on the right page edge.
  final bool pinned;

  /// Pull feedback has a caption; the persistent tab intentionally does not.
  final bool showLabel;

  /// Active reading paper. The caption pill floats over the page, so its
  /// surface, hairline and ink must follow that paper in light and dark.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final accent = VellumTheme.readerAccentOf(context);
    final ribbonLength = (pinned ? 72.0 : 28 + progress * 52).clamp(28.0, 90.0);
    final ribbonColor = pinned
        ? accent
        : (armed
              ? accent
              : (alreadyBookmarked
                    ? accent.withValues(alpha: .55)
                    : ink.withValues(alpha: .45)));
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipPath(
                clipper: const _BookmarkNotchClipper(),
                child: Container(
                  width: pinned ? 28 : 22,
                  height: ribbonLength,
                  color: ribbonColor,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Icon(
                        armed || alreadyBookmarked || pinned
                            ? CupertinoIcons.bookmark_fill
                            : CupertinoIcons.bookmark,
                        size: 14,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(height: 6),
                Opacity(
                  opacity: progress.clamp(0.25, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: bg.withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: armed
                            ? accent.withValues(alpha: .55)
                            : ink.withValues(alpha: .18),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: armed ? accent : ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Creates the V-shaped cut at the bottom of a paper bookmark tab.
class _BookmarkNotchClipper extends CustomClipper<Path> {
  const _BookmarkNotchClipper();

  @override
  Path getClip(Size size) {
    final notchDepth = (size.height * .18).clamp(5.0, 11.0);
    return Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - notchDepth)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _BookmarkNotchClipper oldClipper) => false;
}
