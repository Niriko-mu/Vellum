import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notes_library.dart';
import '../util/text_slices.dart' show safeSubstring, buildBingSearchUri;

export '../util/text_slices.dart' show buildBingSearchUri;

/// DeepL web translator prefill uses the hash fragment — query `text` is
/// ignored by the current site and left the box empty.
Uri deeplTranslateUri(String text) {
  var payload = text.trim();
  if (payload.length > 1800) {
    payload = safeSubstring(payload, 0, 1800);
  }
  return Uri.parse(
    'https://www.deepl.com/translator#auto/zh/${Uri.encodeComponent(payload)}',
  );
}

Future<void> openSelectionService(
  String text, {
  required bool translate,
}) async {
  final uri = translate ? deeplTranslateUri(text) : buildBingSearchUri(text);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Selection toolbar factory that can also open DeepL, attach notes and mark
/// the passage with a highlight.
EditableTextContextMenuBuilder createReaderSelectionToolbar({
  required String bookId,
  required String bookTitle,
  required int Function() currentParagraph,
  NotesLibrary notesLibrary = const NotesLibrary(),
  Future<void> Function(String selected, int paragraphIndex)? onHighlight,
  VoidCallback? onNoteSaved,
}) {
  return (BuildContext context, EditableTextState editableTextState) {
    final value = editableTextState.textEditingValue;
    final selected = value.selection.textInside(value.text).trim();
    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () =>
            editableTextState.copySelection(SelectionChangedCause.toolbar),
      ),
      if (selected.isNotEmpty && onHighlight != null)
        ContextMenuButtonItem(
          label: '划线',
          onPressed: () {
            editableTextState.hideToolbar();
            onHighlight(selected, currentParagraph());
          },
        ),
      if (selected.isNotEmpty)
        ContextMenuButtonItem(
          label: 'Bing 查询',
          onPressed: () {
            editableTextState.hideToolbar();
            openSelectionService(selected, translate: false);
          },
        ),
      if (selected.isNotEmpty)
        ContextMenuButtonItem(
          label: 'DeepL 翻译',
          onPressed: () {
            editableTextState.hideToolbar();
            openSelectionService(selected, translate: true);
          },
        ),
      if (selected.isNotEmpty)
        ContextMenuButtonItem(
          label: '笔记',
          onPressed: () async {
            editableTextState.hideToolbar();
            await showAddNoteSheet(
              context,
              bookId: bookId,
              bookTitle: bookTitle,
              paragraphIndex: currentParagraph(),
              selectedText: selected,
              notesLibrary: notesLibrary,
            );
            onNoteSaved?.call();
          },
        ),
    ];
    return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  };
}

