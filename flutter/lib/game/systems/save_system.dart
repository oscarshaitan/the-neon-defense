import 'dart:async';
import 'dart:convert';
import 'package:flame/components.dart' show Vector2;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../entities/towers/tower.dart';
import '../neon_defense_game.dart';
import 'pathfinding/rift_generator.dart';

const _kSaveKey = 'neon_defense_save';
const _kPlayerNameKey = 'neonDefensePlayerName';

/// Save/load mirroring the JS schema exactly (03_abilities.js:264-296):
/// money, lives, wave, isWaveActive, prepTimer, spawnQueue, paths (points/
/// level/zone/mutation), towers (full per-tower fields incl. hardpoint
/// mount), baseLevel, baseCooldown, energy, playerName, totalKills,
/// pendingRiftGenerations, worldCols, worldRows.
class SaveSystem {
  final NeonDefenseGame game;
  SaveSystem(this.game);

  // JS AUTO_SAVE_RULES (05_loop.js:8-14): queued saves flush after a
  // minimum 120-frame gap, or at most 360 frames after being requested.
  static const int _minFrameGap = 120;
  static const int _maxDelayFrames = 360;
  bool _autoSavePending = false;
  int _autoSaveRequestedAt = 0;
  int _lastAutoSaveFrame = -1000000;

  void queueAutoSave() {
    if (!_autoSavePending) {
      _autoSavePending = true;
      _autoSaveRequestedAt = game.state.frameCount;
    }
  }

