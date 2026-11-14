import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notes_library.dart';
import '../util/text_slices.dart' show safeSubstring, buildBingSearchUri;
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/app_controls.dart';

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
}) {
  return showCupertinoModalPopup<ReadingNote>(
    context: context,
    builder: (ctx) => _AddNoteComposer(
      bookId: bookId,
      bookTitle: bookTitle,
      paragraphIndex: paragraphIndex,
      selectedText: selectedText,
      notesLibrary: notesLibrary,
      existing: existing,
    ),
  );
}

/// The composer itself, stateful so a failed save can say so instead of closing
/// as if it had worked — the silent `catch` is what made a broken save look like
/// "点了保存没有任何反应".
class _AddNoteComposer extends StatefulWidget {
  const _AddNoteComposer({
    required this.bookId,
    required this.bookTitle,
    required this.paragraphIndex,
    required this.selectedText,
    required this.notesLibrary,
    this.existing,
  });

  final String bookId;
  final String bookTitle;
  final int paragraphIndex;
  final String selectedText;
  final NotesLibrary notesLibrary;
  final ReadingNote? existing;

  @override
  State<_AddNoteComposer> createState() => _AddNoteComposerState();
}

class _AddNoteComposerState extends State<_AddNoteComposer> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final body = _controller.text.trim();
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (existing != null) {
        await widget.notesLibrary.updateNote(existing.id, body);
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
        final created = await widget.notesLibrary.add(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
          paragraphIndex: widget.paragraphIndex,
          selectedText: widget.selectedText,
          note: body,
        );
        navigator.pop(created);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: NoteSheetBody(
            title: widget.existing == null ? '添加笔记' : '编辑笔记',
            selectedText: widget.selectedText,
            controller: _controller,
            error: _error,
            onCancel: () => Navigator.pop(context),
            onSave: _save,
          ),
        ),
      ),
    );
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
    this.error,
    super.key,
  });

  final String title;
  final String selectedText;
  final TextEditingController controller;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  /// Shown when the last save attempt failed, so the reader is not left thinking
  /// it worked.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final bg = colors.card;
    final quoteBg = colors.secondary;
    final ink = colors.foreground;
    final muted = colors.mutedForeground;
    final fieldBg = colors.secondary;
    final fieldInk = colors.foreground;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.grouped),
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
              borderRadius: BorderRadius.circular(AppRadius.xl),
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
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 12),
          if (error != null) ...[
            Text(
              error!,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '取消',
                  variant: AppButtonVariant.tonal,
                  expand: true,
                  onPressed: onCancel,
                ),
              ),
              const SizedBox(width: AppSpace.x2),
              Expanded(
                child: AppButton(
                  label: '保存',
                  expand: true,
                  onPressed: onSave,
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
      final colors = context.c;
      final bg = colors.card;
      final ink = colors.foreground;
      final muted = colors.mutedForeground;
      final tileBg = colors.card;
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
                borderRadius: BorderRadius.circular(AppRadius.grouped),
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
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                note.kind.label,
                                style: TextStyle(
                                  fontSize: 13,
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
                                  AppTextButton(
                                    label: '编辑',
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
                                  ),
                                  const SizedBox(width: 4),
                                  AppTextButton(
                                    label: '删除',
                                    color: context.c.destructive,
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
                  AppButton(
                    label: '关闭',
                    variant: AppButtonVariant.tonal,
                    expand: true,
                    onPressed: () => Navigator.pop(ctx),
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