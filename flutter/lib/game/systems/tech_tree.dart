/// Tech Tree strategy layer (ROADMAP Milestone E). Ported 1:1 from the Godot
/// edition (godot/scripts/tech_tree.gd), which leads this feature.
///
/// Research Points (RP) and unlocked nodes are PERSISTENT across runs, stored
/// in a SEPARATE persistent store from the per-run save (SaveSystem) so
/// progression carries over. Node effects are accumulated into [fx] and read
/// live by gameplay (game_world.dart / tower.dart / ability_system.dart), so
/// most unlocks take effect immediately; start-of-run bonuses
/// (credits/lives/energy) apply when a fresh run begins.
///
/// A [ChangeNotifier] so the UI refreshes when RP balance or the unlocked set
/// changes (mirrors Godot's `changed` signal).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Distinct persistence key from the per-run save (`neon_defense_save`).
/// Mirrors Godot's `user://neon_defense_tech.json`.
const String kTechSaveKey = 'neon_defense_tech';

// Control-branch frost tuning (Godot CHILL_FRAMES / CHILL_SLOW).
const int kTechChillFrames = 120; // Cryo Conductors chill duration (2 s @ 60 Hz)
const double kTechChillSlow = 0.5; // chilled enemies move at 50% speed
// Offense capstone execution.
const double kTechExecuteThreshold = 0.15;
const double kTechExecuteBonus = 2.0;
// Core capstone restore.
const int kTechLastStandLives = 5;

const List<String> kTechBranches = ['OFFENSE', 'CONTROL', 'ECONOMY', 'CORE'];

/// A single tech node. `prereq` is the node id that must be unlocked first
/// ("" = always available). `effect` lists the contributions accumulated into
/// [TechTree.fx].
class TechNode {
  final String id;
  final String branch;
  final int tier; // 1-3 lane, 4 capstone
  final int cost; // RP
  final String prereq; // required node id ("" = none)
  final String name;
  final String desc;
  final Map<String, Object> effect;

  const TechNode({
    required this.id,
    required this.branch,
    required this.tier,
    required this.cost,
    required this.prereq,
    required this.name,
    required this.desc,
    required this.effect,
  });
}

