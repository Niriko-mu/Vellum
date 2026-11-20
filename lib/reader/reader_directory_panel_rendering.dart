import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show AlwaysStoppedAnimation, LinearProgressIndicator;
import '../theme/vellum_theme.dart';
import 'reader_directory_panel.dart';
import 'reader_directory_panel_state.dart';
import 'reader_directory_panel_search_view.dart';
import '../theme/app_shape.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_type.dart';

/// Fanqie caloglayout structure: book name → tabs → divider → list.
/// Parent supplies full band height; panel fills it.
Widget renderReaderDirectoryPanel(
  ReaderDirectoryPanelState state,
  BuildContext context,
) => state.renderDirectoryPanel(context);

extension ReaderDirectoryPanelRendering on ReaderDirectoryPanelState {
  Widget renderDirectoryPanel(BuildContext context) {
    final surface = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(surface);
    final muted = ink.withValues(alpha: .55);
    final accent = VellumTheme.readerAccentFor(surface);
    final chapterEntries = entries;
    final emptyMessage = switch (tab) {
      0 => '这本书暂未识别出章节标题。',
      1 => '下拉阅读页面即可添加书签。',
      _ => '选中正文后可以划线或写笔记。',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // The sheet is a fixed slot between the reader's top bar and the bottom
        // chrome, and the soft keyboard shrinks the viewport without shrinking
        // that slot. Below [headerHeight] the book-name line and the query field
        // no longer fit, so the panel drops to a compact header instead of
        // painting the black/yellow overflow stripes.
        //
        // Searching always uses the slim search header: tabs and the book name
        // do not help while typing, and a full header plus the summary bar left
        // the result list a stripe once the keyboard took the rest of the
        // screen. One layout for the whole search session also avoids swapping
        // headers mid-keyboard-animation (which drops the input connection).
        if (searching) {
          return searchLayout(context, ink: ink, muted: muted, accent: accent);
        }
        if (constraints.maxHeight < ReaderDirectoryPanel.headerHeight) {
          return compactLayout(
            context,
            entries: entries,
            emptyMessage: emptyMessage,
            ink: ink,
            muted: muted,
            accent: accent,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(context, ink: ink, muted: muted, accent: accent),
            Expanded(
              child: body(
                context,
                entries: chapterEntries,
                emptyMessage: emptyMessage,
                ink: ink,
                muted: muted,
                accent: accent,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Search-only sheet: query field + 取消, then the results.
  ///
  /// Dropped book name and tabs so a keyboard-squeezed viewport still shows
  /// a usable list instead of three rows of chrome over a stripe of results.
  Widget searchLayout(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: searchField(
                  context,
                  ink: ink,
                  muted: muted,
                  accent: accent,
                ),
              ),
              AppTextButton(
                label: '取消',
                color: accent,
                pressedColor: ink.withValues(alpha: .06),
                onPressed: closeSearch,
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: ink.withValues(alpha: .08)),
        Expanded(
          child: buildSearchResults(
            context,
            ink: ink,
            muted: muted,
            accent: accent,
          ),
        ),
      ],
    );
  }

  /// Header + one row of tabs, for a sheet too short for the full header.
  ///
  /// Everything the reader needs to get out of the squeezed state survives: the
  /// close button, the tab switch, and the search field when it is open.
  Widget compactLayout(
    BuildContext context, {
    required List<MapEntry<int, String>> entries,
    required String emptyMessage,
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: ReaderDirectoryPanel.compactBarHeight,
          child: Row(
            children: [
              if (searching)
                AppTextButton(
                  label: '取消',
                  color: accent,
                  pressedColor: ink.withValues(alpha: .06),
                  onPressed: closeSearch,
                )
              else ...[
                const SizedBox(width: 8),
                AppPressable(
                  onTap: widget.onClose,
                  semanticLabel: '关闭目录',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(AppIcons.clear, size: 19, color: muted),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: searching
                    ? searchField(
                        context,
                        ink: ink,
                        muted: muted,
                        accent: accent,
                      )
                    : Text(
                        widget.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withValues(alpha: .55),
                          fontSize: 13,
                        ),
                      ),
              ),
              if (!searching && canSearch)
                AppPressable(
                  onTap: openSearch,
                  semanticLabel: '搜索全书',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(AppIcons.search, size: 18, color: accent),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        // Tabs are not useful while typing a query; [searchLayout] is the
        // normal search path, and this is only the fallback if search opens
        // mid-squeeze.
        if (!searching)
          SizedBox(
            height: ReaderDirectoryPanel.compactTabHeight,
            child: tabRow(
              context,
              ink: ink,
              muted: muted,
              accent: accent,
              withTrailingControls: false,
            ),
          ),
        Container(height: 0.5, color: ink.withValues(alpha: .08)),
        Expanded(
          child: body(
            context,
            entries: entries,
            emptyMessage: emptyMessage,
            ink: ink,
            muted: muted,
            accent: accent,
          ),
        ),
      ],
    );
  }

  /// Height of the book-name line plus the tab row (non-search full header).
  ///
  /// Part of the panel's contract: [ReaderMenu] keeps the sheet at least this
  /// tall, because a sheet shorter than its own header is what overflows.
  /// Tabs, the search entry point, the order toggle and the close button.
  /// Shared by the full and the compact header; the compact bar already carries
  /// the trailing controls, so [withTrailingControls] turns them off there.
  ///
  /// The tabs are laid out with [Expanded] and [Wrap] rather than a fixed
  /// `Spacer` row: at a large system font scale the three labels plus the three
  /// controls are wider than a phone, and a fixed row simply overflowed.
  Widget tabRow(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
    bool withTrailingControls = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (index, label) in [
                    (0, '目录'),
                    (1, '书签'),
                    (2, '笔记'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          refresh(() {
                            tab = index;
                            currentOffscreen = false;
                          });
                          didAutoScroll = false;
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => autoScrollToCurrent(),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: tab == index ? accent : muted,
                              fontSize: 16,
                              fontWeight: tab == index
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (withTrailingControls) ...[
            // 全文搜索 lives in the catalogue tab, where a reader looks for a
            // passage they half remember. Fanqie's catalog order toggle shares
            // the slot and hides while searching.
            if (tab == 0 && canSearch && !searching)
              AppPressable(
                onTap: openSearch,
                semanticLabel: '搜索全书',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(AppIcons.search, size: 19, color: accent),
                ),
              ),
            if (tab == 0 && !searching)
              AppTextButton(
                label: descending ? '倒序' : '正序',
                color: accent,
                pressedColor: ink.withValues(alpha: .06),
                onPressed: toggleOrder,
              ),
            AppPressable(
              onTap: widget.onClose,
              semanticLabel: '关闭目录',
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(AppIcons.clear, size: 20, color: muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The query field plus its 取消 button.
  Widget searchField(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(
            // Its own element, so a panel rebuild cannot recreate the input
            // connection — which on Android tears the session down
            // (`onFinishInputView`) and starts another (`onStartInput`). The key
            // keeps that element alive even if the surrounding header layout
            // (full vs compact) swaps while the keyboard animates the viewport.
            child: ReaderSearchQueryField(
              key: searchFieldKey,
              controller: searchController,
              focusNode: searchFocus,
              onChanged: onQueryChanged,
              showClear: query.isNotEmpty,
              onClear: () {
                searchController.clear();
                runSearch('');
              },
              style: TextStyle(color: ink, fontSize: 14),
              placeholderStyle: TextStyle(color: muted, fontSize: 14),
              cursorColor: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget header(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Book name (Fanqie V1: 14sp, alpha 0.4 day / 0.6 night)
        if (widget.bookTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              widget.bookTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The shared muted role rather than a local .45: the book name
              // is the one line that says which book this catalogue belongs
              // to, and .45 sits under the text floor on the white paper.
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ),

        // 2) SlidingTabLayout-style tabs (Fanqie 16sp). Searching uses
        // [searchLayout] instead — tabs and the book name are not useful
        // while typing a query.
        tabRow(context, ink: ink, muted: muted, accent: accent),

        // 3) Divider (Fanqie alj / item: 0.5dp)
        Container(height: 0.5, color: ink.withValues(alpha: .08)),
      ],
    );
  }

  /// The tab's list: search results, notes, or the index itself.
  Widget body(
    BuildContext context, {
    required List<MapEntry<int, String>> entries,
    required String emptyMessage,
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    if (searching) {
      return buildSearchResults(
        context,
        ink: ink,
        muted: muted,
        accent: accent,
      );
    }
    if (tab == 2) return buildNotes(context);
    if (entries.isEmpty) {
      return Column(
        children: [
          if (tab == 0 && widget.progressSummary != null)
            continueReadingCard(
              context,
              ink: ink,
              muted: muted,
              accent: accent,
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final list = ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemExtent: ReaderDirectoryPanelState.itemExtent,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isCurrent =
            tab == 0 && isCurrentChapter(entry.key, index, entries);
        final isRead = tab == 0 && isReadChapter(entry.key);
        final titleColor = isCurrent
            ? accent
            : isRead
            ? ink.withValues(alpha: .6)
            : ink;
        // The row's meta line is read, not decorative: same muted role as the
        // rest of the panel instead of a one-off .45.
        final metaColor = muted;
        final secondary = secondaryLabel(entry.key, isCurrent, isRead);
        return Semantics(
          button: true,
          label: isCurrent ? '${entry.value}，当前章节' : entry.value,
          // Press fill over the whole row, like every other list in the app.
          // The catalogue used a bare GestureDetector, so a tap gave no feedback
          // until the page jumped.
          child: AppPressable(
            onTap: () {
              final callback = widget.onJumpToChapter;
              if (tab == 0 && callback != null) {
                callback(entry.key, restorePosition: isCurrent);
              } else {
                widget.onJumpToParagraph(entry.key);
              }
            },
            pressedColor: ink.withValues(alpha: .06),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isCurrent ? accent.withValues(alpha: .07) : null,
                border: Border(
                  left: BorderSide(
                    color: isCurrent ? accent : const Color(0x00000000),
                    width: 3,
                  ),
                  bottom: BorderSide(
                    color: ink.withValues(alpha: .06),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (isCurrent)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        AppIcons.bookmarkFill,
                        size: 14,
                        color: accent,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle(titleColor).copyWith(
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        // The catalogue item is a fixed 54dp Fanqie row. At a
                        // large text scale the title alone fills it, so the
                        // secondary line steps aside rather than being clipped.
                        if (secondary.isNotEmpty &&
                            MediaQuery.textScalerOf(context).scale(1) <=
                                1.4) ...[
                          const SizedBox(height: 4),
                          Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: metaColor, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (tab == 1)
                    AppPressable(
                      onTap: () async {
                        await widget.onRemoveBookmark(entry.key);
                        if (mounted) refresh(() {});
                      },
                      semanticLabel: '移除书签',
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          AppIcons.delete,
                          size: 17,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (tab != 0 || widget.progressSummary == null) return list;
    return Stack(
      children: [
        Column(
          children: [
            continueReadingCard(
              context,
              ink: ink,
              muted: muted,
              accent: accent,
            ),
            Expanded(child: list),
          ],
        ),
        if (currentOffscreen)
          Positioned(
            right: 16,
            bottom: 14,
            child: AppPressable(
              onTap: () {
                didAutoScroll = false;
                autoScrollToCurrent();
              },
              borderRadius: AppRadius.xl3All,
              semanticLabel: '定位到当前章节',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: AppRadius.xl3All,
                ),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      AppIcons.locationFill,
                      size: 18,
                      color: context.c.constantWhite,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget continueReadingCard(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final summary = widget.progressSummary;
    if (summary == null) return const SizedBox.shrink();
    final bookPercent = (summary.bookProgress * 100).round();
    final chapterPercent = (summary.chapterProgress * 100).round();
    final enabled =
        widget.onContinueReading != null &&
        summary.hasResumePosition &&
        !summary.isAtResumePosition;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Semantics(
        button: enabled,
        label: enabled ? '继续阅读 ${summary.resumeChapterTitle}' : '正在阅读',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(AppRadius.grouped),
            border: Border.all(color: accent.withValues(alpha: .22)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        enabled ? '继续阅读' : '正在阅读',
                        style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        summary.resumeChapterTitle.isEmpty
                            ? summary.currentChapterTitle
                            : summary.resumeChapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: 14),
                      ),
                      const SizedBox(height: 7),
                      progressTrack(
                        context,
                        value: summary.bookProgress,
                        color: accent,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // 本章 → 全书, the order the progress row uses. The card
                        // printed the pair backwards, and in scroll mode
                        // currentPageLabel *is* the book percentage, so the
                        // same number used to appear twice on one line.
                        '本章 $chapterPercent% · 全书 $bookPercent%'
                        '${summary.currentPageLabel.isEmpty || summary.currentPageLabel == '$bookPercent%' ? '' : ' · ${summary.currentPageLabel}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // The arrow is an affordance, so it is only drawn when there is
                // somewhere to go. saveState() rewrites the resume position on
                // every turn, so while reading the card is almost always at the
                // reader; a disabled chevron there promised a jump that would
                // never happen.
                if (enabled)
                  AppPressable(
                    onTap: widget.onContinueReading,
                    semanticLabel: '继续阅读',
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        AppIcons.chevronForward,
                        color: accent,
                        size: 18,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget progressTrack(
    BuildContext context, {
    required double value,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.hairlineXs),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: color.withValues(alpha: .14),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }

  /// Search results, grouped by chapter.
  ///
  /// A flat list of "第 N 段" is hard to navigate in a long book, so results are
  /// grouped under chapter headers; each row leads with the passage (query
  /// highlighted) and follows with the line before it for context, plus the page
  /// the hit sits on. A summary bar counts them and steps through them.
}
