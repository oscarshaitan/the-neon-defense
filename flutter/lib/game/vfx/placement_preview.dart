import 'dart:ui';

import 'package:flame/components.dart';

import '../config/constants.dart';
import '../neon_defense_game.dart';
import 'render_utils.dart';

/// Build-target brackets and tower ghost preview, matching JS exactly
/// (06_render.js:354-379 build target, 743-778 ghost preview).
class PlacementPreview extends Component
    with HasGameReference<NeonDefenseGame> {
  @override
  void render(Canvas canvas) {
    final target = game.selection.buildTarget;
    if (target == null) return;

    final btx = target.x - kGridSize / 2;
    final bty = target.y - kGridSize / 2;

    // Corner brackets (10 px legs) + 20%-alpha cyan fill.
    final bracket = Paint()
      ..color = const Color(0xFF00F3FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const g = kGridSize;
    final corners = Path()
      // Top-left
      ..moveTo(btx + 10, bty)
      ..lineTo(btx, bty)
      ..lineTo(btx, bty + 10)
      // Top-right
      ..moveTo(btx + g - 10, bty)
      ..lineTo(btx + g, bty)
      ..lineTo(btx + g, bty + 10)
      // Bottom-right
      ..moveTo(btx + g, bty + g - 10)
      ..lineTo(btx + g, bty + g)
      ..lineTo(btx + g - 10, bty + g)
      // Bottom-left
      ..moveTo(btx, bty + g - 10)
      ..lineTo(btx, bty + g)
      ..lineTo(btx + 10, bty + g);
    canvas.drawPath(corners, bracket);
    canvas.drawRect(Rect.fromLTWH(btx, bty, g, g),
        Paint()..color = const Color(0x3300F3FF));

    // Ghost preview when a tower type is armed for this target.
    final type = game.selection.selectedTowerType;
    if (type == null) return;

    final validation = game.placement.validate(target, type);
    final def = kTowers[type]!;
    final previewScale = validation.hardpoint?.scaleMult ?? 1.0;

    // Grid highlight.
    canvas.drawRect(
      Rect.fromLTWH(btx, bty, g, g),
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Range indicator — green/red by validity, dashed [5,5].
    final rangeFill = validation.valid
        ? const Color(0x1A00FF41)
        : const Color(0x1AFF0000);
    final rangeStroke = validation.valid
        ? const Color(0x8000FF41)
        : const Color(0x80FF0000);
    canvas.drawCircle(
        Offset(target.x, target.y), def.range, Paint()..color = rangeFill);
    drawDashedCircle(
      canvas,
      Offset(target.x, target.y),
      def.range,
      Paint()
        ..color = rangeStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
      5,
      5,
    );

    // Tower ghost at 50% alpha — red when invalid.
    final ghostColor =
        validation.valid ? def.color : const Color(0xFFFF0000);
    drawTowerShape(canvas, type, target.x, target.y, ghostColor, previewScale,
        alpha: 128, glow: false);
  }
}
