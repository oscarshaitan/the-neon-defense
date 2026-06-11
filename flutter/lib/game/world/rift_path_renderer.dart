import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../neon_defense_game.dart';
import '../systems/wave_system.dart';
import '../vfx/render_utils.dart';

/// Rift paths, spawn discs, tier/mutation styling, level pips, and the
/// selected-rift ring — JS 06_render.js:182-254, 392-402.
class RiftPathRenderer extends Component
    with HasGameReference<NeonDefenseGame> {
  final WaveSystem waveSystem;

  RiftPathRenderer(this.waveSystem);

  @override
  void render(Canvas canvas) {
    final frameCount = game.state.frameCount;
    final selectedRift = game.selection.selectedRift;

    for (final rift in waveSystem.rifts) {
      if (rift.points.length < 2) continue;
      final riftLevel = rift.level;
      final mutation = rift.mutation;
      final isHighlighted = identical(rift, selectedRift);

      final pathObj = Path();
      pathObj.moveTo(rift.points.first.x, rift.points.first.y);
      for (int i = 1; i < rift.points.length; i++) {
        pathObj.lineTo(rift.points[i].x, rift.points[i].y);
      }

      // Line color scheme: mutation color > tier-2+ pink > cyan.
      final mutationColor =
          mutation != null ? Color(mutation.colorValue) : null;
      final lineColor = mutationColor ??
          (riftLevel > 1 ? const Color(0xFFFF00AC) : const Color(0xFF00F3FF));

      // 1. Wide glow background — JS lineWidth GRID_SIZE * (1.6 sel / 0.8).
      final glowAlpha = isHighlighted
          ? 0x33
          : (mutation != null ? 0x11 : (riftLevel > 1 ? 0x1A : 0x0D));
      canvas.drawPath(
        pathObj,
        Paint()
          ..color = lineColor.withAlpha(glowAlpha)
          ..strokeWidth = kGridSize * (isHighlighted ? 1.6 : 0.8)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, isHighlighted ? 16 : 8),
      );

      // 2. Dashed center line [10,10].
      _drawDashedPath(
        canvas,
        pathObj,
        Paint()
          ..color = lineColor
          ..strokeWidth = isHighlighted ? 4.0 : 2.0
          ..style = PaintingStyle.stroke,
        10,
        10,
      );

      // 3. Spawn disc — pulse 1 + sin(frameCount*0.1)*0.2; tier-2+/mutated
      // rifts use 1.5x size and their own color.
      final spawn = rift.points.first;
      final pulse = 1 + sin(frameCount * 0.1) * 0.2;
      final spawnColor = mutationColor ??
          (riftLevel > 1 ? const Color(0xFFFF00AC) : const Color(0xFFFF4444));
      final spawnRadius =
          20 * (riftLevel > 1 || mutation != null ? 1.5 : 1.0) * pulse;

      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        spawnRadius,
        Paint()
          ..color = spawnColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * pulse),
      );
      canvas.drawCircle(
          Offset(spawn.x, spawn.y), spawnRadius, Paint()..color = spawnColor);
      canvas.drawCircle(Offset(spawn.x, spawn.y), 10,
          Paint()..color = const Color(0xFF000000));

      // Level pips below the spawn (aligned with the tower pip system).
      if (riftLevel > 1) {
        drawLevelPips(canvas, riftLevel, spawn.x, spawn.y + 30);
      }

      // Selected rift: pink dashed ring r40 + mutation tag.
      if (isHighlighted) {
        drawDashedCircle(
          canvas,
          Offset(spawn.x, spawn.y),
          40,
          Paint()
            ..color = const Color(0xFFFF00AC)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
          5,
          5,
        );
        if (mutation != null) {
          drawWorldLabel(canvas, mutation.name, spawn.x, spawn.y - 30,
              Color(mutation.colorValue), 10);
        }
      }
    }
  }

  void _drawDashedPath(
      Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      bool drawing = true;
      while (dist < metric.length) {
        final len = drawing ? dash : gap;
        final end = (dist + len).clamp(0.0, metric.length);
        if (drawing) canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += len;
        drawing = !drawing;
      }
    }
  }
}
