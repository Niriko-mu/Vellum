import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';

import '../services/book_importer.dart';
import '../services/lazy_paragraphs.dart';
import 'reader_models.dart';
import 'reader_pagination.dart';

/// Owns progressive page measurement and bounded deep jumps for one book.
///
/// The page state supplies layout configuration and decides when to rebuild;
/// this controller owns the pager, generation cancellation, and async slices.
class ReaderPaginationController {
  ReaderPaginationController({required ImportedBook book})
    : _book = book,
      pager = ProgressiveBookPager(book, _initialLayout);

  static const int pagesAhead = 100;
  static const int initialPages = 12;
  static const int anchorFoldParagraphs = 4000;

  /// Forward jump, in paragraphs, beyond which re-anchoring beats measuring.
  ///
  /// Measuring a prefix costs a full layout pass per paragraph; past a few
  /// hundred the reader is waiting on pages they will never see.
  static const int jumpReAnchorParagraphs = 400;

  /// How much already-read context to materialise when a deep anchored window
  /// is asked to turn backwards from its local first page.  This keeps the
  /// recovery bounded while still covering many pages for normal chapters.
  static const int backwardLookbackParagraphs = 256;
  static const int maxBackwardLookbackParagraphs = 512;

  static const _initialLayout = PageLayoutConfig(
    fontSize: 18,
    lineSpacing: ReaderLineSpacing.standard,
    // A const default; the live family is applied per layout at runtime. Kept
    // in step with VellumTheme.bundledSerifFamily by hand because a const
    // cannot reference it.
    fontFamily: 'Noto Serif SC',
    fontWeight: ReaderFontWeight.regular,
    availableHeight: 600,
    contentWidth: 360,
    screenHeight: 800,
    title: '',
  );

  final ImportedBook _book;
  ProgressiveBookPager pager;
  bool _busy = false;
  int _generation = 0;
  Timer? _yieldTimer;
  Size? _lastSize;
  double? _lastHeight;
  double? _lastWidth;
  double? _lastBottomInset;
  PageLayoutConfig? _lastConfig;

  List<List<PageFragment>> get pages => pager.pages;
  int get pageCount => pager.pageCount;

  bool needsReset({
    required PageLayoutConfig config,
    required Size size,
    required double bottomInset,
  }) {
    return _lastSize != size ||
        _lastHeight != config.availableHeight ||
        _lastWidth != config.contentWidth ||
        _lastBottomInset != bottomInset ||
        _lastConfig?.fontSize != config.fontSize ||
        _lastConfig?.lineSpacing != config.lineSpacing ||
        _lastConfig?.fontFamily != config.fontFamily ||
        _lastConfig?.fontWeight != config.fontWeight ||
        _lastConfig?.textScaler != config.textScaler;
  }

  int reset({required PageLayoutConfig config, required int anchorParagraph}) {
    cancel();
    pager = ProgressiveBookPager(_book, config);
    final safe = anchorParagraph.clamp(
      0,
      _book.paragraphs.isEmpty ? 0 : _book.paragraphs.length - 1,
    );
    final watch = Stopwatch()..start();
    final int page;
    if (safe > anchorFoldParagraphs || (_book.usesLazyContent && safe > 0)) {
      pager.paginateFrom(safe, minPages: initialPages);
      page = 0;
    } else {
      pager.paginateThrough(safe);
      page = pager.exactPageForParagraph(safe) ?? 0;
      pager.paginateUntilPages(page + initialPages);
    }
    watch.stop();
    if (kDebugMode && watch.elapsedMilliseconds >= 150) {
      debugPrint(
        'Vellum re-anchor: paragraph $safe → page $page of '
        '${_book.paragraphs.length} ${pager.isAnchored ? '(anchored)' : '(exact)'} '
        'in ${watch.elapsedMilliseconds}ms',
      );
    }
    _lastConfig = config;
    return page;
  }

  void recordLayout({
    required PageLayoutConfig config,
    required Size size,
    required double bottomInset,
  }) {
    _lastConfig = config;
    _lastSize = size;
    _lastHeight = config.availableHeight;
    _lastWidth = config.contentWidth;
    _lastBottomInset = bottomInset;
  }

