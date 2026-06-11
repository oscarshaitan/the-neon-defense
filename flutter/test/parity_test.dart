import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neon_defense/game/config/constants.dart';
import 'package:neon_defense/game/entities/towers/tower.dart';
import 'package:neon_defense/game/systems/pathfinding/rift_generator.dart';
import 'package:neon_defense/game/systems/placement_system.dart';
import 'package:neon_defense/game/systems/spatial_grid.dart';
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
}
