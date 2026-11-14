import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_shadow.dart';
import '../../theme/app_type.dart';

/// One destination in the floating dock.
@immutable
class AppDockItem {
  const AppDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;

  /// The filled counterpart. Selection is carried by the glyph's own shape and
  /// the indicator behind it, not by colour alone.
  final IconData selectedIcon;

  final String label;
}

/// A floating bottom dock: a translucent capsule that hovers over the page.
///
/// Geometry is owned here (see [AppSpace.dockHeight] and friends) so a page
/// never guesses how much room to leave. The capsule is the only place in the
/// app that blurs what is behind it, and it is deliberately small — a
/// full-screen BackdropFilter would cost a frame every time anything scrolls
/// underneath.
class AppDock extends StatelessWidget {
  const AppDock({
    required this.items,
    required this.index,
    required this.onSelected,
    this.bottomInset = 0,
    super.key,
  });

  final List<AppDockItem> items;
  final int index;
  final ValueChanged<int> onSelected;
  final double bottomInset;

  static const double _iconSize = 24;
  static const double _labelGap = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpace.dockSideInset,
        right: AppSpace.dockSideInset,
        bottom: bottomInset + AppSpace.dockBottomGap,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          // A dock is a thumb target, not a page-wide bar: past this width the
          // items stop being reachable with one hand.
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.dock),
              // A floating overlay is one of the three surfaces the system
              // allows a shadow on (see [AppShadow.overlay]).
              boxShadow: AppShadow.overlay(colors),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.dock),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(AppRadius.dock),
                    border: Border.all(
                      color: colors.border,
                      width: 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
                    ),
                  ),
                  child: SizedBox(
                    height: AppSpace.dockHeight,
                    child: _DockItems(
                      items: items,
                      index: index,
                      onSelected: onSelected,
                      iconSize: _iconSize,
                      labelGap: _labelGap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItems extends StatelessWidget {
  const _DockItems({
    required this.items,
    required this.index,
    required this.onSelected,
    required this.iconSize,
    required this.labelGap,
  });

  final List<AppDockItem> items;
  final int index;
  final ValueChanged<int> onSelected;
  final double iconSize;
  final double labelGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxWidth / items.length;
        const inset = 6.0;

        return Stack(
          children: [
            // The selection indicator sits *behind* the items and travels
            // between them. It is one moving object, so the labels never
            // reflow — only the capsule slides.
            AnimatedPositioned(
              duration: reduceMotion ? Duration.zero : AppMotion.base,
              curve: AppMotion.settle,
              left: slot * index + inset,
              top: 6,
              width: slot - inset * 2,
              height: constraints.maxHeight - 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.xl2),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _DockButton(
                      item: items[i],
                      selected: i == index,
                      onTap: () => onSelected(i),
                      iconSize: iconSize,
                      labelGap: labelGap,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.iconSize,
    required this.labelGap,
  });

  final AppDockItem item;
  final bool selected;
  final VoidCallback onTap;
  final double iconSize;
  final double labelGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    // Selected: full-strength ink. Unselected: the muted role, which is still
    // above the 4.5:1 text floor — an inactive tab is not a disabled one.
    final foreground = selected ? colors.foreground : colors.mutedForeground;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: iconSize,
              color: selected ? colors.primary : foreground,
            ),
            SizedBox(height: labelGap),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The dock label is the smallest type in the product and still
              // sits on the ladder's floor (13), not below it.
              style: AppText.caption(foreground).copyWith(
                height: 1.05,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
