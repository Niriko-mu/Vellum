import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/book_library.dart';
import '../services/txt_seek_source.dart';
import 'reader_models.dart';
import 'reader_pagination.dart';
import 'reader_page_pagination_controller.dart';

import 'reader_page_state.dart';
import 'reader_page_state_surface_rendering.dart';

extension ReaderPagePagination on ReaderPageState {
  double pageAvailableHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final view = MediaQuery.viewPaddingOf(context);
    // Must match PageView/list padding, inside SafeArea.
    // Pagination subtracts an extra measurement slack internally.
    return size.height -
        view.top -
        view.bottom -
        ReaderPageState.readerTopInset -
        ReaderPageState.readerBottomInset;
  }

  double pageContentWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.size.width -
        media.padding.left -
        media.padding.right -
        ReaderPageState.readerSideInset * 2;
  }

  PageLayoutConfig pageLayoutConfig(BuildContext context) {
    final media = MediaQuery.of(context);
    return PageLayoutConfig(
      fontSize: fontSize,
      lineSpacing: lineSpacing,
      fontFamily: readerFontFamily,
      fontWeight: readerFontWeight,
      availableHeight: pageAvailableHeight(context),
      contentWidth: pageContentWidth(context),
      screenHeight: media.size.height,
      title: widget.book.title,
    );
  }

  /// Progressive pagination delegates measurement and cancellation to the
  /// controller so the page state only coordinates Flutter callbacks.
  void ensurePages(BuildContext context) {
    final config = pageLayoutConfig(context);
    final anchor = readingMode == ReadingMode.page
        ? currentPageParagraphOrInitial()
        : currentParagraph;
    pagination.ensure(
      config: config,
      size: MediaQuery.sizeOf(context),
      bottomInset: ReaderPageState.readerBottomInset,
      anchorParagraph: anchor,
      currentPage: currentPage,
      pageMode: readingMode == ReadingMode.page,
      onReset: (page) {
        if (page == currentPage) return;
        currentPage = page;
        requestedPage = page;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) jumpToPageExact(page);
        });
      },
      onChanged: () {
        if (mounted) refresh(() {});
      },
      isActive: () => mounted,
    );
  }

  void cancelPagination() => pagination.cancel();

  void paginateAsync({required int targetPages}) {
    pagination.paginateAsync(
      targetPages: targetPages,
      onChanged: () {
        if (mounted) refresh(() {});
      },
      isActive: () => mounted,
    );
  }

  void maybeExtendPagination() {
    if (readingMode != ReadingMode.page) return;
    pagination.maybeExtend(
      currentPage: currentPage,
      onChanged: () {
        if (mounted) refresh(() {});
      },
      isActive: () => mounted,
    );
  }

  /// Makes a predecessor page available when a deep anchored window is at its
  /// local first page.  The paginator keeps the chapter's first visible page
  /// as the semantic target, then returns that target's new local index so the
  /// caller can perform the actual previous-page turn.
  int? preparePreviousPage() {
    if (readingMode != ReadingMode.page || !pager.isAnchored) return null;
    if (pages.isEmpty || currentPage > 0) return null;
    final boundary = pager.firstParagraphOfPage(0) ?? pager.anchorParagraph;
    final page = pagination.preparePreviousPage(boundaryParagraph: boundary);
    if (page == null || page <= 0) return null;
    if (pageController.hasClients) jumpToPageExact(page);
    refresh(() {
      currentPage = page;
      requestedPage = page;
      pagePositionRestored = true;
    });
    paginateAsync(targetPages: page + ReaderPaginationController.pagesAhead);
    return page;
  }

  int firstParagraphOfCurrentPage() {
    if (pages.isEmpty ||
        pages[currentPage.clamp(0, pages.length - 1)].isEmpty) {
      return 0;
    }
    return pages[currentPage.clamp(0, pages.length - 1)].first.paragraphIndex;
  }

  /// Test hooks: the page-mode reading position has to survive a re-layout, and
  /// that is easiest to assert from the page state itself.
  @visibleForTesting
  int get debugCurrentPageParagraph => currentPageParagraphOrInitial();

  @visibleForTesting
  int get debugPageCount => pageCount;

  /// The live search mark, for asserting when it is placed and dropped.
  @visibleForTesting
  String get debugSearchHighlight => searchHighlight;

  /// Places a search mark the way a tapped result does, including the guard that
  /// stops the jump's own page change from clearing it.
  @visibleForTesting
  void debugPlaceSearchHighlight(String query) {
    refresh(() {
      searchHighlight = query.trim();
      searchHighlightSurvivesNextTurn = true;
    });
  }

  /// Turns one page the same way a tap does, for the mark's lifetime rule.
  @visibleForTesting
  void debugTurnPage() => changePage(context, 1);

  @visibleForTesting
  void debugJumpToPage(int page) => jumpToParagraph(
    pages.isEmpty
        ? 0
        : pages[page.clamp(0, pages.length - 1)].first.paragraphIndex,
  );

  @visibleForTesting
  void debugSetFontSize(double value) => refresh(() => fontSize = value);

  /// Paragraph the reader is looking at right now, used to re-anchor after a
  /// re-layout. Falls back to the saved paragraph when the pager is not built
  /// yet, where the page index means nothing.
  int currentPageParagraphOrInitial() {
    return pagination.currentPageParagraph(
      currentPage: currentPage,
      livePage: pageController.hasClients ? pageController.page : null,
      fallback: widget.initialState.paragraphIndex,
    );
  }

  /// Page of the current pagination window that shows [paragraphIndex].
  ///
  /// While the pager is anchored, this re-anchors the window when the target lies
  /// before it, and otherwise extends forward. The result is a local page index
  /// that is safe for the page view; the book-wide number comes from
  /// `ProgressiveBookPager.globalPageFor`.
  int pageForParagraph(int paragraphIndex) {
    return pagination.pageForParagraph(paragraphIndex);
  }

  void restorePageWhenReady() {
    if (pagePositionRestored || readingMode != ReadingMode.page) return;
    final requested = widget.initialState.paragraphIndex;
    final starts = pages;
    if (starts.isEmpty) return;
    final target = pageForParagraph(requested).clamp(0, starts.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || pagePositionRestored) return;
      if (!pageController.hasClients) {
        return;
      }
      // Consume the one-shot restore. Never re-apply after the user navigates
      // (TOC, progress, or tap paging).
      pagePositionRestored = true;
      if (target == 0) return;
      if (currentPage != 0 || requestedPage != 0) return;
      final live = pageController.page;
      if (live == null || live != 0) return;
      jumpToPageExact(target);
      refresh(() {
        currentPage = target;
        requestedPage = target;
      });
    });
  }

  /// Jump to [page]. [SnapPageScrollPhysics] suppresses any residual spring
  /// that [PageController.jumpToPage] would otherwise start via `goBallistic`.
  void jumpToPageExact(int page) {
    if (!pageController.hasClients) return;
    pageController.jumpToPage(page);
  }

  int get activeParagraph => readingMode == ReadingMode.page
      ? firstParagraphOfCurrentPage()
      : currentParagraph;
  bool get isCurrentViewBookmarked {
    if (bookmarks.isEmpty) return false;
    if (readingMode == ReadingMode.scroll) {
      return bookmarks.contains(activeParagraph);
    }
    if (pages.isEmpty) return false;
    final page = currentPage.clamp(0, pages.length - 1);
    return pages[page].any(
      (fragment) => bookmarks.contains(fragment.paragraphIndex),
    );
  }

  Map<int, String> chapterPageLabels() {
    final labels = <int, String>{};
    for (final entry in chapters) {
      final ref = pager.pageRefForParagraph(entry.key);
      labels[entry.key] = ref.exact ? '第 ${ref.page1} 页' : '约第 ${ref.page1} 页';
    }
    return labels;
  }

  List<MapEntry<int, String>> chapterEntries() => chapters;

  /// Index of the chapter containing [paragraph], or -1 when before the first.
  int chapterIndexFor(int paragraph) =>
      progressController.chapterIndexFor(paragraph);

  void rememberCurrentChapterPosition() {
    final restored = readingMode == ReadingMode.page
        ? pagePositionRestored
        : scrollPositionRestored;
    final paragraph = activeParagraph.clamp(
      0,
      widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
    );
    progressController.rememberCurrentChapterPosition(
      paragraph: paragraph,
      scrollOffset: scrollController.hasClients ? scrollController.offset : 0,
      page: currentPage,
      restored: restored,
    );
  }

  /// Chapter title only — top-left / menu bar (Fanqie running head).
  String get chapterLabel {
    if (chapters.isEmpty) return '';
    final index = chapterIndexFor(activeParagraph);
    if (index < 0) return '开篇';
    return chapters[index].value;
  }

  String chapterLabelForParagraph(int paragraph) {
    return progressController.chapterLabelForParagraph(paragraph);
  }

  double chapterProgressForParagraph(int paragraph) {
    return progressController.chapterProgressForParagraph(paragraph, progress);
  }

  ReaderProgressSummary get progressSummary {
    final active = activeParagraph;
    final currentIndex = chapterIndexFor(active);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final resumeTitle = chapterLabelForParagraph(resumeParagraphIndex);
    final hasResume =
        resumeParagraphIndex > 0 ||
        widget.initialState.position > 0 ||
        widget.initialState.page > 0;
    return ReaderProgressSummary(
      bookProgress: progress,
      chapterProgress: chapterProgressForParagraph(active),
      currentChapterIndex: safeIndex,
      currentChapterTitle: chapterLabel,
      currentPageLabel: pageProgress,
      resumeChapterTitle: resumeTitle,
      hasResumePosition: hasResume,
      isAtResumePosition: active == resumeParagraphIndex,
    );
  }

  /// Fanqie bottom indicator: page number only (no percent / paragraph).
  String get pageProgress {
    if (readingMode == ReadingMode.page) {
      final total = bookPageCount;
      final current = pageNumberOf(currentPage).clamp(1, total);
      return pager.fullyPaginated && !pager.isAnchored
          ? '$current / $total'
          : '$current / ~$total';
    }
    final percent = (progress * 100).clamp(0, 100).round();
    return '$percent%';
  }

  /// Book-wide page count: exact when the pager has measured the whole book,
  /// otherwise the character-ratio estimate (an anchored window only knows its
  /// own pages).
  int get bookPageCount {
    if (!pager.isAnchored) return pager.estimatedTotalPageCount;
    // The footer and the progress bar are the only consumers, and they are built
    // once per frame: widen the sample here so the number settles instead of
    // drifting as the reader turns pages.
    pager.calibrateEstimate();
    return pager.estimatedGlobalPageCount;
  }

  /// Book-wide 1-based page number for a page of the current window.
  int pageNumberOf(int page) =>
      pager.isAnchored ? pager.globalPageFor(page) : page + 1;

  /// Page label for a search result, so a hit can be placed in the book.
  ///
  /// Uses the pager's own mapping (exact or estimated) without forcing a new
  /// layout pass: search covers the whole book, and paginating to every hit
  /// would be as expensive as opening every chapter.
  String pageLabelForParagraph(int paragraphIndex) {
    final ref = pager.pageRefForParagraph(paragraphIndex);
    return '${ref.exact ? '第' : '约'} ${ref.page1} 页';
  }

  String get batteryText => batteryLevel < 0 ? '' : '$batteryLevel%';

  double get progress {
    if (readingMode == ReadingMode.page) {
      final total = bookPageCount;
      if (total <= 1) return 0;
      return ((pageNumberOf(currentPage) - 1) / (total - 1)).clamp(0.0, 1.0);
    }
    if (!scrollController.hasClients) return 0;
    final position = scrollController.position;
    // Dimensions may not be applied yet on the first frames.
    if (!position.hasPixels || !position.haveDimensions) return 0;
    final max = position.maxScrollExtent;
    if (max <= 0) return 0;
    final raw = scrollController.offset / max;
    if (raw <= 0.002) return 0.0;
    if (raw >= 0.998) return 1.0;
    return raw.clamp(0.0, 1.0);
  }

  bool get canSeekProgress {
    if (readingMode == ReadingMode.page) {
      return pager.estimatedTotalPageCount > 1 ||
          widget.book.paragraphs.length > 1;
    }
    if (!scrollController.hasClients) return false;
    final position = scrollController.position;
    return position.hasPixels &&
        position.haveDimensions &&
        position.maxScrollExtent > 0;
  }

  Future<void> jumpToProgress(double value) async {
    final target = value.clamp(0.0, 1.0);
    final generation = ++jumpGeneration;
    cancelPagination();
    if (readingMode == ReadingMode.page) {
      final totalParas = widget.book.paragraphs.length;
      if (totalParas <= 0) return;
      final para = (target * (totalParas - 1)).round().clamp(0, totalParas - 1);
      final paragraphs = widget.book.paragraphs;
      if (paragraphs is TxtParagraphList) {
        await paragraphs.source.prefetchAroundParagraph(para);
        if (!mounted || generation != jumpGeneration) return;
      }
      // Past the anchor threshold this jumps the pagination window to the target
      // instead of measuring the whole prefix — the difference between an
      // instant seek and a minute of blocked UI in a 二十四史-sized book.
      final page = pageForParagraph(para).clamp(0, pageCount - 1);
      // `pageForParagraph` may replace the exact prefix with a fresh anchored
      // window. Move the controller before rebuilding with the shorter
      // `itemCount`; otherwise its old deep page remains selected while the
      // new window has only a handful of pages and the next turn is dropped.
      if (pageController.hasClients) jumpToPageExact(page);
      paginateAsync(targetPages: page + ReaderPaginationController.pagesAhead);
      refresh(() {
        currentPage = page;
        requestedPage = page;
      });
      scheduleSave();
      return;
    }
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    scrollController.jumpTo(target * position.maxScrollExtent);
    scheduleSave();
  }

  /// Fanqie progress semantics: SeekBar drives chapter index, not 0–100%.
  void jumpToChapter(int chapterIndex) {
    final entries = chapters;
    if (entries.isEmpty) return;
    final index = chapterIndex.clamp(0, entries.length - 1);
    jumpToParagraph(
      entries[index].key,
      restoreChapter: false,
      preloadPreviousPage: true,
    );
  }

  void jumpToScrollParagraph(
    int target, {
    double? preferredOffset,
    int? jumpGeneration,
  }) {
    final count = widget.book.paragraphs.length;
    if (count == 0 || !scrollController.hasClients) return;
    final index = target.clamp(0, count - 1);
    // A pixel jump in a variable-height list lays out every preceding child.
    // Re-center the two lazy slivers at the destination instead.
    scrollController.jumpTo(0);
    refresh(() {
      scrollAnchor = index;
      currentParagraph = index;
    });
    scheduleSave();
    refineScrollJump(index, jumpGeneration: jumpGeneration);
  }

  void refineScrollJump(int target, {int attempt = 0, int? jumpGeneration}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (jumpGeneration != null && jumpGeneration != this.jumpGeneration) {
        return;
      }
      var ctx = paragraphKeys[target]?.currentContext;
      if (ctx == null) {
        // Target not built yet: step toward the nearest mounted paragraph so
        // the lazy list materializes the destination.
        int? nearest;
        var nearestDistance = 1 << 30;
        for (final entry in paragraphKeys.entries) {
          final child = entry.value.currentContext;
          if (child == null) continue;
          final distance = (entry.key - target).abs();
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearest = entry.key;
          }
        }
        if (nearest != null && nearestDistance > 0) {
          ctx = paragraphKeys[nearest]!.currentContext;
        }
      }
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.08,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      // Retry exact target after the list has had another frame to build it.
      final exact = paragraphKeys[target]?.currentContext;
      if (exact != null && exact.mounted && ctx != exact) {
        await Scrollable.ensureVisible(
          exact,
          alignment: 0.08,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
        );
      }
      if (mounted) {
        if (jumpGeneration != null && jumpGeneration != this.jumpGeneration) {
          return;
        }
        refresh(() => currentParagraph = target);
        scheduleSave();
      }
      if (exact == null && attempt < 8) {
        refineScrollJump(
          target,
          attempt: attempt + 1,
          jumpGeneration: jumpGeneration,
        );
      }
    });
  }

  /// Jumps to a search result and keeps the query so the passage stays marked.
  ///
  /// The search panel closes on tap, so without stashing the term here the
  /// highlight would vanish with it — the reader would land on the paragraph
  /// with nothing showing *why*. The mark lasts until the reader turns the page
  /// (or scrolls away): it is a pointer to the passage, not a note, so it must
  /// not linger over unrelated text.
  void jumpToSearchHit(int paragraphIndex, String query) {
    final term = query.trim();
    refresh(() {
      searchHighlight = term;
      // The jump itself moves the page; only a turn *after* it clears the mark.
      searchHighlightSurvivesNextTurn = true;
    });
    jumpToParagraph(paragraphIndex);
    // In scroll mode the jump lands at an offset: remember it so scrolling away
    // can drop the mark.
    searchHighlightScrollOffset =
        readingMode == ReadingMode.scroll && scrollController.hasClients
        ? scrollController.offset
        : null;
  }

  /// Clears the search mark. Called when the reader turns or scrolls away.
  void clearSearchHighlight() {
    if (searchHighlight.isEmpty) return;
    refresh(() => searchHighlight = '');
  }

  /// True when a page turn should keep the mark (the jump's own turn).
  bool consumeSearchHighlightTurnGuard() {
    if (!searchHighlightSurvivesNextTurn) return false;
    searchHighlightSurvivesNextTurn = false;
    return true;
  }

  /// Applies the "the reader turned the page" rule to the search mark.
  ///
  /// Called from every way a page turn starts — tap/seek, finger drag, and the
  /// page view's own notification — so the mark never outlives the passage it
  /// was placed on, whichever gesture moved the reader on.
  void onPageTurned() {
    if (consumeSearchHighlightTurnGuard()) return;
    clearSearchHighlight();
  }

  Future<void> jumpToParagraph(
    int paragraphIndex, {
    bool restoreChapter = false,
    bool preloadPreviousPage = false,
  }) async {
    final generation = ++jumpGeneration;
    cancelPagination();
    final maxIndex = widget.book.paragraphs.isEmpty
        ? 0
        : widget.book.paragraphs.length - 1;
    rememberCurrentChapterPosition();
    var target = paragraphIndex.clamp(0, maxIndex);
    ChapterReadingPosition? checkpoint;
    if (restoreChapter) {
      checkpoint = chapterPositions[paragraphIndex];
      if (checkpoint != null) {
        target = checkpoint.paragraphIndex.clamp(0, maxIndex);
      }
    }
    final paragraphs = widget.book.paragraphs;
    if (paragraphs is TxtParagraphList) {
      await paragraphs.source.prefetchAroundParagraph(target);
      if (!mounted || generation != jumpGeneration) return;
    }
    if (readingMode == ReadingMode.page) {
      var page = pageForParagraph(target).clamp(0, pageCount - 1);
      if (preloadPreviousPage && page == 0 && pager.isAnchored) {
        final prepared = pagination.preparePreviousPage(
          boundaryParagraph: target,
        );
        if (prepared != null) page = prepared;
      }
      // A chapter jump can re-anchor the pager and shrink PageView's itemCount
      // from an old deep page to the new 12-page window. Clamp the controller
      // and both page fields before the rebuild so PageView never observes an
      // out-of-range current page. The old animation used to complete against
      // the discarded window (or never complete), leaving forward taps stuck.
      if (pageController.hasClients) jumpToPageExact(page);
      refresh(() {
        currentPage = page;
        requestedPage = page;
        pagePositionRestored = true;
      });
      pagination.paginateAsync(
        targetPages: page + ReaderPaginationController.pagesAhead,
        onChanged: () {
          if (mounted) refresh(() {});
        },
        isActive: () => mounted && generation == jumpGeneration,
      );
      scheduleSave();
      return;
    }
    jumpToScrollParagraph(
      target,
      preferredOffset: checkpoint?.position,
      jumpGeneration: generation,
    );
  }
}
