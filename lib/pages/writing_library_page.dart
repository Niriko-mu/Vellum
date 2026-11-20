import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/writing_library.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_shadow.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_field.dart';
import '../widgets/ui/app_pressable.dart';
import 'writing_editor_page.dart';
import '../theme/app_icons.dart';
import '../widgets/ui/app_dialog.dart';
import '../widgets/ui/book_motion.dart';

/// Writing tab: list of local drafts, open editor to write .md / .txt.
class WritingPage extends StatefulWidget {
  const WritingPage({this.initialDocuments, super.key});

  /// Optional seed for tests; when null, drafts load from local storage.
  final List<WritingDocument>? initialDocuments;

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage> {
  final _library = const WritingLibrary();
  final _searchController = TextEditingController();
  List<WritingDocument> _documents = [];
  bool _loading = true;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WritingDocument> get _visibleDocuments {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _documents;
    return _documents
        .where(
          (doc) =>
              doc.title.toLowerCase().contains(query) ||
              doc.body.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.initialDocuments;
    if (seed != null) {
      _documents = List.of(seed);
      _loading = false;
      return;
    }
    _reload();
  }

  /// A failed read is not an empty shelf.
  ///
  /// Swallowing the error into an empty list showed "开始写作 / 文稿保存在本机"
  /// over a disk that had failed to open — the one message a writer must never
  /// be shown about their own drafts.
  bool _loadFailed = false;

  Future<void> _reload() async {
    List<WritingDocument> docs;
    var failed = false;
    try {
      docs = await _library.load().timeout(const Duration(seconds: 2));
    } catch (_) {
      docs = [];
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _loadFailed = failed;
      _loading = false;
    });
  }

  Future<void> _createDocument() async {
    final doc = await _library.create();
    if (!mounted) return;
    // The same journey route the reading side uses: the editor is a full-screen
    // paper surface arriving over the list, and it must keep the platform's
    // interactive back gesture rather than replacing it.
    await Navigator.of(context, rootNavigator: true).push<void>(
      BookJourneyRoute<void>(
        builder: (_) => WritingEditorPage(document: doc, onChanged: _reload),
      ),
    );
    await _reload();
  }

  Future<void> _openDocument(WritingDocument doc) async {
    // The same journey route the reading side uses: the editor is a full-screen
    // paper surface arriving over the list, and it must keep the platform's
    // interactive back gesture rather than replacing it.
    await Navigator.of(context, rootNavigator: true).push<void>(
      BookJourneyRoute<void>(
        builder: (_) => WritingEditorPage(document: doc, onChanged: _reload),
      ),
    );
    await _reload();
  }

  Future<void> _importDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'markdown'],
        withData: !Platform.isAndroid,
      );
      if (result == null || !mounted) return;
      final selected = result.files.single;
      final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final isMd =
          selected.name.toLowerCase().endsWith('.md') ||
          selected.name.toLowerCase().endsWith('.markdown');
      final title = selected.name.contains('.')
          ? selected.name.substring(0, selected.name.lastIndexOf('.'))
          : selected.name;
      await _library.create(
        title: title,
        body: text,
        format: isMd ? WritingFormat.md : WritingFormat.txt,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showAppNote(context: context, title: '导入失败', message: '$error');
    }
  }

  Future<void> _confirmDelete(WritingDocument doc) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '删除《${doc.displayTitle}》？',
      message: '文稿将从本机删除，此操作不可恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    await _library.delete(doc.id);
    await _reload();
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (day == today) return '今天 $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hh:$mm';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;
    final accent = context.c.primary;
    final documents = _visibleDocuments;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final columns = MediaQuery.sizeOf(context).width >= 360 && scale <= 1.3
        ? (MediaQuery.sizeOf(context).width >= 760 ? 3 : 2)
        : 1;

    return CupertinoPageScaffold(
      backgroundColor: context.c.background,
      child: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.pageGutter,
                    AppSpace.x6,
                    AppSpace.pageGutter,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('写作', style: AppText.pageTitle(ink)),
                              const SizedBox(height: AppSpace.x1),
                              Text(
                                '${_documents.length} 篇文稿',
                                style: AppText.caption(muted),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label: '导入文稿',
                          button: true,
                          child: AppPressable(
                            onTap: _importDocument,
                            semanticLabel: '导入文稿',
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                AppIcons.squareArrowDown,
                                size: 23,
                                color: ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.pageGutter,
                    AppSpace.x6,
                    AppSpace.pageGutter,
                    AppSpace.x6,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppTextField(
                      controller: _searchController,
                      search: true,
                      placeholder: '搜索文稿',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: AppContentState(kind: AppContentStateKind.loading),
                    ),
                  )
                else if (_loadFailed)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: AppContentState(
                        kind: AppContentStateKind.error,
                        title: '文稿读取失败',
                        description: '本地存储暂时无法打开，文稿没有丢失。',
                        actions: [
                          AppButton(
                            label: '重试',
                            variant: AppButtonVariant.tonal,
                            pill: true,
                            onPressed: () {
                              setState(() => _loading = true);
                              _reload();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_documents.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyWritingState(onCreate: _createDocument),
                  )
                else if (documents.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: AppContentState(
                        kind: AppContentStateKind.empty,
                        icon: AppIcons.search,
                        title: '未找到相关文稿',
                        description: '换个关键词，或者新建一篇。',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.pageGutter,
                      0,
                      AppSpace.pageGutter,
                      // Grid tail plus the floating dock's own height.
                      AppSpace.dockReserve(
                            MediaQuery.viewPaddingOf(context).bottom,
                          ) +
                          48,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpace.x3,
                        mainAxisSpacing: AppSpace.x3,
                        // The card grows with the reader's text size instead of
                        // multiplying a constant by the scale factor.
                        mainAxisExtent:
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(columns == 1 ? 150 : 176) +
                            42,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final doc = documents[index];
                        return _DraftCard(
                          document: doc,
                          date: _formatTime(doc.updatedAt),
                          onOpen: () => _openDocument(doc),
                          onDelete: () => _confirmDelete(doc),
                        );
                      }, childCount: documents.length),
                    ),
                  ),
              ],
            ),
            if (!_loading && _documents.isNotEmpty)
              Positioned(
                right: AppSpace.x6,
                // Above the floating dock, not on top of it.
                bottom:
                    AppSpace.dockReserve(
                      MediaQuery.viewPaddingOf(context).bottom,
                    ) +
                    AppSpace.x2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: AppRadius.pillAll,
                    // One of the three shadows the system allows: the single
                    // filled primary action of a surface.
                    boxShadow: AppShadow.xs(context.c),
                  ),
                  child: AppButton(
                    label: '新建文稿',
                    icon: AppIcons.add,
                    pill: true,
                    onPressed: _createDocument,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.document,
    required this.date,
    required this.onOpen,
    required this.onDelete,
  });

  final WritingDocument document;
  final String date;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;
    return AppPressable(
      onTap: onOpen,
      onLongPress: onDelete,
      borderRadius: AppRadius.groupedAll,
      semanticLabel: document.displayTitle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.x4),
        decoration: BoxDecoration(
          color: context.c.card,
          borderRadius: AppRadius.groupedAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowTitle(ink),
            ),
            const SizedBox(height: AppSpace.x2),
            Expanded(
              child: Text(
                document.preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowDescription(muted),
              ),
            ),
            const SizedBox(height: AppSpace.x3),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(muted),
            ),
            const SizedBox(height: AppSpace.x1),
            Text(
              '${document.characterCount} 字 · ${document.format.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWritingState extends StatelessWidget {
  const _EmptyWritingState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AppContentState(
      kind: AppContentStateKind.empty,
      icon: AppIcons.docText,
      title: '开始写作',
      description: '文稿保存在本机，可随时继续书写。',
      actions: [AppButton(label: '新建文稿', pill: true, onPressed: onCreate)],
    );
  }
}
