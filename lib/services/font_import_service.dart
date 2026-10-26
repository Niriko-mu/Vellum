import 'dart:async';

import 'package:file_picker/file_picker.dart';

import 'font_storage.dart';

class FontImportResult {
  const FontImportResult(this.filename, {this.error});
  final String filename;
  final String? error;
}

/// Serial disk imports. Never registers a font or retains a batch of bytes.
class FontImportService {
  FontImportService({this.storage = const FontStorage()});
  final FontStorage storage;
  bool _busy = false;

  Future<List<FontImportResult>> importFiles(
    List<PlatformFile> files, {
    void Function(int current, int total, String filename)? onProgress,
  }) async {
    if (_busy) throw StateError('字体正在导入，请稍候');
    _busy = true;
    final results = <FontImportResult>[];
    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        onProgress?.call(i + 1, files.length, file.name);
        try {
          if (!file.name.toLowerCase().endsWith('.ttf')) {
            throw const FormatException('仅支持 TTF 字体');
          }
          final name = file.name.substring(0, file.name.length - 4);
          await storage.importFont(
            name,
            path: file.path,
            stream: file.readStream,
          );
          results.add(FontImportResult(file.name));
        } catch (error) {
          results.add(FontImportResult(file.name, error: error.toString()));
        }
      }
      return results;
    } finally {
      _busy = false;
    }
  }
}
