import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../theme/vellum_theme.dart';
import '../widgets/font_preview.dart';

/// Fanqie-style font picker data: only the built-in system font is listed by
/// default. User-imported fonts are appended from the real installed list;
/// unavailable licensed fonts are never advertised.
const fanqieReaderFonts = <ReaderFontOption>[
  ReaderFontOption('Default', '系统字体'),
];

class ReaderFontOption {
  const ReaderFontOption(this.family, this.title);
  final String family;
  final String title;
}

/// Fanqie-style font picker: a plain full-width list, preview glyph on the
/// right, and an immediate selected state. The picker keeps the preview and
/// filtering controls in the sheet so switching fonts never requires leaving
/// the reading context.
class ReaderFontPickerSheet extends StatefulWidget {
  const ReaderFontPickerSheet({
    required this.installedFonts,
    required this.activeFamily,
    required this.onSelectSystemFont,
    required this.onSelectImportedFont,
    this.surface,
    super.key,
  });

  final List<InstalledFont> installedFonts;
  final String activeFamily;
  final ValueChanged<String> onSelectSystemFont;
  final Future<void> Function(InstalledFont) onSelectImportedFont;

  /// Active reading paper. The sheet sits over the page, so its surface and
  /// ink must follow the page's paper in light and dark themes alike.
  final Color? surface;

  @override
  State<ReaderFontPickerSheet> createState() => _ReaderFontPickerSheetState();
}

class _ReaderFontPickerSheetState extends State<ReaderFontPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installedFonts = widget.installedFonts;
    final activeFamily = widget.activeFamily;
    final onSelectSystemFont = widget.onSelectSystemFont;
    final onSelectImportedFont = widget.onSelectImportedFont;
    final bg = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final muted = ink.withValues(alpha: .55);
    final accent = VellumTheme.readerAccentOf(context);
    final isDarkPaper = bg.computeLuminance() < .24;
    final selectedFill = accent.withValues(alpha: isDarkPaper ? .28 : .13);
    final selectedBorder = accent.withValues(alpha: isDarkPaper ? .92 : .78);
    final divider = ink.withValues(alpha: isDarkPaper ? .20 : .12);
    final query = _query.text.trim().toLowerCase();
    final imported = installedFonts
        .where(
          (font) =>
              query.isEmpty ||
              font.label.toLowerCase().contains(query) ||
              font.family.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '选择字体',
                    style: TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      onPressed: () => Navigator.pop(context),
                      child: Text('完成', style: TextStyle(color: accent)),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: .5, color: divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Aa · 永 · 阅读改变生活',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontFamily: activeFamily.isEmpty
                          ? VellumTheme.systemUiFontFamily
                          : activeFamily,
                      fontSize: 19,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (installedFonts.length > 4) ...[
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      placeholder: '搜索字体',
                      prefix: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Icon(
                          CupertinoIcons.search,
                          size: 16,
                          color: muted,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      style: TextStyle(color: ink),
                      placeholderStyle: TextStyle(color: muted),
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(height: .5, color: divider),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _sectionTitle('内置', ink),
                  for (final option in fanqieReaderFonts)
                    _row(
                      title: option.title,
                      family: option.family == 'Default' ? null : option.family,
                      selected:
                          activeFamily == option.family ||
                          (option.family == 'Default' &&
                                  activeFamily ==
                                      VellumTheme.systemUiFontFamily ||
                              activeFamily == 'Georgia'),
                      muted: muted,
                      accent: accent,
                      ink: ink,
                      selectedFill: selectedFill,
                      selectedBorder: selectedBorder,
                      onTap: () => onSelectSystemFont(
                        option.family == 'Default'
                            ? VellumTheme.systemUiFontFamily
                            : option.family,
                      ),
                    ),
                  _sectionTitle('我的导入', ink),
                  if (imported.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                      child: Text(
                        query.isEmpty ? '还没有导入字体' : '没有匹配的字体',
                        style: TextStyle(color: muted),
                      ),
                    )
                  else
                    for (final font in imported)
                      _row(
                        title: font.label,
                        family: font.family,
                        selected: activeFamily == font.family,
                        muted: muted,
                        accent: accent,
                        ink: ink,
                        selectedFill: selectedFill,
                        selectedBorder: selectedBorder,
                        custom: FontPreview(
                          font: font,
                          compact: true,
                          loadOnMount: activeFamily == font.family,
                          ink: activeFamily == font.family ? accent : muted,
                        ),
                        onTap: () => onSelectImportedFont(font),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, Color ink) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Text(
      title,
      style: TextStyle(
        color: ink.withValues(alpha: .62),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _row({
    required String title,
    required String? family,
    required bool selected,
    required Color muted,
    required Color accent,
    required Color ink,
    required Color selectedFill,
    required Color selectedBorder,
    required VoidCallback onTap,
    Widget? custom,
  }) => CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? selectedFill : null,
        border: selected ? Border.all(color: selectedBorder, width: 1) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accent : ink,
                fontSize: 16,
                fontFamily: family,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (custom != null)
            Flexible(fit: FlexFit.loose, child: custom)
          else
            Text(
              '永Aa',
              style: TextStyle(
                color: selected ? accent : muted,
                fontSize: 16,
                fontFamily: family,
              ),
            ),
          if (selected) ...[
            const SizedBox(width: 12),
            Icon(CupertinoIcons.checkmark_alt, size: 18, color: accent),
          ],
        ],
      ),
    ),
  );
}
