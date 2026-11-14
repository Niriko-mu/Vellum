import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;
import '../services/book_search.dart';
import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'reader_directory_panel_state.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';

const double readerDirectorySearchListRoom = 96;

extension ReaderDirectoryPanelSearchRendering on ReaderDirectoryPanelState {
  Widget buildSearchResults(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final hits = results.hits;
    if (hits.isEmpty) {
      final message = query.isEmpty
          ? '输入至少 ${ReaderDirectoryPanelState.minQueryLength} 个字开始搜索'
          : query.length < ReaderDirectoryPanelState.minQueryLength
          ? '再输入 ${ReaderDirectoryPanelState.minQueryLength - query.length} 个字'
          : '没有找到「$query」';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14),
          ),
        ),
      );
    }

    final groups = groupHitsByChapter(hits);
    final activeIndex = hits.indexWhere(
      (hit) => hit.paragraphIndex == activeHit,
    );
    final summary = searchSummary(
      context,
      ink: ink,
      muted: muted,
      accent: accent,
      activeIndex: activeIndex,
    );
    final list = ListView.builder(
      controller: searchScrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: hits.length + groups.length,
      itemBuilder: (context, row) => searchRow(
        context,
        row,
        groups: groups,
        ink: ink,
        muted: muted,
        accent: accent,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          Expanded(
            // Showing the bar permanently makes it paint every frame, and it
            // asserts when its list has no position yet (an empty or squeezed
            // result view). It shows while scrolling instead.
            child: constraints.maxHeight < readerDirectorySearchListRoom
                ? list
                : Scrollbar(child: list),
          ),
        ],
      ),
    );
  }

  /// Room the results list needs before its scrollbar is worth painting.


  /// Counts, the "showing the first N" caveat, and the step-through buttons.
  Widget searchSummary(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
    required int activeIndex,
  }) {
    final hits = results.hits;
    final position = activeIndex < 0 ? 1 : activeIndex + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ink.withValues(alpha: .06), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${results.paragraphCount} 段 · ${results.totalOccurrences} 处'
              '${results.truncated ? '（仅显示前面这些）' : ''}',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          Text(
            '$position/${hits.length}',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(44, 44),
            onPressed: activeIndex <= 0 ? null : () => stepHit(-1),
            child: Icon(
              CupertinoIcons.chevron_up,
              size: 16,
              color: activeIndex <= 0 ? muted.withValues(alpha: .4) : accent,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(44, 44),
            onPressed: activeIndex >= hits.length - 1
                ? null
                : () => stepHit(1),
            child: Icon(
              CupertinoIcons.chevron_down,
              size: 16,
              color: activeIndex >= hits.length - 1
                  ? muted.withValues(alpha: .4)
                  : accent,
            ),
          ),
        ],
      ),
    );
  }

  /// One row of the grouped results: either a chapter header or a hit.
  Widget searchRow(
    BuildContext context,
    int row, {
    required List<SearchGroup> groups,
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    var remaining = row;
    for (final group in groups) {
      if (remaining == 0) {
        return chapterHeaderRow(group, ink: ink, muted: muted, accent: accent);
      }
      remaining--;
      if (remaining < group.hits.length) {
        final hit = group.hits[remaining];
        return hitRow(hit, ink: ink, muted: muted, accent: accent);
      }
      remaining -= group.hits.length;
    }
    return const SizedBox.shrink();
  }

  Widget chapterHeaderRow(
    SearchGroup group, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final title = group.title.isEmpty ? '未分章' : group.title;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      color: ink.withValues(alpha: .03),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${group.occurrences} 处',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget hitRow(
    SearchHit hit, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final active = hit.paragraphIndex == activeHit;
    final page = widget.pageLabelForParagraph?.call(hit.paragraphIndex) ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final selectedQuery = query;
        closeSearch();
        final jump = widget.onJumpToSearchHit;
        if (jump != null) {
          jump(hit.paragraphIndex, selectedQuery);
        } else {
          widget.onJumpToParagraph(hit.paragraphIndex);
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: .07) : null,
          border: Border(
            bottom: BorderSide(color: ink.withValues(alpha: .06), width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context line above the match: tells the reader what leads into it.
            if (hit.first.leadingContext.isNotEmpty)
              Text(
                hit.first.leadingContext,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: .35),
                  fontSize: 13,
                ),
              ),
            const SizedBox(height: 2),
            matchText(hit.first, ink: ink, accent: accent),
            if (hit.first.trailingContext.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                hit.first.trailingContext,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: .35),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '第 ${hit.paragraphIndex + 1} 段'
                  '${hit.first.lineNumber > 1 ? ' · 第 ${hit.first.lineNumber} 行' : ''}',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                if (page.isNotEmpty) ...[
                  Text(
                    ' · $page',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
                const Spacer(),
                if (hit.matchCount > 1)
                  Text(
                    '本段 ${hit.matchCount} 处',
                    style: TextStyle(
                      color: accent.withValues(alpha: .8),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Snippet with the query picked out, so a hit is recognisable at a glance.
  Widget matchText(
    SearchMatch match, {
    required Color ink,
    required Color accent,
  }) {
    final text = match.snippet;
    final start = match.matchStart.clamp(0, text.length);
    final end = match.matchEnd.clamp(start, text.length);
    final base = TextStyle(
      color: ink.withValues(alpha: .92),
      fontSize: 14,
      height: 1.35,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          if (end > start)
            TextSpan(
              text: text.substring(start, end),
              style: base.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
                backgroundColor: accent.withValues(alpha: .18),
              ),
            ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget buildNotes(BuildContext context) {
    final notes = widget.notes;
    final surface = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(surface);
    final muted = ink.withValues(alpha: .55);
    final accent = context.c.primary;
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.text_badge_plus, size: 30, color: muted),
              const SizedBox(height: 10),
              Text(
                '选中正文后可以划线或写笔记。',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.35),
              ),
            ],
          ),
        ),
      );
    }
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          // Imported notes whose book was never identified are tagged, and this
          // list is where the reader meets them for the current book.
          final orphaned = note.bookId == unmatchedBookId;
          final quote = note.selectedText.trim();
          final comment = note.note.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ink.withValues(alpha: .035),
                borderRadius: BorderRadius.circular(AppRadius.grouped),
                border: Border.all(color: ink.withValues(alpha: .08)),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onJumpToParagraph(note.paragraphIndex),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Text(
                              note.kind.label,
                              style: TextStyle(
                                color: accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [
                                '第 ${note.paragraphIndex + 1} 段',
                                if (orphaned) '$unmatchedBookTitle · 可重新关联',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 13),
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: '删除笔记',
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(44, 44),
                              onPressed: () async {
                                await widget.onRemoveNote(note.id);
                                if (mounted) refresh(() {});
                              },
                              child: Icon(
                                CupertinoIcons.delete,
                                size: 17,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (quote.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: Text(
                            quote,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          comment,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink.withValues(alpha: .82),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}