/// Shared reader markup markers and display-text helpers.
abstract final class ReaderMarkup {
  static final RegExp inlineImage = RegExp(r'\[\[image:\d+\]\]');
  static final RegExp heading = RegExp(r'^\[\[vellum-heading:([1-6])\]\]');
  static final RegExp quote = RegExp(r'^(?:\[\[vellum-quote\]\])+');
  static final RegExp list = RegExp(r'^(?:\[\[vellum-list\]\])+');
  static final RegExp center = RegExp(r'^(?:\[\[vellum-center\]\])+');
  static final RegExp inlineTag = RegExp(r'\[\[/?[biu]\]\]');

  static String readerText(String source) => source
      .replaceFirst(heading, '')
      .replaceFirst(quote, '')
      .replaceFirst(center, '')
      .replaceFirst(list, '• ')
      .replaceAll(inlineTag, '');

  static String layoutText(String source) =>
      readerText(source).replaceAll(inlineImage, '￼');

  static bool isStandaloneImageParagraph(String source) =>
      stripAllMarkers(source).trim().isEmpty;

  static String stripAllMarkers(String source) => source
      .replaceAll(heading, '')
      .replaceAll(quote, '')
      .replaceAll(center, '')
      .replaceAll(list, '')
      .replaceAll(inlineTag, '')
      .replaceAll(inlineImage, '');

  /// TOC filepos / synthetic entries can land on body prose. A paragraph is a
  /// heading only when the *text itself* looks like a chapter title — not
  /// merely because some TOC row points at it.
  static bool looksLikeHeadingText(String source) {
    final plain = source.trim();
    if (plain.isEmpty || plain.length > 48) return false;
    return !plain.contains('。') &&
        !plain.contains('，') &&
        !plain.contains('？') &&
        !plain.contains('！') &&
        !plain.contains('；') &&
        !plain.contains(';');
  }

  static final RegExp _chapterTitle = RegExp(
    r'^(第[0-9一二三四五六七八九十百千万零〇两壹贰叁肆伍陆柒捌玖拾]{1,12}'
    r'(?:章节|章|册|卷|部|回|节|回合|集|篇|话)|'
    r'(?:Chapter|CHAPTER|Part|PART)\s*\d+|'
    r'序章|序言|前言|引子|楔子|尾声|后记|番外|附录|后序|跋|内容简介|作品简介)$',
  );

  /// True when [plain] is title-shaped (chapter head, short label), not body.
  static bool looksLikeChapterTitle(String plain) {
    final t = plain.trim();
    if (t.isEmpty || t.length > 40) return false;
    if (_chapterTitle.hasMatch(t)) return true;
    if (RegExp(r'^【[^】]{1,20}】$').hasMatch(t)) return true;
    if (RegExp(r'^\[[^\]]{1,20}\]$').hasMatch(t)) return true;
    // Short punctuation-free labels only. Any sentence punctuation (CJK or
    // ASCII) means prose — short dialogue like 「好」 still indents unless it
    // matches the chapter-head regex above.
    return t.length <= 16 &&
        !t.contains('。') &&
        !t.contains('，') &&
        !t.contains('？') &&
        !t.contains('！') &&
        !t.contains('；') &&
        !t.contains('、') &&
        !t.contains(',') &&
        !t.contains(';') &&
        !t.contains('…') &&
        !t.contains('.') &&
        !t.contains('!') &&
        !t.contains('?');
  }

  /// Body prose that must receive the two-space first-line indent even when a
  /// decoder slapped center flags on the whole book layout.
  static bool looksLikeBodyProse(String plain) {
    final t = plain.trim();
    if (t.isEmpty) return false;
    if (_chapterTitle.hasMatch(t)) return false;
    if (t.contains('。') ||
        t.contains('！') ||
        t.contains('？') ||
        t.contains('…') ||
        t.contains('!') ||
        t.contains('?') ||
        t.contains('.')) {
      return true;
    }
    if (t.length >= 40) return true;
    return t.length >= 24 &&
        (t.contains('，') || t.contains('、') || t.contains(','));
  }

  /// CJK first-line indent (two ideographic spaces).
  static const String cjkIndent = '\u3000\u3000';

