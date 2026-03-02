import 'package:flutter/material.dart';

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

    // Position at bottom, left of center — matches JS bottom:20px, right:50% + margin
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20, left: 10),
          padding: const EdgeInsets.all(14),
          width: 200,
          decoration: BoxDecoration(
            color: const Color(0xF0050510),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color(0xB3FF00AC), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x5200F3FF), blurRadius: 16),
              BoxShadow(
                  color: Color(0x0AFF00AC),
                  blurRadius: 14,
                  spreadRadius: -2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pink "TOWER INFO" header — matches JS h3 color: neon-pink
              const Text(
                'TOWER INFO',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 11,
                  color: Color(0xFFFF00AC),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              _row('TYPE', tower.type.name.toUpperCase()),
              _row('LEVEL', '${tower.level}'),
              _row('DMG', tower.damage.toStringAsFixed(1)),
              _row('RNG', tower.range.toStringAsFixed(0)),
              if (tower.type == TowerType.arc)
                _row('ARC BONUS', '+${tower.arcNetworkBonus}'),
              const SizedBox(height: 10),
              // Stacked action buttons — matches JS flex-direction: column
              _actionBtn(
                'UPGRADE  \$${tower.upgradeCost.toInt()}',
                canUpgrade
                    ? const Color(0xFF00FF41)
                    : const Color(0x44FFFFFF),
                canUpgrade ? () => _upgrade(tower) : null,
              ),
              const SizedBox(height: 6),
              _actionBtn(
                'SELL  \$${tower.sellValue.toInt()}',
                const Color(0xFFFF4444),
                () => _sell(tower),
              ),
              const SizedBox(height: 6),
              _actionBtn(
                'CLOSE',
                const Color(0x66FFFFFF),
                () => game.selectTower(null),
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
          Text(label,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Color(0xAAFFFFFF),
              )),
          Text(value,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Color(0xFFFFFFFF),
                fontWeight: FontWeight.bold,
              )),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x80000000),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 9,
            color: color,
            letterSpacing: 1,
          ),
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
    game.gameWorld.removeTower(tower);
  }
}
