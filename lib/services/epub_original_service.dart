import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// Book-authored documents receive a different policy from the trusted viewer.
const epubContentPolicy =
    "default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; media-src 'self'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";

String sanitizeEpubDocument(String source) {
  XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } on XmlException {
    final parsed = html_parser.parse(source);
    // Tolerate legacy HTML without serializing void tags back as invalid XML.
    // Preserve prefixed attribute names and xmlns declarations for EPUB.js.
    document = XmlDocument([_htmlToXml(parsed.documentElement!)]);
  }
  for (final node in document.descendants.whereType<XmlElement>().toList()) {
    final tag = node.name.local.toLowerCase();
    if (const {
          'script',
          'iframe',
          'object',
          'embed',
          'base',
          'form',
          'foreignobject',
        }.contains(tag) ||
        (tag == 'meta' && node.getAttribute('http-equiv') != null)) {
      node.parent?.children.remove(node);
      continue;
    }
    node.attributes.removeWhere((attribute) {
      final key = attribute.name.local.toLowerCase();
      final value = attribute.value.trim().toLowerCase();
      return key.startsWith('on') ||
          key == 'srcdoc' ||
          ((key == 'href' || key == 'src' || key == 'action') &&
              (value.startsWith('javascript:') ||
                  value.startsWith('vbscript:') ||
                  value.startsWith('http:') ||
                  value.startsWith('https:') ||
                  value.startsWith('//') ||
                  value.startsWith('file:')));
    });
  }
  return document.toXmlString();
}

XmlElement _htmlToXml(html.Element element) => XmlElement(
  XmlName.fromString(element.localName ?? 'span'),
  [
    for (final entry in element.attributes.entries)
      XmlAttribute(XmlName.fromString(entry.key.toString()), entry.value),
  ],
  [
    for (final child in element.nodes)
      if (child is html.Element)
        _htmlToXml(child)
      else if (child is html.Text)
        XmlText(child.data),
  ],
);

/// Reject traversal, absolute paths, Windows aliases and duplicate ZIP paths.
String safeEpubPath(String name) {
  if (name.isEmpty ||
      name.contains('\\') ||
      name.contains(':') ||
      name.startsWith('/') ||
      name.contains('\u0000')) {
    throw const FormatException('EPUB 包含非法资源路径');
  }
  final parts = name.split('/');
  if (parts.any(
    (part) =>
        part == '..' || part == '.' || part.endsWith('.') || part.endsWith(' '),
  )) {
    throw const FormatException('EPUB 包含非法资源路径');
  }
  return name;
}

Map<String, dynamic> _extractEpub(String sourcePath, String destination) {
  final input = InputFileStream(sourcePath);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    if (archive.length > 20000) throw const FormatException('EPUB 资源数量超过限制');
    var total = 0;
    final paths = <String>{};
    for (final entry in archive) {
      final name = safeEpubPath(entry.name);
      if (!paths.add(name.toLowerCase()))
        throw const FormatException('EPUB 资源路径重复');
      if (entry.isSymbolicLink) throw const FormatException('EPUB 不支持符号链接');
      if (!entry.isFile) continue;
      total += entry.size;
      if (entry.size > 64 * 1024 * 1024 || total > 512 * 1024 * 1024) {
        throw const FormatException('EPUB 解压资源超过限制');
      }
      final file = File('$destination/$name');
      file.parent.createSync(recursive: true);
      final output = OutputFileStream(file.path);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
      if (file.lengthSync() != entry.size)
        throw const FormatException('EPUB 资源长度损坏');
      final lower = name.toLowerCase();
      if (lower.endsWith('.xhtml') ||
          lower.endsWith('.html') ||
          lower.endsWith('.htm') ||
          lower.endsWith('.svg')) {
        if (entry.size > 16 * 1024 * 1024)
          throw const FormatException('EPUB 单章正文超过安全预算');
        file.writeAsStringSync(sanitizeEpubDocument(file.readAsStringSync()));
      }
    }
    final container = XmlDocument.parse(
      File('$destination/META-INF/container.xml').readAsStringSync(),
    );
    final root = container.descendants.whereType<XmlElement>().firstWhere(
      (e) => e.name.local == 'rootfile',
    );
    final package = safeEpubPath(root.getAttribute('full-path') ?? '');
    if (!File('$destination/$package').existsSync())
      throw const FormatException('EPUB 缺少书籍目录');
    final opf = XmlDocument.parse(
      File('$destination/$package').readAsStringSync(),
    );
    final items = <String, String>{
      for (final item in opf.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'item',
      ))
        if (item.getAttribute('id') != null &&
            item.getAttribute('href') != null)
          item.getAttribute('id')!: item.getAttribute('href')!,
    };
    final anchors = <String, int>{};
    var index = 0;
    for (final ref in opf.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'itemref',
    )) {
      final href = items[ref.getAttribute('idref')];
      if (href != null) {
        final resource = Uri(path: package).resolve(href);
        if (resource.hasScheme || resource.hasAuthority)
          throw const FormatException('EPUB 目录引用外部资源');
        final file = File(
          '$destination/${safeEpubPath(Uri.decodeComponent(resource.path))}',
        );
        if (file.existsSync()) {
          final document = XmlDocument.parse(file.readAsStringSync());
          for (final element in document.descendants.whereType<XmlElement>()) {
            if (const {
              'p',
              'li',
              'h1',
              'h2',
              'h3',
              'h4',
              'h5',
              'h6',
              'td',
              'blockquote',
            }.contains(element.name.local)) {
              final text = element.innerText.replaceAll(RegExp(r'\s+'), '');
              if (text.isNotEmpty)
                anchors.putIfAbsent(
                  String.fromCharCodes(text.runes.take(80)),
                  () => index,
                );
            }
          }
        }
      }
      index++;
    }
    return {'package': package, 'anchors': anchors};
  } finally {
    input.closeSync();
  }
}

