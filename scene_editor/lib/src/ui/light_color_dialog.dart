import 'package:flutter/material.dart';

/// The color presets offered for a light source (sRGB). Quick warm/cold
/// light temperatures first, then the saturated accent colors.
const kLightColorPresets = <Color>[
  Color(0xFFFFF2E0), // тёплый «ламповый»
  Color(0xFFFFE3B3), // закат
  Color(0xFFFFFFFF), // нейтральный белый
  Color(0xFFE9F0FF), // холодный дневной
  Color(0xFFFFB45C), // оранжевый
  Color(0xFFFFE14D), // жёлтый
  Color(0xFF7CFF6B), // зелёный
  Color(0xFF4DD7FF), // голубой
  Color(0xFF4D7BFF), // синий
  Color(0xFF8A5CFF), // фиолетовый
  Color(0xFFFF54D8), // розовый
  Color(0xFFFF4D4D), // красный
];

Color lightColorHex(Color c) =>
    Color(0xFF000000 | (c.toARGB32() & 0x00FFFFFF));

String _hexOf(Color c) =>
    '#${(c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? _parseHex(String raw) {
  final s = raw.trim().replaceFirst('#', '');
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// Shows the light color picker dialog; returns the chosen sRGB color (or
/// null when cancelled).
Future<Color?> showLightColorPicker(
  BuildContext context, {
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _LightColorDialog(initial: initial),
  );
}

/// The light color picker: preset swatches, a hue slider, an SV (saturation/
/// value) area, and a hex field. Everything stays in sRGB — the light value
/// conversion to the engine's linear space happens at render time.
class _LightColorDialog extends StatefulWidget {
  final Color initial;
  const _LightColorDialog({required this.initial});

  @override
  State<_LightColorDialog> createState() => _LightColorDialogState();
}

class _LightColorDialogState extends State<_LightColorDialog> {
  late double _hue = HSVColor.fromColor(widget.initial).hue;
  late double _sat = HSVColor.fromColor(widget.initial).saturation;
  late double _val = HSVColor.fromColor(widget.initial).value;
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(lightColorHex(widget.initial)),
  );
  bool _badHex = false;

  Color get _color => HSVColor.fromAHSV(1, _hue, _sat, _val).toColor();

  void _set(Color c) {
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = hsv.hue;
      _sat = hsv.saturation;
      _val = hsv.value;
      _hex.text = _hexOf(lightColorHex(c));
      _badHex = false;
    });
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return AlertDialog(
      backgroundColor: const Color(0xFF262B34),
      title: const Text('Цвет света',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in kLightColorPresets)
                  _Swatch(
                    color: p,
                    selected: color.toARGB32() == p.toARGB32(),
                    onTap: () => _set(p),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                    width: 60,
                    child: Text('Тон',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 12))),
                Expanded(child: _HueSlider(hue: _hue, onChanged: _setHue)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 60,
                    child: Text('Насыщ./ярк.',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 12))),
                Expanded(
                  child: SizedBox(
                    height: 92,
                    child: _SvArea(
                      hue: _hue,
                      sat: _sat,
                      val: _val,
                      onChanged: (s, v) => setState(() {
                        _sat = s;
                        _val = v;
                        _hex.text = _hexOf(_color);
                        _badHex = false;
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Hex',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _badHex ? 'Нужен формат #RRGGBB' : null,
                    ),
                    onSubmitted: _applyHex,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white38),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, lightColorHex(_color)),
          child: const Text('Выбрать'),
        ),
      ],
    );
  }

  void _setHue(double h) {
    setState(() {
      _hue = h;
      _hex.text = _hexOf(_color);
      _badHex = false;
    });
  }

  void _applyHex(String raw) {
    final c = _parseHex(raw);
    if (c == null) {
      setState(() => _badHex = true);
      return;
    }
    _set(c);
  }
}

/// A round preset swatch with a selection border.
class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFF4C9BE8) : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

/// A hue slider (0..360) with a rainbow track.
class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final pos = hue / 360 * w;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onChanged((d.localPosition.dx / w).clamp(0.0, 1.0) * 360),
          onHorizontalDragUpdate: (d) =>
              onChanged(((pos + d.delta.dx) / w).clamp(0.0, 1.0) * 360),
          child: SizedBox(
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: LinearGradient(
                      colors: [
                        for (var i = 0; i <= 12; i++)
                          HSVColor.fromAHSV(1, i * 30, 1, 1).toColor(),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: pos - 5,
                  child: Container(
                    width: 10,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.black45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The saturation/value square of one hue.
class _SvArea extends StatelessWidget {
  final double hue;
  final double sat;
  final double val;
  final void Function(double sat, double val) onChanged;
  const _SvArea({
    required this.hue,
    required this.sat,
    required this.val,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        void apply(Offset p) {
          final s = (p.dx / w).clamp(0.0, 1.0);
          final v = 1 - (p.dy / h).clamp(0.0, 1.0);
          onChanged(s, v);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => apply(d.localPosition),
          onPanDown: (d) => apply(d.localPosition),
          onPanUpdate: (d) => apply(d.localPosition),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SvPainter(base),
                ),
              ),
              Positioned(
                left: sat * w - 7,
                top: (1 - val) * h - 7,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SvPainter extends CustomPainter {
  final Color base;
  _SvPainter(this.base);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    // Desaturation toward white on the left.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(rect),
    );
    // Darkness toward black at the bottom.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.transparent, Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.base != base;
}
