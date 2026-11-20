import 'package:flutter/cupertino.dart';

import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import '../services/reader_background.dart';
import 'reader_control_panels.dart';
import 'reader_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_shape.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/app_controls.dart';
import '../theme/app_icons.dart';

/// Reader chrome overlay.
///
/// Visual language follows Fanqie (44dp top bar, 65dp progress row,
/// 目录|日夜|设置), but usability comes first:
/// - chrome sits on the **reading paper** colour
/// - top bar shows chapter context and **exits the reader**
/// - panels fill the band top-bar → bottom-chrome (no floating sheet gap)
/// - tap-outside only dismisses chrome; it never pops the route
/// - action throttle is short (200ms) so buttons do not feel dead
class ReaderMenu extends StatefulWidget {
  const ReaderMenu({
    required this.visible,
    required this.bookmarked,
    required this.onBack,
    required this.onToggleBookmark,
    required this.progress,
    required this.chapterCount,
    required this.currentChapterIndex,
    required this.chapterTitle,
    required this.canSeek,
    required this.onSeekProgress,
    required this.onSeekChapter,
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.pageTurnStyle,
    required this.brightness,
    required this.eyeCare,
    required this.keepScreenOn,
    required this.volumeKeys,
    required this.chapters,
    required this.chapterPageLabels,
    required this.bookmarks,
    required this.notes,
    this.progressSummary,
    this.onContinueReading,
    this.onJumpToChapter,
    this.paragraphs,
    this.pageLabelForParagraph,
    this.onJumpToSearchHit,
    required this.currentParagraph,
    required this.bookTitle,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    required this.onPageTurnStyle,
    required this.onBrightness,
    required this.onEyeCare,
    required this.onKeepScreenOn,
    required this.onVolumeKeys,
    required this.onShowFonts,
    this.onDismiss,
    this.onToggleUiTheme,
    this.onListen,
    this.listening = false,
    super.key,
  });

  final bool visible;
  final bool bookmarked;

  /// Leave the reader (Navigator.pop). Top-bar back / system back.
  final VoidCallback onBack;

  /// Start listening from the current page; null hides the action on
  /// platforms without speech support.
  final VoidCallback? onListen;

  /// Whether speech is currently playing (toggles the action's state).
  final bool listening;

  /// Collapse chrome only (tap-outside, toggle). Never exits.
  final VoidCallback? onDismiss;
  final VoidCallback onToggleBookmark;

  final double progress;
  final int chapterCount;
  final int currentChapterIndex;
  final String chapterTitle;
  final bool canSeek;
  final ValueChanged<double> onSeekProgress;
  final ValueChanged<int> onSeekChapter;

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final ReaderBackground background;
  final ReadingMode readingMode;
  final PageTurnStyle pageTurnStyle;
  final double brightness;
  final ReaderEyeCare eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;

  final List<MapEntry<int, String>> chapters;
  final Map<int, String> chapterPageLabels;
  final List<MapEntry<int, String>> bookmarks;
  final List<ReadingNote> notes;
  final ReaderProgressSummary? progressSummary;
  final VoidCallback? onContinueReading;
  final void Function(int paragraphIndex, {required bool restorePosition})?
  onJumpToChapter;

  /// Body text for 全文搜索 in the catalogue panel.
  final List<String>? paragraphs;

  /// Page label for a paragraph, shown on search results.
  final String Function(int paragraphIndex)? pageLabelForParagraph;

  /// Tapping a search result: jump to the paragraph, carrying the query so the
  /// reader can highlight what was searched for.
  final void Function(int paragraphIndex, String query)? onJumpToSearchHit;
  final int currentParagraph;
  final String bookTitle;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;

  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<ReaderBackground> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  final ValueChanged<PageTurnStyle> onPageTurnStyle;
  final ValueChanged<double> onBrightness;
  final ValueChanged<ReaderEyeCare> onEyeCare;
  final ValueChanged<bool> onKeepScreenOn;
  final ValueChanged<bool> onVolumeKeys;

  /// Preserved font functionality.
  final VoidCallback onShowFonts;
  final VoidCallback? onToggleUiTheme;

  @override
  State<ReaderMenu> createState() => _ReaderMenuState();
}

const Duration kReaderMenuAnimDuration = AppMotion.base;

/// Short debounce so double-taps do not queue, but buttons still feel live.
const Duration kReaderActionThrottle = AppGestureWindow.actionThrottle;

enum _AbovePanel { none, catalog, settings }

