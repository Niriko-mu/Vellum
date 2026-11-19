/// One-time alignment ratio for stored font sizes.
///
/// The reference reader (番茄小说) lays out its body text at **24dp** by
/// default (`com.dragon.reader.lib.resource.a` → `ot5.j.d(24)`, both dp→px),
/// while Vellum's original default was 19 logical px — the same slider number
/// therefore looked noticeably smaller. Preferences saved before that
/// alignment are scaled once by `24/19` on load, flagged, and then left alone.
const kReaderLegacyFontScale = 24 / 19;

/// Body text sizes are rendered in this range, in logical pixels.
const kReaderFontMin = 16.0;
const kReaderFontMax = 42.0;
const kReaderFontDefault = 24.0;

/// Scales sizes saved before the reference-reader alignment exactly once.
///
/// Idempotent: already-aligned preferences come back untouched, so callers may
/// apply this on every load.
ReaderPreferences alignedReaderPreferences(ReaderPreferences prefs) {
  if (prefs.fontScaleAligned) return prefs;
  final scaled = (prefs.fontSize * kReaderLegacyFontScale)
      .roundToDouble()
      .clamp(kReaderFontMin, kReaderFontMax);
  return prefs.copyWith(fontSize: scaled, fontScaleAligned: true);
}

class FontPreferences {
  const FontPreferences({
    this.useForUi = false,
    this.useForContent = false,
    this.activeFont = '',
  });

  final bool useForUi;
  final bool useForContent;
  final String activeFont;
}

/// Global reader display preferences — shared across all books.
class ReaderPreferences {
  const ReaderPreferences({
    this.fontSize = kReaderFontDefault,
    this.readerFontFamily = 'Georgia',
    this.readerFontWeight = 'regular',
    this.lineSpacing = 'standard',
    this.backgroundValue,
    this.mode = 'page',
    this.pageTurn = 'cover',
    this.brightness = -1,
    this.eyeCare = 'off',
    this.keepScreenOn = true,
    this.volumeKeys = false,
    this.fontScaleAligned = true,
  });

  final double fontSize;
  final String readerFontFamily;
  final String readerFontWeight;
  final String lineSpacing;
  final int? backgroundValue;
  final String mode;
  final String pageTurn;

  /// Screen brightness override, `-1` follows the system.
  final double brightness;

  /// `off` / `soft` / `warm` warm-tint overlay strength.
  final String eyeCare;

  /// Keep the screen awake while the reader is open.
  final bool keepScreenOn;

  /// Volume buttons turn pages while the reader is open.
  final bool volumeKeys;

  /// Whether the stored size has already been scaled by
  /// [kReaderLegacyFontScale]. Files written before that alignment carry no
  /// key and therefore read as `false`.
  final bool fontScaleAligned;

  ReaderPreferences copyWith({double? fontSize, bool? fontScaleAligned}) =>
      ReaderPreferences(
        fontSize: fontSize ?? this.fontSize,
        readerFontFamily: readerFontFamily,
        readerFontWeight: readerFontWeight,
        lineSpacing: lineSpacing,
        backgroundValue: backgroundValue,
        mode: mode,
        pageTurn: pageTurn,
        brightness: brightness,
        eyeCare: eyeCare,
        keepScreenOn: keepScreenOn,
        volumeKeys: volumeKeys,
        fontScaleAligned: fontScaleAligned ?? this.fontScaleAligned,
      );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'readerFontFamily': readerFontFamily,
    'readerFontWeight': readerFontWeight,
    'lineSpacing': lineSpacing,
    'backgroundValue': backgroundValue,
    'mode': mode,
    'pageTurn': pageTurn,
    'brightness': brightness,
    'eyeCare': eyeCare,
    'keepScreenOn': keepScreenOn,
    'volumeKeys': volumeKeys,
    'fontScaleAligned': fontScaleAligned,
  };

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) =>
      ReaderPreferences(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? kReaderFontDefault,
        readerFontFamily: json['readerFontFamily'] as String? ?? 'Georgia',
        readerFontWeight: json['readerFontWeight'] as String? ?? 'regular',
        lineSpacing: json['lineSpacing'] as String? ?? 'standard',
        backgroundValue: (json['backgroundValue'] as num?)?.toInt(),
        mode: json['mode'] as String? ?? 'scroll',
        pageTurn: json['pageTurn'] as String? ?? 'cover',
        brightness: (json['brightness'] as num?)?.toDouble() ?? -1,
        eyeCare: json['eyeCare'] as String? ?? 'off',
        keepScreenOn: json['keepScreenOn'] as bool? ?? true,
        volumeKeys: json['volumeKeys'] as bool? ?? false,
        fontScaleAligned: json['fontScaleAligned'] as bool? ?? false,
      );
}

class InstalledFont {
  const InstalledFont({
    required this.name,
    required this.family,
    this.displayName,
  });

  /// File key (without `.ttf`) used to load/delete the font file.
  final String name;
  final String family;

  /// Human-readable name from the font's internal `name` table.
  /// Falls back to [name] (filename) when unavailable.
  final String? displayName;

  String get label => (displayName?.isNotEmpty ?? false) ? displayName! : name;
}

