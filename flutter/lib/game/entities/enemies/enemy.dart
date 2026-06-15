import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../../systems/tech_tree.dart';
import '../../vfx/render_utils.dart';
import '../../world/game_world.dart' show RenderLayers;

/// Body paints are shared across all enemies of a color — allocating a
/// Paint + MaskFilter per enemy per frame costs thousands of allocations
/// per second and the blur is the most expensive part on CanvasKit.
final Map<int, Paint> _bodyPaintCache = {};
final Map<int, Paint> _bodyPaintCacheNoBlur = {};
final Map<int, Paint> _invisiblePaintCache = {};

Paint _bodyPaintFor(Color color, {required bool blur}) {
  final cache = blur ? _bodyPaintCache : _bodyPaintCacheNoBlur;
  return cache.putIfAbsent(color.toARGB32(), () {
    final paint = Paint()..color = color;
    if (blur) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 5);
    }
    return paint;
  });
}

Paint _invisiblePaintFor(Color color) =>
    _invisiblePaintCache.putIfAbsent(
        color.toARGB32(), () => Paint()..color = color.withAlpha(51));

final Paint _eliteMarkerPaint = Paint()..color = const Color(0xE0FFFFFF);
final Paint _hpBarBackPaint = Paint()..color = const Color(0xFFFF0000);
final Paint _hpBarFrontPaint = Paint()..color = const Color(0xFF00FF00);
final Paint _frozenRingPaint = Paint()
  ..color = const Color(0xFF00F3FF)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 3;
final Paint _frostFillPaint = Paint()..color = const Color(0x4D00F3FF);
final Paint _staticRingPaint = Paint()
  ..color = const Color(0xE57CD7FF)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.5;
final Paint _stunRingPaint = Paint()
  ..color = const Color(0xFFE6F8FF)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2.5;
final Paint _stunSpokePaint = Paint()
  ..color = const Color(0xE5C4ECFF)
  ..strokeWidth = 1.6;

// Static body silhouettes (origin-centered) — geometry never changes, so
// building a Path per enemy per frame is pure allocation waste.
final Path _fastKitePath = Path()
  ..moveTo(0, -12)
  ..lineTo(6, 0)
  ..lineTo(0, 8)
  ..lineTo(-6, 0)
  ..close();
final Path _splitterTrianglePath = Path()
  ..moveTo(0, -14)
  ..lineTo(12, 10)
  ..lineTo(-12, 10)
  ..close();
final Map<int, Path> _hexPathCache = {};

Path _hexPathFor(double radius) =>
    _hexPathCache.putIfAbsent((radius * 4).round(), () {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final a = pi * 2 * i / 6;
        final px = radius * cos(a);
        final py = radius * sin(a);
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      return path..close();
    });

