import 'dart:math';
import 'dart:typed_data';
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
///
/// Render path is allocation-free: jittered points are written into a
/// reused Float32List and drawn with drawRawPoints, and paints are cached
/// per (life, intensity) bucket — only 8x5 combinations exist.
class ArcLightning extends Component {
  late final List<_ArcBurst> _pool;
  int _poolSize;

  static const int _burstLifeFrames = 8;
  static const int _segments = 3;
  // LCG state for deterministic jitter
  int _lcg = 12345;

  // (segments + 1) points x 2 coords, reused across all bursts.
  final Float32List _points = Float32List((_segments + 1) * 2);

  // life (1..8) x intensity (1..5) paint caches.
  final Map<int, Paint> _strokePaints = {};
  final Map<int, Paint> _glowPaints = {};

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

  Paint _strokePaintFor(int life, int intensity) {
    final key = life * 8 + intensity;
    return _strokePaints.putIfAbsent(key, () {
      final alpha =
          ((life / _burstLifeFrames) * 200).round().clamp(0, 255);
      return Paint()
        ..color = Color.fromARGB(alpha, 0x7C, 0xD7, 0xFF)
        ..strokeWidth = 0.5 + intensity * 0.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
    });
  }

  Paint _glowPaintFor(int life, int intensity) {
    final key = life * 8 + intensity;
    return _glowPaints.putIfAbsent(key, () {
      final alpha =
          (((life / _burstLifeFrames) * 200).round() ~/ 3).clamp(0, 255);
      return Paint()
        ..color = Color.fromARGB(alpha, 0x7C, 0xD7, 0xFF)
        ..strokeWidth = (0.5 + intensity * 0.4) * 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
    });
  }

  void _drawBurst(Canvas canvas, _ArcBurst b) {
    final dx = b.x2 - b.x1;
    final dy = b.y2 - b.y1;
    final len = max(1.0, sqrt(dx * dx + dy * dy));

    _points[0] = b.x1;
    _points[1] = b.y1;
    for (int s = 1; s < _segments; s++) {
      final t = s / _segments;
      final jitter = (_nextRng() - 0.5) * 12 * b.intensity;
      // Perpendicular jitter
      _points[s * 2] = b.x1 + dx * t + (-dy / len) * jitter;
      _points[s * 2 + 1] = b.y1 + dy * t + (dx / len) * jitter;
    }
    _points[_segments * 2] = b.x2;
    _points[_segments * 2 + 1] = b.y2;

    canvas.drawRawPoints(
        PointMode.polygon, _points, _strokePaintFor(b.life, b.intensity));

    // Extra glow pass for high intensity — a wider low-alpha stroke, far
    // cheaper than a blur filter.
    if (b.intensity >= 4) {
      canvas.drawRawPoints(
          PointMode.polygon, _points, _glowPaintFor(b.life, b.intensity));
    }
  }

  double _nextRng() {
    _lcg = (_lcg * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_lcg & 0xFFFF) / 0xFFFF;
  }
}
