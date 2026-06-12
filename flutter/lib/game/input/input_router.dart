import 'package:flame/components.dart';

import '../neon_defense_game.dart';
import '../entities/towers/tower.dart';
import '../systems/pathfinding/rift_generator.dart';
import '../systems/placement_system.dart';

/// All world taps resolve here, in one place, mirroring the JS
/// handleClick() priority order (01_init.js:280-432):
///   1. ability targeting consumes the tap
///   2. tower hit (< 20 world units) selects the tower
///   3. rift spawn hit (< 30) selects the rift
///   4. base hit (< 30) selects the base
///   5. free tile -> build target (tapping the same target deselects)
///   6. otherwise deselect everything
class InputRouter {
  final NeonDefenseGame game;

  /// JS hit radii (01_init.js).
  static const double towerHitRadius = 20.0;
  static const double riftHitRadius = 30.0;
  static const double baseHitRadius = 30.0;

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
      game.hints.maybeShowTowerHint();
      return;
    }

    final rift = _riftAt(worldPos);
    if (rift != null) {
      game.selection.selectRift(rift);
      game.hints.maybeShowRiftHint();
      return;
    }

    if (game.gameWorld.coreBase.position.distanceTo(worldPos) <
        baseHitRadius) {
      game.selection.selectBase();
      return;
    }

    final snap = PlacementSystem.snapToGrid(worldPos);
    if (game.placement.isTileFree(snap)) {
      // Toggle behavior: tapping the selected empty tile deselects it.
      final current = game.selection.buildTarget;
      if (current != null &&
          current.x == snap.x &&
          current.y == snap.y) {
        game.selection.clear();
        return;
      }
      game.selection.selectBuildTarget(snap);
      game.tutorial.onBuildTargetSelected();
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

  RiftPath? _riftAt(Vector2 worldPos) {
    for (final rift in game.gameWorld.waveSystem.rifts) {
      if (rift.points.isEmpty) continue;
      if (rift.points.first.distanceTo(worldPos) < riftHitRadius) {
        return rift;
      }
    }
    return null;
  }
}
