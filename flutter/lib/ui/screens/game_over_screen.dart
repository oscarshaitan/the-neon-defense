import 'package:flutter/material.dart';
import '../../game/neon_defense_game.dart';

class GameOverScreen extends StatelessWidget {
  final NeonDefenseGame game;
  const GameOverScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xCC050510),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'SYSTEM FAILURE',
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFF00AC),
                shadows: [
                  Shadow(color: Color(0x99FF00AC), blurRadius: 20),
                ],
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'SECTOR OVERRUN',
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 14,
                color: Color(0x88FF00AC),
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'WAVE ${game.wave}',
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 12,
                color: Color(0x6600F3FF),
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 48),
            OutlinedButton(
              onPressed: game.resetGame,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF00AC), width: 1.5),
                foregroundColor: const Color(0xFFFF00AC),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: const Text(
                'REBOOT SYSTEM',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
