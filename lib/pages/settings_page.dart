import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/book_library.dart';

import '../services/notes_library.dart';
import '../services/notes_import.dart';
import '../services/reading_stats.dart';
import '../services/vellum_update_service.dart';

import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../theme/app_shape.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_page.dart';
import '../widgets/ui/app_section.dart';

import 'font_manager_sheet.dart';
import 'notes_import_sheet.dart';
import 'unassociated_notes_sheet.dart';

import 'ebook_to_txt_page.dart';
import 'reading_stats_page.dart';
import 'backup_settings_page.dart';
import 'tts_settings_page.dart';
import 'update_sheet.dart';
import '../theme/app_icons.dart';
import '../widgets/ui/app_dialog.dart';
import '../widgets/ui/book_motion.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onCycleTheme;

  final String themeModeLabel;

  final bool isDark;

  final List<InstalledFont> installedFonts;

  final String activeFontName;

  final bool useFontForUi;

  final bool useFontForContent;

  final Future<void> Function() onImportFonts;

  final Future<void> Function(String) onActivateFont;

  final Future<void> Function(String) onDeleteFont;

  final Future<void> Function({
    required bool useForUi,
    required bool useForContent,
  })
  onFontUsageChanged;

  final Future<StorageUsage> Function() storageUsage;

  final Future<void> Function() onClearBooks;

  final Future<void> Function() onClearReadingStates;

  /// Shelf titles, for tying imported notes to a book by hand.
  final List<BookMatchCandidate> availableBooks;

  const SettingsPage({
    required this.onCycleTheme,
    required this.themeModeLabel,
    required this.isDark,
    required this.installedFonts,
    required this.activeFontName,
    required this.useFontForUi,
    required this.useFontForContent,
    required this.onImportFonts,
    required this.onActivateFont,
    required this.onDeleteFont,
    required this.onFontUsageChanged,
    required this.storageUsage,
    required this.onClearBooks,
    required this.onClearReadingStates,
    this.availableBooks = const [],
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<StorageUsage> _usage;
  bool _checkingUpdate = false;
  bool _autoCheckUpdate = true;
  String _updateRepo = '';
  String _appVersion = '';
  final _library = const BookLibrary();
  final _statsService = const ReadingStatsService();
  ReadingStats _readingStats = const ReadingStats();

  @override
  void initState() {
    super.initState();
    _usage = widget.storageUsage();
    _loadUpdateRepo();
    _loadUpdatePreferences();
    _loadReadingStats();
    _loadOrphanCount();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {
      // Emulator / test without platform channels: leave the label empty.
    }
  }

  Future<void> _loadUpdatePreferences() async {
    final enabled = await _library.loadAutoUpdateCheck();
    if (mounted) setState(() => _autoCheckUpdate = enabled);
  }

  Future<void> _setAutoCheckUpdate(bool enabled) async {
    setState(() => _autoCheckUpdate = enabled);
    await _library.saveAutoUpdateCheck(enabled);
  }

  Future<void> _loadReadingStats() async {
    final stats = await _statsService.load();
    if (mounted) setState(() => _readingStats = stats);
  }

  Future<void> _exportNotes() async {
    try {
      const notesLibrary = NotesLibrary();
      final notes = await notesLibrary.load();
      if (!mounted) return;
      if (notes.isEmpty) {
        await _showNote('暂无阅读笔记。长按正文选中文字后即可添加。');
        return;
      }
      final bytes = Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent(
            '  ',
          ).convert([for (final n in notes) n.toJson()]),
        ),
      );
      final suggested =
          'vellum_notes_${DateTime.now().millisecondsSinceEpoch}.json';
      final useSaf = Platform.isAndroid || Platform.isIOS;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出阅读笔记',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: useSaf ? bytes : null,
      );
      if (path == null || path.isEmpty || !mounted) return;
      if (!useSaf) {
        final file = File(path.endsWith('.json') ? path : '$path.json');
        await notesLibrary.exportTo(file.path);
        if (!mounted) return;
        await _showNote('已导出 ${notes.length} 条笔记到\n${file.path}');
      } else {
        await _showNote('已导出 ${notes.length} 条笔记');
      }
    } catch (error) {
      if (mounted) await _showNote('导出笔记失败：$error');
    }
  }

  /// Notes waiting for a book, surfaced so the import fallback is reachable
  /// later instead of hiding in the file system.
  int _orphanCount = 0;

  Future<void> _loadOrphanCount() async {
    final notes = await const NotesLibrary().load();
    if (!mounted) return;
    setState(() {
      _orphanCount = notes
          .where((note) => note.bookId == unmatchedBookId)
          .length;
    });
  }

  Future<void> _openUnassociatedNotes() async {
    await showUnassociatedNotesSheet(
      context,
      books: widget.availableBooks,
      onChanged: _loadOrphanCount,
    );
    await _loadOrphanCount();
  }

  /// Reads a notes file, decides which book it belongs to, and lets the reader
  /// confirm or change that before anything is written.
  Future<void> _importNotes() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '导入阅读笔记',
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt', 'md', 'markdown'],
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null || !mounted) return;

      var content = file.bytes == null
          ? ''
          : utf8.decode(file.bytes!, allowMalformed: true);
      if (content.isEmpty && file.path != null) {
        final onDisk = File(file.path!);
        if (await onDisk.exists()) {
          content = await onDisk.readAsString();
        }
      }
      if (!mounted) return;
      if (content.trim().isEmpty) {
        await _showNote('这个文件是空的，或者无法读取。');
        return;
      }

      final import = parseNotesFile(content: content, fileName: file.name);
      if (import.isEmpty) {
        await _showNote(
          import.warning.isEmpty ? '没有在文件里找到笔记。' : import.warning,
        );
        return;
      }

      final books = widget.availableBooks;
      final match = matchBooksForImport(
        books: books,
        import: import,
        fileName: file.name,
      );
      if (!mounted) return;

      final outcome = await showCupertinoModalPopup<NotesImportOutcome>(
        context: context,
        builder: (_) => NotesImportSheet(
          import: import,
          books: books,
          match: match,
          fileName: file.name,
        ),
      );
      if (outcome == null || !mounted) return;

      final saved = await saveImportedNotes(
        library: const NotesLibrary(),
        notes: import.notes,
        book: outcome.unassociated ? null : outcome.book,
      );
      if (!mounted) return;
      await _showNote(
        '已导入 $saved 条笔记'
        '${outcome.unassociated ? '（未关联，可稍后再关联书籍）' : '到《${outcome.book!.title}》'}。',
      );
    } catch (error) {
      if (mounted) await _showNote('导入笔记失败：$error');
    }
  }

  Future<void> _loadUpdateRepo() async {
    final repo = await _library.loadUpdateRepository();
    if (mounted) setState(() => _updateRepo = repo);
  }

  String get _updateRepoLabel {
    final normalized = normalizeUpdateRepository(_updateRepo);
    return normalized ?? vellumDefaultRepository;
  }

  /// Compact form for list rows: \`Murchey/vellum\` instead of \`gitee.com/...\`.
  String get _shortUpdateRepoLabel {
    final full = _updateRepoLabel;
    final hostEnd = full.indexOf('/');
    if (hostEnd < 0 || hostEnd + 1 >= full.length) return full;
    return full.substring(hostEnd + 1);
  }

  Future<void> _editUpdateRepo() async {
    final controller = TextEditingController(text: _updateRepo);
    final next = await showAppDialog<String>(
      context: context,
      title: '更新仓库',
      message:
          '支持 owner/repo、gitee.com/owner/repo 或 github.com/owner/repo；'
          '留空则使用默认仓库。',
      content: CupertinoTextField(
        controller: controller,
        placeholder: vellumDefaultRepository,
        autofocus: true,
        maxLines: 2,
        minLines: 1,
        cursorColor: context.c.primary,
        style: AppText.rowTitle(context.c.foreground),
        decoration: BoxDecoration(
          color: context.c.secondary,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: context.c.border),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x3,
          vertical: 10,
        ),
      ),
      actions: [
        AppDialogAction<String>(label: '恢复默认', value: ''),
        AppDialogAction<String>(
          label: '保存',
          value: controller.text.trim(),
          isDefault: true,
        ),
      ],
    );
    controller.dispose();
    if (next == null || !mounted) return;
    if (next.isNotEmpty && normalizeUpdateRepository(next) == null) {
      await _showNote('格式无效，请填写 owner/repo 或完整 GitHub 地址。');
      return;
    }
    await _library.saveUpdateRepository(next);
    if (!mounted) return;
    setState(() => _updateRepo = next);
  }

  void _refresh() => setState(() => _usage = widget.storageUsage());

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      await checkForUpdates(context, repository: _updateRepo, quiet: false);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  /// In-place outcome feedback. A failure that the reader must act on uses
  /// [AppContentState] instead; an alert is reserved for a decision.
  Future<void> _showNote(String message) =>
      showAppNote(context: context, message: message);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirm(
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: title,
      message: message,
      confirmLabel: '清理',
      destructive: true,
    );
    if (confirmed) {
      await action();
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final hasActiveFont = widget.activeFontName.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.background,
        border: null,
      ),
      // No text-scale clamp: the grouped rows grow with the reader's system
      // font size instead of pinning the page at 1.2.
      //
      // A top-level destination gets a large title in the content area, not an
      // inline navigation title: the title should be worth reading, and it
      // scrolls away with the page instead of eating a bar forever.
      child: AppPage(
        reserveDock: true,
        sections: <Widget>[
          Text('设置', style: AppText.pageTitle(colors.foreground)),
          const SizedBox(height: AppSpace.x6),
          // Group 1 — no header. A header on every block is a wall of labels;
          // only a group that needs distinguishing from its neighbour earns one.
          AppSection(
            children: [
              AppRow(
                leading: Icon(widget.isDark ? AppIcons.sunMax : AppIcons.moon),
                label: '界面主题',
                value: widget.themeModeLabel,
                onTap: widget.onCycleTheme,
              ),
              AppRow(
                leading: const Icon(AppIcons.plusCircle),
                label: '导入字体',
                value: '${widget.installedFonts.length}',
                onTap: widget.onImportFonts,
              ),
              AppRow(
                leading: const Icon(AppIcons.textformat),
                label: '字体列表',
                onTap: () => _showFontManager(context),
              ),
              if (hasActiveFont)
                AppSwitchRow(
                  leading: const Icon(AppIcons.textformatSize),
                  label: '用于界面字体',
                  value: widget.useFontForUi,
                  onChanged: (value) => widget.onFontUsageChanged(
                    useForUi: value,
                    useForContent: widget.useFontForContent,
                  ),
                ),
              AppRow(
                leading: const Icon(AppIcons.docText),
                label: 'MOBI / EPUB 转 TXT',
                onTap: () => Navigator.of(context).push(
                  BookJourneyRoute<void>(
                    builder: (_) => const EbookToTxtPage(),
                  ),
                ),
              ),
              AppRow(
                leading: const Icon(AppIcons.lockShield),
                label: '数据备份',
                value: '本地/云端',
                onTap: () => Navigator.of(context).push(
                  BookJourneyRoute<void>(
                    builder: (_) => const BackupSettingsPage(),
                  ),
                ),
              ),
              AppRow(
                leading: const Icon(AppIcons.speaker1),
                label: '朗读服务（听书）',
                value: 'TTS 接口',
                onTap: () => Navigator.of(context).push(
                  BookJourneyRoute<void>(
                    builder: (_) => const TtsSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          // Group 2 — no header.
          AppSection(
            children: [
              AppRow(
                leading: const Icon(AppIcons.chartBar),
                label: '阅读统计',
                value:
                    '今日 ${ReadingStatsService.formatDuration(_readingStats.todaySeconds)}'
                    ' · 累计 ${ReadingStatsService.formatDuration(_readingStats.totalSeconds)}',
                onTap: () async {
                  await Navigator.of(context).push(
                    BookJourneyRoute<void>(
                      builder: (_) => const ReadingStatsPage(),
                    ),
                  );
                  await _loadReadingStats();
                },
              ),
              AppRow(
                leading: const Icon(AppIcons.docText),
                label: '导出阅读笔记',
                value: 'JSON',
                onTap: _exportNotes,
              ),
              AppRow(
                leading: const Icon(AppIcons.trayArrowDown),
                label: '导入阅读笔记',
                value: 'JSON / 文本',
                onTap: _importNotes,
              ),
              AppRow(
                leading: const Icon(AppIcons.link),
                label: unmatchedBookTitle,
                value: _orphanCount == 0 ? '无' : '$_orphanCount 条',
                onTap: _openUnassociatedNotes,
              ),
              AppRow(
                leading: const Icon(AppIcons.infoCircle),
                label: '当前版本',
                value: _appVersion.isEmpty ? '—' : 'V$_appVersion',
              ),
              AppSelectRow(
                leading: const Icon(AppIcons.arrowDownCircle),
                label: '检查更新',
                value: _checkingUpdate ? '检查中…' : _shortUpdateRepoLabel,
                enabled: !_checkingUpdate,
                onTap: _checkingUpdate ? () {} : _checkForUpdate,
              ),
              AppRow(
                leading: const Icon(AppIcons.gearAlt),
                label: '更新仓库',
                value: '自定义',
                onTap: _editUpdateRepo,
              ),
              AppSwitchRow(
                leading: const Icon(AppIcons.arrow2Circlepath),
                label: '启动时自动检查更新',
                value: _autoCheckUpdate,
                onChanged: _setAutoCheckUpdate,
              ),
            ],
          ),
          // Group 3 — the destructive one. It earns a footer because a reader
          // should be told, once, that this block cannot be undone; folding it
          // into "storage usage" would bury that.
          AppSection(
            footer: '以下操作不可恢复。',
            children: [
              FutureBuilder<StorageUsage>(
                future: _usage,
                builder: (context, snapshot) => AppRow(
                  leading: const Icon(AppIcons.chartBar),
                  label: '占用空间',
                  value: snapshot.data == null
                      ? '计算中…'
                      : _formatBytes(snapshot.data!.totalBytes),
                ),
              ),
              AppRow(
                leading: const Icon(AppIcons.book),
                label: '清空书库',
                destructive: true,
                onTap: () => _confirm(
                  '清空书库？',
                  '将删除已导入的电子书和对应阅读位置，此操作不可恢复。',
                  widget.onClearBooks,
                ),
              ),
              AppRow(
                leading: const Icon(AppIcons.clock),
                label: '清除阅读记录',
                destructive: true,
                onTap: () => _confirm(
                  '清除阅读记录？',
                  '将重置所有书籍的字号、背景、阅读方式和阅读位置。',
                  widget.onClearReadingStates,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFontManager(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => FontManagerSheet(
        installedFonts: widget.installedFonts,
        activeFontName: widget.activeFontName,
        onActivateFont: widget.onActivateFont,
        onDeleteFont: widget.onDeleteFont,
        onImportFonts: widget.onImportFonts,
      ),
    );
  }
}
