import 'package:flutter/cupertino.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_type.dart';

/// Form field and search field, specified once.
///
/// A search field is a pill and always carries a leading glyph; a form field is
/// rounded and carries a real label, never a placeholder that disappears.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.controller,
    this.label,
    this.placeholder,
    this.search = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? placeholder;

  /// Pill shape, 40pt tall, leading search glyph, trailing clear button.
  final bool search;

  final bool autofocus;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final radius = search ? AppRadius.pillAll : AppRadius.lgAll;

    final field = DecoratedBox(
      decoration: BoxDecoration(color: colors.secondary, borderRadius: radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: search ? AppSpace.x3 : AppSpace.x4,
            vertical: search ? 0 : AppSpace.x2,
          ),
          child: Row(
            children: [
              if (search) ...[
                Icon(
                  CupertinoIcons.search,
                  size: 18,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: AppSpace.x2),
              ],
              Expanded(
                child: CupertinoTextField.borderless(
                  controller: controller,
                  autofocus: autofocus,
                  maxLines: maxLines,
                  placeholder: placeholder,
                  placeholderStyle: AppText.rowTitle(colors.mutedForeground),
                  style: AppText.rowTitle(
                    search ? colors.foreground : colors.foreground,
                  ),
                  cursorColor: colors.primary,
                  textInputAction: search
                      ? TextInputAction.search
                      : TextInputAction.done,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );

    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.x2),
          child: Text(
            label!,
            style: AppText.rowDescription(colors.mutedForeground),
          ),
        ),
        field,
      ],
    );
  }
}
