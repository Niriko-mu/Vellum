import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_type.dart';
import 'app_controls.dart';
import 'app_pressable.dart';
import '../../theme/app_icons.dart';

/// A grouped, inset list block — the backbone of every settings, detail and
/// picker page.
///
/// The block *is* the grouping: one rounded `card` surface, rows separated by
/// hairlines inset to the content edge. Never a card inside a card, and never a
/// stroke around the block.
///
/// Geometry is owned here (see references/geometry.md): header 40 tall and 4
/// from the block, rows 40 minimum and 48 natural, separators inset to 44 when
/// the rows carry a leading glyph and 12 when they do not.
class AppSection extends StatelessWidget {
  const AppSection({
    required this.children,
    this.header,
    this.footer,
    this.headerTrailing,
    this.margin,
    super.key,
  });

  /// The rows of the block. Each child must be a row widget, not a wrapper: a
  /// wrapper hides the leading-icon information the separator inset depends on,
  /// and that is exactly how the 44pt inset drifted last time.
  final List<Widget> children;

  /// Grouped header: 16/24 semibold, 40pt tall, 4 above the block.
  ///
  /// A header is a label, not a card title. A block that needs one on every page
  /// is a sign the page has too many groups.
  final String? header;

  /// Grouped footer: 14/20 muted, 8 below the block.
  final String? footer;

  /// Optional small action on the header row (a count, a link).
  final Widget? headerTrailing;

  final EdgeInsetsGeometry? margin;

  /// Whether any row draws a leading glyph. Derived from the rows themselves so
  /// a page cannot forget to say so.
  static bool _hasLeadingRow(List<Widget> rows) {
    for (final row in rows) {
      if (row is AppRow && row.leading != null) return true;
      if (row is AppSelectRow && row.leading != null) return true;
      if (row is AppSwitchRow && row.leading != null) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final hasLeading = _hasLeadingRow(children);
    // One notifier for the whole block: a row reports press, the separators
    // above and below it subscribe. Two notifiers per row would be worse.
    final pressed = ValueNotifier<int?>(null);

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          _SectionSeparator(
            key: ValueKey<String>('section-separator-$i'),
            above: i - 1,
            below: i,
            pressed: pressed,
            hasLeading: hasLeading,
          ),
        );
      }
      rows.add(
        _SectionScope(index: i, pressed: pressed, child: children[i]),
      );
    }

    return Padding(
      padding: margin ?? const EdgeInsets.only(bottom: AppSpace.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpace.x3,
                right: AppSpace.x3,
                bottom: AppSpace.x1,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpace.sectionHeaderMinHeight,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        header!,
                        style: AppText.sectionHeader(colors.foreground),
                      ),
                    ),
                    ?headerTrailing,
                  ],
                ),
              ),
            ),
          ClipRRect(
            borderRadius: AppRadius.groupedAll,
            child: ColoredBox(
              color: colors.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpace.x3,
                right: AppSpace.x3,
                top: AppSpace.x2,
              ),
              child: Text(
                footer!,
                style: AppText.rowDescription(colors.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carries the block's press state down to the rows without a global.
class _SectionScope extends InheritedWidget {
  const _SectionScope({
    required this.index,
    required this.pressed,
    required super.child,
  });

  final int index;
  final ValueNotifier<int?> pressed;

  static _SectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SectionScope>();

  @override
  bool updateShouldNotify(_SectionScope oldWidget) =>
      index != oldWidget.index || pressed != oldWidget.pressed;
}

class _SectionSeparator extends StatelessWidget {
  const _SectionSeparator({
    required this.above,
    required this.below,
    required this.pressed,
    required this.hasLeading,
    super.key,
  });

  /// Row indices on either side. The line disappears while either is pressed.
  final int above;
  final int below;
  final ValueNotifier<int?> pressed;
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final left = hasLeading
        ? AppSpace.separatorInsetAfterLeading
        : AppSpace.separatorInset;
    return ValueListenableBuilder<int?>(
      valueListenable: pressed,
      builder: (context, value, _) {
        final hidden = value == above || value == below;
        return Padding(
          padding: EdgeInsets.only(
            left: left,
            right: AppSpace.separatorInset,
          ),
          child: SizedBox(
            height: appHairline(context),
            child: ColoredBox(
              color: hidden ? colors.border.withValues(alpha: 0) : colors.border,
            ),
          ),
        );
      },
    );
  }
}

/// One physical pixel, whatever the display density.
double appHairline(BuildContext context) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  return 1 / dpr;
}

/// A dense row inside a grouped block.
///
/// Rows are not cards and carry no outer margin: the section owns the gutter
/// and the separator, the row owns its internal padding.
class AppRow extends StatelessWidget {
  const AppRow({
    required this.label,
    this.description,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.onLongPress,
    this.showChevron,
    this.destructive = false,
    this.enabled = true,
    this.selected = false,
    this.density = AppRowDensity.regular,
    super.key,
  });

  final String label;

  /// 14/20 muted, 4 below the title.
  final String? description;

  /// A 16pt stroke glyph. Not a coloured tile, not decoration.
  final Widget? leading;

  /// Overrides [value]: a switch, a spinner.
  final Widget? trailing;

  /// Trailing text, capped at 62% of the window so a long value ellipsizes
  /// instead of squeezing the label into a one-character column.
  final String? value;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overrides the derived chevron. Leave null and the row decides: a row that
  /// navigates and shows no value gets a right chevron, because that is what
  /// "this opens something" means. A row with a value gets none — the value is
  /// already the trailing affordance.
  final bool? showChevron;

  final bool destructive;
  final bool enabled;

  /// Selection is a fill, not a border.
  final bool selected;
  final AppRowDensity density;

  /// Derived: navigate + no value => chevron.
  bool get _chevron {
    if (showChevron != null) return showChevron!;
    return onTap != null && value == null && trailing == null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final titleColor = destructive ? colors.destructive : colors.foreground;
    final scope = _SectionScope.maybeOf(context);

    Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpace.rowMinHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpace.x4,
          vertical: density.verticalPadding,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(
                  size: AppSpace.x4,
                  color: destructive ? colors.destructive : colors.foreground,
                ),
                child: leading!,
              ),
              const SizedBox(width: AppSpace.x3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.rowTitle(titleColor)),
                  if (description != null) ...[
                    const SizedBox(height: AppSpace.x1),
                    Text(
                      description!,
                      style: AppText.rowDescription(colors.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.62,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpace.x3),
                  child: Text(
                    value!,
                    key: const ValueKey<String>('app-row-value'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.rowValue(colors.foreground),
                  ),
                ),
              ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.x3),
                child: trailing!,
              ),
            if (_chevron)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.x2),
                child: Icon(
                  AppIcons.chevronRight,
                  key: const ValueKey<String>('app-row-chevron'),
                  size: AppSpace.x5,
                  color: colors.mutedForeground,
                ),
              ),
          ],
        ),
      ),
    );

    if (selected) {
      content = ColoredBox(color: colors.secondary, child: content);
    }

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: AppPressable(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        enabled: enabled,
        semanticLabel: [label, ?value].join('，'),
        onPressChanged: scope == null
            ? null
            : (pressedNow) =>
                  scope.pressed.value = pressedNow ? scope.index : null,
        child: content,
      ),
    );
  }
}

