import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, SelectableText;
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_type.dart';
import 'app_pressable.dart';

/// The product's switch, specified once for both platforms.
///
/// 44 × 24, thumb 20, 2pt inner padding. Not `CupertinoSwitch`: a second switch
/// style would be a *chosen* difference, and the shape already carries the state
/// without relying on colour.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? semanticLabel;

  static const double trackWidth = 44;
  static const double trackHeight = 24;
  static const double thumbSize = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final interactive = enabled && onChanged != null;

    return Semantics(
      toggled: value,
      enabled: interactive,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: interactive ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            // The track reports *state*, so it reads the control role, not the
            // accent. Sharing one role is how every toggle ends up shouting the
            // brand colour.
            key: const ValueKey<String>('app-switch-track'),
            duration: motionDuration(context, AppMotion.fast),
            curve: AppMotion.settle,
            width: trackWidth,
            height: trackHeight,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? colors.controlActive : colors.borderSelected,
              borderRadius: AppRadius.pillAll,
            ),
            child: Container(
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                color: colors.constantWhite,
                shape: BoxShape.circle,
                // The white thumb needs its own edge on a light track.
                border: Border.all(
                  color: colors.constantBlack.withValues(alpha: 0.30),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Button variants. One `filled` button per surface: a second filled action
/// becomes `tonal` or `ghost`, because two filled buttons compete.
enum AppButtonVariant { filled, tonal, outline, ghost, destructive }

enum AppButtonSize { small, regular, footer, large }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.size = AppButtonSize.regular,
    this.icon,
    this.pill = false,
    this.busy = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// A 20pt glyph, replaced by a spinner while [busy].
  final IconData? icon;

  /// Prominent, standalone actions are pills; in-form actions are rounded.
  final bool pill;

  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final disabled = onPressed == null;
    final geometry = _geometryOf(size);

    final (Color fill, Color labelColor, Border? border) = switch (variant) {
      AppButtonVariant.filled => (
        colors.primary,
        colors.primaryForeground,
        null,
      ),
      AppButtonVariant.tonal => (
        colors.secondary,
        colors.secondaryForeground,
        null,
      ),
      AppButtonVariant.outline => (
        const Color(0x00000000),
        colors.foreground,
        Border.all(color: colors.border),
      ),
      AppButtonVariant.ghost => (
        const Color(0x00000000),
        colors.foreground,
        null,
      ),
      // F1 keeps the destructive fill as the status red; the label reads its
      // own role instead of borrowing the "chrome over content" constant.
      AppButtonVariant.destructive => (
        colors.destructive,
        colors.destructiveForeground,
        null,
      ),
    };

    final radius = pill ? AppRadius.pillAll : AppRadius.xlAll;

    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: geometry.iconSize,
            height: geometry.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: labelColor,
            ),
          )
        else if (icon != null)
          Icon(icon, size: geometry.iconSize, color: labelColor),
        if (busy || icon != null) SizedBox(width: geometry.gap),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: geometry.labelStyle(labelColor),
          ),
        ),
      ],
    );

    content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: geometry.horizontal,
        vertical: geometry.vertical,
      ),
      child: content,
    );

    if (border != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: content,
      );
    }

    final surface = Opacity(
      opacity: disabled ? 0.4 : 1,
      child: AppPressable(
        onTap: disabled || busy ? null : onPressed,
        enabled: !disabled && !busy,
        borderRadius: radius,
        semanticLabel: label,
        child: DecoratedBox(
          key: const ValueKey<String>('app-button-surface'),
          decoration: BoxDecoration(color: fill, borderRadius: radius),
          child: content,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: !disabled && !busy,
      label: busy ? '$label，处理中' : label,
      child: surface,
    );
  }

  AppButtonGeometry _geometryOf(AppButtonSize size) => switch (size) {
    AppButtonSize.small => const AppButtonGeometry(
      horizontal: AppSpace.x3,
      vertical: AppSpace.x2,
      gap: 6,
      iconSize: 16,
      typeIndex: AppTypeStep.sm,
      weight: FontWeight.w500,
    ),
    AppButtonSize.regular => const AppButtonGeometry(
      horizontal: AppSpace.x4,
      vertical: 10,
      gap: AppSpace.x2,
      iconSize: 20,
      typeIndex: AppTypeStep.base,
      weight: FontWeight.w500,
    ),
    AppButtonSize.footer => const AppButtonGeometry(
      horizontal: AppSpace.x4,
      vertical: AppSpace.x3,
      gap: AppSpace.x2,
      iconSize: 20,
      typeIndex: AppTypeStep.sm,
      weight: FontWeight.w500,
    ),
    AppButtonSize.large => const AppButtonGeometry(
      horizontal: AppSpace.x5,
      vertical: AppSpace.x3,
      gap: 10,
      iconSize: 24,
      typeIndex: AppTypeStep.lg,
      weight: FontWeight.w500,
    ),
  };
}

class AppButtonGeometry {
  const AppButtonGeometry({
    required this.horizontal,
    required this.vertical,
    required this.gap,
    required this.iconSize,
    required this.typeIndex,
    required this.weight,
  });

  final double horizontal;
  final double vertical;
  final double gap;
  final double iconSize;
  final int typeIndex;
  final FontWeight weight;

  TextStyle labelStyle(Color color) {
    final step = AppTypeStep.at(typeIndex);
    return TextStyle(
      color: color,
      fontSize: step.size,
      height: step.heightFactor,
      fontWeight: weight,
      letterSpacing: 0,
    );
  }
}

/// A filter or tag. Chips are selections, not actions — "保存" is a button.
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    this.selected = false,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Semantics(
        selected: selected,
        button: true,
        child: AppPressable(
          onTap: enabled ? onTap : null,
          enabled: enabled,
          borderRadius: AppRadius.pillAll,
          semanticLabel: label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.secondaryActive : colors.secondary,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: selected ? colors.borderSelected : colors.border,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x3,
                vertical: 6,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.chipLabel(colors.foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty, loading and error — one component used everywhere.
///
/// A screen that cannot load or has nothing to show renders this inline; it is
/// never a dialog and never a toast that disappears.
enum AppContentStateKind { loading, empty, error }

class AppContentState extends StatelessWidget {
  const AppContentState({
    required this.kind,
    this.title,
    this.description,
    this.icon,
    this.actions = const [],
    this.compact = false,
    super.key,
  });

  final AppContentStateKind kind;
  final String? title;
  final String? description;
  final IconData? icon;
  final List<Widget> actions;

  /// A state inside a row: no icon disc, smaller padding.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final isError = kind == AppContentStateKind.error;

    if (kind == AppContentStateKind.loading) {
      return Semantics(
        liveRegion: true,
        label: title ?? '正在加载',
        child: Padding(
          padding: EdgeInsets.all(compact ? AppSpace.x4 : AppSpace.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.mutedForeground,
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: AppSpace.x3),
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: AppText.rowDescription(colors.mutedForeground),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpace.x4 : AppSpace.x8,
          vertical: compact ? AppSpace.x4 : AppSpace.x10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null && !compact) ...[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: isError ? colors.destructive : colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpace.x4),
            ],
            if (title != null)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: AppText.stateTitle(
                  isError ? colors.destructive : colors.foreground,
                ),
              ),
            if (description != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                description!,
                textAlign: TextAlign.center,
                style: AppText.rowDescription(colors.mutedForeground),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.x4),
              Wrap(
                spacing: AppSpace.x3,
                runSpacing: AppSpace.x2,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
