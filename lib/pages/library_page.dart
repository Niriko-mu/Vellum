import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../services/library_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../theme/app_shape.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_field.dart';
import '../widgets/ui/app_pressable.dart';
import '../widgets/ui/app_section.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/shelf_reveal.dart';
import 'book_widgets.dart';
import '../theme/app_icons.dart';
import '../widgets/ui/app_dialog.dart';

class LibraryPage extends StatefulWidget {
  final List<ImportedBook> books;
  final List<LibraryFolder> folders;

  /// Reading progress 0–1 keyed by `book.storageId`, for shelf cards.
  final Map<String, double> progressById;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  final ValueChanged<ImportedBook> onDelete;
  final ValueChanged<ImportedBook>? onEditCover;
  final Future<void> Function(ImportedBook, String? folderId)? onMoveToFolder;
  final Future<void> Function(String name)? onCreateFolder;
  final Future<void> Function(String folderId)? onDeleteFolder;
  final Future<void> Function(String folderId, String name)? onRenameFolder;

  /// Opens the book's details page (cover Hero + metadata) instead of the
  /// reader directly. Distinct from [onOpen] so entries that keep the old
  /// one-tap behaviour can pass the same callback for both.
  final ValueChanged<ImportedBook>? onOpenDetails;

  /// Debug-only seeding hook; null in release builds.
  final VoidCallback? onDebugSeed;