/// A row that picks a value from a list.
///
/// The trailing down-chevron is the whole point: without it a row showing
/// "简体中文" looks exactly like a row showing something read-only, and readers
/// stop trying to tap it.
class AppSelectRow extends StatelessWidget {
  const AppSelectRow({
    required this.label,
    this.value,
    required this.onTap,
    this.description,
    this.leading,
    this.enabled = true,
    this.density = AppRowDensity.regular,
    super.key,
  });

  final String label;

  /// The current choice. Optional: a row that opens a picker without showing a
  /// choice (the picker's own label is already the label) still needs the down
  /// chevron, because that is the affordance, not the value.
  final String? value;

  final VoidCallback onTap;
  final String? description;
  final Widget? leading;
  final bool enabled;
  final AppRowDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final scope = _SectionScope.maybeOf(context);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: AppPressable(
        onTap: enabled ? onTap : null,
        enabled: enabled,
        semanticLabel: value == null ? label : '$label，当前 $value',
        onPressChanged: scope == null
            ? null
            : (pressedNow) =>
                  scope.pressed.value = pressedNow ? scope.index : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpace.rowMinHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.x4,
              vertical: density.verticalPadding,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      size: AppSpace.x4,
                      color: colors.foreground,
                    ),
                    child: leading!,
                  ),
                  const SizedBox(width: AppSpace.x3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.rowTitle(colors.foreground)),
                      if (description != null) ...[
                        const SizedBox(height: AppSpace.x1),
                        Text(
                          description!,
                          style: AppText.rowDescription(
                            colors.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.62,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpace.x3),
                      child: Text(
                        value!,
                        key: const ValueKey<String>('app-row-value'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppText.rowValue(colors.foreground),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpace.x2),
                  child: Icon(
                    AppIcons.chevronDown,
                    size: 20,
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row whose whole surface toggles a switch.
///
/// The switch is an indicator, not the target: tapping the label toggles it too.
/// A 44pt switch is a small thing to hit on a phone, and the row is already the
/// thing the reader is aiming at.
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.leading,
    this.enabled = true,
    this.density = AppRowDensity.regular,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? description;
  final Widget? leading;
  final bool enabled;
  final AppRowDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final scope = _SectionScope.maybeOf(context);
    final interactive = enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: AppPressable(
        onTap: interactive ? () => onChanged(!value) : null,
        enabled: interactive,
        semanticLabel: label,
        semanticHint: value ? '已开启' : '已关闭',
        onPressChanged: scope == null
            ? null
            : (pressedNow) =>
                  scope.pressed.value = pressedNow ? scope.index : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpace.rowMinHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.x4,
              vertical: density.verticalPadding,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      size: AppSpace.x4,
                      color: colors.foreground,
                    ),
                    child: leading!,
                  ),
                  const SizedBox(width: AppSpace.x3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.rowTitle(colors.foreground)),
                      if (description != null) ...[
                        const SizedBox(height: AppSpace.x1),
                        Text(
                          description!,
                          style: AppText.rowDescription(
                            colors.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                // Indicator only: the row already handles the tap.
                IgnorePointer(
                  child: AppSwitch(
                    value: value,
                    enabled: enabled,
                    semanticLabel: label,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Row vertical padding by density.
enum AppRowDensity {
  compact(8),
  regular(12),
  comfortable(16);

  const AppRowDensity(this.verticalPadding);
  final double verticalPadding;
}
