import 'package:flutter/material.dart';
import '../../game/neon_defense_game.dart';

class PauseMenu extends StatelessWidget {
  final NeonDefenseGame game;
  const PauseMenu({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xCC050510),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF050510),
            border: Border.all(color: const Color(0x8000F3FF), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PAUSED',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF00F3FF),
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 24),
              _menuBtn('RESUME', const Color(0xFF00F3FF), () {
                game.isPaused = false;
                game.overlays.remove('pauseMenu');
              }),
              const SizedBox(height: 10),
              _menuBtn('RESET', const Color(0xFFFF00AC), () {
                game.overlays.remove('pauseMenu');
                game.resetGame();
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(String label, Color color, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        minimumSize: const Size(180, 0),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Orbitron',
          fontSize: 13,
          letterSpacing: 3,
        ),
      ),
    );
  }
}
