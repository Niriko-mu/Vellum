/// Full-text search over a book's paragraphs, for the reader's catalogue panel.
///
/// Books can be huge (a 二十四史-sized TXT is hundreds of thousands of
/// paragraphs), so the scan is a single pass over the paragraph list with an
/// early stop, and results are capped. Every hit carries short snippets instead
/// of the whole paragraph, so a long chapter never gets copied into the result
/// list.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'txt_catalog.dart';
import 'txt_seek_source.dart';

final _searchPaths = Expando<String>();

String? registeredBookSearchPath(List<String> paragraphs) =>
    _searchPaths[paragraphs];

/// Associate a loaded inline body with its persisted file. Workers read that
/// file directly, keeping the body out of UI-isolate message serialization.
void registerBookSearchPath(List<String> paragraphs, String path) {
  _searchPaths[paragraphs] = path;
}

String? bookContentPathFor(List<String> paragraphs) => _searchPaths[paragraphs];

class BookSearchTask {
  BookSearchTask({
    required List<String> paragraphs,
    required String query,
    required List<MapEntry<int, String>> chapters,
  }) {
    final message = <String, dynamic>{
      'port': _port.sendPort,
      'query': query,
      'chapters': chapters,
    };
    if (paragraphs is TxtParagraphList) {
      message['txtPath'] = paragraphs.source.file.path;
      message['catalog'] = paragraphs.catalog.toJson();
    } else if (_searchPaths[paragraphs] case final String path) {
      message['contentPath'] = path;
    } else {
      message['paragraphs'] = paragraphs;
    }
    _subscription = _port.listen((value) {
      if (value is SearchResults) {
        if (!_result.isCompleted) _result.complete(value);
      } else {
        if (!_result.isCompleted) _result.completeError(StateError('$value'));
      }
      _release();
    });
    Future<void>(() async {
      if (_closed) return;
      final worker = await Isolate.spawn(
        _searchWorker,
        message,
        onError: _port.sendPort,
      );
      if (_closed)
        worker.kill(priority: Isolate.immediate);
      else
        _worker = worker;
    }).then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (!_result.isCompleted) _result.completeError(error, stack);
        _release();
      },
    );
  }
  final _port = ReceivePort();
  final _result = Completer<SearchResults>();
  StreamSubscription<dynamic>? _subscription;
  Isolate? _worker;
  bool _closed = false;
  Future<SearchResults> get result => _result.future;
  void cancel() {
    if (!_result.isCompleted) _result.complete(SearchResults.empty);
    _release();
  }

  void _release() {
    _closed = true;
    _worker?.kill(priority: Isolate.immediate);
    _subscription?.cancel();
    _port.close();
  }
}

void _searchWorker(Map<String, dynamic> message) {
  TxtSeekSource? source;
  final port = message['port'] as SendPort;
  try {
    List<String> paragraphs;
    if (message['txtPath'] case final String path) {
      source = TxtSeekSource(
        file: File(path),
        catalog: TxtCatalog.fromJson(
          message['catalog'] as Map<String, dynamic>,
        ),
      );
      paragraphs = TxtParagraphList(source);
    } else if (message['contentPath'] case final String path) {
      final raw =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      paragraphs = (raw['paragraphs'] as List<dynamic>).cast<String>();
    } else {
      paragraphs = message['paragraphs'] as List<String>;
    }
    final result = searchBook(
      paragraphs: paragraphs,
      query: message['query'] as String,
      chapters: message['chapters'] as List<MapEntry<int, String>>,
    );
    source?.close();
    source = null;
    port.send(result);
  } catch (error) {
    port.send(error.toString());
  } finally {
    source?.close();
  }
}

/// One occurrence of the query inside a paragraph.
class SearchMatch {
  const SearchMatch({
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
    this.leadingContext = '',
    this.trailingContext = '',
    this.lineNumber = 1,
  });

  /// Text around the match, with `…` markers where it was cut.
  final String snippet;

  /// Where the match sits inside [snippet], for highlighting.
  final int matchStart;
  final int matchEnd;

  /// The lines just before and after the match's own line, for context.
  final String leadingContext;
  final String trailingContext;

  /// 1-based line number inside the paragraph (1 for single-line paragraphs).
  final int lineNumber;
}

/// One matching paragraph, with every occurrence inside it.
class SearchHit {
  const SearchHit({
    required this.paragraphIndex,
    required this.chapterTitle,
    required this.matches,
  });

  /// Paragraph to jump to.
  final int paragraphIndex;

  /// Chapter the paragraph belongs to ('' when the book has no chapters).
  final String chapterTitle;

  /// Every occurrence in this paragraph, in reading order (capped).
  final List<SearchMatch> matches;

  int get matchCount => matches.length;

  /// First occurrence, used for the collapsed row.
  SearchMatch get first => matches.first;
}

/// Book-wide result: paragraphs, occurrences, and whether the scan was cut off.
class SearchResults {
  const SearchResults({
    required this.hits,
    required this.totalOccurrences,
    required this.truncated,
  });

