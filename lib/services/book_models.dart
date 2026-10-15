import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'txt_catalog.dart';
import 'lazy_paragraphs.dart';

enum BookFormat { epub, mobi, txt }

/// Parse outcome persisted on the book shell so a failed or pending parse is
/// visible and retryable (Fanqie only kept a SharedPreferences boolean; a
/// status field is required to explain errors to the user).
enum BookParseStatus { pending, parsing, ready, failed }

class BookTocEntry {
  const BookTocEntry({required this.title, required this.paragraphIndex});
  final String title;
  final int paragraphIndex;
}

class BookImportException implements Exception {
  const BookImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportedBook {
  const ImportedBook({
    required this.title,
    this.author = '',
    required this.format,
    required this.paragraphs,
    this.coverBytes,
    this.coverText,
    this.folderId,
    this.linkTargets = const {},
    this.tocEntries = const [],
    this.imageBytes = const {},
    this.metaParagraphCount,
    this.id,
    this.catalog,
    this.contentMode = 'inline',
  });
  final String title;

  /// Author extracted from EPUB `dc:creator` / MOBI EXTH 100.
  final String author;
  final BookFormat format;
  final List<String> paragraphs;
  final Uint8List? coverBytes;
  final String? coverText;
  final String? folderId;
  final Map<int, int> linkTargets;
  final List<BookTocEntry> tocEntries;
  final Map<int, Uint8List> imageBytes;
  final int? metaParagraphCount;
  final String? id;

  /// Byte-offset chapter catalog (TXT seek mode).
  final TxtCatalog? catalog;

  /// `inline` — paragraphs live in the content JSON (EPUB/MOBI, legacy TXT).
  /// `seek` — paragraphs are served from the source file + [catalog].
  /// `chunked` — MOBI/EPUB body blocks and images are served from disk.
  final String contentMode;

  bool get usesSeek => contentMode == 'seek' && catalog != null;
  bool get usesLazyContent => usesSeek || contentMode == 'chunked';

  /// Total decoded characters — O(1) when a TXT catalog is present, so the
  /// reader does not have to iterate every paragraph at open.
  int get totalCharCount {
    final body = paragraphs;
    if (body is LazyParagraphs) return body.totalCharacters;
    final catalogChars = catalog?.totalCharCount ?? 0;
    if (catalogChars > 0) return catalogChars;
    var total = 0;
    for (final paragraph in paragraphs) {
      total += paragraph.length;
    }
    return total;
  }

  bool get hasContentLoaded =>
      paragraphs.isNotEmpty || (metaParagraphCount ?? 0) == 0;
  int get paragraphCount => paragraphs.isNotEmpty
      ? paragraphs.length
      : (catalog?.totalParagraphs ?? metaParagraphCount ?? 0);
  String get storageId => id ?? BookLibraryIds.forBook(this);

  ImportedBook copyWith({
    String? id,
    List<String>? paragraphs,
    Uint8List? coverBytes,
    String? coverText,
    String? folderId,
    TxtCatalog? catalog,
    String? contentMode,
    List<BookTocEntry>? tocEntries,
    int? metaParagraphCount,
    bool clearCoverImage = false,
    bool clearCoverText = false,
    bool clearFolder = false,
  }) => ImportedBook(
    id: id ?? this.id,
    title: title,
    author: author,
    format: format,
    paragraphs: paragraphs ?? this.paragraphs,
    coverBytes: clearCoverImage ? null : (coverBytes ?? this.coverBytes),
    coverText: clearCoverText ? null : (coverText ?? this.coverText),
    folderId: clearFolder ? null : (folderId ?? this.folderId),
    linkTargets: linkTargets,
    tocEntries: tocEntries ?? this.tocEntries,
    imageBytes: imageBytes,
    metaParagraphCount: metaParagraphCount ?? this.metaParagraphCount,
    catalog: catalog ?? this.catalog,
    contentMode: contentMode ?? this.contentMode,
  );

  ImportedBook asIndexShell() => ImportedBook(
    id: storageId,
    title: title,
    author: author,
    format: format,
    paragraphs: const [],
    coverBytes: coverBytes,
    coverText: coverText,
    folderId: folderId,
    metaParagraphCount: paragraphCount,
    // Catalog is small (offsets only) and required to reopen seek-mode TXT.
    catalog: catalog,
    contentMode: contentMode,
    tocEntries: tocEntries.take(32).toList(),
  );
}

abstract final class BookLibraryIds {
  /// Content-addressed id: `<format>_<md5 of file bytes>`.
  ///
  /// Follows Fanqie's local-book identity (`bookId = 文件 MD5`): stable across
  /// renames, usable for de-duplication, and the foreign key for progress,
  /// bookmarks and notes. Legacy shelf entries keep their persisted `id`, so
  /// existing libraries are not rewritten.
  static String forBytes(Uint8List bytes, BookFormat format) {
    final digest = md5.convert(bytes);
    return '${format.name}_${digest.toString()}';
  }

  /// Fallback for shells that never captured content bytes (legacy imports).
  static String forBook(ImportedBook book) {
    final parts = [book.format.name, book.title, '${book.paragraphCount}'];
    final source = parts.join(String.fromCharCode(0));
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return '${book.format.name}_${hash.toRadixString(16)}';
  }

  /// Ids written before the interpolation fix look like `${book.format.name}_…`
  /// and were identical for every book.
  static bool isLegacyBrokenId(String? id) => id != null && id.contains(r'${');
}

class HtmlContent {
  const HtmlContent({
    required this.paragraphs,
    required this.anchors,
    required this.links,
    required this.images,
  });
  final List<String> paragraphs;
  final Map<String, int> anchors;
  final Map<int, String> links;
  final Map<int, int> images;
}
