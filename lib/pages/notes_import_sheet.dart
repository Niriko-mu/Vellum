import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;

import '../services/notes_import.dart';
import '../services/notes_library.dart' show unmatchedBookTitle;
import '../widgets/book_picker_sheet.dart';
import '../widgets/ui/app_section.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/app_controls.dart';
import '../theme/app_icons.dart';

/// Where the imported notes should land, as chosen in [NotesImportSheet].
class NotesImportOutcome {
  const NotesImportOutcome.book(BookMatchCandidate this.book)
    : unassociated = false;
  const NotesImportOutcome.unassociated() : book = null, unassociated = true;

  final BookMatchCandidate? book;
  final bool unassociated;
}

/// Confirms a notes import: shows what was read, which book it will attach to,
/// and lets the reader change that — including keeping the notes unassociated.
///
/// The fallback matters more than the happy path: a file exported from another
/// app (or renamed) usually cannot be matched automatically, and the notes are
/// worth keeping either way.
class NotesImportSheet extends StatefulWidget {
  const NotesImportSheet({
    required this.import,
    required this.books,
    required this.match,
    this.fileName = '',
    super.key,
  });

  final NotesImport import;
  final List<BookMatchCandidate> books;
  final BookMatch match;
  final String fileName;

  @override
  State<NotesImportSheet> createState() => _NotesImportSheetState();
}

class _NotesImportSheetState extends State<NotesImportSheet> {
  BookMatchCandidate? _selected;
  late bool _unassociated;

  @override
  void initState() {
    super.initState();
    _selected = widget.match.book;
    _unassociated = widget.match.isFallback;
  }

  @override
  Widget build(BuildContext context) {
    final bg = context.c.card;
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;
    final accent = context.c.primary;
    final notes = widget.import.notes;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '导入阅读笔记',
                style: TextStyle(
                  color: ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '读到 ${notes.length} 条笔记'
                '${widget.fileName.isEmpty ? '' : ' · ${widget.fileName}'}'
                '${widget.import.format == 'json' ? '（JSON 备份）' : '（文本）'}',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),

            // The association is never silent: the reader can always see and
            // change where the notes will land.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('关联书籍', style: TextStyle(color: muted, fontSize: 13)),
            ),
            AppSection(
              margin: EdgeInsets.zero,
              children: [
                AppSelectRow(
                  label: _unassociated
                      ? unmatchedBookTitle
                      : (_selected?.title ?? unmatchedBookTitle),
                  description: _unassociated
                      ? '先存下来，之后可以再关联到某本书'
                      : widget.match.reason,
                  leading: Icon(
                    _unassociated
                        ? AppIcons.questionCircle
                        : AppIcons.book,
                    color: _unassociated ? muted : accent,
                  ),
                  onTap: _pickBook,
                ),
              ],
            ),
            if (widget.import.warning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(
                  widget.import.warning,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),

            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('预览', style: TextStyle(color: muted, fontSize: 13)),
            ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final passage = note.selectedText.isEmpty
                          ? note.note
                          : note.selectedText;
                      final comment = note.selectedText.isEmpty
                          ? ''
                          : note.note;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              passage,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: ink, fontSize: 14),
                            ),
                            if (comment.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  comment,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: muted, fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: '取消',
                      variant: AppButtonVariant.tonal,
                      expand: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: _unassociated
                          ? '仍然导入'
                          : '导入到《${_selected!.title}》',
                      expand: true,
                      onPressed: notes.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              _unassociated
                                  ? const NotesImportOutcome.unassociated()
                                  : NotesImportOutcome.book(_selected!),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Manual association, with the unassociated option kept visible at the top.
  Future<void> _pickBook() async {
    final result = await showBookPickerSheet(
      context,
      books: widget.books,
      selected: _selected,
      unassociated: _unassociated,
    );
    if (result == null || !mounted) return;
    setState(() {
      _unassociated = result.unassociated;
      if (result.book != null) _selected = result.book;
    });
  }
}