  const LibraryPage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    required this.onDelete,
    this.folders = const [],
    this.progressById = const {},
    this.onEditCover,
    this.onMoveToFolder,
    this.onCreateFolder,
    this.onDeleteFolder,
    this.onRenameFolder,
    this.onOpenDetails,
    this.onDebugSeed,
    super.key,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _folderFilter; // null = all

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ImportedBook> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final book in widget.books)
        if ((_folderFilter == null || book.folderId == _folderFilter) &&
            (q.isEmpty ||
                book.title.toLowerCase().contains(q) ||
                (book.coverText?.toLowerCase().contains(q) ?? false) ||
                book.format.name.toLowerCase().contains(q)))
          book,
    ];
  }

  Future<void> _showBookActions(ImportedBook book) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(book.title),
        actions: [
          if (widget.onEditCover != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onEditCover!(book);
              },
              child: const Text('编辑封面'),
            ),
          if (widget.onMoveToFolder != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showFolderPicker(book);
              },
              child: const Text('移动到文件夹'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _showFolderPicker(ImportedBook book) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _FolderPickerSheet(
        title: '移动到文件夹',
        folders: widget.folders,
        extraActionLabel: widget.onCreateFolder == null ? null : '新建文件夹…',
        onExtraAction: () {
          Navigator.pop(ctx);
          _promptCreateFolder(book);
        },
        trailingAllLabel: '全部（移出文件夹）',
        onSelectAll: () {
          Navigator.pop(ctx);
          widget.onMoveToFolder?.call(book, null);
        },
        onSelect: (folder) {
          Navigator.pop(ctx);
          widget.onMoveToFolder?.call(book, folder.id);
        },
      ),
    );
  }

  Future<void> _promptCreateFolder([ImportedBook? book]) async {
    final controller = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      title: '新建文件夹',
      content: CupertinoTextField(
        controller: controller,
        placeholder: '文件夹名称',
        autofocus: true,
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
        AppDialogAction<String>(
          label: '创建',
          value: controller.text.trim(),
          isDefault: true,
        ),
      ],
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await widget.onCreateFolder?.call(name);
    if (!mounted || book == null) return;
    // Move the book into the newest folder by name match on next frame.
    final created = widget.folders.where((f) => f.name == name).toList();
    final folderId = created.isEmpty ? null : created.last.id;
    if (folderId != null) {
      await widget.onMoveToFolder?.call(book, folderId);
    }
  }

  Future<void> _promptManageFolders() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _FolderPickerSheet(
        title: '文件夹（${widget.folders.length}）',
        folders: widget.folders,
        extraActionLabel: '新建文件夹…',
        onExtraAction: () {
          Navigator.pop(ctx);
          _promptCreateFolder();
        },
        onSelect: (folder) {
          Navigator.pop(ctx);
          _promptFolderOptions(folder);
        },
      ),
    );
  }

  Future<void> _promptFolderOptions(LibraryFolder folder) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(folder.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _promptRenameFolder(folder);
            },
            child: const Text('重命名'),
          ),
          if (widget.onDeleteFolder != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                widget.onDeleteFolder!(folder.id);
              },
              child: const Text('删除文件夹'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _promptRenameFolder(LibraryFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showAppDialog<String>(
      context: context,
      title: '重命名文件夹',
      content: CupertinoTextField(
        controller: controller,
        autofocus: true,
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
        AppDialogAction<String>(
          label: '保存',
          value: controller.text.trim(),
          isDefault: true,
        ),
      ],
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await widget.onRenameFolder?.call(folder.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final showEmptyLibrary = widget.books.isEmpty;
    final showEmptySearch = !showEmptyLibrary && filtered.isEmpty;

    final colors = context.c;
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.background,
        border: null,
        middle: const Text('书库'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onCreateFolder != null)
              AppPressable(
                onTap: _promptManageFolders,
                semanticLabel: '管理文件夹',
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(AppIcons.folder),
                ),
              ),
            AppPressable(
              onTap: widget.onImport,
              semanticLabel: '导入电子书',
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(AppIcons.add),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (!showEmptyLibrary) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pageGutter,
                  AppSpace.x3,
                  AppSpace.pageGutter,
                  AppSpace.x2,
                ),
                child: AppTextField(
                  controller: _searchController,
                  search: true,
                  placeholder: '搜索书名',
                  onChanged: (value) => setState(() => _query = value),
                  trailing: _query.isEmpty
                      ? null
                      : AppPressable(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          semanticLabel: '清除搜索',
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(AppIcons.xmarkCircleFill, size: 16),
                          ),
                        ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.pageGutter,
                  ),
                  children: [
                    _folderChip(id: null, label: '全部'),
                    for (final folder in widget.folders)
                      _folderChip(id: folder.id, label: folder.name),
                  ],
                ),
              ),
            ],
            Expanded(
              child: showEmptyLibrary
                  ? EmptyLibrary(
                      onImport: widget.onImport,
                      onDebugSeed: widget.onDebugSeed,
                    )
                  : showEmptySearch
                  ? Center(
                      child: AppContentState(
                        kind: AppContentStateKind.empty,
                        icon: AppIcons.search,
                        title: _query.trim().isEmpty
                            ? '这个文件夹里还没有书'
                            : '没有找到与「${_query.trim()}」相关的书',
                        description: _query.trim().isEmpty
                            ? '在书库里长按一本书可以把它移到这里。'
                            : '换个关键词，或者清除搜索条件。',
                        actions: [
                          if (_query.trim().isNotEmpty)
                            AppButton(
                              label: '清除搜索',
                              variant: AppButtonVariant.tonal,
                              pill: true,
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Keep covers readable on compact phones while using
                        // the extra width on tablets and desktop windows.
                        final width = constraints.maxWidth;
                        final columns = width < 360
                            ? 2
                            : width < 560
                            ? 3
                            : width < 820
                            ? 4
                            : width < 1120
                            ? 5
                            : 6;
                        return ShelfRevealScope(
                          child: GridView.builder(
                            padding: EdgeInsets.fromLTRB(
                              AppSpace.pageGutter,
                              AppSpace.x2,
                              AppSpace.pageGutter,
                              // The dock floats over the grid; without this the
                              // last row is unreachable.
                              AppSpace.dockReserve(
                                MediaQuery.viewPaddingOf(context).bottom,
                              ),
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: width >= 820 ? 14 : 10,
                                  mainAxisSpacing: 16,
                                  // BookGridCard contains title/meta below its
                                  // cover, so give wider cards a little more
                                  // vertical room to avoid clipped metadata.
                                  childAspectRatio: width >= 820 ? .60 : .55,
                                ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final book = filtered[index];
                              return ShelfRevealItem(
                                index: index,
                                child: BookGridCard(
                                  book: book,
                                  progress:
                                      widget.progressById[book.storageId] ?? 0,
                                  onTap: () => widget.onOpen(book),
                                  onDelete: () => widget.onDelete(book),
                                  onLongPress: () => _showBookActions(book),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderChip({required String? id, required String label}) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.x2),
      child: AppChip(
        label: label,
        selected: _folderFilter == id,
        onTap: () => setState(() => _folderFilter = id),
      ),
    );
  }
}

/// Scrollable bottom sheet for many folders (ActionSheet cannot grow forever).
class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({
    required this.title,
    required this.folders,
    required this.onSelect,
    this.onExtraAction,
    this.extraActionLabel,
    this.onSelectAll,
    this.trailingAllLabel,
  });

  final String title;
  final List<LibraryFolder> folders;
  final ValueChanged<LibraryFolder> onSelect;
  final VoidCallback? onExtraAction;
  final String? extraActionLabel;
  final VoidCallback? onSelectAll;
  final String? trailingAllLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return AppSheet(
      title: title,
      maxHeightFactor: 0.56,
      footer: AppButton(
        label: '取消',
        variant: AppButtonVariant.tonal,
        expand: true,
        onPressed: () => Navigator.pop(context),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.groupedAll,
        child: ColoredBox(
          color: colors.backgroundSubtle,
          child: Column(
            children: [
              if (onSelectAll != null)
                AppRow(label: trailingAllLabel ?? '全部', onTap: onSelectAll!),
              if (extraActionLabel != null && onExtraAction != null)
                AppRow(label: extraActionLabel!, onTap: onExtraAction!),
              for (final folder in folders)
                AppRow(label: folder.name, onTap: () => onSelect(folder)),
            ],
          ),
        ),
      ),
    );
  }
}
