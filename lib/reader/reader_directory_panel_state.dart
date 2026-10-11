import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/book_search.dart';
import 'reader_models.dart';
import 'reader_directory_panel.dart';
import 'reader_directory_panel_rendering.dart';

class ReaderDirectoryPanelState extends State<ReaderDirectoryPanel> {
  var tab = 0;

  /// Fanqie-style catalog order toggle (正序/倒序).
  var descending = false;
  final scrollController = ScrollController();
  var didAutoScroll = false;
  var currentOffscreen = false;

  /// 全文搜索 state (catalogue tab only).
  var searching = false;
  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  final searchScrollController = ScrollController();
  String query = '';
  SearchResults results = SearchResults.empty;

  /// Paragraph of the result row the reader is stepping through, so the list can
  /// scroll to it and mark it.
  int? activeHit;

  /// Full-book scanning is a single pass over every paragraph — fast on a normal
  /// book, ~100 ms on a 二十四史-sized one — so typing waits for a short pause
  /// instead of scanning per keystroke.
  Timer? searchDebounce;
  BookSearchTask? _searchTask;
  int _searchGeneration = 0;

  /// Below this length the scan matches too much to be useful; CJK words are
  /// short, so two characters is the useful floor.
  static const int minQueryLength = 2;
  static const Duration searchDebounceDelay = Duration(milliseconds: 180);

  /// How long after the field takes focus a spontaneous loss still counts as the
  /// keyboard failing to settle, rather than the reader dismissing it.
  static const Duration _keyboardSettleWindow = Duration(seconds: 2);

  /// Delay before recovering from such a loss, so it cannot turn into a fight
  /// with a deliberate dismissal.
  static const Duration _keyboardRefocusDelay = Duration(milliseconds: 250);
  Timer? focusLossTimer;
  DateTime? searchOpenedAt;

  /// Estimated height of one result row, used to scroll a stepped-to hit into
  /// view (rows vary by a line or two; this only needs to be close).
  static const double _searchRowHeight = 96;

  /// Stable identity for the query field, so the element that owns the text
  /// input connection survives panel rebuilds (including a header layout swap
  /// while the soft keyboard animates the viewport).
  final searchFieldKey = GlobalKey(debugLabel: 'reader-search-field');

  bool get canSearch => (widget.paragraphs?.isNotEmpty ?? false);

  static const double itemExtent = ReaderDirectoryPanel.itemExtent;

  List<MapEntry<int, String>> get entries {
    final raw = tab == 0 ? widget.chapters : widget.bookmarks;
    if (!descending || raw.isEmpty) return raw;
    return raw.reversed.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    searchFocus.addListener(onSearchFocusChanged);
    scrollController.addListener(updateCurrentVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => autoScrollToCurrent());
  }

