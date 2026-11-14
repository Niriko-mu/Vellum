import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../reader/reader_font_picker.dart';
import '../services/library_models.dart';
import '../services/writing_library.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/app_controls.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_icons.dart';

/// Writing tab: list of local drafts, open editor to write .md / .txt.
class WritingTypographySheet extends StatefulWidget {
  const WritingTypographySheet({
    required this.initial,
    required this.installedFonts,
    required this.novelAvailable,
    required this.onChanged,
    required this.onActivateImportedFont,
    required this.onRefreshFonts,
    super.key,
  });

  final WritingTypography initial;
  final List<InstalledFont> installedFonts;

  /// False for Markdown drafts: novel layout is a plain-text rule.
  final bool novelAvailable;
  final ValueChanged<WritingTypography> onChanged;
  final Future<void> Function(InstalledFont) onActivateImportedFont;
  final Future<List<InstalledFont>> Function() onRefreshFonts;

  @override
  State<WritingTypographySheet> createState() => _WritingTypographySheetState();
}

class _WritingTypographySheetState extends State<WritingTypographySheet> {
  late WritingTypography _typo = widget.initial;
  late List<InstalledFont> _fonts = widget.installedFonts;
  bool _busyFont = false;

  void _update(WritingTypography next) {
    setState(() => _typo = next);
    widget.onChanged(next);
  }

  String get _fontLabel {
    final family = _typo.fontFamily;
    if (family == null || family == 'Georgia' || family == 'Default') {
      return '系统字体';
    }
    for (final font in _fonts) {
      if (font.family == family) return font.label;
    }
    // Built-in aliases from older drafts.
    return switch (family) {
      'serif' => '衬线',
      'monospace' => '等宽',
      'sans-serif' => '无衬线',
      'Cursive' => '手写',
      _ => family,
    };
  }

  Future<void> _openFontPicker() async {
    final fonts = await widget.onRefreshFonts();
    if (!mounted) return;
    setState(() => _fonts = fonts);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => ReaderFontPickerSheet(
        installedFonts: _fonts,
        activeFamily: _typo.fontFamily ?? 'Georgia',
        onSelectSystemFont: (family) {
          Navigator.pop(ctx);
          final isDefault = family == 'Georgia' || family == 'Default';
          _update(
            _typo.copyWith(
              fontFamily: isDefault ? null : family,
              clearFont: isDefault,
            ),
          );
        },
        onSelectImportedFont: (font) async {
          setState(() => _busyFont = true);
          await widget.onActivateImportedFont(font);
          if (!mounted) {
            setState(() => _busyFont = false);
            return;
          }
          setState(() => _busyFont = false);
          if (ctx.mounted) Navigator.pop(ctx);
          _update(_typo.copyWith(fontFamily: font.family));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;
    final accent = context.c.primary;
    final card = context.c.card;
    final line = context.c.border;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(AppRadius.grouped),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '排版',
              textAlign: TextAlign.center,
              style: AppText.sectionHeader(ink),
            ),
            const SizedBox(height: 4),
            Text(
              '对所有文稿全局生效',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 12),
            // Font row — same picker as the reading page (system + imported).
            Text('字体', style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 8),
            AppPressable(
              onTap: _busyFont ? null : _openFontPicker,
              enabled: !_busyFont,
              semanticLabel: '选择字体',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _busyFont ? '正在加载字体…' : _fontLabel,
                        style: TextStyle(
                          color: ink,
                          fontSize: 16,
                          fontFamily: _typo.fontFamily,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '永Aa',
                      style: TextStyle(
                        color: muted,
                        fontSize: 16,
                        fontFamily: _typo.fontFamily,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      AppIcons.rightChevron,
                      size: 16,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('字号', style: TextStyle(fontSize: 13, color: muted)),
            Row(
              children: [
                AppTextButton(
                  label: 'A−',
                  color: ink,
                  onPressed: () => _update(
                    _typo.copyWith(
                      fontSize: (_typo.fontSize - 1).clamp(
                        WritingTypography.minSize,
                        WritingTypography.maxSize,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: CupertinoSlider(
                    value: _typo.fontSize.clamp(
                      WritingTypography.minSize,
                      WritingTypography.maxSize,
                    ),
                    min: WritingTypography.minSize,
                    max: WritingTypography.maxSize,
                    onChanged: (v) => _update(_typo.copyWith(fontSize: v)),
                  ),
                ),
                AppTextButton(
                  label: 'A+',
                  color: ink,
                  onPressed: () => _update(
                    _typo.copyWith(
                      fontSize: (_typo.fontSize + 1).clamp(
                        WritingTypography.minSize,
                        WritingTypography.maxSize,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${_typo.fontSize.round()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('字重', style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 8),
            CupertinoSlidingSegmentedControl<int>(
              groupValue: _typo.weightIndex,
              children: {
                for (var i = 0; i < WritingTypography.weightLabels.length; i++)
                  i: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(WritingTypography.weightLabels[i]),
                  ),
              },
              onValueChanged: (v) {
                if (v == null) return;
                _update(_typo.copyWith(weightIndex: v));
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '小说模式',
                        style: AppText.stateTitle(
                          widget.novelAvailable ? ink : muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.novelAvailable
                            ? '开启后自动排版：段首两格缩进 · 段间空行'
                            : 'Markdown 模式下不启用，切换到纯文本即可使用',
                        style: AppText.caption(muted),
                      ),
                    ],
                  ),
                ),
                AppSwitch(
                  value: widget.novelAvailable && _typo.novelMode,
                  enabled: widget.novelAvailable,
                  semanticLabel: '小说排版',
                  onChanged: (v) => _update(_typo.copyWith(novelMode: v)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '显示保存状态',
                        style: AppText.stateTitle(ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '关闭后标题下方只保留日期，写作时不再出现变化的文字',
                        style: AppText.caption(muted),
                      ),
                    ],
                  ),
                ),
                AppSwitch(
                  value: _typo.showSaveStatus,
                  semanticLabel: '显示保存状态',
                  onChanged: (v) => _update(_typo.copyWith(showSaveStatus: v)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Text(
                (widget.novelAvailable && _typo.novelMode)
                    ? '　　示例文字 The quick brown fox'
                    : '示例文字 The quick brown fox',
                style: TextStyle(
                  color: ink,
                  fontSize: _typo.fontSize,
                  fontFamily: _typo.fontFamily,
                  fontWeight: _typo.fontWeight,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppTextButton(
              label: '完成',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}