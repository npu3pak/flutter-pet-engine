import 'package:flutter/material.dart';

/// Заголовок раздела управления фичей.
Widget fcTitle(String text) => Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 4),
  child: Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  ),
);

/// Ползунок с подписью и значением.
Widget fcSlider({
  required String label,
  required double value,
  required double min,
  required double max,
  required ValueChanged<double> onChanged,
  String Function(double value)? format,
}) {
  final text = (format ?? (v) => v.toStringAsFixed(2))(value);
  return Row(
    children: [
      SizedBox(
        width: 118,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ),
    ],
  );
}

/// Переключатель с подписью.
Widget fcSwitch({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
      Switch(value: value, onChanged: onChanged),
    ],
  );
}

/// Выбор одного значения из списка кнопками.
Widget fcChoice<T>({
  required String label,
  required List<T> values,
  required T selected,
  required String Function(T value) labelOf,
  required ValueChanged<T> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(labelOf(value)),
              selected: value == selected,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(value),
            ),
        ],
      ),
    ],
  );
}

/// Кнопка действия.
Widget fcButton(String label, VoidCallback? onPressed) => OutlinedButton(
  style: OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12),
  ),
  onPressed: onPressed,
  child: Text(label),
);

/// Пояснение под управлением.
Widget fcNote(String text) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(
    text,
    style: const TextStyle(color: Colors.white38, fontSize: 11),
  ),
);

/// Строка списка «цвет — подпись».
class LegendEntry {
  const LegendEntry(this.color, this.label);

  final Color color;
  final String label;
}

/// Список соответствий цвета и названия объектов сцены.
Widget fcLegend(List<LegendEntry> entries) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: entry.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Цвет Flutter из тройки sRGB.
Color rgbColor(List<int> rgb) => Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
