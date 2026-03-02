import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        alignment: Alignment.bottomRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 72, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xE6050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Energy bar
              _EnergyBar(game: game),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AbilitySlot(
                    label: 'EMP',
                    keyHint: '[1]',
                    cost: kEmpCost.toInt(),
                    ready: ab.empReady,
                    active: ab.targetingAbility == AbilityType.emp,
                    cooldownFraction: ab.empCooldownFraction,
                    color: const Color(0xFF00F3FF),
                    onTap: () => game.gameWorld.activateAbility(AbilityType.emp),
                  ),
                  const SizedBox(width: 8),
                  _AbilitySlot(
                    label: 'OVR',
                    keyHint: '[2]',
                    cost: kOverclockCost.toInt(),
                    ready: ab.overclockReady,
                    active: ab.targetingAbility == AbilityType.overclock,
                    cooldownFraction: ab.overclockCooldownFraction,
                    color: const Color(0xFFFCEE0A),
                    onTap: () => game.gameWorld.activateAbility(AbilityType.overclock),
                  ),
                ],
              ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ENERGY  ${game.energy.toInt()}/${game.maxEnergy.toInt()}',
          style: GoogleFonts.orbitron(
            fontSize: 8,
            color: const Color(0x8800F3FF),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 120,
          height: 4,
          child: Stack(
            children: [
              Container(color: const Color(0x22FFFFFF)),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(color: const Color(0xFF00F3FF)),
              ),
            ],
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
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: active ? color.withAlpha(40) : const Color(0x11FFFFFF),
          border: Border.all(
            color: ready ? color.withAlpha(active ? 255 : 150) : const Color(0x33FFFFFF),
            width: 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Cooldown overlay
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
                  style: GoogleFonts.orbitron(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: ready ? color : const Color(0x44FFFFFF),
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '$cost ⚡',
                  style: GoogleFonts.orbitron(
                    fontSize: 8,
                    color: ready ? const Color(0xAA00F3FF) : const Color(0x33FFFFFF),
                  ),
                ),
                Text(
                  keyHint,
                  style: GoogleFonts.orbitron(
                    fontSize: 7,
                    color: const Color(0x3300F3FF),
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
