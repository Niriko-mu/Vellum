import 'dart:convert';

import 'package:flutter/painting.dart' show FontWeight;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum WritingFormat {
  md('Markdown', 'md'),
  txt('纯文本', 'txt');

  const WritingFormat(this.label, this.extension);
  final String label;
  final String extension;

  static WritingFormat fromName(String value) =>
      WritingFormat.values.firstWhere(
        (format) => format.name == value,
        orElse: () => WritingFormat.md,
      );
}

/// True only for ASCII blanks. `String.trim()` also eats U+3000 (`　`), which
/// is the novel indent — a line that is just `　　` is an open paragraph, not
/// a blank line.
bool _isAsciiBlank(String line) {
  for (final unit in line.codeUnits) {
    if (unit != 0x20 && unit != 0x09) return false;
  }
  return true;
}

/// 小说模式排版：段首两格缩进 + 段落之间空一行。
/// 不改标题、列表、引用、代码块；已缩进的段落保持原样。
///
/// [keepTrailingNewlines] keeps the writer's open line / empty paragraph at the
/// end. Live editing must pass true — stripping those newlines is what made
/// Enter look broken (the caret line vanished on the next format pass).
String applyNovelFormatting(
  String source, {
  bool keepTrailingNewlines = false,
}) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Trailing `\n`s are the writer sitting on a new line; never treat them as
  // content to collapse away when the editor is live.
  final trailingMatch = RegExp(r'\n+$').firstMatch(normalized);
  final trailingNewlines = trailingMatch?.group(0)?.length ?? 0;
  final bodySource = trailingNewlines > 0
      ? normalized.substring(0, normalized.length - trailingNewlines)
      : normalized;
  final lines = bodySource.split('\n');
  final out = <String>[];
  var inFence = false;
  var buffer = <String>[];

  void flushParagraph() {
    if (buffer.isEmpty) return;
    final first = buffer.first;
    final body = buffer.join('\n');
    buffer = <String>[];
    // Leave markers / already-indented prose untouched.
    final isProse =
        first.trim().isNotEmpty &&
        !_novelSkipPrefix.hasMatch(first) &&
        !first.startsWith('　') &&
        !RegExp(r'^ {2,}').hasMatch(first) &&
        !first.startsWith('\t');
    if (isProse) {
      out.add('　　$body');
    } else {
      out.add(body);
    }
    out.add(''); // blank line = paragraph gap
  }

  for (final line in lines) {
    if (line.trim().startsWith('```')) {
      flushParagraph();
      inFence = !inFence;
      out.add(line);
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    if (_isAsciiBlank(line)) {
      flushParagraph();
      // collapse extra blank lines later
      continue;
    }
    buffer.add(line);
  }
  flushParagraph();

  // Normalize: single blank line between blocks. Only trim newlines —
  // String.trim() would eat the leading `　　` (U+3000 is whitespace).
  var joined = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  joined = joined.replaceAll(RegExp(r'^\n+'), '');
  joined = joined.replaceAll(RegExp(r'\n+$'), '');
  if (keepTrailingNewlines && trailingNewlines > 0) {
    // Keep at least the open line the caret is on (one `\n`). An extra blank
    // paragraph (two `\n`) is preserved as-is so Enter Enter still feels open.
    final keep = trailingNewlines >= 2 ? trailingNewlines : 1;
    joined = '$joined${'\n' * keep}';
  }
  return joined;
}

/// True only when the writer **just pressed Enter at the end**.
///
/// Backspace that leaves a trailing newline (deleting the indent of an open
/// paragraph, or walking back into the previous line) must return false —
/// otherwise the Enter helper re-inserts `　　` and the caret can never leave
/// the new paragraph. Same for any other shrinkage or mid-document edit.
bool shouldOpenNovelParagraph(String previous, String next) {
  if (next == previous) return false;
  // Deletion / replace: never re-open.
  if (next.length <= previous.length) return false;
  // Must be a pure append at the end (Enter, or typing after it).
  if (!next.startsWith(previous)) return false;
  return next.endsWith('\n');
}

/// Result of inserting a novel-mode paragraph break at the caret.
class NovelParagraphEdit {
  const NovelParagraphEdit({required this.text, required this.caretOffset});

  final String text;
  final int caretOffset;
}

/// Enter in 小说模式: finish the current paragraph and open the next one
/// already indented (`段首两格`), so the writer can type immediately.
///
/// Idempotent — applying it to a break that is already open is a no-op.
String novelParagraphBreak(String source) {
  return novelParagraphBreakWithCaret(source).text;
}

NovelParagraphEdit novelParagraphBreakWithCaret(String source) {
  final text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Already sitting on an indented new paragraph.
  if (text.endsWith('\n\n　　')) {
    return NovelParagraphEdit(text: text, caretOffset: text.length);
  }
  // One Enter + indent: promote to a real paragraph gap.
  if (text.endsWith('\n　　')) {
    final next = '${text.substring(0, text.length - 3)}\n\n　　';
    return NovelParagraphEdit(text: next, caretOffset: next.length);
  }
  // Enter Enter, waiting for the indent.
  if (text.endsWith('\n\n')) {
    final next = '$text　　';
    return NovelParagraphEdit(text: next, caretOffset: next.length);
  }
  // Single Enter at the end — open the next paragraph properly.
  if (text.endsWith('\n')) {
    final next = '$text\n　　';
    return NovelParagraphEdit(text: next, caretOffset: next.length);
  }
  // No newline yet: finish this paragraph and open the next.
  final next = '$text\n\n　　';
  return NovelParagraphEdit(text: next, caretOffset: next.length);
}

final RegExp _novelSkipPrefix = RegExp(
  r'^(#{1,6}\s|>|[-*+]\s|\d+[.、)]\s|```|~~~)',
);

