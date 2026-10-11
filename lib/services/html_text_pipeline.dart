import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as markdown;

import 'book_models.dart';

/// HTML → reader-markup text pipeline shared by MOBI/EPUB.
class HtmlTextPipeline {
  const HtmlTextPipeline();

  // Compiled once instead of per document, per element or per paragraph:
  // import runs these patterns hundreds of thousands of times on a large book.
  static final _recindexImage = RegExp(
    r'''<img[^>]*recindex\s*=\s*["']?(\d+)["']?[^>]*>''',
    caseSensitive: false,
  );
  static final _idTag = RegExp(
    r'''<[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
  );
  static final _hrefTag = RegExp(
    r'''<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
  );
  static final _closingAnchor = RegExp(r'</a\s*>', caseSensitive: false);
  static final _anchorMarker = RegExp(r'\[\[anchor:([^\]]+)\]\]');
  static final _linkMarker = RegExp(r'\[\[link:([^\]]+)\]\]');
  static final _imageMarker = RegExp(r'\[\[image:(\d+)\]\]');
  static final _metadataMarker = RegExp(r'\[\[(?:anchor|link):[^\]]+\]\]');
  static final _emptyLinkMarker = RegExp(r'\[\[/link\]\]');

  static final _imageFileIndex = RegExp(
    r'(?:^|[/\\])(\d+)\.(?:jpe?g|png|gif)$',
    caseSensitive: false,
  );
  static final _styleCenter = RegExp(r'text-align\s*:\s*center');
  static final _styleBold = RegExp(r'font-weight\s*:\s*(bold|[6-9]00)');
  static final _styleItalic = RegExp(r'font-style\s*:\s*italic');
  static final _styleUnderline = RegExp(r'text-decoration[^;]*underline');
  static final _headingTag = RegExp(r'^h[1-6]$');

  static final _openBoldTag = RegExp(
    r'<(b|strong)\b[^>]*>',
    caseSensitive: false,
  );
  static final _closeBoldTag = RegExp(
    r'</(b|strong)\s*>',
    caseSensitive: false,
  );
  static final _openItalicTag = RegExp(
    r'<(i|em|cite|var)\b[^>]*>',
    caseSensitive: false,
  );
  static final _closeItalicTag = RegExp(
    r'</(i|em|cite|var)\s*>',
    caseSensitive: false,
  );
  static final _openUnderlineTag = RegExp(r'<u\b[^>]*>', caseSensitive: false);
  static final _closeUnderlineTag = RegExp(r'</u\s*>', caseSensitive: false);
  static final _openHeadingTag = RegExp(
    r'<h([1-6])\b[^>]*>',
    caseSensitive: false,
  );
  static final _openQuoteTag = RegExp(
    r'<blockquote\b[^>]*>',
    caseSensitive: false,
  );
  static final _openListItemTag = RegExp(r'<li\b[^>]*>', caseSensitive: false);
  static final _breakTag = RegExp(
    r'<(br|/p|/h[1-6]|/div|/section|/article|/pre|/table|/li|/blockquote|hr|/center)\b[^>]*>',
    caseSensitive: false,
  );
  static final _openCenterTag = RegExp(
    r'<center\b[^>]*>',
    caseSensitive: false,
  );
  static final _anyTag = RegExp(r'<[^>]*>');

  /// A tag that never reaches its `>` — `<font color="red"` in either position,
  /// with the text after it left alone. Deliberately shaped like a real tag
  /// (`<`, optional `/`, name, attribute runs) so ordinary prose such as
  /// `A < B` survives.
  static final _danglingTag = RegExp(
    r'</?[a-zA-Z][a-zA-Z0-9:._-]*'
    r'(?:\s+[a-zA-Z_:][a-zA-Z0-9_.:-]*'
    r'''(?:\s*=\s*(?:"[^"]*"?|'[^']*'?|[^\s<>"']*))?)*''',
  );

  /// Reader markup (`[[b]]`, `[[vellum-heading:1]]`, `[[image:3]]`).
  static final _readerMarker = RegExp(r'\[\[[^\]]*\]\]');
  static final _entityPattern = RegExp(
    r'&(?:#x[0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]+);',
  );

