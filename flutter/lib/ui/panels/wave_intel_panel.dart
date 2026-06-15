import 'package:flutter/material.dart';

import '../../game/config/constants.dart';
import '../../game/neon_defense_game.dart';
import '../../game/systems/wave_intel.dart';

/// Wave Intelligence panel (JS wave-info-panel / updateWavePanel):
/// threat level, rift stats, mutation readiness, tags, and the predicted
/// (or live) enemy distribution.
class WaveIntelPanel extends StatelessWidget {
  final NeonDefenseGame game;
  const WaveIntelPanel({super.key, required this.game});

  static const _order = [
    EnemyType.basic,
    EnemyType.fast,
    EnemyType.tank,
    EnemyType.splitter,
    EnemyType.bulwark,
    EnemyType.shifter,
    EnemyType.boss,
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: game.state.waveIntelOpen,
      builder: (_, open, child) {
        if (!open) return const SizedBox.shrink();

        final ws = game.gameWorld.waveSystem;
        final report = buildWaveIntelReport(
          wave: game.state.wave.value,
          rifts: ws.rifts,
          isWaveActive: game.state.isWaveActive.value,
          liveDistribution: ws.currentWaveDistribution,
        );

        return SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.only(top: 64, left: 10, bottom: 12),
              padding: const EdgeInsets.all(14),
              constraints: const BoxConstraints(
                minWidth: 250,
                maxWidth: 330,
                maxHeight: 420,
              ),
              decoration: BoxDecoration(
                color: const Color(0xF0050510),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xB3FF00AC), width: 1),
                boxShadow: const [
                  BoxShadow(color: Color(0x55FF00AC), blurRadius: 14),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'WAVE INTELLIGENCE',
                        style: TextStyle(
                          fontFamily: 'Orbitron',
                          fontSize: 13,
                          color: Color(0xFFFF00AC),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          shadows: [
                            Shadow(color: Color(0xFFFF00AC), blurRadius: 5),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => game.state.waveIntelOpen.value = false,
                        child: const Text(
                          'X',
                          style: TextStyle(
                            fontFamily: 'Orbitron',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00F3FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 5, bottom: 6),
                    height: 1,
                    color: const Color(0x4DFF00AC),
                  ),
                  _row('RIFTS ACTIVE:', '${report.totalRifts}'),
                  _row('MUTATION POTENTIAL:', report.mutationStatus),
                  _row('THREAT LEVEL:', report.threatTitle),
                  const SizedBox(height: 6),
                  const Text(
                    'ENEMY DISTRIBUTION:',
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 9,
                      color: Color(0xFF00F3FF),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final type in _order)
                        if ((report.distribution[type] ?? 0) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x40000000),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0x4000F3FF), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  color: kEnemies[type]!.color,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${report.distribution[type]}',
                                  style: const TextStyle(
                                    fontFamily: 'Orbitron',
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ],
              ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(label,
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 9,
                  color: Color(0xFF00F3FF),
                )),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
