import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

enum HardpointType { core, micro }

class Hardpoint {
  final String id;
  final HardpointType type;
  final int col;
  final int row;
  final Vector2 worldPos;
  bool occupied = false;

  Hardpoint({
    required this.id,
    required this.type,
    required this.col,
    required this.row,
    required this.worldPos,
  });

  double get damageMult =>
      type == HardpointType.core ? kCoreDamageMult : kMicroDamageMult;
  double get rangeMult =>
      type == HardpointType.core ? kCoreRangeMult : kMicroRangeMult;
  double get cooldownMult =>
      type == HardpointType.core ? kCoreCooldownMult : kMicroCooldownMult;
  double get scaleMult =>
      type == HardpointType.core ? kCoreScaleMult : kMicroScaleMult;
}

class HardpointManager extends Component {
  final int worldCols;
  final int worldRows;

  final List<Hardpoint> hardpoints = [];
  late final Vector2 coreWorldPos;

  HardpointManager(this.worldCols, this.worldRows);

  @override
  Future<void> onLoad() async {
    // Match JS: Math.floor(cols/2) * GRID_SIZE + GRID_SIZE/2 → always a cell center
    final coreCol = worldCols ~/ 2;
    final coreRow = worldRows ~/ 2;
    coreWorldPos = Vector2(
      coreCol * kGridSize + kGridSize / 2,
      coreRow * kGridSize + kGridSize / 2,
    );
    _buildHardpoints();
  }

  void _buildHardpoints() {
    // Core ring
    for (int i = 0; i < kCoreHardpointCount; i++) {
      final angle = (2 * pi * i / kCoreHardpointCount) - pi / 2;
      final x = coreWorldPos.x + kCoreHardpointRadiusCells * kGridSize * cos(angle);
      final y = coreWorldPos.y + kCoreHardpointRadiusCells * kGridSize * sin(angle);
      final col = (x / kGridSize).round();
      final row = (y / kGridSize).round();
      hardpoints.add(Hardpoint(
        id: 'core_$i',
        type: HardpointType.core,
        col: col,
        row: row,
        worldPos: Vector2(col * kGridSize + kGridSize / 2, row * kGridSize + kGridSize / 2),
      ));
    }

    // Micro rings
    int microIndex = 0;
    for (final ring in kMicroRings) {
      for (int i = 0; i < ring.count; i++) {
        final angle = (2 * pi * i / ring.count) + ring.angleOffset - pi / 2;
        final x = coreWorldPos.x + ring.radiusCells * kGridSize * cos(angle);
        final y = coreWorldPos.y + ring.radiusCells * kGridSize * sin(angle);
        final col = (x / kGridSize).round();
        final row = (y / kGridSize).round();
        hardpoints.add(Hardpoint(
          id: 'micro_$microIndex',
          type: HardpointType.micro,
          col: col,
          row: row,
          worldPos: Vector2(col * kGridSize + kGridSize / 2, row * kGridSize + kGridSize / 2),
        ));
        microIndex++;
      }
    }
  }

  // Find the nearest available hardpoint within snap radius
  Hardpoint? getNearestSnap(Vector2 worldPos) {
    Hardpoint? best;
    double bestDist = kHardpointSnapRadius;
    for (final hp in hardpoints) {
      final d = hp.worldPos.distanceTo(worldPos);
      if (d < bestDist) {
        bestDist = d;
        best = hp;
      }
    }
    return best;
  }

  bool isNearAnyHardpoint(int col, int row, {double radiusCells = 1.5}) {
    final wx = col * kGridSize + kGridSize / 2;
    final wy = row * kGridSize + kGridSize / 2;
    final wPos = Vector2(wx, wy);
    for (final hp in hardpoints) {
      if (hp.worldPos.distanceTo(wPos) < radiusCells * kGridSize) return true;
    }
    return false;
  }

  @override
  void render(Canvas canvas) {
    for (final hp in hardpoints) {
      _renderHardpoint(canvas, hp);
    }
  }

  void _renderHardpoint(Canvas canvas, Hardpoint hp) {
    final isCore = hp.type == HardpointType.core;
    // Match JS: core=green (#00ff41), micro=yellow (#fcee0a)
    const coreColor = Color(0xFF00FF41);
    const microColor = Color(0xFFFCEE0A);
    final ringColor = isCore ? coreColor : microColor;

    // JS: core radius = GRID_SIZE * 0.36, micro = GRID_SIZE * 0.25
    final radius = isCore ? kGridSize * 0.36 : kGridSize * 0.25;
    final strokeWidth = isCore ? 2.4 : 1.8;
    final center = Offset(hp.worldPos.x, hp.worldPos.y);

    if (hp.occupied) {
      // Occupied: dim white ring + fill
      canvas.drawCircle(center, radius,
          Paint()
            ..color = const Color(0x0FFFFFFF)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(center, radius,
          Paint()
            ..color = const Color(0x4DFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth);
    } else {
      // Translucent fill
      canvas.drawCircle(center, radius,
          Paint()
            ..color = ringColor.withAlpha(isCore ? 23 : 20)
            ..style = PaintingStyle.fill);

      // Glow ring (blur layer behind solid)
      canvas.drawCircle(center, radius,
          Paint()
            ..color = ringColor.withAlpha(60)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 3
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

      // Solid ring
      canvas.drawCircle(center, radius,
          Paint()
            ..color = ringColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth);

      // Crosshair at 45% of radius — matches JS exactly
      final cross = radius * 0.45;
      final crossPaint = Paint()
        ..color = isCore
            ? const Color(0xBF00FF41)
            : const Color(0xA6FCEE0A)
        ..strokeWidth = 1.2;
      canvas.drawLine(
          Offset(hp.worldPos.x - cross, hp.worldPos.y),
          Offset(hp.worldPos.x + cross, hp.worldPos.y),
          crossPaint);
      canvas.drawLine(
          Offset(hp.worldPos.x, hp.worldPos.y - cross),
          Offset(hp.worldPos.x, hp.worldPos.y + cross),
          crossPaint);
    }
  }
}
