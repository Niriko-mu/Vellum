import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show SystemUiOverlayStyle, Uint8List;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, MaterialApp, Theme, ThemeMode;

import 'pages/book_details_page.dart';
import 'pages/cover_editor_sheet.dart';
import 'pages/library_pages.dart';

import 'pages/settings_page.dart';

import 'pages/update_sheet.dart';

import 'pages/writing_page.dart';

import 'reader/book_reading_host.dart';
import 'pages/book_batch_import_page.dart';

import 'services/book_importer.dart';

import 'services/book_library.dart';
import 'services/font_registry.dart';
import 'services/font_import_service.dart';
import 'services/notes_import.dart';
import 'services/reading_stats.dart';
import 'services/widget_shelf.dart';

import 'theme/app_colors.dart';
import 'widgets/ui/app_dock.dart';
import 'widgets/ui/app_dock_auto_hide.dart';
import 'widgets/ui/book_motion.dart';
import 'theme/app_shape.dart';
import 'theme/app_type.dart';
import 'theme/vellum_theme.dart';
import 'theme/app_icons.dart';
import 'widgets/ui/app_dialog.dart';
import 'widgets/ui/paper_route.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

class VellumApp extends StatefulWidget {
  const VellumApp({super.key});

  @override
  State<VellumApp> createState() => _VellumAppState();
}

class _VellumAppState extends State<VellumApp> with WidgetsBindingObserver {
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  Brightness? _manualBrightness;

  final _library = const BookLibrary();

  List<InstalledFont> _installedFonts = [];
  final _fontImporter = FontImportService();
  bool _importingFonts = false;

  String _activeFontName = '';

  bool _useFontForUi = false;

  bool _useFontForContent = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final fonts = await _library.listFonts();

    final prefs = await _library.loadFontPreferences();

    if (!mounted) return;

    setState(() {
      _installedFonts = fonts;

      _activeFontName = prefs.activeFont;

      _useFontForUi = prefs.useForUi;

      _useFontForContent = prefs.useForContent;
    });

    // 加载激活的字体

