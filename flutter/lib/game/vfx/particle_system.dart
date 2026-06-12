import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

class _Particle {
  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double life = 0; // 0..1, counts down
  Color color = const Color(0xFFFFFFFF);
  int priority = 1;
  bool active = false;
}

/// Pooled, batch-rendered particle system matching JS createParticles /
/// updateParticles / particle drawing (05_loop.js:1518-1574,
/// 06_render.js:555-581): velocity (rand-0.5)*5, life 1.0 decaying 0.05
/// per frame, 3x3 rects batched by 8-level quantized alpha.
class ParticleSystem extends Component {
  late final List<_Particle> _pool;
  int _poolSize = 0;
  final _rng = Random();

  ParticleSystem() {
    _poolSize = kQualityProfiles[QualityProfile.high]!.maxParticles;
    _pool = List.generate(_poolSize, (_) => _Particle());
  }

  void setProfile(QualityProfile profile) {
    _poolSize = kQualityProfiles[profile]!.maxParticles;
  }

  /// JS createParticles(x, y, color, count, {priority, speed, life, spread}).
  void createParticles(
    double x,
    double y,
    Color color,
    int count, {
    int priority = 1,
    double speed = 5,
    double life = 1.0,
    double spread = 1.0,
  }) {
    for (var i = 0; i < count; i++) {
      final p = _takeSlot();
      if (p == null) break;
      p
        ..x = x
        ..y = y
        ..vx = (_rng.nextDouble() - 0.5) * speed * spread
        ..vy = (_rng.nextDouble() - 0.5) * speed * spread
        ..color = color
        ..life = life
        ..priority = priority
        ..active = true;
    }
  }

  _Particle? _takeSlot() {
    for (var i = 0; i < _poolSize; i++) {
      if (!_pool[i].active) return _pool[i];
    }
    // Pool full — recycle a low-priority particle if possible.
    for (var i = 0; i < _poolSize; i++) {
      if (_pool[i].priority <= 1) return _pool[i];
    }
    return null;
  }

  @override
  void update(double dt) {
    for (var i = 0; i < _poolSize; i++) {
      final p = _pool[i];
      if (!p.active) continue;
      p.x += p.vx;
      p.y += p.vy;
      p.life -= 0.05; // JS: p.life -= 0.05 per frame, no gravity
      if (p.life <= 0) p.active = false;
    }
  }

  // Persistent render staging: bucket coordinate buffers and paints are
  // reused across frames (one drawRawPoints call per bucket instead of a
  // drawRect per particle, and zero per-frame Map/List/Paint allocations).
  final Map<int, _BucketBuffer> _renderBuckets = {};
  final Map<int, Paint> _bucketPaints = {};

  Paint _paintForBucket(int key) => _bucketPaints.putIfAbsent(key, () {
        final alphaBucket = (key >> 24) & 0xFF;
        final alpha =
            (((alphaBucket + 1) / 8.0) * 255).round().clamp(0, 255);
        final rgb = key & 0x00FFFFFF;
        return Paint()
          ..color = Color.fromARGB(
              alpha, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
          // 3x3 squares via square stroke caps — matches JS rect(x, y, 3, 3).
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.square
          ..style = PaintingStyle.stroke;
      });

  @override
  void render(Canvas canvas) {
    for (final bucket in _renderBuckets.values) {
      bucket.length = 0;
    }

    // Batch by quantized alpha (8 levels) x color.
    for (var i = 0; i < _poolSize; i++) {
      final p = _pool[i];
      if (!p.active) continue;
      final alphaBucket = ((p.life * 8).floor()).clamp(0, 7);
      final rgb = p.color.toARGB32() & 0x00FFFFFF;
      final key = rgb | (alphaBucket << 24);
      // Center of the JS 3x3 corner-anchored rect.
      (_renderBuckets[key] ??= _BucketBuffer()).add(p.x + 1.5, p.y + 1.5);
    }

    for (final entry in _renderBuckets.entries) {
      final bucket = entry.value;
      if (bucket.length == 0) continue;
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(bucket.data, 0, bucket.length),
        _paintForBucket(entry.key),
      );
    }
  }
}

/// Growable Float32List staging buffer reused across frames.
class _BucketBuffer {
  Float32List data = Float32List(64);
  int length = 0;

  void add(double x, double y) {
    if (length + 2 > data.length) {
      final grown = Float32List(data.length * 2);
      grown.setRange(0, data.length, data);
      data = grown;
    }
    data[length++] = x;
    data[length++] = y;
  }
}
