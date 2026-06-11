import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, FontWeight;

import '../config/constants.dart';

/// JS drawLevelPips (06_render.js:1146-1198): centered row of white
/// diamonds (one per 5 levels) and dots (one per remaining level).
void drawLevelPips(Canvas canvas, int level, double x, double y) {
  final fives = level ~/ 5;
  final ones = level % 5;

  const fiveRadius = 4.0;
  const oneRadius = 2.0;
  const gap = 5.0;

  var totalW = (fives * (fiveRadius * 2)) + (ones * (oneRadius * 2));
  final totalItems = fives + ones;
  if (totalItems > 1) totalW += (totalItems - 1) * gap;

  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);

  var currentX = x - totalW / 2;
  for (var i = 0; i < fives; i++) {
    final cx = currentX + fiveRadius;
    canvas.drawPath(
      Path()
        ..moveTo(cx, y - fiveRadius)
        ..lineTo(cx + fiveRadius, y)
        ..lineTo(cx, y + fiveRadius)
        ..lineTo(cx - fiveRadius, y)
        ..close(),
      paint,
    );
    currentX += (fiveRadius * 2) + gap;
  }
  for (var i = 0; i < ones; i++) {
    canvas.drawCircle(Offset(currentX + oneRadius, y), oneRadius, paint);
    currentX += (oneRadius * 2) + gap;
  }
}

/// JS drawTowerOne (06_render.js:867-907): exact tower silhouettes —
/// basic 26x26 square, rapid r13 circle, sniper d15 diamond, arc r14 hex
/// with a pale core dot.
void drawTowerShape(
  Canvas canvas,
  TowerType type,
  double x,
  double y,
  Color color,
  double scale, {
  int alpha = 255,
  bool glow = true,
}) {
  final s = max(0.5, scale);
  final paint = Paint()..color = color.withAlpha(alpha);
  if (glow) {
    paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 6);
  }

  switch (type) {
    case TowerType.basic:
      canvas.drawRect(
          Rect.fromLTWH(x - 13 * s, y - 13 * s, 26 * s, 26 * s), paint);
      break;
    case TowerType.rapid:
      canvas.drawCircle(Offset(x, y), 13 * s, paint);
      break;
    case TowerType.sniper:
      canvas.drawPath(
        Path()
          ..moveTo(x, y - 15 * s)
          ..lineTo(x + 15 * s, y)
          ..lineTo(x, y + 15 * s)
          ..lineTo(x - 15 * s, y)
          ..close(),
        paint,
      );
      break;
    case TowerType.arc:
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final a = (pi * 2 * i / 6) - pi / 2;
        final px = x + cos(a) * 14 * s;
        final py = y + sin(a) * 14 * s;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.drawCircle(
        Offset(x, y),
        4 * s,
        Paint()..color = const Color(0xFFE9F9FF).withAlpha(alpha),
      );
      break;
  }
}

/// Dashed circle helper (canvas has no setLineDash equivalent).
void drawDashedCircle(Canvas canvas, Offset center, double radius,
    Paint paint, double dash, double gap,
    {double phase = 0}) {
  final circumference = 2 * pi * radius;
  final count = (circumference / (dash + gap)).floor();
  if (count <= 0) return;
  final dashAngle = dash / radius;
  final stepAngle = circumference / count / radius;
  for (var i = 0; i < count; i++) {
    final start = phase + i * stepAngle;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
        dashAngle, false, paint);
  }
}

/// JS Orbitron text labels (mutation tags, etc.).
void drawWorldLabel(Canvas canvas, String text, double x, double y,
    Color color, double fontSize) {
  final painter = TextPainter()
    ..textDirection = TextDirection.ltr
    ..text = TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Orbitron',
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    )
    ..layout();
  painter.paint(canvas, Offset(x - painter.width / 2, y - painter.height));
}
