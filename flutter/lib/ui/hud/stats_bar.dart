import 'package:flutter/material.dart';
import '../../game/neon_defense_game.dart';

class StatsBar extends StatelessWidget {
  final NeonDefenseGame game;
  const StatsBar({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final ws = game.gameWorld.waveSystem;
    final state = game.state;
    final remaining = game.entities.enemies.length;
    // The FPS readout is dropped on narrow (phone-landscape) widths so the
    // top bar never overflows; there's room for it on tablet/desktop.
    final showFps = MediaQuery.of(context).size.width >= 760;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full-width stats bar — matches JS left:10 right:10 justify-content:space-between
          Container(
            margin: const EdgeInsets.only(top: 8, left: 8, right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xE6050510),
              border: Border.all(color: const Color(0xFF00F3FF), width: 1),
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [
                BoxShadow(color: Color(0x5500F3FF), blurRadius: 10),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Wave + Lives
                Row(mainAxisSize: MainAxisSize.min, children: [
                  // JS: tapping the wave counter opens Wave Intel.
                  GestureDetector(
                    onTap: () => game.state.waveIntelOpen.value =
                        !game.state.waveIntelOpen.value,
                    child: _stat('WAVE', '${state.wave.value}'),
                  ),
                  const SizedBox(width: 20),
                  _stat('LIVES', '${state.lives.value}'),
                ]),
                // Center: Timer or enemy count
                if (ws.isPrepPhase)
                  _stat('NEXT WAVE', '${ws.prepTimer.ceil()}s',
                      color: const Color(0xFF00FF41))
                else if (state.isWaveActive.value)
                  _stat('ENEMIES', '$remaining',
                      color: const Color(0xFFFF4444)),
                // Right: Credits + Pause
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _stat('CREDITS', '${state.money.value.toInt()}',
                      color: const Color(0xFFFCEE0A)),
                  if (showFps) ...[
                    const SizedBox(width: 12),
                    _stat('FPS', '${game.fps.round()}',
                        color: const Color(0xB300F3FF)),
                  ],
                  const SizedBox(width: 12),
                  _pauseBtn(context),
                ]),
              ],
            ),
          ),
          // START WAVE button — centered below stats bar, matches JS wave-controls
          if (ws.isPrepPhase)
            Center(
              child: GestureDetector(
                onTap: () => ws.skipPrep(),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0x3300FF41),
                    border:
                        Border.all(color: const Color(0xFF00FF41), width: 1),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(color: Color(0x4400FF41), blurRadius: 8),
                    ],
                  ),
                  child: const Text(
                    'START WAVE',
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00FF41),
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value,
      {Color color = const Color(0xFF00F3FF)}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 11,
              letterSpacing: 1,
              color: Color(0x8800F3FF),
              fontWeight: FontWeight.bold,
            )),
        Text(value,
            style: TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 11,
              letterSpacing: 1,
              color: color,
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }

  Widget _pauseBtn(BuildContext context) {
    return GestureDetector(
      onTap: game.togglePause,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF00F3FF), width: 1),
        ),
        child: const Center(
          child: Text(
            'II',
            style: TextStyle(
              fontFamily: 'Orbitron',
              color: Color(0xFF00F3FF),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
