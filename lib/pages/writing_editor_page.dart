import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../services/font_registry.dart';
import '../services/font_storage.dart';
import '../services/library_models.dart';
import '../services/writing_library.dart';
import '../theme/app_colors.dart';
import '../widgets/markdown_preview.dart';
import 'writing_typography_sheet.dart';
import '../theme/app_motion.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_icons.dart';

/// Writing tab: list of local drafts, open editor to write .md / .txt.
class WritingEditorPage extends StatefulWidget {
  const WritingEditorPage({
    required this.document,
    this.onChanged,
    this.library,
    super.key,
  });

  final WritingDocument document;
  final VoidCallback? onChanged;

  /// Test hook: defaults to the on-disk [WritingLibrary].
  final WritingLibrary? library;

  @override
  State<WritingEditorPage> createState() => _WritingEditorPageState();
}

class _WritingEditorPageState extends State<WritingEditorPage>
    with SingleTickerProviderStateMixin {
  late final WritingLibrary _library = widget.library ?? const WritingLibrary();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late WritingFormat _format;
  late WritingDocument _document;
  bool _saving = false;
  bool _dirty = false;

  /// Typing pauses briefly before the disk write, so a burst of keystrokes is
  /// one save rather than one per character.
  static const Duration _autoSaveDelay = AppGestureWindow.autosaveDelay;
  Timer? _autoSaveTimer;
  Timer? _novelFormatTimer;
  final _typoStore = const WritingTypographyStore();
  final _fontStorage = const FontStorage();
  WritingTypography _typo = const WritingTypography();
  List<InstalledFont> _installedFonts = const [];

  /// Markdown drafts can be flipped to a rendered preview.
  bool _previewing = false;

  bool get _canPreview => _format == WritingFormat.md;

  String get _saveStatusText {
    if (_saving) return '保存中…';
    if (_dirty) return '即将自动保存';
    return '已自动保存';
  }

  /// Fades the save label out when its text changes, then back in.
  ///
  /// A cross-fade would need the old and new label laid out side by side, which
  /// widened the row mid-swap; this keeps one line that briefly dips, which is
  /// calmer in peripheral vision — exactly where this text lives.
  ///
  /// Driven by a controller rather than a delayed future so it is disposed with
  /// the page and honours the reduced-motion setting.
  late final AnimationController _saveStatusFade;

  String _shownSaveStatus = '';

  void _syncSaveStatus() {
    final next = _saveStatusText;
    if (next == _shownSaveStatus) return;
    _shownSaveStatus = next;
    _saveStatusFade
      ..duration = motionDuration(context, AppMotion.fast)
      ..value = 0
      ..forward();
  }

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _format = _document.format;
    _titleController = TextEditingController(text: _document.title);
    _bodyController = TextEditingController(text: _document.body);
    _lastBodyText = _document.body;
    _shownSaveStatus = _saveStatusText;
    _saveStatusFade = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
      value: 1,
    );
    _titleController.addListener(_markDirty);
    _bodyController.addListener(_onBodyChanged);
    _loadTypo();
    _loadFonts();
  }

  Future<void> _loadTypo() async {
    // Skip in widget tests: path_provider + timeout leaves a pending timer.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final typo = await _typoStore.load().timeout(const Duration(seconds: 2));
      if (mounted) setState(() => _typo = typo);
    } catch (_) {}
  }

  Future<void> _loadFonts() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final fonts = await _fontStorage.listFonts().timeout(
        const Duration(seconds: 2),
      );
      if (mounted) setState(() => _installedFonts = fonts);
    } catch (_) {}
  }

  /// 小说排版 only applies to 纯文本 drafts. Markdown owns its own rules
  /// (headings, lists, fences), so the novel switch is inert in MD mode.
  bool get _novelModeActive => _typo.novelMode && _format == WritingFormat.txt;

  void _applyTypo(WritingTypography next) {
    final novelTurnedOn = next.novelMode && !_typo.novelMode;
    setState(() => _typo = next);
    // Persist in the background — the sheet must not wait on disk.
    unawaited(() async {
      try {
        await _typoStore.save(next);
      } catch (_) {}
    }());
    if (novelTurnedOn && _novelModeActive) {
      _applyNovelFormat();
    }
  }

  String _lastBodyText = '';

  void _onBodyChanged() {
    _markDirty();
    if (!_novelModeActive) return;
    _maybeOpenNovelParagraph();
    _lastBodyText = _bodyController.text;
  }

  /// Enter at the end in 小说模式 opens a proper new paragraph (段首两格).
  ///
  /// Deliberately a tiny rewrite of the tail only. The old live formatter
  /// rewrote the whole document on a timer, which ate the caret's newline and
  /// broke IME composition — that is what made 换行 feel broken.
  ///
  /// Backspace is explicitly excluded ([shouldOpenNovelParagraph]): deleting
  /// the indent of an open paragraph used to fall through here and get the
  /// `　　` put right back, so the caret could never return to the previous line.
  void _maybeOpenNovelParagraph() {
    final text = _bodyController.text;
    final sel = _bodyController.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    // Never rewrite under an active IME composition.
    if (_bodyController.value.composing.isValid) return;
    if (sel.extentOffset != text.length) return;
    if (!shouldOpenNovelParagraph(_lastBodyText, text)) return;
    if (text.endsWith('\n\n　　')) return;

    final edit = novelParagraphBreakWithCaret(text);
    if (edit.text == text) return;
    _bodyController.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.caretOffset),
    );
    _lastBodyText = edit.text;
    _markDirty();
  }

  /// One-shot rewrite used when 小说模式 is switched on. Keeps any open line
  /// at the end so the caret does not lose the writer's current Enter.
  void _applyNovelFormat() {
    final text = _bodyController.text;
    final formatted = applyNovelFormatting(text, keepTrailingNewlines: true);
    if (formatted == text) {
      _lastBodyText = text;
      return;
    }
    final sel = _bodyController.selection;
    final wasAtEnd =
        !sel.isValid || sel.extentOffset >= text.length || text.isEmpty;
    _bodyController.value = TextEditingValue(
      text: formatted,
      selection: wasAtEnd
          ? TextSelection.collapsed(offset: formatted.length)
          : TextSelection.collapsed(
              offset: sel.extentOffset.clamp(0, formatted.length),
            ),
    );
    _lastBodyText = formatted;
    _markDirty();
  }

  void _showTypoSheet() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => WritingTypographySheet(
        initial: _typo,
        installedFonts: _installedFonts,
        novelAvailable: _format == WritingFormat.txt,
        onChanged: _applyTypo,
        onActivateImportedFont: _activateImportedFont,
        onRefreshFonts: () async {
          await _loadFonts();
          return _installedFonts;
        },
      ),
    );
  }

  /// Registers an imported TTF for the editor (same path as the reader).
  Future<void> _activateImportedFont(InstalledFont font) async {
    try {
      final bytes = await _fontStorage.loadFontByName(font.name);
      if (bytes != null) {
        await FontRegistry.load(font.family, bytes);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _novelFormatTimer?.cancel();
    // Swipe-back / system pop skips 完成; flush whatever is still dirty so the
    // last keystrokes are not lost. Fire-and-forget: dispose cannot await.
    if (_dirty) {
      final snapshot = _document.copyWith(
        title: _titleController.text,
        body: _bodyController.text,
        format: _format,
      );
      unawaited(_library.upsert(snapshot));
    }
    _saveStatusFade.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _markDirty() {
    // Only rebuild when the flag actually flips. It used to call setState on
    // every keystroke purely so the character count stayed live, which rebuilt
    // this whole page — including the text field being typed into — once per
    // character. The count now listens to the controller directly.
    if (!_dirty) {
      setState(() => _dirty = true);
    }
    _syncSaveStatus();
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      if (mounted) unawaited(_persist());
    });
  }

  /// Writes the draft to the local library. Silent — the editor no longer has
  /// a save button; a typing pause (or leaving the page) is the commit point.
  Future<void> _persist() async {
    if (_saving) {
      // A write is already in flight; retry with whatever is on screen now.
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted) unawaited(_persist());
      });
      return;
    }
    final next = _document.copyWith(
      title: _titleController.text,
      body: _bodyController.text,
      format: _format,
    );
    setState(() => _saving = true);
    _syncSaveStatus();
    try {
      final saved = await _library.upsert(next);
      if (!mounted) return;
      setState(() {
        _document = saved;
        _dirty = false;
        _saving = false;
      });
      _syncSaveStatus();
      widget.onChanged?.call();
    } catch (_) {
      // Keep the text dirty so the next pause (or export/leave) retries.
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportFile() async {
    _autoSaveTimer?.cancel();
    if (_dirty) await _persist();
    final text = _bodyController.text;
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name = _document.suggestedFileName;
    final useSaf = Platform.isAndroid || Platform.isIOS;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出文稿',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [_format.extension],
        bytes: useSaf ? bytes : null,
      );
      if (path == null || path.isEmpty || !mounted) return;
      if (!useSaf) {
        final file = File(
          path.endsWith('.${_format.extension}')
              ? path
              : '$path.${_format.extension}',
        );
        await file.writeAsString(text, encoding: utf8, flush: true);
        if (!mounted) return;
        _showToast('已导出到 ${file.path}');
      } else {
        _showToast('已导出');
      }
    } catch (error) {
      if (!mounted) return;
      try {
        final directory = Directory(
          '${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}vellum_exports',
        );
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final file = File('${directory.path}${Platform.pathSeparator}$name');
        await file.writeAsString(text, encoding: utf8, flush: true);
        if (!mounted) return;
        _showToast('已导出到 ${file.path}');
      } catch (_) {
        _showToast('导出失败：$error');
      }
    }
  }

  void _showToast(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导出'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('删除《${_document.displayTitle}》？'),
        content: const Text('文稿将从本机删除，此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _library.delete(_document.id);
    widget.onChanged?.call();
    if (mounted) Navigator.pop(context);
  }

  void _togglePreview() {
    if (!_canPreview) return;
    if (!_previewing) FocusScope.of(context).unfocus();
    setState(() => _previewing = !_previewing);
  }

  void _setFormat(WritingFormat value) {
    if (value == _format) return;
    setState(() {
      _format = value;
      // Plain text has nothing to render.
      if (value != WritingFormat.md) _previewing = false;
    });
    _markDirty();
    // Entering 纯文本 with the global novel switch on applies it once;
    // leaving into Markdown just lets the switch go inert (no rewrite).
    if (_novelModeActive) {
      _lastBodyText = _bodyController.text;
      _applyNovelFormat();
    }
  }

  void _showMoreActions() {
    FocusScope.of(context).unfocus();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              unawaited(_exportFile());
            },
            child: const Text('导出文稿'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(sheetContext);
              unawaited(_confirmDelete());
            },
            child: const Text('删除文稿'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.c.mutedForeground;
    final ink = context.c.foreground;
    final paper = context.c.backgroundSubtle;
    final updated = _document.updatedAt.toLocal();
    final date =
        '${updated.month}月${updated.day}日 '
        '${updated.hour.toString().padLeft(2, '0')}:'
        '${updated.minute.toString().padLeft(2, '0')}';

    return CupertinoPageScaffold(
      backgroundColor: paper,
      navigationBar: CupertinoNavigationBar(
        leading: AppTextButton(
          label: '完成',
          size: AppButtonSize.regular,
          onPressed: () async {
            _autoSaveTimer?.cancel();
            if (_dirty) await _persist();
            if (!context.mounted) return;
            Navigator.pop(context);
          },
        ),
        backgroundColor: paper,
        border: null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canPreview)
              AppTextButton(
                label: _previewing ? '编辑' : '预览',
                size: AppButtonSize.regular,
                onPressed: _togglePreview,
              ),
            Semantics(
              label: '更多操作',
              button: true,
              child: AppPressable(
                onTap: _showMoreActions,
                semanticLabel: '更多操作',
                child: SizedBox(
                  width: 40,
                  height: 44,
                  child: Icon(AppIcons.ellipsis, size: 24, color: ink),
                ),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: '标题',
                maxLines: 1,
                textInputAction: TextInputAction.next,
                style: TextStyle(
                  color: ink,
                  fontSize: 28,
                  fontFamily: _typo.fontFamily,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
                placeholderStyle: TextStyle(
                  color: muted.withValues(alpha: .65),
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption(muted),
                          ),
                        ),
                        if (_typo.showSaveStatus) ...[
                          Text(' · ', style: AppText.caption(muted)),
                          Flexible(
                            // AnimatedSwitcher measures each child in a loose,
                            // overlay-sized box, which pushed this label out of
                            // the row entirely. A plain fade over the *new* text
                            // needs no measurement of the old one, so the line
                            // never changes width mid-swap.
                            child: FadeTransition(
                              opacity: _saveStatusFade,
                              child: Text(
                                _saveStatusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption(muted),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Scoped rebuild: one line follows the text, not the page.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _bodyController,
                    builder: (context, value, _) => Text(
                      '${value.text.characters.length} 字',
                      style: AppText.caption(muted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              // Cross-fade only: scaling body text would blur it, and any
              // height animation would fight the keyboard.
              child: AnimatedSwitcher(
                duration: motionDuration(context, AppMotion.fast),
                switchInCurve: AppMotion.settle,
                switchOutCurve: AppMotion.dismissCurve,
                child: _previewing
                    ? MarkdownPreview(
                        key: const ValueKey('preview'),
                        source: _bodyController.text,
                      )
                    : CupertinoTextField(
                        key: const ValueKey('edit'),
                        controller: _bodyController,
                        placeholder: '写下你的想法…',
                        placeholderStyle: TextStyle(
                          color: muted.withValues(alpha: .6),
                          fontSize: _typo.fontSize,
                          height: 1.85,
                        ),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          color: ink,
                          fontSize: _typo.fontSize,
                          fontFamily: _typo.fontFamily,
                          fontWeight: _typo.fontWeight,
                          height: 1.85,
                        ),
                        decoration: const BoxDecoration(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: paper,
                border: Border(
                  top: BorderSide(color: muted.withValues(alpha: .1)),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth - 32,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Semantics(
                          label: '排版',
                          button: true,
                          child: AppPressable(
                            onTap: _showTypoSheet,
                            semanticLabel: '排版',
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                AppIcons.textformatSize,
                                size: 23,
                                color: ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        CupertinoSlidingSegmentedControl<WritingFormat>(
                          groupValue: _format,
                          backgroundColor: context.c.secondary,
                          thumbColor: context.c.card,
                          children: {
                            for (final format in WritingFormat.values)
                              format: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                child: Text(
                                  format.label,
                                  style: TextStyle(
                                    color: _format == format ? ink : muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          },
                          onValueChanged: (value) {
                            if (value != null) _setFormat(value);
                          },
                        ),
                        const SizedBox(width: 16),
                        Semantics(
                          label: '收起键盘',
                          button: true,
                          child: AppPressable(
                            onTap: () => FocusScope.of(context).unfocus(),
                            semanticLabel: '收起键盘',
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                AppIcons.keyboardChevronCompactDown,
                                size: 23,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}