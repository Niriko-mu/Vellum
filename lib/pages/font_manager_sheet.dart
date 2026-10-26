import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../theme/vellum_theme.dart';

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
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final surface = VellumTheme.shellOf(context);
    final card = VellumTheme.cardOf(context);
    final line = VellumTheme.lineOf(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),

      decoration: BoxDecoration(
        color: surface,

        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),

      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Padding(
            padding: const EdgeInsets.all(16),

            child: Row(
              children: [
                Text(
                  '字体管理',

                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const Spacer(),

                CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),

                  onPressed: () {
                    Navigator.pop(context);

                    onImportFonts();
                  },

                  child: Icon(CupertinoIcons.plus_circle, color: accent),
                ),
              ],
            ),
          ),

          Container(height: 1, color: line),

          Flexible(
            child: installedFonts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),

                    child: Column(
                      children: [
                        Icon(CupertinoIcons.textformat, size: 48, color: muted),

                        const SizedBox(height: 16),

                        Text(
                          '暂无字体',

                          style: TextStyle(fontSize: 16, color: muted),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '点击右上角 + 导入字体',

                          style: TextStyle(fontSize: 14, color: muted),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,

                    itemCount: installedFonts.length,

                    itemBuilder: (context, index) {
                      final font = installedFonts[index];

                      final isActive = font.name == activeFontName;

                      return _FontCard(
                        font: font,

                        isActive: isActive,

                        onActivate: () {
                          Navigator.pop(context);

                          onActivateFont(font.name);
                        },

                        onDelete: () => _confirmDelete(context, font.name),
                      );
                    },
                  ),
          ),

          SafeArea(
            top: false,

            child: Padding(
              padding: const EdgeInsets.all(16),

              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                color: card,

                onPressed: () => Navigator.pop(context),

                child: Text('关闭', style: TextStyle(color: ink)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String fontName) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,

      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          '删除字体',
          style: TextStyle(color: VellumTheme.inkOf(context)),
        ),

        content: Text(
          '确定要删除 "$fontName" 吗？',
          style: TextStyle(color: VellumTheme.mutedOf(context)),
        ),

        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),

            child: Text(
              '取消',
              style: TextStyle(color: VellumTheme.accentOf(context)),
            ),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

      decoration: BoxDecoration(
        color: VellumTheme.cardOf(context),

        borderRadius: BorderRadius.circular(12),

        border: isActive
            ? Border.all(color: VellumTheme.accentOf(context), width: 1.5)
            : Border.all(color: VellumTheme.lineOf(context)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // 字体预览区
          Container(
            padding: const EdgeInsets.all(20),

            decoration: BoxDecoration(
              color: VellumTheme.cardOf(context).withValues(alpha: .72),

              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),

            child: Text(
              '永Aa · 阅读改变生活',
              style: TextStyle(
                color: VellumTheme.inkOf(context),
                fontSize: 20,
                fontFamily: isActive
                    ? font.family
                    : VellumTheme.systemUiFontFamily,
              ),
            ),
          ),

          // 操作区
          Padding(
            padding: const EdgeInsets.all(12),

            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        font.label,

                        style: TextStyle(
                          color: VellumTheme.inkOf(context),
                          fontSize: 16,

                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      if (isActive)
                        Text(
                          '当前使用中',

                          style: TextStyle(
                            fontSize: 12,

                            color: VellumTheme.accentOf(context),
                          ),
                        ),
                    ],
                  ),
                ),

                if (!isActive)
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),

                    onPressed: onActivate,

                    child: Text(
                      '启用',
                      style: TextStyle(color: VellumTheme.accentOf(context)),
                    ),
                  ),

                CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),

                  onPressed: onDelete,

                  child: Icon(
                    CupertinoIcons.trash,

                    color: CupertinoColors.systemRed.resolveFrom(context),

                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
