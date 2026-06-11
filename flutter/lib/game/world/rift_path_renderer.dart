import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../systems/wave_system.dart';

/// Draws rift paths and spawn discs as their own render layer so they sit
/// between the grid and the base, matching the JS draw() order
/// (06_render.js: grid -> paths -> base -> ...).
class RiftPathRenderer extends Component {
  final WaveSystem waveSystem;

  RiftPathRenderer(this.waveSystem);

  @override
  void render(Canvas canvas) {
    for (final rift in waveSystem.rifts) {
      if (rift.points.length < 2) continue;

      final pathObj = Path();
      pathObj.moveTo(rift.points.first.x, rift.points.first.y);
      for (int i = 1; i < rift.points.length; i++) {
        pathObj.lineTo(rift.points[i].x, rift.points[i].y);
      }

      // 1. Wide glow background — matches JS lineWidth = GRID_SIZE * 0.8
      canvas.drawPath(
        pathObj,
        Paint()
          ..color = const Color(0x0D00F3FF) // rgba(0,243,255,0.05)
          ..strokeWidth = kGridSize * 0.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // 2. Thin dashed center line — matches JS lineWidth=2, setLineDash([10,10])
      _drawDashed(
        canvas,
        pathObj,
        Paint()
          ..color = const Color(0xFF00F3FF)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
        10,
        10,
      );

      // 3. Spawn circle at path start — matches JS arc(20), inner black arc(10)
      final spawn = rift.points.first;
      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        20,
        Paint()
          ..color = const Color(0xFFFF4444)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        20,
        Paint()
          ..color = const Color(0xFFFF4444)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(spawn.x, spawn.y),
        10,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawDashed(
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
