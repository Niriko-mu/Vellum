import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';
import '../theme/app_shape.dart';

/// Stage + optional determinate progress for import / format conversion.
class ConversionProgress extends StatelessWidget {
  const ConversionProgress({
    required this.stage,
    this.value,
    this.caption,
    super.key,
  });

  final String stage;

  /// 0..1 when determinate; null shows an indeterminate bar.
  final double? value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final clamped = value?.clamp(0.0, 1.0);
    final percent = clamped == null ? null : (clamped * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stage.isEmpty ? '处理中…' : stage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: VellumTheme.inkOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (percent != null)
              Text('$percent%', style: TextStyle(color: muted, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: VellumTheme.softAccentOf(context)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 180),
                    widthFactor:
                        clamped ??
                        (stage.isEmpty
                            ? 0.08
                            : 0.35 + ((stage.hashCode % 40) / 100)),
                    child: ColoredBox(color: accent),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (caption != null && caption!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            style: TextStyle(color: muted, fontSize: 13, height: 1.35),
          ),
        ],
      ],
    );
  }
}