  static final _paragraphBreak = RegExp(r'\n\s*\n');
  static final _whitespaceRun = RegExp(r'\s+');

  /// Any of these means [normalizeReaderMarkup] has something to rewrite; a
  /// paragraph without one is returned as-is, skipping ~15 regex passes for the
  /// plain prose that makes up most of a novel.
  static final _markupHint = RegExp(r'[*_`\[#>]|\d+[.)]\s|[-+]\s');
  static final _looksMarkdown = RegExp(
    r'^(?:#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)]\s+)|!?(?:\[[^\]]+\]\([^)]*\))|(?:\*{1,3}|_{1,3}|`)',
  );
  static final _markupTagSpacing = RegExp(
    r'(\[\[vellum-(?:quote|list|heading:[1-6])\]\])\s+',
  );
  static final _headingPrefix = RegExp(r'^(#{1,6})\s+');
  static final _listPrefix = RegExp(r'^(?:[-*+]\s+|\d+[.)]\s+)');
  static final _quoteRun = RegExp(r'^(?:\[\[vellum-quote\]\])+');
  static final _listRun = RegExp(r'^(?:\[\[vellum-list\]\])+');
  static final _markdownLink = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
  static final _boldItalicStar = RegExp(r'(?<!\*)\*\*\*([^*]+)\*\*\*');
  static final _boldStar = RegExp(r'(?<!\*)\*\*([^*]+)\*\*');
  static final _italicStar = RegExp(r'(?<!\*)\*([^*]+)\*');
  static final _boldItalicUnder = RegExp(r'(?<!_)___([^_]+)___');
  static final _boldUnder = RegExp(r'(?<!_)__([^_]+)__');
  static final _italicUnder = RegExp(r'(?<!_)_([^_]+)_');
  static final _codeSpan = RegExp(r'`([^`]+)`');

  HtmlContent convert(String source, String documentPath) {
    final marked = source
        .replaceAllMapped(
          _recindexImage,
          (match) => '[[image:${match.group(1)}]]',
        )
        .replaceAllMapped(
          _idTag,
          (match) =>
              '${match.group(0)}[[anchor:$documentPath#${match.group(1)}]]',
        )
        .replaceAllMapped(
          _hrefTag,
          (match) =>
              '[[link:${resolveLink(documentPath, match.group(1)!)}]]${match.group(0)}',
        )
        .replaceAll(_closingAnchor, '[[/link]]');
    final raw = htmlToText(marked);
    final paragraphs = splitParagraphs(raw);
    final anchors = <String, int>{};
    final links = <int, String>{};
    final images = <int, int>{};
    for (var index = 0; index < paragraphs.length; index++) {
      final paragraph = paragraphs[index];
      for (final match in _anchorMarker.allMatches(paragraph)) {
        anchors[match.group(1)!] = index;
      }
      final link = _linkMarker.firstMatch(paragraph);
      if (link != null) links[index] = link.group(1)!;
      final image = _imageMarker.firstMatch(paragraph);
      if (image != null) images[index] = int.parse(image.group(1)!);
      paragraphs[index] = paragraph
          .replaceAll(_metadataMarker, '')
          .replaceAll(_emptyLinkMarker, '')
          .trim();
    }
    final cleaned = <String>[];
    final oldToNew = <int, int>{};
    for (var index = 0; index < paragraphs.length; index++) {
      if (paragraphs[index].isEmpty && !images.containsKey(index)) continue;
      oldToNew[index] = cleaned.length;
      cleaned.add(paragraphs[index]);
    }
    final remapImages = <int, int>{};
    for (final entry in images.entries) {
      final target = oldToNew[entry.key];
      if (target != null) remapImages[target] = entry.value;
    }
    final remapLinks = <int, String>{};
    for (final entry in links.entries) {
      final target = oldToNew[entry.key];
      if (target != null) remapLinks[target] = entry.value;
    }
    final remapAnchors = <String, int>{};
    for (final entry in anchors.entries) {
      final target = oldToNew[entry.value];
      if (target != null) remapAnchors[entry.key] = target;
    }
    return HtmlContent(
      paragraphs: cleaned,
      anchors: remapAnchors,
      links: remapLinks,
      images: remapImages,
    );
  }

