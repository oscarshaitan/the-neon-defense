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
    coreWorldPos = Vector2(
      worldCols * kGridSize / 2,
      worldRows * kGridSize / 2,
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
        worldPos: Vector2(x, y),
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
          worldPos: Vector2(x, y),
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
      final color = hp.type == HardpointType.core
          ? const Color(0x4000F3FF)
          : const Color(0x30FF00AC);
      final ringColor = hp.type == HardpointType.core
          ? const Color(0x8000F3FF)
          : const Color(0x60FF00AC);
      final radius = hp.type == HardpointType.core ? 6.0 : 4.0;

      canvas.drawCircle(
        Offset(hp.worldPos.x, hp.worldPos.y),
        radius,
        Paint()..color = color..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(hp.worldPos.x, hp.worldPos.y),
        kHardpointSnapRadius,
        Paint()..color = ringColor..style = PaintingStyle.stroke..strokeWidth = 0.5,
      );
    }
  }
}
