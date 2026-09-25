import 'package:flutter/cupertino.dart';

/// Compact HSV picker: saturation/value pad + hue bar + hex field.
/// Calls [onChanged] on every gesture tick so the caller can live-preview
/// (body ink / paper underlay) without a confirm step.
class ReaderColorPicker extends StatefulWidget {
  const ReaderColorPicker({
    required this.color,
    required this.onChanged,
    this.previewLabel,
    super.key,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  /// Optional sample painted in the picked colour (e.g. '正文示例').
  final String? previewLabel;

  @override
  State<ReaderColorPicker> createState() => _ReaderColorPickerState();
}

class _ReaderColorPickerState extends State<ReaderColorPicker> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
    _hex = TextEditingController(text: _hexOf(widget.color));
  }

  @override
  void didUpdateWidget(covariant ReaderColorPicker old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color && !_editingHex) {
      _hsv = HSVColor.fromColor(widget.color);
      _hex.text = _hexOf(widget.color);
    }
  }

  bool _editingHex = false;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _hexOf(Color c) {
    final argb = c.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _emit(Color color) {
    widget.onChanged(color);
  }

  void _setHsv(HSVColor next) {
    setState(() => _hsv = next);
    final color = next.toColor();
    if (!_editingHex) _hex.text = _hexOf(color);
    _emit(color);
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.previewLabel != null)
          Container(
            height: 44,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: current.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: current.withValues(alpha: .35)),
            ),
            child: Text(
              widget.previewLabel!,
              style: TextStyle(
                color: current,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = 140.0;
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: _SvPad(hsv: _hsv, onChanged: _setHsv),
                  ),
                ),
                Positioned(
                  left: (_hsv.saturation * (w - 22)).clamp(0.0, w - 22),
                  top: ((1 - _hsv.value) * (h - 22)).clamp(0.0, h - 22),
                  child: IgnorePointer(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: current,
                        border: Border.all(color: CupertinoColors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const SizedBox(
                  height: 12,
                  width: double.infinity,
                  child: _HueBar(),
                ),
              ),
              Align(
                alignment: Alignment(
                  (_hsv.hue / 180) - 1,
                  0,
                ),
                child: IgnorePointer(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                      border: Border.all(color: CupertinoColors.white, width: 2),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    final box =
                        context.findRenderObject() as RenderBox?;
                    final width = box?.size.width ?? 1;
                    final t = ((d.localPosition.dx) / width).clamp(0.0, 1.0);
                    _setHsv(_hsv.withHue(t * 360));
                  },
                  onTapDown: (d) {
                    final box =
                        context.findRenderObject() as RenderBox?;
                    final width = box?.size.width ?? 1;
                    final t = (d.localPosition.dx / width).clamp(0.0, 1.0);
                    _setHsv(_hsv.withHue(t * 360));
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _hex,
                placeholder: '#RRGGBB',
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                style: const TextStyle(fontSize: 14),
                placeholderStyle: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.secondarySystemFill.resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                onChanged: (v) {
                  _editingHex = true;
                },
                onSubmitted: (v) {
                  final hex = v.trim().replaceFirst('#', '');
                  if (hex.length != 6 && hex.length != 8) {
                    _editingHex = false;
                    return;
                  }
                  final argb = int.tryParse(
                    hex.length == 6 ? 'ff$hex' : hex,
                    radix: 16,
                  );
                  _editingHex = false;
                  if (argb == null) return;
                  _setHsv(HSVColor.fromColor(Color(argb)));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SvPad extends StatelessWidget {
  const _SvPad({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    void handle(dynamic details) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final pos = details.localPosition as Offset;
      final s = (pos.dx / box.size.width).clamp(0.0, 1.0);
      final v = 1 - (pos.dy / box.size.height).clamp(0.0, 1.0);
      onChanged(hsv.withSaturation(s).withValue(v));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: handle,
      onPanUpdate: handle,
      onTapDown: handle,
      child: CustomPaint(painter: _SvPainter(hsv.hue)),
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final sat = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xffffffff), base],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sat);
    final val = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xff000000)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, val);
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) => old.hue != hue;
}

class _HueBar extends StatelessWidget {
  const _HueBar();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HuePainter(),
      size: const Size(double.infinity, 12),
    );
  }
}

class _HuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      for (var h = 0; h <= 360; h += 30)
        HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
    ];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
