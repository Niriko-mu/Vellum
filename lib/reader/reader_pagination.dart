import 'dart:collection';

import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../services/lazy_paragraphs.dart';
import '../util/text_slices.dart';
import 'reader_markup.dart';
import 'reader_models.dart';
import 'reader_toc.dart';

/// Immutable layout inputs for page-mode pagination.
class PageLayoutConfig {
  const PageLayoutConfig({
    required this.fontSize,
    required this.lineSpacing,
    required this.fontFamily,
    required this.fontWeight,
    required this.availableHeight,
    required this.contentWidth,
    required this.screenHeight,
    required this.title,
  });

  final double fontSize;
  final ReaderLineSpacing lineSpacing;
  final String fontFamily;
  final ReaderFontWeight fontWeight;
  final double availableHeight;
  final double contentWidth;
  final double screenHeight;
  final String title;

  /// SelectableText/rasterized glyphs can extend beyond TextPainter's reported
  /// line box. Reserve half a rendered line (and never less than 12dp) so the
  /// final line is moved whole to the next page instead of being hard-clipped.
  double get measurementSlack => (lineHeight / 2).clamp(12.0, lineHeight);

  double get usableHeight =>
      (availableHeight - measurementSlack).clamp(80.0, availableHeight);

  double get lineHeight => fontSize * lineSpacing.height;

  TextStyle get measureStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: lineSpacing.height,
    fontWeight: fontWeight.value,
    // Match body text; headings use bold via their own scale in render.
  );
}

/// Exact or estimated pagination for [book] under [config].
///
/// Prefer [ProgressiveBookPager] for interactive reading — it paginates
/// ahead of the current position in slices instead of locking the UI on
/// the whole book.
List<List<PageFragment>> computeBookPages(
  ImportedBook book,
  PageLayoutConfig config,
) {
  final pager = ProgressiveBookPager(book, config);
  while (pager.paginateSlice(maxParagraphs: 200)) {}
  return pager.pages;
}

/// Incremental paginator: keeps exact pages for a growing prefix of the book
/// and estimates page numbers for chapters that are not measured yet.
///
/// Pages are stored as packed bounds, not as rendered fragments. A
/// 二十四史-sized book runs to six figures of pages and hundreds of thousands of
/// fragments; building each of those (every slice a fresh `String`) is what made
/// jumping in a big book run out of memory. Only the pages the reader actually
/// shows are turned into [PageFragment]s, and only a handful of those are kept.
class ProgressiveBookPager {
  ProgressiveBookPager(this.book, PageLayoutConfig config)
    : _config = config,
      _contentSize = Size(config.contentWidth, config.screenHeight) {
    reset();
  }

  final ImportedBook book;
  final PageLayoutConfig _config;
  final Size _contentSize;

  /// Packed fragments, [_fragmentStride] ints each:
  /// `[paragraphIndex, sliceStart, sliceEnd, indentPrefixLength, unused,
  ///   flags]`. The fields are all small ints, so they live in flat storage
  /// instead of one object per fragment.
  final List<int> _fragmentWords = [];

  /// Fragments of the page currently being laid out, not yet packed.
  final List<int> _pendingFragment = [];

  /// `[firstFragmentIndex, fragmentCount]` per page.
  final List<int> _pages = [];

  /// Fragment index the page in progress starts at.
  int _pendingStart = 0;

  static const int _fragmentStride = 6;
  static const int _flagTextSlice = 1;
  static const int _flagCompact = 2;
  static const int _flagIndent = 4;
  static const int _flagImage = 8;
  static const int _flagLink = 16;

  /// Pages already turned into renderable fragments, keyed by page index.
  ///
  /// The last page grows while it is being laid out, so each entry remembers the
  /// pass it was built in; a stale entry for the page in progress is rebuilt.
  final Map<int, ({List<PageFragment> fragments, int pass})> _fragmentCache =
      {};

  /// Bumped whenever the page in progress changes.
  int _pass = 0;

  /// How many rendered pages to keep materialised. The page view rebuilds the
  /// visible pages every frame, so a small window is worth holding.
  static const int _fragmentCacheLimit = 12;

  final Map<int, int> _paragraphFirstPage = {};

  /// Cleaned navigation paragraphs as a set: the per-paragraph TOC scan was
  /// O(entries) inside the layout loop, which a chapter-heavy book paid once
  /// per paragraph on every re-layout.
  late final Set<int> _tocParagraphs = {
    for (final entry in chapterEntries(book)) entry.key,
  };

