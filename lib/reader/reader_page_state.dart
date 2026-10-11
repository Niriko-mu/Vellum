import '../services/txt_seek_source.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'reader_gestures.dart';
import 'reader_models.dart';
import 'reader_pagination.dart';
import 'reader_platform.dart';
import 'reader_page_notes_controller.dart';
import 'reader_page_pagination_controller.dart';
import 'reader_page_paper_controller.dart';
import 'reader_page_progress_controller.dart';
import 'reader_page_reading_session.dart';
import 'reader_selection.dart';
import '../pages/tts_settings_page.dart';
import '../services/tts_client.dart' show TtsException;
import '../services/tts_preferences.dart';
import 'tts_audio_handler.dart';
import '../services/listening_library.dart';
import '../services/reader_background.dart';

import 'reader_page_state_pagination.dart';
import 'reader_page_state_gestures.dart';
import 'reader_page_state_surface_rendering.dart';

class ReaderPage extends StatefulWidget {
  final ImportedBook book;
  final ReadingState initialState;
  final Future<void> Function(ReadingState)? onStateChanged;
  final List<InstalledFont> installedFonts;
  final String activeFontName;
  final Future<void> Function(String)? onActivateFont;
  final VoidCallback? onToggleUiTheme;
  const ReaderPage({
    required this.book,
    this.initialState = const ReadingState(),
    this.onStateChanged,
    this.installedFonts = const [],
    this.activeFontName = '',
    this.onActivateFont,
    this.onToggleUiTheme,
    super.key,
  });

  @override
  State<ReaderPage> createState() => ReaderPageState();
}

class ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late double fontSize;
  late String readerFontFamily;
  late ReaderFontWeight readerFontWeight;
  late ReaderLineSpacing lineSpacing;
  late final ReaderPaperController paperController;
  Color? get background => paperController.background;
  late ReadingMode readingMode;
  late PageTurnStyle pageTurnStyle;
  late final AnimationController coverAnim;
  int? coverFromPage;
  int? coverToPage;
  bool coverJumping = false;
  int pendingPageDelta = 0;
  bool slideBusy = false;
  // Finger-driven page turn: overlay tracks the drag, then finishes or
  // springs back on release. This is what makes swipes 跟手.
  bool dragTurn = false;
  bool dragCommitted = false;
  int? dragFromPage;
  int? dragToPage;
  double dragProgress = 0;
  double dragLastTravel = 0;
  int dragLastMicros = 0;
  double dragVelocity = 0;
  final notesLibrary = const NotesLibrary();
  late final ReaderNotesController notesController;
  String lastSelectedText = '';
  bool showControls = false;
  // Listening (听书): playback lives in the app-wide handler; the page
  // only mirrors its state.
  bool listening = false;
  double ttsSpeed = 1.0;
  String ttsLabel = '';
  String spokenSentence = '';
  double get paperImageOpacity => paperController.imageOpacity;
  ImageProvider? get paperImageProvider => paperController.imageProvider;
  Timer? tapTimer;
  Offset? pendingTapPos;
  ReaderTapAction? pendingTapAction;
  StreamSubscription? ttsStateSub;

  late final ScrollController scrollController;
  late final PageController pageController;
  int currentPage = 0;
  int requestedPage = 0;
  int currentParagraph = 0;
  late final ReaderProgressController progressController;
  int get resumeParagraphIndex => progressController.resumeParagraphIndex;
  set resumeParagraphIndex(int value) =>
      progressController.resumeParagraphIndex = value;
  int jumpGeneration = 0;
  Map<int, ChapterReadingPosition> get chapterPositions =>
      progressController.chapterPositions;
  late List<int> bookmarks;
  bool bookmarkPullArmed = false;
  bool bookmarkPullHandled = false;
  double pullDownDistance = 0;
  String? bookmarkNotice;
  Timer? bookmarkNoticeTimer;
  int batteryLevel = -1;
  Timer? batteryRefreshTimer;
  Timer? saveTimer;
  Future<void> saveQueue = Future<void>.value();
  DateTime? readerPointerDownAt;
  Offset? readerPointerDownPosition;
  bool pointerLooksLikeSelection = false;
  bool bookmarkPullInProgress = false;
  int pageBeforePointerDown = 0;
  Timer? selectionHoldTimer;
  final Map<int, GlobalKey> paragraphKeys = {};
  int scrollAnchor = 0;
  bool scrollPositionRestored = false;
  bool pagePositionRestored = false;
  int scrollRestoreAttempts = 0;
  late double brightness;
  late ReaderEyeCare eyeCare;
  late bool keepScreenOn;
  late bool volumeKeys;
  final platform = const ReaderPlatform();

  /// Highlights and notes for this book, newest first, plus a paragraph-keyed
  /// view so rendering never scans the whole list.
  List<ReadingNote> get notes => notesController.notes;
  Map<int, List<String>> get highlights => notesController.highlights;

  /// Query the reader arrived at from a search result, marked in the body so the
  /// passage they searched for is visible after the search panel closes.
  ///
  /// Cleared as soon as the reader turns the page or scrolls away from it.
  String searchHighlight = '';

  /// Set while the search jump's own page change is still in flight, so that
  /// change does not immediately clear the mark it just placed.
  bool searchHighlightSurvivesNextTurn = false;

  /// Scroll offset the search mark was placed at (scroll mode), so scrolling
  /// away from it clears the mark.
  double? searchHighlightScrollOffset;
  static const double searchHighlightScrollDistance = 260;

  /// Chapter entries are scanned once: the footer needs them on every frame.
  List<MapEntry<int, String>> get chapters => progressController.chapters;

  /// Table-of-contents paragraph indexes, for heading detection in O(1).
  Set<int> get tocParagraphs => progressController.tocParagraphs;

  late final ReaderPaginationController pagination;
  ProgressiveBookPager get pager => pagination.pager;
  List<List<PageFragment>> get pages => pagination.pages;
  int get pageCount => pagination.pageCount;

  late final ReaderReadingSession readingSession;
  ValueNotifier<int> get sessionSeconds => readingSession.sessionSeconds;
  ValueNotifier<int> get todaySeconds => readingSession.todaySeconds;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    progressController = ReaderProgressController(
      book: widget.book,
      initialState: widget.initialState,
    );
    readingSession = ReaderReadingSession(bookId: widget.book.storageId);
    paperController = ReaderPaperController(
      initialBackground: VellumTheme.normalizeReaderBackground(
        widget.initialState.backgroundValue == null
            ? null
            : Color(widget.initialState.backgroundValue!),
      ),
    );
    notesController = ReaderNotesController(
      bookId: widget.book.storageId,
      bookTitle: widget.book.title,
      library: notesLibrary,
    );
    fontSize = widget.initialState.fontSize;
    readerFontFamily = widget.initialState.readerFontFamily;
    readerFontWeight = ReaderFontWeight.fromStorage(
      widget.initialState.readerFontWeight,
    );
    lineSpacing = ReaderLineSpacing.fromStorage(
      widget.initialState.lineSpacing,
    );
    bookmarks = widget.initialState.bookmarks.toSet().toList()..sort();
    readingMode = widget.initialState.mode == 'page'
        ? ReadingMode.page
        : ReadingMode.scroll;
    pageTurnStyle = PageTurnStyle.fromStorage(widget.initialState.pageTurn);
    brightness = widget.initialState.brightness;
    eyeCare = ReaderEyeCare.fromStorage(widget.initialState.eyeCare);
    keepScreenOn = widget.initialState.keepScreenOn;
    volumeKeys = widget.initialState.volumeKeys;
    pagination = ReaderPaginationController(book: widget.book);
    coverAnim = AnimationController(
      vsync: this,
      // Fanqie's page-turn animation is short enough to feel immediate; a
      // 240ms ease-in-out reads as "waiting for the app" instead of turning.
      duration: const Duration(milliseconds: 200),
    );
    scrollController = ScrollController()
      ..addListener(() {
        scheduleSave();
        if (readingMode != ReadingMode.scroll || !mounted) return;
        // Scrolling away from a search result drops its mark, the same way
        // turning a page does.
        final markAt = searchHighlightScrollOffset;
        if (markAt != null &&
            (scrollController.offset - markAt).abs() >
                searchHighlightScrollDistance) {
          searchHighlightScrollOffset = null;
          clearSearchHighlight();
        }
        final estimated =
            scrollAnchor +
            (scrollController.offset / (fontSize * (lineSpacing.height + 1.3)))
                .floor();
        final clamped = estimated.clamp(
          0,
          widget.book.paragraphs.isEmpty
              ? 0
              : widget.book.paragraphs.length - 1,
        );
        if (clamped != currentParagraph) {
          setState(() => currentParagraph = clamped);
        }
      });
    pageController = PageController()..addListener(scheduleSave);
    loadBatteryLevel();
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      // Battery percentage changes slowly; a one-minute poll keeps the tiny
      // footer current during a long reading session without listening to a
      // platform-specific battery broadcast stream.
      batteryRefreshTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => loadBatteryLevel(),
      );
    }
    startReadingTimer();
    loadTodayReading();
    loadNotes();
    loadPaper();
    syncPlatformSettings();
    final paragraphs = widget.book.paragraphs;
    if (paragraphs is TxtParagraphList) {
      txtReady = false;
      paragraphs.source
          .prefetchAroundParagraph(widget.initialState.paragraphIndex)
          .then(
            (_) {
              if (mounted) setState(() => txtReady = true);
            },
            onError: (Object _) {
              if (mounted) setState(() => txtReady = true);
            },
          );
    }
  }

  bool txtReady = true;

  /// Screen brightness / keep-awake / volume-key paging are window-level
  /// settings on Android, so they follow the reader's lifetime.
  Future<void> syncPlatformSettings() async {
    await platform.setBrightness(brightness);
    await platform.setKeepScreenOn(keepScreenOn);
    await syncVolumeKeys();
  }

  Future<void> syncVolumeKeys() async {
    await platform.setVolumeKeyPaging(volumeKeys);
    platform.listenForVolumeKeys(volumeKeys ? handleVolumeKey : null);
  }

  DateTime? lastVolumeTurn;

  void handleVolumeKey(int direction) {
    if (!mounted || !volumeKeys) return;
    // Fanqie throttles volume-key paging to 300 ms so a held key does not
    // flip dozens of pages.
    final now = DateTime.now();
    final last = lastVolumeTurn;
    if (last != null &&
        now.difference(last) < ReaderGestures.volumeKeyThrottle) {
      return;
    }
    lastVolumeTurn = now;
    // Listening: volume keys step sentences (reference input matrix).
    final handler = ttsHandler;
    if (handler != null && handler.hasBook) {
      if (direction > 0) {
        handler.skipToNext();
      } else {
        handler.skipToPrevious();
      }
      return;
    }
    if (readingMode == ReadingMode.page) {
      changePage(context, direction);
      return;
    }
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (!position.hasPixels || !position.haveDimensions) return;
    final delta = position.viewportDimension * .9 * direction;
    scrollController.jumpTo(
      (scrollController.offset + delta).clamp(0.0, position.maxScrollExtent),
    );
    scheduleSave();
  }

  Future<void> loadNotes() async {
    await notesController.load();
    if (!mounted) return;
    setState(() {});
  }

  int noteCountFor(int paragraphIndex) =>
      notesController.noteCountFor(paragraphIndex);

  void openNotesForParagraph(int paragraphIndex) {
    final notes = notesController.notesForParagraph(paragraphIndex);
    if (notes.isEmpty) return;
    showParagraphNotesSheet(
      context,
      bookId: bookId,
      bookTitle: widget.book.title,
      paragraphIndex: paragraphIndex,
      notes: notes,
      notesLibrary: notesLibrary,
      onChanged: loadNotes,
    );
  }

  /// Toggles a highlight for the selected passage — selecting it again removes
  /// it, which is how the reader-style apps behave.
  Future<void> toggleHighlight(String selected, int paragraphIndex) async {
    final added = await notesController.toggleHighlight(
      selected,
      paragraphIndex,
    );
    if (mounted) {
      showBookmarkNotice(added ? '已划线，可在目录的「笔记」里查看' : '已取消划线');
      setState(() {});
    }
  }

  Future<void> removeNote(String id) async {
    await notesController.removeNote(id);
    if (!mounted) return;
    setState(() {});
  }

  String get bookId => widget.book.storageId;

  Future<void> loadTodayReading() async {
    await readingSession.loadToday();
  }

  void startReadingTimer() {
    readingSession.start();
  }

  void pauseReadingTimer() {
    readingSession.pause();
  }

  void restoreScrollPositionWhenReady() {
    if (scrollPositionRestored || readingMode != ReadingMode.scroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scrollPositionRestored) return;
      if (!scrollController.hasClients) {
        scrollRestoreAttempts++;
        if (scrollRestoreAttempts < 8) restoreScrollPositionWhenReady();
        return;
      }
      final paragraph = widget.initialState.paragraphIndex.clamp(
        0,
        widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
      );
      jumpToScrollParagraph(paragraph);
      scrollPositionRestored = true;
    });
  }

  Future<void> loadBatteryLevel() async {
    try {
      final level = await const MethodChannel(
        'vellum/device',
      ).invokeMethod<int>('batteryLevel');
      if (mounted && level != null && level != batteryLevel) {
        setState(() => batteryLevel = level);
      }
    } on PlatformException {
      // Battery information is optional on non-Android targets.
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      startReadingTimer();
      loadBatteryLevel();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      pauseReadingTimer();
      saveTimer?.cancel();
      await saveState();
    }
  }

  @override
  void dispose() {
    // Stops the background pagination loop before it schedules another yield.
    pagination.dispose();
    final paragraphs = widget.book.paragraphs;
    if (paragraphs is TxtParagraphList) paragraphs.source.close();
    WidgetsBinding.instance.removeObserver(this);
    tapTimer?.cancel();
    ttsStateSub?.cancel();
    detachTtsCallbacks();
    selectionHoldTimer?.cancel();
    batteryRefreshTimer?.cancel();
    readingSession.dispose();
    saveTimer?.cancel();
    bookmarkNoticeTimer?.cancel();
    saveState();
    // Release the window-level reader settings.
    platform.listenForVolumeKeys(null);
    platform.setBrightness(-1);
    platform.setKeepScreenOn(false);
    platform.setVolumeKeyPaging(false);
    coverAnim.dispose();
    scrollController.dispose();
    pageController.dispose();
    super.dispose();
  }

  Future<void> setReadingMode(ReadingMode mode) async {
    if (readingMode == mode) return;
    setState(() {
      readingMode = mode;
      scrollPositionRestored = mode == ReadingMode.scroll ? false : true;
      scrollRestoreAttempts = 0;
    });
    saveTimer?.cancel();
    await saveState();
  }

  void showBookmarkNotice(String message) {
    bookmarkNoticeTimer?.cancel();
    setState(() => bookmarkNotice = message);
    bookmarkNoticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => bookmarkNotice = null);
    });
  }

  void performBookmarkPullToggle() {
    if (bookmarkPullHandled) return;
    bookmarkPullHandled = true;
    bookmarkPullArmed = false;
    HapticFeedback.selectionClick();
    toggleBookmarkAtCurrentPosition();
  }

  Future<void> addBookmarkAtCurrentPosition() async {
    if (widget.book.paragraphs.isEmpty) return;
    final paragraph = activeParagraph.clamp(
      0,
      widget.book.paragraphs.length - 1,
    );
    if (bookmarks.contains(paragraph)) {
      showBookmarkNotice('此处已有书签');
      return;
    }
    setState(() {
      bookmarks = [...bookmarks, paragraph]..sort();
    });
    await saveState();
    if (mounted) showBookmarkNotice('书签已添加');
  }

  Future<void> toggleBookmarkAtCurrentPosition() async {
    if (widget.book.paragraphs.isEmpty) return;
    final paragraph = activeParagraph.clamp(
      0,
      widget.book.paragraphs.length - 1,
    );
    if (bookmarks.contains(paragraph)) {
      await removeBookmark(paragraph);
      if (mounted) showBookmarkNotice('书签已取消');
    } else {
      await addBookmarkAtCurrentPosition();
    }
  }

  /// Reading paper: presets keep their theme-tuned look; custom colours and
  /// local images switch body ink by the three-tone slot (reference
  /// ReaderBgColorType). Paper / eye-care / brightness stay orthogonal.
  ReaderBackground get paper => paperController.value;

  Color get readerInk => paperController.readerInk;

  /// Paper stack: underlay colour + optional image at [imageOpacity].
  /// The cached provider prevents page turns from re-decoding the image.
  Widget paperSurface(BuildContext context) {
    final provider = paperImageProvider;
    final underlay = backgroundFor(context);
    if (provider == null) return ColoredBox(color: underlay);
    final opacity = paperImageOpacity.clamp(0.0, 1.0);
    return ColoredBox(
      color: underlay,
      child: opacity <= 0
          ? const SizedBox.expand()
          : Opacity(
              opacity: opacity,
              child: Image(
                image: provider,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            ),
    );
  }

  Widget paperLayer(BuildContext context) =>
      Positioned.fill(child: RepaintBoundary(child: paperSurface(context)));

  Future<void> loadPaper() async {
    await paperController.load(bookId: bookId);
    if (mounted) setState(() {});
  }

  Future<void> applyPaper(ReaderBackground value) async {
    await paperController.apply(value, bookId: bookId);
    if (!mounted) return;
    setState(() {});
    scheduleSave();
  }

  /// Paragraph the listen feature should start from: the one in the middle
  /// of the screen in scroll mode, the first one on the page in page mode.
  int listenStartParagraph() {
    if (readingMode == ReadingMode.page) return firstParagraphOfCurrentPage();
    if (!scrollController.hasClients) return currentParagraph;
    final size = MediaQuery.sizeOf(context);
    final centerY = size.height / 2;
    var best = currentParagraph;
    var bestDistance = double.infinity;
    for (final entry in paragraphKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final distance = (topLeft.dy + box.size.height / 2 - centerY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry.key;
      }
    }
    final max = widget.book.paragraphs.length - 1;
    return best < 0 ? 0 : (best > max ? max : best);
  }

  Future<void> startListening() async {
    final handler = ttsHandler;
    if (handler == null || widget.book.paragraphs.isEmpty) return;
    final preferences = await const TtsPreferencesStore().load();
    if (!mounted) return;
    if (!preferences.isConfigured) {
      final go = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('未配置朗读服务'),
          content: const Text('先填写 TTS 接口地址和 API Key，之后就能从当前页开始听书。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      await Navigator.of(
        context,
      ).push(CupertinoPageRoute(builder: (_) => const TtsSettingsPage()));
      return;
    }

    // Continue where the last session stopped (local key_is_tts memory).
    final remembered = await const ListeningLibrary().load(bookId);
    if (!mounted) return;
    var startParagraph = listenStartParagraph();
    var startSentence = 0;
    if (remembered != null && remembered.paragraphIndex != startParagraph) {
      final resume = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('继续听书？'),
          content: Text('上次听到第 ${remembered.paragraphIndex + 1} 段。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('从本页开始'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续上次'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == true) {
        startParagraph = remembered.paragraphIndex;
        startSentence = remembered.sentenceIndex;
      }
    }
    handler.onSentenceChanged = (paragraphIndex, sentenceIndex, text) {
      if (!mounted) return;
      setState(() {
        currentParagraph = paragraphIndex;
        spokenSentence = text;
      });
      jumpToParagraph(paragraphIndex);
      const ListeningLibrary().save(
        bookId,
        ListeningPosition(
          paragraphIndex: paragraphIndex,
          sentenceIndex: sentenceIndex,
        ),
      );
    };
    handler.onError = onTtsError;
    ttsStateSub?.cancel();
    ttsStateSub = handler.playbackState.listen((state) {
      if (!mounted) return;
      setState(() {
        listening = state.playing || handler.hasBook;
        ttsLabel = handler.positionLabel;
        ttsSpeed = handler.preferences?.speed ?? ttsSpeed;
      });
    });

    await handler.startBook(
      bookId: bookId,
      bookTitle: widget.book.title,
      paragraphs: widget.book.paragraphs,
      startParagraph: startParagraph,
      startSentence: startSentence,
    );
    if (!mounted) return;
    setState(() {
      listening = true;
      showControls = false;
    });
  }

  void onTtsError(TtsException error) {
    if (!mounted) return;
    showBookmarkNotice(error.userMessage);
    setState(() => listening = false);
  }

  Future<void> stopListening() async {
    final handler = ttsHandler;
    if (handler == null) return;
    ttsStateSub?.cancel();
    ttsStateSub = null;
    detachTtsCallbacks();
    await handler.stop();
    if (!mounted) return;
    setState(() {
      listening = false;
      spokenSentence = '';
    });
  }

  void detachTtsCallbacks() {
    final handler = ttsHandler;
    if (handler == null) return;
    if (handler.onSentenceChanged != null) handler.onSentenceChanged = null;
    if (handler.onError != null) handler.onError = null;
  }

  static const ttsSpeedSteps = [0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> cycleTtsSpeed() async {
    final handler = ttsHandler;
    if (handler == null) return;
    final current = handler.preferences?.speed ?? 1.0;
    final next = ttsSpeedSteps.firstWhere(
      (speed) => speed > current + 0.01,
      orElse: () => ttsSpeedSteps.first,
    );
    setState(() => ttsSpeed = next);
    await handler.setSpeed(next);
  }

  Future<void> removeBookmark(int paragraph) async {
    if (!bookmarks.contains(paragraph)) return;
    setState(() => bookmarks.remove(paragraph));
    await saveState();
  }

  bool handleBookmarkPull(ScrollNotification notification) {
    if (readingMode != ReadingMode.scroll) return false;
    if (pointerLooksLikeSelection || lastSelectedText.isNotEmpty) {
      return false;
    }
    if (notification is OverscrollNotification &&
        notification.metrics.pixels <= 0 &&
        notification.overscroll < 0) {
      bookmarkPullArmed = true;
    }
    if (notification is ScrollEndNotification && bookmarkPullArmed) {
      performBookmarkPullToggle();
    }
    return false;
  }

  void scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 350), saveState);
  }

  Future<void> saveState() async {
    final callback = widget.onStateChanged;
    if (callback == null) return;
    rememberCurrentChapterPosition();
    final paragraphIndex = readingMode == ReadingMode.page
        ? firstParagraphOfCurrentPage()
        : currentParagraph;
    resumeParagraphIndex = paragraphIndex;
    final state = ReadingState(
      fontSize: fontSize,
      readerFontFamily: readerFontFamily,
      readerFontWeight: readerFontWeight.name,
      lineSpacing: lineSpacing.name,
      backgroundValue: background?.toARGB32(),
      mode: readingMode == ReadingMode.page ? 'page' : 'scroll',
      position: scrollController.hasClients
          ? scrollController.offset
          : widget.initialState.position,
      page: currentPage,
      paragraphIndex: paragraphIndex,
      bookmarks: List<int>.unmodifiable(bookmarks),
      pageTurn: pageTurnStyle.name,
      bookId: bookId,
      brightness: brightness,
      eyeCare: eyeCare.name,
      keepScreenOn: keepScreenOn,
      volumeKeys: volumeKeys,
      chapterPositions: Map.unmodifiable(chapterPositions),
    );
    saveQueue = saveQueue.then((_) => callback(state));
    await saveQueue;
  }

  /// Reading-surface insets, matched to the reference reader's page metrics
  /// (左右 24dp，底部预留给状态胶囊): controls are a floating overlay and must
  /// not change these, so opening the menu never reflows or re-paginates.
  static const double readerSideInset = 24;
  static const double readerTopInset = 24;

  /// Fanqie page foot is tight so body text fills the column.
  static const double readerBottomInset = 18;

  /// Viewport height for pagination. Shares the same fixed bottom reservation
  /// as list/page padding so layout stays identical with controls open or not.

  void refresh(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) => txtReady
      ? renderReaderPage(this, context)
      : const CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()),
        );
}
