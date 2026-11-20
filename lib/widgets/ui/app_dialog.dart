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
    this.valueBuilder,
    this.enabledBuilder,
    this.isDestructive = false,
    this.isDefault = false,
  });

  final String label;

  /// Popped when tapped. Null is reserved for "cancelled", so cancel is written
  /// as [AppDialog.cancelLabel] rather than as an action.
  final T? value;

  /// Read at the moment of the tap, for an action whose result depends on what
  /// the reader has typed or chosen inside the dialog.
  ///
  /// [value] cannot do this job: the action list is built once, when the dialog
  /// opens, so a value read there is whatever the field held *before* anyone
  /// could touch it — which is how "新建文件夹" popped an empty name and
  /// "设置备份密码" reported that no password had been entered.
  final T Function()? valueBuilder;

  /// Whether the action is available right now. Re-evaluated when the dialog's
  /// body reports a change (see [AppDialog.contentChanged]) and on every tap,
  /// so "确定" is not offered for an empty field.
  final bool Function()? enabledBuilder;

  final bool isDestructive;

  /// Rendered with the accent colour.
  final bool isDefault;

  /// The value this action carries at this instant.
  T? valueNow() => valueBuilder != null ? valueBuilder!() : value;

  /// Whether this action can be taken at this instant.
  bool enabledNow() => enabledBuilder?.call() ?? true;
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
class AppDialog extends StatefulWidget {
  const AppDialog({
    required this.title,
    this.message,
    this.content,
    this.contentController,
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

  /// The field inside [content], when the action's availability depends on what
  /// it holds. Watching it here is what makes "创建" enable itself the moment
  /// the name is typed, instead of offering an action that would pop "".
  final TextEditingController? contentController;

  final List<AppDialogAction<Object?>> actions;

  /// Adds a cancel action that pops null. Omit only when dismissing is not a
  /// valid answer.
  final String? cancelLabel;

  final String? semanticLabel;

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final maxHeight = MediaQuery.sizeOf(context).height * .7;
    final title = widget.title;
    final message = widget.message ?? '';
    final content = widget.content;
    final controller = widget.contentController;

    // A function, not a value: the tree is rebuilt on every keystroke in the
    // body so an action's enabledBuilder is re-read. That is what makes the
    // confirm button light up as soon as the name stops being empty.
    Widget body() => Column(
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
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.x2),
                      Text(
                        message,
                        style: AppText.rowDescription(colors.mutedForeground),
                      ),
                    ],
                    if (content != null) ...[
                      const SizedBox(height: AppSpace.x4),
                      content,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.actions.isNotEmpty || widget.cancelLabel != null)
          _ActionBar(
            actions: widget.actions,
            cancelLabel: widget.cancelLabel,
          ),
      ],
    );

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: widget.semanticLabel ?? title,
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
                child: controller == null
                    ? body()
                    : ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) => body(),
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
                      // Read at the tap, not when the dialog opened: a field's
                      // current text is the whole answer for "创建"/"保存".
                      onPressed: action.enabledNow()
                          ? () =>
                                Navigator.of(context).pop(action.valueNow())
                          : null,
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
  TextEditingController? contentController,
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
      contentController: contentController,
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
