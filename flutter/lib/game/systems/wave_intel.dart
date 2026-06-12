import 'dart:ui';

import '../config/constants.dart';
import 'pathfinding/rift_generator.dart';

/// Wave Intelligence math — pure port of JS 03_abilities.js:78-248.

/// Largest-remainder rounding split (JS distributeByWeights).
Map<EnemyType, int> distributeByWeights(
    int total, List<({EnemyType type, double weight})> weights) {
  final result = <EnemyType, int>{};
  var used = 0;
  final remainders = <({EnemyType type, double frac})>[];

  for (final w in weights) {
    final raw = total * w.weight;
    final base = raw.floor();
    result[w.type] = base;
    used += base;
    remainders.add((type: w.type, frac: raw - base));
  }

  final leftover = total - used;
  remainders.sort((a, b) => b.frac.compareTo(a.frac));
  for (var i = 0; i < leftover; i++) {
    final item = remainders[i % remainders.length];
    result[item.type] = (result[item.type] ?? 0) + 1;
  }
  return result;
}

/// JS getPredictedWaveDistribution: exact weight tables per wave bracket.
Map<EnemyType, int> getPredictedWaveDistribution(int nextWave) {
  final baseCount = 5 + (nextWave * 2.5).floor();
  final dist = <EnemyType, int>{};

  if (nextWave < 3) {
    dist[EnemyType.basic] = baseCount;
  } else if (nextWave < 5) {
    dist.addAll(distributeByWeights(baseCount, [
      (type: EnemyType.basic, weight: 0.7),
      (type: EnemyType.fast, weight: 0.3),
    ]));
  } else if (nextWave < 10) {
    final fixedTank = (nextWave % 5 == 0) ? (baseCount < 2 ? baseCount : 2) : 0;
    final remaining = baseCount - fixedTank;
    dist.addAll(distributeByWeights(remaining, [
      (type: EnemyType.basic, weight: 0.75),
      (type: EnemyType.fast, weight: 0.2),
      (type: EnemyType.tank, weight: 0.05),
    ]));
    dist[EnemyType.tank] = (dist[EnemyType.tank] ?? 0) + fixedTank;
  } else {
    var weights = [
      (type: EnemyType.basic, weight: 0.3),
      (type: EnemyType.fast, weight: 0.5),
      (type: EnemyType.tank, weight: 0.2),
    ];
    if (nextWave >= 15) {
      weights = [
        (type: EnemyType.basic, weight: 0.3),
        (type: EnemyType.fast, weight: 0.2),
        (type: EnemyType.tank, weight: 0.2),
        (type: EnemyType.splitter, weight: 0.3),
      ];
    }
    if (nextWave >= 20) {
      weights = [
        (type: EnemyType.basic, weight: 0.3),
        (type: EnemyType.fast, weight: 0.2),
        (type: EnemyType.tank, weight: 0.2),
        (type: EnemyType.splitter, weight: 0.15),
        (type: EnemyType.bulwark, weight: 0.15),
      ];
    }
    if (nextWave >= 30) {
      weights = [
        (type: EnemyType.basic, weight: 0.3),
        (type: EnemyType.fast, weight: 0.2),
        (type: EnemyType.tank, weight: 0.2),
        (type: EnemyType.splitter, weight: 0.15),
        (type: EnemyType.bulwark, weight: 0.07),
        (type: EnemyType.shifter, weight: 0.08),
      ];
    }
    dist.addAll(distributeByWeights(baseCount, weights));
  }

  if (nextWave % 10 == 0) {
    dist[EnemyType.boss] = (dist[EnemyType.boss] ?? 0) + 1;
  }
  return dist;
}

class WaveIntelTag {
  final String label;
  final Color color;
  const WaveIntelTag(this.label, this.color);
}