  int _nextParagraph = 0;
  bool _finished = false;
  double _usedHeight = 0;
  bool _needsTitleSpace = true;

  /// Paragraph this pagination window starts at.
  ///
  /// Normally 0: pages are measured from the top of the book, so every page
  /// number is exact. A jump that would need minutes of measuring (a
  /// 二十四史-sized book) anchors here instead — right at the paragraph the reader
  /// asked for — and lays out forward from it. The jump is then instant and the
  /// page on screen is exact; only the *absolute* page numbers become estimates,
  /// which [globalPageFor] derives from the book's character ratio.
  int _anchorParagraph = 0;

  /// Total characters in the book, sampled once to place an anchored window.
  int? _totalChars;

  /// Its companion: characters before the current anchor.
  int? _charsBeforeAnchor;

  /// Characters per page, sampled from the pages measured so far.
  double? _sampledCharsPerPage;

  /// How many paragraphs this window has measured, kept alongside the sample so
  /// [calibrateEstimate] knows whether it is representative yet.
  int _sampledParagraphs = 0;

  /// A window that has measured fewer paragraphs than this cannot place the book
  /// by character ratio: the sample is one or two paragraphs per page, which can
  /// be off by tens of percent.
  static const int _calibrationParagraphs = 150;

  bool get fullyPaginated => _finished;

  /// True when this window does not start at the book's first paragraph, so
  /// absolute page numbers are estimates rather than exact positions.
  bool get isAnchored => _anchorParagraph > 0;
  int get anchorParagraph => _anchorParagraph;

  /// Pages in this window. While anchored this is a local count; use
  /// [globalPageFor] for a book-wide position.
  int get pageCount => _pages.isEmpty ? 1 : _pages.length ~/ 2;
  int get nextParagraph => _nextParagraph;

  /// Fragments of the page in progress (the last entry in [_pages]).
  int get _pageFragmentCount => _pendingFragment.length ~/ _fragmentStride;

  /// True while the page being laid out has no fragment yet.
  bool get _pageIsEmpty => _pendingFragment.isEmpty;

  /// Adds one fragment to the page in progress. The last page grows while it is
  /// laid out, so every addition invalidates a cached build of it.
  void _addFragment(List<int> words) {
    _pendingFragment.addAll(words);
    _pass++;
  }

  /// Renderable pages, materialised on demand.
  ListBase<List<PageFragment>> get pages => _PagesView(this);

  /// True when the page exists and carries no renderable fragment.
  bool pageIsEmpty(int page) {
    if (page < 0 || page >= pageCount) return true;
    if (page * 2 + 1 >= _pages.length) return _pageIsEmpty;
    return _pages[page * 2 + 1] == 0;
  }

  /// First paragraph of [page], or of the nearest earlier page that has
  /// content. A page with no text (an image-only spread) would otherwise report
  /// the book's opening paragraph.
  int? firstParagraphOfPage(int page) {
    for (var i = page.clamp(0, pageCount - 1); i >= 0; i--) {
      if (_fragmentCountOf(i) > 0) {
        return _fragmentWords[_fragmentStartOf(i) * _fragmentStride];
      }
    }
    return null;
  }

  /// Fragments of [page] as render input (empty when out of range).
  List<PageFragment> fragmentsOfPage(int page) {
    if (page < 0 || page >= pageCount) return const [];
    return materializePage(page);
  }

  /// Builds one page's fragments from its packed bounds.
  List<PageFragment> materializePage(int page) {
    final last = page == pageCount - 1;
    final cached = _fragmentCache[page];
    if (cached != null && (!last || cached.pass == _pass)) {
      return cached.fragments;
    }
    final words = last
        // Still being laid out: its bounds are not packed yet.
        ? List<int>.of(_pendingFragment)
        : _fragmentWords.sublist(
            _fragmentStartOf(page) * _fragmentStride,
            (_fragmentStartOf(page) + _fragmentCountOf(page)) * _fragmentStride,
          );
    final built = _buildFragments(words);
    if (_fragmentCache.length >= _fragmentCacheLimit) {
      _fragmentCache.remove(_fragmentCache.keys.first);
    }
    _fragmentCache[page] = (fragments: built, pass: _pass);
    return built;
  }

  int _fragmentStartOf(int page) => _pages[page * 2];

  int _fragmentCountOf(int page) {
    if (page * 2 + 1 >= _pages.length) return _pageFragmentCount;
    return _pages[page * 2 + 1];
  }

