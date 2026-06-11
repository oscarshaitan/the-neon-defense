import 'package:flutter/material.dart';
import '../../game/config/constants.dart';
import '../../game/neon_defense_game.dart';

class PauseMenu extends StatefulWidget {
  final NeonDefenseGame game;
  const PauseMenu({super.key, required this.game});

  @override
  State<PauseMenu> createState() => _PauseMenuState();
}

class _PauseMenuState extends State<PauseMenu> {
  NeonDefenseGame get game => widget.game;

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
              _menuBtn('RESUME', const Color(0xFF00F3FF), game.togglePause),
              const SizedBox(height: 10),
              _menuBtn('RESET', const Color(0xFFFF00AC), () {
                game.overlays.remove('pauseMenu');
                game.resetGame();
              }),
              const SizedBox(height: 18),
              _qualityRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qualityRow() {
    final governor = game.gameWorld.qualityGovernor;
    return Column(
      children: [
        const Text(
          'DETAILS',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 9,
            color: Color(0x8800F3FF),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const [
              (QualityProfile.high, 'HIGH'),
              (QualityProfile.balanced, 'MED'),
              (QualityProfile.low, 'LOW'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _chipBtn(
                  entry.$2,
                  selected: !governor.autoAdjust &&
                      governor.currentProfile == entry.$1,
                  onTap: () =>
                      setState(() => governor.setProfileManually(entry.$1)),
                ),
              ),
            const SizedBox(width: 6),
            _chipBtn(
              'AUTO',
              selected: governor.autoAdjust,
              onTap: () => setState(() {
                governor.autoAdjust = true;
                game.state.toast.value = 'DETAILS: AUTO';
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chipBtn(String label,
      {required bool selected, required VoidCallback onTap}) {
    final color =
        selected ? const Color(0xFF00FF41) : const Color(0x8800F3FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
          color: selected ? const Color(0x1A00FF41) : Colors.transparent,
        ),
        child: Text(
          label,
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
