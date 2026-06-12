import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/neon_defense_game.dart';

/// "INCOMING TRANSMISSION" tutorial dialog (JS tutorial-overlay).
/// Modal steps (0-1) block input and type out their text at 20 ms/char;
/// interactive steps (2-4) let taps pass through to the game.
class TutorialOverlay extends StatefulWidget {
  final NeonDefenseGame game;
  const TutorialOverlay({super.key, required this.game});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  String _typed = '';
  Timer? _typeTimer;
  int _typedForStep = -1;

  NeonDefenseGame get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.tutorial.addListener(_onTutorialChanged);
    _startTypewriter();
  }

  @override
  void dispose() {
    game.tutorial.removeListener(_onTutorialChanged);
    _typeTimer?.cancel();
    super.dispose();
  }

  void _onTutorialChanged() {
    if (!mounted) return;
    setState(_startTypewriter);
  }

  void _startTypewriter() {
    final tutorial = game.tutorial;
    if (!tutorial.active || _typedForStep == tutorial.step) return;
    _typedForStep = tutorial.step;
    _typeTimer?.cancel();

    if (!tutorial.isModalStep) {
      // JS skips the typewriter for markup-bearing steps.
      _typed = tutorial.currentText;
      return;
    }

    _typed = '';
    final text = tutorial.currentText;
    var i = 0;
    _typeTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted || i >= text.length) {
        timer.cancel();
        return;
      }
      setState(() => _typed = text.substring(0, ++i));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutorial = game.tutorial;
    if (!tutorial.active) return const SizedBox.shrink();

    final box = Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF2050510),
        border: Border.all(color: const Color(0xFF00F3FF), width: 1),
        boxShadow: const [BoxShadow(color: Color(0x5500F3FF), blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INCOMING TRANSMISSION',
            style: TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 9,
              color: Color(0xFFFF00AC),
              letterSpacing: 3,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _typed,
            style: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 11,
              color: Color(0xFFE6FCFF),
              height: 1.6,
            ),
          ),
          if (tutorial.isModalStep) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _btn('UNDERSTOOD', const Color(0xFF00F3FF), tutorial.next),
                if (tutorial.canSkip) ...[
                  const SizedBox(width: 8),
                  _btn('SKIP', const Color(0x66FFFFFF), tutorial.skip),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (tutorial.isModalStep) {
      return Container(
        color: const Color(0x99050510),
        alignment: Alignment.center,
        child: box,
      );
    }
    // Interactive steps: box floats top-center, taps pass through elsewhere.
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(padding: const EdgeInsets.only(top: 90), child: box),
        ),
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: color, width: 1)),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 10,
            color: color,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
