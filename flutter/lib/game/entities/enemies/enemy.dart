import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
import '../../vfx/render_utils.dart';
import '../../world/game_world.dart' show RenderLayers;

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
    final step = speed; // world units per frame

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
    if (isFrozen) dmg *= 1.2; // JS hitEnemy: frozen enemies take +20%
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
    game.state.money.value += reward;
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
    removeFromParent();
  }

  void _reachCore() {
    reachedCore = true;
    game.state.lives.value -= 1;
    game.state.startShake(20); // JS startShake(20) on core breach
    if (game.state.lives.value <= 0) {
      game.gameOver();
    }
    removeFromParent();
  }

  bool get isFrozen => frozenTimer > 0;
  bool get isStunned => staticStunTimer > 0;

  @override
  void render(Canvas canvas) {
    final halfW = width / 2;
    final frameCount = game.state.frameCount;

    // Body — JS per-type silhouettes (06_render.js:420-489).
    final bodyPaint = Paint()
      ..color = isInvisible ? color.withAlpha(51) : color
      ..maskFilter =
          isInvisible ? null : const MaskFilter.blur(BlurStyle.solid, 5);
    switch (type) {
      case EnemyType.tank:
        canvas.drawRect(
            Rect.fromLTWH(-10, -10, 20, 20), bodyPaint);
        break;
      case EnemyType.fast:
        canvas.drawPath(
          Path()
            ..moveTo(0, -12)
            ..lineTo(6, 0)
            ..lineTo(0, 8)
            ..lineTo(-6, 0)
            ..close(),
          bodyPaint,
        );
        break;
      case EnemyType.boss:
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final a = pi * 2 * i / 6;
          final px = halfW * cos(a);
          final py = halfW * sin(a);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, bodyPaint);
        break;
      case EnemyType.splitter:
        canvas.drawPath(
          Path()
            ..moveTo(0, -14)
            ..lineTo(12, 10)
            ..lineTo(-12, 10)
            ..close(),
          bodyPaint,
        );
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
        Paint()..color = const Color(0xE0FFFFFF),
      );
    }

    // HP bar 20x3 at y-15 — only when damaged (JS pass 4).
    if (hp < maxHp) {
      canvas.drawRect(Rect.fromLTWH(-10, -15, 20, 3),
          Paint()..color = const Color(0xFFFF0000));
      canvas.drawRect(
          Rect.fromLTWH(-10, -15, 20 * (hp / maxHp).clamp(0.0, 1.0), 3),
          Paint()..color = const Color(0xFF00FF00));
    }

    // Frozen: cyan ring + 30% frost fill (JS 06_render.js:622-633).
    if (isFrozen) {
      canvas.drawCircle(
        Offset.zero,
        halfW + 2,
        Paint()
          ..color = const Color(0xFF00F3FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
          Offset.zero, halfW, Paint()..color = const Color(0x4D00F3FF));
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
          Paint()
            ..color = const Color(0xE57CD7FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
          3,
          5,
          phase: -frameCount * 0.8 / (r * pulse),
        );
      }

      if (isStunned) {
        canvas.drawCircle(
          Offset.zero,
          (r + 4) * pulse,
          Paint()
            ..color = const Color(0xFFE6F8FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        // Electric starburst — 6 rotating spokes.
        final spokePaint = Paint()
          ..color = const Color(0xE5C4ECFF)
          ..strokeWidth = 1.6;
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
