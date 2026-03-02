import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE6050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
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

    return GestureDetector(
      onTap: canAfford
          ? () => game.gameWorld.selectTowerType(type)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? def.color.withAlpha(40)
              : Colors.transparent,
          border: Border.all(
            color: canAfford
                ? def.color.withAlpha(isSelected ? 255 : 120)
                : const Color(0x33FFFFFF),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _labels[type]!,
              style: GoogleFonts.orbitron(
                fontSize: 9,
                color: canAfford ? def.color : const Color(0x44FFFFFF),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '\$${def.cost.toInt()}',
              style: GoogleFonts.orbitron(
                fontSize: 9,
                color: canAfford
                    ? const Color(0xFFFCEE0A)
                    : const Color(0x44FFFFFF),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '[${_keys[type]}]',
              style: GoogleFonts.orbitron(
                fontSize: 8,
                color: const Color(0x4400F3FF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
