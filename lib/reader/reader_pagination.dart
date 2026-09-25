import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../util/text_slices.dart';
import 'reader_markup.dart';
import 'reader_models.dart';

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
class ProgressiveBookPager {
  ProgressiveBookPager(this.book, PageLayoutConfig config)
    : _config = config,
      _contentSize = Size(config.contentWidth, config.screenHeight) {
    reset();
  }

  final ImportedBook book;
  final PageLayoutConfig _config;
  final Size _contentSize;

  final List<List<PageFragment>> pages = [];
  final Map<int, int> _paragraphFirstPage = {};
  int _nextParagraph = 0;
  bool _finished = false;
  double _usedHeight = 0;
  bool _needsTitleSpace = true;

  bool get fullyPaginated => _finished;
  int get pageCount => pages.isEmpty ? 1 : pages.length;
  int get nextParagraph => _nextParagraph;

  /// Best-effort total page count for progress display / TOC estimates.
  int get estimatedTotalPageCount {
    if (_finished) return pageCount;
    final totalParas = book.paragraphs.length;
    if (totalParas <= 0) return pageCount;
    final done = _nextParagraph.clamp(1, totalParas);
    final avg = pages.length / done;
    final remaining = totalParas - done;
    final est = pages.length + (remaining * avg).round();
    return est.clamp(pageCount, pages.length + totalParas + 2);
  }

  void reset() {
    pages
      ..clear()
      ..add([]);
    _paragraphFirstPage.clear();
    _nextParagraph = 0;
    _finished = false;
    _usedHeight = 0;
    _needsTitleSpace = true;
  }

  /// Paginate up to [maxParagraphs] more source paragraphs.
  /// Returns true when more book content remains.
  bool paginateSlice({int maxParagraphs = 30}) {
    if (_finished) return false;
    if (pages.isEmpty) pages.add([]);
    if (_needsTitleSpace) {
      _usedHeight = measureTitleHeight(_config) + 30;
      _needsTitleSpace = false;
    }
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

  /// Ensure at least [minPages] exact pages exist.
  void paginateUntilPages(int minPages) {
    var guard = 0;
    while (!_finished && pages.length < minPages && guard < 20000) {
      paginateSlice(maxParagraphs: 25);
      guard++;
    }
  }

  /// 0-based page that contains [paragraphIndex], if already measured.
  int? exactPageForParagraph(int paragraphIndex) =>
      _paragraphFirstPage[paragraphIndex];

  /// 1-based page label plus whether it is measured or estimated.
  ({int page1, bool exact}) pageRefForParagraph(int paragraphIndex) {
    final exact = _paragraphFirstPage[paragraphIndex];
    if (exact != null) return (page1: exact + 1, exact: true);
    if (_finished || pages.isEmpty) {
      final last = pages.isEmpty ? 0 : pages.length - 1;
      return (page1: last + 1, exact: _finished);
    }
    final totalParas = book.paragraphs.length;
    final done = _nextParagraph.clamp(1, totalParas);
    final avg = pages.length / done;
    final est = (paragraphIndex * avg).floor();
    final clamped = est.clamp(0, estimatedTotalPageCount - 1);
    return (page1: clamped + 1, exact: false);
  }

  void _newPage() {
    pages.add([]);
    _usedHeight = 0;
  }

  void _remember(int paragraphIndex) {
    _paragraphFirstPage.putIfAbsent(paragraphIndex, () => pages.length - 1);
  }

  void _paginateParagraph(int index) {
    final availableHeight = _config.usableHeight;
    final contentWidth = _config.contentWidth;
    final source = book.paragraphs[index];
    final hasImage = book.imageBytes[index] != null;
    final hasBlockImage =
        hasImage && ReaderMarkup.isStandaloneImageParagraph(source);
    final hasLink = book.linkTargets[index] != null;
    final imageHeight = hasBlockImage ? _contentSize.height * .36 + 12 : 0.0;
    final linkHeight = hasLink ? 30.0 : 0.0;
    final isTocEntry = book.tocEntries.any(
      (entry) => entry.paragraphIndex == index,
    );
    final headingLevel = ReaderMarkup.effectiveHeadingLevel(
      paragraph: source,
      fullParagraph: source,
      isTocEntry: isTocEntry,
    );
    final headingChrome = ReaderMarkup.headingChromeHeight(headingLevel);
    if (headingLevel != null && headingLevel <= 2 && pages.last.isNotEmpty) {
      _newPage();
    }

    // Inter-paragraph gap is charged when content is laid onto a non-empty
    // page. It is never reserved at the page bottom: the last fragment on a
    // page has 0 bottom padding in the render tree, so a trailing +22 left
    // every page visibly short — worst on long sentences split mid-way.
    double gapBefore() => pages.last.isEmpty ? 0.0 : 22.0;

    if (source.isEmpty) {
      // Empty paragraphs render as a 22px step (bottom pad when not last).
      final body = 22 + imageHeight + linkHeight + headingChrome;
      if (_usedHeight + gapBefore() + body > availableHeight &&
          pages.last.isNotEmpty) {
        _newPage();
      }
      final gap = gapBefore();
      pages.last.add(
        PageFragment(
          paragraphIndex: index,
          text: '',
          showImage: hasImage,
          showLinkAction: hasLink,
        ),
      );
      _remember(index);
      _usedHeight += gap + body;
      return;
    }

    final plainSource = ReaderMarkup.stripAllMarkers(source);
    // Same indent rule as ReaderParagraph — measure with the same prefix
    // prefix the page will render, or page-mode layout drifts from scroll.
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
        if (pages.last.isNotEmpty) {
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
      if (_usedHeight + needed > availableHeight && pages.last.isNotEmpty) {
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
        continue;
      }

      pages.last.add(
        PageFragment(
          paragraphIndex: index,
          text: sliceDisplayText(
            plainSource,
            fragmentStart,
            fragmentEnd,
            indentPrefixLength: willIndent
                ? ReaderMarkup.indentPrefixLengthFor(plainSource)
                : 0,
          ),
          indentFirstLine: firstFragment && willIndent,
          showImage: firstFragment && hasImage,
          showLinkAction: isLastFragment && hasLink,
          // Mid-sentence continuations skip the inter-paragraph 22px step.
          compactPadding: !firstFragment,
        ),
      );
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
