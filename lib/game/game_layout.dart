import 'dart:ui';

/// Computes gameplay geometry from the current viewport size so everything
/// scales nicely across devices. All values are in logical pixels.
class GameLayout {
  GameLayout(this.size)
      : bandWidth = _band(size),
        _left = (size.width - _band(size)) / 2 {
    laneWidth = bandWidth / 3;
    carSize = laneWidth * 0.96;
    playerCenterY = size.height * 0.80;
  }

  final Size size;
  final double bandWidth;
  final double _left;
  late final double laneWidth;
  late final double carSize;
  late final double playerCenterY;

  static double _band(Size s) {
    final w = s.width * 0.86;
    return w > 560 ? 560 : w;
  }

  double get bandLeft => _left;
  double get bandRight => _left + bandWidth;

  /// Center X of a given lane index (0..2).
  double laneCenterX(int lane) => _left + laneWidth * (lane + 0.5);

  /// Continuous X for an interpolated lane position.
  double laneCenterXf(double lane) => _left + laneWidth * (lane + 0.5);
}