/// Bottom sheet to capture an optional personal note for selected text.
/// Returns the saved note, or null if cancelled / save failed.
Future<ReadingNote?> showAddNoteSheet(
  BuildContext context, {
  required String bookId,
  required String bookTitle,
  required int paragraphIndex,
  required String selectedText,
  NotesLibrary notesLibrary = const NotesLibrary(),
  ReadingNote? existing,
}) async {
  final controller = TextEditingController(text: existing?.note ?? '');
  try {
    return await showCupertinoModalPopup<ReadingNote>(
      context: context,
      builder: (ctx) {
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: NoteSheetBody(
                title: existing == null ? '添加笔记' : '编辑笔记',
                selectedText: selectedText,
                controller: controller,
                onCancel: () => Navigator.pop(ctx),
                onSave: () async {
                  final body = controller.text.trim();
                  final navigator = Navigator.of(ctx);
                  try {
                    if (existing != null) {
                      await notesLibrary.updateNote(existing.id, body);
                      navigator.pop(
                        ReadingNote(
                          id: existing.id,
                          bookId: existing.bookId,
                          bookTitle: existing.bookTitle,
                          paragraphIndex: existing.paragraphIndex,
                          selectedText: existing.selectedText,
                          note: body,
                          createdAt: existing.createdAt,
                          style: existing.style,
                        ),
                      );
                    } else {
                      final created = await notesLibrary.add(
                        bookId: bookId,
                        bookTitle: bookTitle,
                        paragraphIndex: paragraphIndex,
                        selectedText: selectedText,
                        note: body,
                      );
                      navigator.pop(created);
                    }
                  } catch (_) {
                    navigator.pop();
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

/// Theme-aware note composer used by add and edit flows.
class NoteSheetBody extends StatelessWidget {
  const NoteSheetBody({
    required this.title,
    required this.selectedText,
    required this.controller,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final String title;
  final String selectedText;
  final TextEditingController controller;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff2c2c2e) : const Color(0xfff7f7f7);
    final quoteBg = isDark
        ? const Color(0xff3a3a3c)
        : const Color(0xffe9e9ec);
    final ink = isDark ? const Color(0xfff2f2f7) : const Color(0xff1c1c1e);
    final muted = isDark
        ? const Color(0xff98989f)
        : const Color(0xff6c6c70);
    final fieldBg = isDark
        ? const Color(0xff1c1c1e)
        : CupertinoColors.white;
    final fieldInk = isDark
        ? const Color(0xfff2f2f7)
        : const Color(0xff1c1c1e);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: quoteBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              selectedText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: muted, height: 1.35),
            ),
          ),
          const SizedBox(height: 10),
          CupertinoTextField(
            controller: controller,
            placeholder: '写下你的想法（可选）',
            placeholderStyle: TextStyle(color: muted),
            maxLines: 4,
            minLines: 2,
            padding: const EdgeInsets.all(10),
            style: TextStyle(color: fieldInk, fontSize: 15, height: 1.35),
            decoration: BoxDecoration(
              color: fieldBg,
              borderRadius: BorderRadius.circular(10),
            ),
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  onPressed: onCancel,
                  child: Text('取消', style: TextStyle(color: ink)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoButton.filled(
                  onPressed: onSave,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing notes on one paragraph (Fanqie-style comment entry).
Future<void> showParagraphNotesSheet(
  BuildContext context, {
  required String bookId,
  required String bookTitle,
  required int paragraphIndex,
  required List<ReadingNote> notes,
  required NotesLibrary notesLibrary,
  required VoidCallback onChanged,
}) async {
  var items = [
    for (final n in notes)
      if (n.paragraphIndex == paragraphIndex) n,
  ];
  if (items.isEmpty) return;
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) {
      final isDark = CupertinoTheme.of(ctx).brightness == Brightness.dark;
      final bg = isDark ? const Color(0xff2c2c2e) : const Color(0xfff7f7f7);
      final ink = isDark ? const Color(0xfff2f2f7) : const Color(0xff1c1c1e);
      final muted = isDark
          ? const Color(0xff98989f)
          : const Color(0xff6c6c70);
      final tileBg = isDark
          ? const Color(0xff3a3a3c)
          : CupertinoColors.white;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '段落笔记',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final note = items[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: tileBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                note.kind.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                note.selectedText,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ink,
                                  height: 1.35,
                                ),
                              ),
                              if (note.note.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  note.note.trim(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: ink.withValues(alpha: .88),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    onPressed: () async {
                                      final updated = await showAddNoteSheet(
                                        context,
                                        bookId: bookId,
                                        bookTitle: bookTitle,
                                        paragraphIndex: paragraphIndex,
                                        selectedText: note.selectedText,
                                        notesLibrary: notesLibrary,
                                        existing: note,
                                      );
                                      if (updated != null) {
                                        items = [
                                          for (final n in items)
                                            n.id == updated.id ? updated : n,
                                        ];
                                        setLocal(() {});
                                        onChanged();
                                      }
                                    },
                                    child: Text(
                                      '编辑',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: CupertinoColors.activeBlue
                                            .resolveFrom(ctx),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    onPressed: () async {
                                      await notesLibrary.delete(note.id);
                                      items = [
                                        for (final n in items)
                                          if (n.id != note.id) n,
                                      ];
                                      setLocal(() {});
                                      onChanged();
                                      if (items.isEmpty && ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                    },
                                    child: Text(
                                      '删除',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: CupertinoColors.destructiveRed
                                            .resolveFrom(ctx),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('关闭', style: TextStyle(color: ink)),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String bookmarkSummary(List<String> paragraphs, int paragraphIndex) {
  if (paragraphs.isEmpty) return '';
  final index = paragraphIndex.clamp(0, paragraphs.length - 1);
  final text = paragraphs[index];
  return text.length <= 42 ? text : '${safeSubstring(text, 0, 42)}…';
}