  static const SearchResults empty = SearchResults(
    hits: [],
    totalOccurrences: 0,
    truncated: false,
  );

  final List<SearchHit> hits;

  /// Occurrences counted across the reported hits.
  final int totalOccurrences;

  /// True when the scan stopped at the cap, so more matches may exist.
  final bool truncated;

  int get paragraphCount => hits.length;
  bool get isEmpty => hits.isEmpty;
}

/// Case-insensitive search over [paragraphs], in reading order.
///
/// CJK has no case, so folding only affects ASCII — which is what a reader
/// expects from a mixed-language book. Paragraph text is normalised the same way
/// as the query (whitespace runs collapsed) before offsets are taken, so a query
/// pasted from somewhere with odd spacing still highlights correctly.
SearchResults searchBook({
  required List<String> paragraphs,
  required String query,
  List<MapEntry<int, String>> chapters = const [],
  int maxParagraphs = 200,
  int maxMatchesPerParagraph = 6,
  int snippetRadius = 26,
  int contextLines = 1,
}) {
  final needle = normalizeQuery(query);
  if (needle.isEmpty || paragraphs.isEmpty || maxParagraphs <= 0) {
    return SearchResults.empty;
  }

  final hits = <SearchHit>[];
  var occurrences = 0;
  var scannedAll = true;
  for (var index = 0; index < paragraphs.length; index++) {
    final source = paragraphs[index];
    if (source.isEmpty) continue;
    final matches = _matchesIn(
      source: source,
      needle: needle,
      maxMatches: maxMatchesPerParagraph,
      snippetRadius: snippetRadius,
      contextLines: contextLines,
    );
    if (matches.isEmpty) continue;
    occurrences += matches.length;
    hits.add(
      SearchHit(
        paragraphIndex: index,
        chapterTitle: chapterTitleFor(chapters, index),
        matches: matches,
      ),
    );
    if (hits.length >= maxParagraphs) {
      scannedAll = false;
      break;
    }
  }

  return SearchResults(
    hits: hits,
    totalOccurrences: occurrences,
    truncated: !scannedAll,
  );
}

/// Convenience wrapper for callers that only want the matching paragraphs.
List<SearchHit> searchParagraphs({
  required List<String> paragraphs,
  required String query,
  List<MapEntry<int, String>> chapters = const [],
  int maxResults = 200,
  int snippetRadius = 28,
}) => searchBook(
  paragraphs: paragraphs,
  query: query,
  chapters: chapters,
  maxParagraphs: maxResults,
  snippetRadius: snippetRadius,
).hits;

/// Query form used for matching: trimmed, case folded, and with internal
/// whitespace runs collapsed so a pasted phrase still matches.
String normalizeQuery(String query) =>
    query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Paragraph form used for matching. Kept in step with [normalizeQuery] so a
/// query pasted with odd spacing still matches.
String _normalizeText(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<SearchMatch> _matchesIn({
  required String source,
  required String needle,
  required int maxMatches,
  required int snippetRadius,
  required int contextLines,
}) {
  // Fast path: most paragraphs are pure CJK with no whitespace runs, where
  // folding case is enough and the normalising pass would only cost time.
  final lower = source.toLowerCase();
  final needsNormalizing = _hasWhitespaceRun(source);
  final fastAt = lower.indexOf(needle);
  if (fastAt < 0 && !needsNormalizing) return const [];
  if (fastAt >= 0 && !needsNormalizing) {
    return _collect(
      source: source,
      hits: _Offsets(lower),
      needle: needle,
      maxMatches: maxMatches,
      snippetRadius: snippetRadius,
      contextLines: contextLines,
    );
  }
  // Slow path: the query or the paragraph has whitespace that must be collapsed
  // before offsets mean anything.
  final haystack = _normalizeText(source);
  if (!haystack.contains(needle)) return const [];
  return _collect(
    source: source,
    hits: _Offsets(haystack),
    needle: needle,
    maxMatches: maxMatches,
    snippetRadius: snippetRadius,
    contextLines: contextLines,
    toDisplay: true,
  );
}

/// True when [text] contains a run of whitespace that collapsing would change.
bool _hasWhitespaceRun(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit > 0x20) continue;
    if (unit != 0x20) return true; // tab/newline always collapses
    if (i + 1 < text.length && text.codeUnitAt(i + 1) <= 0x20) return true;
  }
  return false;
}

/// The string offsets are searched in, with a flag for whether they need mapping
/// back onto the original text.
class _Offsets {
  const _Offsets(this.haystack);

  final String haystack;
}

List<SearchMatch> _collect({
  required String source,
  required _Offsets hits,
  required String needle,
  required int maxMatches,
  required int snippetRadius,
  required int contextLines,
  bool toDisplay = false,
}) {
  final haystack = hits.haystack;
  final matches = <SearchMatch>[];
  var from = 0;
  while (matches.length < maxMatches) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    final end = at + needle.length;
    // The snippet and context are always cut from the original text, so the
    // reader sees the paragraph as written — matching may use a folded copy.
    final offsets = toDisplay
        ? displayOffsets(source, at, end)
        : (start: at, end: end);
    final snippet = _snippet(
      source,
      offsets.start,
      offsets.end,
      radius: snippetRadius,
    );
    final context = _contextLines(source, offsets.start, lines: contextLines);
    matches.add(
      SearchMatch(
        snippet: snippet.text,
        matchStart: snippet.start,
        matchEnd: snippet.end,
        leadingContext: context.leading,
        trailingContext: context.trailing,
        lineNumber: context.lineNumber,
      ),
    );
    // Never loop on a zero-width match.
    from = end > at ? end : at + 1;
  }
  return matches;
}

