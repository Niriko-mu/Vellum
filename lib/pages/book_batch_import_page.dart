import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import '../services/book_import_service.dart';
import '../services/book_library.dart';
import '../services/book_models.dart';
import '../services/local_book_scan_service.dart';

/// Returns the updated lightweight library through Navigator.pop.
class BookBatchImportPage extends StatefulWidget {
  const BookBatchImportPage({
    super.key,
    required this.library,
    required this.existing,
    this.scanDirectory = false,
  });
  final BookLibrary library;
  final List<ImportedBook> existing;
  final bool scanDirectory;
  @override
  State<BookBatchImportPage> createState() => _BookBatchImportPageState();
}

class _Candidate {
  _Candidate(this.name, {this.file, this.scanned});
  final String name;
  final PlatformFile? file;
  final ScannedBookFile? scanned;
  bool selected = true;
  String? outcome;
}

class _BookBatchImportPageState extends State<BookBatchImportPage> {
  final _scanner = const LocalBookScanService();
  final _files = <_Candidate>[];
  late List<ImportedBook> _library;
  StreamSubscription<BookScanUpdate>? _subscription;
  BookImportCancellation? _cancellation;
  bool _busy = false;
  String _status = '请选择需要导入的电子书';
  ImportProgress? _progress;
  @override
  void initState() {
    super.initState();
    _library = widget.existing;
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _files.clear();
      _status = '正在选择文件…';
      _progress = null;
    });
    try {
      if (widget.scanDirectory && _scanner.supported) {
        final uri = await _scanner.pickDirectory();
        if (uri == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await _subscription?.cancel();
        _subscription = _scanner.updates.listen(
          (update) {
            if (!mounted) return;
            setState(() {
              _files.addAll(
                update.files.map((f) => _Candidate(f.name, scanned: f)),
              );
              _status =
                  update.error ??
                  '已检查 ${update.inspected} 个项目，找到 ${_files.length} 本电子书';
              if (update.done) _busy = false;
            });
          },
          onError: (Object error) {
            if (mounted)
              setState(() {
                _status = error.toString();
                _busy = false;
              });
          },
        );
        await _scanner.scan(uri);
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt', 'epub', 'mobi'],
          allowMultiple: true,
          withData: false,
        );
        if (!mounted) return;
        setState(() {
          _files.addAll(
            (picked?.files ?? []).map((f) => _Candidate(f.name, file: f)),
          );
          _busy = false;
          _status = '已选择 ${_files.length} 本电子书';
        });
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _status = error.toString();
          _busy = false;
        });
    }
  }

  Future<void> _import() async {
    final candidates = _files
        .where((f) => f.selected && f.outcome != '已导入' && f.outcome != '已存在')
        .toList();
    if (candidates.isEmpty) return;
    final token = BookImportCancellation();
    _cancellation = token;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      for (var i = 0; i < candidates.length && !token.isCancelled; i++) {
        final candidate = candidates[i];
        PlatformFile? file;
        try {
          setState(
            () => _status =
                '${i + 1}/${candidates.length} 正在读取 ${candidate.name}',
          );
          file = candidate.file ?? await _scanner.copy(candidate.scanned!);
          token.check();
          final result = await const BookImportService().importFile(
            library: widget.library,
            existing: _library,
            file: file,
            cancellation: token,
            onProgress: (p) {
              if (mounted)
                setState(() {
                  _progress = p;
                  _status =
                      '${i + 1}/${candidates.length} ${candidate.name}：${p.stage}';
                });
            },
          );
          _library = result.library;
          candidate.outcome = result.duplicate ? '已存在' : '已导入';
          candidate.selected = false;
        } catch (error) {
          candidate.outcome = error.toString();
          if (error is BookImportCancelled || token.isCancelled) break;
        } finally {
          if (candidate.scanned != null && file?.path != null) {
            final cached = File(file!.path!);
            if (await cached.exists()) await cached.delete();
          }
          if (mounted) setState(() {});
        }
      }
    } finally {
      _cancellation = null;
      if (mounted)
        setState(() {
          _busy = false;
          _progress = null;
          _status = token.isCancelled ? '已取消；已导入的书籍已保存' : '处理完成；失败项目可以重新选择后重试';
        });
    }
  }

  Future<void> _cancel() async {
    _cancellation?.cancel();
    if (_scanner.supported) await _scanner.cancel();
    if (_cancellation == null && mounted)
      setState(() {
        _busy = false;
        _status = '扫描已停止';
      });
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _subscription?.cancel();
    if (_scanner.supported) unawaited(_scanner.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_cancel());
    },
    child: CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.scanDirectory ? '扫描本地电子书' : '批量导入'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy ? _cancel : () => Navigator.pop(context, _library),
          child: Text(_busy ? '取消' : '完成'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: CupertinoActivityIndicator(),
                    ),
                  Expanded(child: Text(_status)),
                ],
              ),
            ),
            if (_progress?.value != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('当前文件：${((_progress!.value!) * 100).round()}%'),
              ),
            if (!_busy)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CupertinoButton(onPressed: _pick, child: const Text('重新选择')),
                  CupertinoButton(
                    onPressed: () => setState(() {
                      final select = _files.any((f) => !f.selected);
                      for (final f in _files) {
                        f.selected = select;
                      }
                    }),
                    child: const Text('全选 / 清空'),
                  ),
                ],
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return CupertinoListTile(
                    title: Text(file.name),
                    subtitle: file.outcome == null ? null : Text(file.outcome!),
                    leading: Icon(
                      file.selected
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                    ),
                    onTap: _busy
                        ? null
                        : () => setState(() => file.selected = !file.selected),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoButton.filled(
                onPressed: _busy || !_files.any((f) => f.selected)
                    ? null
                    : _import,
                child: Text(
                  '导入选中的 ${_files.where((f) => f.selected).length} 本',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
