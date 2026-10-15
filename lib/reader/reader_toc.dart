import '../services/book_importer.dart';
import '../services/html_text_pipeline.dart';

const _pipeline = HtmlTextPipeline();

/// Chapter entries from structured TOC or Chinese chapter-title heuristics.
///
/// Titles are cleaned here rather than only in the decoders, so books imported
/// before that cleanup existed are repaired as well.
List<MapEntry<int, String>> chapterEntries(ImportedBook book) {
  // Lazy books already had TOC cleanup performed in the import/migration
  // worker. Re-running anchor repair here would read every chapter at open.
  if (book.usesLazyContent) {
    return [
      for (final e in book.tocEntries) MapEntry(e.paragraphIndex, e.title),
    ];
  }
  if (book.tocEntries.isNotEmpty) {
    final entries = <MapEntry<int, String>>[];
    for (final raw in book.tocEntries) {
      final title = _pipeline.chapterTitle(raw.title);
      if (!_isNavigationTitle(title)) continue;
      final paragraph = _correctTocParagraph(book, raw.paragraphIndex, title);
      entries.add(MapEntry(paragraph, title));
    }
    // Keep the first occurrence per paragraph after anchor repair. MOBI filepos
    // values frequently point to the paragraph before the real heading; using
    // the corrected position keeps the reader, pager and TOC on one boundary.
    final seen = <int>{};
    final cleaned = <MapEntry<int, String>>[];
    for (final entry in entries) {
      if (!seen.add(entry.key)) continue;
      cleaned.add(entry);
    }
    cleaned.sort((a, b) => a.key.compareTo(b.key));
    return cleaned.isEmpty ? heuristicChapterEntries(book.paragraphs) : cleaned;
  }
  return heuristicChapterEntries(book.paragraphs);
}

/// Filters structured TOCs that contain explanatory footnotes alongside real
/// chapters. The source data remains untouched; this list is only used for
/// navigation and heading layout.
bool _isNavigationTitle(String title) {
  final value = title.trim();
  if (value.length < 2 || value.length > 60) return false;
  if (value.contains('�')) return false;
  // Footnote prose in MOBI files is usually a sentence, while real entries are
  // short labels. Keep punctuation-free structural labels even when they are
  // not numbered (appendices, galleries, production notes, author pages).
  final sentencePunctuation = RegExp(r'[。！？；，,!?…]').hasMatch(value);
  final structural = RegExp(
    r'^(?:第[0-9一二三四五六七八九十百千万零〇两壹贰叁肆伍陆柒捌玖拾]*'
    r'(?:章节|章|册|卷|部|回|节|回合|集|篇)|'
    r'(?:序章|序言|前言|引言|楔子|尾声|终章|后记|附录|目录|版权|作者|制作|说明|画廊|'
    r'神奇的|诗翁|哈利[·・ ]?波特百科|Chapter|CHAPTER|Part|PART))',
  ).hasMatch(value);
  if (sentencePunctuation && !structural) return false;
  if (value.length > 42 && !structural) return false;
  // Long labels without punctuation are still almost always prose when they
  // contain a clause separator or a run of ordinary sentence words.
  if (!structural && value.length > 28) return false;
  return true;
}

String _normaliseTocText(String value) => value
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[「」『』《》〈〉“”·・]'), '');

/// Repairs an anchor that lands immediately before/after a chapter heading.
/// A small window is sufficient for MOBI filepos drift and avoids scanning the
/// book or changing persisted paragraph indexes.
int _correctTocParagraph(ImportedBook book, int rawIndex, String title) {
  if (book.paragraphs.isEmpty) return 0;
  // MOBI appendices can be separated from their filepos marker by a cover,
  // image and metadata block. A bounded 96-paragraph window repairs those
  // anchors without turning TOC construction into a book-wide scan.
  final start = (rawIndex - 96).clamp(0, book.paragraphs.length - 1);
  final end = (rawIndex + 96).clamp(start, book.paragraphs.length - 1);
  final wanted = _normaliseTocText(title);
  var best = rawIndex.clamp(0, book.paragraphs.length - 1);
  var bestScore = -1;
  for (var index = start; index <= end; index++) {
    final candidate = _pipeline.chapterTitle(book.paragraphs[index]);
    if (candidate.isEmpty || !_isNavigationTitle(candidate)) continue;
    final normal = _normaliseTocText(candidate);
    var score = 0;
    if (normal == wanted) {
      score = 100;
    } else if (normal.startsWith(wanted) || wanted.startsWith(normal)) {
      score = 70;
    } else {
      final prefix = wanted.length.clamp(2, 12);
      if (normal.startsWith(wanted.substring(0, prefix))) score = 45;
    }
    if (score == 0) continue;
    score -= (index - rawIndex).abs();
    if (score > bestScore) {
      bestScore = score;
      best = index;
    }
  }
  return best;
}

/// Detects chapter headings from paragraph text alone.
///
/// Pattern aligned with Fanqie's TXT chapter regex (`ar5/a.java`): 第 + CJK or
/// Arabic numerals + 册/卷/部/章/回/节/回合. Fanqie also caps the title at ~30
/// chars and rejects lines that look like body prose.
List<MapEntry<int, String>> heuristicChapterEntries(List<String> paragraphs) {
  final patterns = <RegExp>[
    RegExp(
      r'^\s*.{0,20}第[0-9一二三四五六七八九十百千万零〇两壹贰叁肆伍陆柒捌玖拾]*'
      r'(章节|章|册|卷|部|回|节|回合|集|篇)',
    ),
    RegExp(r'^\s*(?:Chapter|CHAPTER|Part|PART)\s+\d+'),
    RegExp(r'^\s*[0-9]{1,3}\s*[\.、．]\s*\S'),
    RegExp(r'^\s*[【\[][^】\]]{1,24}[】\]]\s*$'),
  ];
  final entries = <MapEntry<int, String>>[];
  for (var index = 0; index < paragraphs.length; index++) {
    // Labels are matched after cleanup so a heading that still carries reader
    // markup ([[vellum-heading:1]]第二章) is still recognised.
    final value = _pipeline.chapterTitle(paragraphs[index]);
    if (value.isEmpty || value.length > 40) continue;
    // Skip body-looking lines that merely start with a number.
    if (value.contains('。') ||
        value.contains('，') ||
        value.contains(',') ||
        value.contains('！') ||
        value.contains('？')) {
      continue;
    }
    for (final pattern in patterns) {
      if (pattern.hasMatch(value)) {
        entries.add(MapEntry(index, value));
        break;
      }
    }
  }
  return entries;
}

Map<int, int> chapterStartPages(
  List<MapEntry<int, String>> chapters,
  int Function(int paragraphIndex) pageForParagraph,
) => {for (final entry in chapters) entry.key: pageForParagraph(entry.key) + 1};

/// 1-based page label for a chapter, marking estimates while paginating.
String chapterPageLabel({
  required int paragraphIndex,
  required int Function(int) exactPageForParagraph,
  required int Function(int) estimatedPageForParagraph,
  required bool fullyPaginated,
}) {
  if (fullyPaginated) {
    return '第 ${exactPageForParagraph(paragraphIndex) + 1} 页';
  }
  final exact = exactPageForParagraph(paragraphIndex);
  if (exact >= 0) return '第 ${exact + 1} 页';
  return '约第 ${estimatedPageForParagraph(paragraphIndex) + 1} 页';
}
