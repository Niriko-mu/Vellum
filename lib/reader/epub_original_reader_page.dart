import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/book_models.dart';
import '../services/library_models.dart';
import '../services/notes_library.dart';
import '../services/epub_original_service.dart';

String _anchor(String text) =>
    String.fromCharCodes(text.replaceAll(RegExp(r'\s+'), '').runes.take(80));

Map<String, int> _readAnchors(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map;
  final paragraphs = json['paragraphs'] as List? ?? [];
  return {
    for (var i = 0; i < paragraphs.length; i++)
      if ((paragraphs[i] as String).trim().isNotEmpty)
        _anchor(paragraphs[i] as String): i,
  };
}

Future<Map<String, int>> _loadAnchors(String path) =>
    Isolate.run(() => _readAnchors(path));

class EpubOriginalReaderPage extends StatefulWidget {
  const EpubOriginalReaderPage({
    super.key,
    required this.book,
    required this.originalPath,
    this.initialState = const ReadingState(),
    this.onStateChanged,
    this.onUseReflow,
    this.contentPath,
    this.onReady,
    this.onError,
  });
  final ImportedBook book;
  final String originalPath;
  final ReadingState initialState;
  final Future<void> Function(ReadingState)? onStateChanged;
  final VoidCallback? onUseReflow;
  final String? contentPath;
  final VoidCallback? onReady;
  final ValueChanged<String>? onError;
  @override
  State<EpubOriginalReaderPage> createState() => _EpubOriginalReaderPageState();
}