  /// Forces the next build to measure with the current typography settings.
  void invalidateLayout() {
    _lastSize = null;
  }

  void ensure({
    required PageLayoutConfig config,
    required Size size,
    required double bottomInset,
    required int anchorParagraph,
    required int currentPage,
    required bool pageMode,
    required void Function(int page) onReset,
    required VoidCallback onChanged,
    required bool Function() isActive,
  }) {
    if (needsReset(config: config, size: size, bottomInset: bottomInset)) {
      final page = reset(config: config, anchorParagraph: anchorParagraph);
      recordLayout(config: config, size: size, bottomInset: bottomInset);
      onReset(page);
      paginateAsync(
        targetPages: page + pagesAhead,
        onChanged: onChanged,
        isActive: isActive,
      );
      return;
    }
    if (pageMode &&
        !pager.fullyPaginated &&
        pager.pageCount < currentPage + pagesAhead) {
      paginateAsync(
        targetPages: currentPage + pagesAhead,
        onChanged: onChanged,
        isActive: isActive,
      );
    }
  }

  void cancel() {
    _generation++;
    _busy = false;
    _yieldTimer?.cancel();
    _yieldTimer = null;
  }

  void paginateAsync({
    required int targetPages,
    required VoidCallback onChanged,
    required bool Function() isActive,
  }) {
    if (_busy) return;
    _busy = true;
    final localPager = pager;
    final generation = _generation;

    Future<void> step() async {
      _yieldTimer = null;
      if (!isActive() ||
          !_busy ||
          generation != _generation ||
          !identical(localPager, pager)) {
        return;
      }
      if (localPager.fullyPaginated || localPager.pageCount >= targetPages) {
        _busy = false;
        return;
      }
      final paragraphs = _book.paragraphs;
      if (paragraphs is LazyParagraphs) {
        try {
          await paragraphs.prefetchAroundParagraph(localPager.nextParagraph);
        } catch (_) {
          _busy = false;
          return;
        }
        if (!isActive() ||
            generation != _generation ||
            !identical(localPager, pager))
          return;
      }
      final sw = Stopwatch()..start();
      while (isActive() &&
          _busy &&
          generation == _generation &&
          identical(localPager, pager) &&
          !localPager.fullyPaginated &&
          localPager.pageCount < targetPages &&
          sw.elapsedMilliseconds < 12) {
        var sliceSize = 20;
        if (paragraphs is LazyParagraphs) {
          final next = localPager.nextParagraph;
          if (!paragraphs.isParagraphCached(next)) break;
          final end = paragraphs.blockEndForParagraph(next);
          sliceSize = (end - next).clamp(1, 20);
        }
        // The budget goes into the slice too: the 12 ms check above only runs
        // between slices, and one slice is up to 20 paragraphs of long text.
        localPager.paginateSlice(
          maxParagraphs: sliceSize,
          clock: sw,
          budgetMs: 12,
        );
      }
      // The book-wide page number needs a representative character sample. It
      // used to be measured by the footer getter, inside build; doing it here
      // keeps the freeze off the frame and lets the number settle within a few
      // slices instead.
      if (localPager.isAnchored &&
          !localPager.isEstimateCalibrated &&
          isActive() &&
          identical(localPager, pager)) {
        localPager.calibrateEstimate();
      }
      if (!isActive() ||
          !_busy ||
          generation != _generation ||
          !identical(localPager, pager)) {
        return;
      }
      onChanged();
      if (localPager.fullyPaginated || localPager.pageCount >= targetPages) {
        _busy = false;
        return;
      }
      _yieldTimer = Timer(Duration.zero, step);
    }

    _yieldTimer = Timer(Duration.zero, step);
  }

  void maybeExtend({
    required int currentPage,
    required VoidCallback onChanged,
    required bool Function() isActive,
  }) {
    if (pager.fullyPaginated) return;
    if (pager.pageCount - currentPage < 24) {
      paginateAsync(
        targetPages: currentPage + pagesAhead,
        onChanged: onChanged,
        isActive: isActive,
      );
    }
  }

