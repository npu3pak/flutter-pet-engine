/// Простой измеритель частоты кадров: сглаженное среднее время кадра и
/// подпись, обновляемая раз в полсекунды.
class FpsMeter {
  double _ema = 0;
  double _since = 0;

  String get label {
    final fps = _ema > 0 ? 1 / _ema : 0;
    return '${fps.round()} FPS · ${(_ema * 1000).toStringAsFixed(1)} мс/кадр';
  }

  /// Накапливает кадр; возвращает true, когда подпись пора обновить.
  bool tick(double dt) {
    _since += dt;
    if (_ema == 0) {
      _ema = dt;
    } else {
      _ema += (dt - _ema) * 0.08;
    }
    if (_since < 0.5) return false;
    _since = 0;
    return true;
  }
}
