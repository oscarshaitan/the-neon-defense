import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

class _ArcBurst {
  double x1 = 0, y1 = 0, x2 = 0, y2 = 0;
  int life = 0; // frames remaining
  int intensity = 1; // 1-5
  bool active = false;
}

/// Renders arc-tower lightning bursts.
/// Intensity 1-5 determines stroke weight and glow.
class ArcLightning extends Component {
  late final List<_ArcBurst> _pool;
  int _poolSize;

  static const int _burstLifeFrames = 8;
  // LCG state for deterministic jitter
  int _lcg = 12345;

  ArcLightning()
      : _poolSize = kQualityProfiles[QualityProfile.high]!.maxArcBursts {
    _pool = List.generate(_poolSize, (_) => _ArcBurst());
  }

  void setProfile(QualityProfile profile) {
    _poolSize = kQualityProfiles[profile]!.maxArcBursts;
  }

  void emit({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    int intensity = 1,
  }) {
    for (int i = 0; i < _poolSize; i++) {
      final b = _pool[i];
      if (!b.active) {
        b
          ..x1 = x1
          ..y1 = y1
          ..x2 = x2
          ..y2 = y2
          ..intensity = intensity.clamp(1, 5)
          ..life = _burstLifeFrames
          ..active = true;
        return;
      }
    }
  }

  @override
  void update(double dt) {
    for (int i = 0; i < _poolSize; i++) {
      final b = _pool[i];
      if (!b.active) continue;
      b.life--;
      if (b.life <= 0) b.active = false;
    }
  }

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < _poolSize; i++) {
      final b = _pool[i];
      if (!b.active) continue;
      _drawBurst(canvas, b);
    }
  }

  void _drawBurst(Canvas canvas, _ArcBurst b) {
    final alpha = ((b.life / _burstLifeFrames) * 200).round().clamp(0, 255);
    final strokeW = 0.5 + b.intensity * 0.4;

    final paint = Paint()
      ..color = Color.fromARGB(alpha, 0x7C, 0xD7, 0xFF)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;

    // Jittered midpoint path (2-3 segments)
    final path = Path();
    path.moveTo(b.x1, b.y1);

    const segments = 3;
    final dx = b.x2 - b.x1;
    final dy = b.y2 - b.y1;

    for (int s = 1; s < segments; s++) {
      final t = s / segments;
      final jitter = (_nextRng() - 0.5) * 12 * b.intensity;
      // Perpendicular jitter
      final px = b.x1 + dx * t + (-dy / _len(dx, dy)) * jitter;
      final py = b.y1 + dy * t + (dx / _len(dx, dy)) * jitter;
      path.lineTo(px, py);
    }
    path.lineTo(b.x2, b.y2);

    canvas.drawPath(path, paint);

    // Extra glow pass for high intensity
    if (b.intensity >= 4) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromARGB(alpha ~/ 3, 0x7C, 0xD7, 0xFF)
          ..strokeWidth = strokeW * 3
          ..style = PaintingStyle.stroke,
      );
    }
  }

  double _len(double dx, double dy) {
    final l = (dx * dx + dy * dy);
    return l > 0 ? l / (l * 0.5 + 0.5) : 1.0; // fast approx
  }

  double _nextRng() {
    _lcg = (_lcg * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_lcg & 0xFFFF) / 0xFFFF;
  }
}
