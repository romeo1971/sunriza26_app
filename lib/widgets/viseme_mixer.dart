import 'dart:math' as math;

class CriticallyDamped {
  double _y = 0.0;
  double step(double target, double dtMs, {double wn = 14.0}) {
    final a = 1 - math.exp(-wn * dtMs / 1000.0);
    _y += a * (target - _y);
    return _y;
  }
}
