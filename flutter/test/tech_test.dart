import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neon_defense/game/systems/tech_tree.dart';

/// Pure-Dart Tech Tree checks, mirroring the Godot smoke-test tech section
/// (godot/tool/headless_smoke.gd, Milestone E). No rendering — just the data
/// layer (prereq gating, effect stacking, persistence values).
void main() {
  // TechTree.save() writes to SharedPreferences asynchronously (fire-and-forget
  // from unlock/grantRp). Mock the store so those writes don't hit a platform
  // channel during tests.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('16 nodes defined across 4 branches', () {
    expect(kTechNodes.length, 16);
    expect(kTechBranches, ['OFFENSE', 'CONTROL', 'ECONOMY', 'CORE']);
    for (final branch in kTechBranches) {
      final t = TechTree();
      expect(t.nodesInBranch(branch).length, 4);
    }
  });

  test('default effects match Godot _default_fx', () {
    final t = TechTree();
    t.recompute();
    expect(t.fx.dmgMult, 1.0);
    expect(t.fx.rangeMult, 1.0);
    expect(t.fx.rewardMult, 1.0);
    expect(t.fx.upgradeCostMult, 1.0);
    expect(t.fx.repairCostMult, 1.0);
    expect(t.fx.empFreezeMult, 1.0);
    expect(t.fx.empRadiusMult, 1.0);
    expect(t.fx.thermalMult, 1.0);
    expect(t.fx.sellRefund, 0.7);
    expect(t.fx.startMoney, 0.0);
    expect(t.fx.startLives, 0);
    expect(t.fx.startEnergy, 0.0);
    expect(t.fx.arcChill, false);
    expect(t.fx.execute, false);
    expect(t.fx.lastStand, false);
  });

  test('prereq gating: off_2 stays locked even with RP until off_1 unlocked',
      () {
    final t = TechTree();
    t.grantRp(100);
    expect(t.canUnlock(t.nodeById('off_2')!), isFalse,
        reason: 'off_2 gated by prereq even with RP');
    expect(t.canUnlock(t.nodeById('off_1')!), isTrue);
    expect(t.unlock('off_2'), isFalse);
    expect(t.unlock('off_1'), isTrue);
    expect(t.canUnlock(t.nodeById('off_2')!), isTrue);
    expect(t.unlock('off_2'), isTrue);
  });

  test('damage mult stacks multiplicatively (1.08 * 1.12)', () {
    final t = TechTree();
    t.grantRp(100);
    t.unlock('off_1');
    expect(t.fx.dmgMult, closeTo(1.08, 1e-9));
    t.unlock('off_2');
    expect(t.fx.dmgMult, closeTo(1.08 * 1.12, 1e-9));
  });

  test('reward mult: eco_1 grants +15%', () {
    final t = TechTree();
    t.grantRp(100);
    t.unlock('eco_1');
    expect(t.fx.rewardMult, closeTo(1.15, 1e-9));
  });

  test('sell_refund takes the best (max) value, default 0.7 -> 1.0', () {
    final t = TechTree();
    t.grantRp(100);
    expect(t.fx.sellRefund, 0.7);
    // eco_4 (Liquidation) requires the eco lane unlocked first.
    t.unlock('eco_1');
    t.unlock('eco_2');
    t.unlock('eco_3');
    t.unlock('eco_4');
    expect(t.fx.sellRefund, 1.0);
  });

  test('arc_chill boolean OR via con_1', () {
    final t = TechTree();
    t.grantRp(100);
    t.unlock('con_1');
    expect(t.fx.arcChill, isTrue);
  });

  test('start-of-run bonuses: war chest +150, plating +5, capacitors +30', () {
    final t = TechTree();
    t.grantRp(100);
    // ECONOMY lane to War Chest (+150 credits).
    t.unlock('eco_1');
    t.unlock('eco_2');
    t.unlock('eco_3');
    expect(t.fx.startMoney, 150.0);
    // CORE lane: Reinforced Plating (+5 lives), Emergency Capacitors (+30).
    t.unlock('core_1');
    expect(t.fx.startLives, 5);
    t.unlock('core_2');
    t.unlock('core_3');
    expect(t.fx.startEnergy, 30.0);
  });

  test('execute capstone sets execute flag', () {
    final t = TechTree();
    t.grantRp(100);
    t.unlock('off_1');
    t.unlock('off_2');
    t.unlock('off_3');
    t.unlock('off_4');
    expect(t.fx.execute, isTrue);
  });

  test('awardWave RP scaling: 1 + wave/10', () {
    final t = TechTree();
    expect(t.awardWave(1), 1);
    expect(t.awardWave(9), 1);
    expect(t.awardWave(10), 2);
    expect(t.awardWave(25), 3);
  });

  test('resetProgress wipes RP and unlocks', () {
    final t = TechTree();
    t.grantRp(100);
    t.unlock('off_1');
    t.resetProgress();
    expect(t.rp, 0);
    expect(t.unlocked, isEmpty);
    expect(t.fx.dmgMult, 1.0);
  });

  test('persistence round trip via SharedPreferences', () async {
    final t = TechTree();
    t.grantRp(20);
    t.unlock('off_1');
    t.unlock('core_1');
    await t.save();
    final savedRp = t.rp;

    final t2 = TechTree();
    await t2.load();
    expect(t2.rp, savedRp);
    expect(t2.isUnlocked('off_1'), isTrue);
    expect(t2.isUnlocked('core_1'), isTrue);
    expect(t2.fx.dmgMult, closeTo(1.08, 1e-9));
  });
}
