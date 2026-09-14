import 'dart:async';

import 'package:flutter/material.dart';

/// Shared compact form controls for the editor panels.

/// Selected color for segmented controls (contrast against the dark panels).
const appSegSelected = Color(0xFF2E5F8F);

/// Consistent style for the app's segmented controls: compact density,
/// transparent when unselected, a contrasting fill when selected.
ButtonStyle appSegmentedStyle({double fontSize = 11}) => ButtonStyle(
      visualDensity: VisualDensity.compact,
      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: fontSize)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? appSegSelected : Colors.transparent,
      ),
    );

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

class NameField extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  const NameField({super.key, required this.initial, required this.onChanged});

  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(NameField old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && _c.text != widget.initial) {
      _c.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
      onChanged: (v) {
        if (v != widget.initial) widget.onChanged(v);
      },
    );
  }
}

class IntField extends StatefulWidget {
  final int initial;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const IntField({
    super.key,
    required this.initial,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<IntField> {
  late final TextEditingController _c = TextEditingController(text: '${widget.initial}');

  @override
  void didUpdateWidget(IntField old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && _c.text != '${widget.initial}') {
      _c.text = '${widget.initial}';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _step(int dir) {
    final base = int.tryParse(_c.text) ?? widget.initial;
    final next = (base + dir).clamp(widget.min, widget.max);
    if (next == base) return;
    _c.text = '$next';
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _c,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration:
                const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null) {
                // Live commit: apply valid integers as they are typed.
                final clamped = n.clamp(widget.min, widget.max);
                if (clamped != widget.initial) widget.onChanged(clamped);
              }
            },
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null) {
                final clamped = n.clamp(widget.min, widget.max);
                _c.text = '$clamped';
                widget.onChanged(clamped);
              } else {
                _c.text = '${widget.initial}';
              }
            },
          ),
        ),
        _SpinnerButtons(step: 1, onStep: (d) => _step(d.toInt())),
      ],
    );
  }
}

class DoubleField extends StatefulWidget {
  final double initial;
  final double step;
  final ValueChanged<double> onChanged;

  /// Число знаков после запятой при отображении и шаге спиннера. Точность
  /// вершин/масштаба многогранника — 4 знака; обычные поля — 2.
  final int precision;

  const DoubleField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.step = 0.1,
    this.precision = 2,
  });

  @override
  State<DoubleField> createState() => _DoubleFieldState();
}

class _DoubleFieldState extends State<DoubleField> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.initial));

  String _fmt(double v) => fmtDouble(v, precision: widget.precision);

  @override
  void didUpdateWidget(DoubleField old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && _c.text != _fmt(widget.initial)) {
      _c.text = _fmt(widget.initial);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _step(double dir) {
    final base = parseDoubleInput(_c.text) ?? widget.initial;
    final next = double.parse(
      (base + dir * widget.step).toStringAsFixed(widget.precision),
    );
    if (next == base) return;
    _c.text = _fmt(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration:
                const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onChanged: (v) {
              // Live commit: apply as soon as the input parses to a complete
              // number; incomplete states ("1.", "-", empty) are left alone.
              final n = parseDoubleInput(v);
              if (n != null && n != widget.initial) widget.onChanged(n);
            },
            onSubmitted: (v) {
              final n = parseDoubleInput(v);
              if (n != null) {
                _c.text = _fmt(n);
                widget.onChanged(n);
              } else {
                _c.text = _fmt(widget.initial);
              }
            },
          ),
        ),
        _SpinnerButtons(step: widget.step, onStep: _step),
      ],
    );
  }
}

/// Formats a value compactly: whole numbers without decimals, fractions
/// with up to [precision] places and trailing zeros stripped ("1.1", "0.25",
/// "3"; with precision 4 — "0.0625").
String fmtDouble(double v, {int precision = 2}) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(precision).replaceFirst(RegExp(r'0+$'), '');
}

/// Parses a numeric input, treating ',' as the decimal separator. Returns
/// null for incomplete or invalid input ("1.", "-", "abc", "").
double? parseDoubleInput(String v) {
  if (v.trim().isEmpty) return null;
  // "1." and "-" are incomplete states while typing.
  if (v.endsWith('.') || v.endsWith('-')) return null;
  final n = double.tryParse(v.replaceAll(',', '.'));
  if (n == null) return null;
  if (!n.isFinite) return null;
  return n;
}

/// Vertical Windows-style spinner (▲/▼) on the right of a numeric field.
/// A click steps once; holding the button keeps stepping after a short
/// delay (350 ms), then every 80 ms. The step amount is [step] (can be
/// negative); the buttons adjust the field by +step / −step.
class _SpinnerButtons extends StatelessWidget {
  final double step;
  final ValueChanged<double> onStep;
  const _SpinnerButtons({required this.step, required this.onStep});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SpinnerButton(
            icon: Icons.arrow_drop_up,
            tooltip: 'Увеличить на ${_fmt(step)}',
            onStep: () => onStep(1),
          ),
          _SpinnerButton(
            icon: Icons.arrow_drop_down,
            tooltip: 'Уменьшить на ${_fmt(step)}',
            onStep: () => onStep(-1),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => fmtDouble(v);
}

/// One spinner arrow with hold-to-repeat behavior.
class _SpinnerButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onStep;
  const _SpinnerButton({
    required this.icon,
    required this.tooltip,
    required this.onStep,
  });

  @override
  State<_SpinnerButton> createState() => _SpinnerButtonState();
}

class _SpinnerButtonState extends State<_SpinnerButton> {
  static const _initialDelay = Duration(milliseconds: 350);
  static const _repeatInterval = Duration(milliseconds: 80);
  Timer? _timer;

  void _start() {
    widget.onStep();
    _timer = Timer(_initialDelay, () {
      widget.onStep();
      _timer = Timer.periodic(_repeatInterval, (_) => widget.onStep());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: Ink(
          height: 20,
          width: 22,
          decoration: const BoxDecoration(
            color: Color(0xFF2E333D),
            border: Border(bottom: BorderSide(color: Color(0xFF3A4250))),
          ),
          child: Icon(widget.icon, size: 16, color: Colors.white70),
        ),
      ),
    );
  }
}
