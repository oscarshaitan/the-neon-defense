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
class LightSourceSystem extends Component {
  late final List<_Light> _pool;
  int _poolSize;

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

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < _poolSize; i++) {
      final l = _pool[i];
      if (!l.active) continue;

      final alpha = (l.life * 80).round().clamp(0, 80);
      final r = (l.color.r * 255).round();
      final g = (l.color.g * 255).round();
      final b = (l.color.b * 255).round();

      final shader = Gradient.radial(
        Offset(l.x, l.y),
        l.radius,
        [
          Color.fromARGB(alpha, r, g, b),
          Color.fromARGB(0, r, g, b),
        ],
      );

      canvas.drawCircle(
        Offset(l.x, l.y),
        l.radius,
        Paint()..shader = shader,
      );
    }
  }
}
