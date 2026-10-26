import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'library_models.dart';
import 'ttf_name_reader.dart';

/// Font file persistence, independent of book storage.
class FontStorage {
  const FontStorage({this.directory});

  /// Explicit root for isolated storage tests and tools.
  final Directory? directory;

  Future<Uint8List?> loadFont() async {
    final file = await _fontFile();
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> saveFont(Uint8List bytes) async {
    final file = await _fontFile();
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<FontPreferences> loadFontPreferences() async {
    final file = await _fontPreferencesFile();
    if (!await file.exists()) return const FontPreferences();
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return FontPreferences(
        useForUi: data['useForUi'] as bool? ?? false,
        useForContent: data['useForContent'] as bool? ?? false,
        activeFont: data['activeFont'] as String? ?? '',
      );
    } catch (_) {
      return const FontPreferences();
    }
  }

  Future<void> saveFontPreferences(FontPreferences preferences) async {
    final file = await _fontPreferencesFile();
    await file.writeAsString(
      jsonEncode({
        'useForUi': preferences.useForUi,
        'useForContent': preferences.useForContent,
        'activeFont': preferences.activeFont,
      }),
    );
  }

  Future<List<InstalledFont>> listFonts() async {
    final dir = await _fontsDir();
    if (!await dir.exists()) return [];

    final fonts = <InstalledFont>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.ttf')) {
        final filename = entity.uri.pathSegments.last;
        final name = filename.replaceFirst(
          RegExp(r'\.ttf$', caseSensitive: false),
          '',
        );
        final family = 'Font_${name.hashCode.abs()}';
        late final String displayName;
        try {
          displayName = await readFontDisplayNameFromFile(entity) ?? name;
        } catch (_) {
          displayName = name;
        }
        fonts.add(
          InstalledFont(name: name, family: family, displayName: displayName),
        );
      }
    }
    return fonts;
  }

  Future<void> saveFontWithName(String name, Uint8List bytes) async {
    final dir = await _fontsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Copy one source with bounded buffers, validate, then replace the old file.
  /// A failed replacement restores the previous font instead of truncating it.
  Future<void> importFont(
    String name, {
    String? path,
    Stream<List<int>>? stream,
  }) async {
    if (name.trim().isEmpty ||
        name.contains(RegExp(r'[/\\\x00-\x1f]')) ||
        name == '.' ||
        name == '..') {
      throw const FormatException('字体文件名无效');
    }
    final dir = await _fontsDir();
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    final temporary = await Directory(dir.path).createTemp('.font-import-');
    final staged = File('${temporary.path}/font.ttf');
    final previous = File('${temporary.path}/previous.ttf');
    try {
      if (path != null && path.isNotEmpty) {
        await File(path).copy(staged.path);
      } else if (stream != null) {
        final sink = staged.openWrite();
        try {
          await sink.addStream(stream);
          await sink.flush();
        } finally {
          await sink.close();
        }
      } else {
        throw const FormatException('无法读取字体文件，请重新选择');
      }
      await validateFontFile(staged);
      if (await file.exists()) await file.rename(previous.path);
      try {
        await staged.rename(file.path);
      } catch (_) {
        if (await previous.exists()) await previous.rename(file.path);
        rethrow;
      }
    } finally {
      // Keep the recoverable previous file if restoring it itself failed.
      if (await previous.exists() && !await file.exists()) {
        await previous.rename(file.path);
      }
      await temporary.delete(recursive: true);
    }
  }

  Future<Uint8List?> loadFontByName(String name) async {
    final dir = await _fontsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> deleteFontByName(String name) async {
    final dir = await _fontsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    if (await file.exists()) await file.delete();
  }

  Future<void> clearFont() async {
    final file = await _fontFile();
    if (await file.exists()) await file.delete();
  }

  Future<File> fontFile() => _fontFile();

  Future<Directory> _fontsDir() async =>
      directory ??
      Directory(
        '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_fonts',
      );

  Future<File> _fontFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_font.ttf',
  );

  Future<File> _fontPreferencesFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_font_preferences.json',
  );
}
