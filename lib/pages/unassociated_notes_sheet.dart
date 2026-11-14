import 'package:flutter/cupertino.dart';

import '../services/notes_import.dart';
import '../services/notes_library.dart';
import '../widgets/book_picker_sheet.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_section.dart';

/// Lists imported notes that never found their book, and links them on request.
///
/// This is the fallback half of the importer: a notes file from another app
/// usually cannot be matched automatically, so the notes are kept under
/// [unmatchedBookTitle] and land here until the reader says which book they
/// belong to.
Future<void> showUnassociatedNotesSheet(
  BuildContext context, {
  required List<BookMatchCandidate> books,
  NotesLibrary notesLibrary = const NotesLibrary(),
  VoidCallback? onChanged,
}) => showCupertinoModalPopup<void>(
  context: context,
  builder: (_) => UnassociatedNotesSheet(
    books: books,
    notesLibrary: notesLibrary,
    onChanged: onChanged,
  ),
);

class UnassociatedNotesSheet extends StatefulWidget {
  const UnassociatedNotesSheet({
    required this.books,
    this.notesLibrary = const NotesLibrary(),
    this.onChanged,
    super.key,
  });

  final List<BookMatchCandidate> books;
  final NotesLibrary notesLibrary;
  final VoidCallback? onChanged;

  @override
  State<UnassociatedNotesSheet> createState() => _UnassociatedNotesSheetState();
}

class _UnassociatedNotesSheetState extends State<UnassociatedNotesSheet> {
  List<ReadingNote>? _notes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.notesLibrary.load();
    if (!mounted) return;
    setState(() {
      _notes = [
        for (final note in all)
          if (note.bookId == unmatchedBookId) note,
      ];
    });
  }

  Future<void> _link(ReadingNote note) async {
    final result = await showBookPickerSheet(
      context,
      books: widget.books,
      title: '关联到哪本书',
    );
    if (result == null || !mounted) return;
    if (result.book == null) return;
    await widget.notesLibrary.updateBook(
      note.id,
      bookId: result.book!.id,
      bookTitle: result.book!.title,
    );
    widget.onChanged?.call();
    if (!mounted) return;
    setState(() {
      _notes = [
        for (final item in _notes ?? <ReadingNote>[])
          if (item.id != note.id) item,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = context.c.card;
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;
    final colors = context.c;
    final notes = _notes;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                unmatchedBookTitle,
                style: TextStyle(
                  color: ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                '这些笔记还没有所属的书。选择一本即可关联。',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
            Flexible(
              child: notes == null
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  : notes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '没有未关联的笔记。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: AppSpace.pageGutter,
                        right: AppSpace.pageGutter,
                        bottom: AppSpace.x2,
                      ),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpace.x2,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: AppRadius.groupedAll,
                            ),
                            child: ClipRRect(
                              borderRadius: AppRadius.groupedAll,
                              // The row itself links the note; the trailing
                              // word is the affordance, not a second target.
                              child: AppRow(
                                label: note.selectedText.isEmpty
                                    ? note.note
                                    : note.selectedText,
                                description:
                                    note.note.isEmpty ||
                                        note.selectedText.isEmpty
                                    ? note.kind.label
                                    : note.note,
                                trailing: Text(
                                  '关联书籍',
                                  style: AppText.caption(colors.primary),
                                ),
                                onTap: () => _link(note),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.pageGutter,
                AppSpace.x1,
                AppSpace.pageGutter,
                AppSpace.x4,
              ),
              child: AppButton(
                label: '关闭',
                variant: AppButtonVariant.tonal,
                expand: true,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}