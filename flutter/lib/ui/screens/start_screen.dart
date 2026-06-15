import 'package:flutter/material.dart';
import '../../game/neon_defense_game.dart';

/// Start screen. With existing save data it offers CONTINUE / NEW GAME
/// (JS start screen + loadGame, 01_init.js:13-22).
class StartScreen extends StatefulWidget {
  final NeonDefenseGame game;
  const StartScreen({super.key, required this.game});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    widget.game.saveSystem.hasSave().then((value) {
      if (mounted) setState(() => _hasSave = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
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
            if (_hasSave) ...[
              const Text(
                'SAVE DATA FOUND',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 10,
                  color: Color(0xFF00FF41),
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 16),
              _NeonButton(
                label: 'CONTINUE',
                color: const Color(0xFF00FF41),
                onPressed: () => game.continueGame(),
              ),
              const SizedBox(height: 12),
              _NeonButton(
                label: 'NEW GAME',
                onPressed: () async {
                  await game.saveSystem.clearSave();
                  game.startGame();
                },
              ),
            ] else
              _NeonButton(
                label: 'INITIATE',
                onPressed: game.startGame,
              ),
            const SizedBox(height: 12),
            _NeonButton(
              label: 'TECH TREE',
              color: const Color(0xFFFCEE0A),
              onPressed: () => game.openTechTree('startScreen'),
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
  final Color color;
  const _NeonButton({
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF00F3FF),
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        foregroundColor: color,
        minimumSize: const Size(220, 0),
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