  /// Turns packed words into render-facing fragments, slicing the text out of
  /// each paragraph's plain text on the way.
  List<PageFragment> _buildFragments(List<int> words) {
    if (words.isEmpty) return const [];
    // A page normally holds at most two paragraphs: the tail of one and the head
    // of the next. Their plain text is resolved once per page.
    final plainSources = <int, String>{};
    String plainOf(int paragraphIndex) => plainSources.putIfAbsent(
      paragraphIndex,
      () => ReaderMarkup.stripAllMarkers(book.paragraphs[paragraphIndex]),
    );

    return [
      for (var i = 0; i < words.length; i += _fragmentStride)
        PageFragment(
          paragraphIndex: words[i],
          text: (words[i + 5] & _flagTextSlice) == 0
              ? ''
              : sliceDisplayText(
                  plainOf(words[i]),
                  words[i + 1],
                  words[i + 2],
                  indentPrefixLength: words[i + 3],
                ),
          indentFirstLine: (words[i + 5] & _flagIndent) != 0,
          showImage: (words[i + 5] & _flagImage) != 0,
          showLinkAction: (words[i + 5] & _flagLink) != 0,
          compactPadding: (words[i + 5] & _flagCompact) != 0,
        ),
    ];
  }

  /// Best-effort total page count for progress display / TOC estimates.
  int get estimatedTotalPageCount {
    if (_finished) return pageCount;
    final totalParas = book.paragraphs.length;
    if (totalParas <= 0) return pageCount;
    final done = _nextParagraph.clamp(1, totalParas);
    final avg = pageCount / done;
    final remaining = totalParas - done;
    final est = pageCount + (remaining * avg).round();
    return est.clamp(pageCount, pageCount + totalParas + 2);
  }

  /// Resets to a window measured from the top of the book, so page numbers are
  /// exact again.
  void reset() {
    _pages
      ..clear()
      ..addAll(const [0, 0]);
    _pendingFragment.clear();
    _pendingStart = 0;
    _fragmentWords.clear();
    _fragmentCache.clear();
    _paragraphFirstPage.clear();
    _nextParagraph = 0;
    _anchorParagraph = 0;
    _charsBeforeAnchor = null;
    _sampledCharsPerPage = null;
    _sampledParagraphs = 0;
    _finished = false;
    _usedHeight = 0;
    _needsTitleSpace = true;
  }

  /// Paginate up to [maxParagraphs] more source paragraphs.
  /// Returns true when more book content remains.
  bool paginateSlice({int maxParagraphs = 30}) {
    if (_finished) return false;
    if (_needsTitleSpace) {
      _usedHeight = measureTitleHeight(_config) + 30;
      _needsTitleSpace = false;
    }
    // Hoisted: `paragraphs` may be a seek-backed view whose `length` is not a
    // field read, so asking per paragraph is not free.
    final total = book.paragraphs.length;
    var processed = 0;
    while (_nextParagraph < total && processed < maxParagraphs) {
      _paginateParagraph(_nextParagraph);
      _nextParagraph++;
      processed++;
    }
    if (_nextParagraph >= total) _finished = true;
    return !_finished;
  }

  /// Ensure [paragraphIndex] has an exact page mapping.
  void paginateThrough(int paragraphIndex) {
    var guard = 0;
    while (!_finished && _nextParagraph <= paragraphIndex && guard < 20000) {
      paginateSlice(maxParagraphs: 40);
      guard++;
    }
  }

  /// Jumps the pagination window to [paragraphIndex] and lays out from there.
  ///
  /// This is what makes a jump in a huge book instant: no page of the book
  /// before the anchor is measured, so the cost is the pages the reader is about
  /// to see rather than the whole prefix. Pages measured this way start exactly
  /// at [paragraphIndex], so the requested paragraph is the first line of the
  /// first page — nothing is left clipped at the top.
  void paginateFrom(int paragraphIndex, {int minPages = 12}) {
    final total = book.paragraphs.length;
    if (total <= 0) return;
    final anchor = paragraphIndex.clamp(0, total - 1);
    _pages
      ..clear()
      ..addAll(const [0, 0]);
    _pendingFragment.clear();
    _pendingStart = 0;
    _fragmentWords.clear();
    _fragmentCache.clear();
    _paragraphFirstPage.clear();
    _nextParagraph = anchor;
    _anchorParagraph = anchor;
    _finished = false;
    _usedHeight = 0;
    // The previous window's calibration does not describe this one.
    _sampledCharsPerPage = null;
    _sampledParagraphs = 0;
    _charsBeforeAnchor = null;
    // The book title opens the first page only when the window starts at the
    // top of the book.
    _needsTitleSpace = anchor == 0;
    paginateUntilPages(minPages);
  }