/// Editor typography for the writing tab (shared across drafts).
class WritingTypography {
  const WritingTypography({
    this.fontFamily,
    this.fontSize = 16,
    this.weightIndex = 1,
    this.novelMode = false,
    this.showSaveStatus = true,
  });

  /// null = system default; otherwise a font-family alias (built-in or
  /// imported TTF family registered through FontRegistry).
  final String? fontFamily;
  final double fontSize;

  /// 0 细 / 1 常规 / 2 中粗 / 3 粗
  final int weightIndex;

  /// 小说排版开关：开启后输入时自动「段首两格 + 段间空行」，无需每次点按钮。
  final bool novelMode;

  /// 是否在标题下方显示自动保存状态（「即将自动保存 / 保存中… / 已自动保存」）。
  ///
  /// 关掉后只保留日期，写作时视野里不再有每句话都在变的文字。
  final bool showSaveStatus;

  static const weightLabels = ['细', '常规', '中粗', '粗'];
  static const weightValues = [
    FontWeight.w300,
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w700,
  ];

  FontWeight get fontWeight =>
      weightValues[weightIndex.clamp(0, weightValues.length - 1)];

  static const minSize = 12.0;
  static const maxSize = 28.0;

  WritingTypography copyWith({
    String? fontFamily,
    bool clearFont = false,
    double? fontSize,
    int? weightIndex,
    bool? novelMode,
    bool? showSaveStatus,
  }) => WritingTypography(
    fontFamily: clearFont ? null : (fontFamily ?? this.fontFamily),
    fontSize: fontSize ?? this.fontSize,
    weightIndex: weightIndex ?? this.weightIndex,
    novelMode: novelMode ?? this.novelMode,
    showSaveStatus: showSaveStatus ?? this.showSaveStatus,
  );

  Map<String, dynamic> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'weightIndex': weightIndex,
    'novelMode': novelMode,
    'showSaveStatus': showSaveStatus,
  };

  factory WritingTypography.fromJson(Map<String, dynamic> json) {
    final size = (json['fontSize'] as num?)?.toDouble() ?? 16.0;
    return WritingTypography(
      fontFamily: json['fontFamily'] as String?,
      fontSize: size.clamp(minSize, maxSize),
      weightIndex: ((json['weightIndex'] as num?)?.toInt() ?? 1).clamp(0, 3),
      novelMode: json['novelMode'] as bool? ?? false,
      // Absent in files written before the switch existed: default to showing,
      // which is what those readers were already seeing.
      showSaveStatus: json['showSaveStatus'] as bool? ?? true,
    );
  }
}

/// Local persistence for writing-tab typography.
class WritingTypographyStore {
  const WritingTypographyStore();

  Future<WritingTypography> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const WritingTypography();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        return WritingTypography.fromJson(raw);
      }
    } catch (_) {}
    return const WritingTypography();
  }

  Future<void> save(WritingTypography value) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(value.toJson()), flush: true);
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_writing_typo.json',
    );
  }
}

class WritingDocument {
  const WritingDocument({
    required this.id,
    required this.title,
    required this.body,
    this.format = WritingFormat.md,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final WritingFormat format;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle => title.trim().isEmpty ? '未命名' : title.trim();

  String get preview {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '（空白文稿）';
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  int get characterCount => body.replaceAll('\r\n', '\n').length;

  int get wordCount {
    final text = body.trim();
    if (text.isEmpty) return 0;
    final cjkPattern = RegExp(r'[一-鿿㐀-䶿]');
    final cjk = cjkPattern.allMatches(text).length;
    final latin = text
        .replaceAll(cjkPattern, ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .length;
    return cjk + latin;
  }

  String get suggestedFileName {
    final trimmed = title.trim();
    final raw = trimmed.isEmpty ? '未命名文稿' : trimmed;
    final name = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final base = name.isEmpty ? '未命名文稿' : name;
    return '$base.${format.extension}';
  }

  WritingDocument copyWith({
    String? title,
    String? body,
    WritingFormat? format,
  }) => WritingDocument(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    format: format ?? this.format,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'format': format.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WritingDocument.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    final updated =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? created;
    return WritingDocument(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      format: WritingFormat.fromName(json['format'] as String? ?? 'md'),
      createdAt: created,
      updatedAt: updated,
    );
  }
}

/// Local draft library for the writing tab.
class WritingLibrary {
  const WritingLibrary();

  Future<List<WritingDocument>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return [];
      final docs = <WritingDocument>[];
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final doc = WritingDocument.fromJson(entry);
          if (doc.id.isNotEmpty) docs.add(doc);
        }
      }
      docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return docs;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<WritingDocument> documents) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode([for (final doc in documents) doc.toJson()]),
      flush: true,
    );
  }

  Future<WritingDocument> create({
    String title = '',
    String body = '',
    WritingFormat format = WritingFormat.md,
  }) async {
    final now = DateTime.now();
    final doc = WritingDocument(
      id: 'w_${now.microsecondsSinceEpoch}',
      title: title,
      body: body,
      format: format,
      createdAt: now,
      updatedAt: now,
    );
    final docs = await load();
    docs.insert(0, doc);
    await saveAll(docs);
    return doc;
  }

  Future<WritingDocument> upsert(WritingDocument document) async {
    final docs = await load();
    final index = docs.indexWhere((item) => item.id == document.id);
    final next = document.copyWith();
    if (index >= 0) {
      docs[index] = next;
    } else {
      docs.insert(0, next);
    }
    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveAll(docs);
    return next;
  }

  Future<void> delete(String id) async {
    final docs = await load();
    docs.removeWhere((item) => item.id == id);
    await saveAll(docs);
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_writings.json');
  }
}