/// Node graph — must match Godot's NODES table exactly.
const List<TechNode> kTechNodes = [
  // --- OFFENSE ---
  TechNode(
      id: 'off_1', branch: 'OFFENSE', tier: 1, cost: 2, prereq: '',
      name: 'FOCUSED OPTICS', desc: '+8% tower damage',
      effect: {'dmg_mult': 1.08}),
  TechNode(
      id: 'off_2', branch: 'OFFENSE', tier: 2, cost: 3, prereq: 'off_1',
      name: 'OVERCHARGED ROUNDS', desc: '+12% tower damage',
      effect: {'dmg_mult': 1.12}),
  TechNode(
      id: 'off_3', branch: 'OFFENSE', tier: 3, cost: 4, prereq: 'off_2',
      name: 'EXTENDED BARRELS', desc: '+12% tower range',
      effect: {'range_mult': 1.12}),
  TechNode(
      id: 'off_4', branch: 'OFFENSE', tier: 4, cost: 6, prereq: 'off_3',
      name: 'EXECUTIONER', desc: 'Enemies below 15% HP take double damage',
      effect: {'execute': true}),
  // --- CONTROL (frost package) ---
  TechNode(
      id: 'con_1', branch: 'CONTROL', tier: 1, cost: 2, prereq: '',
      name: 'CRYO CONDUCTORS', desc: 'Arc attacks chill enemies (slow)',
      effect: {'arc_chill': true}),
  TechNode(
      id: 'con_2', branch: 'CONTROL', tier: 2, cost: 3, prereq: 'con_1',
      name: 'CRYO EMP', desc: 'EMP freeze lasts 50% longer',
      effect: {'emp_freeze_mult': 1.5}),
  TechNode(
      id: 'con_3', branch: 'CONTROL', tier: 3, cost: 4, prereq: 'con_2',
      name: 'THERMAL WEAKNESS', desc: 'Chilled/frozen enemies take +25% damage',
      effect: {'thermal_mult': 1.25}),
  TechNode(
      id: 'con_4', branch: 'CONTROL', tier: 4, cost: 6, prereq: 'con_3',
      name: 'DEEP FREEZE PROTOCOL', desc: 'EMP blast radius +50%',
      effect: {'emp_radius_mult': 1.5}),
  // --- ECONOMY ---
  TechNode(
      id: 'eco_1', branch: 'ECONOMY', tier: 1, cost: 2, prereq: '',
      name: 'SALVAGE ROUTINES', desc: '+15% credits from kills',
      effect: {'reward_mult': 1.15}),
  TechNode(
      id: 'eco_2', branch: 'ECONOMY', tier: 2, cost: 3, prereq: 'eco_1',
      name: 'BULK DISCOUNT', desc: 'Tower upgrades cost 20% less',
      effect: {'upgrade_cost_mult': 0.8}),
  TechNode(
      id: 'eco_3', branch: 'ECONOMY', tier: 3, cost: 4, prereq: 'eco_2',
      name: 'WAR CHEST', desc: 'Start each run with +150 credits',
      effect: {'start_money': 150.0}),
  TechNode(
      id: 'eco_4', branch: 'ECONOMY', tier: 4, cost: 6, prereq: 'eco_3',
      name: 'LIQUIDATION', desc: 'Selling towers refunds 100%',
      effect: {'sell_refund': 1.0}),
  // --- CORE SYSTEMS ---
  TechNode(
      id: 'core_1', branch: 'CORE', tier: 1, cost: 2, prereq: '',
      name: 'REINFORCED PLATING', desc: 'Start each run with +5 lives',
      effect: {'start_lives': 5}),
  TechNode(
      id: 'core_2', branch: 'CORE', tier: 2, cost: 3, prereq: 'core_1',
      name: 'FIELD REPAIRS', desc: 'Base repairs cost 30% less',
      effect: {'repair_cost_mult': 0.7}),
  TechNode(
      id: 'core_3', branch: 'CORE', tier: 3, cost: 4, prereq: 'core_2',
      name: 'EMERGENCY CAPACITORS', desc: 'Start each run with +30 energy',
      effect: {'start_energy': 30.0}),
  TechNode(
      id: 'core_4', branch: 'CORE', tier: 4, cost: 6, prereq: 'core_3',
      name: 'LAST STAND PROTOCOL',
      desc: 'Once per run, survive a fatal breach (restore 5 lives)',
      effect: {'last_stand': true}),
];

/// Accumulated live tech effects (mirrors Godot's `fx` dictionary).
class TechEffects {
  double dmgMult;
  double rangeMult;
  double rewardMult;
  double upgradeCostMult;
  double repairCostMult;
  double empFreezeMult;
  double empRadiusMult;
  double thermalMult;
  double sellRefund;
  double startMoney;
  int startLives;
  double startEnergy;
  bool arcChill;
  bool execute;
  bool lastStand;

  TechEffects()
      : dmgMult = 1.0,
        rangeMult = 1.0,
        rewardMult = 1.0,
        upgradeCostMult = 1.0,
        repairCostMult = 1.0,
        empFreezeMult = 1.0,
        empRadiusMult = 1.0,
        thermalMult = 1.0,
        sellRefund = 0.7,
        startMoney = 0.0,
        startLives = 0,
        startEnergy = 0.0,
        arcChill = false,
        execute = false,
        lastStand = false;
}

class TechTree extends ChangeNotifier {
  int rp = 0;
  final Set<String> unlocked = <String>{};
  TechEffects fx = TechEffects();

  /// All nodes (exposed for UI/tests; mirrors Godot's `NODES`).
  List<TechNode> get nodes => kTechNodes;

  // ---------------------------------------------------------------------------
  // Effect accumulation
  // ---------------------------------------------------------------------------

