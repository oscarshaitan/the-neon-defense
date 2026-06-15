import 'package:flutter/material.dart';

import '../../game/neon_defense_game.dart';
import '../../game/systems/tech_tree.dart';

/// Tech Tree overlay (ROADMAP Milestone E). Shows the persistent RP balance,
/// four branch columns of node cards (acquired / unlockable / locked) with
/// tap-to-unlock, and a close button. Reachable from both the start screen and
/// the pause menu. Styled with the existing neon look (Orbitron, neon borders).
///
/// Mirrors the Godot HUD tech screen: rebuilds on [TechTree]'s change
/// notifications (the Dart equivalent of Godot's `changed` signal).
class TechTreeScreen extends StatelessWidget {
  final NeonDefenseGame game;

  /// Invoked by the close button. Lets the host decide what to restore
  /// (start screen, pause menu, etc.).
  final VoidCallback onClose;

  const TechTreeScreen({super.key, required this.game, required this.onClose});

  static const _blue = Color(0xFF00F3FF);
  static const _yellow = Color(0xFFFCEE0A);
  static const _green = Color(0xFF00FF41);
  static const _dim = Color(0xFF555566);

  /// Per-branch accent color, matching the neon palette.
  static const Map<String, Color> _branchColor = {
    'OFFENSE': Color(0xFFFF00AC),
    'CONTROL': Color(0xFF00F3FF),
    'ECONOMY': Color(0xFFFCEE0A),
    'CORE': Color(0xFF00FF41),
  };

  @override
  Widget build(BuildContext context) {
    final tech = game.tech;
    return ListenableBuilder(
      listenable: tech,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xF2050510),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _header(tech),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final branch in kTechBranches)
                            _branchColumn(tech, branch),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(TechTree tech) {
    return Row(
      children: [
        const Text(
          'TECH TREE',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: _blue,
            letterSpacing: 6,
            shadows: [Shadow(color: Color(0x9900F3FF), blurRadius: 16)],
          ),
        ),
        const SizedBox(width: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: _yellow, width: 1),
          ),
          child: Text(
            'RESEARCH: ${tech.rp} RP',
            style: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 13,
              color: _yellow,
              letterSpacing: 2,
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: onClose,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _blue, width: 1.5),
            foregroundColor: _blue,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: const Text(
            'CLOSE',
            style: TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 13,
              letterSpacing: 3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _branchColumn(TechTree tech, String branch) {
    final accent = _branchColor[branch] ?? _blue;
    return SizedBox(
      width: 200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              branch,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: accent,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            for (final node in tech.nodesInBranch(branch)) ...[
              _nodeCard(tech, node, accent),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nodeCard(TechTree tech, TechNode node, Color accent) {
    final unlocked = tech.isUnlocked(node.id);
    final canUnlock = tech.canUnlock(node);
    final prereqOk = tech.prereqMet(node);

    // Visual state: acquired (green), unlockable (branch accent), locked (dim).
    final Color border;
    final String status;
    if (unlocked) {
      border = _green;
      status = 'ACQUIRED';
    } else if (canUnlock) {
      border = accent;
      status = 'UNLOCK · ${node.cost} RP';
    } else if (!prereqOk) {
      border = _dim;
      status = 'LOCKED';
    } else {
      border = _dim;
      status = 'NEED ${node.cost} RP';
    }

    return GestureDetector(
      onTap: canUnlock ? () => tech.unlock(node.id) : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: unlocked ? const Color(0x1A00FF41) : Colors.transparent,
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.name,
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: unlocked ? _green : (canUnlock ? accent : _dim),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              node.desc,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Color(0xCCCCD6E0),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status,
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: border,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