  /// Book-wide 1-based page estimate for local page [page] of this window.
  ///
  /// Derived from the book's character ratio rather than measured, so it is
  /// honest to display with a "约" marker whenever [isAnchored].
  int globalPageFor(int page) {
    final perPage = _sampleCharsPerPage();
    if (perPage <= 0) return page + 1;
    final before = _charsBeforeAnchor ??= _charsBefore(_anchorParagraph);
    final estimated = (before / perPage).round() + page + 1;
    return estimated < 1 ? 1 : estimated;
  }

  /// Book-wide page-count estimate, scaled from the local window.
  int get estimatedGlobalPageCount {
    final total = _totalChars ??= _countChars();
    final perPage = _sampleCharsPerPage();
    if (total <= 0 || perPage <= 0) return pageCount;
    final estimated = (total / perPage).round();
    return estimated < pageCount ? pageCount : estimated;
  }

  /// Total characters in the book.
  int _countChars() {
    if (book.usesLazyContent) return book.totalCharCount;
    final total = book.paragraphs.length;
    var sum = 0;
    for (var i = 0; i < total; i++) {
      sum += book.paragraphs[i].length;
    }
    return sum;
  }

  /// Characters before [paragraphIndex].
  int _charsBefore(int paragraphIndex) {
    final paragraphs = book.paragraphs;
    if (paragraphs is LazyParagraphs) {
      return paragraphs.charactersBefore(paragraphIndex);
    }
    final limit = paragraphIndex.clamp(0, book.paragraphs.length);
    var sum = 0;
    for (var i = 0; i < limit; i++) {
      sum += book.paragraphs[i].length;
    }
    return sum;
  }

  /// Characters per page, taken from the window measured so far.
  double _sampleCharsPerPage() {
    final sampled = _sampledCharsPerPage;
    if (sampled != null) return sampled;
    final pages = pageCount;
    final measured = _nextParagraph - _anchorParagraph;
    if (pages <= 1 || measured <= 0) return 1200;
    var chars = 0;
    for (var i = _anchorParagraph; i < _nextParagraph; i++) {
      chars += book.paragraphs[i].length;
    }
    _sampledParagraphs = measured;
    final perPage = chars / pages;
    return _sampledCharsPerPage = perPage < 1 ? 1.0 : perPage;
  }

  /// Widens the anchored window until its characters-per-page sample is
  /// representative, so book-wide page numbers settle instead of drifting.
  ///
  /// Bounded by [maxPages] and meant for the UI thread: it measures at most a few
  /// hundred paragraphs, three orders of magnitude below folding the book.
  void calibrateEstimate({int maxPages = 80}) {
    if (!isAnchored) return;
    if (_sampledParagraphs >= _calibrationParagraphs) return;
    _sampledCharsPerPage = null;
    _sampledParagraphs = 0;
    final targetPages = pageCount + maxPages;
    var guard = 0;
    while (!_finished &&
        pageCount < targetPages &&
        _nextParagraph - _anchorParagraph < _calibrationParagraphs &&
        guard < 200) {
      paginateSlice(maxParagraphs: 50);
      guard++;
    }
    _sampleCharsPerPage();
  }

  /// Ensure at least [minPages] exact pages exist.
  void paginateUntilPages(int minPages) {
    var guard = 0;
    while (!_finished && pageCount < minPages && guard < 20000) {
      paginateSlice(maxParagraphs: 25);
      guard++;
    }
  }

  /// 0-based page that contains [paragraphIndex], if already measured.
  int? exactPageForParagraph(int paragraphIndex) =>
      _paragraphFirstPage[paragraphIndex];

