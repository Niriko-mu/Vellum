import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/writing_library.dart';
import '../theme/vellum_theme.dart';
import 'writing_editor_page.dart';
import 'writing_style.dart';

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
  List<WritingDocument> _documents = [];
  bool _loading = true;
  String _query = '';

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

  Future<void> _reload() async {
    List<WritingDocument> docs;
    try {
      docs = await _library.load().timeout(const Duration(seconds: 2));
    } catch (_) {
      docs = [];
    }
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _loading = false;
    });
  }

  Future<void> _createDocument() async {
    final doc = await _library.create();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => WritingEditorPage(document: doc, onChanged: _reload),
      ),
    );
    await _reload();
  }

  Future<void> _openDocument(WritingDocument doc) async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
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
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('导入失败'),
          content: Text('$error'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _confirmDelete(WritingDocument doc) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('删除《${doc.displayTitle}》？'),
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
    if (confirmed != true) return;
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
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final documents = _visibleDocuments;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final columns = MediaQuery.sizeOf(context).width >= 360 && scale <= 1.3
        ? (MediaQuery.sizeOf(context).width >= 760 ? 3 : 2)
        : 1;

    return CupertinoPageScaffold(
      backgroundColor: WritingStyle.background(context),
      child: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '写作',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${_documents.length} 篇文稿',
                                style: TextStyle(color: muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label: '导入文稿',
                          button: true,
                          child: CupertinoButton(
                            onPressed: _importDocument,
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              CupertinoIcons.square_arrow_down,
                              size: 23,
                              color: ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  sliver: SliverToBoxAdapter(
                    child: CupertinoSearchTextField(
                      placeholder: '搜索文稿',
                      backgroundColor: WritingStyle.field(context),
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      style: TextStyle(color: ink, fontSize: 15),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CupertinoActivityIndicator()),
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
                      child: Text(
                        '未找到相关文稿',
                        style: TextStyle(color: muted, fontSize: 15),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: (columns == 1 ? 192.0 : 226.0) * scale,
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
                right: 24,
                bottom: 24,
                child: Semantics(
                  label: '新建文稿',
                  button: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .22),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CupertinoButton(
                      padding: const EdgeInsets.all(20),
                      onPressed: _createDocument,
                      child: const Icon(
                        CupertinoIcons.add,
                        size: 28,
                        color: CupertinoColors.white,
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
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      alignment: Alignment.topLeft,
      onPressed: onOpen,
      onLongPress: onDelete,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 17),
        decoration: BoxDecoration(
          color: WritingStyle.paper(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                document.preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 13, height: 1.65),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted.withValues(alpha: .8),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${document.characterCount} 字 · ${document.format.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted.withValues(alpha: .8),
                fontSize: 11,
              ),
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
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 72),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: WritingStyle.paper(context),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(CupertinoIcons.doc_text, size: 38, color: accent),
          ),
          const SizedBox(height: 24),
          Text(
            '开始写作',
            style: TextStyle(
              color: VellumTheme.inkOf(context),
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '文稿保存在本机，可随时继续书写。',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 24),
          CupertinoButton(
            color: accent,
            borderRadius: BorderRadius.circular(18),
            onPressed: onCreate,
            child: const Text(
              '新建文稿',
              style: TextStyle(color: CupertinoColors.white),
            ),
          ),
        ],
      ),
    );
  }
}