/// Maps offsets in the whitespace-collapsed text back onto [source].
///
/// Collapsing turns newlines and runs of spaces into single spaces, so the raw
/// indexes shift; this walks both strings together instead of guessing.
({int start, int end}) displayOffsets(String source, int start, int end) {
  var raw = 0;
  var collapsed = 0;
  var rawStart = -1;
  var rawEnd = -1;
  while (raw <= source.length) {
    if (collapsed == start && rawStart < 0) rawStart = raw;
    if (collapsed == end && rawEnd < 0) {
      rawEnd = raw;
      break;
    }
    if (raw >= source.length) break;
    final isSpace = source.codeUnitAt(raw) <= 0x20;
    if (isSpace) {
      // A whitespace run collapses to exactly one space in the collapsed text.
      var next = raw;
      while (next < source.length && source.codeUnitAt(next) <= 0x20) {
        next++;
      }
      collapsed++;
      raw = next;
    } else {
      collapsed++;
      raw++;
    }
  }
  final from = rawStart < 0 ? source.length : rawStart;
  final to = rawEnd < 0 ? source.length : rawEnd;
  return (start: from, end: to < from ? from : to);
}

/// Short window of [text] around a match, plus where the match sits in it.
({String text, int start, int end}) _snippet(
  String text,
  int matchStart,
  int matchEnd, {
  required int radius,
}) {
  var start = matchStart - radius;
  var end = matchEnd + radius;
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  start = start.clamp(0, text.length);
  end = end.clamp(start, text.length);
  final body = text.substring(start, end);
  return (
    text: '$prefix$body$suffix',
    start: prefix.length + (matchStart - start),
    end: prefix.length + (matchEnd - start),
  );
}

/// The lines just before and after the match's own line.
///
/// The snippet answers "is this the passage I meant"; these lines answer "what
/// does it say around it", which is what a reader wants before jumping.
({String leading, String trailing, int lineNumber}) _contextLines(
  String text,
  int matchStart, {
  required int lines,
}) {
  if (lines <= 0) return (leading: '', trailing: '', lineNumber: 1);

  // Line starts, so a paragraph containing hard breaks can be described by line.
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
  }
  var lineIndex = 0;
  for (var i = 0; i < starts.length; i++) {
    if (starts[i] <= matchStart) {
      lineIndex = i;
    } else {
      break;
    }
  }

  String lineAt(int index) {
    if (index < 0 || index >= starts.length) return '';
    final start = starts[index];
    final end = index + 1 < starts.length ? starts[index + 1] : text.length;
    final slice = text.substring(start, end.clamp(start, text.length));
    return slice.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final leading = [
    for (var i = lineIndex - lines; i < lineIndex; i++)
      if (i >= 0) lineAt(i),
  ].where((line) => line.isNotEmpty).toList();
  final trailing = [
    for (var i = lineIndex + 1; i <= lineIndex + lines; i++) lineAt(i),
  ].where((line) => line.isNotEmpty).toList();

  return (
    leading: leading.join('\n'),
    trailing: trailing.join('\n'),
    lineNumber: lineIndex + 1,
  );
}

/// Chapter title that owns [paragraphIndex], via binary search over the chapter
/// starts (which are ordered by construction).
String chapterTitleFor(
  List<MapEntry<int, String>> chapters,
  int paragraphIndex,
) {
  if (chapters.isEmpty) return '';
  var low = 0;
  var high = chapters.length - 1;
  var found = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (chapters[mid].key <= paragraphIndex) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found < 0 ? '' : chapters[found].value;
}

/// One chapter's worth of hits.
class SearchGroup {
  const SearchGroup({required this.title, required this.hits});

  /// Chapter title; '' when the book has no chapters.
  final String title;
  final List<SearchHit> hits;

  int get occurrences => hits.fold(0, (sum, hit) => sum + hit.matchCount);
}

/// Search hits grouped by chapter, in reading order.
///
/// A reader looking for a passage thinks in chapters ("that bit in 卷三"), so the
/// list is grouped rather than a flat stream of paragraphs.
List<SearchGroup> groupHitsByChapter(List<SearchHit> hits) {
  final groups = <SearchGroup>[];
  String? current;
  List<SearchHit>? bucket;
  for (final hit in hits) {
    if (bucket == null || hit.chapterTitle != current) {
      bucket = <SearchHit>[];
      current = hit.chapterTitle;
      groups.add(SearchGroup(title: current, hits: bucket));
    }
    bucket.add(hit);
  }
  return groups;
}
