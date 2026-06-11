import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../neon_defense_game.dart';

/// World-space indicator for the selected build target and armed tower type
/// (JS drawBuildTarget / ghost preview, 06_render.js:354-379, 743-778).
/// Functional version — full bracket/ghost styling lands in Phase A3.
class PlacementPreview extends Component
    with HasGameReference<NeonDefenseGame> {
  @override
  void render(Canvas canvas) {
    final target = game.selection.buildTarget;
    if (target == null) return;

    final pulse = 1 + sin(game.state.frameCount * 0.1) * 0.2;
    final half = kGridSize / 2;

    // Tile fill — JS rgba(0,243,255,0.2)
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(target.x, target.y),
          width: kGridSize,
          height: kGridSize),
      Paint()..color = const Color(0x3300F3FF),
    );

    // Pulsing corner brackets
    final ext = half * pulse;
    const len = 8.0;
    final paint = Paint()
      ..color = const Color(0xFF00F3FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final (sx, sy) in const [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]) {
      final cx = target.x + sx * ext;
      final cy = target.y + sy * ext;
      canvas.drawLine(
          Offset(cx, cy), Offset(cx - sx * len, cy), paint);
      canvas.drawLine(
          Offset(cx, cy), Offset(cx, cy - sy * len), paint);
    }
  }
}
