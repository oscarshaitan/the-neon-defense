import 'dart:ui';
import 'package:flame/components.dart';

import '../../neon_defense_game.dart';
import '../../world/game_world.dart' show RenderLayers;
import '../enemies/enemy.dart';

// Shared per-color paint cache — allocating a Paint per projectile per frame
// is pure GC churn under heavy fire (towers fire every few frames).
final Map<int, Paint> _projectilePaintCache = {};

class Projectile extends PositionComponent
    with HasGameReference<NeonDefenseGame> {
  final Enemy target;
  final double damage;
  final double speed; // world units per frame
  final Color color;

  Projectile({
    required Vector2 startPos,
    required this.target,
    required this.damage,
    required this.speed,
    required this.color,
  }) : super(
          position: startPos.clone(),
          size: Vector2.all(4),
          anchor: Anchor.center,
          priority: RenderLayers.projectiles,
        );

  @override
  void onMount() {
    super.onMount();
    game.entities.projectiles.add(this);
  }

  @override
  void onRemove() {
    game.entities.projectiles.remove(this);
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (target.isDead || target.reachedCore) {
      removeFromParent();
      return;
    }

    final diff = target.position - position;
    final dist = diff.length;

    if (dist <= speed) {
      target.takeDamage(damage);
      removeFromParent();
    } else {
      position.addScaled(diff / dist, speed);
    }
  }

  @override
  void render(Canvas canvas) {
    // Flame's render origin is the component's top-left; center it (matches
    // the other in-world entities so the bullet sits exactly on its position).
    canvas.translate(size.x / 2, size.y / 2);
    canvas.drawCircle(
      Offset.zero,
      2,
      _projectilePaintCache.putIfAbsent(
          color.toARGB32(), () => Paint()..color = color),
    );
  }
}
