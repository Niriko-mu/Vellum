import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../services/notes_library.dart';
import '../services/reading_stats.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import 'reader_controls.dart';
import 'reader_font_picker.dart';
import 'reader_gestures.dart';
import 'reader_markup.dart';
import 'reader_models.dart';
import 'reader_pagination.dart';
import 'reader_paragraph.dart';
import 'reader_platform.dart';
import 'reader_selection.dart';
import '../pages/tts_settings_page.dart';
import '../services/tts_client.dart' show TtsException;
import '../services/tts_preferences.dart';
import 'tts_audio_handler.dart';
import 'tts_bar.dart';
import 'package:flutter/rendering.dart';
import '../services/listening_library.dart';
import '../services/reader_background.dart';
import '../services/tts_text.dart' show sentenceAt;
import 'reader_toc.dart';

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
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late double _fontSize;
  late String _readerFontFamily;
  late ReaderFontWeight _readerFontWeight;
  late ReaderLineSpacing _lineSpacing;
  Color? _background;
  late ReadingMode _readingMode;
  late PageTurnStyle _pageTurnStyle;
  late final AnimationController _coverAnim;
  int? _coverFromPage;
  int? _coverToPage;
  bool _coverJumping = false;
  int _pendingPageDelta = 0;
  bool _slideBusy = false;
  // Finger-driven page turn: overlay tracks the drag, then finishes or
  // springs back on release. This is what makes swipes 跟手.
  bool _dragTurn = false;
  bool _dragCommitted = false;
  int? _dragFromPage;
  int? _dragToPage;
  double _dragProgress = 0;
  double _dragLastTravel = 0;
  int _dragLastMicros = 0;
  double _dragVelocity = 0;
  final _notesLibrary = const NotesLibrary();
  String _lastSelectedText = '';
  bool _showControls = false;
  // Listening (听书): playback lives in the app-wide handler; the page
  // only mirrors its state.
  bool _listening = false;
  double _ttsSpeed = 1.0;
  String _ttsLabel = '';
  String _spokenSentence = '';
  String? _paperImage;
  String? _paperImagePath;
  double _paperImageOpacity = 1.0;
  BackgroundTone _paperTone = BackgroundTone.light;
  Color? _paperInk;
  ImageProvider? _paperImageProvider;
  Timer? _tapTimer;
  Offset? _pendingTapPos;
  ReaderTapAction? _pendingTapAction;
  StreamSubscription? _ttsStateSub;

  late final ScrollController _scrollController;
  late final PageController _pageController;
  int _currentPage = 0;
  int _requestedPage = 0;
  int _currentParagraph = 0;
  late Map<int, ChapterReadingPosition> _chapterPositions;
  late List<int> _bookmarks;
  bool _bookmarkPullArmed = false;
  double _pullDownDistance = 0;
  String? _bookmarkNotice;
  Timer? _bookmarkNoticeTimer;
  int _batteryLevel = -1;
  Timer? _saveTimer;
  Future<void> _saveQueue = Future<void>.value();
  DateTime? _readerPointerDownAt;
  Offset? _readerPointerDownPosition;
  bool _pointerLooksLikeSelection = false;
  bool _bookmarkPullInProgress = false;
  int _pageBeforePointerDown = 0;
  Timer? _selectionHoldTimer;
  final Map<int, GlobalKey> _paragraphKeys = {};
  bool _scrollPositionRestored = false;
  bool _pagePositionRestored = false;
  int _scrollRestoreAttempts = 0;
  late double _brightness;
  late ReaderEyeCare _eyeCare;
  late bool _keepScreenOn;
  late bool _volumeKeys;
  final _platform = const ReaderPlatform();

  /// Highlights and notes for this book, newest first, plus a paragraph-keyed
  /// view so rendering never scans the whole list.
  List<ReadingNote> _notes = const [];
  Map<int, List<String>> _highlights = const {};

  /// Chapter entries are scanned once: the footer needs them on every frame.
  late final List<MapEntry<int, String>> _chapters = chapterEntries(
    widget.book,
  );

  /// Table-of-contents paragraph indexes, for heading detection in O(1).
  late final Set<int> _tocParagraphs = {
    for (final entry in widget.book.tocEntries) entry.paragraphIndex,
  };

  final _statsService = const ReadingStatsService();
  final _sessionSeconds = ValueNotifier<int>(0);
  final _todaySeconds = ValueNotifier<int>(0);
  Stopwatch? _readStopwatch;
  Timer? _readTimer;
  int _unflushedReadSeconds = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fontSize = widget.initialState.fontSize;
    _readerFontFamily = widget.initialState.readerFontFamily;
    _readerFontWeight = ReaderFontWeight.fromStorage(
      widget.initialState.readerFontWeight,
    );
    _lineSpacing = ReaderLineSpacing.fromStorage(
      widget.initialState.lineSpacing,
    );
    _bookmarks = widget.initialState.bookmarks.toSet().toList()..sort();
    _chapterPositions = {...widget.initialState.chapterPositions};
    _background = VellumTheme.normalizeReaderBackground(
      widget.initialState.backgroundValue == null
          ? null
          : Color(widget.initialState.backgroundValue!),
    );
    _readingMode = widget.initialState.mode == 'page'
        ? ReadingMode.page
        : ReadingMode.scroll;
    _pageTurnStyle = PageTurnStyle.fromStorage(widget.initialState.pageTurn);
    _brightness = widget.initialState.brightness;
    _eyeCare = ReaderEyeCare.fromStorage(widget.initialState.eyeCare);
    _keepScreenOn = widget.initialState.keepScreenOn;
    _volumeKeys = widget.initialState.volumeKeys;
    _pager = ProgressiveBookPager(
      widget.book,
      const PageLayoutConfig(
        fontSize: 19,
        lineSpacing: ReaderLineSpacing.standard,
        fontFamily: 'Georgia',
        fontWeight: ReaderFontWeight.regular,
        availableHeight: 600,
        contentWidth: 360,
        screenHeight: 800,
        title: '',
      ),
    );
    _coverAnim = AnimationController(
      vsync: this,
      // Fanqie's page-turn animation is short enough to feel immediate; a
      // 240ms ease-in-out reads as "waiting for the app" instead of turning.
      duration: const Duration(milliseconds: 200),
    );
    _scrollController = ScrollController()
      ..addListener(() {
        _scheduleSave();
        if (_readingMode != ReadingMode.scroll || !mounted) return;
        final estimated =
            (_scrollController.offset /
                    (_fontSize * (_lineSpacing.height + 1.3)))
                .floor();
        final clamped = estimated.clamp(
          0,
          widget.book.paragraphs.isEmpty
              ? 0
              : widget.book.paragraphs.length - 1,
        );
        if (clamped != _currentParagraph) {
          setState(() => _currentParagraph = clamped);
        }
      });
    _pageController = PageController()..addListener(_scheduleSave);
    _loadBatteryLevel();
    _startReadingTimer();
    _loadTodayReading();
    _loadNotes();
    _loadPaper();
    _syncPlatformSettings();
  }

  /// Screen brightness / keep-awake / volume-key paging are window-level
  /// settings on Android, so they follow the reader's lifetime.
  Future<void> _syncPlatformSettings() async {
    await _platform.setBrightness(_brightness);
    await _platform.setKeepScreenOn(_keepScreenOn);
    await _syncVolumeKeys();
  }

  Future<void> _syncVolumeKeys() async {
    await _platform.setVolumeKeyPaging(_volumeKeys);
    _platform.listenForVolumeKeys(_volumeKeys ? _handleVolumeKey : null);
  }

  DateTime? _lastVolumeTurn;

  void _handleVolumeKey(int direction) {
    if (!mounted || !_volumeKeys) return;
    // Fanqie throttles volume-key paging to 300 ms so a held key does not
    // flip dozens of pages.
    final now = DateTime.now();
    final last = _lastVolumeTurn;
    if (last != null &&
        now.difference(last) < ReaderGestures.volumeKeyThrottle) {
      return;
    }
    _lastVolumeTurn = now;
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
    if (_readingMode == ReadingMode.page) {
      _changePage(context, direction);
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasPixels || !position.haveDimensions) return;
    final delta = position.viewportDimension * .9 * direction;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(0.0, position.maxScrollExtent),
    );
    _scheduleSave();
  }

  Future<void> _loadNotes() async {
    final notes = await _notesLibrary.loadForBook(_bookId);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _highlights = _groupHighlights(notes);
    });
  }

  int _noteCountFor(int paragraphIndex) {
    var n = 0;
    for (final note in _notes) {
      if (note.paragraphIndex == paragraphIndex) n++;
    }
    return n;
  }

  void _openNotesForParagraph(int paragraphIndex) {
    final notes = [
      for (final note in _notes)
        if (note.paragraphIndex == paragraphIndex) note,
    ];
    if (notes.isEmpty) return;
    showParagraphNotesSheet(
      context,
      bookId: _bookId,
      bookTitle: widget.book.title,
      paragraphIndex: paragraphIndex,
      notes: notes,
      notesLibrary: _notesLibrary,
      onChanged: _loadNotes,
    );
  }

  Map<int, List<String>> _groupHighlights(List<ReadingNote> notes) {
    final map = <int, List<String>>{};
    for (final note in notes) {
      if (note.selectedText.isEmpty) continue;
      (map[note.paragraphIndex] ??= []).add(note.selectedText);
    }
    return map;
  }

  /// Toggles a highlight for the selected passage — selecting it again removes
  /// it, which is how the reader-style apps behave.
  Future<void> _toggleHighlight(String selected, int paragraphIndex) async {
    final value = selected.trim();
    if (value.isEmpty) return;
    final existing = [
      for (final note in _notes)
        if (note.paragraphIndex == paragraphIndex && note.selectedText == value)
          note,
    ];
    if (existing.isNotEmpty) {
      await _notesLibrary.delete(existing.first.id);
      if (mounted) _showBookmarkNotice('已取消划线');
    } else {
      await _notesLibrary.add(
        bookId: _bookId,
        bookTitle: widget.book.title,
        paragraphIndex: paragraphIndex,
        selectedText: value,
        style: ReadingNoteStyle.highlight,
      );
      if (mounted) _showBookmarkNotice('已划线，可在目录的「笔记」里查看');
    }
    await _loadNotes();
  }

  Future<void> _removeNote(String id) async {
    await _notesLibrary.delete(id);
    if (!mounted) return;
    setState(() {
      _notes = [
        for (final note in _notes)
          if (note.id != id) note,
      ];
      _highlights = _groupHighlights(_notes);
    });
  }

  String get _bookId => widget.book.storageId;

  Future<void> _loadTodayReading() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final stats = await _statsService.load().timeout(
        const Duration(seconds: 2),
      );
      if (mounted) _todaySeconds.value = stats.todaySeconds;
    } catch (_) {}
  }

  void _startReadingTimer() {
    // Flutter tests set FLUTTER_TEST; a periodic timer would keep
    // pumpAndSettle busy forever.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _readStopwatch ??= Stopwatch()..start();
    if (!_readStopwatch!.isRunning) _readStopwatch!.start();
    _readTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final watch = _readStopwatch;
      if (watch == null || !watch.isRunning) return;
      final elapsed = watch.elapsed.inSeconds;
      if (elapsed > _sessionSeconds.value) {
        _unflushedReadSeconds += elapsed - _sessionSeconds.value;
        _sessionSeconds.value = elapsed;
      }
      // Persist often enough that killing the app still keeps most time.
      if (_unflushedReadSeconds >= 10) {
        _flushReadingTime();
      }
    });
  }

  void _pauseReadingTimer() {
    _readStopwatch?.stop();
    _flushReadingTime();
  }

  void _flushReadingTime() {
    final seconds = _unflushedReadSeconds;
    if (seconds <= 0) return;
    _unflushedReadSeconds = 0;
    _statsService.addSeconds(bookId: _bookId, seconds: seconds).then((stats) {
      if (mounted) _todaySeconds.value = stats.todaySeconds;
    });
  }

  void _restoreScrollPositionWhenReady() {
    if (_scrollPositionRestored || _readingMode != ReadingMode.scroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scrollPositionRestored) return;
      if (!_scrollController.hasClients) {
        _scrollRestoreAttempts++;
        if (_scrollRestoreAttempts < 8) _restoreScrollPositionWhenReady();
        return;
      }
      final maxExtent = _scrollController.position.maxScrollExtent;
      final requestedOffset = widget.initialState.position;
      if (requestedOffset > 0 && maxExtent <= 0) {
        _scrollRestoreAttempts++;
        if (_scrollRestoreAttempts < 8) _restoreScrollPositionWhenReady();
        return;
      }
      if (requestedOffset > 0) {
        _scrollController.jumpTo(requestedOffset.clamp(0.0, maxExtent));
        _currentParagraph =
            (requestedOffset / (_fontSize * (_lineSpacing.height + 1.3)))
                .floor()
                .clamp(
                  0,
                  widget.book.paragraphs.isEmpty
                      ? 0
                      : widget.book.paragraphs.length - 1,
                );
      } else {
        final paragraph = widget.initialState.paragraphIndex.clamp(
          0,
          widget.book.paragraphs.isEmpty
              ? 0
              : widget.book.paragraphs.length - 1,
        );
        final estimated =
            paragraph * (_fontSize * (_lineSpacing.height + 22 / _fontSize));
        _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
        _currentParagraph = paragraph;
      }
      _scrollPositionRestored = true;
    });
  }

  Future<void> _loadBatteryLevel() async {
    try {
      final level = await const MethodChannel(
        'vellum/device',
      ).invokeMethod<int>('batteryLevel');
      if (mounted && level != null) setState(() => _batteryLevel = level);
    } on PlatformException {
      // Battery information is optional on non-Android targets.
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      _startReadingTimer();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pauseReadingTimer();
      _saveTimer?.cancel();
      await _saveState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tapTimer?.cancel();
    _ttsStateSub?.cancel();
    _detachTtsCallbacks();
    _selectionHoldTimer?.cancel();
    _readTimer?.cancel();
    _readStopwatch?.stop();
    _flushReadingTime();
    _saveTimer?.cancel();
    _bookmarkNoticeTimer?.cancel();
    _saveState();
    // Release the window-level reader settings.
    _platform.listenForVolumeKeys(null);
    _platform.setBrightness(-1);
    _platform.setKeepScreenOn(false);
    _platform.setVolumeKeyPaging(false);
    _coverAnim.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _setReadingMode(ReadingMode mode) async {
    if (_readingMode == mode) return;
    setState(() {
      _readingMode = mode;
      _scrollPositionRestored = mode == ReadingMode.scroll ? false : true;
      _scrollRestoreAttempts = 0;
    });
    _saveTimer?.cancel();
    await _saveState();
  }

  void _showBookmarkNotice(String message) {
    _bookmarkNoticeTimer?.cancel();
    setState(() => _bookmarkNotice = message);
    _bookmarkNoticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _bookmarkNotice = null);
    });
  }

  Future<void> _addBookmarkAtCurrentPosition() async {
    if (widget.book.paragraphs.isEmpty) return;
    final paragraph = _activeParagraph.clamp(
      0,
      widget.book.paragraphs.length - 1,
    );
    if (_bookmarks.contains(paragraph)) {
      _showBookmarkNotice('此处已有书签');
      return;
    }
    setState(() {
      _bookmarks = [..._bookmarks, paragraph]..sort();
    });
    await _saveState();
    if (mounted) _showBookmarkNotice('书签已添加');
  }

  Future<void> _toggleBookmarkAtCurrentPosition() async {
    if (widget.book.paragraphs.isEmpty) return;
    final paragraph = _activeParagraph.clamp(
      0,
      widget.book.paragraphs.length - 1,
    );
    if (_bookmarks.contains(paragraph)) {
      await _removeBookmark(paragraph);
      if (mounted) _showBookmarkNotice('书签已取消');
    } else {
      await _addBookmarkAtCurrentPosition();
    }
  }

  /// Reading paper: presets keep their theme-tuned look; custom colours and
  /// local images switch body ink by the three-tone slot (reference
  /// ReaderBgColorType). Paper / eye-care / brightness stay orthogonal.
  ReaderBackground get _paper => ReaderBackground(
    kind: _paperImage == null ? BackgroundKind.solid : BackgroundKind.image,
    colorValue: _background?.toARGB32(),
    imageFileName: _paperImage,
    imageOpacity: _paperImageOpacity,
    tone: _paperTone,
    inkColorValue: _paperInk?.toARGB32(),
  );

  Color get _readerInk => Color(_paper.inkValue);

  /// Paper stack: underlay colour + optional image at [imageOpacity].
  /// The [ImageProvider] is cached so page-turn rebuilds never re-decode
  /// (that was the background flash). Used by the live page and the cover
  /// turn overlay so both paint the same surface.
  Widget _paperSurface(BuildContext context) {
    final provider = _paperImageProvider;
    final underlay = _backgroundFor(context);
    if (provider == null) return ColoredBox(color: underlay);
    final opacity = _paperImageOpacity.clamp(0.0, 1.0);
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

  Widget _paperLayer(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(child: _paperSurface(context)),
    );
  }

  void _setPaperImageProvider(String? path) {
    if (path == null) {
      _paperImageProvider = null;
      _paperImagePath = null;
      return;
    }
    if (path == _paperImagePath && _paperImageProvider != null) return;
    _paperImagePath = path;
    _paperImageProvider = FileImage(File(path));
  }

  Future<void> _loadPaper() async {
    final store = const ReaderBackgroundStore();
    final stored = await store.load(bookId: _bookId);
    if (!mounted) return;
    if (stored != null) {
      final path = stored.usesImage
          ? await store.imagePathFor(stored.imageFileName!)
          : null;
      if (!mounted) return;
      setState(() {
        _background = stored.colorValue == null
            ? null
            : Color(stored.colorValue!);
        _paperImage = stored.imageFileName;
        _paperImageOpacity = stored.imageOpacity;
        _paperTone = stored.tone;
        _paperInk = stored.inkColorValue == null
            ? null
            : Color(stored.inkColorValue!);
        _setPaperImageProvider(path);
      });
      return;
    }
    // Migrate the legacy solid-colour field once.
    final color = _background;
    if (color == null) return;
    final argb = color.toARGB32();
    final darkPreset =
        argb == VellumTheme.readerNight.toARGB32() ||
        argb == VellumTheme.readerCharcoal.toARGB32() ||
        argb == VellumTheme.readerSoftBlack.toARGB32();
    final tone = darkPreset
        ? BackgroundTone.dark
        : ReaderBackground.suggestTone(argb);
    setState(() => _paperTone = tone);
    await store.save(
      ReaderBackground(kind: BackgroundKind.solid, colorValue: argb, tone: tone),
      bookId: _bookId,
    );
  }

  Future<void> _applyPaper(ReaderBackground value) async {
    final store = const ReaderBackgroundStore();
    final path = value.usesImage
        ? await store.imagePathFor(value.imageFileName!)
        : null;
    if (!mounted) return;
    setState(() {
      _background = value.colorValue == null
          ? null
          : Color(value.colorValue!);
      _paperImage = value.imageFileName;
      _paperImageOpacity = value.imageOpacity;
      _paperTone = value.tone;
      _paperInk = value.inkColorValue == null
          ? null
          : Color(value.inkColorValue!);
      _setPaperImageProvider(path);
    });
    await store.save(value, bookId: _bookId);
    _scheduleSave();
  }

  /// Paragraph the listen feature should start from: the one in the middle
  /// of the screen in scroll mode, the first one on the page in page mode.
  int _listenStartParagraph() {
    if (_readingMode == ReadingMode.page) return _firstParagraphOfCurrentPage();
    if (!_scrollController.hasClients) return _currentParagraph;
    final size = MediaQuery.sizeOf(context);
    final centerY = size.height / 2;
    var best = _currentParagraph;
    var bestDistance = double.infinity;
    for (final entry in _paragraphKeys.entries) {
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

  Future<void> _startListening() async {
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
      await Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => const TtsSettingsPage()),
      );
      return;
    }

    // Continue where the last session stopped (local key_is_tts memory).
    final remembered = await const ListeningLibrary().load(_bookId);
    if (!mounted) return;
    var startParagraph = _listenStartParagraph();
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
        _currentParagraph = paragraphIndex;
        _spokenSentence = text;
      });
      _jumpToParagraph(paragraphIndex);
      const ListeningLibrary().save(
        _bookId,
        ListeningPosition(
          paragraphIndex: paragraphIndex,
          sentenceIndex: sentenceIndex,
        ),
      );
    };
    handler.onError = _onTtsError;
    _ttsStateSub?.cancel();
    _ttsStateSub = handler.playbackState.listen((state) {
      if (!mounted) return;
      setState(() {
        _listening = state.playing || handler.hasBook;
        _ttsLabel = handler.positionLabel;
        _ttsSpeed = handler.preferences?.speed ?? _ttsSpeed;
      });
    });

    await handler.startBook(
      bookId: _bookId,
      bookTitle: widget.book.title,
      paragraphs: widget.book.paragraphs,
      startParagraph: startParagraph,
      startSentence: startSentence,
    );
    if (!mounted) return;
    setState(() {
      _listening = true;
      _showControls = false;
    });
  }

  void _onTtsError(TtsException error) {
    if (!mounted) return;
    _showBookmarkNotice(error.userMessage);
    setState(() => _listening = false);
  }

  Future<void> _stopListening() async {
    final handler = ttsHandler;
    if (handler == null) return;
    _ttsStateSub?.cancel();
    _ttsStateSub = null;
    _detachTtsCallbacks();
    await handler.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _spokenSentence = '';
    });
  }

  void _detachTtsCallbacks() {
    final handler = ttsHandler;
    if (handler == null) return;
    if (handler.onSentenceChanged != null) handler.onSentenceChanged = null;
    if (handler.onError != null) handler.onError = null;
  }

  static const _ttsSpeedSteps = [0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> _cycleTtsSpeed() async {
    final handler = ttsHandler;
    if (handler == null) return;
    final current = handler.preferences?.speed ?? 1.0;
    final next = _ttsSpeedSteps.firstWhere(
      (speed) => speed > current + 0.01,
      orElse: () => _ttsSpeedSteps.first,
    );
    setState(() => _ttsSpeed = next);
    await handler.setSpeed(next);
  }

  Future<void> _removeBookmark(int paragraph) async {
    if (!_bookmarks.contains(paragraph)) return;
    setState(() => _bookmarks.remove(paragraph));
    await _saveState();
  }

  bool _handleBookmarkPull(ScrollNotification notification) {
    if (_readingMode != ReadingMode.scroll) return false;
    if (_pointerLooksLikeSelection || _lastSelectedText.isNotEmpty) {
      return false;
    }
    if (notification is OverscrollNotification &&
        notification.metrics.pixels <= 0 &&
        notification.overscroll < 0) {
      _bookmarkPullArmed = true;
    }
    if (notification is ScrollEndNotification && _bookmarkPullArmed) {
      _bookmarkPullArmed = false;
      _toggleBookmarkAtCurrentPosition();
    }
    return false;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveState);
  }

  Future<void> _saveState() async {
    final callback = widget.onStateChanged;
    if (callback == null) return;
    _rememberCurrentChapterPosition();
    final paragraphIndex = _readingMode == ReadingMode.page
        ? _firstParagraphOfCurrentPage()
        : _currentParagraph;
    final state = ReadingState(
      fontSize: _fontSize,
      readerFontFamily: _readerFontFamily,
      readerFontWeight: _readerFontWeight.name,
      lineSpacing: _lineSpacing.name,
      backgroundValue: _background?.toARGB32(),
      mode: _readingMode == ReadingMode.page ? 'page' : 'scroll',
      position: _scrollController.hasClients
          ? _scrollController.offset
          : widget.initialState.position,
      page: _currentPage,
      paragraphIndex: paragraphIndex,
      bookmarks: List<int>.unmodifiable(_bookmarks),
      pageTurn: _pageTurnStyle.name,
      bookId: _bookId,
      brightness: _brightness,
      eyeCare: _eyeCare.name,
      keepScreenOn: _keepScreenOn,
      volumeKeys: _volumeKeys,
      chapterPositions: Map.unmodifiable(_chapterPositions),
    );
    _saveQueue = _saveQueue.then((_) => callback(state));
    await _saveQueue;
  }

  /// Reading-surface insets, matched to the reference reader's page metrics
  /// (左右 24dp，底部预留给状态胶囊): controls are a floating overlay and must
  /// not change these, so opening the menu never reflows or re-paginates.
  static const double _readerSideInset = 24;
  static const double _readerTopInset = 24;

  /// Fanqie page foot is tight so body text fills the column.
  static const double _readerBottomInset = 18;

  /// Viewport height for pagination. Shares the same fixed bottom reservation
  /// as list/page padding so layout stays identical with controls open or not.
  double _pageAvailableHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final view = MediaQuery.viewPaddingOf(context);
    // Must match PageView/list padding, inside SafeArea.
    // Pagination subtracts an extra measurement slack internally.
    return size.height -
        view.top -
        view.bottom -
        _readerTopInset -
        _readerBottomInset;
  }

  double _pageContentWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.size.width -
        media.padding.left -
        media.padding.right -
        _readerSideInset * 2;
  }

  PageLayoutConfig _pageLayoutConfig(BuildContext context) {
    final media = MediaQuery.of(context);
    return PageLayoutConfig(
      fontSize: _fontSize,
      lineSpacing: _lineSpacing,
      fontFamily: _readerFontFamily,
      fontWeight: _readerFontWeight,
      availableHeight: _pageAvailableHeight(context),
      contentWidth: _pageContentWidth(context),
      screenHeight: media.size.height,
      title: widget.book.title,
    );
  }

  /// How many measured pages to keep ahead of the current reading position.
  static const int _pagesAhead = 100;
  late ProgressiveBookPager _pager;
  bool _paginateBusy = false;
  Size? _lastMeasuredSize;
  double? _lastMeasuredFontSize;
  ReaderLineSpacing? _lastMeasuredLineSpacing;
  String? _lastMeasuredFontFamily;
  ReaderFontWeight? _lastMeasuredFontWeight;
  double? _lastMeasuredPageHeight;
  double? _lastMeasuredPageWidth;
  double? _lastMeasuredBottomInset;

  List<List<PageFragment>> get _pages => _pager.pages;
  int get _pageCount => _pager.pageCount;

  bool _layoutNeedsReset(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pageHeight = _pageAvailableHeight(context);
    final pageWidth = _pageContentWidth(context);
    final bottomInset = _readerBottomInset;
    return _lastMeasuredSize != size ||
        _lastMeasuredFontSize != _fontSize ||
        _lastMeasuredLineSpacing != _lineSpacing ||
        _lastMeasuredFontFamily != _readerFontFamily ||
        _lastMeasuredFontWeight != _readerFontWeight ||
        _lastMeasuredPageHeight != pageHeight ||
        _lastMeasuredPageWidth != pageWidth ||
        _lastMeasuredBottomInset != bottomInset;
  }

  void _recordLayoutMetrics(BuildContext context) {
    _lastMeasuredSize = MediaQuery.sizeOf(context);
    _lastMeasuredFontSize = _fontSize;
    _lastMeasuredLineSpacing = _lineSpacing;
    _lastMeasuredFontFamily = _readerFontFamily;
    _lastMeasuredFontWeight = _readerFontWeight;
    _lastMeasuredPageHeight = _pageAvailableHeight(context);
    _lastMeasuredPageWidth = _pageContentWidth(context);
    _lastMeasuredBottomInset = _readerBottomInset;
  }

  /// Progressive pagination: measure ahead of the current position in
  /// small slices so first paint stays fast; extend as the reader advances.
  void _ensurePages(BuildContext context) {
    if (_layoutNeedsReset(context)) {
      _pager = ProgressiveBookPager(widget.book, _pageLayoutConfig(context));
      _recordLayoutMetrics(context);
      final resumePara = widget.initialState.paragraphIndex.clamp(
        0,
        widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
      );
      _pager.paginateThrough(resumePara);
      final resumePage = _pager.exactPageForParagraph(resumePara) ?? 0;
      _pager.paginateUntilPages(resumePage + _pagesAhead);
    } else {
      final target = _currentPage + _pagesAhead;
      if (!_pager.fullyPaginated && _pager.pageCount < target) {
        _paginateAsync(targetPages: target);
      }
    }
  }

  void _paginateAsync({required int targetPages}) {
    if (_paginateBusy) return;
    _paginateBusy = true;
    Future<void>(() async {
      while (mounted && _paginateBusy) {
        if (_pager.fullyPaginated || _pager.pageCount >= targetPages) break;
        final sw = Stopwatch()..start();
        while (mounted &&
            !_pager.fullyPaginated &&
            _pager.pageCount < targetPages &&
            sw.elapsedMilliseconds < 12) {
          _pager.paginateSlice(maxParagraphs: 20);
        }
        if (!mounted) break;
        setState(() {});
        if (_pager.fullyPaginated || _pager.pageCount >= targetPages) break;
        await Future<void>.delayed(Duration.zero);
      }
      _paginateBusy = false;
    });
  }

  void _maybeExtendPagination() {
    if (_readingMode != ReadingMode.page || _pager.fullyPaginated) return;
    final remaining = _pager.pageCount - _currentPage;
    if (remaining < 24) {
      _paginateAsync(targetPages: _currentPage + _pagesAhead);
    }
  }

  int _firstParagraphOfCurrentPage() {
    if (_pages.isEmpty ||
        _pages[_currentPage.clamp(0, _pages.length - 1)].isEmpty) {
      return 0;
    }
    return _pages[_currentPage.clamp(0, _pages.length - 1)]
        .first
        .paragraphIndex;
  }

  int _pageForParagraph(int paragraphIndex) {
    if (paragraphIndex > _pager.nextParagraph) {
      _pager.paginateThrough(paragraphIndex);
    }
    final exact = _pager.exactPageForParagraph(paragraphIndex);
    if (exact != null) {
      return exact.clamp(0, (_pager.pageCount - 1).clamp(0, exact));
    }
    final ref = _pager.pageRefForParagraph(paragraphIndex);
    return (ref.page1 - 1).clamp(0, _pager.pageCount - 1);
  }

  void _restorePageWhenReady() {
    if (_pagePositionRestored || _readingMode != ReadingMode.page) return;
    final requested = widget.initialState.paragraphIndex;
    final starts = _pages;
    if (starts.isEmpty) return;
    final target = _pageForParagraph(requested).clamp(0, starts.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pagePositionRestored) return;
      if (!_pageController.hasClients) {
        return;
      }
      // Consume the one-shot restore. Never re-apply after the user navigates
      // (TOC, progress, or tap paging).
      _pagePositionRestored = true;
      if (target == 0) return;
      if (_currentPage != 0 || _requestedPage != 0) return;
      final live = _pageController.page;
      if (live == null || live != 0) return;
      _jumpToPageExact(target);
      setState(() {
        _currentPage = target;
        _requestedPage = target;
      });
    });
  }

  /// Jump to [page]. [SnapPageScrollPhysics] suppresses any residual spring
  /// that [PageController.jumpToPage] would otherwise start via `goBallistic`.
  void _jumpToPageExact(int page) {
    if (!_pageController.hasClients) return;
    _pageController.jumpToPage(page);
  }

  int get _activeParagraph => _readingMode == ReadingMode.page
      ? _firstParagraphOfCurrentPage()
      : _currentParagraph;
  bool get _isCurrentViewBookmarked {
    if (_bookmarks.isEmpty) return false;
    if (_readingMode == ReadingMode.scroll) {
      return _bookmarks.contains(_activeParagraph);
    }
    if (_pages.isEmpty) return false;
    final page = _currentPage.clamp(0, _pages.length - 1);
    return _pages[page].any(
      (fragment) => _bookmarks.contains(fragment.paragraphIndex),
    );
  }

  Map<int, String> _chapterPageLabels() {
    final labels = <int, String>{};
    for (final entry in _chapters) {
      final ref = _pager.pageRefForParagraph(entry.key);
      labels[entry.key] = ref.exact ? '第 ${ref.page1} 页' : '约第 ${ref.page1} 页';
    }
    return labels;
  }

  List<MapEntry<int, String>> _chapterEntries() => _chapters;

  /// Index of the chapter containing [paragraph], or -1 when before the first.
  int _chapterIndexFor(int paragraph) {
    var low = 0;
    var high = _chapters.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_chapters[mid].key <= paragraph) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  int _chapterStartForParagraph(int paragraph) {
    final index = _chapterIndexFor(paragraph);
    return index < 0 ? 0 : _chapters[index].key;
  }

  void _rememberCurrentChapterPosition() {
    final restored = _readingMode == ReadingMode.page
        ? _pagePositionRestored
        : _scrollPositionRestored;
    if (!restored || _chapters.isEmpty) return;
    final paragraph = _activeParagraph.clamp(
      0,
      widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
    );
    final start = _chapterStartForParagraph(paragraph);
    _chapterPositions[start] = ChapterReadingPosition(
      position: _scrollController.hasClients ? _scrollController.offset : 0,
      page: _currentPage,
      paragraphIndex: paragraph,
    );
  }

  /// Chapter title only — top-left / menu bar (Fanqie running head).
  String get _chapterLabel {
    if (_chapters.isEmpty) return '';
    final index = _chapterIndexFor(_activeParagraph);
    if (index < 0) return '开篇';
    return _chapters[index].value;
  }

  /// Fanqie bottom indicator: page number only (no percent / paragraph).
  String get _pageProgress {
    if (_readingMode == ReadingMode.page) {
      final total = _pager.estimatedTotalPageCount;
      final current = (_currentPage + 1).clamp(1, total);
      return _pager.fullyPaginated ? '$current / $total' : '$current / ~$total';
    }
    final percent = (_progress * 100).clamp(0, 100).round();
    return '$percent%';
  }

  String get _batteryText => _batteryLevel < 0 ? '' : '$_batteryLevel%';
  double get _progress {
    if (_readingMode == ReadingMode.page) {
      final total = _pager.estimatedTotalPageCount;
      if (total <= 1) return 0;
      return (_currentPage / (total - 1)).clamp(0.0, 1.0);
    }
    if (!_scrollController.hasClients) return 0;
    final position = _scrollController.position;
    // Dimensions may not be applied yet on the first frames.
    if (!position.hasPixels || !position.haveDimensions) return 0;
    final max = position.maxScrollExtent;
    if (max <= 0) return 0;
    final raw = _scrollController.offset / max;
    if (raw <= 0.002) return 0.0;
    if (raw >= 0.998) return 1.0;
    return raw.clamp(0.0, 1.0);
  }

  bool get _canSeekProgress {
    if (_readingMode == ReadingMode.page) {
      return _pager.estimatedTotalPageCount > 1 ||
          widget.book.paragraphs.length > 1;
    }
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return position.hasPixels &&
        position.haveDimensions &&
        position.maxScrollExtent > 0;
  }

  void _jumpToProgress(double value) {
    final target = value.clamp(0.0, 1.0);
    if (_readingMode == ReadingMode.page) {
      final totalParas = widget.book.paragraphs.length;
      if (totalParas <= 0) return;
      final para = (target * (totalParas - 1)).round().clamp(0, totalParas - 1);
      // Measure through the destination so TOC/page numbers stay consistent.
      _pager.paginateThrough(para);
      final page = _pageForParagraph(para);
      _paginateAsync(targetPages: page + _pagesAhead);
      setState(() {
        _currentPage = page;
        _requestedPage = page;
      });
      if (_pageController.hasClients) {
        _jumpToPageExact(page);
      }
      _scheduleSave();
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    _scrollController.jumpTo(target * position.maxScrollExtent);
    _scheduleSave();
  }

  /// Fanqie progress semantics: SeekBar drives chapter index, not 0–100%.
  void _jumpToChapter(int chapterIndex) {
    final entries = _chapters;
    if (entries.isEmpty) return;
    final index = chapterIndex.clamp(0, entries.length - 1);
    _jumpToParagraph(entries[index].key, restoreChapter: true);
  }

  void _jumpToScrollParagraph(int target, {double? preferredOffset}) {
    final count = widget.book.paragraphs.length;
    if (count == 0 || !_scrollController.hasClients) return;
    final index = target.clamp(0, count - 1);
    final fraction = count <= 1 ? 0.0 : index / (count - 1);
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (preferredOffset ?? (fraction * position.maxScrollExtent)).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    setState(() => _currentParagraph = index);
    _scheduleSave();
    _refineScrollJump(index);
  }

  void _refineScrollJump(int target, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      var ctx = _paragraphKeys[target]?.currentContext;
      if (ctx == null) {
        // Target not built yet: step toward the nearest mounted paragraph so
        // the lazy list materializes the destination.
        int? nearest;
        var nearestDistance = 1 << 30;
        for (final entry in _paragraphKeys.entries) {
          final child = entry.value.currentContext;
          if (child == null) continue;
          final distance = (entry.key - target).abs();
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearest = entry.key;
          }
        }
        if (nearest != null && nearestDistance > 0) {
          ctx = _paragraphKeys[nearest]!.currentContext;
        }
      }
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.08,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      // Retry exact target after the list has had another frame to build it.
      final exact = _paragraphKeys[target]?.currentContext;
      if (exact != null && exact.mounted && ctx != exact) {
        await Scrollable.ensureVisible(
          exact,
          alignment: 0.08,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
        );
      }
      if (mounted) {
        setState(() => _currentParagraph = target);
        _scheduleSave();
      }
      if (exact == null && attempt < 8) {
        _refineScrollJump(target, attempt: attempt + 1);
      }
    });
  }

  void _jumpToParagraph(int paragraphIndex, {bool restoreChapter = false}) {
    final maxIndex = widget.book.paragraphs.isEmpty
        ? 0
        : widget.book.paragraphs.length - 1;
    _rememberCurrentChapterPosition();
    var target = paragraphIndex.clamp(0, maxIndex);
    ChapterReadingPosition? checkpoint;
    if (restoreChapter) {
      checkpoint = _chapterPositions[paragraphIndex];
      if (checkpoint != null) {
        target = checkpoint.paragraphIndex.clamp(0, maxIndex);
      }
    }
    if (_readingMode == ReadingMode.page) {
      final page = _pageForParagraph(target).clamp(0, _pageCount - 1);
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
        setState(() {
          _currentPage = page;
          _requestedPage = page;
        });
      }
      return;
    }
    _jumpToScrollParagraph(target, preferredOffset: checkpoint?.position);
  }

  Widget _bookmarkPullIndicator(BuildContext context) {
    final threshold = ReaderGestures.bookmarkPullThreshold;
    final progress = (_pullDownDistance / threshold).clamp(0.0, 1.2);
    final armed = _pullDownDistance >= threshold;
    final already = _isCurrentViewBookmarked;
    final label = already
        ? (armed ? '松开取消书签' : '下拉取消书签')
        : (armed ? '松开添加书签' : '下拉添加书签');
    return BookmarkRibbon(
      surface: _backgroundFor(context),
      progress: progress,
      armed: armed,
      alreadyBookmarked: already,
      label: label,
    );
  }

  Color _backgroundFor(BuildContext context) =>
      _background ??
      (CupertinoTheme.of(context).brightness == Brightness.dark
          ? VellumTheme.readerNight
          : VellumTheme.readerWhite);
  bool _isScrollIdle() => true;
  void _handleReaderPointerMove(PointerMoveEvent event) {
    final down = _readerPointerDownPosition;
    if (down == null) return;
    // Only treat a clear intentional slide as "dismiss chrome". A 18px
    // threshold made every careful tap near a button feel broken.
    if (_showControls) {
      final dx = event.position.dx - down.dx;
      final dy = event.position.dy - down.dy;
      if (dx * dx + dy * dy > 72 * 72) {
        setState(() => _showControls = false);
      }
    }
    final atTop =
        _readingMode != ReadingMode.scroll ||
        (!_scrollController.hasClients || _scrollController.offset <= 2);
    if (!atTop) {
      if (_pullDownDistance != 0) {
        setState(() => _pullDownDistance = 0);
      }
      return;
    }
    final dy = event.position.dy - down.dy;
    final dx = event.position.dx - down.dx;
    // A deliberate downward bookmark pull owns this gesture. Interrupt the
    // PageView as soon as the vertical intent is clear so a slight diagonal
    // movement cannot turn the page underneath the bookmark interaction.
    if (_readingMode == ReadingMode.page &&
        !_pointerLooksLikeSelection &&
        dy > 18 &&
        dy > dx.abs() * 1.25) {
      _bookmarkPullInProgress = true;
      _restorePageAfterBookmarkPull();
    }
    if (_readingMode == ReadingMode.page &&
        !_pointerLooksLikeSelection &&
        !_bookmarkPullInProgress &&
        !_coverJumping &&
        !_slideBusy) {
      _updateDragTurn(dx);
    }
    final next = dy > 0 ? dy : 0.0;
    if ((next - _pullDownDistance).abs() > 0.5) {
      setState(() => _pullDownDistance = next);
    }
  }

  void _restorePageAfterBookmarkPull() {
    if (_readingMode != ReadingMode.page ||
        !_pageController.hasClients ||
        _pageCount <= 0) {
      return;
    }
    final page = _pageBeforePointerDown.clamp(0, _pageCount - 1);
    _pageController.jumpToPage(page);
    if (_currentPage != page) {
      setState(() {
        _currentPage = page;
        _requestedPage = page;
      });
    }
  }

  /// Begin/update a finger-driven page turn. Progress maps 1:1 to drag
  /// distance so the overlay follows the hand instead of playing a canned
  /// animation only after release.
  void _updateDragTurn(double dx) {
    const intent = 10.0;
    if (!_dragTurn) {
      if (dx.abs() < intent) return;
      final pageCount = _pageCount;
      if (pageCount <= 0) return;
      final from = _currentPage.clamp(0, pageCount - 1);
      final to = dx < 0 ? from + 1 : from - 1;
      if (to < 0 || to >= pageCount) return;
      if (!_pager.fullyPaginated && to >= _pager.pageCount) {
        _pager.paginateUntilPages(to + 1);
      }
      _dragTurn = true;
      _dragFromPage = from;
      _dragToPage = to;
      _dragProgress = 0;
      _dragLastTravel = 0;
      _dragLastMicros = DateTime.now().microsecondsSinceEpoch;
      _dragVelocity = 0;
      _coverFromPage = from;
      _coverToPage = to;
      _requestedPage = to;
      setState(() {});
      return;
    }
    final from = _dragFromPage;
    final to = _dragToPage;
    if (from == null || to == null) return;
    final travel = to > from ? -dx : dx;
    final width = MediaQuery.sizeOf(context).width;
    final p = (travel / (width == 0 ? 1 : width)).clamp(0.0, 1.0);
    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - _dragLastMicros) / 1e6;
    if (dt > 0) {
      _dragVelocity = (travel - _dragLastTravel) / dt;
    }
    _dragLastTravel = travel;
    _dragLastMicros = now;
    if ((p - _dragProgress).abs() < 0.002) return;
    setState(() => _dragProgress = p);
  }

  void _cancelDragTurn() {
    _dragCommitted = false;
    _dragTurn = false;
    _dragFromPage = null;
    _dragToPage = null;
    _dragProgress = 0;
    _dragVelocity = 0;
    _coverFromPage = null;
    _coverToPage = null;
  }

  /// Release a finger-driven turn: finish past ~38% (or a fast flick),
  /// otherwise spring back to the original page.
  void _endDragTurn() {
    if (!_dragTurn) return;
    final from = _dragFromPage;
    final to = _dragToPage;
    final progress = _dragProgress;
    // Positive travel speed commits the turn (direction-normalised).
    final velocityTravel = _dragVelocity;
    _dragTurn = false;
    if (from == null || to == null) {
      _cancelDragTurn();
      return;
    }
    final flick = velocityTravel > 700;
    final commit = progress >= 0.38 || flick;
    if (!commit) {
      _coverFromPage = from;
      _coverToPage = to;
      _requestedPage = from;
      _coverAnim.stop();
      _coverAnim.value = progress.clamp(0.0, 1.0);
      _coverAnim
          .animateTo(0, duration: const Duration(milliseconds: 160))
          .whenComplete(() {
            if (!mounted) return;
            _dragCommitted = false;
            _cancelDragTurn();
            setState(() {
              _currentPage = from;
              _requestedPage = from;
            });
          });
      setState(() {});
      return;
    }
    if (_pageTurnStyle == PageTurnStyle.none) {
      _cancelDragTurn();
      setState(() {
        _currentPage = to;
        _requestedPage = to;
      });
      _jumpToPageExact(to);
      _scheduleSave();
      return;
    }
    // Cover and slide: glide the remainder on the same overlay so the page
    // does not jump at release (跟手). Timed _startSlideTurn is for taps only.
    _dragCommitted = true;
    _coverFromPage = from;
    _coverToPage = to;
    _requestedPage = to;
    _coverAnim.stop();
    _coverAnim.value = progress.clamp(0.0, 1.0);
    _coverAnim.forward().whenComplete(() {
      if (!mounted) return;
      _dragCommitted = false;
      _finishCoverTurn(to);
    });
    setState(() {});
  }

  void _handleReaderPointerUp(BuildContext context, PointerUpEvent event) {
    final pressedAt = _readerPointerDownAt;
    final pressedPosition = _readerPointerDownPosition;
    final selectionGesture =
        _pointerLooksLikeSelection ||
        (_lastSelectedText.isNotEmpty && _pullDownDistance > 0);
    final wasBookmarkPull = _bookmarkPullInProgress;
    if (wasBookmarkPull) _restorePageAfterBookmarkPull();
    _bookmarkPullInProgress = false;
    final wasDragTurn = _dragTurn;
    if (wasDragTurn) {
      _endDragTurn();
    }
    _readerPointerDownAt = null;
    _readerPointerDownPosition = null;
    _pointerLooksLikeSelection = false;
    if (_pullDownDistance != 0) {
      setState(() => _pullDownDistance = 0);
    }
    // Drag-turn already resolved the gesture — do not also fire a tap/swipe.
    if (wasDragTurn) return;
    final size = MediaQuery.sizeOf(context);
    final beginsAtScrollTop =
        _readingMode != ReadingMode.scroll ||
        (!_scrollController.hasClients || _scrollController.offset <= 2);
    final action = ReaderGestures.resolvePointerUp(
      downAt: pressedAt,
      downPosition: pressedPosition,
      upPosition: event.position,
      mode: _readingMode,
      beginsAtScrollTop: beginsAtScrollTop,
      isIdle: _isScrollIdle(),
      screenWidth: size.width,
      screenHeight: size.height,
      selectionGesture: selectionGesture,
    );
    _dispatchTap(action, event.position);
  }

  /// While a listen session is armed, single taps wait out the double-tap
  /// window (200 ms, the reference reader's
  /// `key_audio_reader_double_click_interval_time`) so a second tap can speak
  /// the tapped sentence; otherwise the action runs immediately.
  void _dispatchTap(ReaderTapAction action, Offset upPosition) {
    final listenArmed = ttsHandler?.hasBook ?? false;
    if (!listenArmed || action == ReaderTapAction.none) {
      _runTap(action);
      return;
    }
    final pending = _pendingTapPos;
    if (_tapTimer != null &&
        pending != null &&
        (upPosition - pending).distance < 24) {
      _tapTimer!.cancel();
      _tapTimer = null;
      _pendingTapPos = null;
      _pendingTapAction = null;
      _speakSentenceAt(upPosition);
      return;
    }
    _tapTimer?.cancel();
    _pendingTapPos = upPosition;
    _pendingTapAction = action;
    _tapTimer = Timer(const Duration(milliseconds: 200), () {
      _tapTimer = null;
      final deferred = _pendingTapAction;
      _pendingTapAction = null;
      _pendingTapPos = null;
      if (deferred != null) _runTap(deferred);
    });
  }

  void _runTap(ReaderTapAction action) {
    switch (action) {
      case ReaderTapAction.none:
        break;
      case ReaderTapAction.toggleBookmark:
        _bookmarkPullArmed = false;
        _toggleBookmarkAtCurrentPosition();
      case ReaderTapAction.toggleControls:
        setState(() => _showControls = !_showControls);
      case ReaderTapAction.previousPage:
        _changePage(context, -1);
      case ReaderTapAction.nextPage:
        _changePage(context, 1);
    }
  }

  /// Double-tap listen: find the paragraph under the tap, ask its text layer
  /// for the character offset, and speak the containing sentence.
  void _speakSentenceAt(Offset global) {
    final handler = ttsHandler;
    if (handler == null || !handler.hasBook) return;
    for (final key in _paragraphKeys.values) {
      final paragraphContext = key.currentContext;
      if (paragraphContext == null) continue;
      final root = paragraphContext.findRenderObject();
      if (root is! RenderBox || !root.attached) continue;
      RenderBox? textBox;
      void hunt(RenderObject node) {
        if (textBox != null) return;
        if (node is RenderBox &&
            (node is RenderParagraph || node is RenderEditable)) {
          textBox = node;
          return;
        }
        node.visitChildren(hunt);
      }

      hunt(root);
      final box = textBox;
      if (box == null) continue;
      final origin = box.localToGlobal(Offset.zero);
      final local = global - origin;
      if (local.dy < -4 || local.dy > box.size.height + 4) continue;
      // SelectableText renders through RenderEditable (global hit test);
      // plain Text.rich through RenderParagraph (local).
      final position = box is RenderParagraph
          ? box.getPositionForOffset(local)
          : (box as RenderEditable).getPositionForPoint(global);
      final plain = box is RenderParagraph
          ? box.text.toPlainText()
          : (box as RenderEditable).plainText;
      final span = sentenceAt(plain, position.offset);
      if (span == null) continue;
      final sentence = plain.substring(span.start, span.end).trim();
      if (sentence.isEmpty) continue;
      handler.speakSentence(sentence);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_readingMode == ReadingMode.page) {
      _ensurePages(context);
    } else {
      _restoreScrollPositionWhenReady();
    }
    return CupertinoPageScaffold(
      backgroundColor: _backgroundFor(context),
      navigationBar: null,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // System/edge back: chrome first, then leave the reader.
          if (_showControls) {
            setState(() => _showControls = false);
            return;
          }
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        },
        child: SafeArea(
          child: Stack(
            children: [
              _paperLayer(context),
            Localizations.override(
                context: context,
                delegates: const [DefaultMaterialLocalizations.delegate],
                child: SelectionArea(
                  onSelectionChanged: (content) {
                    _lastSelectedText = content?.plainText.trim() ?? '';
                  },
                  contextMenuBuilder: (context, selectableRegionState) {
                    final selected = _lastSelectedText.trim();
                    final buttonItems = <ContextMenuButtonItem>[
                      // Keep the platform copy action (SelectionArea handles it).
                      ...selectableRegionState.contextMenuButtonItems,
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'Bing 查询',
                          onPressed: () {
                            selectableRegionState.hideToolbar();
                            openSelectionService(selected, translate: false);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'DeepL 翻译',
                          onPressed: () {
                            selectableRegionState.hideToolbar();
                            openSelectionService(selected, translate: true);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: '笔记',
                          onPressed: () async {
                            selectableRegionState.hideToolbar();
                            await showAddNoteSheet(
                              context,
                              bookId: _bookId,
                              bookTitle: widget.book.title,
                              paragraphIndex: _currentParagraph,
                              selectedText: selected,
                              notesLibrary: _notesLibrary,
                            );
                            await _loadNotes();
                          },
                        ),
                    ];
                    return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                      anchors: selectableRegionState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
                  child: Listener(
                    onPointerDown: (event) {
                      _readerPointerDownAt = DateTime.now();
                      _readerPointerDownPosition = event.position;
                      _bookmarkPullInProgress = false;
                      _pageBeforePointerDown = _currentPage;
                      _pointerLooksLikeSelection = false;
                      _selectionHoldTimer?.cancel();
                      _selectionHoldTimer = Timer(
                        const Duration(milliseconds: 400),
                        () {
                          _pointerLooksLikeSelection = true;
                        },
                      );
                    },
                    onPointerMove: _handleReaderPointerMove,
                    onPointerCancel: (_) {
                      _selectionHoldTimer?.cancel();
                      _readerPointerDownAt = null;
                      _readerPointerDownPosition = null;
                      _pointerLooksLikeSelection = false;
                      if (_bookmarkPullInProgress) {
                        _restorePageAfterBookmarkPull();
                        _bookmarkPullInProgress = false;
                      }
                      if (_dragTurn) {
                        _endDragTurn();
                      }
                      if (_pullDownDistance != 0) {
                        setState(() => _pullDownDistance = 0);
                      }
                    },
                    onPointerUp: (event) {
                      _selectionHoldTimer?.cancel();
                      _handleReaderPointerUp(context, event);
                    },
                    child: _readingMode == ReadingMode.scroll
                        ? NotificationListener<ScrollNotification>(
                            onNotification: _handleBookmarkPull,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.fromLTRB(
                                _readerSideInset,
                                _readerTopInset,
                                _readerSideInset,
                                _readerBottomInset,
                              ),
                              itemCount: widget.book.paragraphs.length + 2,
                              itemBuilder: (context, index) {
                                if (index == 0) return _title(context);
                                if (index == 1) {
                                  return const SizedBox(height: 30);
                                }
                                final paragraphIndex = index - 2;
                                final isHeading =
                                    ReaderMarkup.heading.hasMatch(
                                      widget.book.paragraphs[paragraphIndex],
                                    ) ||
                                    _tocParagraphs.contains(paragraphIndex);
                                return KeyedSubtree(
                                  key: _paragraphKeys.putIfAbsent(
                                    paragraphIndex,
                                    () => GlobalKey(),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      bottom: 22,
                                      top: isHeading ? 10 : 0,
                                    ),
                                    child: ReaderParagraph(
                                      book: widget.book,
                                      paragraph: widget
                                          .book
                                          .paragraphs[paragraphIndex],
                                      paragraphIndex: paragraphIndex,
                                      fontSize: _fontSize,
                                      fontFamily: _readerFontFamily,
                                      lineSpacing: _lineSpacing,
                                      fontWeight: _readerFontWeight,
                                      ink: _readerInk,
                                      contextMenuBuilder:
                                          createReaderSelectionToolbar(
                                            bookId: _bookId,
                                            bookTitle: widget.book.title,
                                            currentParagraph: () =>
                                                paragraphIndex,
                                            notesLibrary: _notesLibrary,
                                            onHighlight: _toggleHighlight,
                                            onNoteSaved: _loadNotes,
                                          ),
                                      highlights: [
                                      ...?_highlights[paragraphIndex],
                                      if (_spokenSentence.isNotEmpty)
                                        _spokenSentence,
                                    ],
                                      isChapterHeading: _tocParagraphs.contains(
                                        paragraphIndex,
                                      ),
                                      noteCount: _noteCountFor(paragraphIndex),
                                      onOpenNotes: () => _openNotesForParagraph(
                                        paragraphIndex,
                                      ),
                                      onJumpToParagraph: _jumpToParagraph,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              _restorePageWhenReady();
                              return PageView.builder(
                                controller: _pageController,
                                scrollDirection: Axis.horizontal,
                                // Finger swipes are classified by
                                // ReaderGestures and routed through
                                // _changePage so the selected PageTurnStyle
                                // (cover / slide / none) always applies.
                                // PageView scrolling would bypass that.
                                physics: const NeverScrollableScrollPhysics(),
                                allowImplicitScrolling: true,
                                itemCount: _pageCount,
                                onPageChanged: (index) {
                                  if (_bookmarkPullInProgress) {
                                    return;
                                  }
                                  if (_coverJumping || _slideBusy) {
                                    return;
                                  }
                                  setState(() {
                                    _currentPage = index;
                                    _requestedPage = index;
                                  });
                                  _maybeExtendPagination();
                                  _scheduleSave();
                                },
                                itemBuilder: (context, index) => Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    _readerSideInset,
                                    _readerTopInset,
                                    _readerSideInset,
                                    _readerBottomInset,
                                  ),
                                  child: _readingPage(context, index),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
              if (_pullDownDistance > 8) _bookmarkPullIndicator(context),
              if (_coverFromPage != null) _coverTurnOverlay(context),
              if (_eyeCare != ReaderEyeCare.off)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: const Color(
                        0xffd9a441,
                      ).withValues(alpha: _eyeCare.opacity),
                    ),
                  ),
                ),
              // Fanqie BottomIndicator: page + battery only when chrome is hidden.
              if (!_showControls)
                ReaderStatusBar(
                  pageLabel: _pageProgress,
                  batteryLabel: _batteryText,
                  surface: _backgroundFor(context),
                ),
              if (!_showControls)
                ReaderRunningHead(
                  chapterLabel: _chapterLabel,
                  surface: _backgroundFor(context),
                ),
              if (_listening && !_showControls)
                TtsBar(
                  playing: ttsHandler?.isPlaying ?? false,
                  positionLabel: _ttsLabel,
                  speed: _ttsSpeed,
                  subtitle: _spokenSentence,
                  onPlayPause: () {
                    final handler = ttsHandler;
                    if (handler == null) return;
                    handler.isPlaying ? handler.pause() : handler.play();
                  },
                  onPrevious: () => ttsHandler?.skipToPrevious(),
                  onNext: () => ttsHandler?.skipToNext(),
                  onCycleSpeed: _cycleTtsSpeed,
                  onClose: _stopListening,
                ),
              if (_isCurrentViewBookmarked)
                Semantics(
                  label: '当前阅读页面已添加书签',
                  child: BookmarkRibbon(
                    surface: _backgroundFor(context),
                    progress: 1,
                    armed: false,
                    alreadyBookmarked: true,
                    label: '',
                    pinned: true,
                    showLabel: false,
                  ),
                ),
              if (_bookmarkNotice != null)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 42),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: VellumTheme.cardOf(context),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 12),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          child: Text(
                            _bookmarkNotice!,
                            style: TextStyle(
                              color: VellumTheme.inkOf(context),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Fanqie ReaderMenu: Stack overlay (not Dialog), top bar -44dp /
              // bottom bar height, both 300ms. Font picker stays wired via
              // onShowFonts → existing FontPickerSheet.
              ReaderMenu(
                visible: _showControls,
                bookTitle: widget.book.title,
                bookmarked: _isCurrentViewBookmarked,
                // Fanqie TopBar exit: leave the reader route. Progress is
                // flushed in dispose()/didChangeAppLifecycle.
                onBack: () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  } else {
                    setState(() => _showControls = false);
                  }
                },
                // Tap outside only collapses chrome — not an exit.
                onDismiss: () => setState(() => _showControls = false),
              // Listening runs through the app-wide handler; null on platforms
              // without speech support hides the action.
              onListen: ttsHandler == null ? null : _startListening,
              listening: _listening,
                onToggleBookmark: _toggleBookmarkAtCurrentPosition,
                progress: _progress,
                chapterCount: _chapters.length,
                currentChapterIndex: _chapterIndexFor(_activeParagraph) < 0
                    ? 0
                    : _chapterIndexFor(_activeParagraph),
                chapterTitle: _chapterLabel,
                canSeek: _canSeekProgress,
                onSeekProgress: _jumpToProgress,
                onSeekChapter: _jumpToChapter,
                fontSize: _fontSize,
                readerFontWeight: _readerFontWeight,
                lineSpacing: _lineSpacing,
                background: _paper,
                readingMode: _readingMode,
                pageTurnStyle: _pageTurnStyle,
                brightness: _brightness,
                eyeCare: _eyeCare,
                keepScreenOn: _keepScreenOn,
                volumeKeys: _volumeKeys,
                chapters: _chapterEntries(),
                chapterPageLabels: _chapterPageLabels(),
                bookmarks: [
                  for (final bookmark in _bookmarks)
                    MapEntry(
                      bookmark,
                      bookmarkSummary(widget.book.paragraphs, bookmark),
                    ),
                ],
                notes: _notes,
                currentParagraph: _activeParagraph,
                onJumpToParagraph: (paragraph) {
                  setState(() => _showControls = false);
                  _jumpToParagraph(
                    paragraph,
                    restoreChapter: _chapters.any(
                      (entry) => entry.key == paragraph,
                    ),
                  );
                },
                onRemoveBookmark: _removeBookmark,
                onRemoveNote: _removeNote,
                onFontSize: (value) {
                  setState(() {
                    _fontSize = value;
                  });
                  _scheduleSave();
                },
                onReaderFontWeight: (value) {
                  setState(() => _readerFontWeight = value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onLineSpacing: (value) {
                  setState(() => _lineSpacing = value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onBackground: _applyPaper,
                onReadingMode: (value) {
                  _setReadingMode(value);
                },
                onPageTurnStyle: (value) {
                  setState(() => _pageTurnStyle = value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onBrightness: (value) {
                  setState(() => _brightness = value);
                  _platform.setBrightness(value);
                  _scheduleSave();
                },
                onEyeCare: (value) {
                  setState(() => _eyeCare = value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onKeepScreenOn: (value) {
                  setState(() => _keepScreenOn = value);
                  _platform.setKeepScreenOn(value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onVolumeKeys: (value) {
                  setState(() => _volumeKeys = value);
                  _syncVolumeKeys();
                  _saveTimer?.cancel();
                  _saveState();
                },
                onShowFonts: _showFontPicker,
                onToggleUiTheme: widget.onToggleUiTheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readingPage(
    BuildContext context,
    int pageIndex, {
    bool selectable = true,
  }) {
    if (_pages.isEmpty) return const SizedBox.shrink();
    final page = pageIndex.clamp(0, _pages.length - 1);
    final fragments = _pages[page];
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: ClipRect(
              clipBehavior: Clip.hardEdge,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: constraints.maxHeight,
                maxHeight: double.infinity,
                maxWidth: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (page == 0) _title(context),
                    if (page == 0) const SizedBox(height: 30),
                    for (var index = 0; index < fragments.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == fragments.length - 1
                              ? 0
                              : (fragments[index].compactPadding ? 0 : 22),
                        ),
                        child: ReaderParagraph(
                          book: widget.book,
                          paragraph: fragments[index].text,
                          paragraphIndex: fragments[index].paragraphIndex,
                          fontSize: _fontSize,
                          fontFamily: _readerFontFamily,
                          lineSpacing: _lineSpacing,
                          fontWeight: _readerFontWeight,
                          ink: _readerInk,
                          contextMenuBuilder: createReaderSelectionToolbar(
                            bookId: _bookId,
                            bookTitle: widget.book.title,
                            currentParagraph: () =>
                                fragments[index].paragraphIndex,
                            notesLibrary: _notesLibrary,
                            onHighlight: _toggleHighlight,
                            onNoteSaved: _loadNotes,
                          ),
                          highlights: [
                                      ...?_highlights[fragments[index].paragraphIndex],
                                      if (_spokenSentence.isNotEmpty)
                                        _spokenSentence,
                                    ],
                          isChapterHeading: _tocParagraphs.contains(
                            fragments[index].paragraphIndex,
                          ),
                          noteCount: _noteCountFor(
                            fragments[index].paragraphIndex,
                          ),
                          onOpenNotes: () => _openNotesForParagraph(
                            fragments[index].paragraphIndex,
                          ),
                          showImage: fragments[index].showImage,
                          showLinkAction:
                              selectable && fragments[index].showLinkAction,
                          indentFirstLine: fragments[index].indentFirstLine,
                          selectable: selectable,
                          onJumpToParagraph: _jumpToParagraph,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) => Text(
    widget.book.title,
    style: TextStyle(
      fontFamily: _readerFontFamily,
      fontSize: _fontSize + 9,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: _readerInk,
    ),
  );
  void _showFontPicker() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => ReaderFontPickerSheet(
        surface: _backgroundFor(context),
        installedFonts: widget.installedFonts,
        activeFamily: _readerFontFamily,
        onSelectSystemFont: (family) {
          Navigator.pop(ctx);
          setState(() {
            _readerFontFamily = family;
            _lastMeasuredFontFamily = null;
          });
          _saveState();
        },
        onSelectImportedFont: (font) async {
          if (widget.onActivateFont == null) return;
          await widget.onActivateFont!(font.name);
          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);
          setState(() {
            _readerFontFamily = font.family;
            _lastMeasuredFontFamily = null;
          });
          _saveState();
        },
      ),
    );
  }

  void _changePage(BuildContext context, int delta) {
    if (!_pageController.hasClients) return;
    final pageCount = _pageCount;
    if (pageCount <= 0) return;
    final live = _pageController.hasClients
        ? _pageController.page?.round()
        : null;
    var base = (live ?? _requestedPage).clamp(0, pageCount - 1);
    if (_coverFromPage != null) base = _coverToPage ?? base;
    if (_slideBusy) base = _requestedPage.clamp(0, pageCount - 1);
    final target = (base + delta).clamp(0, pageCount - 1);
    if (target == base && !_coverAnim.isAnimating && !_slideBusy) return;

    if (_pageTurnStyle == PageTurnStyle.none) {
      setState(() {
        _requestedPage = target;
        _currentPage = target;
      });
      _jumpToPageExact(target);
      _scheduleSave();
      return;
    }

    if (_pageTurnStyle == PageTurnStyle.slide) {
      _startSlideTurn(target);
      return;
    }

    // Cover (and default): queue rapid taps instead of dropping them.
    if (_coverAnim.isAnimating) {
      _pendingPageDelta += delta;
      return;
    }
    _startCoverTurn(base, target);
  }

  void _startSlideTurn(int target) {
    if (!_pageController.hasClients) return;
    if (_slideBusy) {
      _requestedPage = target;
      _pageController.jumpToPage(_requestedPage);
    }
    _slideBusy = true;
    setState(() => _requestedPage = target);
    _pageController
        .animateToPage(
          target,
          // 180ms easeOutCubic: snappy tap-to-turn. Fanqie's slide mode uses a
          // short custom-Scroller fling; long durations feel laggy on tap.
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          setState(() {
            _currentPage = target;
            _requestedPage = target;
          });
          _slideBusy = false;
          _scheduleSave();
        });
  }

  void _startCoverTurn(int from, int to) {
    _coverFromPage = from;
    _coverToPage = to;
    // Measure the destination page before the animation starts so the
    // overlay never shows a half-paginated page that reflows mid-turn.
    if (!_pager.fullyPaginated && to >= _pager.pageCount) {
      _pager.paginateUntilPages(to + 1);
    }
    // Keep PageView on [from] during the overlay so the underlying page does
    // not re-layout mid-animation (avoids visible “reflow” under the cover).
    _dragCommitted = false;
    setState(() {
      _requestedPage = to;
    });
    _coverAnim
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        _finishCoverTurn(to);
      });
  }

  void _finishCoverTurn(int to) {
    _coverJumping = true;
    _jumpToPageExact(to);
    setState(() {
      _currentPage = to;
      _requestedPage = to;
    });
    // Drop the overlay one frame after the jump so the user never sees
    // PageView rebuild/layout under the cover.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _coverFromPage = null;
        _coverToPage = null;
      });
      _coverJumping = false;
      _scheduleSave();
      final pending = _pendingPageDelta;
      _pendingPageDelta = 0;
      if (pending != 0) {
        final pageCount = _pageCount;
        final base = to.clamp(0, pageCount - 1);
        final next = (base + pending).clamp(0, pageCount - 1);
        if (next != base) _startCoverTurn(base, next);
      }
    });
  }

  Widget _coverTurnOverlay(BuildContext context) {
    final from = _coverFromPage;
    final to = _coverToPage;
    if (from == null || to == null) return const SizedBox.shrink();
    final isNext = to > from;
    // Fanqie「覆盖」mode 2 (`pager/s.java` `w()`):
    // - 下一页: slipTarget = current；current **向左滑出**，next 钉在底下不动。
    // - 上一页: slipTarget = previous；previous **从左盖上来**，current 不动。
    // (Vellum used to slide the destination in from the right on next — reversed.)
    final movingPage = isNext ? from : to;
    final staticPage = isNext ? to : from;
    // Page surfaces are built once (as AnimatedBuilder.child) and only the
    // slide offset updates each frame. RepaintBoundary lets Flutter rasterize
    // the expensive text layers once, then just move them.
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: _coverPageSurface(context, staticPage)),
                AnimatedBuilder(
                  animation: _coverAnim,
                  child: RepaintBoundary(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(alpha: .22),
                            blurRadius: 18,
                            spreadRadius: 1,
                            // Leading edge sits on the right in both directions
                            // (next exits left; prev enters from the left).
                            offset: const Offset(10, 0),
                          ),
                        ],
                      ),
                      child: _coverPageSurface(context, movingPage),
                    ),
                  ),
                  builder: (context, child) {
                    // While the finger is down (and after a committed drag)
                    // progress is raw travel — linear = 跟手. Timed taps ease.
                    final progress = (_dragTurn || _dragCommitted)
                        ? (_dragTurn ? _dragProgress : _coverAnim.value)
                        : Curves.easeOutCubic.transform(_coverAnim.value);
                    // Next: current slides out to the left (dx 0→-1).
                    // Prev: previous slides in from the left (dx -1→0).
                    final dx = isNext ? -progress : -1 + progress;
                    return FractionalTranslation(
                      translation: Offset(dx, 0),
                      child: child,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverPageSurface(BuildContext context, int page) {
    if (page < 0 || page >= _pageCount) return const SizedBox.expand();
    // Same paper stack as the live page (underlay + image). Painting only a
    // solid colour here made the background pop every cover-style turn.
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: _paperSurface(context)),
        Padding(
          padding: EdgeInsets.fromLTRB(
            _readerSideInset,
            _readerTopInset,
            _readerSideInset,
            _readerBottomInset,
          ),
          // selectable:true matches the PageView builder exactly. Rendering the
          // overlay with selectable:false used SelectableText vs Text and let
          // the two widgets lay out differently — the page visibly "settled"
          // (paragraph spacing shifted) the moment the animation ended.
          // The overlay is already wrapped in IgnorePointer.
          child: _readingPage(context, page, selectable: true),
        ),
      ],
    );
  }
}
