// flutter run -d emulator-5554 -t tool/local_reader_device_probe.dart
// Uses real shelf books for migration and isolated fixtures for import. Restores
// the original shelf, preferences and writing/progress files in finally.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';
import 'package:vellum/pages/writing_editor_page.dart';
import 'package:vellum/reader/epub_original_reader_page.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_import_service.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/book_models.dart';
import 'package:vellum/services/book_search.dart';
import 'package:vellum/services/chunked_book_store.dart';
import 'package:vellum/services/lazy_paragraphs.dart';
import 'package:vellum/services/writing_library.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _Probe()));
}

String _digest(List<String> paragraphs) => sha256
    .convert(
      utf8.encode(
        [
          0,
          paragraphs.length ~/ 2,
          paragraphs.length - 1,
        ].map((i) => paragraphs[i]).join('\u0000'),
      ),
    )
    .toString();

Map<String, Object> _legacySample(String path) {
  final data =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final chunked = data['contentMode'] == 'chunked';
  final paragraphs = chunked
      ? ChunkedParagraphList(path, data)
      : (data['paragraphs'] as List).cast<String>();
  return {
    'count': paragraphs.length,
    'digest': _digest(paragraphs),
    'was_chunked': chunked,
  };
}

Future<List<String>> _fixtures(String root) async {
  final text = StringBuffer('<html><body>');
  for (var i = 0; i < 13485; i++) {
    if (i % 500 == 0) text.write('<h1>第${i ~/ 500 + 1}章 设备验收</h1>');
    if (i % 1000 == 0) text.write('<img recindex="1"/>');
    text.write('<p>设备正文第${i + 1}段，${'本地分块中文😀阅读。' * 10}</p>');
  }
  text.write('</body></html>');
  final body = utf8.encode(text.toString());
  final picture = image.Image(width: 2000, height: 2400);
  image.fill(picture, color: image.ColorRgb8(130, 165, 190));
  final png = image.encodePng(picture);
  final records = (body.length + 4095) ~/ 4096;
  final header = 78 + (records + 2) * 8;
  final start = header + 256;
  final bytes = Uint8List(start + body.length + png.length);
  final data = ByteData.sublistView(bytes);
  data.setUint16(76, records + 2);
  data.setUint32(78, header);
  for (var i = 0; i < records; i++)
    data.setUint32(86 + i * 8, start + i * 4096);
  data.setUint32(86 + records * 8, start + body.length);
  data.setUint16(header, 1);
  data.setUint32(header + 4, body.length);
  data.setUint16(header + 8, records);
  bytes.setRange(header + 16, header + 20, ascii.encode('MOBI'));
  data.setUint32(header + 28, 65001);
  data.setUint32(header + 108, records + 1);
  bytes.setRange(start, start + body.length, body);
  bytes.setRange(start + body.length, bytes.length, png);
  final mobi = File('$root/vellum_device_13485.mobi');
  await mobi.writeAsBytes(bytes);

  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'book.opf',
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">vellum-device-lazy</dc:identifier>'
            '<dc:title>Vellum设备分块EPUB</dc:title><dc:language>zh</dc:language></metadata>'
            '<manifest><item id="body" href="body.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest>'
            '<spine><itemref idref="body"/></spine></package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'nav.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head>'
            '<body><nav epub:type="toc"><ol><li><a href="body.xhtml">验收正文</a></li></ol></nav></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'body.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>验收</title></head><body>'
            '${List.generate(20000, (i) => '<p>EPUB设备第${i + 1}段，中文😀原书与重排。</p>').join()}'
            '</body></html>',
      ),
    );
  final epub = File('$root/vellum_device_20000.epub');
  await epub.writeAsBytes(ZipEncoder().encode(archive));
  final txt = File('$root/vellum_device_gb18030.txt');
  final sink = txt.openWrite();
  // Four-byte U+20000 and U+1F600 straddle 5K source block boundaries.
  final line = [
    ...ascii.encode('GB18030-device '),
    0x95,
    0x32,
    0x82,
    0x36,
    0x94,
    0x39,
    0xfc,
    0x36,
    10,
  ];
  final block = <int>[for (var i = 0; i < 1024; i++) ...line];
  for (var i = 0; i < 512; i++) {
    sink.add(block);
    if (i % 32 == 0) await sink.flush();
  }
  await sink.flush();
  await sink.close();
  return [mobi.path, epub.path, txt.path];
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _library = const BookLibrary();
  final _key = GlobalKey<ReaderPageState>();
  final _events = <Map<String, Object?>>[];
  final _errors = <String>[];
  final _created = <ImportedBook>[];
  final _snapshots = <String, Uint8List?>{};
  List<ImportedBook> _before = [];
  bool _shelfCaptured = false;
  Widget? _surface;
  String _status = 'Preparing device validation';
  Timer? _timer;
  int _lag = 0;
  int _peakRss = 0;
  String _root = '';
  String _temp = '';

  void _check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  void _log(String event, [Map<String, Object?> values = const {}]) {
    final row = {
      'event': event,
      'rss': ProcessInfo.currentRss,
      'max_ui_lag_ms': _lag,
      ...values,
    };
    _events.add(row);
    // ignore: avoid_print
    print('VELLUM_DEVICE ${jsonEncode(row)}');
    if (mounted) setState(() => _status = event);
  }

  @override
  void initState() {
    super.initState();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _errors.add(details.exceptionAsString());
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _errors.add('$error');
      _log('ASYNC_ERROR', {'error': '$error', 'stack': '$stack'});
      return true;
    };
    final watch = Stopwatch()..start();
    var last = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = watch.elapsedMilliseconds;
      final delay = now - last - 100;
      if (delay > _lag) _lag = delay;
      last = now;
      final rss = ProcessInfo.currentRss;
      if (rss > _peakRss) _peakRss = rss;
    });
    unawaited(_run());
  }

  Future<void> _hide() async {
    if (mounted) setState(() => _surface = null);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _read(ImportedBook book) async {
    await _hide();
    setState(
      () => _surface = ReaderPage(
        key: _key,
        book: book,
        initialState: const ReadingState(mode: 'page'),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final state = _key.currentState!;
    _check(state.readingMode == ReadingMode.page, 'page preference ignored');
    final target = book.paragraphCount * 9 ~/ 10;
    final watch = Stopwatch()..start();
    await state.jumpToParagraph(target);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final paragraph = state.currentPageParagraphOrInitial();
    _check(
      (paragraph - target).abs() < 3,
      'deep jump missed: $paragraph / $target',
    );
    _log('DEEP_JUMP', {
      'format': book.format.name,
      'paragraphs': book.paragraphCount,
      'target': target,
      'landed': paragraph,
      'ms_including_settle': watch.elapsedMilliseconds,
    });
    final before = state.currentPageParagraphOrInitial();
    state.refresh(() => state.fontSize = 28);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _check(
      (state.currentPageParagraphOrInitial() - before).abs() < 3,
      'font changed position',
    );
    for (var i = 0; i < 4; i++) {
      if (!state.mounted) throw StateError("Reader disposed during validation");
      state.changePage(state.context, 1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    _check(
      state.currentPageParagraphOrInitial() >= before,
      'forward paging moved backwards',
    );
    await state.setReadingMode(ReadingMode.scroll);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await state.jumpToParagraph(book.paragraphCount ~/ 2);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _check(
      (state.currentParagraph - book.paragraphCount ~/ 2).abs() < 3,
      'scroll jump missed: ${state.currentParagraph}',
    );
    final body = book.paragraphs;
    if (body is ChunkedParagraphList) {
      _check(body.cachedBlockCount <= 5, 'cache limit exceeded');
      _log('READER_PASS', {
        'format': book.format.name,
        'cached_blocks': body.cachedBlockCount,
        'cached_text_bytes': body.cachedBytes,
      });
    } else {
      _log('READER_PASS', {'format': book.format.name});
    }
    await _hide();
  }

  Future<void> _run() async {
    var success = false;
    try {
      _root = (await getApplicationDocumentsDirectory()).path;
      _temp = '${(await getTemporaryDirectory()).path}/vellum_lazy_validation';
      await Directory(_temp).create(recursive: true);
      for (final name in [
        'vellum_reader_prefs.json',
        'vellum_reading_state.json',
        'vellum_reading_stats.json',
        'vellum_writings.json',
      ]) {
        final file = File('$_root/$name');
        _snapshots[name] = await file.exists()
            ? await file.readAsBytes()
            : null;
      }
      _before = await _library.load();
      _shelfCaptured = true;
      for (final shell in _before) {
        final path = '$_root/vellum_books/${shell.storageId}.json';
        final sample = await compute(_legacySample, path);
        final watch = Stopwatch()..start();
        final full = await _library.loadBookContent(shell);
        _check(
          full.paragraphs is ChunkedParagraphList,
          'legacy migration failed',
        );
        _check(
          _digest(full.paragraphs) == sample['digest'],
          'legacy text changed',
        );
        _log(
          sample['was_chunked'] == true ? 'CHUNKED_REOPEN' : 'LEGACY_MIGRATION',
          {
            'title': full.title,
            'paragraphs': full.paragraphCount,
            'ms': watch.elapsedMilliseconds,
            'sample_sha256': sample['digest'],
          },
        );
        await _read(full);
      }
      _log('GENERATE_FIXTURES');
      final root = _temp;
      final paths = await compute(_fixtures, root);
      var shelf = _before;
      for (final path in paths) {
        final file = File(path);
        final watch = Stopwatch()..start();
        final result = await const BookImportService().importFile(
          library: _library,
          existing: shelf,
          file: PlatformFile(
            name: file.uri.pathSegments.last,
            path: path,
            size: await file.length(),
          ),
        );
        shelf = result.library;
        if (!result.duplicate) _created.add(result.book);
        _log('IMPORT', {
          'format': result.book.format.name,
          'paragraphs': result.book.paragraphCount,
          'ms': watch.elapsedMilliseconds,
        });
        final full = await _library.loadBookContent(result.book);
        _check(full.paragraphs is LazyParagraphs, 'eager book loaded');
        if (full.format == BookFormat.txt) {
          _check(
            full.paragraphs.last.contains('𠀀😀'),
            'GB18030 text corrupted',
          );
        }
        final task = BookSearchTask(
          paragraphs: full.paragraphs,
          query: full.format == BookFormat.txt
              ? '不存在的验收词'
              : (full.format == BookFormat.mobi
                    ? '设备正文第13485段'
                    : 'EPUB设备第20000段'),
          chapters: [],
        );
        final hits = await task.result;
        _check(
          full.format == BookFormat.txt ? hits.isEmpty : !hits.isEmpty,
          'search result mismatch',
        );
        _log('SEARCH_PASS', {
          'format': full.format.name,
          'hits': hits.hits.length,
        });
        if (full.format == BookFormat.mobi) {
          _check(full.imageBytes.isNotEmpty, 'MOBI images lost');
          final picture = image.decodeImage(full.coverBytes!)!;
          _check(
            picture.width <= 1600 && picture.height <= 1600,
            'cover not resized',
          );
          _log('COVER_AND_IMAGES_PASS', {
            'images': full.imageBytes.length,
            'cover_width': picture.width,
            'cover_height': picture.height,
          });
        }
        await _read(full);
        if (full.format == BookFormat.epub) {
          final ready = Completer<void>();
          final original = await _library.originalEpubPath(full.storageId);
          setState(
            () => _surface = EpubOriginalReaderPage(
              book: full,
              originalPath: original,
              contentPath: registeredBookSearchPath(full.paragraphs),
              onReady: () {
                if (!ready.isCompleted) ready.complete();
              },
              onError: (error) {
                if (!ready.isCompleted) ready.completeError(error);
              },
            ),
          );
          await ready.future.timeout(const Duration(seconds: 60));
          _log('EPUB_WEBVIEW_PASS');
          await _hide();
        }
      }
      final writing = const WritingLibrary();
      final draft = await writing.create(
        title: 'Vellum设备验收草稿',
        body: '草稿初始正文。',
      );
      setState(() => _surface = WritingEditorPage(document: draft));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final fields = <CupertinoTextField>[];
      void visit(Element element) {
        if (element.widget is CupertinoTextField)
          fields.add(element.widget as CupertinoTextField);
        element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
      final bodyField = fields.firstWhere(
        (f) => f.controller?.text == '草稿初始正文。',
      );
      bodyField.controller!.text = '草稿初始正文。\n\n设备验证自动保存，中文😀。';
      await Future<void>.delayed(const Duration(seconds: 2));
      _check(
        (await writing.load())
            .firstWhere((d) => d.id == draft.id)
            .body
            .contains('设备验证自动保存'),
        'draft autosave failed',
      );
      await _hide();
      _log('DRAFT_AUTOSAVE_PASS');
      _check(_errors.isEmpty, 'Flutter errors: $_errors');
      success = true;
    } catch (error, stack) {
      _log('FAIL', {'error': '$error', 'stack': '$stack'});
    } finally {
      await _hide();
      for (final book in _created) await _library.deleteBook(book);
      if (_shelfCaptured) await _library.saveIndex(_before);
      for (final entry in _snapshots.entries) {
        final file = File('$_root/${entry.key}');
        if (entry.value == null) {
          if (await file.exists()) await file.delete();
        } else {
          await file.writeAsBytes(entry.value!, flush: true);
        }
      }
      _timer?.cancel();
      final report = {
        'success': success,
        'peak_rss': _peakRss,
        'max_ui_lag_ms': _lag,
        'flutter_errors': _errors,
        'events': _events,
      };
      await File(
        '$_temp/report.json',
      ).writeAsString(jsonEncode(report), flush: true);
      _log(success ? 'PASS' : 'FAILED', {'peak_rss': _peakRss});
    }
  }

  @override
  Widget build(BuildContext context) =>
      _surface ?? CupertinoPageScaffold(child: Center(child: Text(_status)));
}
