import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../enemies/enemy.dart';
import '../projectiles/projectile.dart';

/// The core crystal + optional turret (level > 0).
/// Turret numbers match JS exactly (05_loop.js:1399-1432):
/// damage 20 + (level-1)*10, range 150 + (level-1)*30,
/// cooldown max(8, 35 - level*5), projectile speed 12.
class CoreBase extends PositionComponent
    with HasGameReference<NeonDefenseGame> {
  int level = 0;
  int baseCooldown = 0;

  final SpatialGrid spatialGrid;

  // Green (#00ff41) matching JS game
  static const _green = Color(0xFF00FF41);

  CoreBase({required Vector2 worldCenter, required this.spatialGrid})
      : super(
          position: worldCenter,
          size: Vector2.all(kGridSize * 1.2),
          anchor: Anchor.center,
        );

  double get currentDamage => 20.0 + (level - 1) * 10.0;
  double get currentRange => 150.0 + (level - 1) * 30.0;
  int get currentCooldown => max(8, 35 - level * 5);

  /// JS: 200 * (baseLevel + 1) (01_init.js:519)
  double get upgradeCost => 200.0 * (level + 1);

  /// JS getRepairCost (01_init.js:493-497): $50 base, +$25 per life
  /// bought beyond the starting 20.
  double get repairCost {
    final lives = game.state.lives.value;
    if (lives < 20) return 50;
    return 50.0 + (lives - 20 + 1) * 25;
  }

  bool get canUpgrade => level < 10;

  /// JS repairBase (01_init.js:499-515) — adds TWO lives (played behavior;
  /// the UI label says +1 but the implementation increments twice).
  bool repair() {
    final cost = repairCost;
    if (game.state.money.value < cost) return false;
    game.state.money.value -= cost;
    game.state.lives.value += 2;
    return true;
  }

  /// JS upgradeBase (01_init.js:517-535) — increments level TWICE per
  /// purchase (played behavior; replicated as-is).
  bool upgrade() {
    final cost = upgradeCost;
    if (game.state.money.value < cost || level >= 10) return false;
    game.state.money.value -= cost;
    level++;
    level++;
    return true;
  }

  @override
  void update(double dt) {
    if (level == 0) return;

    if (baseCooldown > 0) baseCooldown--;

    // JS base turret targets the nearest enemy.
    final candidates = spatialGrid.queryRadius(position, currentRange);
    Enemy? target;
    var minDist2 = double.infinity;
    for (final e in candidates) {
      final d2 = e.position.distanceToSquared(position);
      if (d2 < minDist2) {
        minDist2 = d2;
        target = e;
      }
    }

    if (target != null && baseCooldown <= 0) {
      parent?.add(Projectile(
        startPos: position.clone(),
        target: target,
        damage: currentDamage,
        speed: 12.0, // JS spawnProjectile(..., 12, ...) for the base
        color: _green,
      ));
      baseCooldown = currentCooldown;
    }
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