class ReadingState {
  const ReadingState({
    this.fontSize = kReaderFontDefault,
    this.readerFontFamily = 'Georgia',
    this.readerFontWeight = 'regular',
    this.lineSpacing = 'standard',
    this.backgroundValue,
    this.mode = 'page',
    this.position = 0,
    this.page = 0,
    this.paragraphIndex = 0,
    this.bookmarks = const [],
    this.pageTurn = 'cover',
    this.bookId = '',
    this.brightness = -1,
    this.eyeCare = 'off',
    this.keepScreenOn = true,
    this.volumeKeys = false,
    this.chapterPositions = const {},
  });

  final double fontSize;
  final String readerFontFamily;
  final String readerFontWeight;
  final String lineSpacing;
  final int? backgroundValue;
  final String mode;
  final double position;
  final int page;
  final int paragraphIndex;
  final List<int> bookmarks;

  /// `cover` or `none` — page turn animation style.
  final String pageTurn;

  /// Storage id of the book this state belongs to.
  final String bookId;

  /// Screen brightness override, `-1` follows the system.
  final double brightness;
  final String eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;
  final Map<int, ChapterReadingPosition> chapterPositions;

  ReadingState copyWith({String? bookId}) => ReadingState(
    fontSize: fontSize,
    readerFontFamily: readerFontFamily,
    readerFontWeight: readerFontWeight,
    lineSpacing: lineSpacing,
    backgroundValue: backgroundValue,
    mode: mode,
    position: position,
    page: page,
    paragraphIndex: paragraphIndex,
    bookmarks: bookmarks,
    pageTurn: pageTurn,
    bookId: bookId ?? this.bookId,
    brightness: brightness,
    eyeCare: eyeCare,
    keepScreenOn: keepScreenOn,
    volumeKeys: volumeKeys,
    chapterPositions: chapterPositions,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'readerFontFamily': readerFontFamily,
    'readerFontWeight': readerFontWeight,
    'lineSpacing': lineSpacing,
    'backgroundValue': backgroundValue,
    'mode': mode,
    'position': position,
    'page': page,
    'paragraphIndex': paragraphIndex,
    'bookmarks': bookmarks,
    'pageTurn': pageTurn,
    'bookId': bookId,
    'brightness': brightness,
    'eyeCare': eyeCare,
    'keepScreenOn': keepScreenOn,
    'volumeKeys': volumeKeys,
    'chapterPositions': {
      for (final entry in chapterPositions.entries)
        entry.key.toString(): entry.value.toJson(),
    },
  };

  factory ReadingState.fromJson(Map<String, dynamic> json) => ReadingState(
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? kReaderFontDefault,
    readerFontFamily: json['readerFontFamily'] as String? ?? 'Georgia',
    readerFontWeight: json['readerFontWeight'] as String? ?? 'regular',
    lineSpacing: json['lineSpacing'] as String? ?? 'standard',
    backgroundValue: (json['backgroundValue'] as num?)?.toInt(),
    mode: json['mode'] as String? ?? 'scroll',
    position: (json['position'] as num?)?.toDouble() ?? 0,
    page: (json['page'] as num?)?.toInt() ?? 0,
    paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
    bookmarks: (json['bookmarks'] as List<dynamic>? ?? [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
    pageTurn: json['pageTurn'] as String? ?? 'cover',
    bookId: json['bookId'] as String? ?? '',
    brightness: (json['brightness'] as num?)?.toDouble() ?? -1,
    eyeCare: json['eyeCare'] as String? ?? 'off',
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    volumeKeys: json['volumeKeys'] as bool? ?? false,
    chapterPositions: _chapterPositionsFromJson(json['chapterPositions']),
  );
}

class ChapterReadingPosition {
  const ChapterReadingPosition({
    this.position = 0,
    this.page = 0,
    this.paragraphIndex = 0,
  });

  final double position;
  final int page;
  final int paragraphIndex;

  Map<String, dynamic> toJson() => {
    'position': position,
    'page': page,
    'paragraphIndex': paragraphIndex,
  };

  factory ChapterReadingPosition.fromJson(Map<String, dynamic> json) =>
      ChapterReadingPosition(
        position: (json['position'] as num?)?.toDouble() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 0,
        paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
      );
}

Map<int, ChapterReadingPosition> _chapterPositionsFromJson(Object? value) {
  if (value is! Map) return const {};
  final result = <int, ChapterReadingPosition>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key.toString());
    final raw = entry.value;
    if (key != null && raw is Map) {
      result[key] = ChapterReadingPosition.fromJson(
        Map<String, dynamic>.from(raw),
      );
    }
  }
  return result;
}

class StorageUsage {
  const StorageUsage({
    required this.libraryBytes,
    required this.readingStateBytes,
    required this.fontBytes,
    this.backgroundBytes = 0,
    this.ttsBytes = 0,
  });

  final int libraryBytes;
  final int readingStateBytes;
  final int fontBytes;

  /// Custom reading papers (backgrounds/).
  final int backgroundBytes;

  /// Cached speech audio (tts_audio/).
  final int ttsBytes;

  int get totalBytes =>
      libraryBytes + readingStateBytes + fontBytes + backgroundBytes + ttsBytes;
}

class LibraryFolder {
  const LibraryFolder({required this.id, required this.name});
  final String id;
  final String name;
}
