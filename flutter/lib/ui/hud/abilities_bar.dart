import 'package:flutter/material.dart';

import '../../game/config/constants.dart';
import '../../game/neon_defense_game.dart';
import '../../game/systems/ability_system.dart';

class AbilitiesBar extends StatelessWidget {
  final NeonDefenseGame game;
  const AbilitiesBar({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final ab = game.gameWorld.abilitySystem;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xE6050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AbilitySlot(
                label: 'EMP\nBURST',
                keyHint: '[1]',
                cost: kEmpCost.toInt(),
                ready: ab.empReady,
                active: ab.targetingAbility == AbilityType.emp,
                cooldownFraction: ab.empCooldownFraction,
                color: const Color(0xFF00F3FF),
                onTap: () => game.gameWorld.activateAbility(AbilityType.emp),
              ),
              const SizedBox(height: 8),
              _AbilitySlot(
                label: 'OVER\nCLOCK',
                keyHint: '[2]',
                cost: kOverclockCost.toInt(),
                ready: ab.overclockReady,
                active: ab.targetingAbility == AbilityType.overclock,
                cooldownFraction: ab.overclockCooldownFraction,
                color: const Color(0xFFFCEE0A),
                onTap: () =>
                    game.gameWorld.activateAbility(AbilityType.overclock),
              ),
              const SizedBox(height: 10),
              _EnergyBar(game: game),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnergyBar extends StatelessWidget {
  final NeonDefenseGame game;
  const _EnergyBar({required this.game});

  @override
  Widget build(BuildContext context) {
    final fraction = (game.energy / game.maxEnergy).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'ENERGY',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 7,
            color: Color(0x8800F3FF),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 8,
          height: 60,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(color: const Color(0x22FFFFFF)),
              FractionallySizedBox(
                heightFactor: fraction,
                child: Container(color: const Color(0xFF00F3FF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${game.energy.toInt()}/${game.maxEnergy.toInt()}',
          style: const TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 7,
            color: Color(0x8800F3FF),
          ),
        ),
      ],
    );
  }
}

class _AbilitySlot extends StatelessWidget {
  final String label;
  final String keyHint;
  final int cost;
  final bool ready;
  final bool active;
  final double cooldownFraction;
  final Color color;
  final VoidCallback onTap;

  const _AbilitySlot({
    required this.label,
    required this.keyHint,
    required this.cost,
    required this.ready,
    required this.active,
    required this.cooldownFraction,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: ready ? onTap : null,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: active ? color.withAlpha(40) : const Color(0x11FFFFFF),
          border: Border.all(
            color: ready
                ? color.withAlpha(active ? 255 : 150)
                : const Color(0x33FFFFFF),
            width: 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (cooldownFraction > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor: cooldownFraction,
                  child: Container(color: const Color(0x44000000)),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: ready ? color : const Color(0x44FFFFFF),
                    letterSpacing: 1,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$cost \u26a1',
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    fontSize: 8,
                    color: ready
                        ? const Color(0xAA00F3FF)
                        : const Color(0x33FFFFFF),
                  ),
                ),
                Text(
                  keyHint,
                  style: const TextStyle(
                    fontFamily: 'Orbitron',
                    fontSize: 7,
                    color: Color(0x3300F3FF),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