  /// Rebuild [fx] from the unlocked set. Keys ending `_mult` multiply;
  /// `start_*` add; `sell_refund` takes the max; booleans OR.
  void recompute() {
    final f = TechEffects();
    for (final node in kTechNodes) {
      if (!unlocked.contains(node.id)) continue;
      node.effect.forEach((key, value) {
        switch (key) {
          case 'dmg_mult':
            f.dmgMult *= value as double;
            break;
          case 'range_mult':
            f.rangeMult *= value as double;
            break;
          case 'reward_mult':
            f.rewardMult *= value as double;
            break;
          case 'upgrade_cost_mult':
            f.upgradeCostMult *= value as double;
            break;
          case 'repair_cost_mult':
            f.repairCostMult *= value as double;
            break;
          case 'emp_freeze_mult':
            f.empFreezeMult *= value as double;
            break;
          case 'emp_radius_mult':
            f.empRadiusMult *= value as double;
            break;
          case 'thermal_mult':
            f.thermalMult *= value as double;
            break;
          case 'sell_refund':
            final v = value as double;
            if (v > f.sellRefund) f.sellRefund = v; // best refund wins
            break;
          case 'start_money':
            f.startMoney += value as double;
            break;
          case 'start_lives':
            f.startLives += value as int;
            break;
          case 'start_energy':
            f.startEnergy += value as double;
            break;
          case 'arc_chill':
            f.arcChill = f.arcChill || value as bool;
            break;
          case 'execute':
            f.execute = f.execute || value as bool;
            break;
          case 'last_stand':
            f.lastStand = f.lastStand || value as bool;
            break;
        }
      });
    }
    fx = f;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Node queries / unlocking
  // ---------------------------------------------------------------------------

  TechNode? nodeById(String id) {
    for (final node in kTechNodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  bool isUnlocked(String id) => unlocked.contains(id);

  bool prereqMet(TechNode node) =>
      node.prereq.isEmpty || unlocked.contains(node.prereq);

  bool canUnlock(TechNode node) =>
      !isUnlocked(node.id) && prereqMet(node) && rp >= node.cost;

  List<TechNode> nodesInBranch(String branch) =>
      [for (final n in kTechNodes) if (n.branch == branch) n];

  /// Spend RP to unlock a node. Returns false if gated/unaffordable/unknown.
  bool unlock(String id) {
    final node = nodeById(id);
    if (node == null || !canUnlock(node)) return false;
    rp -= node.cost;
    unlocked.add(id);
    recompute(); // notifies
    save();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Research Points
  // ---------------------------------------------------------------------------

  /// Awarded when a wave is cleared; scales gently with depth
  /// (Godot: 1 + cleared_wave / 10). Returns the RP gained so the caller can
  /// surface a toast (kept GameState-free for pure-Dart testability).
  int awardWave(int clearedWave) {
    final gain = 1 + (clearedWave ~/ 10);
    rp += gain;
    save();
    notifyListeners();
    return gain;
  }

  void grantRp(int amount) {
    rp += amount;
    save();
    notifyListeners();
  }

  /// Debug/respec: wipe all progression.
  void resetProgress() {
    rp = 0;
    unlocked.clear();
    recompute(); // notifies
    save();
  }

  // ---------------------------------------------------------------------------
  // Persistence (separate store from the per-run save)
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kTechSaveKey);
    if (raw == null) {
      recompute();
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      rp = (data['rp'] as num?)?.toInt() ?? 0;
      unlocked.clear();
      for (final id in (data['unlocked'] as List<dynamic>? ?? [])) {
        final s = id.toString();
        if (nodeById(s) != null) unlocked.add(s);
      }
    } catch (_) {
      // Corrupt store: start fresh rather than crash.
      rp = 0;
      unlocked.clear();
    }
    recompute();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        kTechSaveKey, jsonEncode({'rp': rp, 'unlocked': unlocked.toList()}));
  }
}
