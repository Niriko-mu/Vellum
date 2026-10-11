import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import 'book_models.dart';
import 'html_text_pipeline.dart';

class EpubDecoder {
  const EpubDecoder({this.pipeline = const HtmlTextPipeline()});

  final HtmlTextPipeline pipeline;

  ImportedBook decode(String filename, Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      var expandedBytes = 0;
      if (archive.length > 20000) {
        throw const BookImportException('EPUB 包含过多文件。');
      }
      for (final entry in archive) {
        expandedBytes += entry.size;
        if (entry.size > 64 * 1024 * 1024 ||
            expandedBytes > 256 * 1024 * 1024) {
          throw const BookImportException('EPUB 解压后超过安全大小。');
        }
      }
      final container = fileText(archive, 'META-INF/container.xml');
      final containerXml = XmlDocument.parse(container);
      final rootfiles = _elements(containerXml, 'rootfile');
      final packagePath = rootfiles.isEmpty
          ? null
          : rootfiles.first.getAttribute('full-path');
      if (packagePath == null) {
        throw const BookImportException('EPUB 缺少 OPF 书籍目录。');
      }
      final opf = fileText(archive, packagePath);
      final opfXml = XmlDocument.parse(opf);
      final titles = _elements(opfXml, 'title');
      final creators = _elements(opfXml, 'creator');
      final title = titles.isEmpty
          ? pipeline.titleFromFilename(filename)
          : pipeline.chapterTitle(titles.first.innerText);
      // Fanqie's EpubMetaData carries mCreator; without it the shelf has no
      // author line to show.
      final author = _cleanMeta(
        creators.isEmpty ? '' : creators.first.innerText,
      );
      final manifest = <String, _ManifestItem>{};
      for (final item in _elements(opfXml, 'item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id == null || href == null) continue;
        manifest[id] = _ManifestItem(
          href: href,
          mediaType: item.getAttribute('media-type') ?? '',
          properties: item.getAttribute('properties') ?? '',
        );
      }
      final slash = packagePath.lastIndexOf('/');
      final opfDir = slash < 0 ? '' : packagePath.substring(0, slash + 1);

      // Cover: Fanqie extracts one via TTEPubParser.b(path). EPUB declares it
      // three common ways — try them in order of certainty.
      final coverBytes = _extractCover(
        archive: archive,
        opf: opf,
        opfDir: opfDir,
        manifest: manifest,
      );

      final contents = <_SpineDocument>[];
      final imageByIndex = <int, String>{};
      var nextImageIndex = 1;
      for (final ref in _elements(opfXml, 'itemref')) {
        final id = ref.getAttribute('idref');
        final item = id == null ? null : manifest[id];
        if (item == null) continue;
        final href = _normalizePath(opfDir, item.href);
        if (href == null) continue;
        if ((archive.findFile(href)?.size ?? 0) > 16 * 1024 * 1024) {
          throw const BookImportException('EPUB 单章正文超过安全大小。');
        }
        final raw = _tryFileText(archive, href);
        if (raw == null) continue;
        // Rewrite <img src="…"> to recindex so the shared HTML pipeline
        // records image anchors; the archive bytes are resolved below.
        final docDir = _dirOf(href);
        final rewritten = raw.replaceAllMapped(
          RegExp(
            r'''<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>''',
            caseSensitive: false,
          ),
          (img) {
            final src = img.group(1)!.trim();
            if (src.isEmpty || src.startsWith('data:')) return img.group(0)!;
            final resolved = _normalizePath(docDir, src);
            if (resolved == null) return img.group(0)!;
            final index = nextImageIndex++;
            imageByIndex[index] = resolved;
            return '<img recindex="$index">';
          },
        );
        contents.add(
          _SpineDocument(
            path: href,
            content: pipeline.convert(rewritten, href),
          ),
        );
      }
      if (contents.isEmpty) {
        throw const BookImportException('EPUB 中没有可阅读的正文。');
      }

      final paragraphs = <String>[];
      final anchors = <String, int>{};
      final documentStart = <String, int>{};
      final unresolvedLinks = <int, String>{};
      final paragraphImages = <int, int>{};
      for (final doc in contents) {
        final offset = paragraphs.length;
        documentStart[doc.path] = offset;
        paragraphs.addAll(doc.content.paragraphs);
        for (final entry in doc.content.anchors.entries) {
          anchors[entry.key] = offset + entry.value;
        }
        for (final entry in doc.content.links.entries) {
          unresolvedLinks[offset + entry.key] = entry.value;
        }
        for (final entry in doc.content.images.entries) {
          paragraphImages[offset + entry.key] = entry.value;
        }
      }
      final linkTargets = <int, int>{
        for (final entry in unresolvedLinks.entries)
          if (anchors[entry.value] != null) entry.key: anchors[entry.value]!,
      };
      if (paragraphs.isEmpty) {
        throw const BookImportException('EPUB 中没有可阅读的正文。');
      }

      final imageBytes = <int, Uint8List>{};
      for (final entry in paragraphImages.entries) {
        final path = imageByIndex[entry.value];
        if (path == null) continue;
        final file = archive.findFile(path);
        final data = file?.readBytes();
        if (data == null || data.isEmpty) continue;
        if (!_looksLikeImage(data)) continue;
        imageBytes[entry.key] = Uint8List.fromList(data);
      }

      final tocEntries = _parseToc(
        archive: archive,
        packagePath: packagePath,
        opf: opf,
        opfDir: opfDir,
        manifest: manifest,
        anchors: anchors,
        documentStart: documentStart,
        paragraphs: paragraphs,
      );

      return ImportedBook(
        title: title,
        author: author,
        format: BookFormat.epub,
        paragraphs: paragraphs,
        coverBytes: coverBytes,
        linkTargets: linkTargets,
        tocEntries: tocEntries,
        imageBytes: imageBytes,
      );
    } on BookImportException {
      rethrow;
    } catch (_) {
      throw const BookImportException('无法读取此 EPUB 文件。');
    }
  }