  String resolveLink(String documentPath, String href) {
    if (href.startsWith('#')) return '$documentPath$href';
    final hash = href.indexOf('#');
    if (hash < 0) return href;
    final slash = documentPath.lastIndexOf('/');
    final directory = slash < 0 ? '' : documentPath.substring(0, slash + 1);
    return '$directory$href';
  }

  String htmlToText(String source) {
    if (source.length > 2 * 1024 * 1024) return htmlToTextFast(source);
    final fragment = html_parser.parseFragment(source);
    final output = StringBuffer();
    // Tracks the trailing newlines so paragraphBreak never has to flatten the
    // whole buffer (which made large documents quadratic).
    var trailingNewlines = 0;

    void emit(String value) {
      if (value.isEmpty) return;
      output.write(value);
      if (value.endsWith('\n\n')) {
        trailingNewlines = 2;
      } else if (value.endsWith('\n')) {
        if (trailingNewlines < 2) trailingNewlines = 1;
      } else {
        trailingNewlines = 0;
      }
    }

    void paragraphBreak() {
      if (output.isEmpty || trailingNewlines >= 2) return;
      emit('\n\n');
    }

    void visit(dom.Node node) {
      if (node is dom.Text) {
        emit(node.data);
        return;
      }
      if (node is! dom.Element) {
        for (final child in node.nodes) {
          visit(child);
        }
        return;
      }
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'script' || tag == 'style' || tag == 'head') return;
      if (tag == 'br') {
        emit('\n\n');
        return;
      }
      if (tag == 'hr') {
        paragraphBreak();
        return;
      }
      if (tag == 'img') {
        final recindex = node.attributes['recindex'];
        if (recindex != null && recindex.isNotEmpty) {
          emit('[[image:$recindex]]');
        } else {
          final src = node.attributes['src'] ?? '';
          final fileIndex = _imageFileIndex.firstMatch(src)?.group(1);
          if (fileIndex != null) {
            emit('[[image:$fileIndex]]');
          }
        }
        return;
      }
      final inlineStyle = (node.attributes['style'] ?? '').toLowerCase();
      final isBoldTag = tag == 'b' || tag == 'strong' || tag == 'th';
      final isItalicTag =
          tag == 'i' || tag == 'em' || tag == 'cite' || tag == 'var';
      final isUnderlineTag = tag == 'u';
      final isCenterTag = tag == 'center';
      final alignAttr = (node.attributes['align'] ?? '').toLowerCase();
      final isCentered =
          isCenterTag ||
          alignAttr == 'center' ||
          _styleCenter.hasMatch(inlineStyle);
      final styleBold = _styleBold.hasMatch(inlineStyle);
      final styleItalic = _styleItalic.hasMatch(inlineStyle);
      final styleUnderline = _styleUnderline.hasMatch(inlineStyle);
      final openBold = isBoldTag || styleBold;
      final openItalic = isItalicTag || styleItalic;
      final openUnderline = isUnderlineTag || styleUnderline;
      if (openBold) emit('[[b]]');
      if (openItalic) emit('[[i]]');
      if (openUnderline) emit('[[u]]');
      final block = {'p', 'div', 'section', 'article', 'pre', 'table'};
      final heading = _headingTag.hasMatch(tag);
      final quote = tag == 'blockquote';
      final nestedQuote = quote && node.parent?.localName == 'blockquote';
      final inQuote = node.parent?.localName == 'blockquote';
      final listItem = tag == 'li';
      final needsBreak =
          (block.contains(tag) && !inQuote) ||
          heading ||
          (quote && !nestedQuote) ||
          listItem ||
          isCenterTag;
      if (needsBreak) {
        paragraphBreak();
      }
      if (heading) emit('[[vellum-heading:${tag.substring(1)}]]');
      if (quote && !nestedQuote) emit('[[vellum-quote]]');
      if (isCentered && !heading) emit('[[vellum-center]]');
      if (listItem) emit('[[vellum-list]]');
      for (final child in node.nodes) {
        visit(child);
      }
      if (openUnderline) emit('[[/u]]');
      if (openItalic) emit('[[/i]]');
      if (openBold) emit('[[/b]]');
      if (needsBreak) {
        paragraphBreak();
      }
    }

