import 'package:flutter/cupertino.dart';

import 'reader_directory_panel_state.dart';
import 'reader_models.dart';
import '../services/notes_library.dart';
import '../theme/app_icons.dart';

class ReaderDirectoryPanel extends StatefulWidget {
  const ReaderDirectoryPanel({
    required this.chapters,
    required this.bookmarks,
    required this.notes,
    required this.chapterPageLabels,
    required this.currentParagraph,
    required this.readingMode,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
    required this.onClose,
    this.onJumpToSearchHit,
    this.paragraphs,
    this.pageLabelForParagraph,
    this.bookTitle = '',
    this.surface,
    this.onSearchingChanged,
    this.progressSummary,
    this.onContinueReading,
    this.onJumpToChapter,
    super.key,
  });

  /// Height of the book-name line plus the tab row.
  ///
  /// Searching no longer shares this header — it uses [searchHeaderHeight] —
  /// so this is the full (non-search) chrome. [ReaderMenu] keeps the sheet at
  /// least as tall as [minPanelHeight], because a sheet shorter than its own
  /// header is exactly what overflows — and the soft keyboard is what makes a
  /// sheet that short.
  static double get headerHeight =>
      bookTitleHeight + tabRowHeight + _catalogSummaryHeight + 0.5;

  /// Header height the panel falls back to when the sheet is too short for the
  /// book-name line: a compact app bar, one row of tabs, their rule, and a small
  /// margin so sub-pixel rounding never turns into an overflow stripe.
  static double get compactHeaderHeight =>
      compactBarHeight +
      compactTabHeight +
      _catalogSummaryHeight +
      0.5 +
      _compactSlack;

  static const double _compactSlack = 4;

  /// Height of the search summary bar (counts + step buttons).
  static const double _searchSummaryHeight = 48;

  /// Minimum room the tab's list needs to stay usable.
  static const double _minBodyHeight = 40;

  /// Smallest sheet the panel can render without overflowing.
  ///
  /// The search view is the tallest fixed content: the compact header plus the
  /// summary bar, with a little list left underneath.
  static double get minPanelHeight =>
      compactHeaderHeight + _searchSummaryHeight + _minBodyHeight;

  /// Height of the search-only header (query field + 取消).
  ///
  /// While searching the tab row and book name are noise; this is all the
  /// chrome the results list needs, so the list keeps the rest of the sheet.
  static double get searchHeaderHeight => _searchRowHeight + _searchHeaderSlack;

  static const double _searchHeaderSlack = 8;

  static const double compactBarHeight = 46;
  static const double compactTabHeight = 34;
  static const double bookTitleHeight = 14 + 17 + 8;
  static const double tabRowHeight = 44;
  static const double _catalogSummaryHeight = 94;
  static const double _searchRowHeight = 36 + 14;

  /// Fanqie reader catalog item height (`caloglayout/a.java` setItemHeight 54).
  static const double itemExtent = 54;

  /// Test-only alias so widget tests can assert the Fanqie height.
  static const double itemExtentForTest = itemExtent;

  final List<MapEntry<int, String>> chapters;
  final List<MapEntry<int, String>> bookmarks;
  final List<ReadingNote> notes;
  final Map<int, String> chapterPageLabels;
  final int currentParagraph;
  final ReadingMode readingMode;
  final ValueChanged<int> onJumpToParagraph;
  final void Function(int paragraphIndex, {required bool restorePosition})?
  onJumpToChapter;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;
  final VoidCallback onClose;
  final String bookTitle;

  /// Body text, enabling 全文搜索 in the catalogue tab. Null on panels that only
  /// list the existing indexes.
  final List<String>? paragraphs;

  /// Tapping a search result: jumps to the paragraph **and** carries the query,
  /// so the reader can mark the passage it was searching for.
  final void Function(int paragraphIndex, String query)? onJumpToSearchHit;

  /// Page label for a paragraph (e.g. `第 132 页`), shown on search results so a
  /// hit can be placed in the book. Null when the reader has no page numbers.
  final String Function(int paragraphIndex)? pageLabelForParagraph;

  /// Panel background (reading paper). Ink is derived from this so night
  /// paper stays readable even when the app theme is light.
  final Color? surface;

  /// Notifies the parent when 全文搜索 opens/closes, so the sheet can expand
  /// for the keyboard instead of staying a half-screen card over the seek bar.
  final ValueChanged<bool>? onSearchingChanged;

  /// Live progress used by the catalogue's pinned “继续阅读” card.
  final ReaderProgressSummary? progressSummary;

  /// Restores the durable book position and closes the catalogue.
  final VoidCallback? onContinueReading;

  @override
  State<ReaderDirectoryPanel> createState() => ReaderDirectoryPanelState();
}

/// The reader's search query field.
///
/// It exists only while searching, so `autofocus` is what claims the caret and
/// raises the soft keyboard: a focus request made from the panel lands before
/// this field is mounted and is dropped. It is a separate widget so panel
/// rebuilds cannot recreate its input connection.
class ReaderSearchQueryField extends StatefulWidget {
  const ReaderSearchQueryField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.showClear,
    required this.onClear,
    required this.style,
    required this.placeholderStyle,
    required this.cursorColor,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool showClear;
  final VoidCallback onClear;
  final TextStyle style;
  final TextStyle placeholderStyle;
  final Color cursorColor;

  @override
  State<ReaderSearchQueryField> createState() => ReaderSearchQueryFieldState();
}

class ReaderSearchQueryFieldState extends State<ReaderSearchQueryField> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: true,
            onChanged: widget.onChanged,
            placeholder: '搜索全书内容',
            placeholderStyle: widget.placeholderStyle,
            style: widget.style,
            padding: EdgeInsets.zero,
            decoration: const BoxDecoration(),
            cursorColor: widget.cursorColor,
          ),
        ),
        if (widget.showClear)
          GestureDetector(
            onTap: widget.onClear,
            child: Icon(
              AppIcons.xmarkCircleFill,
              size: 16,
              color: widget.placeholderStyle.color,
            ),
          ),
      ],
    );
  }
}
