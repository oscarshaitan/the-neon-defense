import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../../systems/tech_tree.dart';
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

  /// Guards the one-time Tech range multiplier in [onMount]. Saved towers
  /// already carry their final range, so [markRestored] sets this to skip it.
  bool _rangeBoosted = false;

  /// Called by SaveSystem for towers restored from disk: their stats are
  /// already final, so the build-time Tech range multiplier must not re-apply.
  void markRestored() => _rangeBoosted = true;

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
    // Tech OFFENSE (Extended Barrels): range multiplier applied once on build,
    // mirroring Godot's def.range * Tech.fx.range_mult (clamped). Skipped for
    // towers restored from a save, which already carry their final range.
    if (!_rangeBoosted) {
      _rangeBoosted = true;
      range = (range * game.tech.fx.rangeMult).clamp(0, kMaxTowerRange);
    }
    game.entities.towers.add(this);
    // Mark on actual (de)registration — Flame add/remove is deferred, so the
    // arc network must be recomputed once the registry truly changes.
    game.gameWorld.markArcNetworkDirty();
  }

  @override
  void onRemove() {
    game.entities.towers.remove(this);
    game.gameWorld.markArcNetworkDirty();
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
    if (type == TowerType.arc) {
      _fireArc(target);
      return;
    }
    final proj = Projectile(
      startPos: position.clone(),
      target: target,
      damage: damage,
      speed: 10.0, // JS spawnProjectile(..., 10, ...) for towers
      color: color,
    );
    parent?.add(proj);
    // JS shoot(): muzzle flash light r40 + throttled shoot SFX.
    game.gameWorld.lights
        .emit(x: position.x, y: position.y, radius: 40, color: color);
    game.playShootSfx();
  }

  /// JS fireArcTower (05_loop.js:1312): an instant lightning chain. Hits the
  /// target, then bounces to nearby enemies, applying static charge (which
  /// stuns at the threshold). The connected-tower network bonus scales the
  /// bolt intensity and static charge.
  void _fireArc(Enemy target) {
    final bonus = arcNetworkBonus.clamp(1, kArcMaxBonus);
    final arc = game.gameWorld.arcLightning;
    arc.emit(
        x1: position.x,
        y1: position.y,
        x2: target.position.x,
        y2: target.position.y,
        intensity: bonus);
    target.takeDamage(damage);
    target.applyStaticCharge(bonus.toDouble());
    // Tech CONTROL (Cryo Conductors): arc attacks chill enemies.
    if (game.tech.fx.arcChill) target.chill = kTechChillFrames;

    final visited = <Enemy>{target};
    var fromX = target.position.x;
    var fromY = target.position.y;
    final bounceDamage = damage * kArcBounceDamageMult;
    for (var i = 0; i < kArcBaseChainTargets; i++) {
      final next = _findArcBounce(fromX, fromY, visited);
      if (next == null) break;
      arc.emit(
          x1: fromX,
          y1: fromY,
          x2: next.position.x,
          y2: next.position.y,
          intensity: bonus);
      next.takeDamage(bounceDamage);
      next.applyStaticCharge(1.0);
      if (game.tech.fx.arcChill) next.chill = kTechChillFrames;
      visited.add(next);
      fromX = next.position.x;
      fromY = next.position.y;
    }
    game.gameWorld.lights
        .emit(x: position.x, y: position.y, radius: 46, color: color);
    game.playShootSfx();
  }

  Enemy? _findArcBounce(double x, double y, Set<Enemy> visited) {
    final candidates = spatialGrid.queryRadius(Vector2(x, y), kArcChainRange);
    Enemy? nearest;
    var minD2 = double.infinity;
    for (final e in candidates) {
      if (e.isDead || e.reachedCore || e.isInvisible || visited.contains(e)) {
        continue;
      }
      final dx = e.position.x - x;
      final dy = e.position.y - y;
      final d2 = dx * dx + dy * dy;
      if (d2 < minD2) {
        minD2 = d2;
        nearest = e;
      }
    }
    return nearest;
  }

  // ---------------------------------------------------------------------------
  // Upgrades
  // ---------------------------------------------------------------------------

  /// Tech effects, resolved safely. The economy getters below are also read by
  /// detached towers in unit tests (no mounted game), where `game` would
  /// assert; `findGame()` returns null instead, so we fall back to neutral
  /// defaults (all multipliers 1.0, sell_refund 0.7).
  TechEffects get _techFx =>
      (findGame() as NeonDefenseGame?)?.tech.fx ?? TechEffects();

  // JS getUpgradeCost, with Tech ECONOMY (Bulk Discount) multiplier applied.
  double get upgradeCost =>
      (baseCost * 0.5 * level * _techFx.upgradeCostMult).floorToDouble();

  void upgrade() {
    final cost = upgradeCost; // capture before level++ (JS: getUpgradeCost called before level++)
    level++;
    damage *= 1.2;
    range = (range * 1.1).clamp(0, kMaxTowerRange);
    totalCost += cost;
  }

  // JS: Math.floor(totalCost * 0.7); Tech ECONOMY (Liquidation) raises the
  // refund fraction (default 0.7, capped at 1.0 by the best unlocked node).
  double get sellValue =>
      (totalCost * _techFx.sellRefund).floorToDouble();

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    // Flame's render canvas origin is the component's top-left, not its
    // center, even with Anchor.center. All shapes below are authored around
    // (0,0) = center (matching the JS draw functions), so shift the origin to
    // the box centre — otherwise towers draw half a cell up-left, landing on
    // the grid intersection instead of inside the cell.
    canvas.translate(size.x / 2, size.y / 2);

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
