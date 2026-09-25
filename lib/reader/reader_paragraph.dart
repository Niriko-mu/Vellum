import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;

import '../services/book_importer.dart';
import '../theme/vellum_theme.dart';
import '../util/text_slices.dart';
import 'reader_markup.dart';
import 'reader_models.dart';

/// Renders one reader paragraph (body, heading, quote, list, image, link).
class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    required this.book,
    required this.paragraph,
    required this.paragraphIndex,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.fontWeight,
    required this.ink,
    required this.contextMenuBuilder,
    this.showImage = true,
    this.showLinkAction = true,
    this.indentFirstLine = true,
    this.selectable = true,
    this.onJumpToParagraph,
    this.highlights = const [],
    this.highlightColor,
    this.isChapterHeading,
    super.key,
  });

  final ImportedBook book;
  final String paragraph;
  final int paragraphIndex;
  final double fontSize;
  final String fontFamily;
  final ReaderLineSpacing lineSpacing;
  final ReaderFontWeight fontWeight;
  final Color ink;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final bool showImage;
  final bool showLinkAction;
  final bool indentFirstLine;

  /// Cover-turn animation only needs a visual snapshot — skip SelectableText.
  final bool selectable;
  final ValueChanged<int>? onJumpToParagraph;

  /// Selected passages of this paragraph, drawn with a highlight background.
  final List<String> highlights;

  /// Background painted behind [highlights]; defaults to the theme accent.
  final Color? highlightColor;

  /// Whether a table-of-contents entry starts here. Callers that know it should
  /// pass it: the fallback scans every entry, which is O(entries) per build.
  final bool? isChapterHeading;

  @override
  Widget build(BuildContext context) {
    final image = showImage ? book.imageBytes[paragraphIndex] : null;
    final target = showLinkAction ? book.linkTargets[paragraphIndex] : null;
    final standaloneImage = ReaderMarkup.isStandaloneImageParagraph(paragraph);
    final blockImage = image != null && standaloneImage;
    final fullParagraph =
        paragraphIndex >= 0 && paragraphIndex < book.paragraphs.length
        ? book.paragraphs[paragraphIndex]
        : paragraph;
    final isQuote =
        ReaderMarkup.quote.hasMatch(paragraph) ||
        ReaderMarkup.quote.hasMatch(fullParagraph);
    final isList =
        ReaderMarkup.list.hasMatch(paragraph) ||
        ReaderMarkup.list.hasMatch(fullParagraph);
    final isCenter =
        ReaderMarkup.center.hasMatch(paragraph) ||
        ReaderMarkup.center.hasMatch(fullParagraph);
    final isTocHeading =
        isChapterHeading ??
        book.tocEntries.any((entry) => entry.paragraphIndex == paragraphIndex);
    final effectiveHeading = ReaderMarkup.effectiveHeadingLevel(
      paragraph: paragraph,
      fullParagraph: fullParagraph,
      isTocEntry: isTocHeading,
    );
    final scale = effectiveHeading == null
        ? 1.0
        : ReaderMarkup.headingFontScale(effectiveHeading);
    final displayFontSize = fontSize * scale;
    final bodyInk = target == null ? ink : VellumTheme.readerAccentOf(context);
    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: displayFontSize,
      height: effectiveHeading == null
          ? lineSpacing.height
          : ReaderMarkup.headingLineHeight(effectiveHeading),
      fontWeight: effectiveHeading == null ? fontWeight.value : FontWeight.w700,
      fontStyle: isQuote ? FontStyle.italic : null,
      color: bodyInk,
      decoration: target == null ? null : TextDecoration.underline,
    );
    // Chinese body always gets `　　` unless it is a real title / quote /
    // list, or the source already carries indent. Synthetic TOC hits and
    // whole-book center layouts must not strip indent from prose.
    final needsFirstLineIndent = indentFirstLine
        ? ReaderMarkup.shouldIndentFirstLine(
            paragraph: paragraph,
            fullParagraph: fullParagraph,
            headingLevel: effectiveHeading,
            isQuote: isQuote,
            isList: isList,
            isCenter: isCenter,
          )
        : false;
    final plain = ReaderMarkup.readerText(paragraph);
    final spans = <InlineSpan>[
      // Text indent, not WidgetSpan: a leading WidgetSpan breaks SelectionArea
      // offsets and can throw RangeError(start) = -1 while selecting text.
      if (needsFirstLineIndent)
        TextSpan(
          text: '　　',
          style: TextStyle(
            fontSize: displayFontSize,
            height: effectiveHeading == null
                ? lineSpacing.height
                : ReaderMarkup.headingLineHeight(effectiveHeading),
          ),
        ),
      ..._richInlineSpans(
        plain,
        image: image,
        highlights: highlights,
        highlightColor:
            highlightColor ??
            VellumTheme.readerAccentOf(context).withValues(alpha: .22),
      ),
    ];
    final alignment = effectiveHeading != null
        ? (plain.trim().length <= 28 ? TextAlign.center : TextAlign.start)
        : isCenter
        ? TextAlign.center
        // Natural start alignment, never `TextAlign.justify`: justified
        // (non-last) lines hang their leading whitespace, which silently
        // deletes the `　　` two-em first-line indent on every paragraph
        // that wraps to two or more lines. CJK lines fill evenly anyway.
        : TextAlign.start;
    final span = TextSpan(style: textStyle, children: spans);
    // Pass style explicitly: SelectableText.rich must paint body ink
    // (custom 正文字色) rather than DefaultTextStyle.
    final text = selectable
        ? SelectableText.rich(
            span,
            style: textStyle,
            contextMenuBuilder: contextMenuBuilder,
            textAlign: alignment,
          )
        : Text.rich(span, style: textStyle, textAlign: alignment);
    final formattedText = isQuote
        ? Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: VellumTheme.readerAccentOf(
                    context,
                  ).withValues(alpha: .7),
                  width: 3,
                ),
              ),
            ),
            child: text,
          )
        : effectiveHeading != null
        ? Padding(
            padding: EdgeInsets.only(
              top: effectiveHeading <= 2 ? 10 : 6,
              bottom: 8,
            ),
            child: text,
          )
        : text;
    final content = <Widget>[
      if (blockImage)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Image.memory(
            image,
            fit: BoxFit.contain,
            width: double.infinity,
            height: MediaQuery.sizeOf(context).height * .36,
            cacheWidth: (MediaQuery.sizeOf(context).width * 2).round(),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      if (ReaderMarkup.layoutText(paragraph).isNotEmpty) formattedText,
    ];
    if (target == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...content,
        CupertinoButton(
          padding: const EdgeInsets.only(top: 2),
          minimumSize: const Size(0, 28),
          onPressed: () => onJumpToParagraph?.call(target),
          child: const Text('跳转至书内链接'),
        ),
      ],
    );
  }

  List<InlineSpan> _richInlineSpans(
    String source, {
    Uint8List? image,
    List<String> highlights = const [],
    Color highlightColor = const Color(0x33a33d2e),
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var bold = false;
    var italic = false;
    var underline = false;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            fontStyle: italic ? FontStyle.italic : null,
            decoration: underline ? TextDecoration.underline : null,
          ),
        ),
      );
      buffer.clear();
    }

    var cursor = 0;
    for (final match in ReaderMarkup.inlineTag.allMatches(source)) {
      if (match.start > cursor) {
        buffer.write(safeSubstring(source, cursor, match.start));
      }
      final token = match.group(0)!;
      if (token == '[[b]]') {
        flush();
        bold = true;
      } else if (token == '[[/b]]') {
        flush();
        bold = false;
      } else if (token == '[[i]]') {
        flush();
        italic = true;
      } else if (token == '[[/i]]') {
        flush();
        italic = false;
      } else if (token == '[[u]]') {
        flush();
        underline = true;
      } else if (token == '[[/u]]') {
        flush();
        underline = false;
      }
      cursor = match.end;
    }
    if (cursor < source.length) {
      buffer.write(safeSubstring(source, cursor));
    }
    flush();

    if (image != null && source.contains('[[image:')) {
      final rebuilt = <InlineSpan>[];
      for (final span in spans) {
        final text = span is TextSpan ? (span.text ?? '') : '';
        if (!text.contains('[[image:')) {
          rebuilt.add(span);
          continue;
        }
        var pos = 0;
        for (final marker in ReaderMarkup.inlineImage.allMatches(text)) {
          if (marker.start > pos) {
            rebuilt.add(
              TextSpan(
                text: safeSubstring(text, pos, marker.start),
                style: span is TextSpan ? span.style : null,
              ),
            );
          }
          rebuilt.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Image.memory(
                  image,
                  width: fontSize * 1.05,
                  height: fontSize * 1.05,
                  fit: BoxFit.contain,
                  cacheWidth: (fontSize * 2.2).round(),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          pos = marker.end;
        }
        if (pos < text.length) {
          rebuilt.add(
            TextSpan(
              text: safeSubstring(text, pos),
              style: span is TextSpan ? span.style : null,
            ),
          );
        }
      }
      spans
        ..clear()
        ..addAll(rebuilt);
    }

    if (spans.isEmpty) spans.add(TextSpan(text: source));
    if (highlights.isEmpty) return spans;
    return _highlightSpans(spans, highlights, highlightColor);
  }

  /// Splits plain text spans so every occurrence of a highlighted passage gets
  /// [highlightColor] as its background. Non-text spans pass through.
  static List<InlineSpan> _highlightSpans(
    List<InlineSpan> spans,
    List<String> highlights,
    Color highlightColor,
  ) {
    // The stored passage may carry the paragraph's leading indent or padding.
    final needles = <String>[];
    for (final highlight in highlights) {
      final value = highlight.trim();
      if (value.isNotEmpty && !needles.contains(value)) needles.add(value);
    }
    if (needles.isEmpty) return spans;

    final result = <InlineSpan>[];
    for (final span in spans) {
      final text = span is TextSpan ? span.text : null;
      if (text == null || text.isEmpty) {
        result.add(span);
        continue;
      }
      final ranges = <({int start, int end})>[];
      for (final needle in needles) {
        var from = 0;
        while (true) {
          final at = text.indexOf(needle, from);
          if (at < 0) break;
          ranges.add((start: at, end: at + needle.length));
          from = at + needle.length;
        }
      }
      if (ranges.isEmpty) {
        result.add(span);
        continue;
      }
      ranges.sort((a, b) => a.start.compareTo(b.start));
      final base = (span as TextSpan).style ?? const TextStyle();
      final marked = base.copyWith(backgroundColor: highlightColor);
      var cursor = 0;
      for (final range in ranges) {
        final start = range.start.clamp(cursor, text.length);
        final end = range.end.clamp(start, text.length);
        if (start > cursor) {
          result.add(
            TextSpan(text: safeSubstring(text, cursor, start), style: base),
          );
        }
        if (end > start) {
          result.add(
            TextSpan(text: safeSubstring(text, start, end), style: marked),
          );
        }
        cursor = end;
      }
      if (cursor < text.length) {
        result.add(TextSpan(text: safeSubstring(text, cursor), style: base));
      }
    }
    return result;
  }
}
