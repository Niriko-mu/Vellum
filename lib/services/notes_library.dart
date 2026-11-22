import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'atomic_json_store.dart';

/// Thrown when a library refuses to write because its document is unreadable.
///
/// The message is meant for the reader: it says what was not saved and where
/// the original file was kept. Callers must surface it rather than swallow it —
/// that silence is what made the data loss invisible.
class StorageDamagedException implements Exception {
  const StorageDamagedException(this.message, {required this.path});

  final String message;
  final String path;

  @override
  String toString() => message;
}

/// `note` keeps a written thought, `highlight` only marks the passage — both
/// render as a highlight in the body, the difference is the comment.
enum ReadingNoteStyle {
  note('笔记'),
  highlight('划线');

  const ReadingNoteStyle(this.label);
  final String label;

  static ReadingNoteStyle fromStorage(String value) =>
      ReadingNoteStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => ReadingNoteStyle.note,
      );
}

/// Storage id carried by imported notes whose book could not be identified.
///
/// They are kept rather than dropped, so nothing the reader imported is lost;
/// opening one offers to link it to a book.
const String unmatchedBookId = 'unassociated';

/// Title shown for those notes, in the reader's note list and in the library.
const String unmatchedBookTitle = '未关联笔记';

class ReadingNote {
  const ReadingNote({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.paragraphIndex,
    required this.selectedText,
    this.note = '',
    required this.createdAt,
    this.style = 'note',
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final int paragraphIndex;
  final String selectedText;
  final String note;
  final DateTime createdAt;
  final String style;

  ReadingNoteStyle get kind => ReadingNoteStyle.fromStorage(style);

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'bookTitle': bookTitle,
    'paragraphIndex': paragraphIndex,
    'selectedText': selectedText,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'style': style,
  };

  factory ReadingNote.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    return ReadingNote(
      id: json['id'] as String? ?? '',
      bookId: json['bookId'] as String? ?? '',
      bookTitle: json['bookTitle'] as String? ?? '',
      paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
      selectedText: json['selectedText'] as String? ?? '',
      note: json['note'] as String? ?? '',
      createdAt: created,
      style: json['style'] as String? ?? 'note',
    );
  }
}

/// Local notes created from reader text selection.
class NotesLibrary {
  const NotesLibrary();

  /// Reads every note. Overridden in tests with an in-memory store.
  ///
  /// Always returns a **growable** list: [add] inserts into the result, and the
  /// empty/error paths used to hand back `const []`, so the very first note a
  /// reader ever wrote threw `Cannot add to an unmodifiable list` — the save was
  /// swallowed and the composer closed with nothing written.
  ///
  /// An unreadable file reads as empty here, because a list view has nothing
  /// better to show — but [guardWritable] stops any write from acting on it.
  Future<List<ReadingNote>> load() async {
    final notes = await _read();
    return notes ?? <ReadingNote>[];
  }

  /// The notes on disk, or null when the document exists but is unreadable.
  Future<List<ReadingNote>?> _read() async {
    try {
      final file = await _file();
      final result = await AtomicJsonStore.read(file);
      _damaged = result.damaged;
      _damagedPath = result.damaged ? file.path : '';
      if (result.missing) return <ReadingNote>[];
      if (result.damaged) return null;
      final raw = jsonDecode(result.text!);
      if (raw is! List<dynamic>) {
        _damaged = true;
        _damagedPath = file.path;
        return null;
      }
      final notes = <ReadingNote>[
        for (final entry in raw)
          if (entry is Map<String, dynamic>) ReadingNote.fromJson(entry),
      ];
      notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notes;
    } catch (_) {
      // Could not even reach the file (platform channel unavailable in a unit
      // test, storage unmounted). Unknown, so writes stay allowed.
      _damaged = false;
      _damagedPath = '';
      return null;
    }
  }

  /// Set by [load] when the document exists but cannot be parsed.
  ///
  /// A flag rather than a second read: [load] already touches the file, and a
  /// mutation that followed it with its own probe would do the I/O twice (and
  /// would hang in a widget test, where real file futures never complete).
  static bool _damaged = false;
  static String _damagedPath = '';

