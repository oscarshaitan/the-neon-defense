import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neon_defense/game/config/constants.dart';
import 'package:neon_defense/game/entities/towers/tower.dart';
import 'package:neon_defense/game/systems/pathfinding/rift_generator.dart';
import 'package:neon_defense/game/systems/placement_system.dart';
import 'package:neon_defense/game/systems/spatial_grid.dart';
import 'package:neon_defense/game/systems/wave_intel.dart';
import 'package:neon_defense/game/world/hardpoint_manager.dart';

void main() {
  group('Tower economy parity (JS 04_tutorial.js)', () {
    Tower makeTower(TowerType type, {Hardpoint? hp}) => Tower(
          position: Vector2.zero(),
          type: type,
          spatialGrid: SpatialGrid(),
          hardpoint: hp,
        );

    test('upgrade cost = floor(baseCost * 0.5 * level)', () {
      final t = makeTower(TowerType.basic); // cost 50
      expect(t.upgradeCost, 25); // level 1
      t.upgrade();
      expect(t.level, 2);
      expect(t.upgradeCost, 50); // level 2
    });

    test('upgrade applies +20% damage, +10% range, capped at 800', () {
      final t = makeTower(TowerType.basic);
      final d0 = t.damage, r0 = t.range;
      t.upgrade();
      expect(t.damage, closeTo(d0 * 1.2, 1e-9));
      expect(t.range, closeTo(r0 * 1.1, 1e-9));

      final sniper = makeTower(TowerType.sniper); // range 250
      for (var i = 0; i < 20; i++) {
        sniper.upgrade();
      }
      expect(sniper.range, kMaxTowerRange);
    });

    test('sell value = floor(totalCost * 0.7)', () {
      final t = makeTower(TowerType.sniper); // cost 200
      expect(t.sellValue, 140);
      t.totalCost += t.upgradeCost; // +100 -> 300
      expect(t.sellValue, 210);
    });

    test('core hardpoint multipliers (1.08 dmg / 1.06 range / 0.95 cd)', () {
      final hp = Hardpoint(
        id: 'core_0',
        type: HardpointType.core,
        col: 0,
        row: 0,
        worldPos: Vector2.zero(),
      );
      final t = makeTower(TowerType.basic, hp: hp);
      expect(t.damage, closeTo(10 * 1.08, 1e-9));
      expect(t.range, closeTo(100 * 1.06, 1e-9));
      expect(t.maxCooldown, (30 * 0.95).round());
    });
  });

  group('Mutation profiles (JS 03_abilities.js:908-914)', () {
    test('five profiles with exact multipliers', () {
      expect(kMutationProfiles.length, 5);
      final titan = kMutationProfiles.firstWhere((m) => m.key == 'TITAN');
      expect(titan.hpMulti, 3.0);
      expect(titan.speedMulti, 0.7);
      expect(titan.rewardMulti, 3.0);
      expect(titan.colorValue, 0xFF00FFAA);
    });

    test('JSON round trip', () {
      final m = kMutationProfiles[0];
      final restored = Mutation.fromJson(m.toJson())!;
      expect(restored.key, m.key);
      expect(restored.hpMulti, m.hpMulti);
      expect(restored.colorValue, m.colorValue);
      expect(Mutation.fromJson(null), isNull);
    });
  });

  group('Placement snapping (JS snapToGrid)', () {
    test('snaps to cell centers', () {
      expect(PlacementSystem.snapToGrid(Vector2(5, 5)), Vector2(20, 20));
      expect(PlacementSystem.snapToGrid(Vector2(79, 41)), Vector2(60, 60));
      expect(
          PlacementSystem.snapToGrid(Vector2(40, 40)), Vector2(60, 60));
    });
  });

  group('Wave composition math (JS startWave)', () {
    test('enemy count = 5 + floor(wave * 2.5)', () {
      expect(5 + (1 * 2.5).floor(), 7);
      expect(5 + (10 * 2.5).floor(), 30);
      expect(5 + (25 * 2.5).floor(), 67);
    });
  });

  group('Wave Intel parity (JS 03_abilities.js)', () {
    test('distributeByWeights uses largest-remainder rounding', () {
      // 10 split 0.7/0.3 -> exactly 7/3
      final even = distributeByWeights(10, [
        (type: EnemyType.basic, weight: 0.7),
        (type: EnemyType.fast, weight: 0.3),
      ]);
      expect(even[EnemyType.basic], 7);
      expect(even[EnemyType.fast], 3);

      // 12 split 0.75/0.2/0.05 -> raw 9.0/2.4/0.6; leftover 1 goes to the
      // largest fractional remainder (0.6 -> tank).
      final split = distributeByWeights(12, [
        (type: EnemyType.basic, weight: 0.75),
        (type: EnemyType.fast, weight: 0.2),
        (type: EnemyType.tank, weight: 0.05),
      ]);
      expect(split[EnemyType.basic], 9);
      expect(split[EnemyType.fast], 2);
      expect(split[EnemyType.tank], 1);
      expect(split.values.reduce((a, b) => a + b), 12);
    });

    test('predicted distribution matches JS wave brackets', () {
      // Wave 1: all basic, 7 enemies.
      final w1 = getPredictedWaveDistribution(1);
      expect(w1[EnemyType.basic], 7);

      // Wave 5: fixed 2 tanks + 0.75/0.2/0.05 split of the rest.
      final w5 = getPredictedWaveDistribution(5);
      expect(w5.values.reduce((a, b) => a + b), 5 + (5 * 2.5).floor());
      expect(w5[EnemyType.tank], greaterThanOrEqualTo(2));

      // Wave 10: boss appended on every 10th wave.
      final w10 = getPredictedWaveDistribution(10);
      expect(w10[EnemyType.boss], 1);
      expect(w10.values.reduce((a, b) => a + b), 31);

      // Wave 30+: shifters enter the table.
      final w30 = getPredictedWaveDistribution(30);
      expect(w30[EnemyType.shifter], greaterThan(0));
    });

    test('threat tags follow JS thresholds', () {
      final tags20 = getWaveIntelTags(20, 0, 0, 1);
      expect(tags20.map((t) => t.label),
          containsAll(['BOSS', 'TAUNT', 'MUT_EVENT']));
      final tags55 = getWaveIntelTags(55, 2, 1, 3);
      expect(
          tags55.map((t) => t.label),
          containsAll(['SURPRISE_BOSS', 'TAUNT', 'STEALTH', 'MUTx1', 'T3']));
    });
  });
}
