import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

class TileGrid extends Component {
  final int cols;
  final int rows;

  late final double worldWidth;
  late final double worldHeight;

  static final Paint _gridPaint = Paint()
    ..color = const Color(0x08_00F3FF) // very faint neon blue
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  TileGrid(this.cols, this.rows) {
    worldWidth = cols * kGridSize;
    worldHeight = rows * kGridSize;
  }

  @override
  void render(Canvas canvas) {
    // Frustum culling: only draw lines inside visible bounds.
    // The camera transform is applied by Flame before render() is called,
    // so we draw in world space.
    for (int c = 0; c <= cols; c++) {
      final x = c * kGridSize;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, worldHeight),
        _gridPaint,
      );
    }
    for (int r = 0; r <= rows; r++) {
      final y = r * kGridSize;
      canvas.drawLine(
        Offset(0, y),
        Offset(worldWidth, y),
        _gridPaint,
      );
    }
  }

  // Snap a world position to the nearest grid cell center
  Vector2 snapToGrid(Vector2 worldPos) {
    final col = (worldPos.x / kGridSize).floor();
    final row = (worldPos.y / kGridSize).floor();
    return Vector2(
      col * kGridSize + kGridSize / 2,
      row * kGridSize + kGridSize / 2,
    );
  }

  // Convert world position to grid cell (col, row)
  (int col, int row) worldToCell(Vector2 worldPos) {
    return (
      (worldPos.x / kGridSize).floor().clamp(0, cols - 1),
      (worldPos.y / kGridSize).floor().clamp(0, rows - 1),
    );
  }

  // Convert grid cell to world center
  Vector2 cellToWorld(int col, int row) {
    return Vector2(
      col * kGridSize + kGridSize / 2,
      row * kGridSize + kGridSize / 2,
    );
  }
}