  String _cleanMeta(String value) {
    final cleaned = pipeline.chapterTitle(value);
    if (cleaned.isEmpty) return '';
    // Strip role suffixes some producers append: "作者 (Author)" → "作者".
    final paren = cleaned.indexOf('(');
    if (paren > 1 && cleaned.endsWith(')')) {
      return cleaned.substring(0, paren).trim();
    }
    return cleaned;
  }

  Iterable<XmlElement> _elements(XmlDocument document, String localName) =>
      document.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == localName,
      );

  Uint8List? _extractCover({
    required Archive archive,
    required String opf,
    required String opfDir,
    required Map<String, _ManifestItem> manifest,
  }) {
    // 1) <meta name="cover" content="manifest-id"/> (EPUB2 convention)
    final coverMeta = _elements(
      XmlDocument.parse(opf),
      'meta',
    ).where((item) => item.getAttribute('name') == 'cover');
    final metaCoverId = coverMeta.isEmpty
        ? null
        : coverMeta.first.getAttribute('content');
    // 2) manifest properties="cover-image" (EPUB3)
    String? propertiesHref;
    String? firstImageHref;
    for (final item in manifest.values) {
      final props = item.properties.toLowerCase().split(RegExp(r'\s+'));
      if (props.contains('cover-image')) {
        propertiesHref = item.href;
      }
      if (firstImageHref == null &&
          item.mediaType.toLowerCase().startsWith('image/')) {
        firstImageHref = item.href;
      }
    }
    final candidates = <String?>[
      manifest[metaCoverId]?.href,
      propertiesHref,
      // href heuristic: a file named cover.*
      for (final item in manifest.values)
        if (item.mediaType.toLowerCase().startsWith('image/') &&
            RegExp(r'cover', caseSensitive: false).hasMatch(item.href))
          item.href,
      firstImageHref,
    ];
    for (final href in candidates) {
      if (href == null) continue;
      final path = _normalizePath(opfDir, href);
      if (path == null) continue;
      final file = archive.findFile(path);
      final data = file?.readBytes();
      if (data == null || data.isEmpty) continue;
      if (!_looksLikeImage(data)) continue;
      return Uint8List.fromList(data);
    }
    return null;
  }

  bool _looksLikeImage(List<int> data) {
    if (data.length < 4) return false;
    // JPEG
    if (data[0] == 0xff && data[1] == 0xd8) return true;
    // PNG
    if (data[0] == 0x89 && data[1] == 0x50) return true;
    // GIF
    if (data[0] == 0x47 && data[1] == 0x49) return true;
    // WEBP (RIFF....WEBP)
    if (data.length >= 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[8] == 0x57 &&
        data[9] == 0x45) {
      return true;
    }
    return false;
  }

  List<BookTocEntry> _parseToc({
    required Archive archive,
    required String packagePath,
    required String opf,
    required String opfDir,
    required Map<String, _ManifestItem> manifest,
    required Map<String, int> anchors,
    required Map<String, int> documentStart,
    required List<String> paragraphs,
  }) {
    final raw = <_RawTocItem>[];

    final ncxPath = _findNcxPath(opf, opfDir, manifest);
    if (ncxPath != null) {
      final ncx = _tryFileText(archive, ncxPath);
      if (ncx != null) raw.addAll(_parseNcx(ncx, ncxPath));
    }

    if (raw.isEmpty) {
      final navPath = _findNavPath(opfDir, manifest);
      if (navPath != null) {
        final nav = _tryFileText(archive, navPath);
        if (nav != null) raw.addAll(_parseNav(nav, navPath));
      }
    }

    return _mapTocItems(
      raw,
      anchors: anchors,
      documentStart: documentStart,
      paragraphs: paragraphs,
    );
  }

  String? _findNcxPath(
    String opf,
    String opfDir,
    Map<String, _ManifestItem> manifest,
  ) {
    final spines = _elements(XmlDocument.parse(opf), 'spine');
    final spineToc = spines.isEmpty ? null : spines.first.getAttribute('toc');
    if (spineToc != null && manifest[spineToc] != null) {
      return _normalizePath(opfDir, manifest[spineToc]!.href);
    }
    for (final item in manifest.values) {
      if (item.mediaType.toLowerCase().contains('dtbncx')) {
        return _normalizePath(opfDir, item.href);
      }
    }
    for (final item in manifest.values) {
      if (item.href.toLowerCase().endsWith('.ncx')) {
        return _normalizePath(opfDir, item.href);
      }
    }
    return null;
  }

  String? _findNavPath(String opfDir, Map<String, _ManifestItem> manifest) {
    for (final item in manifest.values) {
      if (item.properties.toLowerCase().split(RegExp(r'\s+')).contains('nav')) {
        return _normalizePath(opfDir, item.href);
      }
    }
    return null;
  }

  List<_RawTocItem> _parseNcx(String source, String ncxPath) {
    final dir = _dirOf(ncxPath);
    final items = <_RawTocItem>[];
    // A few generators put dangling HTML tags inside NCX text. Sanitize each
    // label once before XML parsing, preserving the tolerant historical path.
    final cleanSource = source.replaceAllMapped(
      RegExp(r'<text\b[^>]*>([\s\S]*?)</text\s*>', caseSensitive: false),
      (match) =>
          '<text>${pipeline.chapterTitle(match.group(1)!).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</text>',
    );
    final document = XmlDocument.parse(cleanSource);
    for (final point in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'navPoint',
    )) {
      final label = point.childElements
          .where((e) => e.name.local == 'navLabel')
          .firstOrNull;
      final content = point.childElements
          .where((e) => e.name.local == 'content')
          .firstOrNull;
      final src = content?.getAttribute('src')?.trim();
      final title = pipeline.chapterTitle(label?.innerText ?? '');
      if (src == null || src.isEmpty || title.isEmpty) continue;
      items.add(_RawTocItem(title: title, href: src, baseDir: dir));
    }
    return items;
  }

  List<_RawTocItem> _parseNav(String source, String navPath) {
    final dir = _dirOf(navPath);
    final items = <_RawTocItem>[];
    final fragment = html_parser.parseFragment(source);
    dom.Element? tocRoot;
    for (final node in fragment.nodes.whereType<dom.Element>()) {
      if (node.localName?.toLowerCase() != 'nav') continue;
      final type =
          (node.attributes['epub:type'] ?? node.attributes['type'] ?? '')
              .toLowerCase();
      if (type.contains('toc') || tocRoot == null) {
        tocRoot = node;
        if (type.contains('toc')) break;
      }
    }
    tocRoot ??= fragment.querySelector('nav');
    if (tocRoot == null) return items;
    for (final anchor in tocRoot.querySelectorAll('a')) {
      final href = anchor.attributes['href']?.trim();
      final title = pipeline.chapterTitle(anchor.text);
      if (href == null || href.isEmpty || title.isEmpty) continue;
      items.add(_RawTocItem(title: title, href: href, baseDir: dir));
    }
    return items;
  }

  List<BookTocEntry> _mapTocItems(
    List<_RawTocItem> items, {
    required Map<String, int> anchors,
    required Map<String, int> documentStart,
    required List<String> paragraphs,
  }) {
    final entries = <BookTocEntry>[];
    final seen = <int>{};
    for (final item in items) {
      final index = _resolveParagraphIndex(
        item,
        anchors: anchors,
        documentStart: documentStart,
      );
      if (index == null) continue;
      final clamped = index.clamp(0, paragraphs.length - 1);
      if (!seen.add(clamped)) continue;
      entries.add(BookTocEntry(title: item.title, paragraphIndex: clamped));
    }
    entries.sort((a, b) => a.paragraphIndex.compareTo(b.paragraphIndex));
    return entries;
  }

  int? _resolveParagraphIndex(
    _RawTocItem item, {
    required Map<String, int> anchors,
    required Map<String, int> documentStart,
  }) {
    final resolved = _resolveHref(item.baseDir, item.href);
    if (resolved == null) return null;
    final exact = anchors[resolved];
    if (exact != null) return exact;

    final hash = resolved.indexOf('#');
    final path = hash < 0 ? resolved : resolved.substring(0, hash);
    final fragment = hash < 0 ? '' : resolved.substring(hash + 1);

    if (fragment.isNotEmpty) {
      // Some generators rewrite ids; try a suffix match on the fragment.
      for (final entry in anchors.entries) {
        if (entry.key.endsWith('#$fragment')) return entry.value;
      }
    }

    final start = documentStart[path];
    if (start != null) return start;

    // Last resort: match by file name only (OPF hrefs sometimes differ by ./).
    final fileName = path.split('/').last;
    for (final entry in documentStart.entries) {
      if (entry.key.split('/').last == fileName) return entry.value;
    }
    return null;
  }

  String? _resolveHref(String baseDir, String href) {
    var value = href.trim();
    if (value.isEmpty) return null;
    // Strip query; keep fragment.
    final query = value.indexOf('?');
    if (query >= 0) value = value.substring(0, query);
    if (value.startsWith('#')) {
      return baseDir.isEmpty ? value : '$baseDir$value';
    }
    return _normalizePath(baseDir, value);
  }

  String? _normalizePath(String baseDir, String href) {
    var value = href.trim();
    if (value.isEmpty) return null;
    // Decode common percent-escapes used in OPF hrefs.
    value = _decodeEntities(Uri.decodeFull(value));
    final hash = value.indexOf('#');
    final fragment = hash < 0 ? '' : value.substring(hash);
    var path = hash < 0 ? value : value.substring(0, hash);
    if (path.contains('://')) return null;
    final combined = path.startsWith('/') ? path.substring(1) : '$baseDir$path';
    final parts = <String>[];
    for (final segment in combined.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.isEmpty ? null : '${parts.join('/')}$fragment';
  }

  String _dirOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash + 1);
  }

  String _decodeEntities(String source) {
    if (!source.contains('&')) return source;
    return source
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  String? _tryFileText(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null || !file.isFile) return null;
    try {
      return utf8.decode(file.readBytes()!, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  String fileText(Archive archive, String name) {
    final text = _tryFileText(archive, name);
    if (text == null) {
      throw BookImportException('EPUB 缺少文件：$name');
    }
    return text;
  }

  String? attribute(String source, String tag, String attribute) {
    final match = RegExp(
      '<$tag\\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(source);
    return match == null ? null : attributeInTag(match.group(0)!, attribute);
  }

  String? attributeInTag(String tag, String attribute) => RegExp(
    '$attribute\\s*=\\s*["\\\']([^"\\\']+)["\\\']',
    caseSensitive: false,
  ).firstMatch(tag)?.group(1);

  String? elementText(String source, String tag) => RegExp(
    '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(source)?.group(1)?.trim();
}

class _ManifestItem {
  const _ManifestItem({
    required this.href,
    required this.mediaType,
    required this.properties,
  });
  final String href;
  final String mediaType;
  final String properties;
}

class _SpineDocument {
  const _SpineDocument({required this.path, required this.content});
  final String path;
  final HtmlContent content;
}

class _RawTocItem {
  const _RawTocItem({
    required this.title,
    required this.href,
    required this.baseDir,
  });
  final String title;
  final String href;
  final String baseDir;
}