  /// 1-based page label plus whether it is measured or estimated.
  ///
  /// While anchored, only the current window is measured; anything before the
  /// anchor is placed by the character ratio, so it is reported as an estimate.
  ({int page1, bool exact}) pageRefForParagraph(int paragraphIndex) {
    final exact = _paragraphFirstPage[paragraphIndex];
    if (exact != null) {
      return isAnchored
          ? (page1: globalPageFor(exact), exact: false)
          : (page1: exact + 1, exact: true);
    }
    if (_finished || pageCount <= 0) {
      final last = pageCount <= 0 ? 1 : pageCount;
      return (
        page1: isAnchored ? globalPageFor(last - 1) : last,
        exact: _finished && !isAnchored,
      );
    }
    final totalParas = book.paragraphs.length;
    final done = _nextParagraph.clamp(1, totalParas);
    final avg = pageCount / done;
    final est = (paragraphIndex * avg).floor();
    final clamped = est.clamp(0, estimatedTotalPageCount - 1);
    return (
      page1: isAnchored ? globalPageFor(clamped) : clamped + 1,
      exact: false,
    );
  }

  void _newPage() {
    // Freeze the page just finished, then start an empty one.
    final finishedCount = _pageFragmentCount;
    _fragmentWords.addAll(_pendingFragment);
    _pages[_pages.length - 1] = finishedCount;
    _pages
      ..add(_pendingStart + finishedCount)
      ..add(0);
    _pendingStart += finishedCount;
    _pendingFragment.clear();
    _pass++;
    _usedHeight = 0;
  }

  void _remember(int paragraphIndex) {
    _paragraphFirstPage.putIfAbsent(paragraphIndex, () => pageCount - 1);
  }

