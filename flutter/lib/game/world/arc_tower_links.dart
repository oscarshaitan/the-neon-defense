import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../neon_defense_game.dart';
import 'game_world.dart';

/// Renders the connecting bolts between linked arc towers (JS drawArcTowerLinks,
/// 06_render.js:990). Stroke weight/alpha scale with the link strength; the
/// max-strength link gets a neon double-stroke (wide halo + bright core).
/// Paints are cached per strength and lines are drawn one per link, so this is
/// cheap even with many towers.
class ArcTowerLinkRenderer extends Component
    with HasGameReference<NeonDefenseGame> {
  final GameWorld world;
  ArcTowerLinkRenderer(this.world);

  final Map<int, Paint> _linkPaints = {};

  Paint _linkPaint(int strength) => _linkPaints.putIfAbsent(strength, () {
        final s = strength.clamp(1, kArcMaxBonus);
        final alpha = (90 + 34 * s).clamp(0, 255);
        return Paint()
          ..color = Color.fromARGB(alpha, 0x88, 0xD2, 0xFF)
          ..strokeWidth = 1.0 + s * 0.45
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
      });

  static final Paint _maxHalo = Paint()
    ..color = const Color(0x4778D2FF)
    ..strokeWidth = 10
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  static final Paint _maxCore = Paint()
    ..color = const Color(0xF0C8F5FF)
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    final links = world.arcTowerLinks;
    if (links.isEmpty) return;
    for (final l in links) {
      final p1 = Offset(l.a.position.x, l.a.position.y);
      final p2 = Offset(l.b.position.x, l.b.position.y);
      if (l.strength >= kArcMaxBonus) {
        canvas.drawLine(p1, p2, _maxHalo);
        canvas.drawLine(p1, p2, _maxCore);
      } else {
        canvas.drawLine(p1, p2, _linkPaint(l.strength));
      }
    }
  }
}
