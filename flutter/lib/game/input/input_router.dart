import 'package:flame/components.dart';

import '../neon_defense_game.dart';
import '../entities/towers/tower.dart';

/// All world taps resolve here, in one place, mirroring the JS
/// handleClick() priority order (01_init.js:280-432):
///   1. ability targeting consumes the tap
///   2. tower hit (< 20 world units) selects the tower
///   3. build placement (selected tower type)
///   4. otherwise deselect everything
/// Rift-spawn and base hits slot in between 2 and 3 in Phase A2.
class InputRouter {
  final NeonDefenseGame game;

  /// JS tower hit radius (01_init.js: dist < 20).
  static const double towerHitRadius = 20.0;

  InputRouter(this.game);

  void handleTap(Vector2 worldPos) {
    if (!game.state.isPlaying) return;

    final ability = game.gameWorld.abilitySystem;
    if (ability.isTargeting) {
      ability.useAbility(worldPos);
      return;
    }

    final tower = _towerAt(worldPos);
    if (tower != null) {
      game.selection.selectTower(tower);
      return;
    }

    if (game.selection.selectedTowerType != null) {
      game.gameWorld.placeTower(worldPos);
      return;
    }

    game.selection.clear();
  }

  Tower? _towerAt(Vector2 worldPos) {
    Tower? hit;
    var best = towerHitRadius;
    for (final tower in game.entities.towers) {
      final d = tower.position.distanceTo(worldPos);
      if (d < best) {
        best = d;
        hit = tower;
      }
    }
    return hit;
  }
}
