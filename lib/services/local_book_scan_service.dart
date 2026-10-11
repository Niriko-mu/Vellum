import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class ScannedBookFile {
  const ScannedBookFile({
    required this.uri,
    required this.name,
    required this.size,
  });
  final String uri;
  final String name;
  final int size;
  factory ScannedBookFile.fromMap(Map<dynamic, dynamic> map) => ScannedBookFile(
    uri: map['uri'] as String,
    name: map['name'] as String,
    size: (map['size'] as num?)?.toInt() ?? 0,
  );
}

class BookScanUpdate {
  const BookScanUpdate({
    this.files = const [],
    this.inspected = 0,
    this.done = false,
    this.error,
  });
  final List<ScannedBookFile> files;
  final int inspected;
  final bool done;
  final String? error;
}

class LocalBookScanService {
  const LocalBookScanService();
  static const _methods = MethodChannel('vellum/local_books');
  static const _events = EventChannel('vellum/local_books/scan');
  bool get supported => Platform.isAndroid;
  Future<String?> pickDirectory() =>
      _methods.invokeMethod<String>('pickDirectory');
  Stream<BookScanUpdate> get updates =>
      _events.receiveBroadcastStream().map((event) {
        final map = event as Map;
        return BookScanUpdate(
          files: [
            for (final value in map['files'] as List? ?? [])
              ScannedBookFile.fromMap(value as Map),
          ],
          inspected: (map['inspected'] as num?)?.toInt() ?? 0,
          done: map['done'] == true,
          error: map['error'] as String?,
        );
      });
  Future<void> scan(String uri) async {
    await _methods.invokeMethod('scanDirectory', {'uri': uri});
  }

  Future<void> cancel() async {
    await _methods.invokeMethod('cancel');
  }

  Future<PlatformFile> copy(ScannedBookFile file) async {
    final result = await _methods.invokeMapMethod<String, dynamic>('copyFile', {
      'uri': file.uri,
      'name': file.name,
    });
    if (result == null) throw const FileSystemException('文件提供方没有返回内容');
    return PlatformFile(
      name: file.name,
      path: result['path'] as String,
      size: result['size'] as int,
    );
  }
}
