import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../../vfx/render_utils.dart';
import '../../world/game_world.dart' show RenderLayers;
import '../../world/hardpoint_manager.dart';
import '../enemies/enemy.dart';
import '../projectiles/projectile.dart';

class Tower extends PositionComponent
    with HasGameReference<NeonDefenseGame> {
  final TowerType type;
  double damage;
  double range;
  int cooldown; // current cooldown counter (counts down)
  int maxCooldown; // mutable so saves can restore it
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
            .clamp(0, kMaxTowerRange),
        // JS: Math.max(4, towerConfig.cooldown * hardpointRules.cooldownMult)
        maxCooldown = hardpoint != null
            ? max(4, (kTowers[type]!.cooldown * hardpoint.cooldownMult).round())
            : kTowers[type]!.cooldown,
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
          priority: RenderLayers.towers,
        );

  @override
  void onMount() {
    super.onMount();
    game.entities.towers.add(this);
  }

  @override
  void onRemove() {
    game.entities.towers.remove(this);
    super.onRemove();
  }

  @override
  void update(double dt) {
    // JS updateTowers (05_loop.js:1351-1397): overclock doubles the cooldown
    // decrement rate rather than halving maxCooldown.
    var cdRate = 1;
    if (overclocked) {
      cdRate = 2;
      overclockTimer--;
      if (overclockTimer <= 0) overclocked = false;
      // JS overclock trail: yellow particle every 14 frames.
      if (game.state.frameCount % 14 == 0) {
        game.gameWorld.particles.createParticles(
            position.x, position.y, const Color(0xFFFCEE0A), 1, priority: 0);
      }
    }

    if (cooldown > 0) cooldown -= cdRate;

    final target = _findTarget();
    if (target != null && cooldown <= 0) {
      _fire(target);
      cooldown = maxCooldown;
    }
  }

  /// JS targeting: bulwark taunters in range take priority; otherwise the
  /// nearest targetable (non-invisible) enemy.
  Enemy? _findTarget() {
    var candidates = spatialGrid.queryTaunters(position, range);
    if (candidates.isEmpty) {
      candidates = spatialGrid.queryRadius(position, range);
    }
    if (candidates.isEmpty) return null;

    Enemy? nearest;
    var minDist2 = double.infinity;
    for (final e in candidates) {
      final d2 = e.position.distanceToSquared(position);
      if (d2 < minDist2) {
        minDist2 = d2;
        nearest = e;
      }
    }
    return nearest;
  }

  void _fire(Enemy target) {
    final proj = Projectile(
      startPos: position.clone(),
      target: target,
      damage: damage,
      speed: 10.0, // JS spawnProjectile(..., 10, ...) for towers
      color: color,
    );
    parent?.add(proj);
    // JS shoot(): muzzle flash light r40.
    game.gameWorld.lights
        .emit(x: position.x, y: position.y, radius: 40, color: color);
  }

  // ---------------------------------------------------------------------------
  // Upgrades
  // ---------------------------------------------------------------------------

  double get upgradeCost =>
      (baseCost * 0.5 * level).floorToDouble(); // JS getUpgradeCost

  void upgrade() {
    final cost = upgradeCost; // capture before level++ (JS: getUpgradeCost called before level++)
    level++;
    damage *= 1.2;
    range = (range * 1.1).clamp(0, kMaxTowerRange);
    totalCost += cost;
  }

  double get sellValue =>
      (totalCost * 0.7).floorToDouble(); // JS: Math.floor(totalCost * 0.7)

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final frameCount = game.state.frameCount;

    // JS tower silhouettes at exact sizes (drawTowerOne).
    drawTowerShape(canvas, type, 0, 0, color, scaleMult);

    // Level pips — diamond per 5 levels + dot per 1 (JS drawLevelPips).
    if (level > 1) {
      drawLevelPips(canvas, level, 0, 20);
    }

    // Selection: white dashed range circle + fill + 36x36 frame
    // (JS 06_render.js:781-792).
    if (isSelected) {
      canvas.drawCircle(
          Offset.zero, range, Paint()..color = const Color(0x1AFFFFFF));
      drawDashedCircle(
        canvas,
        Offset.zero,
        range,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
        5,
        5,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 36, height: 36),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Overclock pulse — yellow ring + white core (JS 06_render.js:701-717).
    if (overclocked) {
      final pulse = 1 + sin(frameCount * 0.5) * 0.2;
      canvas.drawCircle(
        Offset.zero,
        20 * pulse,
        Paint()
          ..color = const Color(0xFFFCEE0A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
          Offset.zero, 18 * pulse, Paint()..color = const Color(0x4DFFFFFF));
    }
  }
}
