import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_icons.dart';

/// Floating control bar while the listen (听书) feature is active.
///
/// Mirrors the notification controls: previous/play-pause/next sentence, the
/// speed preset, and close. A one-line caption shows the sentence being spoken
/// (the reference reader's listening subtitle).
class TtsBar extends StatelessWidget {
  const TtsBar({
    required this.playing,
    required this.positionLabel,
    required this.speed,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onCycleSpeed,
    required this.onClose,
    this.subtitle = '',
    super.key,
  });

  final bool playing;
  final String positionLabel;
  final double speed;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCycleSpeed;
  final VoidCallback onClose;

  /// Current sentence, shown as a one-line caption.
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = context.c.primary;
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: VellumTheme.readerChromeOf(context).withValues(alpha: .97),
              borderRadius: BorderRadius.circular(AppRadius.xl2),
              border: Border.all(color: context.c.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: ink, height: 1.3),
                    ),
                  ),
                Row(
                  children: [
                    _icon(
                      context,
                      AppIcons.backwardEnd,
                      onPrevious,
                      color: muted,
                    ),
                    _icon(
                      context,
                      playing ? AppIcons.pause : AppIcons.play,
                      onPlayPause,
                      color: playing ? accent : ink,
                      size: 30,
                    ),
                    _icon(
                      context,
                      AppIcons.forwardEnd,
                      onNext,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        positionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                    AppTextButton(
                      label: '×${speed.toStringAsFixed(2)}',
                      color: accent,
                      onPressed: onCycleSpeed,
                    ),
                    _icon(
                      context,
                      AppIcons.xmark,
                      onClose,
                      color: muted,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(
    BuildContext context,
    IconData icon,
    VoidCallback onTap, {
    required Color color,
    double size = 24,
  }) => AppPressable(
    onTap: onTap,
    child: SizedBox(
      // 44 square: these four are the only transport controls while a book is
      // being read aloud, and a 36-high target misses under a thumb.
      width: 44,
      height: 44,
      child: Icon(icon, size: size, color: color),
    ),
  );
}