  void _paginateParagraph(int index) {
    final availableHeight = _config.usableHeight;
    final contentWidth = _config.contentWidth;
    final source = book.paragraphs[index];
    final hasImage = book.imageBytes.containsKey(index);
    final hasBlockImage =
        hasImage && ReaderMarkup.isStandaloneImageParagraph(source);
    final hasLink = book.linkTargets[index] != null;
    final imageHeight = hasBlockImage ? _contentSize.height * .36 + 12 : 0.0;
    final linkHeight = hasLink ? 30.0 : 0.0;
    final isTocEntry = _tocParagraphs.contains(index);
    final headingLevel = ReaderMarkup.effectiveHeadingLevel(
      paragraph: source,
      fullParagraph: source,
      isTocEntry: isTocEntry,
    );
    final headingChrome = ReaderMarkup.headingChromeHeight(headingLevel);
    if (headingLevel != null && headingLevel <= 2 && !_pageIsEmpty) {
      _newPage();
    }

    // Inter-paragraph gap is charged when content is laid onto a non-empty
    // page. It is never reserved at the page bottom: the last fragment on a
    // page has 0 bottom padding in the render tree, so a trailing +22 left
    // every page visibly short — worst on long sentences split mid-way.
    double gapBefore() => _pageIsEmpty ? 0.0 : 22.0;

    if (source.isEmpty) {
      // Empty paragraphs render as a 22px step (bottom pad when not last).
      final body = 22 + imageHeight + linkHeight + headingChrome;
      if (_usedHeight + gapBefore() + body > availableHeight && !_pageIsEmpty) {
        _newPage();
      }
      final gap = gapBefore();
      _addFragment([
        index,
        0,
        0,
        0,
        0,
        _flagIndent | (hasImage ? _flagImage : 0) | (hasLink ? _flagLink : 0),
      ]);
      _remember(index);
      _usedHeight += gap + body;
      return;
    }

    final plainSource = ReaderMarkup.stripAllMarkers(source);
    // Same indent rule as ReaderParagraph — measure with the same prefix
    // the page will render, or page-mode layout drifts from scroll.
    final isQuote = ReaderMarkup.quote.hasMatch(source);
    final isList = ReaderMarkup.list.hasMatch(source);
    final isCenter = ReaderMarkup.center.hasMatch(source);
    final isHeading = headingLevel != null;
    final willIndent = ReaderMarkup.shouldIndentFirstLine(
      paragraph: source,
      fullParagraph: source,
      headingLevel: headingLevel,
      isQuote: isQuote,
      isList: isList,
      isCenter: isCenter,
    );
    // Justification handles the first line's visual spacing. Keep the indent
    // in the measured text so CJK line breaks remain identical to rendering.
    final displaySource = plainSource.isEmpty
        ? plainSource
        : (willIndent
              ? '${ReaderMarkup.indentPrefixFor(plainSource)}$plainSource'
              : plainSource);
    final measureStyle = isHeading
        ? TextStyle(
            fontFamily: _config.fontFamily,
            fontSize:
                _config.fontSize * ReaderMarkup.headingFontScale(headingLevel),
            height: ReaderMarkup.headingLineHeight(headingLevel),
            fontWeight: FontWeight.w700,
          )
        : _config.measureStyle;
    final painter = TextPainter(
      text: TextSpan(text: displaySource, style: measureStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    final lines = painter.computeLineMetrics();
    var lineStart = 0;
    var firstFragment = true;

    for (var lineIndex = 0; lineIndex < lines.length;) {
      final fragmentStart = lineStart;
      var fragmentHeight = 0.0;
      var fragmentEnd = lineStart;
      final prefixHeight = firstFragment ? imageHeight + headingChrome : 0.0;
      // Continuations of a split sentence: no leading gap, no indent.
      final leadGap = firstFragment ? gapBefore() : 0.0;

      while (lineIndex < lines.length) {
        final nextHeight = fragmentHeight + lines[lineIndex].height;
        final isLastLine = lineIndex == lines.length - 1;
        // No trailing paragraph gap here — only the link chrome on the
        // paragraph's final line. Filling the page must not leave 22px idle.
        final linkCost = isLastLine ? linkHeight : 0.0;
        final wouldFit =
            _usedHeight + leadGap + prefixHeight + nextHeight + linkCost <=
            availableHeight;
        if (!wouldFit && fragmentEnd != fragmentStart) break;
        fragmentHeight = nextHeight;
        fragmentEnd = painter
            .getPositionForOffset(
              Offset(contentWidth, lines[lineIndex].baseline),
            )
            .offset;
        lineIndex++;
        if (!wouldFit) break;
      }

      if (fragmentEnd == fragmentStart) {
        // Nothing committed (should be rare): open a fresh page and retry.
        if (!_pageIsEmpty) {
          _newPage();
          continue;
        }
        // Empty page still cannot hold the first line — commit it anyway so
        // the pager always makes progress.
        fragmentHeight = lines[lineIndex].height;
        fragmentEnd = painter
            .getPositionForOffset(
              Offset(contentWidth, lines[lineIndex].baseline),
            )
            .offset;
        lineIndex++;
      }

      final isLastFragment = lineIndex == lines.length;
      final needed =
          leadGap +
          prefixHeight +
          fragmentHeight +
          (isLastFragment ? linkHeight : 0.0);
      if (_usedHeight + needed > availableHeight && !_pageIsEmpty) {
        // The last lines do not fit after all. Remember what this fragment
        // covers — the retry below rewinds `lineIndex`, which would otherwise
        // move `fragmentStart` and silently drop this fragment when the lines
        // are re-checked against the fresh page.
        final keptEnd = fragmentEnd;
        lineStart = fragmentStart;
        final retryLine = lines.indexWhere(
          (line) =>
              painter
                  .getPositionForOffset(Offset(contentWidth, line.baseline))
                  .offset >
              fragmentStart,
        );
        lineIndex = retryLine < 0 ? lineIndex : retryLine;
        _newPage();
        fragmentEnd = keptEnd;
        continue;
      }

      // Store the slice bounds, not the text: the string is cut only when this
      // page is actually rendered.
      _addFragment([
        index,
        fragmentStart,
        fragmentEnd,
        willIndent ? ReaderMarkup.indentPrefixLengthFor(plainSource) : 0,
        0,
        _flagTextSlice |
            (firstFragment ? 0 : _flagCompact) |
            (firstFragment && willIndent ? _flagIndent : 0) |
            (firstFragment && hasImage ? _flagImage : 0) |
            (isLastFragment && hasLink ? _flagLink : 0),
      ]);
      _remember(index);
      _usedHeight += needed;
      lineStart = fragmentEnd;
      firstFragment = false;
    }
  }
}

double measureTitleHeight(PageLayoutConfig config) {
  final painter = TextPainter(
    text: TextSpan(
      text: config.title,
      style: TextStyle(
        fontFamily: config.fontFamily,
        fontSize: config.fontSize + 9,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: config.contentWidth);
  return painter.height;
}

/// `List<List<PageFragment>>` view over the pager's packed bounds.
///
/// Only `length` and the pages the reader actually renders are touched; each
/// index builds (and briefly caches) that page.
class _PagesView extends ListBase<List<PageFragment>> {
  _PagesView(this._pager);

  final ProgressiveBookPager _pager;

  @override
  int get length => _pager.pageCount;

  @override
  set length(int value) => throw UnsupportedError('pages are read-only');

  @override
  List<PageFragment> operator [](int index) => _pager.fragmentsOfPage(index);

  @override
  void operator []=(int index, List<PageFragment> value) =>
      throw UnsupportedError('pages are read-only');
}
