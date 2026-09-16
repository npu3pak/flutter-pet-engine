import 'package:flutter/material.dart';

import 'app_info.dart';

/// Раздел «О приложении»: версии приложения, движка, Flutter и Dart,
/// платформа и графический интерфейс, коммит, дата сборки и краткая история
/// изменений движка.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.info});

  final AppInfo info;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'О приложении',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Приложение-пример показывает возможности движка pet_engine по одной. '
              'Версии записываются вместе с каждым результатом визуальной проверки.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Divider(height: 28),
            _row('Версия приложения', info.appVersion),
            _row('Версия движка', info.engineVersion),
            _row('Версия Flutter', info.flutterVersionLabel),
            _row('Версия Dart', info.dartVersion),
            _row(
              'Платформа и графический интерфейс',
              '${info.platform} · ${info.gpu}',
            ),
            _row('Коммит движка', info.shortCommit),
            _row('Дата сборки', info.buildDateLabel),
            const Divider(height: 28),
            const Text(
              'История изменений движка',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              info.changelog,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 240,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
