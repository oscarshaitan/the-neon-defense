import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
            Text(
              'THE NEON DEFENSE',
              style: GoogleFonts.orbitron(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF00F3FF),
                shadows: [
                  const Shadow(
                    color: Color(0x9900F3FF),
                    blurRadius: 20,
                  ),
                ],
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'FLUTTER EDITION',
              style: GoogleFonts.orbitron(
                fontSize: 12,
                color: const Color(0x8800F3FF),
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
        style: GoogleFonts.orbitron(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 4,
        ),
      ),
    );
  }
}
