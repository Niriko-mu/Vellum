import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_type.dart';
import 'app_pressable.dart';

/// A grouped, inset list block — the backbone of every settings, detail and
/// picker page.
///
/// The block *is* the grouping: one rounded `card` surface, rows separated by
/// hairlines inset to the content edge. Never a card inside a card, and never a
/// stroke around the block.
class AppSection extends StatelessWidget {
  const AppSection({
    required this.children,
    this.header,
    this.footer,
    this.headerTrailing,
    this.margin,
    super.key,
  });

  final List<Widget> children;

  /// Grouped header: 16/24 semibold, 40pt tall, aligned to the block edge.
  final String? header;

  /// Grouped footer: 14/20 muted, 8 below the block.
  final String? footer;

  /// Optional small action on the header row (a count, a link).
  final Widget? headerTrailing;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const _SectionSeparator());
      rows.add(children[i]);
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
                bottom: AppSpace.x2,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSpace.x8),
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

class _SectionSeparator extends StatelessWidget {
  const _SectionSeparator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppSpace.x3),
    child: SizedBox(
      height: appHairline(context),
      child: ColoredBox(color: context.c.border),
    ),
  );
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
    this.showChevron = false,
    this.destructive = false,
    this.enabled = true,
    this.selected = false,
    this.density = AppRowDensity.regular,
    super.key,
  });

  final String label;

  /// 14/20 muted, 4 below the title.
  final String? description;

  /// A 20pt stroke glyph. Not a coloured tile, not decoration.
  final Widget? leading;

  /// Overrides [value]: a switch, a spinner.
  final Widget? trailing;

  /// Trailing text, capped at 62% of the window so a long value ellipsizes
  /// instead of squeezing the label into a one-character column.
  final String? value;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Only when the row navigates and shows no value.
  final bool showChevron;

  final bool destructive;
  final bool enabled;

  /// Selection is a fill, not a border.
  final bool selected;
  final AppRowDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final titleColor = destructive ? colors.destructive : colors.foreground;
    final trailingSlot = trailing;

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: leading == null
            ? AppSpace.rowMinHeight
            : AppSpace.rowMinHeightLeading,
      ),
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
                  size: 20,
                  color: destructive
                      ? colors.destructive
                      : colors.mutedForeground,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.rowValue(colors.mutedForeground),
                  ),
                ),
              ),
            if (trailingSlot != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.x3),
                child: trailingSlot,
              ),
            if (showChevron && value == null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.x2),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 20,
                  color: colors.foregroundTertiary,
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
        child: content,
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
