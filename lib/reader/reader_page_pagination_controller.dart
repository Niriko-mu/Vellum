import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';

import '../services/book_importer.dart';
import '../services/txt_seek_source.dart';
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

  /// How much already-read context to materialise when a deep anchored window
  /// is asked to turn backwards from its local first page.  This keeps the
  /// recovery bounded while still covering many pages for normal chapters.
  static const int backwardLookbackParagraphs = 256;
  static const int maxBackwardLookbackParagraphs = 512;

  static const _initialLayout = PageLayoutConfig(
    fontSize: 19,
    lineSpacing: ReaderLineSpacing.standard,
    fontFamily: 'Georgia',
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
        _lastConfig?.fontWeight != config.fontWeight;
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
    if (safe > anchorFoldParagraphs || (_book.usesSeek && safe > 0)) {
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
      if (paragraphs is TxtParagraphList) {
        try {
          await paragraphs.source.prefetchAroundParagraph(
            localPager.nextParagraph,
          );
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
        if (paragraphs is TxtParagraphList) {
          final next = localPager.nextParagraph;
          final chapter = paragraphs.catalog.chapterForParagraph(next);
          if (!paragraphs.source.isCached(chapter.index)) break;
          final end =
              paragraphs.catalog.paragraphStartOf(chapter.index) +
              chapter.paragraphCount;
          sliceSize = (end - next).clamp(1, 20);
        }
        localPager.paginateSlice(maxParagraphs: sliceSize);
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
      pager.paginateThrough(target);

      final page = pager.exactPageForParagraph(target);
      if (page != null && page > 0) return page;
      if (anchor == 0 || lookback >= maxBackwardLookbackParagraphs) {
        return page != null && page > 0 ? page : null;
      }
      lookback = maxBackwardLookbackParagraphs;
    }
  }

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
    if (total > 0 &&
        (paragraphIndex > anchorFoldParagraphs ||
            (_book.usesSeek && paragraphIndex > pager.nextParagraph))) {
      cancel();
      pager.paginateFrom(paragraphIndex, minPages: initialPages);
      return 0;
    }
    if (paragraphIndex > pager.nextParagraph)
      pager.paginateThrough(paragraphIndex);
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