class EpubOriginalServer {
  EpubOriginalServer._(
    this._server,
    this._directory,
    this._token,
    this.packagePath,
    this.spineAnchors,
  );
  final HttpServer _server;
  final Directory _directory;
  final String _token;
  final String packagePath;
  final Map<String, int> spineAnchors;
  Uri get viewerUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/$_token/index.html');
  Uri get packageUri => viewerUri.resolve('book/$packagePath');
  bool owns(Uri uri) =>
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == _server.port &&
      uri.path.startsWith('/$_token/');

  static Future<EpubOriginalServer> start(
    String sourcePath, {
    Map<String, Uint8List>? assets,
  }) async {
    final directory = await Directory.systemTemp.createTemp('vellum_epub_');
    HttpServer? server;
    try {
      final package = await Isolate.run(
        () => _extractEpub(sourcePath, directory.path),
      );
      final loaded =
          assets ??
          <String, Uint8List>{
            for (final name in ['index.html', 'reader.js', 'epub.min.js'])
              name: (await rootBundle.load(
                'assets/epub_reader/$name',
              )).buffer.asUint8List(),
          };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final token = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final result = EpubOriginalServer._(
        server,
        directory,
        token,
        package['package'] as String,
        package['anchors'] as Map<String, int>,
      );
      server.listen((request) async {
        try {
          final prefix = '/$token/';
          if (!request.uri.path.startsWith(prefix) || request.method != 'GET') {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            final name = Uri.decodeComponent(
              request.uri.path.substring(prefix.length),
            );
            request.response.headers.set('Cache-Control', 'no-store');
            request.response.headers.set('X-Content-Type-Options', 'nosniff');
            request.response.headers.set(
              'Content-Security-Policy',
              name.startsWith('book/')
                  ? epubContentPolicy
                  : "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; frame-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'",
            );
            if (loaded.containsKey(name)) {
              request.response.headers.set(
                'Content-Type',
                name.endsWith('.js')
                    ? 'application/javascript; charset=utf-8'
                    : 'text/html; charset=utf-8',
              );
              request.response.add(loaded[name]!);
            } else if (name.startsWith('book/')) {
              final relative = safeEpubPath(name.substring(5));
              final file = File('${directory.path}/$relative');
              if (!await file.exists()) {
                request.response.statusCode = HttpStatus.notFound;
              } else {
                request.response.headers.set('Content-Type', _mime(relative));
                await request.response.addStream(file.openRead());
              }
            } else {
              request.response.statusCode = HttpStatus.notFound;
            }
          }
        } catch (_) {
          request.response.statusCode = HttpStatus.badRequest;
        } finally {
          await request.response.close();
        }
      });
      return result;
    } catch (_) {
      await server?.close(force: true);
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}

String _mime(String name) {
  final extension = name.split('.').last.toLowerCase();
  return const {
        'xhtml': 'application/xhtml+xml; charset=utf-8',
        'html': 'text/html; charset=utf-8',
        'htm': 'text/html; charset=utf-8',
        'opf': 'application/xml; charset=utf-8',
        'xml': 'application/xml; charset=utf-8',
        'ncx': 'application/xml; charset=utf-8',
        'css': 'text/css; charset=utf-8',
        'svg': 'image/svg+xml',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'woff': 'font/woff',
        'woff2': 'font/woff2',
        'ttf': 'font/ttf',
        'otf': 'font/otf',
      }[extension] ??
      'application/octet-stream';
}

/// Sidecar lives beside the source, so library backups include it unchanged.
class EpubOriginalStateStore {
  EpubOriginalStateStore(this.originalPath);
  final String originalPath;
  Future<Map<String, dynamic>> load() async {
    final file = File('$originalPath.reader.json');
    if (!await file.exists()) return {};
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> save(Map<String, dynamic> state) async {
    final file = File('$originalPath.reader.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(file.path);
  }

  static Future<String> preferredMode(String path) async =>
      (await EpubOriginalStateStore(path).load())['mode'] as String? ??
      'original';
  static Future<void> setPreferredMode(String path, String mode) async {
    final store = EpubOriginalStateStore(path);
    final state = await store.load();
    state['mode'] = mode;
    await store.save(state);
  }
}
