import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../services/font_registry.dart';

/// Renders an imported font using the exact runtime family that is assigned
/// when it is selected. The preview binds that family before loading finishes;
/// Flutter replaces the fallback glyphs as soon as the registration completes.
///
/// Registration goes through [FontRegistry] and is deferred a moment. A picker
/// sheet with a dozen imported CJK fonts used to register every row it built at
/// once, and each registration permanently costs the engine ≈1.9× the font
/// file size — the memory that made font switching end in a crash. Deferring
/// also means rows scrolled straight past never register at all.
class FontPreview extends StatefulWidget {
  const FontPreview({
    required this.font,
    this.compact = false,
    this.ink,
    this.defer = const Duration(milliseconds: 180),
    this.loadOnMount = true,
    super.key,
  });

  final InstalledFont font;
  final bool compact;

  /// Preview ink. Defaults to the ambient theme text color; the reader font
  /// picker passes the active paper's ink so night/charcoal papers stay right.
  final Color? ink;

  /// How long the row must stay on screen before it asks for its font.
  final Duration defer;

  /// Render without registration when used in a catalog row.
  final bool loadOnMount;

  @override
  State<FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<FontPreview> {
  Timer? _defer;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnMount) _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant FontPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadOnMount &&
        (oldWidget.font.name != widget.font.name ||
            oldWidget.font.family != widget.font.family)) {
      _scheduleLoad();
    }
  }

  @override
  void dispose() {
    _defer?.cancel();
    super.dispose();
  }

  void _scheduleLoad() {
    _defer?.cancel();
    // Already registered: the row paints in the real face with no I/O at all.
    if (FontRegistry.isRegistered(widget.font.family)) return;
    if (widget.defer == Duration.zero) {
      _loadFont();
      return;
    }
    _defer = Timer(widget.defer, () {
      if (mounted) _loadFont();
    });
  }

  Future<void> _loadFont() async {
    try {
      final bytes = await const BookLibrary().loadFontByName(widget.font.name);
      if (bytes == null) return;
      final registered = await FontRegistry.load(widget.font.family, bytes);
      if (registered && mounted) setState(() {});
    } catch (_) {
      // The font row remains legible via the platform fallback if invalid.
    }
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.ink ?? CupertinoTheme.of(context).textTheme.textStyle.color;
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '永',
            style: TextStyle(
              fontFamily: widget.font.family,
              fontSize: 23,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Aa',
            style: TextStyle(
              fontFamily: widget.font.family,
              fontSize: 18,
              color: color,
              height: 1,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '中文示例：阅读改变生活',
          style: TextStyle(
            fontFamily: widget.font.family,
            fontSize: 20,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'English: Reading changes life',
          style: TextStyle(
            fontFamily: widget.font.family,
            fontSize: 18,
            color: color,
          ),
        ),
      ],
    );
  }
}
