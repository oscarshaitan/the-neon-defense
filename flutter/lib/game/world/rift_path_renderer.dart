import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../neon_defense_game.dart';
import '../systems/pathfinding/rift_generator.dart';
import '../systems/wave_system.dart';
import '../vfx/render_utils.dart';

/// Cached per-rift render geometry. Rift point lists are immutable after
/// generation, so the full path and the dashed center-line segments are
/// built once instead of running computeMetrics/extractPath every frame
/// (hundreds of Path allocations per rift per frame otherwise).
class _RiftGeometry {
  final int pointCount;
  final Path fullPath;
  final Path dashedCenter;
  _RiftGeometry(this.pointCount, this.fullPath, this.dashedCenter);
}

/// Rift paths, spawn discs, tier/mutation styling, level pips, and the
/// selected-rift ring — JS 06_render.js:182-254, 392-402.
class RiftPathRenderer extends Component
    with HasGameReference<NeonDefenseGame> {
  final WaveSystem waveSystem;
  final Expando<_RiftGeometry> _geometryCache = Expando();

  // Paint caches — keys combine color and the few discrete style states.
  final Map<int, Paint> _glowPaints = {};
  final Map<int, Paint> _centerPaints = {};
  final Map<int, Paint> _spawnGlowPaints = {};
  final Map<int, Paint> _fillPaints = {};

  RiftPathRenderer(this.waveSystem);

  Paint _glowPaint(Color color, int alpha, bool highlighted) =>
      _glowPaints.putIfAbsent(
          Object.hash(color.toARGB32(), alpha, highlighted),
          () => Paint()
            ..color = color.withAlpha(alpha)
            ..strokeWidth = kGridSize * (highlighted ? 1.6 : 0.8)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, highlighted ? 20 : 12));

  Paint _centerPaint(Color color, bool highlighted) =>
      _centerPaints.putIfAbsent(Object.hash(color.toARGB32(), highlighted),
          () => Paint()
            ..color = color
            ..strokeWidth = highlighted ? 4.0 : 2.0
            ..style = PaintingStyle.stroke);

  /// Spawn glow blur scales with the pulse; quantizing it to half-pixel
  /// steps keeps the cache tiny while staying visually identical.
  Paint _spawnGlowPaint(Color color, double blur) {
    final quantized = (blur * 2).round();
    return _spawnGlowPaints.putIfAbsent(
        Object.hash(color.toARGB32(), quantized),
        () => Paint()
          ..color = color
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, quantized / 2));
  }

  Paint _fillPaint(Color color) => _fillPaints.putIfAbsent(
      color.toARGB32(), () => Paint()..color = color);

  _RiftGeometry _geometryFor(RiftPath rift, List<Vector2> points) {
    final cached = _geometryCache[rift];
    if (cached != null && cached.pointCount == points.length) return cached;

    final fullPath = Path()..moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length; i++) {
      fullPath.lineTo(points[i].x, points[i].y);
    }

    // Pre-extract the [10,10] dash segments into a single combined Path.
    final dashed = Path();
    for (final metric in fullPath.computeMetrics()) {
      double dist = 0;
      bool drawing = true;
      while (dist < metric.length) {
        final end = (dist + 10).clamp(0.0, metric.length);
        if (drawing) {
          dashed.addPath(metric.extractPath(dist, end), Offset.zero);
        }
        dist += 10;
        drawing = !drawing;
      }
    }

    final geometry = _RiftGeometry(points.length, fullPath, dashed);
    _geometryCache[rift] = geometry;
    return geometry;
  }

  @override
  void render(Canvas canvas) {
    final frameCount = game.state.frameCount;
    final selectedRift = game.selection.selectedRift;

    for (final rift in waveSystem.rifts) {
      if (rift.points.length < 2) continue;
      final riftLevel = rift.level;
      final mutation = rift.mutation;
      final isHighlighted = identical(rift, selectedRift);
      final geometry = _geometryFor(rift, rift.points);

      // Line color scheme: mutation color > tier-2+ pink > cyan.
      final mutationColor =
          mutation != null ? Color(mutation.colorValue) : null;
      final lineColor = mutationColor ??
          (riftLevel > 1 ? const Color(0xFFFF00AC) : const Color(0xFF00F3FF));

      // 1. Wide glow background — JS lineWidth GRID_SIZE * (1.6 sel / 0.8).
      // JS layers a shadowBlur colored halo over the faint trunk; with a single
      // blurred stroke we need a higher alpha or the halo is invisible (the
      // "rifts are only lines" report).
      final glowAlpha = isHighlighted
          ? 0x5C
          : (mutation != null ? 0x30 : (riftLevel > 1 ? 0x3D : 0x24));
      canvas.drawPath(geometry.fullPath,
          _glowPaint(lineColor, glowAlpha, isHighlighted));

      // 2. Dashed center line [10,10] — one drawPath on cached segments.
      canvas.drawPath(
          geometry.dashedCenter, _centerPaint(lineColor, isHighlighted));

      // 3. Spawn disc — pulse 1 + sin(frameCount*0.1)*0.2; tier-2+/mutated
      // rifts use 1.5x size and their own color.
      final spawn = rift.points.first;
      final pulse = 1 + sin(frameCount * 0.1) * 0.2;
      final spawnColor = mutationColor ??
          (riftLevel > 1 ? const Color(0xFFFF00AC) : const Color(0xFFFF4444));
      final spawnRadius =
          20 * (riftLevel > 1 || mutation != null ? 1.5 : 1.0) * pulse;

      canvas.drawCircle(Offset(spawn.x, spawn.y), spawnRadius,
          _spawnGlowPaint(spawnColor, 10 * pulse));
      canvas.drawCircle(
          Offset(spawn.x, spawn.y), spawnRadius, _fillPaint(spawnColor));
      canvas.drawCircle(Offset(spawn.x, spawn.y), 10,
          _fillPaint(const Color(0xFF000000)));

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
}