  /// Refuses to start a read-modify-write on a document that is unreadable.
  ///
  /// Without this the mutation path read an empty list, inserted into it and
  /// saved: one damaged file silently replaced every note the reader had.
  /// Callers must have awaited [load] first, which is what sets the flag.
  Future<void> guardWritable() async {
    if (!_damaged) return;
    throw StorageDamagedException(
      '阅读笔记的记录文件已损坏，本次修改没有保存。'
      '${_damagedPath.isEmpty ? '' : '原文件已保留为 $_damagedPath${AtomicJsonStore.quarantineSuffix}。'}',
      path: _damagedPath,
    );
  }

  /// Writes every note. Overridden in tests with an in-memory store.
  Future<void> saveAll(List<ReadingNote> notes) async {
    final file = await _file();
    await AtomicJsonStore.write(
      file,
      jsonEncode([for (final note in notes) note.toJson()]),
    );
  }

  /// Serialises read-modify-write across every instance of this library.
  ///
  /// The class is stateless and `const`, so the reader's notes controller and
  /// the settings importer can be inside the same read-modify-write at once;
  /// the second one then saves its stale snapshot over the first one's note.
  ///
  /// Keyed by a constant, not by the resolved path: resolving the path is
  /// itself platform-channel I/O, and every instance of this class writes the
  /// same single document anyway.
  Future<T> _serialised<T>(Future<T> Function() operation) =>
      AtomicJsonStore.serialised('vellum_notes', operation);

  Future<ReadingNote> add({
    required String bookId,
    required String bookTitle,
    required int paragraphIndex,
    required String selectedText,
    String note = '',
    ReadingNoteStyle style = ReadingNoteStyle.note,
  }) async {
    final now = DateTime.now();
    final item = ReadingNote(
      id: 'n_${now.microsecondsSinceEpoch}',
      bookId: bookId,
      bookTitle: bookTitle,
      paragraphIndex: paragraphIndex,
      selectedText: selectedText,
      note: note,
      createdAt: now,
      style: style.name,
    );
    await _serialised(() async {
      await guardWritable();
      // Copy before mutating: a store is free to hand back a read-only list, and
      // the first note must not be the one that fails. `load` (not `_read`)
      // goes through this class's overrides, which in-memory stores rely on.
      final notes = (await load()).toList();
      notes.insert(0, item);
      await saveAll(notes);
    });
    return item;
  }

  /// Notes and highlights belonging to one book, newest first.
  Future<List<ReadingNote>> loadForBook(String bookId) async {
    final notes = await load();
    return [
      for (final note in notes)
        if (note.bookId == bookId) note,
    ];
  }

  Future<void> updateNote(String id, String note) async {
    await _serialised(() async {
      await guardWritable();
      final notes = (await load()).toList();
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].id == id) {
          notes[i] = _copy(notes[i], noteText: note);
          break;
        }
      }
      await saveAll(notes);
    });
  }

  /// Re-points a note at another book.
  ///
  /// Imported notes whose book could not be identified are stored against
  /// [unmatchedBookId]; this is how the reader links them afterwards.
  Future<void> updateBook(
    String id, {
    required String bookId,
    required String bookTitle,
  }) async {
    await _serialised(() async {
      await guardWritable();
      final notes = (await load()).toList();
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].id == id) {
          notes[i] = _copy(notes[i], bookId: bookId, bookTitle: bookTitle);
          break;
        }
      }
      await saveAll(notes);
    });
  }

  static ReadingNote _copy(
    ReadingNote note, {
    String? noteText,
    String? bookId,
    String? bookTitle,
  }) => ReadingNote(
    id: note.id,
    bookId: bookId ?? note.bookId,
    bookTitle: bookTitle ?? note.bookTitle,
    paragraphIndex: note.paragraphIndex,
    selectedText: note.selectedText,
    note: noteText ?? note.note,
    createdAt: note.createdAt,
    style: note.style,
  );

  Future<void> delete(String id) async {
    await _serialised(() async {
      await guardWritable();
      final notes = (await load()).toList();
      notes.removeWhere((n) => n.id == id);
      await saveAll(notes);
    });
  }

  /// Writes all notes as pretty JSON to [outputPath].
  Future<File> exportTo(String outputPath) async {
    final notes = await load();
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(outputPath);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(
      encoder.convert([for (final n in notes) n.toJson()]),
      encoding: utf8,
      flush: true,
    );
    return file;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_notes.json');
  }
}
