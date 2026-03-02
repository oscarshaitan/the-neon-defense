import 'package:flutter/material.dart';
import '../../game/neon_defense_game.dart';

class StartScreen extends StatelessWidget {
  final NeonDefenseGame game;
  const StartScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'THE NEON DEFENSE',
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Color(0xFF00F3FF),
                shadows: [
                  Shadow(color: Color(0x9900F3FF), blurRadius: 20),
                ],
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'FLUTTER EDITION',
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 12,
                color: Color(0x8800F3FF),
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 60),
            _NeonButton(
              label: 'INITIATE',
              onPressed: game.startGame,
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _NeonButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFF00F3FF), width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        foregroundColor: const Color(0xFF00F3FF),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Orbitron',
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 4,
        ),
      ),
    );
  }
}
