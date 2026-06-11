import 'dart:ui';
import 'package:flame/components.dart';

import '../../config/constants.dart';
import '../../neon_defense_game.dart';
import '../../systems/spatial_grid.dart';
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
      return;
    }
    if (staticStunTimer > 0) {
      staticStunTimer--;
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
    if (type == EnemyType.splitter) {
      game.gameWorld.spawnMinis(this);
    }
    removeFromParent();
  }

  void _reachCore() {
    reachedCore = true;
    game.state.lives.value -= 1;
    if (game.state.lives.value <= 0) {
      game.gameOver();
    }
    removeFromParent();
  }

  bool get isFrozen => frozenTimer > 0;
  bool get isStunned => staticStunTimer > 0;

  @override
  void render(Canvas canvas) {
    if (isInvisible) return;

    final halfW = width / 2;
    final color = isFrozen
        ? const Color(0xFF88EEFF)
        : isStunned
            ? const Color(0xFFFFFF88)
            : this.color;

    // Body
    canvas.drawCircle(
      Offset.zero,
      halfW,
      Paint()..color = color.withAlpha(200),
    );

    // HP bar (above enemy)
    final barW = width * 1.2;
    final barH = 3.0;
    final barX = -barW / 2;
    final barY = -halfW - 6;
    canvas.drawRect(
      Rect.fromLTWH(barX, barY, barW, barH),
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawRect(
      Rect.fromLTWH(barX, barY, barW * (hp / maxHp), barH),
      Paint()..color = const Color(0xFF00FF41),
    );
  }
}
