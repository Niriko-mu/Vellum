import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_shadow.dart';
import '../../theme/app_type.dart';
import 'app_controls.dart';
import 'app_section.dart';

/// One pressable in an [AppDialog].
///
/// Actions carry their own result value so callers never have to branch on a
/// label string to work out what was chosen.
class AppDialogAction<T> {
  const AppDialogAction({
    required this.label,
    this.value,
    this.isDestructive = false,
    this.isDefault = false,
  });

  final String label;

  /// Popped when tapped. Null is reserved for "cancelled", so cancel is written
  /// as [AppDialog.cancelLabel] rather than as an action.
  final T? value;

  final bool isDestructive;

  /// Rendered with the accent colour.
  final bool isDefault;
}

/// A decision, not a page.
///
/// Why not CupertinoAlertDialog: on Android that renders an iOS alert — iOS radius,
/// iOS type, iOS button stack — in an app that otherwise speaks its own
/// geometry. A dialog is the one surface a reader cannot scroll past, so it is
/// the worst place to look like another platform.
///
/// The card is the same shape as a sheet's: AppRadius.grouped, no stroke,
/// AppShadow.overlay. Actions are 44pt targets, right-aligned, and only the
/// destructive or default one carries colour.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.cancelLabel,
    this.semanticLabel,
    super.key,
  });

  final String title;

  /// 14/20 muted. One or two sentences: a dialog is a question, not a manual.
  final String? message;

  /// Extra body — a field, a list. Constrained so a long body scrolls instead of
  /// pushing the actions off the screen.
  final Widget? content;

  final List<AppDialogAction<Object?>> actions;

  /// Adds a cancel action that pops null. Omit only when dismissing is not a
  /// valid answer.
  final String? cancelLabel;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final maxHeight = MediaQuery.sizeOf(context).height * .7;

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: semanticLabel ?? title,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x6,
            vertical: AppSpace.x6,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: AppRadius.groupedAll,
                boxShadow: AppShadow.overlay(colors),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.groupedAll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.x5,
                              AppSpace.x5,
                              AppSpace.x5,
                              AppSpace.x4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: AppText.stateTitle(colors.foreground),
                                ),
                                if (message != null) ...[
                                  const SizedBox(height: AppSpace.x2),
                                  Text(
                                    message!,
                                    style: AppText.rowDescription(
                                      colors.mutedForeground,
                                    ),
                                  ),
                                ],
                                if (content != null) ...[
                                  const SizedBox(height: AppSpace.x4),
                                  content!,
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (actions.isNotEmpty || cancelLabel != null)
                      _ActionBar(actions: actions, cancelLabel: cancelLabel),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.actions, required this.cancelLabel});

  final List<AppDialogAction<Object?>> actions;
  final String? cancelLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final ordered = <AppDialogAction<Object?>>[
      if (cancelLabel != null)
        AppDialogAction<Object?>(label: cancelLabel!, value: null),
      ...actions,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: appHairline(context),
          child: ColoredBox(color: colors.border),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x2,
            vertical: AppSpace.x2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final action in ordered)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AppTextButton(
                      label: action.label,
                      size: AppButtonSize.regular,
                      color: action.isDestructive
                          ? colors.destructive
                          : action.isDefault
                          ? colors.primary
                          : colors.foreground,
                      onPressed: () => Navigator.of(context).pop(action.value),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows [AppDialog], popping the tapped action's value; null when dismissed.
///
/// Motion is the product's: settle in, dismiss curve out — the same pair every
/// other overlay uses.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  List<AppDialogAction<T>> actions = const [],
  String? cancelLabel = '取消',
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: title,
    barrierColor: const Color(0x66000000),
    transitionDuration: motionDuration(context, AppMotion.base),
    pageBuilder: (context, _, _) => AppDialog(
      title: title,
      message: message,
      content: content,
      actions: actions,
      cancelLabel: cancelLabel,
    ),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.settle,
        reverseCurve: AppMotion.dismissCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// A yes/no question. A destructive question colours the confirm action and
/// does not sit in the default position.
Future<bool> showAppConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: title,
    message: message,
    cancelLabel: cancelLabel,
    actions: [
      AppDialogAction<bool>(
        label: confirmLabel,
        value: true,
        isDestructive: destructive,
        isDefault: !destructive,
      ),
    ],
  );
  return result ?? false;
}

/// A single acknowledgement, for outcomes the reader must notice. Anything they
/// can act on belongs in the page as AppContentState, not here.
Future<void> showAppNote({
  required BuildContext context,
  required String message,
  String title = '提示',
  String dismissLabel = '好',
}) {
  return showAppDialog<void>(
    context: context,
    title: title,
    message: message,
    cancelLabel: dismissLabel,
  );
}
