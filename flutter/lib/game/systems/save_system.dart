import 'dart:convert';
import 'package:flame/components.dart' show Vector2;
import 'package:shared_preferences/shared_preferences.dart';

import '../neon_defense_game.dart';
import '../systems/pathfinding/rift_generator.dart';

const _kSaveKey = 'neon_defense_save';

class SaveSystem {
  final NeonDefenseGame game;
  SaveSystem(this.game);

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSaveKey, jsonEncode(_buildSnapshot()));
  }

  Map<String, dynamic> _buildSnapshot() {
    final gw = game.gameWorld;
    return {
      'money': game.money,
      'lives': game.lives,
      'energy': game.energy,
      'wave': game.wave,
      'isWaveActive': game.isWaveActive,
      'rifts': gw.waveSystem.rifts
          .map((r) => {
                'level': r.level,
                'mutationKey': r.mutationKey,
                'points': r.points
                    .map((p) => {'x': p.x, 'y': p.y})
                    .toList(),
              })
          .toList(),
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
    game.money = (data['money'] as num).toDouble();
    game.lives = data['lives'] as int;
    game.energy = (data['energy'] as num).toDouble();
    game.wave = data['wave'] as int;
    game.isWaveActive = data['isWaveActive'] as bool? ?? false;

    final gw = game.gameWorld;
    gw.waveSystem.rifts.clear();

    for (final r in (data['rifts'] as List<dynamic>? ?? [])) {
      final rMap = r as Map<String, dynamic>;
      final points = (rMap['points'] as List<dynamic>)
          .map((p) {
            final pm = p as Map<String, dynamic>;
            return Vector2(
              (pm['x'] as num).toDouble(),
              (pm['y'] as num).toDouble(),
            );
          })
          .toList();

      gw.waveSystem.rifts.add(RiftPath(
        points: points,
        level: rMap['level'] as int? ?? 1,
        mutationKey: rMap['mutationKey'] as String?,
      ));
    }
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
}