class _ReaderMenuState extends State<ReaderMenu>
    with SingleTickerProviderStateMixin {
  _AbovePanel _panel = _AbovePanel.none;

  /// 全文搜索 is open inside the catalogue panel. While it is, the sheet
  /// expands to the viewport so the result list is not a stripe above the
  /// seek bar (the soft keyboard is up on a phone).
  var _searchActive = false;
  double? _seekPreview;
  DateTime? _lastActionAt;
  late final AnimationController _chromeAnim = AnimationController(
    vsync: this,
    duration: kReaderMenuAnimDuration,
    // Closing is a dismissal, not a performance: it takes less time than
    // opening even before the curve makes it leave earlier.
    reverseDuration: AppMotion.dismiss,
  );

  @override
  void initState() {
    super.initState();
    _chromeAnim.addStatusListener(_onChromeAnimationStatus);
    if (widget.visible) _chromeAnim.value = 1;
  }

  void _onChromeAnimationStatus(AnimationStatus _) {
    // SlideTransition repaints itself, but the parent must rebuild at the end
    // of the reverse animation to remove the back/bookmark buttons entirely.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chromeAnim
      ..removeStatusListener(_onChromeAnimationStatus)
      ..dispose();
    super.dispose();
  }

  bool get _throttled {
    final now = DateTime.now();
    final last = _lastActionAt;
    if (last != null && now.difference(last) < kReaderActionThrottle) {
      return true;
    }
    _lastActionAt = now;
    return false;
  }

  @override
  void didUpdateWidget(covariant ReaderMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _panel = _AbovePanel.none;
      _chromeAnim.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _panel = _AbovePanel.none;
      _chromeAnim.reverse();
    }
  }

  void _togglePanel(_AbovePanel panel) {
    // No debounce on panel open/close — a blocked second tap felt like the
    // menu was broken. Only day/night theme flip stays lightly throttled.
    setState(() {
      _panel = _panel == panel ? _AbovePanel.none : panel;
      if (_panel != _AbovePanel.catalog) _searchActive = false;
    });
  }

  void _closePanel() {
    if (_panel != _AbovePanel.none) {
      setState(() {
        _panel = _AbovePanel.none;
        _searchActive = false;
      });
    }
  }

  /// Tap-outside: close panel, then chrome. Never pops the route.
  void _handleDismiss() {
    if (_panel != _AbovePanel.none) {
      _closePanel();
      return;
    }
    (widget.onDismiss ?? widget.onBack)();
  }

  /// Top-bar back: panel first, then leave the reader. No throttle — exit
  /// must always respond.
  void _handleTopBarBack() {
    if (_panel != _AbovePanel.none) {
      _closePanel();
      return;
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _chromeAnim.isDismissed) {
      return const SizedBox.shrink();
    }
    // Chrome sits on the reading paper so menu and page feel like one surface.
    final themeBg = Color(widget.background.chromeColorValue);
    final chromeInk = VellumTheme.readerChromeInk(themeBg);
    final media = MediaQuery.of(context);
    final topSafe = media.padding.top;
    final bottomSafe = media.padding.bottom;
    // One curve pair for both directions: opening settles, closing leaves
    // immediately. Reusing the decelerating curve on the way out made every
    // dismissal feel like waiting for the bars to finish leaving.
    final chromeCurve = motionPair(_chromeAnim);
    final topSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(chromeCurve);
    final bottomSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(chromeCurve);
    final chromeVisible = widget.visible || _chromeAnim.isAnimating;

    // Bottom chrome always shows progress + actions so seek stays usable
    // while a catalog/settings sheet is open. It is a floating stack now:
    // progress pill (78) + gap (8) + capsule (54) + bottom air (12).
    final bottomChrome =
        68.0 +
        _ReaderBottomDock.progressGap +
        _ReaderBottomDock.capsuleHeight +
        12 +
        bottomSafe;
    final bandTop = ReaderTopBar.height + topSafe;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !widget.visible,
        // The sheet is sized from the box this overlay is actually given, not
        // from `MediaQuery.size`: when the soft keyboard resizes the window (or
        // the scaffold above us does), the box is smaller than the media size,
        // and computing from the media size put the sheet past its own bottom —
        // the overflow block that appeared while typing.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxHeight;
            // CupertinoPageScaffold consumes viewInsets (zeros the bottom) and
            // shrinks its body by the keyboard, so this box is short while
            // `MediaQuery.size` still reports the full screen. A short box
            // here means the keyboard is up — or search is open, which is the
            // same layout problem: the reader wants the sheet, not the seek bar.
            final mediaHeight = MediaQuery.sizeOf(context).height;
            final squeezed = mediaHeight - available > 120;
            final expandSheet =
                _panel != _AbovePanel.none && (_searchActive || squeezed);
            final compact = expandSheet || available < 420;
            final chrome = expandSheet
                ? 0.0
                : compact
                ? (available * .22).clamp(0.0, 90.0)
                : bottomChrome;
            final band = expandSheet
                ? 0.0
                : compact
                ? available * .16
                : bandTop;
            final room = (available - band - chrome).clamp(
              0.0,
              double.infinity,
            );
            // The catalogue/settings sheet is slightly taller than half the
            // reading area so chapter rows remain useful without hiding the
            // bottom reading controls. While typing it fills the space above
            // the keyboard or the result list collapses to a stripe.
            final desired = expandSheet
                ? room
                : (available * .58).clamp(0.0, double.infinity);
            final panelHeight = desired
                .clamp(
                  room < ReaderDirectoryPanel.minPanelHeight
                      ? room
                      : ReaderDirectoryPanel.minPanelHeight,
                  room,
                )
                .clamp(0.0, room);
            final panelTop = available - chrome - panelHeight;
            // Chrome paints over the sheet in the stack below; when the panel
            // owns the full viewport it would sit under the bars, so hide them.
            final showChrome = !expandSheet;

            return Stack(
              children: [
                // Middle-band dismiss target (page stays visible around chrome).
                if (widget.visible)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: band,
                    bottom: chrome,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleDismiss,
                      child: const ColoredBox(color: Color(0x00000000)),
                    ),
                  ),

                // Taller sheet above the action bar (seek row stays under it).
                //
                // The panel is the largest surface in the reader, and it used to
                // appear and vanish between two frames. It slides up into place
                // instead — position and opacity only. Animating its height (a
                // SizeTransition, or an AnimatedSize driven by this value) would
                // re-lay-out the whole band every frame, which is the same cost
                // the top bar just lost.
                // Mounted even when the panel is closed: the switcher needs to
                // stay in the tree to animate the outgoing surface. An empty
                // child paints nothing and takes no taps.
                Positioned(
                  left: 0,
                  right: 0,
                  top: panelTop,
                  bottom: chrome,
                  child: AnimatedSwitcher(
                    // Reduced motion lands the panel immediately: a sheet that
                    // is already open should not take a moment to arrive, and
                    // the platform asked for no movement, not for a shorter one.
                    duration: motionDuration(context, AppMotion.base),
                    reverseDuration: motionDuration(context, AppMotion.dismiss),
                    switchInCurve: AppMotion.settle,
                    switchOutCurve: AppMotion.dismissCurve,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _panel == _AbovePanel.none
                        ? const SizedBox.expand(
                            key: ValueKey('reader-panel-none'),
                          )
                        : DecoratedBox(
                            key: ValueKey(_panel),
                            decoration: BoxDecoration(
                              color: themeBg,
                              border: Border(
                                top: BorderSide(
                                  color: chromeInk.withValues(alpha: .08),
                                  width: 0.5,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: context.c.constantBlack.withValues(
                                    alpha: .10,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Grabber: tap or flick down closes the sheet only.
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _closePanel,
                                  onVerticalDragEnd: (details) {
                                    if ((details.primaryVelocity ?? 0) > 280) {
                                      _closePanel();
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: chromeInk.withValues(
                                            alpha: .22,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.hairlineXs,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: _panel == _AbovePanel.catalog
                                      ? _catalogPanel(context, themeBg)
                                      : _settingsPanel(context, themeBg),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),

                if (chromeVisible && showChrome)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    // Slides only. The old ClipRect + SizeTransition animated
                    // the bar's *height*, so every frame re-laid-out the whole
                    // top of the page; the bottom bar was already using a pure
                    // slide, and the two bars did not move alike.
                    child: SlideTransition(
                      position: topSlide,
                      child: ReaderTopBar(
                        bookmarked: widget.bookmarked,
                        title: widget.chapterTitle.isNotEmpty
                            ? widget.chapterTitle
                            : widget.bookTitle,
                        surface: themeBg,
                        onBack: _handleTopBarBack,
                        onToggleBookmark: widget.onToggleBookmark,
                      ),
                    ),
                  ),

                if (chromeVisible && showChrome)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SlideTransition(
                      position: bottomSlide,
                      child: _ReaderBottomDock(
                        surface: themeBg,
                        ink: chromeInk,
                        progress: _progressRow(context, themeBg),
                        actions: _actionRow(context, themeBg),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Progress row: labels are tappable chapter steps + seek bar.
  Widget _progressRow(BuildContext context, Color themeBg) {
    final ink = VellumTheme.readerChromeInk(themeBg);
    final accent = VellumTheme.readerAccentFor(themeBg);
    final hasChapters = widget.chapterCount > 1;
    final chapterMax = (widget.chapterCount - 1).clamp(0, 1 << 30);
    final chapterValue = widget.currentChapterIndex.clamp(0, chapterMax);
    final atStart = hasChapters ? chapterValue <= 0 : widget.progress <= 0.001;
    final atEnd = hasChapters
        ? chapterValue >= chapterMax
        : widget.progress >= 0.999;
    final sliderValue = (_seekPreview ?? widget.progress).clamp(0.0, 1.0);

    void seek(double value) {
      if (!widget.canSeek) return;
      widget.onSeekProgress(value);
    }

    Widget stepLabel(
      String text, {
      required bool enabled,
      VoidCallback? onTap,
    }) {
      final color = ink.withValues(alpha: enabled ? .9 : .32);
      return AppTextButton(
        label: text,
        color: color,
        pressedColor: ink.withValues(alpha: .06),
        onPressed: enabled ? onTap : null,
      );
    }

    final summary = widget.progressSummary;
    final chapterText = summary == null || summary.currentChapterTitle.isEmpty
        ? widget.chapterTitle
        : summary.currentChapterTitle;
    final bookPercent = ((summary?.bookProgress ?? widget.progress) * 100)
        .round()
        .clamp(0, 100);
    final chapterPercent = ((summary?.chapterProgress ?? 0) * 100)
        .round()
        .clamp(0, 100);
    return SizedBox(
      // 68, not 78: this now floats above the action capsule instead of being
      // welded into a bar, so its own padding was doing the spacing that the
      // gap between the two surfaces already does.
      height: 68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    chapterText.isEmpty ? '阅读进度' : chapterText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.withValues(alpha: .86),
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '本章 $chapterPercent% · 全书 $bookPercent%',
                  style: TextStyle(
                    color: ink.withValues(alpha: .55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  stepLabel(
                    '上一章',
                    enabled: !atStart,
                    onTap: () {
                      if (!widget.canSeek) return;
                      if (hasChapters) {
                        widget.onSeekChapter(
                          (chapterValue - 1).clamp(0, chapterMax),
                        );
                      } else {
                        widget.onSeekProgress(
                          (widget.progress - 0.05).clamp(0, 1),
                        );
                      }
                    },
                  ),
                  Expanded(
                    child: CupertinoSlider(
                      value: sliderValue,
                      activeColor: accent,
                      thumbColor: accent,
                      onChanged: widget.canSeek
                          ? (value) => setState(() => _seekPreview = value)
                          : null,
                      onChangeEnd: widget.canSeek
                          ? (value) {
                              seek(value);
                              if (mounted) setState(() => _seekPreview = null);
                            }
                          : null,
                    ),
                  ),
                  stepLabel(
                    '下一章',
                    enabled: !atEnd,
                    onTap: () {
                      if (!widget.canSeek) return;
                      if (hasChapters) {
                        widget.onSeekChapter(
                          (chapterValue + 1).clamp(0, chapterMax),
                        );
                      } else {
                        widget.onSeekProgress(
                          (widget.progress + 0.05).clamp(0, 1),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context, Color themeBg) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            _actionItem(
              context,
              themeBg,
              icon: AppIcons.listBullet,
              label: '目录',
              selected: _panel == _AbovePanel.catalog,
              onTap: () => _togglePanel(_AbovePanel.catalog),
            ),
            _actionItem(
              context,
              themeBg,
              icon: isDark ? AppIcons.sunMax : AppIcons.moon,
              label: isDark ? '日间' : '夜间',
              selected: false,
              onTap: () {
                if (_throttled) return;
                widget.onToggleUiTheme?.call();
              },
            ),
            if (widget.onListen != null)
              _actionItem(
                context,
                themeBg,
                icon: widget.listening ? AppIcons.speaker2 : AppIcons.speaker1,
                label: widget.listening ? '听书中' : '听书',
                selected: widget.listening,
                onTap: widget.onListen!,
              ),
            _actionItem(
              context,
              themeBg,
              icon: AppIcons.gear,
              label: '设置',
              selected: _panel == _AbovePanel.settings,
              onTap: () => _togglePanel(_AbovePanel.settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionItem(
    BuildContext context,
    Color themeBg, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = VellumTheme.readerAccentFor(themeBg);
    final ink = VellumTheme.readerChromeInk(themeBg);
    // Same press feedback as every other tap target in the app: the cell fills,
    // the icon and label do not fade. These four are the most-tapped controls in
    // the reader and were the only place still using an opacity dip.
    return Expanded(
      child: AppPressable(
        onTap: onTap,
        pressedColor: ink.withValues(alpha: .06),
        semanticLabel: label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? accent : ink.withValues(alpha: .92),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? accent : ink.withValues(alpha: .92),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogPanel(BuildContext context, Color themeBg) {
    return ColoredBox(
      color: themeBg,
      child: ReaderDirectoryPanel(
        bookTitle: widget.bookTitle,
        surface: themeBg,
        chapters: widget.chapters,
        bookmarks: widget.bookmarks,
        notes: widget.notes,
        paragraphs: widget.paragraphs,
        pageLabelForParagraph: widget.pageLabelForParagraph,
        onJumpToSearchHit: widget.onJumpToSearchHit,
        chapterPageLabels: widget.chapterPageLabels,
        currentParagraph: widget.currentParagraph,
        readingMode: widget.readingMode,
        progressSummary: widget.progressSummary,
        onContinueReading: widget.onContinueReading,
        onJumpToChapter: widget.onJumpToChapter,
        onJumpToParagraph: (paragraph) {
          _closePanel();
          widget.onJumpToParagraph(paragraph);
        },
        onRemoveBookmark: widget.onRemoveBookmark,
        onRemoveNote: widget.onRemoveNote,
        onClose: _closePanel,
        onSearchingChanged: (searching) {
          if (!mounted || _searchActive == searching) return;
          setState(() => _searchActive = searching);
        },
      ),
    );
  }

  Widget _settingsPanel(BuildContext context, Color themeBg) {
    return ColoredBox(
      color: themeBg,
      child: ReaderSettingsPanel(
        surface: themeBg,
        fontSize: widget.fontSize,
        readerFontWeight: widget.readerFontWeight,
        lineSpacing: widget.lineSpacing,
        background: widget.background,
        readingMode: widget.readingMode,
        pageTurnStyle: widget.pageTurnStyle,
        brightness: widget.brightness,
        eyeCare: widget.eyeCare,
        keepScreenOn: widget.keepScreenOn,
        volumeKeys: widget.volumeKeys,
        onFontSize: widget.onFontSize,
        onReaderFontWeight: widget.onReaderFontWeight,
        onLineSpacing: widget.onLineSpacing,
        onBackground: widget.onBackground,
        onReadingMode: widget.onReadingMode,
        onPageTurnStyle: widget.onPageTurnStyle,
        onBrightness: widget.onBrightness,
        onEyeCare: widget.onEyeCare,
        onKeepScreenOn: widget.onKeepScreenOn,
        onVolumeKeys: widget.onVolumeKeys,
        onShowFonts: widget.onShowFonts,
        onClose: _closePanel,
      ),
    );
  }
}

/// The reader's bottom chrome, as a floating capsule rather than a full-width bar.
///
/// A bar welded to the bottom edge occupies a permanent strip of the page; a
/// capsule hovers over the text and lets the page run underneath it, which is
/// what makes the reading surface feel like the whole screen. The progress row
/// sits directly on top of the capsule (also floating) so seeking never costs
/// another band of height.
///
/// Geometry follows the reading-dock convention: 54 tall capsule, fully rounded,
/// 12 above the safe area, a hairline instead of a shadow, and an edge shade
/// where it meets the page so the capsule reads as glass over paper rather than
/// as a pasted-on rectangle.
class _ReaderBottomDock extends StatelessWidget {
  const _ReaderBottomDock({
    required this.surface,
    required this.ink,
    required this.progress,
    required this.actions,
  });

  final Color surface;
  final Color ink;
  final Widget progress;
  final Widget actions;

  /// Capsule height. Label + icon need 44; the rest is breathing room.
  static const double capsuleHeight = 54;

  /// Gap between the progress pill and the capsule.
  static const double progressGap = 8;

  /// Side inset of the floating stack from the window edge.
  static const double sideInset = 12;

  /// Largest width the capsule grows to; a reading dock is a thumb target.
  static const double maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(capsuleHeight / 2);
    final hairline = Border.all(
      color: ink.withValues(alpha: .10),
      width: 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: sideInset),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress floats above the capsule, sharing its width.
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(18),
                      border: hairline,
                    ),
                    child: progress,
                  ),
                ),
                const SizedBox(height: progressGap),
                ClipRRect(
                  borderRadius: radius,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: radius,
                      border: hairline,
                    ),
                    child: SizedBox(height: capsuleHeight, child: actions),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
