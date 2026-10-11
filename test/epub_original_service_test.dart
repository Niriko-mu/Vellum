import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/epub_original_service.dart';

void main() {
  test(
    'legacy non-XML HTML is converted without losing local styling or namespace attributes',
    () {
      final clean = sanitizeEpubDocument(
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><link href="local.css"></head><body><p epub:type="chapter">正文<br>第二行<img src="image.png"><script>alert(1)</script></body></html>',
      );
      expect(clean, contains('xmlns:epub='));
      expect(clean, contains('epub:type="chapter"'));
      expect(clean, contains('local.css'));
      expect(clean, contains('image.png'));
      expect(clean, isNot(contains('alert')));
    },
  );
  test(
    'unsafe archives fail before a resource can escape the staging root',
    () async {
      final temp = await Directory.systemTemp.createTemp('unsafe_epub_');
      try {
        final archive = Archive()
          ..addFile(
            ArchiveFile.bytes('../escape.xhtml', utf8.encode('<html/>')),
          );
        final source = File('${temp.path}/unsafe.epub');
        await source.writeAsBytes(ZipEncoder().encode(archive));
        await expectLater(
          EpubOriginalServer.start(source.path, assets: {}),
          throwsFormatException,
        );
        expect(await File('${temp.path}/escape.xhtml').exists(), isFalse);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'sanitization keeps layout and local resources but removes executable content',
    () {
      final clean = sanitizeEpubDocument(
        '''<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="styles.css"/><style>table{border:1px solid}</style><script src="bad.js"/><meta http-equiv="refresh" content="0;url=https://example.com"/></head><body onload="alert(1)"><table><tr><td>中文😀</td></tr></table><img src="picture.png"/><a href="chapter.xhtml#target">下一章</a><a href="javascript:alert(1)">bad</a><iframe src="https://example.com"/></body></html>''',
      );
      expect(clean, contains('<table>'));
      expect(clean, contains('styles.css'));
      expect(clean, contains('picture.png'));
      expect(clean, contains('chapter.xhtml#target'));
      expect(clean, isNot(contains('script')));
      expect(clean, isNot(contains('onload')));
      expect(clean, isNot(contains('http-equiv')));
      expect(clean, isNot(contains('iframe')));
    },
  );

  test('reject unsafe archive paths', () {
    for (final path in [
      '../escape',
      '/absolute',
      'C:/file',
      r'a\b',
      'a/../b',
      'a/./b',
      'trailing.',
    ]) {
      expect(() => safeEpubPath(path), throwsFormatException);
    }
    expect(safeEpubPath('OPS/中文.xhtml'), 'OPS/中文.xhtml');
  });

  test(
    'server isolates resource URLs, returns sanitized XHTML and retains font and OPF layout',
    () async {
      final temp = await Directory.systemTemp.createTemp('original_test_');
      final archive = Archive();
      final files = {
        'META-INF/container.xml':
            '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        'OPS/book.opf':
            '<package><metadata><meta property="rendition:layout">pre-paginated</meta></metadata><manifest><item id="c" href="中文.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>',
        'OPS/中文.xhtml':
            '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>@font-face{font-family:book;src:url(font.ttf)}</style></head><body><p>原书内容😀</p><script>alert(1)</script><a href="https://remote.test">remote</a></body></html>',
        'OPS/font.ttf': 'fake-font-test',
      };
      for (final entry in files.entries) {
        archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
      }
      final source = File('${temp.path}/book.epub');
      await source.writeAsBytes(ZipEncoder().encode(archive));
      final server = await EpubOriginalServer.start(
        source.path,
        assets: {
          'index.html': Uint8List.fromList(utf8.encode('<html>viewer</html>')),
        },
      );
      final client = HttpClient();
      try {
        expect(server.owns(server.packageUri), isTrue);
        expect(server.owns(Uri.parse('https://remote.test')), isFalse);
        expect(server.spineAnchors, containsPair('原书内容😀', 0));
        final response = await (await client.getUrl(
          server.packageUri.resolve('中文.xhtml'),
        )).close();
        expect(response.statusCode, 200);
        expect(
          response.headers.value('content-security-policy'),
          contains("script-src 'none'"),
        );
        final html = await utf8.decoder.bind(response).join();
        expect(html, contains('原书内容😀'));
        expect(html, contains('font.ttf'));
        expect(html, isNot(contains('alert')));
        expect(html, isNot(contains('remote.test')));
        final opf = await (await client.getUrl(server.packageUri)).close();
        expect(await utf8.decoder.bind(opf).join(), contains('pre-paginated'));
        final invalid = await (await client.getUrl(
          server.viewerUri.resolve('/wrong/index.html'),
        )).close();
        expect(invalid.statusCode, 404);
        await invalid.drain<void>();
      } finally {
        client.close(force: true);
        await server.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test('sidecar preserves CFI and marks across mode changes', () async {
    final temp = await Directory.systemTemp.createTemp('epub_state_test_');
    try {
      final path = '${temp.path}/book.original.epub';
      final store = EpubOriginalStateStore(path);
      expect(await EpubOriginalStateStore.preferredMode(path), 'original');
      await store.save({
        'cfi': 'epubcfi(/6/2!/4/2)',
        'notes': [
          {'cfi': 'epubcfi(/6/2!/4/4)'},
        ],
      });
      await EpubOriginalStateStore.setPreferredMode(path, 'reflow');
      final state = await store.load();
      expect(state['cfi'], 'epubcfi(/6/2!/4/2)');
      expect((state['notes'] as List).length, 1);
      expect(await EpubOriginalStateStore.preferredMode(path), 'reflow');
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
