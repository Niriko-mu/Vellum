/// Speakable-text preparation for the listen (听书) feature.
///
/// The reader stores paragraphs in its own markup (`[[b]]`, `[[vellum-heading:2]]`,
/// `[[image:3]]`); speech APIs want plain text. Segments are **sentence
/// granular** (the reference reader's 双击听书 speaks the tapped sentence), and
/// long sentence-free runs are hard-cut inside [buildSpeakableSegments].
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'book_search.dart' show bookContentPathFor;
import 'txt_catalog.dart';
import 'txt_seek_source.dart';

Future<List<SpeakableSegment>> buildSpeakableSegmentsInBackground(
  List<String> paragraphs,
) {
  final message = <String, dynamic>{};
  if (paragraphs is TxtParagraphList) {
    message['txtPath'] = paragraphs.source.file.path;
    message['catalog'] = paragraphs.catalog.toJson();
  } else if (bookContentPathFor(paragraphs) case final String path) {
    message['contentPath'] = path;
  } else {
    message['paragraphs'] = paragraphs;
  }
  return compute(_buildSpeakableWorker, message);
}

List<SpeakableSegment> _buildSpeakableWorker(Map<String, dynamic> message) {
  TxtSeekSource? source;
  try {
    List<String> paragraphs;
    if (message['txtPath'] case final String path) {
      source = TxtSeekSource(
        file: File(path),
        catalog: TxtCatalog.fromJson(
          message['catalog'] as Map<String, dynamic>,
        ),
      );
      paragraphs = TxtParagraphList(source);
    } else if (message['contentPath'] case final String path) {
      final raw =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      paragraphs = (raw['paragraphs'] as List<dynamic>).cast<String>();
    } else {
      paragraphs = message['paragraphs'] as List<String>;
    }
    return buildSpeakableSegments(
      paragraphs,
      maxSegments: 50000,
      maxTotalChars: 8 * 1024 * 1024,
    );
  } finally {
    source?.close();
  }
}

class SpeakableSegment {
  const SpeakableSegment({
    required this.paragraphIndex,
    required this.sentenceIndex,
    required this.text,
  });

  /// Book paragraph this sentence belongs to, so playback can follow the text.
  final int paragraphIndex;

  /// Sentence index within the paragraph (kept in cache keys).
  final int sentenceIndex;

  final String text;
}

final RegExp _blockMarker = RegExp(
  r'^\[\[vellum-(?:heading:[1-6]|quote|list|center)\]\]+',
);
final RegExp _inlineMarker = RegExp(r'\[\[/?[biu]\]\]');
final RegExp _imageMarker = RegExp(r'\[\[image:\d+\]\]');
final RegExp _whitespace = RegExp(r'\s+');

/// Strips reader markup down to what a speech engine should read.
String speakableText(String paragraph) => paragraph
    .replaceFirst(_blockMarker, '')
    .replaceAll(_imageMarker, '')
    .replaceAll(_inlineMarker, '')
    .replaceAll(_whitespace, ' ')
    .trim();

/// Sentence ends, absorbing a trailing closing quote/bracket — the Dart
/// approximation of the reference reader's `libtokenizer.so` sentence bounds.
final RegExp _sentenceEnd = RegExp(r'[。！？!?…；;]["\x27”’)\]]?');

/// Builds the playback queue: one segment per sentence.
///
/// Empty and image-only paragraphs are skipped. A run without any sentence end
/// (a wall of text) is hard-cut at [maxChars] so no request overflows the API.
List<SpeakableSegment> buildSpeakableSegments(
  List<String> paragraphs, {
  int maxChars = 1800,
  int? maxSegments,
  int? maxTotalChars,
}) {
  final segments = <SpeakableSegment>[];
  var totalChars = 0;
  for (var index = 0; index < paragraphs.length; index++) {
    final text = speakableText(paragraphs[index]);
    if (text.isEmpty) continue;
    var sentenceIndex = 0;
    for (final sentence in _splitSentences(text, maxChars)) {
      if (sentence.isEmpty) continue;
      totalChars += sentence.length;
      if ((maxSegments != null && segments.length >= maxSegments) ||
          (maxTotalChars != null && totalChars > maxTotalChars)) {
        throw const FormatException('听书内容超过安全大小，请将电子书拆分后朗读。');
      }
      segments.add(
        SpeakableSegment(
          paragraphIndex: index,
          sentenceIndex: sentenceIndex++,
          text: sentence,
        ),
      );
    }
  }
  return segments;
}

/// Sentence span `[start, end)` containing [offset] in [text] (rendered plain
/// text), or null when the offset is out of range. Used by 双击听书.
({int start, int end})? sentenceAt(String text, int offset) {
  if (text.isEmpty || offset < 0) return null;
  final o = offset.clamp(0, text.length - 1);
  var start = 0;
  var stop = text.length;
  for (final match in _sentenceEnd.allMatches(text)) {
    if (match.end <= o) {
      start = match.end;
    } else {
      stop = match.end;
      break;
    }
  }
  while (start < text.length && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  return stop > start ? (start: start, end: stop) : null;
}

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0a ||
    unit == 0x0d ||
    unit == 0x3000;

/// Splits [text] on sentence ends; a terminator-free run is hard-cut at
/// [maxChars].
List<String> _splitSentences(String text, int maxChars) {
  final chunks = <String>[];
  var start = 0;
  for (final match in _sentenceEnd.allMatches(text)) {
    final end = match.end;
    if (end - start > maxChars) {
      // One absurdly long "sentence": hard-cut before it.
      while (end - start > maxChars) {
        chunks.add(text.substring(start, start + maxChars).trim());
        start += maxChars;
      }
    }
    final piece = text.substring(start, end).trim();
    if (piece.isNotEmpty) chunks.add(piece);
    start = end;
  }
  if (start < text.length) {
    var rest = start;
    while (text.length - rest > maxChars) {
      chunks.add(text.substring(rest, rest + maxChars).trim());
      rest += maxChars;
    }
    final tail = text.substring(rest).trim();
    if (tail.isNotEmpty) chunks.add(tail);
  }
  return chunks;
}
