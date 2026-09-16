import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pet_engine/pet_engine.dart';

import 'scene_host.dart';

/// Правая сворачиваемая панель: только настройки текущей сцены (затенение в
/// стыках, тени, яркость окружения, масштаб отрисовки, сглаживание, фильтр
/// увеличения, туман) и показ частоты кадров. Управление конкретной фичей
/// живёт в рабочей области.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.host,
    required this.showFps,
    required this.onShowFpsChanged,
  });

  final SceneHost host;
  final bool showFps;
  final ValueChanged<bool> onShowFpsChanged;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _ssao = false;
  bool _shadows = false;
  bool _wireframe = false;
  double _ambient = 1.0;
  double _renderScale = 1.0;
  SceneAntiAliasing _aa = SceneAntiAliasing.auto;
  FilterQuality _filter = FilterQuality.none;
  bool _fogOn = false;
  double _fogStart = 1.0;
  double _fogEnd = 12.0;
  double _fogOpacity = 0.6;

  @override
  void initState() {
    super.initState();
    _readFromHost();
  }

  @override
  void didUpdateWidget(SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host.revision != widget.host.revision) _readFromHost();
  }

  void _readFromHost() {
    final settings = widget.host.settings;
    if (settings == null) return;
    _ssao = settings.ssao;
    _shadows = settings.shadows;
    _wireframe = settings.wireframe;
    _ambient = settings.ambient.clamp(0.0, 2.0).toDouble();
    _renderScale = settings.renderScale;
    _aa = settings.antiAliasing;
    _filter = settings.filterQuality;
    _fogOn = settings.fogEnabled;
    _fogStart = settings.fogStart;
    _fogEnd = settings.fogEnd;
    _fogOpacity = settings.fogOpacity;
  }

  static bool get _isTouch =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  double get _scaleMin => _isTouch ? 0.25 : 0.5;
  double get _scaleMax => _isTouch ? 1.0 : 1.5;

  void _applyFog() {
    widget.host.applyFog(
      _fogOn
          ? SceneFog(
              color: const Color(0xFF8C99AD),
              start: _fogStart,
              end: _fogEnd,
              maxOpacity: _fogOpacity,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    return Container(
      color: const Color(0xFF1B1F26),
      child: host.settings == null
          ? const Center(
              child: Text(
                'Сцена ещё не готова',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Настройки сцены',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Настройки применяются к текущей сцене и не зависят от выбранной возможности.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const Divider(height: 20),
                  _switchRow('Затенение в стыках (SSAO)', _ssao, (v) {
                    setState(() => _ssao = v);
                    host.applySsao(v);
                  }, key: const Key('settings-ssao')),
                  _switchRow('Тени от направленного света', _shadows, (v) {
                    setState(() => _shadows = v);
                    host.applyShadows(v);
                  }, key: const Key('settings-shadows')),
                  _switchRow('Wireframe всей сцены', _wireframe, (v) {
                    setState(() => _wireframe = v);
                    host.applyWireframe(v);
                  }, key: const Key('settings-wireframe')),
                  _sliderRow('Яркость окружения', _ambient, 0.0, 2.0, (v) {
                    setState(() => _ambient = v);
                    host.applyAmbient(v);
                  }),
                  const Divider(height: 20),
                  _sliderRow(
                    'Масштаб отрисовки',
                    _renderScale,
                    _scaleMin,
                    _scaleMax,
                    (v) {
                      setState(() => _renderScale = v);
                      host.applyRenderScale(v);
                    },
                  ),
                  const Text(
                    'Сглаживание кромок',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<SceneAntiAliasing>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: SceneAntiAliasing.none,
                        label: Text('ВЫКЛ'),
                      ),
                      ButtonSegment(
                        value: SceneAntiAliasing.fxaa,
                        label: Text('FXAA'),
                      ),
                      ButtonSegment(
                        value: SceneAntiAliasing.msaa,
                        label: Text('MSAA'),
                      ),
                      ButtonSegment(
                        value: SceneAntiAliasing.auto,
                        label: Text('АВТО'),
                      ),
                    ],
                    selected: {_aa},
                    onSelectionChanged: (s) {
                      setState(() => _aa = s.first);
                      host.applyAntiAliasing(s.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Фильтр увеличения',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<FilterQuality>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: FilterQuality.none,
                        label: Text('резкий'),
                      ),
                      ButtonSegment(
                        value: FilterQuality.low,
                        label: Text('мягкий'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) {
                      setState(() => _filter = s.first);
                      host.applyRenderScale(
                        host.settings!.renderScale,
                        filterQuality: s.first,
                      );
                    },
                  ),
                  const Divider(height: 20),
                  _switchRow('Туман', _fogOn, (v) {
                    setState(() => _fogOn = v);
                    _applyFog();
                  }, key: const Key('settings-fog')),
                  if (_fogOn) ...[
                    _sliderRow('начало', _fogStart, 0.0, 20.0, (v) {
                      setState(() => _fogStart = v);
                      _applyFog();
                    }),
                    _sliderRow('конец', _fogEnd, 1.0, 40.0, (v) {
                      setState(() => _fogEnd = v);
                      _applyFog();
                    }),
                    _sliderRow('плотность', _fogOpacity, 0.0, 1.0, (v) {
                      setState(() => _fogOpacity = v);
                      _applyFog();
                    }),
                  ],
                  const Divider(height: 20),
                  _switchRow(
                    'Показывать частоту кадров',
                    widget.showFps,
                    widget.onShowFpsChanged,
                    key: const Key('settings-fps'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _switchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Key? key,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Switch(key: key, value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 110,
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
          width: 36,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    );
  }
}
