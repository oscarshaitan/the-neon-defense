import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../systems/spatial_grid.dart';
import '../projectiles/projectile.dart';

class CoreBase extends PositionComponent {
  int level = 0;
  double baseDamage = 20.0;
  double baseRange = 150.0;
  int baseCooldown = 0;
  final int baseMaxCooldown = 60;

  final SpatialGrid spatialGrid;

  // Green (#00ff41) matching JS game
  static const _green = Color(0xFF00FF41);

  CoreBase({required Vector2 worldCenter, required this.spatialGrid})
      : super(
          position: worldCenter,
          size: Vector2.all(kGridSize * 1.2),
          anchor: Anchor.center,
        );

  double get upgradeCost => 200.0 * (level + 1);
  double get repairCost => 50.0;

  @override
  void update(double dt) {
    if (level == 0) return;

    if (baseCooldown > 0) {
      baseCooldown--;
      return;
    }

    final candidates = spatialGrid.queryRadius(position, baseRange);
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.pathIndex.compareTo(a.pathIndex));
      final target = candidates.first;
      parent?.add(Projectile(
        startPos: position.clone(),
        target: target,
        damage: baseDamage,
        speed: 7.0,
        color: _green,
      ));
      baseCooldown = baseMaxCooldown;
    }
  }

  void upgradeBase() {
    level++;
    baseDamage = 20 + (level - 1) * 10.0;
    baseRange = 150 + (level - 1) * 30.0;
  }

  @override
  void render(Canvas canvas) {
    const r = 18.0;

    // Glow layer
    canvas.drawPath(
      _diamond(r),
      Paint()
        ..color = _green
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Solid green diamond — matches JS exactly
    canvas.drawPath(
      _diamond(r),
      Paint()
        ..color = _green
        ..style = PaintingStyle.fill,
    );

    // Level indicator pips
    if (level > 0) {
      for (int i = 0; i < level; i++) {
        final angle = -pi / 2 + i * (2 * pi / 10);
        final pr = r * 1.8;
        canvas.drawCircle(
          Offset(pr * cos(angle), pr * sin(angle)),
          2.5,
          Paint()..color = _green,
        );
      }
    }
  }

  static Path _diamond(double r) {
    return Path()
      ..moveTo(0, -r)
      ..lineTo(r, 0)
      ..lineTo(0, r)
      ..lineTo(-r, 0)
      ..close();
  }
}
