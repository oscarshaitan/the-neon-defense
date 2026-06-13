import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../neon_defense_game.dart';
import '../entities/base/core_base.dart';
import '../systems/wave_system.dart';
import '../vfx/render_utils.dart';

/// JS spatial-zoning debug overlay (06_render.js:164-209), toggled from the
/// command center: the zone-0 no-rift disc, concentric zone rings every 3
/// cells, and the wide no-build buffer along each rift. Renders only while the
/// overlay flag is on.
class NoBuildOverlay extends Component
    with HasGameReference<NeonDefenseGame> {
  final WaveSystem waveSystem;
  final CoreBase coreBase;

  NoBuildOverlay(this.waveSystem, this.coreBase);

  final Paint _zone0Stroke = Paint()
    ..color = const Color(0x66FF0000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _zone0Fill = Paint()..color = const Color(0x0DFF0000);
  final Paint _ringStroke = Paint()
    ..color = const Color(0x3300F3FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _bufferStroke = Paint()
    ..color = const Color(0x4DFF0000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = kGridSize * 3 // ~1.5 cells each side (JS no-build buffer)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    if (!game.state.noBuildOverlay.value) return;
    final center = Offset(coreBase.position.x, coreBase.position.y);

    // Zone 0 — no-rift commitment radius.
    final zone0 = kZone0RadiusCells * kGridSize;
    canvas.drawCircle(center, zone0, _zone0Fill);
    drawDashedCircle(canvas, center, zone0, _zone0Stroke, 10, 5);

    // Concentric zone rings every 3 cells.
    for (var r = kZone0RadiusCells + 3; r < 60; r += 3) {
      drawDashedCircle(canvas, center, r * kGridSize, _ringStroke, 10, 5);
    }

    // No-build buffer along each rift path.
    for (final rift in waveSystem.rifts) {
      final pts = rift.points;
      if (pts.length < 2) continue;
      final path = Path()..moveTo(pts.first.x, pts.first.y);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].x, pts[i].y);
      }
      canvas.drawPath(path, _bufferStroke);
    }
  }
}
