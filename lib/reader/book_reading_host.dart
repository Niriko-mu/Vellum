import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../services/book_importer.dart';
import '../services/book_search.dart';
import 'epub_original_reader_page.dart';
import '../services/epub_original_state.dart';
import 'reader_page.dart';

/// Routes EPUB to its retained original while keeping the existing reader.
class BookReadingHost extends StatefulWidget {
  const BookReadingHost({
    required this.book,
    required this.initialState,
    required this.originalPath,
    this.onStateChanged,
    this.installedFonts = const [],
    this.activeFontName = '',
    this.onActivateFont,
    this.onToggleUiTheme,
    super.key,
  });

  final ImportedBook book;
  final ReadingState initialState;
  final String? originalPath;
  final Future<void> Function(ReadingState)? onStateChanged;
  final List<InstalledFont> installedFonts;
  final String activeFontName;
  final Future<void> Function(String)? onActivateFont;
  final VoidCallback? onToggleUiTheme;

  @override
  State<BookReadingHost> createState() => _BookReadingHostState();
}

class _BookReadingHostState extends State<BookReadingHost> {
  late ReadingState _readingState;
  bool? _original;

  @override
  void initState() {
    super.initState();
    _readingState = widget.initialState;
    _loadMode();
  }

  Future<void> _loadMode() async {
    final path = widget.originalPath;
    final available =
        Platform.isAndroid && path != null && await File(path).exists();
    var mode = 'reflow';
    if (available) {
      try {
        mode = await EpubOriginalStateStore.preferredMode(path);
      } catch (_) {
        // The original reader explains the damaged sidecar and offers reflow.
        mode = 'original';
      }
    }
    if (mounted) setState(() => _original = available && mode != 'reflow');
  }

  Future<void> _saveState(ReadingState value) async {
    _readingState = value;
    await widget.onStateChanged?.call(value);
  }

  Future<void> _switchMode(bool original) async {
    final path = widget.originalPath;
    if (path == null) return;
    await EpubOriginalStateStore.setPreferredMode(
      path,
      original ? 'original' : 'reflow',
    );
    if (mounted) setState(() => _original = original);
  }

  @override
  Widget build(BuildContext context) {
    if (_original == null) {
      return const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_original!) {
      return EpubOriginalReaderPage(
        book: widget.book,
        originalPath: widget.originalPath!,
        contentPath: registeredBookSearchPath(widget.book.paragraphs),
        initialState: _readingState,
        onStateChanged: _saveState,
        onUseReflow: () => _switchMode(false),
      );
    }
    final reader = ReaderPage(
      key: ValueKey('reflow_${_readingState.paragraphIndex}'),
      book: widget.book,
      initialState: _readingState,
      onStateChanged: _saveState,
      installedFonts: widget.installedFonts,
      activeFontName: widget.activeFontName,
      onActivateFont: widget.onActivateFont,
      onToggleUiTheme: widget.onToggleUiTheme,
    );
    if (!Platform.isAndroid || widget.originalPath == null) return reader;
    return Stack(
      children: [
        reader,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 4,
          right: 12,
          child: CupertinoButton(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: () => _switchMode(true),
            child: const Text('原书样式', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}
