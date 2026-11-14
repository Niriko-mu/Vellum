import 'package:flutter/cupertino.dart';
import '../theme/vellum_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_icons.dart';
class ReaderPanelTitle extends StatelessWidget {
  const ReaderPanelTitle({
    required this.icon,
    required this.title,
    required this.onClose,
    this.onBack,
    this.surface,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final muted = VellumTheme.readerSecondaryInk(bg);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        children: [
          if (onBack != null)
            AppPressable(
              onTap: onBack,
              semanticLabel: '返回',
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(AppIcons.chevronBack, size: 20, color: muted),
              ),
            )
          else
            Icon(icon, size: 18, color: context.c.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: ink,
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          AppPressable(
            onTap: onClose,
            semanticLabel: '收起',
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(AppIcons.chevronDown, size: 20, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

class ReaderSettingRow extends StatelessWidget {
  const ReaderSettingRow({
    required this.label,
    required this.child,
    this.surface,
    super.key,
  });

  final String label;
  final Widget child;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final muted = VellumTheme.readerSecondaryInk(bg);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                label,
                style: TextStyle(color: muted, fontSize: 13, height: 18 / 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}