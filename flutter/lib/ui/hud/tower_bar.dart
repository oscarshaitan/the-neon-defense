import 'dart:math';
import 'package:flutter/material.dart';
import '../../game/config/constants.dart';
import '../../game/neon_defense_game.dart';

class TowerBar extends StatelessWidget {
  final NeonDefenseGame game;
  const TowerBar({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xF0050510),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xB800F3FF), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x4400F3FF), blurRadius: 16),
              BoxShadow(
                  color: Color(0x0800F3FF),
                  blurRadius: 14,
                  spreadRadius: -2),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: TowerType.values
                .map((type) => _TowerButton(game: game, type: type))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _TowerButton extends StatelessWidget {
  final NeonDefenseGame game;
  final TowerType type;

  static const Map<TowerType, String> _labels = {
    TowerType.basic: 'BASIC',
    TowerType.rapid: 'RAPID',
    TowerType.sniper: 'SNIPER',
    TowerType.arc: 'ARC',
  };

  static const Map<TowerType, String> _keys = {
    TowerType.basic: 'Q',
    TowerType.rapid: 'W',
    TowerType.sniper: 'E',
    TowerType.arc: 'R',
  };

  const _TowerButton({required this.game, required this.type});

  @override
  Widget build(BuildContext context) {
    final def = kTowers[type]!;
    final isSelected = game.gameWorld.selectedTowerType == type;
    final canAfford = game.money >= def.cost;

    // JS: selected border = green (#00ff41), not tower color
    final borderColor = isSelected
        ? const Color(0xFF00FF41)
        : canAfford
            ? def.color.withAlpha(120)
            : const Color(0x33FFFFFF);

    return GestureDetector(
      onTap: canAfford ? () => game.gameWorld.selectTowerType(type) : null,
      child: Container(
        width: 60,
        height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0x1A00FF41)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: isSelected
              ? const [BoxShadow(color: Color(0x4400FF41), blurRadius: 10)]
              : null,
        ),
        child: Stack(
          children: [
            // Key hint top-left
            Positioned(
              top: 3,
              left: 4,
              child: Text(
                _keys[type]!,
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 7,
                  color: Color(0x80FFFFFF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Main content: icon + label + cost
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TowerIcon(type: type, canAfford: canAfford),
                  const SizedBox(height: 5),
                  Text(
                    _labels[type]!,
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 8,
                      color: canAfford ? def.color : const Color(0x44FFFFFF),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${def.cost.toInt()}',
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 9,
                      color: canAfford
                          ? const Color(0xFFFFFFFF)
                          : const Color(0x44FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tower shape icons matching JS CSS shapes
class _TowerIcon extends StatelessWidget {
  final TowerType type;
  final bool canAfford;

  const _TowerIcon({required this.type, required this.canAfford});

  @override
  Widget build(BuildContext context) {
    final def = kTowers[type]!;
    final color = canAfford ? def.color : const Color(0x44FFFFFF);
    const size = 24.0;

    switch (type) {
      case TowerType.basic:
        // Cyan square
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            boxShadow: canAfford
                ? [BoxShadow(color: color.withAlpha(120), blurRadius: 5)]
                : null,
          ),
        );
      case TowerType.rapid:
        // Yellow circle
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: canAfford
                ? [BoxShadow(color: color.withAlpha(120), blurRadius: 5)]
                : null,
          ),
        );
      case TowerType.sniper:
        // Pink diamond (rotated square)
        return Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              color: color,
              boxShadow: canAfford
                  ? [BoxShadow(color: color.withAlpha(120), blurRadius: 5)]
                  : null,
            ),
          ),
        );
      case TowerType.arc:
        // Blue hexagon via CustomPaint
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _HexPainter(color: color),
          ),
        );
    }
  }
}

class _HexPainter extends CustomPainter {
  final Color color;
  const _HexPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    final path = Path();
    // CSS clip-path: polygon(50% 0%, 88% 20%, 88% 80%, 50% 100%, 12% 80%, 12% 20%)
    final points = [
      Offset(cx, 0),
      Offset(cx + r * 0.76, cy * 0.4),
      Offset(cx + r * 0.76, cy * 1.6),
      Offset(cx, size.height),
      Offset(cx - r * 0.76, cy * 1.6),
      Offset(cx - r * 0.76, cy * 0.4),
    ];
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}
