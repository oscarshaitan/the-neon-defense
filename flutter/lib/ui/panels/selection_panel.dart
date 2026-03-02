import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../game/config/constants.dart' show TowerType;
import '../../game/entities/towers/tower.dart';
import '../../game/neon_defense_game.dart';

class SelectionPanel extends StatelessWidget {
  final NeonDefenseGame game;
  final Tower? selectedTower;
  const SelectionPanel({super.key, required this.game, this.selectedTower});

  @override
  Widget build(BuildContext context) {
    final tower = selectedTower;
    if (tower == null) return const SizedBox.shrink();

    final canUpgrade = game.money >= tower.upgradeCost;

    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(12),
          width: 160,
          decoration: BoxDecoration(
            color: const Color(0xF0050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('TYPE', tower.type.name.toUpperCase()),
              _row('LVL', '${tower.level}'),
              _row('DMG', tower.damage.toStringAsFixed(1)),
              _row('RNG', tower.range.toStringAsFixed(0)),
              if (tower.type == TowerType.arc)
                _row('ARC', '+${tower.arcNetworkBonus}'),
              const SizedBox(height: 8),
              Row(children: [
                _actionBtn(
                  'UP \$${tower.upgradeCost.toInt()}',
                  canUpgrade ? const Color(0xFF00F3FF) : const Color(0x44FFFFFF),
                  canUpgrade ? () => _upgrade(tower) : null,
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  'SELL \$${tower.sellValue.toInt()}',
                  const Color(0xFFFF00AC),
                  () => _sell(tower),
                ),
              ]),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => tower.isSelected = false,
                child: Text(
                  '✕ CLOSE',
                  style: GoogleFonts.orbitron(
                    fontSize: 8,
                    color: const Color(0x6600F3FF),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.orbitron(fontSize: 9, color: const Color(0x8800F3FF))),
          Text(value, style: GoogleFonts.orbitron(fontSize: 9, color: const Color(0xFF00F3FF), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.orbitron(fontSize: 8, color: color, letterSpacing: 1),
        ),
      ),
    );
  }

  void _upgrade(Tower tower) {
    if (game.money < tower.upgradeCost) return;
    game.money -= tower.upgradeCost;
    tower.upgrade();
  }

  void _sell(Tower tower) {
    game.money += tower.sellValue;
    tower.removeFromParent();
  }
}
