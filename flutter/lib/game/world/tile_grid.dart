import 'dart:ui';
import 'package:flame/components.dart';

import '../config/constants.dart';

class TileGrid extends Component {
  final int cols;
  final int rows;

  late final double worldWidth;
  late final double worldHeight;

  /// The grid is static geometry (~470 line strokes); it is recorded into a
  /// Picture once and replayed per frame instead of issuing every stroke.
  Picture? _gridPicture;

  // Match JS exactly: rgba(255, 255, 255, 0.08) — white, not blue
  static final Paint _gridPaint = Paint()
    ..color = const Color(0x14FFFFFF)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  TileGrid(this.cols, this.rows) {
    worldWidth = cols * kGridSize;
    worldHeight = rows * kGridSize;
  }

  Picture _buildGridPicture() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // Extend grid well beyond world bounds to appear infinite at any zoom level
    const extra = kGridSize * 60.0;
    final startX = -extra;
    final endX = worldWidth + extra;
    final startY = -extra;
    final endY = worldHeight + extra;

    final startCol = (startX / kGridSize).floor();
    final endCol = (endX / kGridSize).ceil();
    final startRow = (startY / kGridSize).floor();
    final endRow = (endY / kGridSize).ceil();

    for (int c = startCol; c <= endCol; c++) {
      final x = c * kGridSize;
      canvas.drawLine(Offset(x, startY), Offset(x, endY), _gridPaint);
    }
    for (int r = startRow; r <= endRow; r++) {
      final y = r * kGridSize;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), _gridPaint);
    }
    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    _gridPicture ??= _buildGridPicture();
    canvas.drawPicture(_gridPicture!);
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