    for (final node in fragment.nodes) {
      visit(node);
    }
    return output.toString();
  }

  String htmlToTextFast(String source) {
    final visible = source.replaceAll(
      RegExp(
        r'<(head|script|style)\b[^>]*>[\s\S]*?</\1\s*>',
        caseSensitive: false,
      ),
      '',
    );
    final withInline = visible
        .replaceAllMapped(_openBoldTag, (_) => '[[b]]')
        .replaceAllMapped(_closeBoldTag, (_) => '[[/b]]')
        .replaceAllMapped(_openItalicTag, (_) => '[[i]]')
        .replaceAllMapped(_closeItalicTag, (_) => '[[/i]]')
        .replaceAllMapped(_openUnderlineTag, (_) => '[[u]]')
        .replaceAllMapped(_closeUnderlineTag, (_) => '[[/u]]');
    final withBreaks = withInline
        .replaceAllMapped(
          _openHeadingTag,
          (match) => '[[vellum-heading:${match.group(1)}]]',
        )
        .replaceAll(_openQuoteTag, '[[vellum-quote]]')
        .replaceAll(_openListItemTag, '[[vellum-list]]')
        .replaceAll(_breakTag, '\n\n')
        .replaceAll(_openCenterTag, '\n\n[[vellum-center]]')
        .replaceAll(_anyTag, '');
    return decodeHtmlEntities(withBreaks);
  }

  static const Map<String, String> _htmlEntities = {
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'sbquo': '‚',
    'bdquo': '„',
    'bull': '•',
    'middot': '·',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'deg': '°',
    'plusmn': '±',
    'times': '×',
    'divide': '÷',
    'sect': '§',
    'para': '¶',
    'dagger': '†',
    'Dagger': '‡',
    'permil': '‰',
    'euro': '€',
    'pound': '£',
    'yen': '¥',
    'cent': '¢',
    'laquo': '«',
    'raquo': '»',
    'prime': '′',
    'Prime': '″',
    'dArr': '⇓',
    'uArr': '⇑',
    'rArr': '⇒',
    'lArr': '⇐',
    'hArr': '⇔',
    'infin': '∞',
    'ne': '≠',
    'le': '≤',
    'ge': '≥',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'pi': 'π',
    'sigma': 'σ',
    'omega': 'ω',
  };

  String decodeHtmlEntities(String source) {
    if (!source.contains('&')) return source;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in _entityPattern.allMatches(source)) {
      if (match.start > cursor) {
        buffer.write(source.substring(cursor, match.start));
      }
      buffer.write(_decodeEntity(match.group(0)!));
      cursor = match.end;
    }
    if (cursor < source.length) buffer.write(source.substring(cursor));
    return buffer.toString();
  }

  String _decodeEntity(String entity) {
    if (entity.length < 3 || !entity.endsWith(';')) return entity;
    final body = entity.substring(1, entity.length - 1);
    if (body.startsWith('#')) {
      final isHex = body.length > 2 && (body[1] == 'x' || body[1] == 'X');
      final digits = isHex
          ? (body.length > 2 ? body.substring(2) : '')
          : (body.length > 1 ? body.substring(1) : '');
      final code = int.tryParse(digits, radix: isHex ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10FFFF) return entity;
      return String.fromCharCodes([code]);
    }
    return _htmlEntities[body] ?? _htmlEntities[body.toLowerCase()] ?? entity;
  }

  /// Chapter-title pattern for Chinese TXT novels.
  ///
  /// Mirrors Fanqie's `ar5/a.java` regex (第 + 中文/阿拉伯数字 + 册卷部章节回节/回合),
  /// with the quantifier character-class fixed so `|` is not treated as a
  /// literal. Anchored to the paragraph line; callers still reject long lines
  /// and lines that look like body prose.
  static final chapterPattern = RegExp(
    r'^\s*.{0,24}第[0-9一二三四五六七八九十百千万零〇两壹贰叁肆伍陆柒捌玖拾]*'
    r'(章节|章|册|卷|部|回|节|回合|集|篇).*$',
  );

  /// Max title length accepted when scanning TXT paragraphs for chapters
  /// (Fanqie uses 30; slightly relaxed for real-world titles like
  /// 「第xxx章 章节标题」).
  static const int maxChapterTitleLength = 40;

  /// Byte window used when sniffing UTF-8 validity before falling back to GBK
  /// (Fanqie samples a large window; 64 KiB is a good balance for TXT novels).

  /// Three-stage plain-text decode, following Fanqie's encoding sniff:
  /// BOM → UTF-8 validity probe → GBK fallback.
  ///
  /// Chinese novel TXT files are very often GBK/GB18030; decoding them as
  /// UTF-8 with `allowMalformed: false` throws and the import fails outright.
  String decodePlainText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _sanitizePlainText(_decodeUtf16(bytes.sublist(2), Endian.little));
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _sanitizePlainText(_decodeUtf16(bytes.sublist(2), Endian.big));
    }
    final content =
        bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? bytes.sublist(3)
        : bytes;

    if (_looksLikeUtf8(content)) {
      try {
        return _sanitizePlainText(utf8.decode(content, allowMalformed: false));
      } on FormatException {
        // Rare: probe passed but a later byte is invalid — fall through to GBK.
      }
    }
    try {
      return _sanitizePlainText(gbk.decode(content, allowMalformed: true));
    } catch (_) {
      return _sanitizePlainText(utf8.decode(content, allowMalformed: true));
    }
  }

  /// UTF-8 multi-byte validity probe over a bounded window.
  ///
  /// Follows Fanqie's shape: a lead byte in 0xC0–0xDF must be followed by one
  /// continuation byte, 0xE0–0xEF by two. Control bytes above 0xF4 are treated
  /// as non-UTF-8 so GB18030/GBK payloads fall through to the GBK decoder.
  bool _looksLikeUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Strips BOM residue and ideographic spaces that break chapter matching and
  /// paragraph splitting (Fanqie's `pt5.h.e` does the same).
  String _sanitizePlainText(String text) =>
      text.replaceAll('﻿', '').replaceAll('　', ' ');

  /// Detects chapter headings in decoded plain paragraphs (TXT import path).
  ///
  /// When no heading is recognised, synthesises `第N章` blocks roughly every
  /// [syntheticChapterParagraphs] paragraphs — Fanqie's fallback when a TXT
  /// has no titles at all (it splits every ~5000 bytes).
  List<BookTocEntry> detectTxtChapters(
    List<String> paragraphs, {
    int syntheticChapterParagraphs = 30,
  }) {
    final entries = <BookTocEntry>[];
    for (var index = 0; index < paragraphs.length; index++) {
      final value = chapterTitle(paragraphs[index]);
      if (value.isEmpty || value.length > maxChapterTitleLength) continue;
      // Reject body prose that happens to start with 第…章.
      if (value.contains('。') ||
          value.contains('，') ||
          value.contains(',') ||
          value.contains('！') ||
          value.contains('？')) {
        continue;
      }
      if (chapterPattern.hasMatch(value)) {
        entries.add(BookTocEntry(title: value, paragraphIndex: index));
      }
    }
    if (entries.isNotEmpty) return entries;

    if (paragraphs.isEmpty) return const [];
    final synthetic = <BookTocEntry>[];
    final stride = syntheticChapterParagraphs < 1
        ? 1
        : syntheticChapterParagraphs;
    for (var index = 0; index < paragraphs.length; index += stride) {
      final chapterNo = index ~/ stride + 1;
      synthetic.add(BookTocEntry(title: '第$chapterNo章', paragraphIndex: index));
    }
    return synthetic;
  }

  String _decodeUtf16(List<int> bytes, Endian endian) {
    final units = <int>[];
    final data = ByteData.sublistView(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(data.getUint16(index, endian));
    }
    return String.fromCharCodes(units);
  }

  List<String> splitParagraphs(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(_paragraphBreak)
        .map(
          (paragraph) => normalizeReaderMarkup(
            paragraph.replaceAll(_whitespaceRun, ' ').trim(),
          ),
        )
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
  }

  String normalizeReaderMarkup(String paragraph) {
    if (!_markupHint.hasMatch(paragraph)) return paragraph.trim();
    if (_looksMarkdown.hasMatch(paragraph)) {
      final parsed = markdown.markdownToHtml(paragraph);
      if (parsed.isNotEmpty) {
        final semanticText = htmlToText(
          parsed,
        ).replaceAll(_whitespaceRun, ' ').trim();
        return semanticText.replaceAllMapped(
          _markupTagSpacing,
          (match) => match.group(1)!,
        );
      }
    }
    var value = paragraph;
    final heading = _headingPrefix.firstMatch(value);
    if (heading != null) {
      value =
          '[[vellum-heading:${heading.group(1)!.length}]]'
          '${value.substring(heading.end)}';
    } else if (value.startsWith('>')) {
      value = '[[vellum-quote]]${value.substring(1).trimLeft()}';
    } else if (_listPrefix.hasMatch(value)) {
      value = '[[vellum-list]]${value.replaceFirst(_listPrefix, '')}';
    }
    value = value
        .replaceAll(_quoteRun, '[[vellum-quote]]')
        .replaceAll(_listRun, '[[vellum-list]]')
        .replaceAllMapped(_markdownLink, (match) => match.group(1) ?? '')
        .replaceAllMapped(
          _boldItalicStar,
          (match) => '[[b]][[i]]${match.group(1)!}[[/i]][[/b]]',
        )
        .replaceAllMapped(_boldStar, (match) => '[[b]]${match.group(1)!}[[/b]]')
        .replaceAllMapped(
          _italicStar,
          (match) => '[[i]]${match.group(1)!}[[/i]]',
        )
        .replaceAllMapped(
          _boldItalicUnder,
          (match) => '[[b]][[i]]${match.group(1)!}[[/i]][[/b]]',
        )
        .replaceAllMapped(
          _boldUnder,
          (match) => '[[b]]${match.group(1)!}[[/b]]',
        )
        .replaceAllMapped(
          _italicUnder,
          (match) => '[[i]]${match.group(1)!}[[/i]]',
        )
        .replaceAllMapped(_codeSpan, (match) => match.group(1) ?? '');
    return value.trim();
  }

  /// Plain text for a chapter label coming from NCX, an EPUB nav document or a
  /// MOBI `filepos` anchor.
  ///
  /// Labels are hand-written metadata in the source file, so they regularly
  /// arrive dirty: escaped markup (`&lt;b&gt;`), a tag that never closes
  /// (`<font color="red"`), or the reader's own `[[…]]` markers when a heading
  /// element went through [htmlToText]. None of that belongs in a table of
  /// contents, so it is cleaned here instead of at every call site.
  String chapterTitle(String source) {
    if (!source.contains('<') &&
        !source.contains('&') &&
        !source.contains('[[')) {
      return source.trim();
    }
    var value = source.contains('&') ? decodeHtmlEntities(source) : source;
    if (value.contains('<')) {
      // Decoding first turns `&lt;b&gt;` into a real tag so both shapes are
      // swept. This is plain text surgery on purpose: the HTML parser drops an
      // unterminated tag *together with the text after it*, which is exactly
      // the label we want to keep. Complete tags go first, then the runs that
      // never reach their `>`.
      value = value.replaceAll(_anyTag, ' ').replaceAll(_danglingTag, ' ');
    }
    if (value.contains('[[')) value = value.replaceAll(_readerMarker, ' ');
    return value.replaceAll(_whitespaceRun, ' ').trim();
  }

  String titleFromFilename(String filename) {
    final separator = filename.lastIndexOf('.');
    return separator > 0 ? filename.substring(0, separator) : filename;
  }
}
