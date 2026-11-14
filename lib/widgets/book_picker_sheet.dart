import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;

import '../services/notes_import.dart';
import '../services/notes_library.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import 'ui/app_section.dart';
import 'ui/app_controls.dart';

/// Picks a book from the shelf, with "keep unassociated" always available.
///
/// Shared by the notes importer and the unassociated-notes list, so both offer
/// exactly the same choices.
Future<BookPickResult?> showBookPickerSheet(
  BuildContext context, {
  required List<BookMatchCandidate> books,
  BookMatchCandidate? selected,
  bool unassociated = false,
  String title = '选择书籍',
}) => showCupertinoModalPopup<BookPickResult>(
  context: context,
  builder: (_) => BookPickerSheet(
    books: books,
    selected: selected,
    unassociated: unassociated,
    title: title,
  ),
);

class BookPickResult {
  const BookPickResult({this.book, this.unassociated = false});

  final BookMatchCandidate? book;
  final bool unassociated;
}

class BookPickerSheet extends StatefulWidget {
  const BookPickerSheet({
    required this.books,
    this.selected,
    this.unassociated = false,
    this.title = '选择书籍',
    super.key,
  });

  final List<BookMatchCandidate> books;
  final BookMatchCandidate? selected;
  final bool unassociated;
  final String title;

  @override
  State<BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<BookPickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final bg = context.c.card;
    final ink = context.c.foreground;
    final accent = context.c.primary;
    final needle = _query.trim().toLowerCase();
    final books = [
      for (final book in widget.books)
        if (needle.isEmpty || book.title.toLowerCase().contains(needle)) book,
    ];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  AppTextButton(
                    label: '完成',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoTextField(
                placeholder: '按书名筛选',
                onChanged: (value) => setState(() => _query = value),
                style: TextStyle(color: ink, fontSize: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    AppSection(
                      margin: EdgeInsets.zero,
                      children: [
                        // The fallback first: a notes file that cannot be
                        // matched is the common case, and it must not look like
                        // a secondary option.
                        AppRow(
                          label: unmatchedBookTitle,
                          description: '保留在「未关联笔记」，之后可再关联',
                          selected: widget.unassociated,
                          trailing: widget.unassociated
                              ? Icon(
                                  CupertinoIcons.checkmark_alt,
                                  color: accent,
                                )
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            const BookPickResult(unassociated: true),
                          ),
                        ),
                        for (final book in books)
                          AppRow(
                            label: book.title,
                            selected:
                                !widget.unassociated &&
                                widget.selected?.id == book.id,
                            trailing:
                                !widget.unassociated &&
                                    widget.selected?.id == book.id
                                ? Icon(
                                    CupertinoIcons.checkmark_alt,
                                    color: accent,
                                  )
                                : null,
                            onTap: () => Navigator.pop(
                              context,
                              BookPickResult(book: book),
                            ),
                          ),
                      ],
                    ),
                    if (books.isEmpty)
                      AppContentState(
                        kind: AppContentStateKind.empty,
                        compact: true,
                        title: widget.books.isEmpty
                            ? '书库还是空的'
                            : '没有匹配的书名',
                        description: widget.books.isEmpty
                            ? '先导入书籍，或先把笔记存为未关联。'
                            : '换个关键词再试。',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}