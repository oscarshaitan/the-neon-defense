import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../game/neon_defense_game.dart';

class StatsBar extends StatelessWidget {
  final NeonDefenseGame game;
  const StatsBar({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE6050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stat('WAVE', '${game.wave}'),
              const SizedBox(width: 16),
              _stat('LIVES', '${game.lives}'),
              const SizedBox(width: 16),
              _stat('CREDITS', '${game.money.toInt()}',
                  color: const Color(0xFFFCEE0A)),
              const SizedBox(width: 16),
              _stat('ENERGY',
                  '${game.energy.toInt()}/${game.maxEnergy.toInt()}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {Color color = const Color(0xFF00F3FF)}) {
    final style = GoogleFonts.orbitron(fontSize: 11, letterSpacing: 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: style.copyWith(color: const Color(0x8800F3FF))),
        Text(value, style: style.copyWith(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
