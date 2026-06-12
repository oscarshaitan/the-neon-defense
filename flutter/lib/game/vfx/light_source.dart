import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

class _Light {
  double x = 0, y = 0;
  double radius = 0;
  Color color = const Color(0xFFFFFFFF);
  double life = 1.0; // 0..1, counts down
  double decay = 0.03;
  bool active = false;
}

/// Pooled soft-light blobs rendered as radial gradients.
///
/// Gradient shaders are cached per (color, radius, alpha bucket) and built
/// centered at the origin, then positioned with canvas.translate — the JS
/// version caches gradient textures the same way (getLightGradientTexture);
/// building a new shader per light per frame is the expensive path.
class LightSourceSystem extends Component {
  late final List<_Light> _pool;
  int _poolSize;

  static const int _alphaBuckets = 8;
  final Map<int, Paint> _shaderPaints = {};

  LightSourceSystem()
      : _poolSize = kQualityProfiles[QualityProfile.high]!.maxLights {
    _pool = List.generate(_poolSize, (_) => _Light());
  }

  void setProfile(QualityProfile profile) {
    _poolSize = kQualityProfiles[profile]!.maxLights;
  }

  void emit({
    required double x,
    required double y,
    required double radius,
    required Color color,
    double decay = 0.03,
  }) {
    for (int i = 0; i < _poolSize; i++) {
      final l = _pool[i];
      if (!l.active) {
        l
          ..x = x
          ..y = y
          ..radius = radius
          ..color = color
          ..life = 1.0
          ..decay = decay
          ..active = true;
        return;
      }
    }
  }

  @override
  void update(double dt) {
    for (int i = 0; i < _poolSize; i++) {
      final l = _pool[i];
      if (!l.active) continue;
      l.life -= l.decay;
      if (l.life <= 0) l.active = false;
    }
  }

  Paint _paintFor(Color color, double radius, int alphaBucket) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    final key = Object.hash(rgb, radius.round(), alphaBucket);
    if (_shaderPaints.length > 256) _shaderPaints.clear();
    return _shaderPaints.putIfAbsent(key, () {
      final alpha =
          (((alphaBucket + 1) / _alphaBuckets) * 80).round().clamp(0, 80);
      final r = (rgb >> 16) & 0xFF;
      final g = (rgb >> 8) & 0xFF;
      final b = rgb & 0xFF;
      return Paint()
        ..shader = Gradient.radial(
          Offset.zero,
          radius,
          [
            Color.fromARGB(alpha, r, g, b),
            Color.fromARGB(0, r, g, b),
          ],
        );
    });
  }

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < _poolSize; i++) {
      final l = _pool[i];
      if (!l.active) continue;

      final alphaBucket =
          ((l.life * _alphaBuckets).floor()).clamp(0, _alphaBuckets - 1);
      final paint = _paintFor(l.color, l.radius, alphaBucket);

      canvas.save();
      canvas.translate(l.x, l.y);
      canvas.drawCircle(Offset.zero, l.radius, paint);
      canvas.restore();
    }
  }
}
