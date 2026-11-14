import 'package:flutter/cupertino.dart';

import '../theme/app_motion.dart';
import '../theme/vellum_theme.dart';
import '../theme/app_shape.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

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
              AppPressable(
                onTap: onBack,
                semanticLabel: '返回',
                child: SizedBox(
                  width: 48,
                  height: 44,
                  child: Icon(AppIcons.chevronBack, size: 26, color: ink),
                ),
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
                      color: VellumTheme.readerSecondaryInk(bg),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 18 / 13,
                    ),
                  ),
                ),
              ),
              AppPressable(
                onTap: onToggleBookmark,
                semanticLabel: bookmarked ? '取消书签' : '添加书签',
                child: SizedBox(
                  width: 48,
                  height: 44,
                  child: Icon(
                    bookmarked
                        ? AppIcons.bookmarkFill
                        : AppIcons.bookmark,
                    size: 22,
                    color: bookmarked
                        ? context.c.primary
                        : ink.withValues(alpha: .85),
                  ),
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
    this.batteryLevel,
    this.surface,
    super.key,
  });

  final String pageLabel;
  final String batteryLabel;
  final int? batteryLevel;
  final Color? surface;

  /// Uses four readable visual steps as the system status bar while keeping
  /// the tiny reader footer legible on paper backgrounds.
  static IconData batteryIconFor(int level) {
    final value = level.clamp(0, 100);
    if (value <= 5) return AppIcons.battery0;
    if (value <= 50) return AppIcons.battery25Percent;
    if (value <= 75) return AppIcons.battery75Percent;
    return AppIcons.batteryFull;
  }

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
                    color: VellumTheme.readerTertiaryInk(bg),
                    fontSize: 13,
                    height: 18 / 13,
                  ),
                ),
              const Spacer(),
              if (batteryLabel.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      batteryLevel == null
                          ? AppIcons.battery75Percent
                          : batteryIconFor(batteryLevel!),
                      size: 14,
                      color: batteryLevel != null && batteryLevel! <= 15
                          ? context.c.destructive
                          : ink.withValues(alpha: .55),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      batteryLabel,
                      style: TextStyle(
                        color: VellumTheme.readerTertiaryInk(bg),
                        fontSize: 13,
                        height: 18 / 13,
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
              // Was alpha .38 — 2.64:1 on the white paper, below both the text
              // and the graphics floor. Tertiary keeps it quiet but readable.
              color: VellumTheme.readerTertiaryInk(bg),
              fontSize: 13,
              height: 18 / 13,
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
    final accent = context.c.primary;
    final normalizedProgress = progress.clamp(0.0, 1.2);
    final easedProgress = AppMotion.settle.transform(
      (normalizedProgress / 1.2).clamp(0.0, 1.0),
    );
    final ribbonLength = pinned ? 72.0 : 22 + easedProgress * 68;
    final idleColor = alreadyBookmarked
        ? accent.withValues(alpha: .55)
        : ink.withValues(alpha: .45);
    final ribbonColor = pinned || armed
        ? accent
        : Color.lerp(idleColor, accent.withValues(alpha: .82), easedProgress)!;
    final visibleLabelOpacity = showLabel
        ? (0.18 + easedProgress * .82).clamp(0.0, 1.0)
        : 0.0;
    final semanticsLabel = pinned ? '当前阅读位置已添加书签' : label;
    return Semantics(
      container: true,
      liveRegion: showLabel,
      label: semanticsLabel,
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: motionDuration(context, AppMotion.fast),
                  curve: AppMotion.settle,
                  width: pinned ? 28 : 22 + easedProgress * 3,
                  height: ribbonLength,
                  child: ClipPath(
                    clipper: const _BookmarkNotchClipper(),
                    child: ColoredBox(
                      color: ribbonColor,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AnimatedSwitcher(
                            duration: motionDuration(context, AppMotion.fast),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(opacity: animation, child: child),
                            child: Icon(
                              armed || alreadyBookmarked || pinned
                                  ? AppIcons.bookmarkFill
                                  : AppIcons.bookmark,
                              key: ValueKey(
                                armed || alreadyBookmarked || pinned,
                              ),
                              size: 14,
                              color: context.c.constantWhite,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 6),
                  AnimatedOpacity(
                    duration: motionDuration(context, AppMotion.fast),
                    curve: AppMotion.settle,
                    opacity: visibleLabelOpacity,
                    child: AnimatedSlide(
                      duration: motionDuration(context, AppMotion.fast),
                      curve: AppMotion.settle,
                      offset: Offset(0, (1 - easedProgress) * -.18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: bg.withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(AppRadius.grouped),
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
                            fontSize: 13,
                            height: 18 / 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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