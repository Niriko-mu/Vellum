// Run with flutter run -d emulator-5554 -t tool/import_device_probe.dart.
// Uses isolated fixture IDs and restores the pre-existing bookshelf afterwards.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vellum/reader/epub_original_reader_page.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_import_service.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/book_search.dart';
import 'package:vellum/services/txt_seek_source.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _Probe()));
}

Future<List<String>> _fixtures(String root) async {
  final txt = File('$root/vellum_probe_99mb.txt');
  final out = txt.openWrite();
  out.write('第一章 Vellum设备验收\n');
  final line = utf8.encode('设备验收中文😀正文，按章节和字符安全分块。\n');
  final chunk = BytesBuilder(copy: false);
  for (var i = 0; i < 1024; i++) chunk.add(line);
  final data = chunk.takeBytes();
  var count = 0;
  while (count + data.length < 99 * 1024 * 1024) {
    out.add(data);
    count += data.length;
    if (count % (data.length * 32) == 0) await out.flush();
  }
  await out.flush();
  await out.close();
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/book.opf',
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">vellum-probe-20261011</dc:identifier><dc:title>Vellum十万段验收</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="body" href="body.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="body"/></spine></package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/nav.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="body.xhtml">验收正文</a></li></ol></nav></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/body.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>验收</title><style>table{border-collapse:collapse}td{border:1px solid #999;color:#a33}</style></head><body><table><tr><td>原书表格样式</td></tr></table>${List.generate(100000, (i) => '<p>设备正文第${i + 1}段，中文😀原书样式测试。</p>').join()}</body></html>',
      ),
    );
  final epub = File('$root/vellum_probe_large.epub');
  await epub.writeAsBytes(ZipEncoder().encode(archive));
  return [txt.path, epub.path];
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  String _status = 'Preparing';
  ImportedBook? _epub;
  String? _path;
  final _library = const BookLibrary();
  final _created = <ImportedBook>[];
  List<ImportedBook> _before = [];
  Timer? _timer;
  int _maxLag = 0;
  final _watch = Stopwatch()..start();
  final _readerKey = GlobalKey<ReaderPageState>();
  bool _reflow = false;

  void _log(String message) {
    // ignore: avoid_print
    print('VELLUM_PROBE $message');
    if (mounted) setState(() => _status = message);
  }

  @override
  void initState() {
    super.initState();
    var last = _watch.elapsedMilliseconds;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = _watch.elapsedMilliseconds;
      final lag = now - last - 50;
      if (lag > _maxLag) _maxLag = lag;
      last = now;
    });
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final prior = await _library.load();
      for (final book in prior.where((b) =>
          b.title == 'vellum_probe_99mb' || b.title == 'Vellum十万段验收')) {
        await _library.deleteBook(book);
        await _library.deleteReadingState(book);
      }
      _before = prior.where((b) =>
          b.title != 'vellum_probe_99mb' && b.title != 'Vellum十万段验收').toList();
      await _library.saveIndex(_before);
      final temp = await getTemporaryDirectory();
      final root = await Directory(
        '${temp.path}/vellum_device_probe',
      ).create(recursive: true);
      final paths = await Isolate.run(() => _fixtures(root.path));
      var books = _before;
      for (final path in paths) {
        final source = File(path);
        final start = Stopwatch()..start();
        final result = await const BookImportService().importFile(
          library: _library,
          existing: books,
          file: PlatformFile(
            name: source.uri.pathSegments.last,
            path: path,
            size: await source.length(),
          ),
        );
        books = result.library;
        if (!result.duplicate) _created.add(result.book);
        _log(
          'IMPORT ${result.book.format.name} ms=${start.elapsedMilliseconds} paragraphs=${result.book.paragraphCount}',
        );
        final full = await _library.loadBookContent(result.book);
        final task = BookSearchTask(
          paragraphs: full.paragraphs,
          query: '不存在的验收关键词',
          chapters: [],
        );
        final matches = await task.result;
        if (!matches.isEmpty) throw StateError('unexpected matches');
        _log('SEARCH ${full.format.name} complete');
        if (full.paragraphs is TxtParagraphList) {
          final list = full.paragraphs as TxtParagraphList;
          await list.source.prefetchAroundParagraph(full.paragraphCount - 1);
          if (full.paragraphs.last.contains('�'))
            throw StateError('broken character');
          list.source.close();
        } else {
          _epub = full;
          _path = await _library.originalEpubPath(full.storageId);
        }
      }
      _log(
        'ORIGINAL_OPEN max_ui_lag_ms=$_maxLag rss=${ProcessInfo.currentRss}',
      );
    } catch (error, stack) {
      _log('FAIL $error $stack');
      await _cleanup();
    }
  }

  Future<void> _ready() async {
    _log('WEBVIEW_READY rss=${ProcessInfo.currentRss}');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _reflow = true);
    await Future<void>.delayed(const Duration(seconds: 3));
    await _readerKey.currentState?.jumpToParagraph(90000);
    await Future<void>.delayed(const Duration(seconds: 2));
    _log(
      'REFLOW_DEEP_JUMP max_ui_lag_ms=$_maxLag rss=${ProcessInfo.currentRss}',
    );
    if (mounted)
      setState(() {
        _epub = null;
      });
    await Future<void>.delayed(const Duration(seconds: 1));
    await _cleanup();
    _log(
      'PASS elapsed_ms=${_watch.elapsedMilliseconds} max_ui_lag_ms=$_maxLag rss=${ProcessInfo.currentRss}',
    );
    _timer?.cancel();
  }

  Future<void> _cleanup() async {
    for (final book in _created) {
      await _library.deleteBook(book);
      await _library.deleteReadingState(book);
      final state = File(
        '${await _library.originalEpubPath(book.storageId)}.reader.json',
      );
      if (await state.exists()) await state.delete();
    }
    await _library.saveIndex(_before);
  }

  @override
  Widget build(BuildContext context) {
    if (_epub != null && _path != null) {
      if (_reflow) return ReaderPage(key: _readerKey, book: _epub!);
      return EpubOriginalReaderPage(
        book: _epub!,
        originalPath: _path!,
        contentPath: registeredBookSearchPath(_epub!.paragraphs),
        onReady: () => unawaited(_ready()),
        onError: (error) {
          _log('WEBVIEW_FAIL $error');
          unawaited(_cleanup());
        },
      );
    }
    return CupertinoPageScaffold(child: Center(child: Text(_status)));
  }
}