  /// Called once per logic frame; also with force=true on game over.
  void flushQueuedAutoSave({bool force = false}) {
    if (!_autoSavePending) return;
    final frameCount = game.state.frameCount;
    if (!force) {
      final framesSinceLast = frameCount - _lastAutoSaveFrame;
      final framesWaiting = frameCount - _autoSaveRequestedAt;
      final canSaveNow = framesSinceLast >= _minFrameGap ||
          framesWaiting >= _maxDelayFrames;
      if (!canSaveNow) return;
    }
    save();
    _lastAutoSaveFrame = frameCount;
    _autoSavePending = false;
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _pendingSnapshot;
  bool _writeScheduled = false;

  /// Snapshot state now, but defer the (potentially large) jsonEncode +
  /// SharedPreferences write off the current frame — the JS version does
  /// the same with requestIdleCallback({timeout: 5000})
  /// (03_abilities.js:285-295). Saves issued within the deferral window
  /// coalesce into one write of the most recent snapshot.
  Future<void> save() async {
    _pendingSnapshot = _buildSnapshot();
    if (_writeScheduled) return;
    _writeScheduled = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _writeScheduled = false;
    final snapshot = _pendingSnapshot;
    _pendingSnapshot = null;
    if (snapshot == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSaveKey, jsonEncode(snapshot));
  }

  Map<String, dynamic> _buildSnapshot() {
    final gw = game.gameWorld;
    final state = game.state;
    return {
      'money': state.money.value,
      'lives': state.lives.value,
      'wave': state.wave.value,
      'isWaveActive': state.isWaveActive.value,
      'prepTimer': gw.waveSystem.prepTimer,
      'spawnQueue': [
        for (final t in gw.waveSystem.spawnQueue) t.name,
      ],
      'paths': [
        for (final r in gw.waveSystem.rifts)
          {
            'points': [
              for (final p in r.points) {'x': p.x, 'y': p.y},
            ],
            'level': r.level,
            'zone': r.zone,
            'mutation': r.mutation?.toJson(),
          },
      ],
      'towers': [
        for (final t in game.entities.towers)
          {
            'type': t.type.name,
            'x': t.position.x,
            'y': t.position.y,
            'level': t.level,
            'damage': t.damage,
            'range': t.range,
            'cooldown': t.cooldown,
            'maxCooldown': t.maxCooldown,
            'cost': t.baseCost,
            'totalCost': t.totalCost,
            'hardpointId': t.hardpoint?.id,
            'hardpointType': t.hardpoint?.type.name,
            'hardpointScale': t.scaleMult,
          },
      ],
      'baseLevel': gw.coreBase.level,
      'baseCooldown': gw.coreBase.baseCooldown,
      'energy': state.energy.value,
      'playerName': state.playerName,
      'totalKills': {
        for (final entry in state.totalKills.entries)
          entry.key.name: entry.value,
      },
      'pendingRiftGenerations': 0,
      'worldCols': gw.worldCols,
      'worldRows': gw.worldRows,
    };
  }

  // ---------------------------------------------------------------------------
  // Load
  // ---------------------------------------------------------------------------

  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSaveKey);
    if (raw == null) return false;
    try {
      _applySnapshot(jsonDecode(raw) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _applySnapshot(Map<String, dynamic> data) {
    final gw = game.gameWorld;
    final state = game.state;

    state.money.value = (data['money'] as num).toDouble();
    state.lives.value = (data['lives'] as num).toInt();
    state.wave.value = (data['wave'] as num).toInt();
    state.energy.value = (data['energy'] as num? ?? 0).toDouble();
    state.playerName = data['playerName'] as String?;

    state.totalKills.clear();
    final kills = data['totalKills'] as Map<String, dynamic>? ?? {};
    for (final entry in kills.entries) {
      final type =
          EnemyType.values.where((t) => t.name == entry.key).firstOrNull;
      if (type != null) state.totalKills[type] = (entry.value as num).toInt();
    }

    // Clear transient entities + selection before restoring.
    gw.reset();
    game.selection.clear();

    // Rifts
    for (final r in (data['paths'] as List<dynamic>? ?? [])) {
      final rMap = r as Map<String, dynamic>;
      final points = (rMap['points'] as List<dynamic>).map((p) {
        final pm = p as Map<String, dynamic>;
        return Vector2(
            (pm['x'] as num).toDouble(), (pm['y'] as num).toDouble());
      }).toList();
      gw.waveSystem.rifts.add(RiftPath(
        points: points,
        level: (rMap['level'] as num?)?.toInt() ?? 1,
        zone: (rMap['zone'] as num?)?.toInt() ?? 1,
        mutation: Mutation.fromJson(rMap['mutation'] as Map<String, dynamic>?),
      ));
    }

    // Towers — restored with saved stats and hardpoint mounts.
    for (final t in (data['towers'] as List<dynamic>? ?? [])) {
      final tMap = t as Map<String, dynamic>;
      final type =
          TowerType.values.where((v) => v.name == tMap['type']).firstOrNull;
      if (type == null) continue;

      final hardpointId = tMap['hardpointId'] as String?;
      final hardpoint = hardpointId == null
          ? null
          : gw.hardpointManager.hardpoints
              .where((hp) => hp.id == hardpointId)
              .firstOrNull;
      hardpoint?.occupied = true;

      final tower = Tower(
        position: Vector2(
            (tMap['x'] as num).toDouble(), (tMap['y'] as num).toDouble()),
        type: type,
        spatialGrid: gw.spatialGrid,
        hardpoint: hardpoint,
      )
        ..level = (tMap['level'] as num?)?.toInt() ?? 1
        ..damage =
            (tMap['damage'] as num?)?.toDouble() ?? kTowers[type]!.damage
        ..range = (tMap['range'] as num?)?.toDouble() ?? kTowers[type]!.range
        ..cooldown = (tMap['cooldown'] as num?)?.toInt() ?? 0
        ..totalCost =
            (tMap['totalCost'] as num?)?.toDouble() ?? kTowers[type]!.cost;
      final savedMaxCooldown = (tMap['maxCooldown'] as num?)?.toInt();
      if (savedMaxCooldown != null) tower.maxCooldown = savedMaxCooldown;
      gw.add(tower);
    }

    // Base
    gw.coreBase.level = (data['baseLevel'] as num?)?.toInt() ?? 0;
    gw.coreBase.baseCooldown = (data['baseCooldown'] as num?)?.toInt() ?? 0;

    // Wave state — JS demotes a mid-wave load to a 5 s prep phase.
    final wasWaveActive = data['isWaveActive'] as bool? ?? false;
    state.isWaveActive.value = false;
    gw.waveSystem.isPrepPhase = true;
    gw.waveSystem.prepTimer = wasWaveActive
        ? 5.0
        : ((data['prepTimer'] as num?)?.toDouble() ?? 30.0).clamp(1.0, 30.0);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> clearSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSaveKey);
  }

  Future<bool> hasSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kSaveKey);
  }

  Future<void> savePlayerName(String name) async {
    game.state.playerName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlayerNameKey, name);
  }

  Future<String?> loadPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPlayerNameKey);
  }
}