  /// Rebuilds an anchored window with a small amount of content before
  /// [boundaryParagraph], then returns the local page containing that
  /// paragraph.  Deep jumps intentionally start at the requested paragraph so
  /// they are instant; that means local page zero has no predecessor.  This
  /// method is the bounded, on-demand bridge used by a backwards page turn.
  ///
  /// The method never folds the whole book.  It tries a 256-paragraph lookback
  /// first and expands once to 512 paragraphs only if the target still lands
  /// on local page zero.  A target at paragraph zero (or an empty book) has no
  /// predecessor and returns null.
  int? preparePreviousPage({required int boundaryParagraph}) {
    final total = _book.paragraphs.length;
    if (total <= 0) return null;
    final target = boundaryParagraph.clamp(0, total - 1);
    if (target <= 0) return null;

    var lookback = backwardLookbackParagraphs;
    while (true) {
      final anchor = (target - lookback).clamp(0, target - 1);
      cancel();
      pager.paginateFrom(anchor, minPages: initialPages);
      // Bounded: the window starts [lookback] paragraphs before the target, so
      // this measures at most that many — but a full layout per paragraph is
      // still enough to stall the frame, so the slice gets a budget and the
      // caller may settle for the first page of the window (the reader is
      // turning backwards, so landing one page earlier is not a regression).
      final clock = Stopwatch()..start();
      pager.paginateThrough(
        target,
        clock: clock,
        budgetMs: previousPageBudgetMs,
      );

      final page = pager.exactPageForParagraph(target);
      if (page != null && page > 0) return page;
      if (anchor == 0 ||
          lookback >= maxBackwardLookbackParagraphs ||
          clock.elapsedMilliseconds >= previousPageBudgetMs) {
        return page != null && page > 0 ? page : null;
      }
      lookback = maxBackwardLookbackParagraphs;
    }
  }

  /// Upper bound for one backwards-page rebuild.
  ///
  /// One 256-paragraph window is normally enough; this stops a pathological
  /// chapter from turning a single tap on "上一页" into a multi-hundred-ms
  /// freeze. When it runs out the reader simply stays on the first page of the
  /// prepared window instead of getting the exact predecessor.
  static const int previousPageBudgetMs = 80;

  int pageForParagraph(int paragraphIndex) {
    final total = _book.paragraphs.length;
    if (pager.isAnchored) {
      if (paragraphIndex < pager.anchorParagraph ||
          paragraphIndex > pager.nextParagraph) {
        cancel();
        pager.paginateFrom(paragraphIndex, minPages: initialPages);
      } else {
        pager.paginateThrough(paragraphIndex);
      }
      final exact = pager.exactPageForParagraph(paragraphIndex);
      if (exact != null) return exact.clamp(0, pager.pageCount - 1);
      return (pager.pageRefForParagraph(paragraphIndex).page1 - 1).clamp(
        0,
        pager.pageCount - 1,
      );
    }
    // A forward jump inside the measured prefix is cheap; one further ahead is
    // not, and measuring everything in between is what made a seek in a big
    // book block the UI. Past [jumpReAnchorParagraphs] the window is re-anchored
    // at the target instead of measuring pages the reader will never see.
    final ahead = paragraphIndex - pager.nextParagraph;
    if (total > 0 &&
        (paragraphIndex > anchorFoldParagraphs ||
            ahead > jumpReAnchorParagraphs ||
            (_book.usesLazyContent && ahead > 0))) {
      cancel();
      pager.paginateFrom(paragraphIndex, minPages: initialPages);
      return 0;
    }
    if (ahead > 0) pager.paginateThrough(paragraphIndex);
    final exact = pager.exactPageForParagraph(paragraphIndex);
    if (exact != null)
      return exact.clamp(0, (pager.pageCount - 1).clamp(0, exact));
    final ref = pager.pageRefForParagraph(paragraphIndex);
    return (ref.page1 - 1).clamp(0, pager.pageCount - 1);
  }

  int currentPageParagraph({
    required int currentPage,
    required double? livePage,
    required int fallback,
  }) {
    if (pages.isEmpty) return fallback;
    var index = currentPage.clamp(0, pages.length - 1);
    if (livePage != null && livePage.round() != index) {
      final live = livePage.round().clamp(0, pages.length - 1);
      if (!pager.pageIsEmpty(live)) index = live;
    }
    return pager.firstParagraphOfPage(index) ?? fallback;
  }

  void dispose() => cancel();
}