class _EpubOriginalReaderPageState extends State<EpubOriginalReaderPage> {
  EpubOriginalServer? _server;
  WebViewController? _controller;
  late final _store = EpubOriginalStateStore(widget.originalPath);
  Map<String, dynamic> _state = {};
  Map<String, int> _anchors = {};
  List<Map<String, dynamic>> _toc = [];
  String? _error;
  bool _ready = false;
  bool _switching = false;
  Timer? _saveTimer;
  Timer? _openTimer;
  Future<void> _writes = Future.value();
  int _paragraph = 0;

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    widget.onError?.call(message);
  }

  @override
  void initState() {
    super.initState();
    _openTimer = Timer(const Duration(seconds: 60), () {
      if (!_ready) _fail('原书打开超时，可切换重排阅读。');
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      _state = await _store.load();
      _paragraph = widget.initialState.paragraphIndex;
      final paragraphs = widget.book.paragraphs;
      final contentPath = widget.contentPath;
      _anchors = contentPath != null
          ? await _loadAnchors(contentPath)
          : {
              if (_paragraph < paragraphs.length)
                _anchor(paragraphs[_paragraph]): _paragraph,
            };
      final server = await EpubOriginalServer.start(widget.originalPath);
      if (!mounted) {
        await server.close();
        return;
      }
      _server = server;
      final resume =
          _state['mode'] != 'reflow' &&
          (_state['paragraphIndex'] as num?)?.toInt() == _paragraph;
      final chapter = widget.book.tocEntries.lastIndexWhere(
        (entry) => entry.paragraphIndex <= _paragraph,
      );
      final config = {
        'url': server.packageUri.toString(),
        'cfi': resume ? _state['cfi'] : null,
        'spine': _paragraph < paragraphs.length
            ? (server.spineAnchors[_anchor(paragraphs[_paragraph])] ??
                  (chapter < 0 ? 0 : chapter))
            : (chapter < 0 ? 0 : chapter),
        'text': _paragraph < paragraphs.length ? paragraphs[_paragraph] : '',
        'notes': _state['notes'] ?? [],
      };
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'Vellum',
          onMessageReceived: (message) => unawaited(_message(message.message)),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) =>
                server.owns(Uri.parse(request.url)) ||
                    request.url == 'about:blank'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
            onPageFinished: (url) async {
              if (url == server.viewerUri.toString()) {
                try {
                  await _controller?.runJavaScript(
                    'startBook(${jsonEncode(config)})',
                  );
                } catch (_) {
                  _fail('原书阅读器初始化失败，可切换重排。');
                }
              }
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == true) _fail('原书页面加载失败，请重试或切换重排。');
            },
          ),
        );
      _controller = controller;
      setState(() {});
      await controller.loadRequest(server.viewerUri);
    } catch (error) {
      _fail('无法打开原书样式：$error');
    }
  }

  Future<void> _message(String raw) async {
    if (!mounted || raw.length > 256 * 1024) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      switch (data['type']) {
        case 'ready':
          _openTimer?.cancel();
          setState(() => _ready = true);
          widget.onReady?.call();
        case 'toc':
          setState(
            () => _toc = (data['entries'] as List)
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList(),
          );
        case 'error':
          _fail('原书渲染失败：${data['message']}');
        case 'position':
          if (_switching) return;
          _paragraph = _anchors[data['text']] ?? _paragraph;
          _state.addAll({
            'cfi': data['cfi'],
            'spine': data['spine'],
            'paragraphIndex': _paragraph,
            'mode': 'original',
          });
          _saveTimer?.cancel();
          _saveTimer = Timer(
            const Duration(milliseconds: 500),
            () => unawaited(
              _persist().catchError((Object error) {
                _fail('阅读位置保存失败，请重试。');
              }),
            ),
          );
        case 'selection':
          await _selection(data);
      }
    } catch (_) {
      _fail('阅读位置或标注无法保存，请重试。');
    }
  }

  Future<void> _selection(Map<String, dynamic> data) async {
    final text = data['text'] as String? ?? '';
    final cfi = data['cfi'] as String? ?? '';
    if (text.isEmpty || cfi.isEmpty) return;
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('标注选中文字'),
        message: Text(text.characters.take(300).join()),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存划线'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ),
    );
    if (result != true || !mounted) return;
    final note = await const NotesLibrary().add(
      bookId: widget.book.storageId,
      bookTitle: widget.book.title,
      paragraphIndex: _anchors[_anchor(text)] ?? _paragraph,
      selectedText: text,
      style: ReadingNoteStyle.highlight,
    );
    final notes = List<dynamic>.from(_state['notes'] as List? ?? []);
    notes.add({
      'id': note.id,
      'cfi': cfi,
      'text': text,
      'paragraphIndex': note.paragraphIndex,
    });
    _state['notes'] = notes;
    await _persist();
    await _controller?.runJavaScript('mark(${jsonEncode(cfi)})');
  }

  Future<void> _persist() {
    final snapshot = Map<String, dynamic>.from(_state);
    final reading = ReadingState.fromJson({
      ...widget.initialState.toJson(),
      'paragraphIndex': _paragraph,
      'bookId': widget.book.storageId,
    });
    _writes = _writes.catchError((_) {}).then((_) async {
      await _store.save(snapshot);
      await widget.onStateChanged?.call(reading);
    });
    return _writes;
  }

  Future<void> _reflow() async {
    if (_switching) return;
    _switching = true;
    _saveTimer?.cancel();
    try {
      if (_ready) {
        var location = await _controller?.runJavaScriptReturningResult(
          'readerLocation()',
        );
        if (location is String) {
          dynamic decoded = jsonDecode(location);
          if (decoded is String) decoded = jsonDecode(decoded);
          if (decoded is Map && decoded['start'] is Map) {
            _state['cfi'] = decoded['start']['cfi'];
            _state['spine'] = decoded['start']['index'];
          }
        }
      }
      _state['mode'] = 'reflow';
      await _persist();
      if (mounted) widget.onUseReflow?.call();
    } catch (_) {
      _switching = false;
      _fail('保存阅读位置失败，请重试。');
    }
  }

  void _directory() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoPopupSurface(
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: ListView(
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭目录'),
                ),
                for (final entry in _toc)
                  CupertinoButton(
                    alignment: Alignment.centerLeft,
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(
                        _controller?.runJavaScript(
                              'go(${jsonEncode(entry['href'])})',
                            ) ??
                            Future.value(),
                      );
                    },
                    child: Text(
                      '${'  ' * ((entry['depth'] as num?)?.toInt() ?? 0)}${entry['title']}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _openTimer?.cancel();
    if (_state.containsKey('cfi')) unawaited(_persist().catchError((_) {}));
    unawaited(_server?.close() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: Text(widget.book.title),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: widget.onUseReflow == null ? null : _reflow,
        child: const Text('重排'),
      ),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!),
                    ),
                  )
                : Stack(
                    children: [
                      if (_controller != null)
                        WebViewWidget(controller: _controller!),
                      if (!_ready)
                        const Center(child: CupertinoActivityIndicator()),
                    ],
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CupertinoButton(
                onPressed: _ready
                    ? () => _controller?.runJavaScript('turn(-1)')
                    : null,
                child: const Text('上一页'),
              ),
              CupertinoButton(
                onPressed: _ready ? _directory : null,
                child: const Text('目录'),
              ),
              CupertinoButton(
                onPressed: _ready
                    ? () => _controller?.runJavaScript('turn(1)')
                    : null,
                child: const Text('下一页'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