class Enemy extends PositionComponent
    with HasGameReference<NeonDefenseGame> {
  final EnemyType type;
  double hp;
  final double maxHp;
  final double speed; // world units / frame (at 60fps)
  final Color color;
  final double reward;
  @override
  final double width;
  final List<Vector2> path;
  final int riftLevel;
  final bool isMutant;
  final String? mutationKey;
  final SpatialGrid spatialGrid;

  int pathIndex = 0;
  bool isDead = false;
  bool reachedCore = false;

  // Status effects
  int frozenTimer = 0;
  double staticCharges = 0;
  int staticStunTimer = 0;
  bool isInvisible = false;
  // Tech CONTROL (Cryo Conductors): chilled enemies move at half speed for a
  // limited number of frames. Distinct from `frozen` (full stop via EMP).
  int chill = 0;

  Enemy({
    required this.type,
    required this.hp,
    required this.speed,
    required this.color,
    required this.reward,
    required this.width,
    required this.path,
    required this.riftLevel,
    required this.spatialGrid,
    this.isMutant = false,
    this.mutationKey,
    Vector2? spawnPos,
    int? startPathIndex,
  })  : maxHp = hp,
        super(
          size: Vector2.all(width),
          anchor: Anchor.center,
          priority: RenderLayers.enemies,
        ) {
    position = spawnPos?.clone() ??
        (path.isNotEmpty ? path[0].clone() : Vector2.zero());
    pathIndex = startPathIndex ?? 0;
  }

  @override
  void onMount() {
    super.onMount();
    spatialGrid.insert(this);
    game.entities.enemies.add(this);
  }

  @override
  void onRemove() {
    spatialGrid.remove(this);
    game.entities.enemies.remove(this);
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (isDead || reachedCore) return;

    // Status: frozen / stun (JS: frozen enemies still tick down stun)
    if (frozenTimer > 0) {
      if (staticStunTimer > 0) staticStunTimer--;
      frozenTimer--;
      // JS frozen trail (05_loop.js:1103): cyan particle every 16 frames.
      if (game.state.frameCount % 16 == 0) {
        game.gameWorld.particles
            .createParticles(position.x, position.y, const Color(0xFF00F3FF), 1, priority: 0);
      }
      return;
    }
    if (staticStunTimer > 0) {
      staticStunTimer--;
      if (game.state.frameCount % 16 == 0) {
        game.gameWorld.particles
            .createParticles(position.x, position.y, const Color(0xFF7CD7FF), 1, priority: 0);
      }
      return;
    }

    if (pathIndex >= path.length) {
      _reachCore();
      return;
    }

    final target = path[pathIndex];
    final diff = target - position;
    final dist = diff.length;
    var step = speed; // world units per frame

    // Tech CONTROL (Cryo Conductors): chilled enemies crawl at 50% speed.
    // Decrement here so the slow wears off; emits a frost trail like frozen.
    if (chill > 0) {
      chill--;
      step *= kTechChillSlow;
      if (game.state.frameCount % 16 == 0) {
        game.gameWorld.particles.createParticles(
            position.x, position.y, const Color(0xFF00F3FF), 1, priority: 0);
      }
    }

    if (dist <= step) {
      final oldPos = position.clone();
      position.setFrom(target);
      spatialGrid.update(this, oldPos);
      pathIndex++;
    } else {
      final oldPos = position.clone();
      position.addScaled(diff / dist, step);
      spatialGrid.update(this, oldPos);
    }

    // Shifter phase cycle — JS: isInvisible = (frameCount % 360) > 180
    if (type == EnemyType.shifter) {
      isInvisible = (game.state.frameCount % 360) > 180;
    }
  }

  void takeDamage(double dmg) {
    final fx = game.tech.fx;
    dmg *= fx.dmgMult; // Tech OFFENSE: global tower damage
    if (isFrozen) dmg *= 1.2; // JS hitEnemy: frozen enemies take +20%
    // Tech CONTROL (Thermal Weakness): chilled/frozen enemies take more.
    if (isFrozen || chill > 0) dmg *= fx.thermalMult;
    // Tech OFFENSE capstone (Executioner): finish low-HP targets.
    if (fx.execute && maxHp > 0 && hp / maxHp <= kTechExecuteThreshold) {
      dmg *= kTechExecuteBonus;
    }
    hp -= dmg;
    if (hp <= 0) _die();
  }

  void applyStaticCharge(double amount) {
    staticCharges += amount;
    if (staticCharges >= kArcStaticThreshold) {
      staticCharges = 0;
      staticStunTimer = kArcStunFrames;
    }
  }

  void freeze(int frames) {
    frozenTimer = frames;
  }

  void _die() {
    isDead = true;
    // JS: money += reward; energy = Math.min(maxEnergy, energy + 1)
    // Tech ECONOMY (Salvage Routines): reward multiplier.
    game.state.money.value += reward * game.tech.fx.rewardMult;
    game.state.addEnergy(1.0);
    game.state.recordKill(type);
    // JS hitEnemy kill effects: 4 particles (priority 2) + light r60.
    game.gameWorld.particles
        .createParticles(position.x, position.y, color, 4, priority: 2);
    game.gameWorld.lights
        .emit(x: position.x, y: position.y, radius: 60, color: color);
    if (type == EnemyType.splitter) {
      game.gameWorld.spawnMinis(this);
    }
    game.audio.playExplosion();
    game.saveSystem.queueAutoSave(); // JS batches combat saves
    removeFromParent();
  }

  void _reachCore() {
    reachedCore = true;
    game.state.lives.value -= 1;
    game.state.startShake(20); // JS startShake(20) on core breach
    game.audio.playHit();
    if (game.state.lives.value <= 0) {
      // Tech CORE capstone (Last Stand Protocol): survive once per run.
      if (game.tech.fx.lastStand && !game.lastStandUsed) {
        game.lastStandUsed = true;
        game.state.lives.value = kTechLastStandLives;
        game.state.showToast('LAST STAND PROTOCOL');
        game.gameWorld.particles.createParticles(
            position.x, position.y, const Color(0xFF00FF41), 30);
      } else {
        game.gameOver();
      }
    }
    removeFromParent();
  }

  bool get isFrozen => frozenTimer > 0;
  bool get isStunned => staticStunTimer > 0;

  @override
  void render(Canvas canvas) {
    // Flame's render origin is the component's top-left; the body is authored
    // around (0,0) = center, so shift to the box centre — otherwise the enemy
    // draws half its width up-left of where it actually walks on the rift.
    canvas.translate(size.x / 2, size.y / 2);

    final halfW = width / 2;
    final frameCount = game.state.frameCount;

    // Body — JS per-type silhouettes (06_render.js:420-489). Paints are
    // cached per color; the glow blur is dropped on the LOW quality
    // profile (it is the dominant per-enemy GPU cost on CanvasKit).
    final lowQuality =
        game.gameWorld.qualityGovernor.currentProfile == QualityProfile.low;
    final bodyPaint = isInvisible
        ? _invisiblePaintFor(color)
        : _bodyPaintFor(color, blur: !lowQuality);
    switch (type) {
      case EnemyType.tank:
        canvas.drawRect(
            Rect.fromLTWH(-10, -10, 20, 20), bodyPaint);
        break;
      case EnemyType.fast:
        canvas.drawPath(_fastKitePath, bodyPaint);
        break;
      case EnemyType.boss:
        canvas.drawPath(_hexPathFor(halfW), bodyPaint);
        break;
      case EnemyType.splitter:
        canvas.drawPath(_splitterTrianglePath, bodyPaint);
        break;
      case EnemyType.mini:
        canvas.drawCircle(Offset.zero, 6, bodyPaint);
        break;
      default:
        canvas.drawCircle(Offset.zero, halfW, bodyPaint);
    }

    if (isInvisible) return; // JS draws nothing else for phased shifters

    // Elite marker — white diamond above (riftLevel > 1).
    if (riftLevel > 1) {
      final mY = -halfW - 8;
      final ms = min(6, 4 + (riftLevel - 1) ~/ 2).toDouble();
      canvas.drawPath(
        Path()
          ..moveTo(0, mY - ms)
          ..lineTo(ms, mY)
          ..lineTo(0, mY + ms)
          ..lineTo(-ms, mY)
          ..close(),
        _eliteMarkerPaint,
      );
    }

    // HP bar 20x3 at y-15 — only when damaged (JS pass 4).
    if (hp < maxHp) {
      canvas.drawRect(Rect.fromLTWH(-10, -15, 20, 3), _hpBarBackPaint);
      canvas.drawRect(
          Rect.fromLTWH(-10, -15, 20 * (hp / maxHp).clamp(0.0, 1.0), 3),
          _hpBarFrontPaint);
    }

    // Frozen: cyan ring + 30% frost fill (JS 06_render.js:622-633).
    if (isFrozen) {
      canvas.drawCircle(Offset.zero, halfW + 2, _frozenRingPaint);
      canvas.drawCircle(Offset.zero, halfW, _frostFillPaint);
    }

    // Static charge / stun rings (JS 06_render.js:654-697).
    final hasStatic = staticCharges > 0;
    if (hasStatic || isStunned) {
      final r = halfW + 8;
      final pulse = 1 + sin(frameCount * 0.35 + position.x * 0.01) * 0.12;

      if (hasStatic) {
        drawDashedCircle(
          canvas,
          Offset.zero,
          r * pulse,
          _staticRingPaint,
          3,
          5,
          phase: -frameCount * 0.8 / (r * pulse),
        );
      }

      if (isStunned) {
        canvas.drawCircle(Offset.zero, (r + 4) * pulse, _stunRingPaint);
        // Electric starburst — 6 rotating spokes.
        final spokePaint = _stunSpokePaint;
        for (var i = 0; i < 6; i++) {
          final a = (pi * 2 * i / 6) + (frameCount * 0.06);
          final outer = r + 9 + (i.isOdd ? 2 : 0);
          canvas.drawLine(
            Offset(cos(a) * (r + 1), sin(a) * (r + 1)),
            Offset(cos(a) * outer, sin(a) * outer),
            spokePaint,
          );
        }
      }
    }
  }
}
