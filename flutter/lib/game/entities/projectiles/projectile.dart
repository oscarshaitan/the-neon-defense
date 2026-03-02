import 'dart:ui';
import 'package:flame/components.dart';

import '../../entities/enemies/enemy.dart';

class Projectile extends PositionComponent {
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
  }) : super(position: startPos.clone(), size: Vector2.all(4), anchor: Anchor.center);

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
    canvas.drawCircle(
      Offset.zero,
      2,
      Paint()..color = color,
    );
  }
}
