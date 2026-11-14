import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_type.dart';
import 'app_pressable.dart';
import 'app_section.dart' show appHairline;

/// The one bottom-sheet presentation.
///
/// Fill is `popover`, which is distinguishable from the page `background` in
/// dark mode — that is the whole reason the two roles are separate. The footer
/// inherits the sheet fill so it never falls back to the page colour.
class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.child,
    this.title,
    this.leading,
    this.trailing,
    this.footer,
    this.maxHeightFactor = 0.86,
    this.scrollable = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.x4),
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? leading;
  final Widget? trailing;

  /// Pinned below the scrolling body, on the sheet's own fill.
  final Widget? footer;

  final double maxHeightFactor;
  final bool scrollable;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final paddingInsets = MediaQuery.viewPaddingOf(context);
    final height = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * maxHeightFactor),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.popover,
            borderRadius: AppRadius.sheetTop,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpace.x2),
                Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: AppRadius.pillAll,
                  ),
                ),
                if (title != null || leading != null || trailing != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.x4,
                      AppSpace.x4,
                      AppSpace.x4,
                      AppSpace.x3,
                    ),
                    child: Row(
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: AppSpace.x2),
                        ],
                        Expanded(
                          child: Text(
                            title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.sectionHeader(colors.foreground),
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                  )
                else
                  const SizedBox(height: AppSpace.x3),
                Flexible(
                  child: scrollable
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: AppSpace.x4),
                          child: Padding(padding: padding, child: child),
                        )
                      : Padding(padding: padding, child: child),
                ),
                if (footer != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.popover,
                      border: Border(top: BorderSide(color: colors.border)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.x4,
                        AppSpace.x3,
                        AppSpace.x4,
                        AppSpace.x3 + paddingInsets.bottom,
                      ),
                      child: footer!,
                    ),
                  )
                else
                  SizedBox(height: AppSpace.x2 + paddingInsets.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of an action sheet.
class AppActionSheetItem {
  const AppActionSheetItem({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// Separated by a divider and coloured; never the default action.
  final bool destructive;
}

/// A single-decision action sheet: 56pt rows, the cancel group separated.
class AppActionSheet extends StatelessWidget {
  const AppActionSheet({
    required this.actions,
    required this.onCancel,
    this.title,
    this.message,
    super.key,
  });

  final List<AppActionSheetItem> actions;
  final VoidCallback onCancel;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final insets = MediaQuery.viewPaddingOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.x2,
        AppSpace.x2,
        AppSpace.x2,
        insets.bottom + AppSpace.x2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.popover,
              borderRadius: AppRadius.xl3All,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null || message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.x4,
                      AppSpace.x5,
                      AppSpace.x4,
                      AppSpace.x3,
                    ),
                    child: Column(
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            textAlign: TextAlign.center,
                            style: AppText.sectionHeader(colors.foreground),
                          ),
                        if (message != null) ...[
                          const SizedBox(height: AppSpace.x1),
                          Text(
                            message!,
                            textAlign: TextAlign.center,
                            style: AppText.rowDescription(
                              colors.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                for (final action in actions) ...[
                  Container(height: appHairline(context), color: colors.border),
                  _ActionRow(
                    label: action.label,
                    color: action.destructive
                        ? colors.destructive
                        : colors.foreground,
                    onPressed: action.onPressed,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.x2),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.popover,
              borderRadius: AppRadius.xl3All,
            ),
            child: _ActionRow(
              label: '取消',
              color: colors.foreground,
              bold: true,
              onPressed: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.color,
    required this.onPressed,
    this.bold = false,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = AppText.rowTitle(color);
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: SizedBox(
        height: 56,
        child: Center(
          child: Text(
            label,
            style: bold ? style.copyWith(fontWeight: FontWeight.w600) : style,
          ),
        ),
      ),
    );
  }
}
