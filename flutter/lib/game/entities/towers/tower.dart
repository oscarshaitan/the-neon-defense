import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../../world/hardpoint_manager.dart';
import '../enemies/enemy.dart';
import '../projectiles/projectile.dart';

class Tower extends PositionComponent
    with TapCallbacks, HasGameReference<NeonDefenseGame> {
  final TowerType type;
  double damage;
  double range;
  int cooldown; // current cooldown counter (counts down)
  final int maxCooldown;
  final Color color;
  final double baseCost;
  double totalCost;
  int level;

  // Hardpoint bonuses
  final Hardpoint? hardpoint;
  final double scaleMult;

  // Overclock
  bool overclocked = false;
  int overclockTimer = 0;

  // Arc network
  int arcNetworkBonus = 0; // 1-5

  final SpatialGrid spatialGrid;

  bool isSelected = false;

  Tower({
    required Vector2 position,
    required this.type,
    required this.spatialGrid,
    this.hardpoint,
  })  : damage = kTowers[type]!.damage *
            (hardpoint?.damageMult ?? 1.0),
        range = (kTowers[type]!.range *
            (hardpoint?.rangeMult ?? 1.0))
            .clamp(0, 800),
        maxCooldown = kTowers[type]!.cooldown,
        cooldown = 0,
        color = kTowers[type]!.color,
        baseCost = kTowers[type]!.cost,
        totalCost = kTowers[type]!.cost,
        level = 1,
        scaleMult = hardpoint?.scaleMult ?? 1.0,
        super(
          position: position,
          size: Vector2.all(kGridSize * (hardpoint?.scaleMult ?? 1.0)),
          anchor: Anchor.center,
        );

  @override
  void update(double dt) {
    if (overclocked) {
      overclockTimer--;
      if (overclockTimer <= 0) overclocked = false;
    }

    if (cooldown > 0) {
      cooldown--;
      return;
    }

    final target = _findTarget();
    if (target != null) {
      _fire(target);
      final effectiveCooldown = overclocked
          ? (maxCooldown * 0.5).round()
          : maxCooldown;
      cooldown = effectiveCooldown;
    }
  }

  Enemy? _findTarget() {
    final candidates = spatialGrid.queryRadius(position, range);
    if (candidates.isEmpty) return null;
    // Prioritize enemy closest to end of its path (most progress)
    candidates.sort((a, b) => b.pathIndex.compareTo(a.pathIndex));
    return candidates.first;
  }

  void _fire(Enemy target) {
    final projectileSpeed = 6.0;
    final proj = Projectile(
      startPos: position.clone(),
      target: target,
      damage: damage,
      speed: projectileSpeed,
      color: color,
    );
    parent?.add(proj);
  }

  // ---------------------------------------------------------------------------
  // Upgrades
  // ---------------------------------------------------------------------------

  double get upgradeCost => baseCost * 0.5 * level;

  void upgrade() {
    level++;
    damage *= 1.2;
    range = (range * 1.1).clamp(0, 800);
    totalCost += upgradeCost;
  }

  double get sellValue => totalCost * 0.6;

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final halfW = size.x / 2;
    final baseColor = isSelected
        ? color.withAlpha(255)
        : color.withAlpha(200);

    // Draw shape based on type
    switch (type) {
      case TowerType.basic:
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y),
          Paint()..color = baseColor..style = PaintingStyle.fill,
        );
        break;
      case TowerType.rapid:
        canvas.drawCircle(
          Offset.zero, halfW,
          Paint()..color = baseColor..style = PaintingStyle.fill,
        );
        break;
      case TowerType.sniper:
        _drawDiamond(canvas, halfW, baseColor);
        break;
      case TowerType.arc:
        _drawHexagon(canvas, halfW, baseColor);
        break;
    }

    // Level pips
    if (level > 1) {
      for (int i = 0; i < min(level - 1, 5); i++) {
        final pipX = -halfW + 4 + i * 5.0;
        canvas.drawCircle(
          Offset(pipX, halfW + 4),
          2,
          Paint()..color = color,
        );
      }
    }

    // Range ring when selected
    if (isSelected) {
      canvas.drawCircle(
        Offset.zero,
        range,
        Paint()
          ..color = color.withAlpha(30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Overclock pulse
    if (overclocked) {
      canvas.drawCircle(
        Offset.zero,
        halfW + 4 + sin(overclockTimer * 0.2) * 3,
        Paint()
          ..color = const Color(0xAAFCEE0A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawDiamond(Canvas canvas, double halfW, Color c) {
    final path = Path()
      ..moveTo(0, -halfW)
      ..lineTo(halfW, 0)
      ..lineTo(0, halfW)
      ..lineTo(-halfW, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = c);
  }

  void _drawHexagon(Canvas canvas, double halfW, Color c) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = pi / 6 + i * pi / 3;
      final x = halfW * cos(angle);
      final y = halfW * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = c);
  }

  @override
  void onTapDown(TapDownEvent event) {
    game.selectTower(this);
    event.handled = true;
  }
}