  /// English first-line indent: 1em, market standard for Latin prose.
  static const String latinIndent = '\u2003';

  /// True when [text] is Latin-script body (English books). Latin letters
  /// must not be outnumbered by CJK ideographs; empty/punctuation-only
  /// text falls back to false (CJK indent rules apply).
  ///
  /// Counts only visible prose — `[[image:N]]` and other markers must not
  /// vote Latin (the word "image" used to flip CJK paragraphs).
  static bool isLatinBody(String text) {
    var latin = 0;
    var cjk = 0;
    for (final rune in stripAllMarkers(text).runes) {
      if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          (rune >= 0xC0 && rune <= 0x24F)) {
        latin++;
      } else if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF)) {
        cjk++;
      }
    }
    return latin > 0 && latin >= cjk;
  }

  /// First-line indent string for [plain] under the market typography split:
  /// Latin books get a 1em indent, CJK gets the two-em indent.
  static String indentPrefixFor(String plain) =>
      isLatinBody(plain) ? latinIndent : cjkIndent;

  static int indentPrefixLengthFor(String plain) => indentPrefixFor(plain).length;

  /// Source already carries a first-line indent — display must not double it.
  static bool alreadyHasFirstLineIndent(String source) {
    final t = readerText(source);
    if (t.isEmpty) return false;
    return t.startsWith('　') ||
        t.startsWith('\u2003') ||
        t.startsWith('\u00A0') ||
        t.startsWith('\u2007') ||
        t.startsWith('\t') ||
        RegExp(r'^ {2,}').hasMatch(t);
  }

  /// Shared rule for render + pagination.
  ///
  /// **Default is indent.** Chinese (and most western) body paragraphs get
  /// `　　` unless they are clearly not body: real headings, quotes, lists,
  /// already-indented source, empty/image lines, or centered title labels.
  /// Do not require “looks like prose” — short dialogue and English lines
  /// that end with `.` must still indent, or whole books read flush-left.
  static bool shouldIndentFirstLine({
    required String paragraph,
    required String fullParagraph,
    required int? headingLevel,
    required bool isQuote,
    required bool isList,
    required bool isCenter,
  }) {
    if (headingLevel != null) return false;
    if (isQuote) return false;
    if (isList) return false;
    if (alreadyHasFirstLineIndent(paragraph) ||
        alreadyHasFirstLineIndent(fullParagraph)) {
      return false;
    }
    final plain = readerText(fullParagraph).trim();
    if (plain.isEmpty) return false;
    // Standalone image / marker-only paragraphs stay unindented.
    if (stripAllMarkers(fullParagraph).trim().isEmpty) return false;
    // Explicit chapter heads stay flush (第N章 / Chapter N / 前言…).
    if (_chapterTitle.hasMatch(plain)) return false;
    // Centered short title-like labels stay flush; long centered body
    // (whole-book text-align:center EPUBs) still indents.
    if (isCenter && looksLikeChapterTitle(plain)) return false;
    return true;
  }

  static int? effectiveHeadingLevel({
    required String paragraph,
    required String fullParagraph,
    required bool isTocEntry,
  }) {
    final match =
        heading.firstMatch(paragraph) ?? heading.firstMatch(fullParagraph);
    final level = int.tryParse(match?.group(1) ?? '');
    if (level != null) return level;
    if (!isTocEntry) return null;
    final plain = readerText(fullParagraph).trim();
    // TOC target is a heading only when the paragraph itself is title-shaped.
    // Synthetic 第N章 markers that land on body prose must keep indent.
    if (_chapterTitle.hasMatch(plain) || looksLikeChapterTitle(plain)) return 2;
    return null;
  }

  /// Vertical chrome ReaderParagraph adds around headings.
  static double headingChromeHeight(int? level) {
    if (level == null) return 0;
    return (level <= 2 ? 10 : 6) + 8;
  }

  static double headingFontScale(int level) {
    switch (level) {
      case 1:
        return 1.5;
      case 2:
        return 1.3;
      case 3:
        return 1.16;
      case 4:
        return 1.08;
      default:
        return 1.04;
    }
  }

  static double headingLineHeight(int level) => switch (level) {
    1 => 1.22,
    2 => 1.28,
    _ => 1.35,
  };
}
