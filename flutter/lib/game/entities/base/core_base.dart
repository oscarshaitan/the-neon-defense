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
    if (level == 0) return; // no turret at level 0

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
        color: kColorNeonBlue,
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
    // Crystal diamond shape
    final halfW = size.x / 2;
    final path = Path()
      ..moveTo(0, -halfW)
      ..lineTo(halfW * 0.6, -halfW * 0.2)
      ..lineTo(halfW * 0.6, halfW * 0.4)
      ..lineTo(0, halfW)
      ..lineTo(-halfW * 0.6, halfW * 0.4)
      ..lineTo(-halfW * 0.6, -halfW * 0.2)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = kColorNeonBlue.withAlpha(180)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = kColorNeonBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Hexagonal shield ring
    _drawHexRing(canvas, halfW * 1.6);

    // Level indicator
    if (level > 0) {
      for (int i = 0; i < level; i++) {
        final angle = -pi / 2 + i * (2 * pi / 10);
        final r = halfW * 1.4;
        canvas.drawCircle(
          Offset(r * cos(angle), r * sin(angle)),
          2.5,
          Paint()..color = kColorNeonBlue,
        );
      }
    }
  }

  void _drawHexRing(Canvas canvas, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = pi / 6 + i * pi / 3;
      final x = r * cos(angle);
      final y = r * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = kColorNeonBlue.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }
}