    if (_activeFontName.isNotEmpty) {
      await _activateFont(_activeFontName);
    }
  }

  Future<void> _activateFont(String name) async {
    final bytes = await _library.loadFontByName(name);

    if (bytes == null) return;

    final family = 'Font_${name.hashCode.abs()}';

    // Registers at most once per family. A repeated registration does not
    // replace the previous one — the engine keeps every copy for the life of
    // the process, which is what drained the heap during font switching.
    await FontRegistry.load(family, bytes);

    if (!mounted) return;

    setState(() {
      _activeFontName = name;

      VellumTheme.fontFamily = _useFontForUi
          ? family
          : VellumTheme.systemUiFontFamily;

      VellumTheme.contentFontFamily = _useFontForContent ? family : 'serif';
    });

    await _library.saveFontPreferences(
      FontPreferences(
        useForUi: _useFontForUi,

        useForContent: _useFontForContent,

        activeFont: name,
      ),
    );
  }

  Future<void> _importFonts() async {
    if (_importingFonts) return;
    _importingFonts = true;
    final navigator = appNavigatorKey.currentState;
    final progress = ValueNotifier<String>('正在准备字体…');
    CupertinoDialogRoute<void>? route;
    String? summary;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf'],
        withData: false,
        withReadStream: true,
        allowMultiple: true,
      );
      if (result == null || !mounted || navigator == null) return;
      route = CupertinoDialogRoute<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AppDialog(
            title: '正在导入字体',
            message: '导入完成后会告诉你结果。',
            content: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, value, _) => Row(
                children: [
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: AppSpace.x3),
                  Expanded(
                    child: Text(
                      value,
                      style: AppText.rowDescription(context.c.mutedForeground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      unawaited(navigator.push(route));
      final outcomes = await _fontImporter.importFiles(
        result.files,
        onProgress: (done, total, name) =>
            progress.value = '$done/$total  $name',
      );
      await _loadFonts();
      final failed = outcomes.where((item) => item.error != null).toList();
      summary = '成功 ${outcomes.length - failed.length} 个，失败 ${failed.length} 个';
      if (failed.isNotEmpty) {
        summary =
            '$summary\n${failed.map((item) => '${item.filename}：${item.error}').join('\n')}';
      }
    } catch (error) {
      summary = '字体导入失败：$error';
    } finally {
      if (route?.isActive ?? false) navigator?.removeRoute(route!);
      // The route can still be animating out when removed.
      WidgetsBinding.instance.addPostFrameCallback((_) => progress.dispose());
      _importingFonts = false;
    }
    // Every path through the try/catch above assigns a summary, so reaching
    // here always has one to report; only a dismissed picker returns early.
    final host = navigator ?? appNavigatorKey.currentState;
    if (mounted && host != null) {
      await showAppDialog<void>(
        context: host.context,
        title: '字体导入结果',
        message: summary,
        cancelLabel: '完成',
      );
    }
  }

  Future<void> _deleteFont(String name) async {
    await _library.deleteFontByName(name);

    // The engine cannot unload a family, but dropping the bookkeeping lets a
    // later re-import of the same name register its new bytes.
    FontRegistry.forget('Font_${name.hashCode.abs()}');

    if (_activeFontName == name) {
      _activeFontName = '';

      VellumTheme.fontFamily = VellumTheme.systemUiFontFamily;

      VellumTheme.contentFontFamily = 'serif';

      await _library.saveFontPreferences(const FontPreferences());
    }

    await _loadFonts();
  }

  Future<void> _setFontUsage({
    required bool useForUi,

    required bool useForContent,
  }) async {
    final family = _activeFontName.isNotEmpty
        ? 'Font_${_activeFontName.hashCode.abs()}'
        : 'serif';

    setState(() {
      _useFontForUi = useForUi;

      _useFontForContent = useForContent;

      VellumTheme.fontFamily = useForUi && _activeFontName.isNotEmpty
          ? family
          : VellumTheme.systemUiFontFamily;

      VellumTheme.contentFontFamily = useForContent ? family : 'serif';
    });

    await _library.saveFontPreferences(
      FontPreferences(
        useForUi: useForUi,

        useForContent: useForContent,

        activeFont: _activeFontName,
      ),
    );
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _manualBrightness ?? _brightness;
    final family = _useFontForUi && _activeFontName.isNotEmpty
        ? 'Font_${_activeFontName.hashCode.abs()}'
        : VellumTheme.systemUiFontFamily;

    // A Material shell exists for two things only: `ThemeExtension` (which
    // `CupertinoThemeData` cannot carry) and the localizations Material widgets
    // expect. Every visible surface is still Cupertino — `CupertinoTheme` is
    // re-mounted in `builder` so `CupertinoPageScaffold`, the navigation bars and
    // the interactive pop gesture behave exactly as before.
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Vellum',
      theme: VellumTheme.forBrightness(Brightness.light, fontFamily: family),
      darkTheme: VellumTheme.forBrightness(Brightness.dark, fontFamily: family),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final family =
            theme.textTheme.bodyMedium?.fontFamily ??
            VellumTheme.systemUiFontFamily;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Edge-to-edge: the bars are transparent and the page paints behind
          // them; the icons follow the resolved brightness. This is read from
          // the layer tree, so it costs nothing per rebuild — a
          // `SystemChrome.setSystemUIOverlayStyle` call here would cross the
          // platform channel on every tab tap and every theme frame.
          value:
              (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                  .copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Colors.transparent,
                  ),
          child: DefaultTextStyle(
            // MaterialApp ships WidgetsApp with a deliberately loud red-on-yellow
            // error text style as its default. Everything we have not styled
            // explicitly must fall back to the row title instead.
            style: AppText.rowTitle(
              theme.extension<AppColors>()!.foreground,
            ).copyWith(fontFamily: family, decoration: TextDecoration.none),
            child: CupertinoTheme(
              data: VellumTheme.cupertinoOf(context),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: LibraryShell(
        themeModeLabel: _manualBrightness == null
            ? '跟随系统'
            : (_manualBrightness == Brightness.dark ? '深色' : '浅色'),
        onCycleTheme: () => setState(() {
          if (_manualBrightness == null) {
            _manualBrightness = _brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark;
          } else if (_manualBrightness == Brightness.light) {
            _manualBrightness = Brightness.dark;
          } else {
            _manualBrightness = null;
          }
        }),
        isDark: (_manualBrightness ?? _brightness) == Brightness.dark,

        installedFonts: _installedFonts,

        activeFontName: _activeFontName,

        useFontForUi: _useFontForUi,

        useFontForContent: _useFontForContent,

        onImportFonts: _importFonts,

        onActivateFont: _activateFont,

        onDeleteFont: _deleteFont,

        onFontUsageChanged: _setFontUsage,
      ),
    );
  }
}

class LibraryShell extends StatefulWidget {
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

  const LibraryShell({
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

    super.key,
  });

  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell>
    with WidgetsBindingObserver {
  final _books = <ImportedBook>[];

  final _folders = <LibraryFolder>[];

  final _library = const BookLibrary();

  ReadingState? _continueState;
  final Map<String, double> _progressById = {};
  final _widgetShelfSync = const WidgetShelfSync();
  Future<void> _widgetSyncQueue = Future<void>.value();
  Timer? _widgetSyncTimer;
  String? _widgetCurrentBookId;

  /// Tab index as a listenable: tapping a tab changes one int, it does not
  /// rebuild the shell and therefore does not re-run every tab's build.
  final _tab = ValueNotifier<int>(0);

  /// Destinations opened so far. A tab is built on first visit and then kept
  /// alive — the compromise between "nothing is prebuilt" and "all four run
  /// their startup work before the first frame".
  ///
  /// This is a set, not a high-water mark: opening 设置 must not also start the
  /// writing page's two-second load, which is exactly what a max-index check
  /// would do.
  final Set<int> _visitedTabs = {0};

  /// One Navigator per destination, so each keeps its own back stack and its
  /// navigation bar is the only hero in its subtree.
  final List<GlobalKey<NavigatorState>> _tabNavigators = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  bool _importing = false;

  String _importStage = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadLibrary();

    _scheduleUpdateCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetSyncTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queueWidgetShelfSync(immediate: true);
    }
  }

  void _queueWidgetShelfSync({String? currentBookId, bool immediate = false}) {
    if (currentBookId != null) {
      _widgetCurrentBookId = currentBookId;
    }
    _widgetSyncTimer?.cancel();
    if (immediate) {
      _flushWidgetShelfSync();
    } else {
      _widgetSyncTimer = Timer(
        const Duration(seconds: 2),
        _flushWidgetShelfSync,
      );
    }
  }

  void _flushWidgetShelfSync() {
    _widgetSyncTimer = null;
    final snapshot = WidgetShelfSnapshot.fromBooks(
      books: _books,
      progressById: _progressById,
      currentBookId: _widgetCurrentBookId,
    );
    _widgetSyncQueue = _widgetSyncQueue
        .then((_) => _widgetShelfSync.publish(snapshot))
        .catchError((_) {});
  }

  /// Checks the release feed once per launch, a moment after the shelf settles.
  /// Silent when up to date or offline; the setting can turn it off.
  Future<void> _scheduleUpdateCheck() async {
    // Flutter tests set FLUTTER_TEST; a delayed network check would leave a
    // pending timer and is pointless there.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final enabled = await _library.loadAutoUpdateCheck();
      if (!enabled) return;
      final repository = await _library.loadUpdateRepository();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      await checkForUpdates(context, repository: repository);
    } catch (_) {
      // Checking for updates must never get in the way of opening the app.
    }
  }

  Future<void> _loadLibrary() async {
    final books = await _library.load();
    final folders = await _library.loadFolders();

    ReadingState? continueState;
    final progressById = <String, double>{};

    if (books.isNotEmpty) {
      for (final book in books) {
        final state = await _library.loadReadingState(book);
        final total = book.paragraphCount;
        if (total > 1) {
          progressById[book.storageId] = (state.paragraphIndex / (total - 1))
              .clamp(0.0, 1.0);
        }
        if (state.paragraphIndex > 0 || state.page > 0 || state.position > 0) {
          continueState = state;
        }
      }
      continueState ??= await _library.loadReadingState(books.first);
    }

    if (!mounted) return;

    setState(() {
      _books
        ..clear()
        ..addAll(books);

      _folders
        ..clear()
        ..addAll(folders);

      _continueState = continueState;
      _progressById
        ..clear()
        ..addAll(progressById);
    });
    _widgetCurrentBookId = continueState?.bookId;
    _queueWidgetShelfSync(immediate: true);
  }

  Future<void> _importBook() async {
    if (_importing) return;
    final scan = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('导入本地书'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('选择文件（可多选）'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('扫描授权文件夹'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (scan == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final updated = await Navigator.of(context).push<List<ImportedBook>>(
        CupertinoPageRoute(
          builder: (_) => BookBatchImportPage(
            library: _library,
            existing: List.of(_books),
            scanDirectory: scan,
          ),
        ),
      );
      final latest = updated ?? await _library.load();
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(latest);
      });
      _queueWidgetShelfSync(immediate: true);
    } on BookImportException catch (error) {
      if (mounted) await _showError(error.message);
    } catch (error) {
      if (mounted) await _showError('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;

          _importStage = '';
        });
      }
    }
  }

  Future<void> _showError(String message, {String title = '无法导入'}) =>
      showAppNote(context: context, title: title, message: message);

  Future<void> _activateReaderFont(String name) async {
    await widget.onActivateFont(name);
  }

  /// The shelf opens a book through its details page: the cover flies over
  /// (Hero, tagged by storage id), the shelf recedes, and reading stays one
  /// tap away. Metadata only — the body is not loaded until the reader opens.
  Future<void> _openBookDetails(ImportedBook book) async {
    await Navigator.of(context).push(
      BookJourneyRoute<void>(
        builder: (_) => BookDetailsPage(
          book: book,
          progress: _progressById[book.storageId] ?? 0,
          onRead: () => _openBook(book),
          onEditCover: () => _editBookCover(book),
        ),
      ),
    );
    // Returning from the reader via details: refresh what the page shows.
    if (!mounted) return;
    final latest = await _library.loadReadingState(book);
    if (!mounted) return;
    setState(() {
      _continueState = latest;
      _updateWidgetProgress(book, latest);
    });
    _queueWidgetShelfSync(currentBookId: book.storageId, immediate: true);
  }

  Future<void> _openBook(ImportedBook book) async {
    final full = await _library.loadBookContent(book);
    final originalPath = book.format == BookFormat.epub
        ? await _library.originalEpubPath(book.storageId)
        : null;
    final hasOriginal =
        originalPath != null && await File(originalPath).exists();

    final state = await _library.loadReadingState(full);

    _continueState = state;
    _widgetCurrentBookId = full.storageId;
    _updateWidgetProgress(full, state);
    _queueWidgetShelfSync(currentBookId: full.storageId, immediate: true);

    if (!mounted) return;

    await Navigator.of(context).push(
      // The reader is the one destination that replaces the whole screen: it
      // dissolves in instead of arriving as a finished slab (see PaperRoute).
      PaperRoute<void>(
        builder: (_) => BookReadingHost(
          book: full,
          originalPath: hasOriginal ? originalPath : null,

          initialState: state,

          onStateChanged: (value) async {
            await _library.saveReadingState(full, value);
            _continueState = value;
            _widgetCurrentBookId = full.storageId;
            _updateWidgetProgress(full, value);
            _queueWidgetShelfSync(currentBookId: full.storageId);
          },

          installedFonts: widget.installedFonts,

          activeFontName: widget.activeFontName,

          onActivateFont: _activateReaderFont,

          onToggleUiTheme: widget.onCycleTheme,
        ),
      ),
    );

    if (!mounted) return;

    final latest = await _library.loadReadingState(full);

    if (mounted) {
      setState(() => _continueState = latest);
      _widgetCurrentBookId = full.storageId;
      _updateWidgetProgress(full, latest);
      _queueWidgetShelfSync(currentBookId: full.storageId, immediate: true);
    }
  }

  void _updateWidgetProgress(ImportedBook book, ReadingState state) {
    final total = book.paragraphCount;
    _progressById[book.storageId] = total > 1
        ? (state.paragraphIndex / (total - 1)).clamp(0.0, 1.0)
        : 0.0;
  }

  Future<void> _editBookCover(ImportedBook book) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CoverEditorSheet(
        book: book,
        onSave:
            ({
              Uint8List? coverBytes,
              String? coverText,
              bool clearCoverImage = false,
              bool clearCoverText = false,
            }) async {
              await _library.updateBookCover(
                book,
                coverBytes: coverBytes,
                coverText: coverText,
                clearCoverImage: clearCoverImage,
                clearCoverText: clearCoverText,
              );
              if (!mounted) return;
              final updated = book.copyWith(
                coverBytes: coverBytes,
                coverText: coverText,
                clearCoverImage: clearCoverImage,
                clearCoverText: clearCoverText,
              );
              setState(() {
                final i = _books.indexWhere(
                  (b) => b.storageId == book.storageId,
                );
                if (i >= 0) _books[i] = updated;
              });
            },
      ),
    );
  }

  Future<void> _moveBookToFolder(ImportedBook book, String? folderId) async {
    await _library.setBookFolder(book, folderId);
    if (!mounted) return;
    final updated = folderId == null
        ? book.copyWith(clearFolder: true)
        : book.copyWith(folderId: folderId);
    setState(() {
      final i = _books.indexWhere((b) => b.storageId == book.storageId);
      if (i >= 0) _books[i] = updated;
    });
  }

  Future<void> _createFolder(String name) async {
    final folder = await _library.createFolder(name);
    if (!mounted) return;
    setState(() => _folders.add(folder));
  }

  Future<void> _deleteFolder(String folderId) async {
    await _library.deleteFolder(folderId);
    if (!mounted) return;
    setState(() {
      _folders.removeWhere((f) => f.id == folderId);
      for (var i = 0; i < _books.length; i++) {
        if (_books[i].folderId == folderId) {
          _books[i] = _books[i].copyWith(clearFolder: true);
        }
      }
    });
  }

  Future<void> _renameFolder(String folderId, String name) async {
    await _library.renameFolder(folderId, name);
    if (!mounted) return;
    setState(() {
      final i = _folders.indexWhere((f) => f.id == folderId);
      if (i >= 0) {
        _folders[i] = LibraryFolder(id: folderId, name: name);
      }
    });
  }

  Future<void> _deleteBook(ImportedBook book) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '删除这本书？',
      message: '《${book.title}》和它的阅读记录将被删除，此操作不可恢复。',
      confirmLabel: '删除',
      destructive: true,
    );

    if (!confirmed) return;

    setState(() => _books.remove(book));

    await _library.saveIndex(_books);

    await _library.deleteBook(book);

    await _library.deleteReadingState(book);

    if (_widgetCurrentBookId == book.storageId) {
      _widgetCurrentBookId = _books.isEmpty ? null : _books.first.storageId;
    }
    _progressById.remove(book.storageId);
    _queueWidgetShelfSync(immediate: true);

    // Drop the per-book reading-time row so stats never show 未知书籍.
    await const ReadingStatsService().removeBook(book.storageId);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The shell fills the window. Without this the inner stack — a
      // non-positioned child — is measured loosely and shrinks to its
      // content, which floated the dock up the screen instead of pinning it.
      fit: StackFit.expand,
      children: [
        // The dock and the page live in one wrapper so the dock can answer the
        // page's scroll without any page knowing about it. A destination is
        // built the first time it is opened and then stays mounted, so scroll
        // offsets, open sheets and drafts survive a dock tap — but only the
        // visible one is on stage. Offstage (rather than
        // IndexedStack) also keeps the hidden pages out of the hero and focus
        // trees: two CupertinoNavigationBars both "on stage" claim the same
        // default hero tag and break the push animation.
        ValueListenableBuilder<int>(
          valueListenable: _tab,
          builder: (context, index, _) => AppDockAutoHide(
            key: const Key('app-dock-shell'),
            bottomInset: MediaQuery.viewPaddingOf(context).bottom,
            dock: _FloatingDock(
              tab: _tab,
              bottomInset: MediaQuery.viewPaddingOf(context).bottom,
              onOpen: (value) {
                if (_visitedTabs.contains(value)) return;
                setState(() => _visitedTabs.add(value));
              },
            ),
            page: Stack(
              fit: StackFit.expand,
              children: [
                // A destination is built the first time it is opened and then
                // stays mounted, so scroll offsets, open sheets and drafts
                // survive a dock tap. Unvisited tabs are an empty box of the same
                // size: identical layout, none of that page's startup work.
                for (var i = 0; i < 4; i++)
                  if (!_visitedTabs.contains(i))
                    const SizedBox.expand()
                  else
                    // Only the visible destination is on stage: an offstage page
                    // must not take taps (it does if it is a Stack child with no
                    // hit-test guard) and must not join the hero or focus trees,
                    // where two CupertinoNavigationBars claim the same default
                    // hero tag and break the push animation.
                    //
                    // Each destination owns a Navigator, so a page opened from
                    // 书库 keeps its back stack while the reader is on screen.
                    Offstage(
                      offstage: i != index,
                      child: TickerMode(
                        enabled: i == index,
                        child: Navigator(
                          key: _tabNavigators[i],
                          onGenerateRoute: (settings) => PageRouteBuilder<void>(
                            settings: settings,
                            pageBuilder: (_, _, _) => KeyedSubtree(
                              key: ValueKey<int>(i),
                              child: switch (i) {
                                0 => HomePage(
                                  books: _books,
                                  continueState: _continueState,
                                  onOpen: _openBook,
                                  onOpenDetails: _openBookDetails,
                                  onImport: _importBook,
                                ),
                                1 => LibraryPage(
                                  books: _books,
                                  folders: _folders,
                                  progressById: _progressById,
                                  onOpen: _openBookDetails,
                                  onOpenDetails: _openBookDetails,
                                  onImport: _importBook,
                                  onDelete: _deleteBook,
                                  onEditCover: _editBookCover,
                                  onMoveToFolder: _moveBookToFolder,
                                  onCreateFolder: _createFolder,
                                  onDeleteFolder: _deleteFolder,
                                  onRenameFolder: _renameFolder,
                                ),
                                2 => const WritingPage(),
                                _ => SettingsPage(
                                  onCycleTheme: widget.onCycleTheme,
                                  themeModeLabel: widget.themeModeLabel,
                                  isDark: widget.isDark,
                                  installedFonts: widget.installedFonts,
                                  activeFontName: widget.activeFontName,
                                  useFontForUi: widget.useFontForUi,
                                  useFontForContent: widget.useFontForContent,
                                  onImportFonts: widget.onImportFonts,
                                  onActivateFont: widget.onActivateFont,
                                  onDeleteFont: widget.onDeleteFont,
                                  onFontUsageChanged: widget.onFontUsageChanged,
                                  storageUsage: _library.storageUsage,
                                  availableBooks: exportableBooks(_books),
                                  onClearBooks: () async {
                                    await _library.clearBooks();
                                    await _library.clearReadingStates();
                                    if (mounted) {
                                      setState(() => _books.clear());
                                      _progressById.clear();
                                      _widgetCurrentBookId = null;
                                      _queueWidgetShelfSync(immediate: true);
                                    }
                                  },
                                  onClearReadingStates:
                                      _library.clearReadingStates,
                                ),
                              },
                            ),
                            transitionsBuilder: (_, _, _, child) => child,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),

        // Import progress paints above the dock: it is a modal outcome, not
        // page content.
        if (_importing)
          Positioned.fill(
            child: ColoredBox(
              color: context.c.scrim,

              child: Center(
                child: Container(
                  width: 280,

                  padding: const EdgeInsets.all(AppSpace.x6),

                  decoration: BoxDecoration(
                    color: context.c.popover,

                    borderRadius: AppRadius.xl3All,
                  ),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      const CupertinoActivityIndicator(radius: 14),

                      const SizedBox(height: AppSpace.x5),

                      Text(
                        '正在导入电子书',

                        style: AppText.sectionHeader(context.c.foreground),
                      ),

                      const SizedBox(height: AppSpace.x2),

                      Text(
                        _importStage,

                        textAlign: TextAlign.center,

                        style: AppText.rowDescription(
                          context.c.mutedForeground,
                        ),
                      ),

                      const SizedBox(height: AppSpace.x3),

                      Text(
                        '大型 MOBI 需要一点时间，请不要关闭应用。',

                        textAlign: TextAlign.center,

                        style: AppText.caption(context.c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The dock sits above the page and drives the same [ValueNotifier] the pages
/// read, so a tap changes one integer and repaints two widgets.
class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.tab,
    required this.bottomInset,
    this.onOpen,
  });

  final ValueNotifier<int> tab;
  final double bottomInset;

  /// Lets the shell record the highest destination visited so the stack can
  /// stop rendering empty boxes for tabs that have been opened.
  final ValueChanged<int>? onOpen;

  static const _items = <AppDockItem>[
    AppDockItem(
      icon: AppIcons.book,
      selectedIcon: AppIcons.bookSolid,
      label: '阅读',
    ),
    AppDockItem(
      icon: AppIcons.squareStack3dUp,
      selectedIcon: AppIcons.squareStack3dUpFill,
      label: '书库',
    ),
    AppDockItem(
      icon: AppIcons.pencil,
      selectedIcon: AppIcons.pencil,
      label: '写作',
    ),
    AppDockItem(
      icon: AppIcons.gear,
      selectedIcon: AppIcons.gearSolid,
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: tab,
    builder: (context, index, _) => AppDock(
      items: _items,
      index: index,
      bottomInset: bottomInset,
      onSelected: (value) {
        onOpen?.call(value);
        tab.value = value;
      },
    ),
  );
}
