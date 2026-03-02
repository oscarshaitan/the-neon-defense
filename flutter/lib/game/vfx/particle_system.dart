import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

class _Particle {
  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double life = 0; // 0..1, counts down
  double decay = 0;
  Color color = const Color(0xFFFFFFFF);
  bool active = false;
}

/// Pooled, batch-rendered particle system.
/// All particles are rendered in a single Component to minimize canvas state changes.
class ParticleSystem extends Component {
  late final List<_Particle> _pool;
  int _poolSize = 0;

  ParticleSystem() {
    _poolSize = kQualityProfiles[QualityProfile.high]!.maxParticles;
    _pool = List.generate(_poolSize, (_) => _Particle());
  }

  void setProfile(QualityProfile profile) {
    _poolSize = kQualityProfiles[profile]!.maxParticles;
  }

  void emit({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required Color color,
    double life = 1.0,
    double decay = 0.02,
  }) {
    // Find a free slot in the pool
    for (int i = 0; i < _poolSize; i++) {
      final p = _pool[i];
      if (!p.active) {
        p
          ..x = x
          ..y = y
          ..vx = vx
          ..vy = vy
          ..color = color
          ..life = life
          ..decay = decay
          ..active = true;
        return;
      }
    }
    // Pool full — overwrite oldest (first active one found)
    for (int i = 0; i < _poolSize; i++) {
      final p = _pool[i];
      if (p.active) {
        p
          ..x = x
          ..y = y
          ..vx = vx
          ..vy = vy
          ..color = color
          ..life = life
          ..decay = decay;
        return;
      }
    }
  }

  /// Convenience: emit a burst of particles from a hit point.
  void emitBurst({
    required double x,
    required double y,
    required Color color,
    int count = 6,
    double speed = 1.5,
  }) {
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 6.283;
      emit(
        x: x,
        y: y,
        vx: speed * _cos(angle),
        vy: speed * _sin(angle),
        color: color,
        decay: 0.025 + _rng() * 0.02,
      );
    }
  }

  @override
  void update(double dt) {
    for (int i = 0; i < _poolSize; i++) {
      final p = _pool[i];
      if (!p.active) continue;
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.05; // slight gravity
      p.life -= p.decay;
      if (p.life <= 0) p.active = false;
    }
  }

  @override
  void render(Canvas canvas) {
    // Batch by color bucket (alpha-quantized)
    // Group into alpha buckets and draw each bucket with one paint
    final buckets = <int, List<_Particle>>{};
    for (int i = 0; i < _poolSize; i++) {
      final p = _pool[i];
      if (!p.active) continue;
      // Alpha bucket: quantize life to 8 levels
      final alphaBucket = ((p.life * 8).floor()).clamp(0, 7);
      final rgb = p.color.toARGB32() & 0x00FFFFFF;
      final key = rgb | (alphaBucket << 24);
      buckets.putIfAbsent(key, () => []).add(p);
    }

    for (final entry in buckets.entries) {
      final alphaBucket = (entry.key >> 24) & 0xFF;
      final alpha = ((alphaBucket / 7.0) * 220).round().clamp(0, 255);
      final rgb = entry.key & 0x00FFFFFF;
      final paint = Paint()
        ..color = Color.fromARGB(alpha, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
        ..style = PaintingStyle.fill;

      for (final p in entry.value) {
        canvas.drawCircle(Offset(p.x, p.y), 2, paint);
      }
    }
  }

  // Minimal math helpers (avoids dart:math import for perf)
  static double _cos(double a) {
    // Simple approximation via sin shift
    return _sin(a + 1.5707963);
  }

  static double _sin(double a) {
    // Clamp to [-π, π] then use polynomial
    a = a % 6.283185;
    if (a < 0) a += 6.283185;
    if (a > 3.14159) a -= 6.283185;
    final a2 = a * a;
    return a * (1 - a2 / 6 * (1 - a2 / 20));
  }

  static double _rngSeed = 0.5;
  static double _rng() {
    _rngSeed = (_rngSeed * 16807 + 1) % 2147483647 / 2147483647;
    return _rngSeed;
  }
}
