import 'package:flutter/cupertino.dart';

import '../services/notes_import.dart';
import '../services/notes_library.dart';
import '../widgets/book_picker_sheet.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';

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
    final accent = context.c.primary;
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
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return CupertinoListTile(
                          backgroundColor: bg,
                          backgroundColorActivated: ink.withValues(alpha: .06),
                          title: Text(
                            note.selectedText.isEmpty
                                ? note.note
                                : note.selectedText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: ink, fontSize: 15),
                          ),
                          subtitle: Text(
                            note.note.isEmpty || note.selectedText.isEmpty
                                ? note.kind.label
                                : note.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          trailing: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            onPressed: () => _link(note),
                            child: Text(
                              '关联书籍',
                              style: TextStyle(color: accent, fontSize: 13),
                            ),
                          ),
                          onTap: () => _link(note),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: CupertinoButton(
                color: ink.withValues(alpha: .06),
                onPressed: () => Navigator.pop(context),
                child: Text('关闭', style: TextStyle(color: ink)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}