/// JS getWaveIntelTags.
List<WaveIntelTag> getWaveIntelTags(int nextWave, int upgradedRiftsCount,
    int mutatedRiftsCount, int maxTier) {
  final tags = <WaveIntelTag>[];
  if (nextWave % 10 == 0) {
    tags.add(const WaveIntelTag('BOSS', Color(0xFFFF00AC)));
  }
  if (nextWave > 50 && nextWave % 5 == 0 && nextWave % 10 != 0) {
    tags.add(const WaveIntelTag('SURPRISE_BOSS', Color(0xFFFFCC66)));
  }
  if (nextWave >= 20) {
    tags.add(const WaveIntelTag('TAUNT', Color(0xFFFCEE0A)));
  }
  if (nextWave >= 30) {
    tags.add(const WaveIntelTag('STEALTH', Color(0xFFFF66CC)));
  }
  if (nextWave % 20 == 0) {
    tags.add(const WaveIntelTag('MUT_EVENT', Color(0xFFFFFFFF)));
  }
  if (mutatedRiftsCount > 0) {
    tags.add(WaveIntelTag('MUTx$mutatedRiftsCount', const Color(0xFFFFFFFF)));
  }
  if (upgradedRiftsCount > 0) {
    tags.add(WaveIntelTag('T$maxTier', const Color(0xFF00F3FF)));
  }
  return tags;
}

class WaveIntelReport {
  final int wave;
  final int totalRifts;
  final int upgradedRifts;
  final int mutatedRifts;
  final int maxTier;
  final List<WaveIntelTag> tags;
  final String threatTitle;
  final Color threatColor;
  final String mutationStatus;
  final Map<EnemyType, int> distribution;

  WaveIntelReport({
    required this.wave,
    required this.totalRifts,
    required this.upgradedRifts,
    required this.mutatedRifts,
    required this.maxTier,
    required this.tags,
    required this.threatTitle,
    required this.threatColor,
    required this.mutationStatus,
    required this.distribution,
  });
}

/// JS updateWavePanel: threat score + mutation readiness + distribution
/// (live mid-wave, predicted during prep).
WaveIntelReport buildWaveIntelReport({
  required int wave,
  required List<RiftPath> rifts,
  required bool isWaveActive,
  Map<EnemyType, int>? liveDistribution,
}) {
  final upgradedRifts = rifts.where((r) => r.level > 1).length;
  final mutatedRifts = rifts.where((r) => r.mutation != null).length;
  final maxTier = rifts.fold(1, (acc, r) => r.level > acc ? r.level : acc);

  final tags = getWaveIntelTags(wave, upgradedRifts, mutatedRifts, maxTier);
  final threatScore =
      tags.length + (wave >= 50 ? 1 : 0) + (upgradedRifts > 0 ? 1 : 0);
  final threatTitle = threatScore >= 7
      ? 'CRITICAL'
      : (threatScore >= 5 ? 'HIGH' : (threatScore >= 3 ? 'ELEVATED' : 'NORMAL'));
  final threatColor = switch (threatTitle) {
    'CRITICAL' => const Color(0xFFFF00AC),
    'HIGH' => const Color(0xFFFF7A00),
    'ELEVATED' => const Color(0xFFFFCC00),
    _ => const Color(0xFFFFFFFF),
  };

  final String mutationStatus;
  if (wave % 20 == 0) {
    mutationStatus = 'MUTATION EVENT THIS WAVE';
  } else if (mutatedRifts > 0) {
    mutationStatus = '$mutatedRifts ACTIVE MUTATION SECTOR(S)';
  } else {
    mutationStatus = 'Stable | Next mutation check in ${20 - (wave % 20)} wave(s)';
  }

  return WaveIntelReport(
    wave: wave,
    totalRifts: rifts.length,
    upgradedRifts: upgradedRifts,
    mutatedRifts: mutatedRifts,
    maxTier: maxTier,
    tags: tags,
    threatTitle: threatTitle,
    threatColor: threatColor,
    mutationStatus: mutationStatus,
    distribution: (isWaveActive && liveDistribution != null)
        ? liveDistribution
        : getPredictedWaveDistribution(wave),
  );
}
