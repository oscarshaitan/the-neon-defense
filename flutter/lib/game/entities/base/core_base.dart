import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../../vfx/render_utils.dart';
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

  // Static render resources — the base renders every frame.
  static final Path _diamondPath = _diamond(18);
  static final Paint _diamondGlowPaint = Paint()
    ..color = _green
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
  static final Paint _diamondPaint = Paint()
    ..color = _green
    ..style = PaintingStyle.fill;
  static final List<Paint> _shieldPaints = [
    for (var j = 0; j < 4; j++)
      Paint()
        ..color = _green.withValues(alpha: (0.3 + j * 0.2).clamp(0, 1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
  ];
  static final Paint _dronePaint = Paint()..color = const Color(0xFFFFFFFF);

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
    game.gameWorld.particles.createParticles(
        position.x, position.y, const Color(0xFF00FF41), 20); // green heal
    game.audio.playBuild();
    game.saveSystem.save();
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
    game.gameWorld.particles.createParticles(
        position.x, position.y, const Color(0xFF00F3FF), 30); // blue upgrade
    game.audio.playBuild();
    game.saveSystem.save();
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
      game.playShootSfx();
    }
  }

  @override
  void render(Canvas canvas) {
    // Selection ring + range indicator (JS 06_render.js:260-279).
    if (game.selection.selectedBase) {
      drawDashedCircle(
        canvas,
        Offset.zero,
        40,
        Paint()
          ..color = _green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
        5,
        5,
      );
      if (level > 0) {
        canvas.drawCircle(
            Offset.zero, currentRange, Paint()..color = const Color(0x1A00FF41));
        canvas.drawCircle(
          Offset.zero,
          currentRange,
          Paint()
            ..color = const Color(0x4D00FF41)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // Glow layer + solid green diamond — matches JS exactly.
    canvas.drawPath(_diamondPath, _diamondGlowPaint);
    canvas.drawPath(_diamondPath, _diamondPaint);

    // Turret visuals: rotating hex shield layers + orbiting drones
    // (JS 06_render.js:294-341).
    if (level > 0) {
      final time = DateTime.now().millisecondsSinceEpoch / 800;

      final shieldLayers = max(1, level ~/ 3);
      for (var j = 0; j < shieldLayers; j++) {
        final radius = 22.0 + j * 4;
        final dir = j.isEven ? 1.0 : -1.0;
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final angle = (pi / 3) * i + time * dir;
          final hx = cos(angle) * radius;
          final hy = sin(angle) * radius;
          if (i == 0) {
            path.moveTo(hx, hy);
          } else {
            path.lineTo(hx, hy);
          }
        }
        path.close();
        canvas.drawPath(path, _shieldPaints[j.clamp(0, 3)]);
      }

      // Orbiting defense drones — triangles in two orbits (r32 / r45).
      final dronePaint = _dronePaint;
      for (var i = 0; i < level; i++) {
        final orbitIndex = i < 5 ? 0 : 1;
        final orbitCount = i < 5 ? min(level, 5) : level - 5;
        final orbitPos = i < 5 ? i : i - 5;

        final radius = orbitIndex == 0 ? 32.0 : 45.0;
        final orbitTime = orbitIndex == 0 ? time * 2 : -time * 1.5;
        final angle = orbitTime + (orbitPos * (pi * 2 / orbitCount));
        final ox = cos(angle) * radius;
        final oy = sin(angle) * radius;

        canvas.drawPath(
          Path()
            ..moveTo(ox + cos(angle) * 5, oy + sin(angle) * 5)
            ..lineTo(ox + cos(angle + 2.5) * 5, oy + sin(angle + 2.5) * 5)
            ..lineTo(ox + cos(angle - 2.5) * 5, oy + sin(angle - 2.5) * 5)
            ..close(),
          dronePaint,
        );
      }
    }

    // Core pulsing effect (JS: alpha 0.5 + sin(t/200) * 0.3).
    final pulseAlpha =
        (0.5 + sin(DateTime.now().millisecondsSinceEpoch / 200) * 0.3)
            .clamp(0.0, 1.0);
    canvas.drawCircle(Offset.zero, 8,
        Paint()..color = Color.fromRGBO(255, 255, 255, pulseAlpha));
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
