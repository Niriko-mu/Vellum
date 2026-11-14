import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';
import '../widgets/ui/app_section.dart' show appHairline;
import '../widgets/ui/app_sheet.dart';
import '../theme/app_icons.dart';

class FontManagerSheet extends StatelessWidget {
  final List<InstalledFont> installedFonts;

  final String activeFontName;

  final Future<void> Function(String) onActivateFont;

  final Future<void> Function(String) onDeleteFont;

  final Future<void> Function() onImportFonts;

  final String appName = 'Vellum';

  const FontManagerSheet({
    super.key,
    required this.installedFonts,
    required this.activeFontName,
    required this.onActivateFont,
    required this.onDeleteFont,
    required this.onImportFonts,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.c;

    return AppSheet(
      title: '字体管理',
      maxHeightFactor: 0.7,
      padding: EdgeInsets.zero,
      trailing: AppPressable(
        onTap: onImportFonts,
        semanticLabel: '导入字体',
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x2),
          child: Icon(AppIcons.plusCircle, color: colors.primary),
        ),
      ),
      footer: AppButton(
        label: '关闭',
        variant: AppButtonVariant.tonal,
        expand: true,
        onPressed: () => Navigator.pop(context),
      ),
      child: installedFonts.isEmpty
          ? const AppContentState(
              kind: AppContentStateKind.empty,
              icon: AppIcons.textformat,
              title: '暂无字体',
              description: '点击右上角 + 导入字体',
            )
          : Column(
              children: [
                for (final font in installedFonts)
                  _FontCard(
                    font: font,
                    isActive: font.name == activeFontName,
                    onActivate: () {
                      Navigator.pop(context);
                      onActivateFont(font.name);
                    },
                    onDelete: () => _confirmDelete(context, font.name),
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String fontName) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除字体'),
        content: Text('确定要删除 "\$fontName" 吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await onDeleteFont(fontName);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _FontCard extends StatelessWidget {
  final InstalledFont font;

  final bool isActive;

  final VoidCallback onActivate;

  final VoidCallback onDelete;

  const _FontCard({
    required this.font,
    required this.isActive,
    required this.onActivate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.c;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        0,
        AppSpace.x4,
        AppSpace.x3,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: AppRadius.groupedAll,
          // Selection is a fill plus an outline in the selected tier; it is not
          // a thicker version of the default hairline.
          border: isActive
              ? Border.all(color: colors.primary, width: 1)
              : Border.all(color: colors.border),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.groupedAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Glyph sample, inside the card: one surface, no nested panel.
              Padding(
                padding: const EdgeInsets.all(AppSpace.x5),
                child: Text(
                  '永Aa · 阅读改变生活',
                  style: AppText.stateTitle(colors.foreground).copyWith(
                    fontSize: 24,
                    fontFamily: isActive
                        ? font.family
                        : VellumThemeFamilies.system,
                  ),
                ),
              ),
              SizedBox(height: appHairline(context), child: ColoredBox(color: colors.border)),
              Padding(
                padding: const EdgeInsets.all(AppSpace.x3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            font.label,
                            style: AppText.rowTitle(colors.foreground),
                          ),
                          if (isActive) ...[
                            const SizedBox(height: AppSpace.x1),
                            Text(
                              '当前使用中',
                              style: AppText.caption(colors.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isActive)
                      AppButton(
                        label: '启用',
                        size: AppButtonSize.small,
                        variant: AppButtonVariant.tonal,
                        onPressed: onActivate,
                      ),
                    const SizedBox(width: AppSpace.x2),
                    AppPressable(
                      onTap: onDelete,
                      semanticLabel: '删除字体',
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.x3),
                        child: Icon(
                          AppIcons.trash,
                          color: colors.destructive,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The interface font family, resolved outside a widget tree.
abstract final class VellumThemeFamilies {
  static const system = 'sans-serif';
}
