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
              margin: const EdgeInsets.only(top: 64, left: 10),
              padding: const EdgeInsets.all(14),
              width: 250,
              decoration: BoxDecoration(
                color: const Color(0xF0050510),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xB300F3FF), width: 1),
                boxShadow: const [
                  BoxShadow(color: Color(0x5500F3FF), blurRadius: 14),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'WAVE ${report.wave} INTEL',
                        style: const TextStyle(
                          fontFamily: 'Orbitron',
                          fontSize: 11,
                          color: Color(0xFF00F3FF),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => game.state.waveIntelOpen.value = false,
                        child: const Text(
                          'X',
                          style: TextStyle(
                            fontFamily: 'Orbitron',
                            fontSize: 11,
                            color: Color(0x88FFFFFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _row('THREAT',
                      Text(report.threatTitle, style: _valueStyle(report.threatColor))),
                  _row('RIFTS',
                      Text('${report.totalRifts}', style: _valueStyle(Colors.white))),
                  const SizedBox(height: 6),
                  Text(
                    report.mutationStatus,
                    style: const TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 8,
                      color: Color(0xAAFFFFFF),
                      height: 1.5,
                    ),
                  ),
                  if (report.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final tag in report.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: tag.color, width: 1),
                            ),
                            child: Text(
                              tag.label,
                              style: TextStyle(
                                fontFamily: 'Orbitron',
                                fontSize: 7,
                                color: tag.color,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'EXPECTED HOSTILES',
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 8,
                      color: Color(0x8800F3FF),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final type in _order)
                        if ((report.distribution[type] ?? 0) > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                color: kEnemies[type]!.color,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${report.distribution[type]}',
                                style: const TextStyle(
                                  fontFamily: 'Orbitron',
                                  fontSize: 9,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _valueStyle(Color color) => TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 9,
        color: color,
        fontWeight: FontWeight.bold,
      );

  Widget _row(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 9,
                color: Color(0xAAFFFFFF),
              )),
          value,
        ],
      ),
    );
  }
}