  @override
  void dispose() {
    _searchGeneration++;
    _searchTask?.cancel();
    searchDebounce?.cancel();
    focusLossTimer?.cancel();
    searchFocus.removeListener(onSearchFocusChanged);
    if (searching) widget.onSearchingChanged?.call(false);
    scrollController.removeListener(updateCurrentVisibility);
    scrollController.dispose();
    searchScrollController.dispose();
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReaderDirectoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentParagraph != widget.currentParagraph ||
        oldWidget.chapters != widget.chapters) {
      didAutoScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) autoScrollToCurrent();
      });
    }
  }

  void openSearch() {
    setState(() {
      searching = true;
      query = '';
      results = SearchResults.empty;
      activeHit = null;
    });
    widget.onSearchingChanged?.call(true);
    // The query field mounts on the next frame, where its own `autofocus` claims
    // the caret and raises the keyboard. Asking the platform to show it from here
    // as well opened a second input session for the same field: Android finished
    // the first (`onFinishInputView`) and started another (`onStartInput`), which
    // is what left the keyboard flickering or never settling.
    WidgetsBinding.instance.addPostFrameCallback((_) => focusSearchField());
  }

  /// Refocuses the query field if it is on screen but has lost the caret
  /// (after clearing it, or switching tabs).
  ///
  /// It deliberately does not ask the platform to show the keyboard: the field's
  /// own `autofocus` already does that when it opens, and a second request opens
  /// a second input session for the same field. Android then finishes the first
  /// (`onFinishInputView`) and starts another (`onStartInput`) — the keyboard
  /// flicker in the device log.
  void focusSearchField() {
    if (!searching) return;
    final node = searchFocus;
    if (node.hasFocus) return;
    if (!node.canRequestFocus) return;
    node.requestFocus();
  }

  /// Watches for the keyboard being dropped shortly after it opens.
  ///
  /// The field keeps focus in every case we can reproduce, so a spontaneous loss
  /// means the platform's input session went away. One delayed refocus recovers
  /// from that without fighting the reader: dismissing the search (取消, the
  /// sheet grabber, tapping away) clears `searching` first, and a loss that
  /// happens after the keyboard has settled is left alone.
  void onSearchFocusChanged() {
    focusLossTimer?.cancel();
    if (searchFocus.hasFocus) {
      searchOpenedAt = DateTime.now();
      return;
    }
    if (!searching) return;
    final openedAt = searchOpenedAt;
    if (openedAt == null) return;
    if (DateTime.now().difference(openedAt) > _keyboardSettleWindow) return;
    focusLossTimer = Timer(_keyboardRefocusDelay, () {
      if (!mounted || !searching || searchFocus.hasFocus) return;
      searchFocus.requestFocus();
    });
  }

  void closeSearch() {
    _searchGeneration++;
    _searchTask?.cancel();
    searchDebounce?.cancel();
    focusLossTimer?.cancel();
    searchController.clear();
    setState(() {
      searching = false;
      query = '';
      results = SearchResults.empty;
      activeHit = null;
    });
    widget.onSearchingChanged?.call(false);
  }

  /// Restarts the debounce window; [runSearch] does the actual scan.
  void onQueryChanged(String value) {
    searchDebounce?.cancel();
    final query = value.trim();
    // Clearing or falling below the floor shows the prompt immediately.
    if (query.length < minQueryLength) {
      runSearch(value);
      return;
    }
    searchDebounce = Timer(searchDebounceDelay, () {
      if (mounted) runSearch(value);
    });
  }

  Future<void> runSearch(String value) async {
    searchDebounce?.cancel();
    _searchTask?.cancel();
    final generation = ++_searchGeneration;
    final nextQuery = value.trim();
    setState(() {
      query = nextQuery;
      results = SearchResults.empty;
      activeHit = null;
    });
    if (nextQuery.length < minQueryLength || widget.paragraphs == null) return;
    final task = BookSearchTask(
      paragraphs: widget.paragraphs!,
      query: nextQuery,
      chapters: widget.chapters,
    );
    _searchTask = task;
    try {
      final found = await task.result;
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        results = found;
        activeHit = results.isEmpty ? null : results.hits.first.paragraphIndex;
      });
      if (searchScrollController.hasClients) searchScrollController.jumpTo(0);
    } catch (_) {
      // Closing or replacing a query must never surface a stale worker failure.
      if (mounted && generation == _searchGeneration) {
        setState(() => results = SearchResults.empty);
      }
    }
  }

  /// Moves to the next/previous result, as one flat sequence over the grouped
  /// list, and scrolls it into view.
  void stepHit(int delta) {
    final hits = results.hits;
    if (hits.isEmpty) return;
    final current = hits.indexWhere((hit) => hit.paragraphIndex == activeHit);
    final next = current < 0
        ? (delta >= 0 ? 0 : hits.length - 1)
        : (current + delta).clamp(0, hits.length - 1);
    setState(() => activeHit = hits[next].paragraphIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) scrollSearchTo(hits[next].paragraphIndex);
    });
  }

  void scrollSearchTo(int paragraphIndex) {
    if (!searchScrollController.hasClients) return;
    final groups = groupHitsByChapter(results.hits);
    var row = 0;
    for (final group in groups) {
      row++; // chapter header
      for (final hit in group.hits) {
        if (hit.paragraphIndex == paragraphIndex) {
          final max = searchScrollController.position.maxScrollExtent;
          searchScrollController.animateTo(
            (row * _searchRowHeight).clamp(0.0, max),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
          );
          return;
        }
        row++;
      }
    }
  }

  void toggleOrder() {
    setState(() {
      descending = !descending;
      didAutoScroll = false;
      currentOffscreen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => autoScrollToCurrent());
  }

  int currentDisplayIndex() {
    if (tab != 0) return -1;
    final chapterEntries = entries;
    for (var index = 0; index < chapterEntries.length; index++) {
      if (isCurrentChapter(chapterEntries[index].key, index, chapterEntries))
        return index;
    }
    return -1;
  }

  void updateCurrentVisibility() {
    if (!mounted || !scrollController.hasClients || tab != 0) return;
    final target = currentDisplayIndex();
    if (target < 0) return;
    final first = (scrollController.offset / itemExtent).floor();
    final visible = (scrollController.position.viewportDimension / itemExtent)
        .ceil();
    final last = first + visible - 1;
    final offscreen = target < first - 1 || target > last + 1;
    if (offscreen != currentOffscreen) {
      setState(() => currentOffscreen = offscreen);
    }
  }

  /// Current chapter in the *displayed* list order (handles 倒序).
  bool isCurrentChapter(
    int paragraphIndex,
    int index,
    List<MapEntry<int, String>> entries,
  ) {
    final current = widget.currentParagraph;
    if (descending) {
      // Displayed[i] is original[n-1-i]. Range is (prevDisplay.key, this.key]
      // inverted: current is in this chapter when
      // current >= this.key && (next display is smaller chapter start OR last).
      final higherNeighbor = index > 0 ? entries[index - 1].key : 1 << 30;
      return current >= paragraphIndex && current < higherNeighbor;
    }
    final next = index + 1 < entries.length ? entries[index + 1].key : 1 << 30;
    return current >= paragraphIndex && current < next;
  }

  /// Fanqie `wl5/e.M3` three-state title colour:
  /// - current (`p3`): accent (`b5.n`) + left icon + title leftMargin 16
  /// - read (`!z2 && progress > 0`): `yz4.j.y(theme, 0.6f)` body @ 60%
  /// - unread: full body (`getReaderConfig().d1()`)
  /// Vellum approximates Fanqie's per-chapter progress % as "chapter start
  /// is strictly before the paragraph currently on screen".
  bool isReadChapter(int paragraphIndex) =>
      paragraphIndex < widget.currentParagraph;

  /// Fanqie `P3`/`S3` secondary labels (always 60% body):
  /// - current: `读到 x/y 页` / `读到x%`
  /// - read: `已读x%` / `上次读到 x/y 页`
  /// - also word count / first-pass time when available.
  String readStateLabel(int paragraphIndex, bool isCurrent, bool isRead) {
    if (isCurrent && widget.progressSummary != null) {
      final percent = (widget.progressSummary!.chapterProgress * 100)
          .round()
          .clamp(0, 100);
      final page = widget.chapterPageLabels[paragraphIndex];
      if (page != null && page.isNotEmpty) return '读到 $percent% · $page';
      return '读到 $percent%';
    }
    if (widget.readingMode == ReadingMode.page) {
      final page = widget.chapterPageLabels[paragraphIndex];
      if (page != null && page.isNotEmpty) {
        return isCurrent ? '读到 $page' : '上次读到 $page';
      }
    }
    if (isCurrent) return '当前章节';
    if (isRead) return '已读';
    return '';
  }

  void autoScrollToCurrent() {
    if (didAutoScroll || !scrollController.hasClients) return;
    final chapterEntries = entries;
    if (chapterEntries.isEmpty) return;
    var target = 0;
    if (descending) {
      // Reverse list: unread later chapters sit first; current is the first
      // entry whose start is <= currentParagraph.
      for (var i = 0; i < entries.length; i++) {
        if (chapterEntries[i].key <= widget.currentParagraph) {
          target = i;
          break;
        }
      }
    } else {
      for (var i = 0; i < entries.length; i++) {
        if (chapterEntries[i].key <= widget.currentParagraph) {
          target = i;
        } else {
          break;
        }
      }
    }
    didAutoScroll = true;
    final maxOffset = scrollController.position.maxScrollExtent;
    final offset = (target * itemExtent - 96).clamp(0.0, maxOffset);
    if ((offset - scrollController.offset).abs() > 1) {
      scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    if (currentOffscreen) setState(() => currentOffscreen = false);
  }

  String secondaryLabel(int paragraphIndex, bool isCurrent, bool isRead) {
    if (tab == 1) return '第 ${paragraphIndex + 1} 段';
    if (tab == 2) return '';
    return readStateLabel(paragraphIndex, isCurrent, isRead);
  }

  void refresh(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) =>
      renderReaderDirectoryPanel(this, context);
}
