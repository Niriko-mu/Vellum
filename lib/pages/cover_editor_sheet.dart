import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';

/// Long-press sheet: edit shelf cover with an image or custom text.
class CoverEditorSheet extends StatefulWidget {
  const CoverEditorSheet({required this.book, required this.onSave, super.key});

  final ImportedBook book;
  final Future<void> Function({
    Uint8List? coverBytes,
    String? coverText,
    bool clearCoverImage,
    bool clearCoverText,
  })
  onSave;

  @override
  State<CoverEditorSheet> createState() => _CoverEditorSheetState();
}

class _CoverEditorSheetState extends State<CoverEditorSheet> {
  late final TextEditingController _textController;
  late final FocusNode _textFocus;
  Uint8List? _pickedImage;
  var _mode = 'keep';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.book.coverText ?? '');
    _textFocus = FocusNode();
    if (widget.book.coverBytes != null) _mode = 'image';
    if (widget.book.coverText?.isNotEmpty ?? false) _mode = 'text';
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    setState(() {
      _pickedImage = bytes;
      _mode = 'image';
    });
  }

  Future<void> _save() async {
    final text = _textController.text.trim();
    if (_mode == 'image') {
      final image = _pickedImage ?? widget.book.coverBytes;
      if (image == null) return;
      await widget.onSave(coverBytes: image, clearCoverText: true);
    } else if (_mode == 'text') {
      if (text.isEmpty) return;
      await widget.onSave(coverText: text, clearCoverImage: true);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _pickedImage ?? widget.book.coverBytes;
    // Keep the text field above the soft keyboard.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        decoration: BoxDecoration(
          color: context.c.card,
          borderRadius: AppRadius.sheetTop,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '编辑封面',
                      style: TextStyle(
                        color: context.c.foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: 110,
                    height: 156,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: context.c.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: preview != null
                            ? Image.memory(preview, fit: BoxFit.cover)
                            : _TextCoverPreview(
                                title: _textController.text.trim().isEmpty
                                    ? widget.book.title
                                    : _textController.text.trim(),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  onPressed: _pickImage,
                  child: Text(preview == null ? '上传封面图片' : '更换封面图片'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: () {
                    setState(() => _mode = 'text');
                    _textFocus.requestFocus();
                  },
                  child: const Text('用文字生成封面'),
                ),
                if (_mode == 'text') ...[
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: _textController,
                    focusNode: _textFocus,
                    placeholder: '封面文字，例如书名或题词',
                    maxLines: 3,
                    minLines: 2,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() {}),
                    decoration: BoxDecoration(
                      color: context.c.secondary.withValues(
                        alpha:
                            CupertinoTheme.of(context).brightness ==
                                Brightness.dark
                            ? .08
                            : .5,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: context.c.border),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '保存后书架将使用这段文字作为封面。',
                    style: TextStyle(
                      color: context.c.mutedForeground,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextCoverPreview extends StatelessWidget {
  const _TextCoverPreview({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          context.c.primary.withValues(alpha: .9),
          context.c.primary.withValues(alpha: .55),
        ],
      ),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(10),
    child: Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: CupertinoColors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    ),
  );
}